import XCTest
@testable import FerretCore

final class ResultFilterTests: XCTestCase {
    func testPrefixBoundary() {
        let excluded = ["/a/b"]
        XCTAssertFalse(ResultFilter.keeps(path: "/a/b", excluded: excluded, showHidden: true, scope: nil))
        XCTAssertFalse(ResultFilter.keeps(path: "/a/b/c", excluded: excluded, showHidden: true, scope: nil))
        XCTAssertTrue(ResultFilter.keeps(path: "/a/bc", excluded: excluded, showHidden: true, scope: nil))
        XCTAssertTrue(ResultFilter.keeps(path: "/a/b-extra", excluded: excluded, showHidden: true, scope: nil))
    }

    func testTrailingSlashExclusionMatchesTheDirectory() {
        XCTAssertFalse(ResultFilter.keeps(path: "/a/b/c", excluded: ["/a/b/"], showHidden: true, scope: nil))
    }

    func testHiddenComponentsAreBelowTheScopeRoot() {
        XCTAssertFalse(ResultFilter.keeps(path: "/scope/.secret/file", excluded: [], showHidden: false, scope: "/scope"))
        XCTAssertTrue(ResultFilter.keeps(path: "/scope/file", excluded: [], showHidden: false, scope: "/scope"))
        XCTAssertTrue(ResultFilter.keeps(path: "/scope/.hidden/file", excluded: [], showHidden: false, scope: "/scope/.hidden"))
        XCTAssertFalse(ResultFilter.keeps(path: "/scope/.hidden/.keep", excluded: [], showHidden: false, scope: "/scope/.hidden"))
        XCTAssertFalse(ResultFilter.keeps(path: "/tmp/.hidden/file", excluded: [], showHidden: false, scope: nil))
        XCTAssertTrue(ResultFilter.keeps(path: "/tmp/file", excluded: [], showHidden: false, scope: nil))
        XCTAssertTrue(ResultFilter.keeps(path: "/scope/.secret/file", excluded: [], showHidden: true, scope: "/scope"))
    }

    func testOverFetchAndTruncate() {
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 50, excluded: [], showHidden: true), 50)
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 50, excluded: [], showHidden: false), 150)
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 50, excluded: ["/secret"], showHidden: true), 150)
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 400, excluded: [], showHidden: false), 1000)
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 9, excluded: [], showHidden: true), 10)
        XCTAssertEqual(ResultFilter.requestLimit(userLimit: 900, excluded: [], showHidden: true), 500)

        let paths = (1...12).map { "/scope/file\($0)" }
        XCTAssertEqual(
            ResultFilter.apply(paths: paths, userLimit: 10, excluded: [], showHidden: true, scope: "/scope"),
            (1...10).map { "/scope/file\($0)" }
        )
    }
}
