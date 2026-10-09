import XCTest
@testable import FerretCore

final class URLRouteTests: XCTestCase {
    func testSettingsAndOnboardingRoundTrip() {
        XCTAssertEqual(URLRoute(url: URLRoute.settings.url), .settings)
        XCTAssertEqual(URLRoute(url: URLRoute.onboarding.url), .onboarding)
        XCTAssertEqual(URLRoute.settings.url.absoluteString, "ferret://settings")
        XCTAssertEqual(URLRoute.onboarding.url.absoluteString, "ferret://onboarding")
    }

    func testSearchRoundTripPreservesQueryAndExistingDirectory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ferret route \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = URLRoute.search(query: "alpha report", scope: dir.path)
        XCTAssertEqual(URLRoute(url: original.url), original)
    }

    func testRelativeOrMissingScopeIsDropped() {
        let relative = URLRoute.search(query: "q", scope: "relative").url
        XCTAssertEqual(URLRoute(url: relative), .search(query: "q", scope: nil))

        let missing = URLRoute.search(query: nil, scope: "/no/such/ferret/directory").url
        XCTAssertEqual(URLRoute(url: missing), .search(query: nil, scope: nil))
    }

    func testFileScopeIsDropped() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ferret-route-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let url = URLRoute.search(query: "q", scope: file.path).url
        XCTAssertEqual(URLRoute(url: url), .search(query: "q", scope: nil))
    }

    func testQueryIsTruncatedTo512Characters() {
        let long = String(repeating: "a", count: 600)
        let url = URLRoute.search(query: long, scope: nil).url
        XCTAssertEqual(URLRoute(url: url), .search(query: String(repeating: "a", count: 512), scope: nil))

        let exact = String(repeating: "b", count: 512)
        XCTAssertEqual(
            URLRoute(url: URLRoute.search(query: exact, scope: nil).url),
            .search(query: exact, scope: nil)
        )
    }

    func testUnknownHostIsNil() {
        XCTAssertNil(URLRoute(url: URL(string: "ferret://nope")!))
        XCTAssertNil(URLRoute(url: URL(string: "https://search")!))
        XCTAssertNil(URLRoute(url: URL(string: "ferret://")!))
    }
}
