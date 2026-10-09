import Foundation

public enum FullDiskAccess {
    /// System Settings → Privacy & Security → Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// `open(TCC.db, O_RDONLY) >= 0`. Fails immediately and never prompts.
    public static func isGranted() -> Bool {
        let fd = Darwin.open("/Library/Application Support/com.apple.TCC/TCC.db", Darwin.O_RDONLY)
        guard fd >= 0 else { return false }
        Darwin.close(fd)
        return true
    }
}
