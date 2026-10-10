import AppKit
import FerretCore
import XCTest
@testable import Ferret

@MainActor
final class DockedPanelTests: XCTestCase {
    func testDockedPanelSitsUnderToolbarAndTogglesScope() {
        let defaults = UserDefaults(suiteName: "ferret.dock.tests")!
        defaults.removePersistentDomain(forName: "ferret.dock.tests")
        let panel = PanelController(backend: FixtureBackend(root: "/Users/demo", mode: .normal),
                                    settings: SettingsStore(defaults: defaults), demo: true)
        let finder = NSRect(x: 100, y: 100, width: 900, height: 600)
        let dock = FinderDock.dockOrigin(finderCocoaFrame: finder)
        panel.showDocked(topLeft: dock.topLeft, width: dock.width, folder: "/Users/demo/Developer")
        XCTAssertTrue(panel.docked)
        XCTAssertEqual(panel.window.frame.maxY, finder.maxY - FinderDock.toolbarHeight, accuracy: 0.5)
        XCTAssertEqual(panel.window.frame.maxX, finder.maxX - FinderDock.rightInset, accuracy: 0.5)
        XCTAssertEqual(panel.window.frame.width, FinderDock.panelWidth, accuracy: 0.5)
        XCTAssertEqual(panel.scope, "/Users/demo/Developer")
        panel.scopeControl.selectedSegment = 1
        panel.scopeToggled()
        XCTAssertNil(panel.scope)
        XCTAssertTrue(panel.scopeIsThisMac)

        let moved = finder.offsetBy(dx: 40, dy: -30)
        let d2 = FinderDock.dockOrigin(finderCocoaFrame: moved)
        panel.followDock(topLeft: d2.topLeft, width: d2.width)
        XCTAssertEqual(panel.window.frame.maxX, moved.maxX - FinderDock.rightInset, accuracy: 0.5)
        panel.hide()
        panel.show(scope: nil)
        XCTAssertFalse(panel.docked)
        panel.hide()
    }
}
