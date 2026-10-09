import Foundation

/// Client-side exclusions and hidden-file filtering.
/// fsearch still indexes excluded folders; this only drops hits from the rows we show.
public enum ResultFilter {
    public static func requestLimit(userLimit: Int, excluded: [String], showHidden: Bool) -> Int {
        let limit = clampUserLimit(userLimit)
        let filtering = !excluded.isEmpty || !showHidden
        guard filtering else { return limit }
        return min(limit * 3, 1000)
    }

    public static func apply(
        paths: [String],
        userLimit: Int,
        excluded: [String],
        showHidden: Bool,
        scope: String?
    ) -> [String] {
        let limit = clampUserLimit(userLimit)
        var kept: [String] = []
        kept.reserveCapacity(min(paths.count, limit))
        for path in paths {
            if kept.count == limit { break }
            if keeps(path: path, excluded: excluded, showHidden: showHidden, scope: scope) {
                kept.append(path)
            }
        }
        return kept
    }

    public static func keeps(path: String, excluded: [String], showHidden: Bool, scope: String?) -> Bool {
        if isExcluded(path, excluded: excluded) { return false }
        if !showHidden, isHidden(path, scope: scope) { return false }
        return true
    }

    public static func clampUserLimit(_ value: Int) -> Int {
        min(max(value, 10), 500)
    }

    private static func isExcluded(_ path: String, excluded: [String]) -> Bool {
        let path = normalize(path)
        for root in excluded.map(normalize) where !root.isEmpty {
            if path == root || path.hasPrefix(root + "/") { return true }
        }
        return false
    }

    /// A dot component counts only below the scope root. The scope folder's own name does not.
    private static func isHidden(_ path: String, scope: String?) -> Bool {
        let path = normalize(path)
        let root = normalize(scope ?? "/")
        let relative: String
        if root == "/" {
            relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        } else if path == root {
            relative = ""
        } else if path.hasPrefix(root + "/") {
            relative = String(path.dropFirst(root.count + 1))
        } else {
            return false
        }
        return relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    private static func normalize(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
