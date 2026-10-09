import Foundation

/// Chooses the folder a Finder Sync "Search here" action should scope to.
///
/// Compiled into FerretCore (for tests) and into the Finder Sync appex.
/// The appex does not link FerretCore.
public enum ScopeResolver {
    /// - A directory that is not a package resolves to itself.
    /// - A file or a package resolves to its parent.
    /// - With no selection, `targeted` is used.
    public static func scope(targeted: URL?, selected: [URL]) -> String? {
        guard let first = selected.first else {
            return targeted?.path
        }
        if isDirectory(first), !isPackage(first) {
            return first.path
        }
        return first.deletingLastPathComponent().path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }
}
