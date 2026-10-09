import Foundation

enum AppLocations {
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["FERRET_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var cacheDirectory: URL {
        home.appendingPathComponent("Library/Caches/com.shinycake.ferret", isDirectory: true)
    }

    static var logDirectory: URL {
        home.appendingPathComponent("Library/Logs/Ferret", isDirectory: true)
    }
}
