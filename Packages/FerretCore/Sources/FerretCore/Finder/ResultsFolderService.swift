import Foundation

/// Cache folder of symlinks that Finder shows for "Show all in Finder".
/// Materializing the folder lands with the show-all ticket; launch only cleans up.
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
}
