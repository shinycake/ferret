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

/// `--screen menu`: renders the live status item's real NSMenuItems into one of our own windows.
/// (The system-drawn menu itself cannot be captured with cacheDisplay.)
enum MenuSnapshot {
    @MainActor
    static func capture(to url: URL) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        var continuation: AsyncStream<ShellHealth>.Continuation!
        let stream = AsyncStream<ShellHealth> { continuation = $0 }
        let controller = StatusItemController(panel: PanelController(demo: true), health: stream, openLogs: {})
        continuation.yield(.ready("7.7M items · FDA ✓"))
        SnapshotCapture.spin(0.3)
        logLine("MENU_TITLES: \(controller.menuDumpLine)")

        let width: CGFloat = 300
        let rowHeight: CGFloat = 24
        let items = controller.menu.items
        let height = CGFloat(items.count) * rowHeight + 52
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        let bar = NSView(frame: NSRect(x: 0, y: height - 28, width: width, height: 28))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        let icon = NSImageView(frame: NSRect(x: 12, y: 5, width: 18, height: 18))
        icon.image = controller.statusItem.button?.image
        icon.contentTintColor = .white
        bar.addSubview(icon)
        let barLabel = NSTextField(labelWithString: "Ferret menu-bar item")
        barLabel.frame = NSRect(x: 36, y: 5, width: 240, height: 17)
        barLabel.textColor = .secondaryLabelColor
        barLabel.font = .systemFont(ofSize: 12)
        bar.addSubview(barLabel)
        content.addSubview(bar)
        var y = height - 28 - 12 - rowHeight
        for item in items {
            if item.isSeparatorItem {
                let line = NSBox(frame: NSRect(x: 10, y: y + rowHeight / 2, width: width - 20, height: 1))
                line.boxType = .separator
                content.addSubview(line)
            } else {
                let title = NSTextField(labelWithString: item.title)
                title.frame = NSRect(x: 18, y: y + 3, width: 190, height: 18)
                title.font = .menuFont(ofSize: 13)
                title.textColor = item.isEnabled && item.action != nil ? .labelColor : .secondaryLabelColor
                content.addSubview(title)
                var key = ""
                if item === controller.searchItem { key = MenuHotkey.display }
                else if !item.keyEquivalent.isEmpty { key = "⌘" + item.keyEquivalent.uppercased() }
                let keyLabel = NSTextField(labelWithString: key)
                keyLabel.frame = NSRect(x: width - 100, y: y + 3, width: 82, height: 18)
                keyLabel.alignment = .right
                keyLabel.textColor = .secondaryLabelColor
                keyLabel.font = .menuFont(ofSize: 13)
                content.addSubview(keyLabel)
            }
            y -= rowHeight
        }
        window.contentView = content
        window.orderFrontRegardless()
        SnapshotCapture.capture(window: window, to: url)
    }
}
