import AppKit
import FerretCore
import FinderSync

/// Live Finder Sync extension status from `pluginkit -m -i`, and the ways to turn it on.
enum FinderExtensionStatus {
    static func pluginkit(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func current() -> ExtensionStatus {
        let text = pluginkit(["-m", "-i", ExtensionStatus.bundleID])
        let parsed = ExtensionStatus.parse(pluginkitOutput: text)
        if parsed == .unknown { return FIFinderSyncController.isExtensionEnabled ? .enabled : .disabled }
        return parsed
    }

    /// Elects the extension for use (same as ticking it in System Settings), then re-checks.
    @discardableResult
    static func enableWithPluginkit() -> ExtensionStatus {
        _ = pluginkit(["-e", "use", "-i", ExtensionStatus.bundleID])
        return current()
    }

    /// System Settings → General → Login Items & Extensions (macOS 15+), Extensions pane on older systems.
    static func openSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
