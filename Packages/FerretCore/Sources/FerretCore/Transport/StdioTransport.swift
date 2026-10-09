import Darwin
import Foundation
import os

public final class StdioTransport: FSearchTransport, @unchecked Sendable {
    private let binary: URL
    private let environment: [String: String]
    private let writeQueue = DispatchQueue(label: "com.shinycake.ferret.stdio.write")
    private let lock = NSLock()
    private var process: Process?
    private var pipes: [Pipe] = []
    private var stdinFD: Int32 = -1
    private var stdoutFD: Int32 = -1
    private var stderrFD: Int32 = -1
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
        let fd = currentStdin()
        guard fd >= 0 else { throw FSearchError.notConnected }
        var payload = line
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                OffMain.precondition()
                do {
                    try Self.writeAll(fd: fd, data: payload)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() {
        let fds = takeFDs()
        for fd in fds where fd >= 0 {
            Darwin.close(fd)
        }
        lock.lock()
        let process = self.process
        self.process = nil
        pipes = []
        lock.unlock()
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

        let stdinFD = dup(stdinPipe.fileHandleForWriting.fileDescriptor)
        let stdoutFD = dup(stdoutPipe.fileHandleForReading.fileDescriptor)
        let stderrFD = dup(stderrPipe.fileHandleForReading.fileDescriptor)
        guard stdinFD >= 0, stdoutFD >= 0, stderrFD >= 0 else {
            for fd in [stdinFD, stdoutFD, stderrFD] where fd >= 0 {
                Darwin.close(fd)
            }
            process.terminate()
            throw FSearchError.daemonFailedToStart("dup failed")
        }
        configure(stdinFD, ignoreSigPipe: true)
        configure(stdoutFD, ignoreSigPipe: false)
        configure(stderrFD, ignoreSigPipe: false)

        // Close the parent's original ends so only the dup'd descriptors are used.
        // FileHandle reads and writes hop through the main queue and hang under XCTest.
        try? stdinPipe.fileHandleForReading.close()
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForWriting.close()

        lock.lock()
        self.process = process
        self.pipes = [stdinPipe, stdoutPipe, stderrPipe]
        self.stdinFD = stdinFD
        self.stdoutFD = stdoutFD
        self.stderrFD = stderrFD
        lock.unlock()

        let reader = Thread { [weak self] in
            self?.readLoop(fd: stdoutFD)
        }
        reader.name = "com.shinycake.ferret.stdio.read"
        reader.start()
        let errors = Thread { [weak self] in
            self?.drainStderr(fd: stderrFD)
        }
        errors.name = "com.shinycake.ferret.stdio.stderr"
        errors.start()
    }

    private func configure(_ fd: Int32, ignoreSigPipe: Bool) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        if ignoreSigPipe {
            _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        }
    }

    private func readLoop(fd: Int32) {
        OffMain.precondition()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var lines = LineBuffer()
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count == 0 {
                finish(nil)
                return
            }
            if count < 0 {
                if errno == EINTR { continue }
                finish(FSearchError.transportClosed)
                return
            }
            for line in lines.append(Data(buffer.prefix(count))) {
                continuation.yield(line)
            }
        }
    }

    private func drainStderr(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count <= 0 { return }
            let data = Data(buffer.prefix(count))
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                stderrLog.debug("\(text, privacy: .public)")
            }
        }
    }

    private func currentStdin() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return stdinFD
    }

    private func takeFDs() -> [Int32] {
        lock.lock()
        defer { lock.unlock() }
        let fds = [stdinFD, stdoutFD, stderrFD]
        stdinFD = -1
        stdoutFD = -1
        stderrFD = -1
        return fds
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

    private static func writeAll(fd: Int32, data: Data) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw FSearchError.transportClosed
            }
            if written == 0 {
                throw FSearchError.transportClosed
            }
            offset += written
        }
    }
}
