import AppKit
import FerretCore
import XCTest
@testable import Ferret

final class RecordingWorkspace: Workspace {
    var revealed: [[URL]] = []
    var opened: [URL] = []
    func activateFileViewerSelecting(_ fileURLs: [URL]) { revealed.append(fileURLs) }
    func open(_ url: URL) -> Bool { opened.append(url); return true }
}

@MainActor
final class FinderActionsTests: XCTestCase {
    var workspace: RecordingWorkspace!
    var pasteboard: NSPasteboard!
    var exists = true

    private func makePanel(query: String = "alpha") async -> PanelController {
        workspace = RecordingWorkspace()
        pasteboard = NSPasteboard(name: .init("ferret-test-\(UUID().uuidString)"))
        let defaults = UserDefaults(suiteName: "actions.tests.\(UUID().uuidString)")!
        let panel = PanelController(backend: FixtureBackend(root: "/Users/demo"), settings: SettingsStore(defaults: defaults), demo: true)
        panel.setActions(FinderActions(workspace: workspace, pasteboard: pasteboard, fileExists: { [unowned self] _ in self.exists }))
        panel.show(scope: nil, query: query)
        let deadline = Date().addingTimeInterval(3)
        while panel.rows.isEmpty, Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(panel.rows.isEmpty)
        return panel
    }

    private func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testReturnRevealsAndHides() async {
        let panel = await makePanel()
        let path = panel.selectedRow!.path
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(workspace.revealed, [[URL(fileURLWithPath: path)]])
        XCTAssertFalse(panel.isVisible)
    }

    func testCommandReturnOpensAndHides() async {
        let panel = await makePanel()
        let path = panel.selectedRow!.path
        XCTAssertTrue(panel.handleKey(key("\r", code: 36, flags: .command)))
        XCTAssertEqual(workspace.opened, [URL(fileURLWithPath: path)])
        XCTAssertTrue(workspace.revealed.isEmpty)
        XCTAssertFalse(panel.isVisible)
    }

    func testCommandRRevealsWithoutHiding() async {
        let panel = await makePanel()
        XCTAssertTrue(panel.handleKey(key("r", code: 15, flags: .command)))
        XCTAssertEqual(workspace.revealed.count, 1)
        XCTAssertTrue(panel.isVisible)
        panel.hide()
    }

    func testCommandDigitRevealsNthRow() async {
        let panel = await makePanel()
        XCTAssertGreaterThanOrEqual(panel.rows.count, 3)
        let third = panel.rows[2].path
        XCTAssertTrue(panel.handleKey(key("3", code: 20, flags: .command)))
        XCTAssertEqual(workspace.revealed.last, [URL(fileURLWithPath: third)])
        XCTAssertEqual(panel.selectedIndex, 2)
        panel.hide()
    }

    func testCommandCCopiesPathAndFileURL() async {
        let panel = await makePanel()
        panel.window.makeFirstResponder(nil)
        let path = panel.selectedRow!.path
        XCTAssertTrue(panel.handleKey(key("c", code: 8, flags: .command)))
        XCTAssertEqual(pasteboard.string(forType: .string), path)
        XCTAssertEqual(pasteboard.string(forType: .fileURL), URL(fileURLWithPath: path).absoluteString)
        XCTAssertEqual(panel.toastText, "Copied")
        panel.hide()
    }

    func testCommandOptionCCopiesAllPaths() async {
        let panel = await makePanel()
        XCTAssertTrue(panel.handleKey(key("c", code: 8, flags: [.command, .option])))
        XCTAssertEqual(pasteboard.string(forType: .string), panel.rows.map(\.path).joined(separator: "\n"))
        panel.hide()
    }

    func testMissingFileShowsToastAndDoesNothing() async {
        let panel = await makePanel()
        exists = false
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(workspace.revealed.isEmpty)
        XCTAssertEqual(panel.toastText, "File no longer exists")
        XCTAssertTrue(panel.isVisible)
        panel.hide()
    }

    func testControlNPAndCommandArrows() async {
        let panel = await makePanel()
        let count = panel.rows.count
        XCTAssertTrue(panel.handleKey(key("n", code: 45, flags: .control)))
        XCTAssertEqual(panel.selectedIndex, 1)
        XCTAssertTrue(panel.handleKey(key("p", code: 35, flags: .control)))
        XCTAssertEqual(panel.selectedIndex, 0)
        XCTAssertTrue(panel.handleKey(key("", code: 125, flags: .command)))
        XCTAssertEqual(panel.selectedIndex, count - 1)
        XCTAssertTrue(panel.handleKey(key("", code: 126, flags: .command)))
        XCTAssertEqual(panel.selectedIndex, 0)
        panel.hide()
    }

    func testCommandCommaOpensSettings() async {
        let panel = await makePanel()
        var opened = false
        panel.openSettings = { opened = true }
        XCTAssertTrue(panel.handleKey(key(",", code: 43, flags: .command)))
        XCTAssertTrue(opened)
        panel.hide()
    }
}
