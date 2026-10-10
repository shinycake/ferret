import CoreGraphics
import Foundation
import XCTest
@testable import FerretCore

final class FinderDockTests: XCTestCase {
    private func entry(pid: Int32, layer: Int, x: Double, y: Double, w: Double, h: Double, id: UInt32) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowBounds as String: CGRect(x: x, y: y, width: w, height: h).dictionaryRepresentation as NSDictionary,
        ]
    }

    func testFrontWindowSkipsOtherOwnersLayersAndTinyWindows() {
        let list = [
            entry(pid: 9, layer: 0, x: 0, y: 0, w: 800, h: 600, id: 1),     // other app in front
            entry(pid: 42, layer: 25, x: 0, y: 0, w: 800, h: 30, id: 2),    // Finder menu-ish layer
            entry(pid: 42, layer: 0, x: 0, y: 0, w: 50, h: 50, id: 3),      // tiny
            entry(pid: 42, layer: 0, x: 100, y: 80, w: 900, h: 600, id: 4), // the one
            entry(pid: 42, layer: 0, x: 10, y: 10, w: 900, h: 600, id: 5),
        ]
        XCTAssertEqual(FinderDock.frontWindow(in: list, pid: 42)?.windowID, 4)
        XCTAssertEqual(FinderDock.frontWindow(in: list, pid: 42)?.bounds, CGRect(x: 100, y: 80, width: 900, height: 600))
        XCTAssertNil(FinderDock.frontWindow(in: list, pid: 7))
    }

    func testCoordinateConversionAndDockOrigin() {
        let cocoa = FinderDock.cocoaRect(fromQuartz: CGRect(x: 100, y: 80, width: 900, height: 600), primaryHeight: 1000)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 320, width: 900, height: 600))
        let dock = FinderDock.dockOrigin(finderCocoaFrame: cocoa)
        XCTAssertEqual(dock.width, 340)
        XCTAssertEqual(dock.topLeft.x, 100 + 900 - 10 - 340)
        XCTAssertEqual(dock.topLeft.y, 920 - 52)
        let narrow = FinderDock.dockOrigin(finderCocoaFrame: CGRect(x: 0, y: 0, width: 300, height: 400))
        XCTAssertEqual(narrow.width, 280)
    }

    func testPluginkitParsing() {
        let id = ExtensionStatus.bundleID
        XCTAssertEqual(ExtensionStatus.parse(pluginkitOutput: "+    \(id)(1.0)\n"), .enabled)
        XCTAssertEqual(ExtensionStatus.parse(pluginkitOutput: "-    \(id)(1.0)\n"), .disabled)
        XCTAssertEqual(ExtensionStatus.parse(pluginkitOutput: "     \(id)(1.0)\n"), .disabled)
        XCTAssertEqual(ExtensionStatus.parse(pluginkitOutput: ""), .notRegistered)
    }

    func testDockRouteRoundTrip() {
        let route = URLRoute.dock(scope: "/tmp")
        XCTAssertEqual(URLRoute(url: route.url), .dock(scope: "/tmp"))
        XCTAssertEqual(URLRoute(url: URL(string: "ferret://dock")!), .dock(scope: nil))
        XCTAssertEqual(URLRoute(url: URL(string: "ferret://dock?in=relative")!), .dock(scope: nil))
    }
}
