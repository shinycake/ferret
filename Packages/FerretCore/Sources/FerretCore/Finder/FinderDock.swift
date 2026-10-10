import CoreGraphics
import Foundation

/// Geometry and window-metadata helpers for the panel docked to a Finder window.
/// Uses only `CGWindowListCopyWindowInfo` metadata (bounds, owner, layer), never window images.
public enum FinderDock {
    public static let finderBundleID = "com.apple.finder"
    public static let panelWidth: CGFloat = 340
    /// Unified title bar + toolbar height of a Finder window (macOS 14–26 default toolbar).
    public static let toolbarHeight: CGFloat = 52
    public static let rightInset: CGFloat = 10

    public struct WindowInfo: Equatable, Sendable {
        public let windowID: UInt32
        public let pid: Int32
        /// Quartz global coordinates: origin at the top-left of the primary display, y down.
        public let bounds: CGRect
        public init(windowID: UInt32, pid: Int32, bounds: CGRect) {
            self.windowID = windowID
            self.pid = pid
            self.bounds = bounds
        }
    }

    /// Picks the frontmost normal (layer 0) window owned by `pid` from a front-to-back
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` list. Tiny windows (e.g. the desktop) are skipped.
    public static func frontWindow(in list: [[String: Any]], pid: Int32) -> WindowInfo? {
        for entry in list {
            guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 200, bounds.height >= 120
            else { continue }
            let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            return WindowInfo(windowID: id, pid: pid, bounds: bounds)
        }
        return nil
    }

    /// Converts Quartz (top-left, y down) to Cocoa (bottom-left, y up) using the primary display height.
    public static func cocoaRect(fromQuartz r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Top-left point (Cocoa coordinates) where the docked panel goes: just under the toolbar,
    /// right-aligned like Finder's own search field. Narrow windows shrink the width.
    public static func dockOrigin(finderCocoaFrame f: CGRect, width: CGFloat = panelWidth) -> (topLeft: CGPoint, width: CGFloat) {
        let w = min(width, max(f.width - 2 * rightInset, 220))
        let x = f.maxX - rightInset - w
        let top = f.maxY - toolbarHeight
        return (CGPoint(x: x, y: top), w)
    }
}

/// Parses `pluginkit -m -i <bundle id>` output. A leading `+` means enabled (user elected to use it),
/// `-` disabled, no line means the extension isn't registered with PlugInKit yet.
public enum ExtensionStatus: Equatable, Sendable {
    case enabled, disabled, notRegistered, unknown

    public static let bundleID = "com.shinycake.ferret.FinderSync"

    public static func parse(pluginkitOutput text: String) -> ExtensionStatus {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains(bundleID) else { continue }
            if line.hasPrefix("+") { return .enabled }
            if line.hasPrefix("-") { return .disabled }
            if line.hasPrefix("!") || line.hasPrefix("=") { return .disabled }
            return .disabled // registered, no election mark: not enabled by the user
        }
        return text.isEmpty ? .notRegistered : .unknown
    }

    public var label: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Installed but turned off"
        case .notRegistered: return "Not registered yet — open Ferret from /Applications once"
        case .unknown: return "Unknown"
        }
    }
}
