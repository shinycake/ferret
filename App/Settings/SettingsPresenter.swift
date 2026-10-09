import AppKit
import ServiceManagement
import SwiftUI
import FerretCore

@MainActor
enum SettingsPresenter {
    private static var window: NSWindow?
    private static var model: SettingsModel?

    static func showLive() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let store = SettingsStore()
        store.launchAtLogin = SMAppService.mainApp.status == .enabled
        let model = SettingsModel(
            store: store,
            confirm: confirmReindex,
            performReindex: reindexSearchIndex
        )
        self.model = model
        let window = makeWindow(model: model, about: liveAbout(), interactive: true)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Hook for `DaemonManager.reindex()` once that actor is linked into the app.
    static func reindexSearchIndex() {}

    static func confirmReindex(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Reindex?"
        alert.informativeText = message
        alert.addButton(withTitle: "Reindex")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func captureSnapshot(to url: URL) {
        let name = "ferret.settings.snapshot"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = SettingsStore(defaults: defaults)
        store.resultLimit = 50
        store.showHiddenFiles = false
        store.launchAtLogin = false
        store.excludedPaths = ["/Users/example/Secret"]
        let model = SettingsModel(store: store, confirm: { _ in false }, performReindex: {})
        self.model = model
        let window = makeWindow(model: model, about: snapshotAbout(), interactive: false)
        self.window = window
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
        logLine("ferret: settings capture bounds \(NSStringFromRect(view.bounds))")
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

    static func liveAbout() -> AboutSnapshot {
        AboutSnapshot(
            marketingVersion: FerretVersion.marketing,
            gitSHA: "unavailable",
            fsearchPin: pinSHA(),
            daemonSummary: "not connected",
            fullDiskAccess: FullDiskAccess.isGranted()
        )
    }

    static func snapshotAbout() -> AboutSnapshot {
        AboutSnapshot(
            marketingVersion: FerretVersion.marketing,
            gitSHA: "unavailable",
            fsearchPin: pinSHA(),
            daemonSummary: "not connected",
            fullDiskAccess: false
        )
    }

    static func pinSHA() -> String {
        guard let url = Bundle.main.url(forResource: "FSearchPin", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "unavailable"
        }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "unavailable" : line
    }

    private static func makeWindow(model: SettingsModel, about: AboutSnapshot, interactive: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(
            store: model.store,
            about: about,
            onAddExcluded: {
                guard interactive else { return }
                addExcluded(to: model.store)
            },
            onReindex: {
                guard interactive else { return }
                model.requestReindex()
            },
            onOpenLogs: {
                guard interactive else { return }
                openLogs()
            },
            onOpenLicenses: {
                guard interactive else { return }
                openLicenses()
            },
            onLaunchAtLogin: { enabled in
                guard interactive else { return }
                applyLogin(enabled)
            }
        ))
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()
        return window
    }

    private static func addExcluded(to store: SettingsStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            store.addExcluded(url.path)
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

    private static func openLogs() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ferret", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private static func openLicenses() {
        guard let url = Bundle.main.url(
            forResource: "fsearch-LICENSE",
            withExtension: "txt",
            subdirectory: "ThirdPartyLicenses"
        ) else {
            logLine("ferret: third-party license missing")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
