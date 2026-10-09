import AppKit
import FinderSync
import ServiceManagement
import SwiftUI
import FerretCore

@MainActor
enum OnboardingPresenter {
    private static var window: NSWindow?
    private static var delegate: CloseDelegate?

    static func showLive() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let model = liveModel()
        model.startPolling()
        let window = makeWindow(model: model, completesOnClose: true)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func liveModel() -> OnboardingModel {
        OnboardingModel(
            isFullDiskAccessGranted: { FullDiskAccess.isGranted() },
            health: {
                OnboardingModel.Health(phase: .failed("Search engine not connected"), externalWithoutFDA: false)
            },
            isExtensionEnabled: { FIFinderSyncController.isExtensionEnabled },
            loginState: { loginState() },
            restartDaemon: restartSearchDaemon,
            applyLaunchAtLogin: { applyLogin($0) },
            openPrivacySettings: { NSWorkspace.shared.open(FullDiskAccess.settingsURL) },
            openExtensionManagement: { FIFinderSyncController.showExtensionManagementInterface() },
            openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }

    /// Hook for `DaemonManager.restart()` once that actor is linked into the app.
    static func restartSearchDaemon() {}

    private static func loginState() -> OnboardingModel.Login {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .off
        @unknown default:
            return .off
        }
    }

    private static func applyLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logLine("ferret: login item \(error.localizedDescription)")
        }
    }

    static func makeWindow(model: OnboardingModel, completesOnClose: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, onClose: {
            if completesOnClose {
                model.markCompleted()
            }
            model.stopPolling()
            window.close()
        }))
        window.setContentSize(NSSize(width: 560, height: 460))
        window.center()
        let delegate = CloseDelegate(model: model, completesOnClose: completesOnClose)
        window.delegate = delegate
        self.delegate = delegate
        return window
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        let model: OnboardingModel
        let completesOnClose: Bool

        init(model: OnboardingModel, completesOnClose: Bool) {
            self.model = model
            self.completesOnClose = completesOnClose
        }

        func windowWillClose(_ notification: Notification) {
            model.stopPolling()
            if completesOnClose {
                model.markCompleted()
            }
            OnboardingPresenter.window = nil
        }
    }
}

enum OnboardingSnapshot {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["FERRET_DEMO"] == "1"
            && CommandLine.arguments.contains("--demo-snapshot")
    }

    @MainActor
    static func run() -> Never {
        let screen = argument("--screen")
        guard let out = argument("--out") else {
            logLine("ferret: demo-snapshot needs --screen onboarding|settings --out <png>")
            exit(2)
        }
        let url = URL(fileURLWithPath: out)
        switch screen {
        case "onboarding":
            captureOnboarding(to: url)
        case "settings":
            SettingsPresenter.captureSnapshot(to: url)
        default:
            logLine("ferret: demo-snapshot unsupported screen \(screen ?? "nil")")
            exit(2)
        }
        exit(0)
    }

    @MainActor
    static func captureOnboarding(to url: URL) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let model = OnboardingModel.snapshotFixture()
        let window = OnboardingPresenter.makeWindow(model: model, completesOnClose: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        let until = Date().addingTimeInterval(0.5)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        window.displayIfNeeded()
        let view = window.contentView?.superview ?? window.contentView!
        logLine("ferret: capture bounds \(NSStringFromRect(view.bounds))")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            logLine("ferret: cacheDisplay failed")
            exit(3)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            logLine("ferret: png encode failed")
            exit(3)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            logLine("ferret: snapshot write failed \(error.localizedDescription)")
            exit(3)
        }
        logLine("ferret: wrote \(url.path)")
    }

    private static func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: index)
        guard args.indices.contains(next) else { return nil }
        return args[next]
    }
}
