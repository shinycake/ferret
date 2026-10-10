import AppKit
import XCTest
@testable import Ferret

@MainActor
final class URLRoutingTests: XCTestCase {
    override func setUp() async throws {
        ferretAppDelegate.panel.hide()
    }

    func testSearchURLWithApplicationsScopeShowsThatScope() throws {
        let url = try XCTUnwrap(URL(string: "ferret://search?in=/Applications"))
        ferretAppDelegate.handle(url: url)
        XCTAssertTrue(ferretAppDelegate.panel.isVisible)
        XCTAssertEqual(ferretAppDelegate.panel.scope, "/Applications")
    }

    func testRelativeScopeShowsPanelWithNoScope() throws {
        let url = try XCTUnwrap(URL(string: "ferret://search?in=relative"))
        ferretAppDelegate.handle(url: url)
        XCTAssertTrue(ferretAppDelegate.panel.isVisible)
        XCTAssertNil(ferretAppDelegate.panel.scope)
    }
}
