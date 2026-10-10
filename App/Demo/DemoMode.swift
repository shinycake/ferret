import AppKit
import FerretCore

/// cacheDisplay capture of one of our own windows (never CGWindowList / ScreenCaptureKit).
enum SnapshotCapture {
    @MainActor
    static func capture(window: NSWindow, to url: URL) {
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        spin(0.3)
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

    @MainActor
    static func spin(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

/// `--screen panel|cheatsheet` for the demo harness (SPEC §13.4) with the FixtureBackend.
enum PanelSnapshot {
    static let fixtureRoot = "/Users/demo"

    @MainActor
    static func capture(to url: URL, arguments: [String]) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        func arg(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let state = arg("--state")
        let backend = FixtureBackend(root: fixtureRoot, mode: state == "indexing" ? .indexing : .normal)
        let defaults = UserDefaults(suiteName: "ferret.panel.snapshot")!
        defaults.removePersistentDomain(forName: "ferret.panel.snapshot")
        let settings = SettingsStore(defaults: defaults)
        let controller = PanelController(backend: backend, settings: settings, demo: true)
        controller.setFooterStatus(state == "indexing" ? "Indexing…" : "7.7M items · FDA ✓")
        var scope = arg("--scope")
        if let s = scope, !s.hasPrefix("/") { scope = fixtureRoot + "/" + s }
        let query = arg("--query") ?? ""
        var done = false
        controller.onStateChange = { _ in done = true }
        controller.show(scope: scope, query: query)
        if query.isEmpty { done = true }
        let deadline = Date().addingTimeInterval(10)
        while !done, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard done else {
            logLine("ferret: panel snapshot timed out")
            exit(2)
        }
        if let select = arg("--select").flatMap(Int.init) {
            controller.select(select - 1)
        }
        logLine("ferret: panel rows \(controller.rows.map(\.name).joined(separator: ", "))")
        SnapshotCapture.capture(window: controller.window, to: url)
    }
}
