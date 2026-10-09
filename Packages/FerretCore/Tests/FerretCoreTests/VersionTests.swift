import XCTest
@testable import FerretCore

final class VersionTests: XCTestCase {
    func testMarketingVersionIsSet() {
        XCTAssertEqual(FerretVersion.marketing, "0.1.0")
        XCTAssertFalse(FerretVersion.marketing.isEmpty)
    }
}
