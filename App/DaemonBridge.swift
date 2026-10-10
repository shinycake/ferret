import AppKit
import FerretCore

/// Connects FerretCore's `DaemonManager` to the app: menu status line, panel backend and footer,
/// onboarding health, Settings reindex, and FDA restart.
@MainActor
final class DaemonBridge {
    static weak var shared: DaemonBridge?

    let health: AsyncStream<ShellHealth>
    private let continuation: AsyncStream<ShellHealth>.Continuation
    let manager: FerretCore.DaemonManager?
    private weak var panel: PanelController?
    private(set) var latest: FerretCore.DaemonManager.Health = .starting
    private(set) var modeSummary = "not connected"
    private var started = false
    private var stopped = false

    init(panel: PanelController?, binary: URL? = Bundle.main.url(forAuxiliaryExecutable: "fsearch")) {
        var continuation: AsyncStream<ShellHealth>.Continuation!
        health = AsyncStream { continuation = $0 }
        self.continuation = continuation
        self.panel = panel
        if let binary {
            manager = FerretCore.DaemonManager(paths: .current(), binary: binary)
        } else {
            manager = nil
        }
        continuation.yield(.starting)
        DaemonBridge.shared = self
    }

    func start() {
        guard !started else { return }
        started = true
        logLine("ferret: DaemonManager.start")
        guard let manager else {
            continuation.yield(.failed("fsearch binary missing"))
            return
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Hosted app tests: don't start a whole-disk crawl on the CI runner.
            return
        }
        Task { @MainActor [weak self] in
            for await event in manager.health {
                await self?.apply(event)
            }
        }
        Task { _ = await manager.start() }
    }

    func stop() {
        guard !stopped, let manager else { return }
        stopped = true
        logLine("ferret: DaemonManager.stop")
        // Best effort at quit: save, SIGTERM the owned child. Bounded by the manager's own timeouts.
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await manager.stop()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 4)
    }

    func restart() {
        guard let manager else { return }
        Task { _ = await manager.restart() }
    }

    func reindex() {
        guard let manager else { return }
        Task { @MainActor in
            do {
                try await manager.reindex()
            } catch FSearchError.externalDaemon {
                let alert = NSAlert()
                alert.messageText = "fsearch is running outside Ferret"
                alert.informativeText = "Stop that daemon first (for example `fsearch uninstall`); its LaunchAgent would respawn it anyway."
                alert.runModal()
            } catch {
                logLine("ferret: reindex failed \(error)")
            }
        }
    }

    var onboardingHealth: OnboardingModel.Health {
        let phase: OnboardingModel.Phase
        var externalWithoutFDA = false
        switch latest {
        case .starting, .indexing:
            phase = .scanning
        case .ready(let s):
            phase = .ready(items: s.entries ?? 0, folders: s.dirs ?? 0, contentPending: s.contentPending ?? 0)
            if modeSummary.hasPrefix("external"), s.fullDiskAccess == false, FullDiskAccess.isGranted() {
                externalWithoutFDA = true
            }
        case .failed(let e):
            phase = .failed(Self.describe(e))
        }
        return OnboardingModel.Health(phase: phase, externalWithoutFDA: externalWithoutFDA)
    }

    private func apply(_ event: FerretCore.DaemonManager.Health) async {
        latest = event
        if let manager {
            let mode = await manager.mode
            switch mode {
            case .ownedChild(let pid): modeSummary = "owned (pid \(pid))"
            case .external(let pid, _): modeSummary = "external fsearch daemon\(pid.map { " (pid \($0))" } ?? "") — version may differ"
            case .stdioFallback: modeSummary = "stdio fallback"
            case .stopped: modeSummary = "stopped"
            }
            if case .ready = event, let client = await manager.client {
                panel?.coordinator.backend = client
            }
        }
        let shell: ShellHealth
        switch event {
        case .starting:
            shell = .starting
        case .indexing:
            shell = .indexing(nil)
        case .ready(let s):
            shell = .ready(Self.summary(s))
        case .failed(let e):
            shell = .failed(Self.describe(e))
        }
        panel?.setFooterStatus(shell.menuTitle)
        continuation.yield(shell)
    }

    static func summary(_ s: DaemonStatus) -> String {
        let count = s.entries ?? 0
        let items: String
        if count >= 1_000_000 {
            items = String(format: "%.1fM items", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            items = String(format: "%.0fK items", Double(count) / 1_000)
        } else {
            items = "\(count) items"
        }
        let fda = s.fullDiskAccess == true ? "FDA ✓" : "Limited: no Full Disk Access"
        return "\(items) · \(fda)"
    }

    static func describe(_ e: FSearchError) -> String {
        switch e {
        case .binaryMissing: return "fsearch binary missing"
        case .daemonFailedToStart: return "Search engine failed to start"
        case .externalDaemon: return "External fsearch daemon"
        case .socketPathTooLong: return "Socket path too long"
        default: return "Search engine unavailable"
        }
    }
}
