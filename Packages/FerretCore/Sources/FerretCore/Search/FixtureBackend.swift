import Foundation

/// Deterministic in-memory backend for demo snapshots and tests (minimal T8).
/// Matching is a small imitation of fsearch: tokens are case-insensitive substrings,
/// words of 5+ letters forgive one typo, and `ext:`, `type:doc`, `size:>N`, `kind:dir`, `grep:` are honoured.
public struct FixtureBackend: SearchBackend {
    public enum Mode: Sendable { case normal, indexing }

    public struct Entry: Sendable {
        public let path: String
        public let kind: HitKind
        public let size: UInt64
        public let mtime: UInt32
        public let lines: [String]
        public init(path: String, kind: HitKind = .file, size: UInt64 = 0, mtime: UInt32, lines: [String] = []) {
            self.path = path
            self.kind = kind
            self.size = size
            self.mtime = mtime
            self.lines = lines
        }
    }

    public let entries: [Entry]
    public let mode: Mode
    public let root: String

    public init(root: String = "/Users/demo", mode: Mode = .normal, now: Date = Date()) {
        self.root = root
        self.mode = mode
        let t = UInt32(now.timeIntervalSince1970)
        let day: UInt32 = 86_400
        self.entries = [
            Entry(path: "\(root)/Documents/alpha-report.pdf", size: 482_133, mtime: t - 2 * 3600),
            Entry(path: "\(root)/Documents/Reports/alpha-report-2025.pdf", size: 1_204_551, mtime: t - 40 * day),
            Entry(path: "\(root)/Desktop/alpha reply draft.docx", size: 38_912, mtime: t - 3 * day),
            Entry(path: "\(root)/Documents/beta notes.md", size: 2_048, mtime: t - 5 * day, lines: ["# Beta notes", "alpha report follow-up"]),
            Entry(path: "\(root)/Developer/fsearch/src/main.rs", size: 7_421, mtime: t - 1 * day, lines: ["mod walk;", "fn main() {", "    walk::apply_dir(&root);"]),
            Entry(path: "\(root)/Developer/fsearch/src/walk.rs", size: 12_930, mtime: t - 1 * day, lines: ["pub fn apply_dir(path: &str) {}", "// apply_dir walks one folder", "fn apply_dirs() {}"]),
            Entry(path: "\(root)/Developer/fsearch/README.md", size: 5_310, mtime: t - 6 * day, lines: ["fsearch: whole-disk fuzzy search"]),
            Entry(path: "\(root)/Developer/ferret/README.md", size: 3_101, mtime: t - 300, lines: ["Ferret puts fsearch behind a hotkey"]),
            Entry(path: "\(root)/Developer/ferret/sub dir/notes.txt", size: 911, mtime: t - 10 * day),
            Entry(path: "\(root)/Developer/ferret/sub dir/alpha-sketch.png", size: 2_400_000, mtime: t - 12 * day),
            Entry(path: "\(root)/Developer/ferret/sub dir", kind: .dir, mtime: t - 10 * day),
            Entry(path: "\(root)/Downloads/big.bin", size: 6_000_000, mtime: t - 20 * day),
            Entry(path: "\(root)/Documents/old.txt", size: 120, mtime: t - 400 * day),
            Entry(path: "\(root)/Documents/invoice-march.pdf", size: 92_000, mtime: t - 25 * day),
            Entry(path: "/Applications/Safari.app", kind: .dir, mtime: t - 30 * day),
            Entry(path: "\(root)/Documents", kind: .dir, mtime: t - 1 * day),
        ]
    }

    public func status() async throws -> DaemonStatus {
        if mode == .indexing { throw FSearchError.indexing }
        return DaemonStatus(entries: 7_712_345, dirs: 812_345, contentPending: 0, fullDiskAccess: true, owner: true)
    }

    public func search(_ request: FSearchClient.SearchRequest) async throws -> SearchPayload {
        if mode == .indexing { throw FSearchError.indexing }
        var words: [String] = []
        var exts: [String] = []
        var docOnly = false
        var minSize: UInt64?
        var dirOnly = false
        var grep: String?
        for token in request.text.split(separator: " ").map(String.init) {
            let lower = token.lowercased()
            if lower.hasPrefix("ext:") {
                exts = lower.dropFirst(4).split(separator: ",").map(String.init)
            } else if lower.hasPrefix("type:") {
                docOnly = lower.contains("doc")
            } else if lower.hasPrefix("size:") {
                let value = lower.dropFirst(5)
                guard value.hasPrefix(">"), let n = Self.bytes(String(value.dropFirst())) else {
                    throw FSearchError.server("bad range \(value)")
                }
                minSize = n
            } else if lower.hasPrefix("kind:") {
                dirOnly = lower.hasSuffix("dir") || lower.hasSuffix("d")
            } else if lower.hasPrefix("grep:") || lower.hasPrefix("content:") {
                grep = String(token.split(separator: ":", maxSplits: 1).last ?? "")
            } else {
                words.append(lower)
            }
        }
        let candidates = entries.filter { entry in
            if let scope = request.scope, !(entry.path == scope || entry.path.hasPrefix(scope + "/")) { return false }
            let name = (entry.path as NSString).lastPathComponent.lowercased()
            let ext = (name as NSString).pathExtension
            if !exts.isEmpty, !exts.contains(ext) { return false }
            if docOnly, !["pdf", "md", "docx", "txt"].contains(ext) { return false }
            if let minSize, entry.size <= minSize { return false }
            if dirOnly, entry.kind != .dir { return false }
            return words.allSatisfy { Self.matches(word: $0, in: name) }
        }
        if let grep {
            let files = candidates.compactMap { entry -> GrepFile? in
                let lines = entry.lines.enumerated().filter { $0.element.contains(grep) }
                guard !lines.isEmpty else { return nil }
                return GrepFile(path: entry.path, matches: lines.map { GrepLine(line: $0.offset + 1, text: $0.element) })
            }
            return .content(files: Array(files.prefix(request.limit)), tookUs: 5_600, complete: true, fromIndex: true, pending: 0)
        }
        let hits = candidates.prefix(request.limit).enumerated().map { index, entry in
            Hit(path: entry.path, kind: entry.kind, size: entry.size, mtime: entry.mtime, score: Int32(400 - index))
        }
        return .names(hits: Array(hits), tookUs: 1_312)
    }

    static func matches(word: String, in name: String) -> Bool {
        if name.contains(word) { return true }
        guard word.count >= 5 else { return false }
        // One typo: a single substitution or adjacent swap against any window of the name.
        let w = Array(word), n = Array(name)
        guard n.count >= w.count else { return false }
        for start in 0...(n.count - w.count) {
            let window = Array(n[start..<start + w.count])
            let diffs = zip(w, window).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
            if diffs.count <= 1 { return true }
            if diffs.count == 2, diffs[1] == diffs[0] + 1, w[diffs[0]] == window[diffs[1]], w[diffs[1]] == window[diffs[0]] { return true }
        }
        return false
    }

    static func bytes(_ text: String) -> UInt64? {
        let lower = text.lowercased()
        let units: [(String, UInt64)] = [("tb", 1_000_000_000_000), ("gb", 1_000_000_000), ("mb", 1_000_000), ("kb", 1_000), ("t", 1_000_000_000_000), ("g", 1_000_000_000), ("m", 1_000_000), ("k", 1_000), ("b", 1)]
        for (suffix, scale) in units where lower.hasSuffix(suffix) {
            guard let n = Double(lower.dropLast(suffix.count)) else { return nil }
            return UInt64(n * Double(scale))
        }
        return UInt64(lower)
    }
}
