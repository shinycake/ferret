import Darwin
import Foundation
import os

/// Owns the fsearch daemon lifecycle (SPEC §5): probe, spawn, stdio fallback, readiness polling,
/// crash restart with backoff, reindex, and shutdown. Never signals a daemon it did not spawn.
public actor DaemonManager {
    public enum Mode: Equatable, Sendable {
        case ownedChild(pid: Int32)
        case external(pid: Int32?, executable: String?)
        case stdioFallback
        case stopped
    }

    public enum Health: Equatable, Sendable {
        case starting
        case indexing(DaemonStatus?)
        case ready(DaemonStatus)
        case failed(FSearchError)
    }

    public struct Timing: Sendable {
        public var pingPoll: Duration = .milliseconds(30)
        public var spawnTimeout: Duration = .seconds(3)
        public var statusInterval: Duration = .seconds(1)
        public var healthInterval: Duration = .seconds(10)
        public var backoff: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
        public var giveUpExits = 5
        public var giveUpWindow: TimeInterval = 60
        public var saveGrace: Duration = .milliseconds(300)
        public var killGrace: Duration = .seconds(3)
        public init() {}
    }

    public let paths: FerretPaths
    public let binary: URL
    private let launcher: ProcessLauncher
    private let makeClient: @Sendable (any FSearchTransportFactory) -> FSearchClient
    private let timing: Timing
    private let log = Logger(subsystem: "com.shinycake.ferret", category: "DaemonManager")

    public private(set) var mode: Mode = .stopped
    public private(set) var client: FSearchClient?
    public private(set) var currentHealth: Health = .starting

    private var child: LaunchedProcess?
    private var monitor: Task<Void, Never>?
    private var stopping = false
    private var exitTimes: [Date] = []
    private var generation = 0

    public nonisolated let health: AsyncStream<Health>
    private let healthContinuation: AsyncStream<Health>.Continuation

    public init(
        paths: FerretPaths,
        binary: URL,
        launcher: ProcessLauncher = SystemProcessLauncher(),
        timing: Timing = Timing(),
        makeClient: @escaping @Sendable (any FSearchTransportFactory) -> FSearchClient = { FSearchClient(factory: $0) }
    ) {
        self.paths = paths
        self.binary = binary
        self.launcher = launcher
        self.timing = timing
        self.makeClient = makeClient
        var continuation: AsyncStream<Health>.Continuation!
        health = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation = $0 }
        healthContinuation = continuation
        continuation.yield(.starting)
    }

    public var isExternal: Bool {
        if case .external = mode { return true }
        return false
    }

    // MARK: start

    @discardableResult
    public func start() async -> Health {
        stopping = false
        generation += 1
        let gen = generation
        monitor?.cancel()
        monitor = nil
        emit(.starting)

        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            return emit(.failed(.binaryMissing))
        }

        if let probed = await probeSocket() {
            adopt(probed)
        } else if paths.socket.path.utf8.count >= 104 {
            guard await useStdio() else { return emit(.failed(.socketPathTooLong)) }
        } else {
            var attached = false
            do {
                attached = try await spawnAndAttach()
            } catch {
                log.error("spawn failed: \(String(describing: error), privacy: .public)")
            }
            if !attached, !(await useStdio()) {
                return emit(.failed(.daemonFailedToStart(LogRotation.tail(paths.daemonLog))))
            }
        }
        guard gen == generation else { return currentHealth }
        let first = await pollStatusOnce()
        startMonitor(gen: gen)
        return first
    }

    @discardableResult
    public func restart() async -> Health {
        if isExternal { return currentHealth }
        await stop()
        return await start()
    }

    /// SPEC §5.4: owned daemons only; deletes `index.bin` and `content/` and nothing else.
    public func reindex() async throws {
        if isExternal { throw FSearchError.externalDaemon }
        await stop()
        let fm = FileManager.default
        try? fm.removeItem(at: paths.fsearchDir.appendingPathComponent("index.bin"))
        try? fm.removeItem(at: paths.fsearchDir.appendingPathComponent("content", isDirectory: true))
        _ = await start()
    }

    public func stop() async {
        stopping = true
        generation += 1
        monitor?.cancel()
        monitor = nil
        if case .ownedChild = mode, let child, let client {
            _ = await withTimeout(timing.saveGrace) { try await client.save() }
            child.terminate()
            let deadline = ContinuousClock.now + timing.killGrace
            while child.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if child.isRunning { child.kill() }
        }
        // External daemons are never signalled.
        await client?.close()
        client = nil
        child = nil
        mode = .stopped
    }

    // MARK: internals

    private struct Probed {
        let client: FSearchClient
    }

    private func probeSocket() async -> Probed? {
        guard paths.socket.path.utf8.count < 104,
              FileManager.default.fileExists(atPath: paths.socket.path) else { return nil }
        let candidate = makeClient(SocketTransportFactory(path: paths.socket.path))
        do {
            try await candidate.ping()
            return Probed(client: candidate)
        } catch {
            await candidate.close()
            return nil
        }
    }

    private func adopt(_ probed: Probed) {
        client = probed.client
        let lockPID = paths.socketLockPID()
        if let child, child.isRunning, lockPID == nil || lockPID == child.pid {
            mode = .ownedChild(pid: child.pid)
        } else {
            mode = .external(pid: lockPID, executable: lockPID.flatMap(Self.executablePath))
        }
        log.info("attached mode=\(String(describing: self.mode), privacy: .public)")
    }

    private func spawnAndAttach() async throws -> Bool {
        for attempt in 0..<2 {
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = paths.home.path
            let process = try launcher.launch(executable: binary, args: ["serve"], env: env, log: paths.daemonLog)
            child = process
            let gen = generation
            process.onExit { [weak self] code in
                Task { await self?.childExited(process: process, code: code, gen: gen) }
            }
            let deadline = ContinuousClock.now + timing.spawnTimeout
            while ContinuousClock.now < deadline {
                if let probed = await probeSocket() {
                    adopt(probed)
                    return true
                }
                if !process.isRunning { break }
                try? await Task.sleep(for: timing.pingPoll)
            }
            if process.isRunning { return false }
            // The child lost the socket.lock race; re-probe once (SPEC §5.1 step 3).
            child = nil
            if let probed = await probeSocket() {
                adopt(probed)
                return true
            }
            if attempt == 1 { break }
        }
        return false
    }

    private func useStdio() async -> Bool {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = paths.home.path
        let candidate = makeClient(StdioTransportFactory(binary: binary, env: env))
        do {
            try await candidate.ping()
        } catch {
            await candidate.close()
            return false
        }
        client = candidate
        mode = .stdioFallback
        log.info("using stdio fallback")
        return true
    }

    private func childExited(process: LaunchedProcess, code: Int32, gen: Int) async {
        guard !stopping, let current = child, current === process else { return }
        child = nil
        await client?.close()
        client = nil
        mode = .stopped
        let now = Date()
        exitTimes.append(now)
        exitTimes = exitTimes.filter { now.timeIntervalSince($0) <= timing.giveUpWindow }
        log.error("daemon exited code=\(code) recent=\(self.exitTimes.count)")
        if exitTimes.count >= timing.giveUpExits {
            monitor?.cancel()
            emit(.failed(.daemonFailedToStart(LogRotation.tail(paths.daemonLog))))
            return
        }
        let index = min(exitTimes.count - 1, timing.backoff.count - 1)
        let delay = timing.backoff.isEmpty ? .zero : timing.backoff[max(index, 0)]
        emit(.starting)
        try? await Task.sleep(for: delay)
        guard !stopping else { return }
        _ = await start()
    }

    @discardableResult
    private func pollStatusOnce() async -> Health {
        guard let client else { return emit(.failed(.notConnected)) }
        do {
            let status = try await client.status()
            return emit(.ready(status))
        } catch FSearchError.indexing {
            return emit(.indexing(nil))
        } catch let error as FSearchError {
            return emit(.failed(error))
        } catch {
            return emit(.failed(.server(String(describing: error))))
        }
    }

    private func startMonitor(gen: Int) {
        monitor = Task { [weak self] in
            var pingFailures = 0
            while !Task.isCancelled {
                guard let self else { return }
                let health = await self.currentHealth
                let busy: Bool
                switch health {
                case .indexing: busy = true
                case .ready(let s): busy = (s.contentPending ?? 0) > 0
                default: busy = false
                }
                let interval = busy ? self.timing.statusInterval : self.timing.healthInterval
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                guard await self.generation == gen else { return }
                if busy {
                    await self.pollStatusOnce()
                    continue
                }
                if await self.pingOK() {
                    pingFailures = 0
                } else {
                    pingFailures += 1
                    if pingFailures >= 2 {
                        await self.reconnectAfterPingFailures(gen: gen)
                        return
                    }
                }
            }
        }
    }

    private func pingOK() async -> Bool {
        guard let client else { return false }
        do {
            try await client.ping()
            return true
        } catch {
            return false
        }
    }

    private func reconnectAfterPingFailures(gen: Int) async {
        guard gen == generation, !stopping else { return }
        await client?.close()
        client = nil
        _ = await start()
    }

    @discardableResult
    private func emit(_ health: Health) -> Health {
        currentHealth = health
        healthContinuation.yield(health)
        return health
    }

    private func withTimeout(_ limit: Duration, _ body: @escaping @Sendable () async throws -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await body()) != nil }
            group.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
