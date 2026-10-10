import AppKit
import FerretCore
import Quartz
import XCTest
@testable import Ferret

@MainActor
final class QuickLookTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("qlfix-\(UUID().uuidString.prefix(6))")
        for entry in FixtureBackend(root: root.path).entries where entry.kind == .file && entry.path.hasPrefix(root.path) {
            let url = URL(fileURLWithPath: entry.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture \(url.lastPathComponent)\n".utf8).write(to: url)
        }
    }

    override func tearDown() async throws {
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared().orderOut(nil) }
        try? FileManager.default.removeItem(at: root)
    }

    private func makePanel() async -> PanelController {
        let defaults = UserDefaults(suiteName: "ql.tests.\(UUID().uuidString)")!
        let panel = PanelController(backend: FixtureBackend(root: root.path), settings: SettingsStore(defaults: defaults), demo: true)
        panel.show(scope: nil, query: "alpha")
        let deadline = Date().addingTimeInterval(3)
        while panel.rows.count < 2, Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        return panel
    }

    private func waitFor(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    private func spin(_ seconds: TimeInterval = 0.5) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testShiftSpaceShowsSelectedItemAndFollowsSelection() async throws {
        let panel = await makePanel()
        XCTAssertTrue(panel.handleKey(key(" ", code: 49, flags: .shift)))
        await spin()
        let ql = try XCTUnwrap(QLPreviewPanel.shared())
        XCTAssertTrue(ql.isVisible)
        XCTAssertEqual((ql.currentPreviewItem as? URL)?.path ?? (ql.currentPreviewItem as? NSURL)?.path, panel.selectedRow?.path)
        XCTAssertEqual(panel.quickLook.currentURL?.path, panel.rows[0].path)
        panel.moveSelection(by: 1)
        await spin(0.3)
        XCTAssertEqual(panel.quickLook.currentURL?.path, panel.rows[1].path)
        let item = (ql.currentPreviewItem as? URL)?.path ?? (ql.currentPreviewItem as? NSURL)?.path
        logLine("QL_CURRENT: \(item ?? "nil") selected=\(panel.rows[1].path)")
        XCTAssertEqual(item, panel.rows[1].path)
        panel.hide()
    }

    func testSpaceTogglesOnlyInNavigationMode() async {
        let panel = await makePanel()
        XCTAssertFalse(panel.navigationMode)
        XCTAssertFalse(panel.handleKey(key(" ", code: 49)), "space types into the query outside navigation mode")
        _ = panel.handle(command: #selector(NSResponder.moveDown(_:)))
        XCTAssertTrue(panel.navigationMode)
        XCTAssertTrue(panel.handleKey(key(" ", code: 49)))
        await waitFor { panel.quickLook.isVisible }
        XCTAssertTrue(panel.quickLook.isVisible)
        XCTAssertTrue(panel.handleKey(key("y", code: 16, flags: .command)))
        await waitFor { !panel.quickLook.isVisible }
        XCTAssertFalse(panel.quickLook.isVisible)
        panel.hide()
    }

    func testEscClosesQuickLookFirst() async {
        let panel = await makePanel()
        panel.quickLook.show()
        await spin()
        XCTAssertTrue(panel.quickLook.isVisible)
        XCTAssertTrue(panel.handle(command: #selector(NSResponder.cancelOperation(_:))))
        await spin(0.3)
        XCTAssertFalse(panel.quickLook.isVisible)
        XCTAssertEqual(panel.field.stringValue, "alpha")
        XCTAssertTrue(panel.isVisible)
        panel.hide()
    }

    func testPanelDoesNotHideWhenQuickLookTakesKey() async throws {
        let panel = await makePanel()
        panel.quickLook.show()
        await spin()
        let ql = try XCTUnwrap(QLPreviewPanel.shared())
        XCTAssertFalse(panel.shouldHideOnResign(newKey: ql))
        panel.quickLook.close()
        await spin(0.3)
        XCTAssertTrue(panel.shouldHideOnResign(newKey: nil))
        panel.hide()
    }
}
