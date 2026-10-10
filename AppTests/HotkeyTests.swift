import AppKit
import FerretCore
import KeyboardShortcuts
import XCTest
@testable import Ferret

@MainActor
final class HotkeyTests: XCTestCase {
    func testDefaultIsOptionSpace() throws {
        let shortcut = try XCTUnwrap(HotkeyService.defaultShortcut)
        XCTAssertEqual(shortcut.key, .space)
        XCTAssertEqual(shortcut.modifiers, [.option])
        logLine("HOTKEY_DEFAULT: \(shortcut)")
    }

    func testFireTogglesPanel() {
        let defaults = UserDefaults(suiteName: "hotkey.tests.\(UUID().uuidString)")!
        let panel = PanelController(backend: FixtureBackend(), settings: SettingsStore(defaults: defaults), demo: true)
        let service = HotkeyService(panel: panel)
        XCTAssertFalse(panel.isVisible)
        service.fire()
        XCTAssertTrue(panel.isVisible)
        service.fire()
        XCTAssertFalse(panel.isVisible)
    }
}
