import AppKit
import FerretCore
import XCTest
@testable import Ferret

@MainActor
final class PanelControllerTests: XCTestCase {
    private func makePanel() -> PanelController {
        let defaults = UserDefaults(suiteName: "panel.tests.\(UUID().uuidString)")!
        return PanelController(backend: FixtureBackend(root: "/Users/demo"), settings: SettingsStore(defaults: defaults), demo: true)
    }

    private func waitForRows(_ panel: PanelController, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while panel.rows.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testShowRunsQueryAndSelectsFirstRow() async {
        let panel = makePanel()
        panel.show(scope: nil, query: "alpha rep")
        await waitForRows(panel)
        XCTAssertEqual(panel.rows.first?.name, "alpha-report.pdf")
        XCTAssertEqual(panel.selectedIndex, 0)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.cheatSheet.isHidden)
        panel.hide()
        XCTAssertFalse(panel.isVisible)
    }

    func testEmptyQueryShowsCheatSheet() {
        let panel = makePanel()
        panel.show(scope: nil, query: "")
        XCTAssertFalse(panel.cheatSheet.isHidden)
        panel.hide()
    }

    func testArrowKeysWrapAndEnterNavigationMode() async {
        let panel = makePanel()
        panel.show(scope: nil, query: "alpha")
        await waitForRows(panel)
        let count = panel.rows.count
        XCTAssertGreaterThan(count, 1)
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(panel.selectedIndex, count - 1)
        XCTAssertTrue(panel.navigationMode)
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(panel.selectedIndex, 0)
        panel.hide()
    }

    func testScopeChipAndBackspaceRemovesIt() async {
        let panel = makePanel()
        panel.show(scope: "/Users/demo/Developer/ferret/sub dir", query: "")
        XCTAssertFalse(panel.chip.isHidden)
        XCTAssertEqual(panel.chip.toolTip, "/Users/demo/Developer/ferret/sub dir")
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.deleteBackward(_:))))
        XCTAssertNil(panel.scope)
        XCTAssertTrue(panel.chip.isHidden)
        panel.hide()
    }

    func testEscClearsThenHides() async {
        let panel = makePanel()
        panel.show(scope: nil, query: "alpha")
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(panel.field.stringValue, "")
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertFalse(panel.isVisible)
    }

    func testPanelGeometry() {
        XCTAssertEqual(SearchPanel.height(rows: 0), 78)
        XCTAssertEqual(SearchPanel.height(rows: 20), 56 + 9 * 44 + 22)
        let panel = makePanel()
        XCTAssertEqual(panel.window.frame.width, 680)
        XCTAssertTrue(panel.window.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.window.level, .floating)
        XCTAssertTrue(panel.window.canBecomeKey)
    }
}
