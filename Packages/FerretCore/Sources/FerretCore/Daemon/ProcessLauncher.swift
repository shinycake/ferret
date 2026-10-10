import Foundation

public protocol LaunchedProcess: AnyObject, Sendable {
    var pid: Int32 { get }
    var isRunning: Bool { get }
    func onExit(_ handler: @escaping @Sendable (Int32) -> Void)
    func terminate()
    func kill()
}

public protocol ProcessLauncher: Sendable {
    func launch(executable: URL, args: [String], env: [String: String], log: URL) throws -> LaunchedProcess
}

/// `Process`-backed launcher. The child is not detached, so TCC treats Ferret as responsible.
public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}

    public func launch(executable: URL, args: [String], env: [String: String], log: URL) throws -> LaunchedProcess {
        let fm = FileManager.default
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        LogRotation.rotateIfNeeded(log)
        if !fm.fileExists(atPath: log.path) {
            fm.createFile(atPath: log.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = env
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        let wrapper = SystemLaunchedProcess(process: process)
        process.terminationHandler = { p in
            try? handle.close()
            wrapper.fireExit(p.terminationStatus)
        }
        try process.run()
        return wrapper
    }
}

final class SystemLaunchedProcess: LaunchedProcess, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var handlers: [@Sendable (Int32) -> Void] = []
    private var exitCode: Int32?

    init(process: Process) {
        self.process = process
    }

    var pid: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if let code = exitCode {
            lock.unlock()
            handler(code)
            return
        }
        handlers.append(handler)
        lock.unlock()
    }

    func fireExit(_ code: Int32) {
        lock.lock()
        exitCode = code
        let pending = handlers
        handlers = []
        lock.unlock()
        pending.forEach { $0(code) }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func kill() {
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}

public struct SocketTransportFactory: FSearchTransportFactory {
    public let path: String
    public init(path: String) { self.path = path }
    public func makeTransport(lane: FSearchClient.Lane) -> any FSearchTransport {
        SocketTransport(path: path)
    }
}

public struct StdioTransportFactory: FSearchTransportFactory {
    public let binary: URL
    public let env: [String: String]
    public init(binary: URL, env: [String: String]) {
        self.binary = binary
        self.env = env
    }
    public func makeTransport(lane: FSearchClient.Lane) -> any FSearchTransport {
        StdioTransport(binary: binary, env: env)
    }
}
