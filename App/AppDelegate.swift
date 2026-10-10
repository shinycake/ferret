import AppKit
import CoreServices
import FerretCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static var isDemoExit: Bool {
        ProcessInfo.processInfo.environment["FERRET_DEMO"] == "1"
            && CommandLine.arguments.contains("--demo-exit")
    }

    let panel = PanelController()
    let daemonManager = DaemonManager()
    private(set) var statusController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerURLEvents()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logLine("ferret: launched \(FerretVersion.marketing)")
        guard !AppDelegate.isDemoExit else {
            logLine("ferret: demo-exit")
            NSApp.terminate(nil)
            return
        }
        if OnboardingSnapshot.isRequested {
            OnboardingSnapshot.run()
        }
        cleanupResultsFolders()
        let status = StatusItemController(panel: panel, health: daemonManager.health)
        statusController = status
        let daemon = daemonManager
        Task { await daemon.start() }
        if OnboardingModel.shouldAutoShow() {
            OnboardingPresenter.showLive()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemonManager.stop()
    }

    func handle(url: URL) {
        guard let route = URLRoute(url: url) else {
            logLine("ferret: ignored url \(url.absoluteString)")
            return
        }
        switch route {
        case .search(let query, let scope):
            panel.show(scope: scope, query: query)
        case .settings:
            statusController?.showSettings(nil)
        case .onboarding:
            statusController?.showSetup(nil)
        }
    }

    private func cleanupResultsFolders() {
        do {
            try ResultsFolderService(cacheDir: AppLocations.cacheDirectory).cleanup()
            logLine("ferret: results cleanup ok")
        } catch {
            logLine("ferret: results cleanup failed \(error)")
        }
    }

    private func registerURLEvents() {
        // kInternetEventClass / kAEGetURL ('GURL') and keyDirectObject ('----').
        let internetEventClass = AEEventClass(0x4755524C)
        let getURL = AEEventID(0x4755524C)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: internetEventClass,
            andEventID: getURL
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let directObject = AEKeyword(0x2D2D2D2D)
        guard let text = event.paramDescriptor(forKeyword: directObject)?.stringValue,
              let url = URL(string: text) else {
            return
        }
        handle(url: url)
    }
}

func logLine(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
}
