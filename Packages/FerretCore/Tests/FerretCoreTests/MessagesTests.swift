import XCTest
@testable import FerretCore

final class MessagesTests: XCTestCase {
    private let goldenRequests: [(Request, String)] = [
        (Request(id: 1, op: .ping), #"{"id":1,"op":"ping"}"#),
        (Request(id: 2, op: .status), #"{"id":2,"op":"status"}"#),
        (Request(id: 3, op: .save), #"{"id":3,"op":"save"}"#),
        (Request(id: 4, q: "fsearch main", limit: 50), #"{"id":4,"limit":50,"q":"fsearch main"}"#),
        (
            Request(id: 5, q: "invoice ext:pdf mtime:<30d", scope: "/Users/idan/Documents", limit: 50),
            #"{"id":5,"in":"/Users/idan/Documents","limit":50,"q":"invoice ext:pdf mtime:<30d"}"#
        ),
        (Request(id: 6, q: "ext:rs grep:apply_dir", limit: 50), #"{"id":6,"limit":50,"q":"ext:rs grep:apply_dir"}"#),
        (
            Request(
                id: 7,
                op: .grep,
                scope: "~/Developer",
                limit: 50,
                pattern: "apply_dir",
                mode: .literal,
                perFile: 3,
                budgetMs: 150
            ),
            #"{"budget_ms":150,"id":7,"in":"~/Developer","limit":50,"mode":"literal","op":"grep","pattern":"apply_dir","per_file":3}"#
        ),
    ]

    func testGoldenEncodingOfSection33Requests() throws {
        XCTAssertEqual(goldenRequests.count, 7)
        for (request, golden) in goldenRequests {
            let line = try FSearchJSON.encodeRequestLine(request)
            XCTAssertEqual(line, golden)
            XCTAssertFalse(line.contains("null"), line)
        }
    }

    func testNilOptionalsAreOmitted() throws {
        let line = try FSearchJSON.encodeRequestLine(Request(id: 42))
        XCTAssertEqual(line, #"{"id":42}"#)
        XCTAssertFalse(line.contains("null"))
        XCTAssertFalse(line.contains("\"op\""))
        XCTAssertFalse(line.contains("\"in\""))
        XCTAssertFalse(line.contains("per_file"))
        XCTAssertFalse(line.contains("budget_ms"))
    }

    func testAllFixturesDecode() throws {
        let lines = try fixtureLines()
        XCTAssertGreaterThanOrEqual(lines.count, 16)
        for (index, line) in lines.enumerated() {
            do {
                _ = try FSearchJSON.decodeResponse(Data(line.utf8))
            } catch {
                XCTFail("fixture line \(index) failed to decode: \(error)\n\(line)")
            }
        }
    }

    func testPingSaveAndIndexingShapes() throws {
        let ping = try decode(fixture(containing: #"{"ok":true,"id":1}"#))
        XCTAssertTrue(ping.ok)
        XCTAssertEqual(try XCTUnwrap(ping.id), 1)
        XCTAssertNil(FSearchError.from(response: ping))

        let save = try decode(fixture(containing: "\"scheduled\":true"))
        XCTAssertEqual(try XCTUnwrap(save.scheduled), true)
        XCTAssertEqual(try XCTUnwrap(save.id), 3)
        XCTAssertTrue(save.ok)

        let indexingLine = try fixture(containing: "indexing (first run scans the whole disk, ~20s)")
        let indexing = try decode(indexingLine)
        XCTAssertFalse(indexing.ok)
        XCTAssertEqual(try XCTUnwrap(indexing.id), 2)
        XCTAssertEqual(try XCTUnwrap(indexing.error), "indexing (first run scans the whole disk, ~20s)")
        XCTAssertEqual(FSearchError.from(response: indexing), .indexing)
    }

    func testReadyStatusShapeOmitsReadyAndDecodesFields() throws {
        let line = try fixture(containing: "\"full_disk_access\":true")
        XCTAssertFalse(line.contains("\"ready\""))
        let response = try decode(line)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(try XCTUnwrap(response.id), 2)
        XCTAssertNil(response.error)

        let status = try FSearchJSON.decodeStatus(Data(line.utf8))
        XCTAssertEqual(try XCTUnwrap(status.entries), 7_712_345)
        XCTAssertEqual(try XCTUnwrap(status.dirs), 812_345)
        XCTAssertEqual(try XCTUnwrap(status.overlay), 120)
        XCTAssertEqual(try XCTUnwrap(status.removed), 3)
        XCTAssertEqual(try XCTUnwrap(status.eventId), UInt64(123_456_789))
        XCTAssertEqual(try XCTUnwrap(status.indexBytes), 281_000_000)
        XCTAssertEqual(try XCTUnwrap(status.contentDocs), 90_000)
        XCTAssertEqual(try XCTUnwrap(status.contentSegments), 7)
        XCTAssertEqual(try XCTUnwrap(status.contentBytes), 120_000_000)
        XCTAssertEqual(try XCTUnwrap(status.contentPending), 0)
        XCTAssertEqual(try XCTUnwrap(status.fullDiskAccess), true)
        XCTAssertEqual(try XCTUnwrap(status.owner), true)
    }

    func testSearchHitsDecodeAndMapToPayload() throws {
        let response = try decode(try fixture(containing: "main.rs"))
        XCTAssertEqual(try XCTUnwrap(response.tookUs), UInt64(1312))
        XCTAssertEqual(try XCTUnwrap(response.id), 4)
        XCTAssertEqual(try XCTUnwrap(response.hits).count, 2)

        let first = try XCTUnwrap(response.hits?.first)
        XCTAssertEqual(first.path, "/Users/idan/Developer/fsearch/src/main.rs")
        XCTAssertEqual(try XCTUnwrap(first.kind), .file)
        XCTAssertEqual(try XCTUnwrap(first.size), UInt64(7421))
        XCTAssertEqual(try XCTUnwrap(first.mtime), UInt32(1_760_023_351))
        XCTAssertEqual(try XCTUnwrap(first.score), Int32(412))

        let second = try XCTUnwrap(response.hits?.dropFirst().first)
        XCTAssertEqual(second.path, "/Applications/Safari.app")
        XCTAssertEqual(try XCTUnwrap(second.kind), .link)
        XCTAssertEqual(try XCTUnwrap(second.size), UInt64(0))
        XCTAssertEqual(try XCTUnwrap(second.mtime), UInt32(1_759_000_000))
        XCTAssertEqual(try XCTUnwrap(second.score), Int32(390))

        let payload = try response.searchPayload()
        guard case .names(let hits, let tookUs) = payload else {
            return XCTFail("expected name hits, got \(payload)")
        }
        XCTAssertEqual(hits, try XCTUnwrap(response.hits))
        XCTAssertEqual(tookUs, UInt64(1312))
    }

    func testGrepShapeDecodesAndMapsToPayload() throws {
        let response = try decode(try fixture(containing: "apply_dir"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(try XCTUnwrap(response.id), 6)
        XCTAssertEqual(try XCTUnwrap(response.tookUs), UInt64(5600))
        XCTAssertEqual(try XCTUnwrap(response.source), "index")
        XCTAssertEqual(try XCTUnwrap(response.candidates), 812)
        XCTAssertEqual(try XCTUnwrap(response.read), 120)
        XCTAssertEqual(try XCTUnwrap(response.complete), true)
        XCTAssertEqual(try XCTUnwrap(response.indexing), 0)
        let decodedFiles = try XCTUnwrap(response.files)
        XCTAssertEqual(decodedFiles.count, 1)
        let decodedFile = try XCTUnwrap(decodedFiles.first)
        XCTAssertEqual(decodedFile.path, "/Users/idan/Developer/fsearch/src/walk.rs")
        XCTAssertEqual(decodedFile.matches.count, 1)
        let matchLine = try XCTUnwrap(decodedFile.matches.first)
        XCTAssertEqual(matchLine.line, 88)
        XCTAssertEqual(matchLine.text, "fn apply_dir(...) {")

        let payload = try response.searchPayload()
        guard case .content(let files, let tookUs, let complete, let fromIndex, let pending) = payload else {
            return XCTFail("expected content payload, got \(payload)")
        }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(tookUs, UInt64(5600))
        XCTAssertTrue(complete)
        XCTAssertTrue(fromIndex)
        XCTAssertEqual(pending, 0)
    }

    func testServerErrorsStayServerErrors() throws {
        let cases = [
            "bad range >",
            "unknown type im",
            "unknown kind x",
            "bad limit",
            "regex parse error: unclosed group",
        ]
        for message in cases {
            let response = try decode(try fixture(containing: message))
            XCTAssertFalse(response.ok)
            XCTAssertEqual(try XCTUnwrap(response.error), message)
            XCTAssertEqual(FSearchError.from(response: response), .server(message))
        }
    }

    func testNullIDUnknownFieldsAndMissingOptionals() throws {
        let badJSON = try decode(try fixture(containing: "bad json:"))
        XCTAssertFalse(badJSON.ok)
        XCTAssertNil(badJSON.id)
        XCTAssertTrue(badJSON.error?.hasPrefix("bad json:") == true)
        XCTAssertEqual(FSearchError.from(response: badJSON), .server("bad json: expected value at line 1 column 1"))

        let nullID = try decode(try fixture(where: { $0 == #"{"ok":true,"id":null}"# }))
        XCTAssertTrue(nullID.ok)
        XCTAssertNil(nullID.id)
        XCTAssertNil(nullID.error)
        XCTAssertNil(nullID.hits)
        XCTAssertNil(nullID.files)

        let extra = try decode(try fixture(containing: "unknown_field"))
        XCTAssertEqual(try XCTUnwrap(extra.id), 4)
        XCTAssertEqual(try XCTUnwrap(extra.tookUs), UInt64(1))
        XCTAssertEqual(try XCTUnwrap(extra.hits).count, 0)
        XCTAssertTrue(extra.ok)

        let bare = try decode(try fixture(where: { $0 == #"{"ok":true}"# }))
        XCTAssertTrue(bare.ok)
        XCTAssertNil(bare.id)
        XCTAssertNil(bare.error)
        XCTAssertNil(bare.hits)
        XCTAssertNil(bare.scheduled)
        XCTAssertThrowsError(try bare.searchPayload()) { error in
            guard case FSearchError.badJSONResponse = error else {
                return XCTFail("unexpected \(error)")
            }
        }

        let sparseHits = try XCTUnwrap(try decode(try fixture(containing: "/only/path")).hits)
        XCTAssertEqual(sparseHits.count, 4)
        XCTAssertNil(sparseHits[0].kind)
        XCTAssertNil(sparseHits[0].size)
        XCTAssertNil(sparseHits[0].mtime)
        XCTAssertNil(sparseHits[0].score)
        XCTAssertEqual(try XCTUnwrap(sparseHits[1].kind), .dir)
        XCTAssertEqual(try XCTUnwrap(sparseHits[2].kind), .other)
        XCTAssertEqual(try XCTUnwrap(sparseHits[2].size), UInt64(1))
        XCTAssertEqual(try XCTUnwrap(sparseHits[3].kind), .file)
        XCTAssertNil(sparseHits[3].size)
    }

    func testMalformedJSONBecomesBadJSONResponse() {
        XCTAssertThrowsError(try FSearchJSON.decodeResponse(Data("{".utf8))) { error in
            guard case FSearchError.badJSONResponse(let message) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
        XCTAssertThrowsError(try FSearchJSON.decodeResponse(Data(#"{"id":1}"#.utf8))) { error in
            guard case FSearchError.badJSONResponse = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testIndexingPrefixIsRequired() throws {
        let response = RawResponse(ok: false, id: 1, error: "reindexing soon")
        XCTAssertEqual(FSearchError.from(response: response), .server("reindexing soon"))
        let empty = try decode(try fixture(containing: #"{"ok":false,"error":"","id":null}"#))
        XCTAssertEqual(FSearchError.from(response: empty), .server(""))
        XCTAssertNotEqual(FSearchError.from(response: empty), .indexing)
    }

    private func fixtureLines() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/responses.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    private func fixture(containing needle: String) throws -> String {
        try fixture { $0.contains(needle) }
    }

    private func fixture(where matches: (String) -> Bool) throws -> String {
        let lines = try fixtureLines()
        guard let line = lines.first(where: matches) else {
            XCTFail("no fixture matched")
            throw FSearchError.badJSONResponse("missing fixture")
        }
        return line
    }

    private func decode(_ line: String) throws -> RawResponse {
        try FSearchJSON.decodeResponse(Data(line.utf8))
    }
}
