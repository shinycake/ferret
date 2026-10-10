import Foundation
import XCTest
@testable import FerretCore

actor RecordingBackend: SearchBackend {
    var requests: [FSearchClient.SearchRequest] = []
    var delay: Duration = .milliseconds(30)
    var failNext: FSearchError?

    func setFail(_ e: FSearchError?) { failNext = e }

    func search(_ request: FSearchClient.SearchRequest) async throws -> SearchPayload {
        requests.append(request)
        try await Task.sleep(for: delay)
        if let e = failNext { failNext = nil; throw e }
        if QueryText.isContent(request.text) {
            return .content(files: [GrepFile(path: "/x/\(request.text)", matches: [GrepLine(line: 3, text: "  hit  "), GrepLine(line: 9, text: "b")])], tookUs: 9, complete: false, fromIndex: true, pending: 2)
        }
        return .names(hits: [Hit(path: "/r/\(request.text)", kind: .file, size: 10, mtime: 1), Hit(path: "/r/.hidden/\(request.text)", kind: .file)], tookUs: 7)
    }

    func status() async throws -> DaemonStatus { DaemonStatus() }
}

@MainActor
final class CoordinatorTests: XCTestCase {
    private func settings() -> SettingsStore {
        let name = "coord.\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: name)!)
    }

    private func waitFor(_ c: SearchCoordinator, timeout: TimeInterval = 3, _ predicate: (SearchCoordinator.State) -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(c.state), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testRapidUpdatesSendAtMostTwiceAndLatestWins() async {
        let backend = RecordingBackend()
        let c = SearchCoordinator(backend: backend, settings: settings())
        for text in ["a", "al", "alp", "alph", "alpha"] { c.update(text: text, scope: nil) }
        await waitFor(c) { if case .results(let s) = $0 { return s.query == "alpha" }; return false }
        let sent = await backend.requests.map(\.text)
        XCTAssertEqual(sent, ["a", "alpha"])
        XCTAssertEqual(c.rows.map(\.path), ["/r/alpha"]) // hidden filtered by default
    }

    func testContentQueriesAreDebounced() async throws {
        let backend = RecordingBackend()
        let c = SearchCoordinator(backend: backend, settings: settings(), contentDebounce: .milliseconds(120))
        c.update(text: "grep:a", scope: nil)
        c.update(text: "grep:ab", scope: nil)
        try await Task.sleep(for: .milliseconds(60))
        let early = await backend.requests.count
        XCTAssertEqual(early, 0)
        await waitFor(c) { if case .results = $0 { return true }; return false }
        let sent = await backend.requests.map(\.text)
        XCTAssertEqual(sent, ["grep:ab"])
        guard case .results(let set) = c.state else { return XCTFail() }
        XCTAssertEqual(set.rows.first?.snippet, "L3: hit")
        XCTAssertEqual(set.rows.first?.extraMatches, 1)
        XCTAssertTrue(set.partial)
        XCTAssertEqual(set.contentPending, 2)
    }

    func testErrorsKeepPreviousRows() async {
        let backend = RecordingBackend()
        let c = SearchCoordinator(backend: backend, settings: settings())
        c.update(text: "size", scope: nil)
        await waitFor(c) { if case .results = $0 { return true }; return false }
        await backend.setFail(.server("bad range >"))
        c.update(text: "size:>", scope: nil)
        await waitFor(c) { if case .hint = $0 { return true }; return false }
        guard case .hint(let msg, let keeping) = c.state else { return XCTFail("\(c.state)") }
        XCTAssertEqual(msg, "bad range >")
        XCTAssertEqual(keeping?.rows.map(\.path), ["/r/size"])
    }

    func testEmptyGrepPatternIsAHintAndNotSent() async {
        let backend = RecordingBackend()
        let c = SearchCoordinator(backend: backend, settings: settings())
        c.update(text: "ext:rs grep:", scope: nil)
        XCTAssertEqual(c.state, .hint(SearchCoordinator.emptyPatternHint, keeping: nil))
        let count = await backend.requests.count
        XCTAssertEqual(count, 0)
    }

    func testIndexingState() async {
        let c = SearchCoordinator(backend: FixtureBackend(mode: .indexing), settings: settings(), indexingPoll: .milliseconds(50))
        c.update(text: "alpha", scope: nil)
        await waitFor(c) { if case .indexing = $0 { return true }; return false }
        XCTAssertEqual(c.state, .indexing(nil))
    }

    func testOverFetchWhenFiltersActive() async {
        let backend = RecordingBackend()
        let store = settings()
        store.resultLimit = 20
        store.showHiddenFiles = false
        let c = SearchCoordinator(backend: backend, settings: store)
        c.update(text: "x", scope: "/scope")
        await waitFor(c) { if case .results = $0 { return true }; return false }
        let req = await backend.requests.first
        XCTAssertEqual(req?.limit, 60)
        XCTAssertEqual(req?.scope, "/scope")
    }

    func testFixtureBackendFuzzyTypoAndFilters() async throws {
        let f = FixtureBackend(root: "/Users/demo")
        func names(_ q: String, scope: String? = nil) async throws -> [String] {
            guard case .names(let hits, _) = try await f.search(.init(text: q, scope: scope, limit: 50)) else { return [] }
            return hits.map { ($0.path as NSString).lastPathComponent }
        }
        let fuzzy = try await names("alpha rep")
        XCTAssertEqual(fuzzy.first, "alpha-report.pdf")
        let typo = try await names("mian.rs")
        XCTAssertEqual(typo, ["main.rs"])
        let big = try await names("size:>5mb")
        XCTAssertEqual(big, ["big.bin"])
        let scoped = try await names("alpha", scope: "/Users/demo/Developer/ferret/sub dir")
        XCTAssertEqual(scoped, ["alpha-sketch.png"])
        do {
            _ = try await f.search(.init(text: "size:>", limit: 50))
            XCTFail()
        } catch let e as FSearchError {
            XCTAssertEqual(e, .server("bad range >"))
        }
    }
}
