import Foundation

/// Every on-disk location Ferret touches, derived from one home so tests can redirect it.
public struct FerretPaths: Sendable, Equatable {
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    /// `FERRET_HOME` when set, otherwise the user's home directory.
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> FerretPaths {
        if let override = environment["FERRET_HOME"], !override.isEmpty {
            return FerretPaths(home: URL(fileURLWithPath: override, isDirectory: true))
        }
        return FerretPaths(home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    public var fsearchDir: URL { home.appendingPathComponent("Library/Application Support/FSearch", isDirectory: true) }
    public var socket: URL { fsearchDir.appendingPathComponent("fsearch.sock") }
    public var socketLock: URL { fsearchDir.appendingPathComponent("socket.lock") }
    public var cacheDir: URL { home.appendingPathComponent("Library/Caches/com.shinycake.ferret", isDirectory: true) }
    public var logDir: URL { home.appendingPathComponent("Library/Logs/Ferret", isDirectory: true) }
    public var daemonLog: URL { logDir.appendingPathComponent("fsearch.log") }
    public var launchAgent: URL { home.appendingPathComponent("Library/LaunchAgents/mt.nd.fsearch.plist") }

    /// PID written by `fsearch serve` into `socket.lock`, if readable.
    public func socketLockPID() -> Int32? {
        guard let text = try? String(contentsOf: socketLock, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum LogRotation {
    /// Moves `log` to `log.1` (replacing an older `.1`) when it is larger than `maxBytes`.
    @discardableResult
    public static func rotateIfNeeded(_ log: URL, maxBytes: Int = 5 * 1024 * 1024, fileManager: FileManager = .default) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: log.path),
              let size = attrs[.size] as? NSNumber, size.intValue > maxBytes else { return false }
        let rotated = URL(fileURLWithPath: log.path + ".1")
        try? fileManager.removeItem(at: rotated)
        do {
            try fileManager.moveItem(at: log, to: rotated)
            return true
        } catch {
            return false
        }
    }

    /// Last `count` lines of a log file.
    public static func tail(_ log: URL, count: Int = 20) -> String {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(count).joined(separator: "\n")
    }
}
