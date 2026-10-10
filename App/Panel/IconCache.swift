import AppKit
import FerretCore
import UniformTypeIdentifiers

/// Generic icons are synchronous and cached per extension; real icons for apps, dirs, and links load
/// on a utility queue (never synchronously during reload) and are cached in an NSCache.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var generic: [String: NSImage] = [:]
    private let specific = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "ferret.icons", qos: .utility)

    init() {
        specific.countLimit = 500
    }

    func icon(for row: ResultRow, ready: @escaping (NSImage) -> Void) -> NSImage {
        let needsSpecific = row.kind == .dir || row.kind == .link || row.path.hasSuffix(".app")
        if needsSpecific, let cached = specific.object(forKey: row.path as NSString) {
            return cached
        }
        let placeholder = genericIcon(for: row)
        if needsSpecific {
            let path = row.path
            queue.async {
                let image = NSWorkspace.shared.icon(forFile: path)
                DispatchQueue.main.async { [weak self] in
                    self?.specific.setObject(image, forKey: path as NSString)
                    ready(image)
                }
            }
        }
        return placeholder
    }

    func genericIcon(for row: ResultRow) -> NSImage {
        let key = row.kind == .dir ? "/dir" : (row.path as NSString).pathExtension.lowercased()
        if let cached = generic[key] { return cached }
        let type: UTType = row.kind == .dir ? .folder : (UTType(filenameExtension: key) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        generic[key] = image
        return image
    }
}
