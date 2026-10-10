import Darwin
import Foundation
import XCTest
@testable import FerretCore

/// Fake child: launching starts a FakeFSearchServer on the real socket path and writes socket.lock.
final class FakeLauncher: ProcessLauncher, @unchecked Sendable {
    enum Behavior { case serve, exitImmediately }
    let paths: FerretPaths
    var behavior: Behavior
    private let lock = NSLock()
    private(set) var launched: [FakeProcess] = []

    init(paths: FerretPaths, behavior: Behavior = .serve) {
        self.paths = paths
        self.behavior = behavior
    }

    var launchCount: Int { lock.lock(); defer { lock.unlock() }; return launched.count }

    func launch(executable: URL, args: [String], env: [String: String], log: URL) throws -> LaunchedProcess {
        XCTAssertEqual(args, ["serve"])
        XCTAssertEqual(env["HOME"], paths.home.path)
        lock.lock()
        let pid = Int32(50_000 + launched.count)
        let process = FakeProcess(pid: pid)
        launched.append(process)
        lock.unlock()
        switch behavior {
        case .serve:
            try FileManager.default.createDirectory(at: paths.fsearchDir, withIntermediateDirectories: true)
            process.server = try FakeFSearchServer(path: paths.socket.path)
            try "\(pid)\n".write(to: paths.socketLock, atomically: true, encoding: .utf8)
        case .exitImmediately:
            process.exit(code: 1)
        }
        return process
    }
}

final class FakeProcess: LaunchedProcess, @unchecked Sendable {
    let pid: Int32
    var server: FakeFSearchServer?
    private let lock = NSLock()
    private var running = true
    private var handlers: [@Sendable (Int32) -> Void] = []
    private(set) var terminated = 0
    private(set) var killed = 0

    init(pid: Int32) { self.pid = pid }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        if !running { lock.unlock(); handler(1); return }
        handlers.append(handler)
        lock.unlock()
    }

    func exit(code: Int32) {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        let pending = handlers
        handlers = []
        lock.unlock()
        server?.stop()
        server = nil
        pending.forEach { $0(code) }
    }

    func terminate() { terminated += 1; exit(code: 15) }
    func kill() { killed += 1; exit(code: 9) }
}

final class DaemonManagerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        // Short path: sun_path is limited to 104 bytes.
        home = URL(fileURLWithPath: "/tmp/fd-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var fastTiming: DaemonManager.Timing {
        var t = DaemonManager.Timing()
        t.spawnTimeout = .milliseconds(800)
        t.statusInterval = .milliseconds(50)
        t.healthInterval = .milliseconds(100)
        t.backoff = [.milliseconds(10)]
        t.giveUpWindow = 60
        t.killGrace = .milliseconds(200)
        return t
    }

    private func executableBinary() throws -> URL {
        let url = home.appendingPathComponent("fsearch")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url
    }

    func testMissingBinaryFails() async {
        let paths = FerretPaths(home: home)
        let manager = DaemonManager(paths: paths, binary: home.appendingPathComponent("nope"), launcher: FakeLauncher(paths: paths), timing: fastTiming)
        let health = await manager.start()
        XCTAssertEqual(health, .failed(.binaryMissing))
    }

    func testSpawnsOwnedChildAndBecomesReady() async throws {
        let paths = FerretPaths(home: home)
        let launcher = FakeLauncher(paths: paths)
        let manager = DaemonManager(paths: paths, binary: try executableBinary(), launcher: launcher, timing: fastTiming)
        let health = await manager.start()
        guard case .ready(let status) = health else { return XCTFail("health \(health)") }
        XCTAssertEqual(status.entries, 3)
        XCTAssertEqual(launcher.launchCount, 1)
        let mode = await manager.mode
        XCTAssertEqual(mode, .ownedChild(pid: 50_000))
        await manager.stop()
        XCTAssertEqual(launcher.launched[0].terminated, 1)
        let stopped = await manager.mode
        XCTAssertEqual(stopped, .stopped)
    }

    func testAdoptsExternalDaemonAndNeverSignalsIt() async throws {
        let paths = FerretPaths(home: home)
        try FileManager.default.createDirectory(at: paths.fsearchDir, withIntermediateDirectories: true)
        let server = try FakeFSearchServer(path: paths.socket.path)
        defer { server.stop() }
        try "4242\n".write(to: paths.socketLock, atomically: true, encoding: .utf8)
        let launcher = FakeLauncher(paths: paths)
        let manager = DaemonManager(paths: paths, binary: try executableBinary(), launcher: launcher, timing: fastTiming)
        let health = await manager.start()
        guard case .ready = health else { return XCTFail("health \(health)") }
        let mode = await manager.mode
        guard case .external(let pid, _) = mode else { return XCTFail("mode \(mode)") }
        XCTAssertEqual(pid, 4242)
        XCTAssertEqual(launcher.launchCount, 0)
        await manager.stop()
        XCTAssertEqual(launcher.launchCount, 0)
        // The external server still answers after stop().
        let probe = FSearchClient(factory: SocketTransportFactory(path: paths.socket.path))
        try await probe.ping()
        await probe.close()
        do {
            let external = DaemonManager(paths: paths, binary: try executableBinary(), launcher: launcher, timing: fastTiming)
            _ = await external.start()
            try await external.reindex()
            XCTFail("reindex should refuse in external mode")
        } catch let error as FSearchError {
            XCTAssertEqual(error, .externalDaemon)
        }
    }

    func testCrashRestartsWithBackoffThenGivesUp() async throws {
        let paths = FerretPaths(home: home)
        let launcher = FakeLauncher(paths: paths)
        var timing = fastTiming
        timing.giveUpExits = 3
        let manager = DaemonManager(paths: paths, binary: try executableBinary(), launcher: launcher, timing: timing)
        _ = await manager.start()
        XCTAssertEqual(launcher.launchCount, 1)
        for round in 1...2 {
            launcher.launched.last!.exit(code: 1)
            try await waitUntil { launcher.launchCount == round + 1 }
            try await waitUntil { if case .ready = await manager.currentHealth { return true }; return false }
        }
        launcher.launched.last!.exit(code: 1)
        try await waitUntil {
            if case .failed(.daemonFailedToStart) = await manager.currentHealth { return true }
            return false
        }
        XCTAssertEqual(launcher.launchCount, 3)
    }

    func testStdioFallbackWhenSpawnNeverServes() async throws {
        let paths = FerretPaths(home: home)
        let launcher = FakeLauncher(paths: paths, behavior: .exitImmediately)
        let script = home.appendingPathComponent("fake_fsearch.py")
        try Self.fakeStdio.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        let manager = DaemonManager(paths: paths, binary: script, launcher: launcher, timing: fastTiming)
        let health = await manager.start()
        guard case .ready(let status) = health else { return XCTFail("health \(health)") }
        XCTAssertEqual(status.entries, 4)
        let mode = await manager.mode
        XCTAssertEqual(mode, .stdioFallback)
        await manager.stop()
    }

    func testReindexDeletesOnlyIndexFiles() async throws {
        let paths = FerretPaths(home: home)
        let launcher = FakeLauncher(paths: paths)
        let manager = DaemonManager(paths: paths, binary: try executableBinary(), launcher: launcher, timing: fastTiming)
        _ = await manager.start()
        let fm = FileManager.default
        let dir = paths.fsearchDir
        try Data("x".utf8).write(to: dir.appendingPathComponent("index.bin"))
        try fm.createDirectory(at: dir.appendingPathComponent("content"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("content/seg0"))
        try Data("keep".utf8).write(to: dir.appendingPathComponent("daemon.log"))
        try await manager.reindex()
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("index.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("content").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("daemon.log").path))
        XCTAssertEqual(launcher.launchCount, 2)
        XCTAssertEqual(launcher.launched[0].terminated, 1)
        await manager.stop()
    }

    func testLogRotationKeepsOneBackup() throws {
        let paths = FerretPaths(home: home)
        try FileManager.default.createDirectory(at: paths.logDir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 5 * 1024 * 1024 + 10).write(to: paths.daemonLog)
        let process = try SystemProcessLauncher().launch(executable: URL(fileURLWithPath: "/bin/echo"), args: ["hello-log"], env: [:], log: paths.daemonLog)
        let done = expectation(description: "exit")
        process.onExit { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        let listing = try FileManager.default.contentsOfDirectory(atPath: paths.logDir.path).sorted()
        let sizes = listing.map { name -> String in
            let size = (try? FileManager.default.attributesOfItem(atPath: paths.logDir.appendingPathComponent(name).path)[.size] as? NSNumber)?.intValue ?? -1
            return "\(name) \(size)"
        }
        print("LOG_ROTATION_LISTING: \(sizes.joined(separator: ", "))")
        XCTAssertEqual(listing, ["fsearch.log", "fsearch.log.1"])
        XCTAssertTrue(try String(contentsOf: paths.daemonLog, encoding: .utf8).contains("hello-log"))
    }

    func testFerretHomeOverride() {
        let paths = FerretPaths.current(environment: ["FERRET_HOME": "/tmp/x"])
        XCTAssertEqual(paths.socket.path, "/tmp/x/Library/Application Support/FSearch/fsearch.sock")
        XCTAssertEqual(paths.logDir.path, "/tmp/x/Library/Logs/Ferret")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("condition not met in \(timeout)s")
        throw CancellationError()
    }

    static let fakeStdio = """
    #!/usr/bin/env python3
    import json, sys
    if len(sys.argv) < 2 or sys.argv[1] != "stdio":
        sys.exit(2)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        req = json.loads(line)
        rid = req.get("id")
        op = req.get("op", "search")
        if op == "status":
            out = {"ok": True, "entries": 4, "dirs": 1, "content_pending": 0, "full_disk_access": False, "owner": True}
        elif op == "ping":
            out = {"ok": True}
        elif op == "save":
            out = {"ok": True, "scheduled": True}
        else:
            out = {"ok": True, "took_us": 5, "hits": [{"path": "/tmp/" + req.get("q", ""), "kind": "file"}]}
        out["id"] = rid
        sys.stdout.write(json.dumps(out) + "\\n")
        sys.stdout.flush()
    """
}
