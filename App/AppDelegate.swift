import AppKit
import FerretCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isDemoExit: Bool {
        ProcessInfo.processInfo.environment["FERRET_DEMO"] == "1"
            && CommandLine.arguments.contains("--demo-exit")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logLine("ferret: launched \(FerretVersion.marketing)")
        guard AppDelegate.isDemoExit else { return }
        logLine("ferret: demo-exit")
        NSApp.terminate(nil)
    }
}

func logLine(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
}
