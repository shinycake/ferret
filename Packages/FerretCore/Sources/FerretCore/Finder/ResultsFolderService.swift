import Foundation

/// Cache folder of symlinks that Finder shows for "Show all in Finder".
public struct ResultsFolderService {
    public let cacheDir: URL
    private let fileManager: FileManager
    private let now: () -> Date

    public init(cacheDir: URL, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.cacheDir = cacheDir
        self.fileManager = fileManager
        self.now = now
    }

    /// Delete `results-*` directories older than `maxAge`, and keep at most `keep` of the newest.
    /// `removeItem` on each directory removes the symlinks inside it and does not follow them.
    public func cleanup(maxAge: TimeInterval = 86_400, keep: Int = 10) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        let names = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
        var dated: [(url: URL, created: Date)] = []
        for name in names where name.hasPrefix("results-") {
            let url = cacheDir.appendingPathComponent(name, isDirectory: true)
            var itemIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &itemIsDirectory), itemIsDirectory.boolValue else {
                continue
            }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let created = (attributes?[.creationDate] as? Date)
                ?? (attributes?[.modificationDate] as? Date)
                ?? .distantPast
            dated.append((url, created))
        }
        dated.sort { $0.created > $1.created }
        let cutoff = now().addingTimeInterval(-maxAge)
        for (index, item) in dated.enumerated() where item.created < cutoff || index >= keep {
            try fileManager.removeItem(at: item.url)
        }
    }

    /// Creates `results-<yyyyMMdd-HHmmss>-<6 hex>/` with one symlink per existing path and a `_query.txt`.
    public func materialize(paths: [String], query: String, scope: String? = nil) throws -> URL {
        try? cleanup()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = now()
        let hex = String(format: "%06x", UInt32.random(in: 0...0xFFFFFF))
        let folder = cacheDir.appendingPathComponent("results-\(formatter.string(from: stamp))-\(hex)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var taken: Set<String> = ["_query.txt"]
        for path in paths {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            let name = Self.uniqueName((path as NSString).lastPathComponent, isPackageOrDir: isDirectory.boolValue, taken: &taken)
            try fileManager.createSymbolicLink(atPath: folder.appendingPathComponent(name).path, withDestinationPath: path)
        }
        var note = "query: \(query)\n"
        if let scope { note += "scope: \(scope)\n" }
        note += "created: \(ISO8601DateFormatter().string(from: stamp))\n"
        note += "These are symlinks. Moving one to the Trash removes only the link, never the original.\n"
        try note.write(to: folder.appendingPathComponent("_query.txt"), atomically: true, encoding: .utf8)
        return folder
    }

    /// `README.md` → `README (2).md`; `Foo.app` → `Foo (2).app`; `Makefile` → `Makefile (2)`.
    public static func uniqueName(_ name: String, isPackageOrDir: Bool, taken: inout Set<String>) -> String {
        if taken.insert(name).inserted { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if taken.insert(candidate).inserted { return candidate }
            n += 1
        }
    }
}
