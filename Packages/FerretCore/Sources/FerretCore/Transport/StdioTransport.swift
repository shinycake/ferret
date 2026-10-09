import Foundation
import os

public final class StdioTransport: FSearchTransport, @unchecked Sendable {
    private let binary: URL
    private let environment: [String: String]
    private let writeQueue = DispatchQueue(label: "com.shinycake.ferret.stdio.write")
    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var finished = false
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    public let lines: AsyncThrowingStream<Data, Error>
    private let stderrLog = Logger(subsystem: "com.shinycake.ferret", category: "stdio")

    public init(binary: URL, env: [String: String]) {
        self.binary = binary
        self.environment = env
        var captured: AsyncThrowingStream<Data, Error>.Continuation!
        self.lines = AsyncThrowingStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.continuation = captured
    }

    deinit {
        close()
    }

    public func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.launch()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func send(line: Data) async throws {
        lock.lock()
        let handle = stdinHandle
        lock.unlock()
        guard let handle else { throw FSearchError.notConnected }
        var payload = line
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                OffMain.precondition()
                do {
                    try handle.write(contentsOf: payload)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: FSearchError.transportClosed)
                }
            }
        }
    }

    public func close() {
        lock.lock()
        let handle = stdinHandle
        let process = self.process
        stdinHandle = nil
        self.process = nil
        lock.unlock()
        try? handle?.close()
        if let process, process.isRunning {
            process.terminate()
        }
        finish(nil)
    }

    private func launch() throws {
        OffMain.precondition()
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw FSearchError.binaryMissing
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["stdio"]
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in self.environment {
            environment[key] = value
        }
        process.environment = environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw FSearchError.daemonFailedToStart(String(describing: error))
        }
        lock.lock()
        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        lock.unlock()
        let stdout = stdoutPipe.fileHandleForReading
        let stderr = stderrPipe.fileHandleForReading
        Thread { [weak self] in
            self?.readStdout(stdout)
        }.start()
        Thread { [weak self] in
            self?.drainStderr(stderr)
        }.start()
    }

    private func readStdout(_ handle: FileHandle) {
        OffMain.precondition()
        var lines = LineBuffer()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty {
                finish(nil)
                return
            }
            for line in lines.append(chunk) {
                continuation.yield(line)
            }
        }
    }

    private func drainStderr(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { return }
            if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                stderrLog.debug("\(text, privacy: .public)")
            }
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
