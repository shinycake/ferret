import AppKit
import FerretCore

/// `--screen dock`: the Finder-docked panel over a mock Finder-like window. Both are our own
/// windows rendered with cacheDisplay and composited; nothing reads the real screen.
enum DockSnapshot {
    @MainActor
    static func capture(to url: URL, arguments: [String]) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        func arg(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let root = PanelSnapshot.fixtureRoot
        let folder = root + "/Developer/ferret"
        let finderFrame = NSRect(x: 120, y: 120, width: 940, height: 600)
        let mock = MockFinderWindow(frame: finderFrame, title: "ferret")
        mock.orderFront(nil)

        let defaults = UserDefaults(suiteName: "ferret.dock.snapshot")!
        defaults.removePersistentDomain(forName: "ferret.dock.snapshot")
        let controller = PanelController(backend: FixtureBackend(root: root, mode: .normal),
                                         settings: SettingsStore(defaults: defaults), demo: true)
        controller.setFooterStatus("7.7M items · FDA ✓")
        let query = arg("--query") ?? ""
        var done = query.isEmpty
        controller.onStateChange = { _ in done = true }
        let dock = FinderDock.dockOrigin(finderCocoaFrame: finderFrame)
        controller.showDocked(topLeft: dock.topLeft, width: dock.width, folder: folder, query: query)
        if arg("--scope-mode") == "mac" {
            controller.scopeControl.selectedSegment = 1
            done = query.isEmpty
            controller.scopeToggled()
        }
        let deadline = Date().addingTimeInterval(10)
        while !done, Date() < deadline { SnapshotCapture.spin(0.05) }
        if let select = arg("--select").flatMap(Int.init) { controller.select(select - 1) }
        SnapshotCapture.spin(0.3)
        logLine("ferret: dock rows \(controller.rows.map(\.name).joined(separator: ", ")) frame \(NSStringFromRect(controller.window.frame))")

        guard let base = render(mock), let overlay = render(controller.window) else {
            logLine("ferret: dock cacheDisplay failed"); exit(3)
        }
        let pad: CGFloat = 30
        let pf = controller.window.frame
        let canvas = NSRect(x: 0, y: 0, width: finderFrame.width + 2 * pad,
                            height: max(finderFrame.maxY, pf.maxY) - min(finderFrame.minY, pf.minY) + 2 * pad)
        let minY = min(finderFrame.minY, pf.minY)
        let image = NSImage(size: canvas.size)
        image.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1).setFill()
        canvas.fill()
        base.draw(in: NSRect(x: pad, y: finderFrame.minY - minY + pad, width: finderFrame.width, height: finderFrame.height))
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.set()
        overlay.draw(in: NSRect(x: pf.minX - finderFrame.minX + pad, y: pf.minY - minY + pad, width: pf.width, height: pf.height))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try png.write(to: url) } catch { logLine("ferret: write failed \(error)"); exit(3) }
        logLine("ferret: wrote \(url.path)")
    }

    @MainActor
    static func render(_ window: NSWindow) -> NSImage? {
        window.displayIfNeeded()
        let view = window.contentView?.superview ?? window.contentView!
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

/// A Finder look-alike: unified toolbar with traffic lights and a search field spot, sidebar, list.
final class MockFinderWindow: NSWindow {
    init(frame: NSRect, title: String) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .clear
        contentView = MockFinderView(frame: NSRect(origin: .zero, size: frame.size), title: title)
    }
}

final class MockFinderView: NSView {
    let title: String
    init(frame: NSRect, title: String) { self.title = title; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let path = NSBezierPath(roundedRect: b, xRadius: 12, yRadius: 12)
        path.addClip()
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill(); b.fill()
        let sidebar = NSRect(x: 0, y: 0, width: 190, height: b.height)
        NSColor(calibratedWhite: 0.19, alpha: 1).setFill(); sidebar.fill()
        let bar = NSRect(x: 190, y: b.height - FinderDock.toolbarHeight, width: b.width - 190, height: FinderDock.toolbarHeight)
        NSColor(calibratedWhite: 0.17, alpha: 1).setFill(); bar.fill()
        NSColor(calibratedWhite: 0.05, alpha: 1).setFill()
        NSRect(x: 190, y: bar.minY - 1, width: bar.width, height: 1).fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18 + CGFloat(i) * 20, y: b.height - 32, width: 12, height: 12)).fill()
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)]
        ("‹  ›   " + title as NSString).draw(at: NSPoint(x: 210, y: b.height - 34), withAttributes: titleAttrs)
        let icon = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon?.isTemplate = true
        let iconRect = NSRect(x: b.width - 44, y: b.height - 36, width: 20, height: 20)
        NSColor(calibratedWhite: 0.30, alpha: 1).setFill()
        NSBezierPath(roundedRect: iconRect.insetBy(dx: -6, dy: -4), xRadius: 6, yRadius: 6).fill()
        icon?.draw(in: iconRect.insetBy(dx: 2, dy: 2))
        let side: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1)]
        for (i, s) in ["Favorites", "  Recents", "  Applications", "  Desktop", "  Documents", "  Downloads", "  Developer"].enumerated() {
            (s as NSString).draw(at: NSPoint(x: 16, y: b.height - 76 - CGFloat(i) * 24), withAttributes: side)
        }
        let row: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1)]
        for (i, s) in ["App", "FinderSync", "Packages", "docs", "scripts", "sub dir", "README.md", "project.yml", "Package.resolved"].enumerated() {
            let y = b.height - FinderDock.toolbarHeight - 30 - CGFloat(i) * 26
            if i % 2 == 1 { NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); NSRect(x: 190, y: y - 6, width: b.width - 190, height: 26).fill() }
            (("📁  " + s) as NSString).draw(at: NSPoint(x: 210, y: y), withAttributes: row)
        }
    }
}
