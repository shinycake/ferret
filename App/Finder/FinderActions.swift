import AppKit
import FerretCore

protocol Workspace: AnyObject {
    func activateFileViewerSelecting(_ fileURLs: [URL])
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: Workspace {}

/// Finder-facing actions for result rows (SPEC §6.3). Every action checks that the file still exists.
@MainActor
final class FinderActions {
    static let missingMessage = "File no longer exists"
    static let copiedMessage = "Copied"

    let workspace: Workspace
    let pasteboard: NSPasteboard
    let fileExists: (String) -> Bool
    var toast: ((String) -> Void)?

    init(workspace: Workspace = NSWorkspace.shared, pasteboard: NSPasteboard = .general, fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.workspace = workspace
        self.pasteboard = pasteboard
        self.fileExists = fileExists
    }

    @discardableResult
    func reveal(_ row: ResultRow) -> Bool {
        guard check(row) else { return false }
        workspace.activateFileViewerSelecting([URL(fileURLWithPath: row.path)])
        return true
    }

    @discardableResult
    func open(_ row: ResultRow) -> Bool {
        guard check(row) else { return false }
        _ = workspace.open(URL(fileURLWithPath: row.path))
        return true
    }

    @discardableResult
    func copyPath(_ row: ResultRow) -> Bool {
        guard check(row) else { return false }
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: row.path)
        pasteboard.declareTypes([.string, .fileURL], owner: nil)
        pasteboard.setString(row.path, forType: .string)
        pasteboard.setString(url.absoluteString, forType: .fileURL)
        toast?(Self.copiedMessage)
        return true
    }

    func copyAll(_ rows: [ResultRow]) {
        guard !rows.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(rows.map(\.path).joined(separator: "\n"), forType: .string)
        toast?(Self.copiedMessage)
    }

    var resultsService = ResultsFolderService(cacheDir: FerretPaths.current().cacheDir)

    @discardableResult
    func showAll(paths: [String], query: String, scope: String?) -> URL? {
        do {
            let folder = try resultsService.materialize(paths: paths, query: query, scope: scope)
            _ = workspace.open(folder)
            return folder
        } catch {
            toast?("Could not create the results folder")
            return nil
        }
    }

    private func check(_ row: ResultRow) -> Bool {
        if fileExists(row.path) { return true }
        toast?(Self.missingMessage)
        return false
    }
}
