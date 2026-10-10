import AppKit
import CoreGraphics
import FerretCore

/// Opens the search panel docked under the frontmost Finder window's toolbar and keeps it there.
/// Window frames come from CGWindowListCopyWindowInfo metadata only (no Accessibility, no capture).
@MainActor
final class FinderDockController {
    let panel: PanelController
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    init(panel: PanelController) {
        self.panel = panel
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        }
    }

    static var finderApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: FinderDock.finderBundleID).first
    }

    static var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == FinderDock.finderBundleID
    }

    /// Cocoa-coordinate frame of the frontmost Finder browser window, if any.
    static func finderWindowFrame() -> CGRect? {
        guard let finder = finderApp,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = FinderDock.frontWindow(in: list, pid: finder.processIdentifier),
              let primary = NSScreen.screens.first
        else { return nil }
        return FinderDock.cocoaRect(fromQuartz: info.bounds, primaryHeight: primary.frame.height)
    }

    /// `folder` comes from the Finder Sync extension (targetedURL); otherwise ask Finder via AppleScript.
    func open(folder: String?) {
        let scope = folder ?? Self.frontFinderFolder()
        guard let frame = Self.finderWindowFrame() else {
            logLine("ferret: dock: no Finder window, using the regular panel")
            panel.show(scope: scope)
            return
        }
        let dock = FinderDock.dockOrigin(finderCocoaFrame: frame)
        panel.showDocked(topLeft: dock.topLeft, width: dock.width, folder: scope)
        startTracking()
    }

    func toggle(folder: String?) {
        if panel.isVisible, panel.docked { panel.hide(); stopTracking() } else { open(folder: folder) }
    }

    private func startTracking() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard panel.isVisible, panel.docked else { return stopTracking() }
        guard let frame = Self.finderWindowFrame() else {
            panel.hide()
            return stopTracking()
        }
        let dock = FinderDock.dockOrigin(finderCocoaFrame: frame)
        panel.followDock(topLeft: dock.topLeft, width: dock.width)
    }

    private func appActivated(_ app: NSRunningApplication?) {
        guard panel.isVisible, panel.docked else { return }
        let id = app?.bundleIdentifier
        // Ferret itself may activate (e.g. Quick Look); anything else means Finder lost focus.
        if id != FinderDock.finderBundleID, app != NSRunningApplication.current {
            panel.hide()
            stopTracking()
        }
    }

    /// POSIX path of Finder's front window target. Needs the Automation (Apple Events) permission.
    static func frontFinderFolder() -> String? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error { logLine("ferret: dock: AppleScript failed \(error)") }
        guard let path = result, !path.isEmpty else { return nil }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
