import AppKit
import XCTest
@testable import Ferret

@MainActor
final class StatusMenuTests: XCTestCase {
    func testMenuItemTitlesAndHotkey() {
        let (controller, _) = makeController()
        let line = controller.menuDumpLine
        logLine("MENU_TITLES: \(line)")
        XCTAssertEqual(
            controller.menuItemTitles.filter { !$0.isEmpty },
            ["Search…", "Setup…", "Settings…", "Reindex…", "Starting…", "Open Logs", "Quit"]
        )
        XCTAssertEqual(controller.searchItem.keyEquivalent, " ")
        XCTAssertTrue(controller.searchItem.keyEquivalentModifierMask.contains(.option))
        XCTAssertFalse(controller.searchItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(line.contains("Search… [⌥Space]"))
    }

    func testStatusLineUpdatesFromHealthStream() async {
        let (controller, continuation) = makeController()
        XCTAssertEqual(controller.statusTitle, "Starting…")

        continuation.yield(.indexing(nil))
        await waitUntil(controller, title: "Indexing…")

        continuation.yield(.indexing("Scanning your disk…"))
        await waitUntil(controller, title: "Scanning your disk…")

        continuation.yield(.ready("7.7M items · FDA ✓"))
        await waitUntil(controller, title: "7.7M items · FDA ✓")

        continuation.yield(.failed("Search engine restarting…"))
        await waitUntil(controller, title: "Search engine restarting…")
        logLine("MENU_TITLES: \(controller.menuDumpLine)")
    }

    func testLiveMenuContainsCommands() async {
        let deadline = Date().addingTimeInterval(5)
        while ferretAppDelegate.statusController == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let controller = try XCTUnwrap(ferretAppDelegate.statusController)
        let titles = controller.menuItemTitles.filter { !$0.isEmpty }
        logLine("LIVE_MENU_TITLES: \(titles.joined(separator: " | "))")
        XCTAssertTrue(titles.contains("Search…"))
        XCTAssertTrue(titles.contains("Setup…"))
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertTrue(titles.contains("Reindex…"))
        XCTAssertTrue(titles.contains("Open Logs"))
        XCTAssertTrue(titles.contains("Quit"))
    }

    func testNoDockIcon() {
        let bundle = Bundle(for: AppDelegate.self)
        let element = bundle.object(forInfoDictionaryKey: "LSUIElement")
        let isAgent = (element as? Bool) == true || (element as? NSNumber)?.boolValue == true || (element as? String) == "1"
        XCTAssertTrue(isAgent, "LSUIElement missing from \(bundle.bundlePath)")
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        logLine("DOCK: LSUIElement=true activationPolicy=accessory")
    }

    private func makeController() -> (StatusItemController, AsyncStream<ShellHealth>.Continuation) {
        var continuation: AsyncStream<ShellHealth>.Continuation!
        let stream = AsyncStream<ShellHealth> { continuation = $0 }
        let controller = StatusItemController(panel: PanelController(), health: stream, openLogs: {})
        return (controller, continuation)
    }

    private func waitUntil(_ controller: StatusItemController, title: String) async {
        let deadline = Date().addingTimeInterval(2)
        while controller.statusTitle != title, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.statusTitle, title)
    }
}
