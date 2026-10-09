import XCTest

final class AppLaunchTests: XCTestCase {
    func testHostBundleIsPresent() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
