import XCTest
@testable import FerretCore

final class ClientTests: XCTestCase {
    func testDefaultTimeoutsAreTwoAndFiveSeconds() async {
        let client = FSearchClient(factory: SocketPathFactory(path: "/tmp/unused-ferret.sock"))
        let interactive = await client.interactiveTimeout
        let content = await client.contentTimeout
        XCTAssertEqual(interactive, .seconds(2))
        XCTAssertEqual(content, .seconds(5))
    }

    func testPingStatusSaveAndSearchMatchIDs() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        let client = makeClient(server)
        defer { Task { await client.close() } }
        try await client.ping()
        let status = try await client.status()
        XCTAssertEqual(try XCTUnwrap(status.entries), 3)
        XCTAssertEqual(try XCTUnwrap(status.eventId), UInt64(9))
        XCTAssertEqual(try XCTUnwrap(status.owner), true)
        try await client.save()
        let payload = try await client.search(FSearchClient.SearchRequest(text: "alpha", scope: "/Users/idan/Documents", limit: 50))
        guard case .names(let hits, _) = payload else {
            return XCTFail("expected names, got \(payload)")
        }
        XCTAssertEqual(hits.first?.path, "/result/alpha")
        let objects = try jsonObjects(server.requests)
        XCTAssertEqual(objects.count, 4)
        XCTAssertEqual(objects.map { $0["id"] as? Int }, [1, 2, 3, 4])
        XCTAssertEqual(objects[0]["op"] as? String, "ping")
        XCTAssertEqual(objects[1]["op"] as? String, "status")
        XCTAssertEqual(objects[2]["op"] as? String, "save")
        XCTAssertEqual(objects[3]["q"] as? String, "alpha")
        XCTAssertEqual(objects[3]["in"] as? String, "/Users/idan/Documents")
        XCTAssertEqual(objects[3]["limit"] as? Int, 50)
        XCTAssertNil(objects[3]["op"])
        for request in server.requests {
            let text = String(decoding: request, as: UTF8.self)
            XCTAssertFalse(text.contains("null"), text)
        }
        print("ClientTests id-matching ids=\(objects.compactMap { $0["id"] as? Int })")
    }

    func testOutOfOrderResponsesStayMatchedToTheirIDs() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        server.behavior = .reorderPairs
        let client = makeClient(server)
        defer { Task { await client.close() } }
        async let first = client.search(FSearchClient.SearchRequest(text: "one", limit: 10))
        async let second = client.search(FSearchClient.SearchRequest(text: "two", limit: 10))
        let firstPayload = try await first
        let secondPayload = try await second
        guard case .names(let firstHits, _) = firstPayload, case .names(let secondHits, _) = secondPayload else {
            return XCTFail("expected name payloads")
        }
        XCTAssertEqual(firstHits.first?.path, "/result/one")
        XCTAssertEqual(secondHits.first?.path, "/result/two")
        let requestIDs = try jsonObjects(server.requests).compactMap { $0["id"] as? Int }
        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(server.responseIDs, [requestIDs[1], requestIDs[0]])
        print("ClientTests out-of-order responseIDs=\(server.responseIDs) requestIDs=\(requestIDs)")
    }

    func testStaleAndNullIDsAreDropped() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        server.behavior = .staleBeforeReal
        let client = makeClient(server)
        defer { Task { await client.close() } }
        let payload = try await client.search(FSearchClient.SearchRequest(text: "real", limit: 5))
        guard case .names(let hits, _) = payload else {
            return XCTFail("expected names")
        }
        XCTAssertEqual(hits.first?.path, "/result/real")
        XCTAssertEqual(server.responseIDs.first, 999_999)
        XCTAssertNotEqual(hits.first?.path, "/stale")
        print("ClientTests stale-id dropped responseIDs=\(server.responseIDs)")
    }

    func testLaneIsolationKeepsNameSearchUnder50ms() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        server.contentDelay = 1
        let client = makeClient(server, interactiveTimeout: .seconds(2), contentTimeout: .seconds(5))
        defer { Task { await client.close() } }
        let clock = ContinuousClock()
        let contentStarted = clock.now
        async let content = client.search(FSearchClient.SearchRequest(text: "grep:apply", limit: 10))
        let waitDeadline = clock.now.advanced(by: .seconds(2))
        while clock.now < waitDeadline {
            let sawContent = server.requests.contains { line in
                String(data: line, encoding: .utf8)?.contains("grep:") == true
            }
            if sawContent { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(server.requests.contains(where: { String(data: $0, encoding: .utf8)?.contains("grep:") == true }))
        let nameStarted = clock.now
        let name = try await client.search(FSearchClient.SearchRequest(text: "alpha", limit: 10))
        let nameDelay = nameStarted.duration(to: clock.now)
        guard case .names(let hits, _) = name else {
            return XCTFail("expected a name payload")
        }
        XCTAssertEqual(hits.first?.path, "/result/alpha")
        let contentPayload = try await content
        let contentDelay = contentStarted.duration(to: clock.now)
        guard case .content(let files, _, _, _, _) = contentPayload else {
            return XCTFail("expected content payload")
        }
        XCTAssertEqual(files.first?.path, "/tmp/grep")
        XCTAssertGreaterThanOrEqual(server.accepted, 2)
        let nameMS = milliseconds(nameDelay)
        let contentMS = milliseconds(contentDelay)
        print(String(format: "ClientTests lane-isolation name=%.2fms content=%.2fms accepted=%d", nameMS, contentMS, server.accepted))
        XCTAssertLessThan(nameDelay, .milliseconds(50), "name reply took \(nameMS)ms while a 1s grep was in flight")
        XCTAssertGreaterThan(contentDelay, .milliseconds(900))
        let contentRequest = try XCTUnwrap(jsonObjects(server.requests).first { $0["q"] as? String == "grep:apply" })
        XCTAssertEqual(contentRequest["per_file"] as? Int, 3)
        XCTAssertEqual(contentRequest["budget_ms"] as? Int, 150)
    }

    func testTimeoutMarksTheLaneDead() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        server.behavior = .silent
        let client = makeClient(server, interactiveTimeout: .milliseconds(200), contentTimeout: .seconds(5))
        defer { Task { await client.close() } }
        let clock = ContinuousClock()
        let started = clock.now
        do {
            try await client.ping()
            XCTFail("expected timeout")
        } catch FSearchError.timeout {
            let elapsed = milliseconds(started.duration(to: clock.now))
            print(String(format: "ClientTests timeout elapsed=%.2fms", elapsed))
            XCTAssertGreaterThan(elapsed, 150)
            XCTAssertLessThan(elapsed, 2000)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(await client.isLaneConnected(.interactive))
    }

    func testReconnectsOnceAfterThePeerCloses() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        let client = makeClient(server)
        defer { Task { await client.close() } }
        try await client.ping()
        XCTAssertEqual(server.accepted, 1)
        XCTAssertTrue(await client.isLaneConnected(.interactive))
        server.dropClients()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await client.isLaneConnected(.interactive), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(await client.isLaneConnected(.interactive))
        try await client.ping()
        XCTAssertEqual(server.accepted, 2)
        print("ClientTests reconnect accepted=\(server.accepted)")
    }

    func testFailedReconnectDoesNotLoop() async throws {
        let server = try FakeFSearchServer()
        let client = makeClient(server, interactiveTimeout: .milliseconds(300))
        defer { Task { await client.close() } }
        try await client.ping()
        let accepted = server.accepted
        server.stop()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await client.isLaneConnected(.interactive), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        do {
            try await client.ping()
            XCTFail("expected connect failure")
        } catch FSearchError.notConnected {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(server.accepted, accepted)
    }

    func testSocketPathTooLong() async throws {
        let direct = SocketTransport(path: String(repeating: "a", count: 110))
        do {
            try await direct.connect()
            XCTFail("expected socketPathTooLong")
        } catch FSearchError.socketPathTooLong {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let exactly104 = SocketTransport(path: String(repeating: "b", count: 104))
        do {
            try await exactly104.connect()
            XCTFail("expected socketPathTooLong")
        } catch FSearchError.socketPathTooLong {
        }
        let allowed = SocketTransport(path: "/" + String(repeating: "c", count: 102))
        do {
            try await allowed.connect()
            XCTFail("expected notConnected")
        } catch FSearchError.socketPathTooLong {
            XCTFail("103-byte path should be allowed")
        } catch FSearchError.notConnected {
        }
        let client = FSearchClient(factory: SocketPathFactory(path: String(repeating: "d", count: 110)))
        do {
            try await client.ping()
            XCTFail("expected socketPathTooLong")
        } catch FSearchError.socketPathTooLong {
            print("ClientTests long-path threw socketPathTooLong")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyGrepPatternIsNotSent() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        let client = makeClient(server)
        defer { Task { await client.close() } }
        do {
            _ = try await client.search(FSearchClient.SearchRequest(text: "grep:", limit: 10))
            XCTFail("expected refusal")
        } catch FSearchError.server(let message) {
            XCTAssertEqual(message, "type a pattern after grep:")
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testIndexingErrorIsThrown() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        server.behavior = .indexingStatus
        let client = makeClient(server)
        defer { Task { await client.close() } }
        do {
            _ = try await client.status()
            XCTFail("expected indexing")
        } catch FSearchError.indexing {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSearchBackendUsesTheSameClient() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        let client = makeClient(server)
        defer { Task { await client.close() } }
        let backend: any SearchBackend = client
        let status = try await backend.status()
        XCTAssertEqual(try XCTUnwrap(status.dirs), 1)
        let payload = try await backend.search(FSearchClient.SearchRequest(text: "backend", limit: 4))
        guard case .names(let hits, _) = payload else {
            return XCTFail("expected names")
        }
        XCTAssertEqual(hits.first?.path, "/result/backend")
    }

    func testStdioTransportDecodesRealClientReplies() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("ferret-stdio-\(UUID().uuidString).pl")
        let source = """
        #!/usr/bin/perl
        use strict;
        use warnings;
        $| = 1;
        while (my $line = <STDIN>) {
            chomp $line;
            next if $line eq "";
            my ($id) = $line =~ /"id":(\\d+)/;
            if ($line =~ /"op":"ping"/) {
                print qq({"ok":true,"id":$id}\\n);
            } elsif ($line =~ /"op":"status"/) {
                print qq({"entries":4,"dirs":2,"overlay":0,"removed":0,"event_id":7,"index_bytes":8,"content_docs":0,"content_segments":0,"content_bytes":0,"content_pending":0,"full_disk_access":false,"owner":true,"ok":true,"id":$id}\\n);
            } elsif ($line =~ /"op":"save"/) {
                print qq({"ok":true,"scheduled":true,"id":$id}\\n);
            } else {
                my ($q) = $line =~ /"q":"([^"]*)"/;
                $q = "" unless defined $q;
                print qq({"ok":true,"took_us":5,"hits":[{"path":"/stdio/$q","kind":"file","size":2,"mtime":3,"score":4}],"id":$id}\\n);
            }
        }
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let client = FSearchClient(factory: StdioFactory(binary: script))
        defer { Task { await client.close() } }
        try await client.ping()
        let status = try await client.status()
        XCTAssertEqual(try XCTUnwrap(status.entries), 4)
        XCTAssertEqual(try XCTUnwrap(status.eventId), UInt64(7))
        let payload = try await client.search(FSearchClient.SearchRequest(text: "notes", limit: 8))
        guard case .names(let hits, _) = payload else {
            return XCTFail("expected names")
        }
        XCTAssertEqual(hits.first?.path, "/stdio/notes")
        print("ClientTests stdio decoded ping, status, and search")
    }

    func testDispatchPreconditionHoldsForClientCalls() async throws {
        let server = try FakeFSearchServer()
        defer { server.stop() }
        let client = makeClient(server)
        defer { Task { await client.close() } }
        try await client.ping()
        _ = try await client.status()
        print("ClientTests dispatchPrecondition held during ping and status")
    }

    private func makeClient(
        _ server: FakeFSearchServer,
        interactiveTimeout: Duration = .seconds(2),
        contentTimeout: Duration = .seconds(5)
    ) -> FSearchClient {
        FSearchClient(
            factory: SocketPathFactory(path: server.path),
            interactiveTimeout: interactiveTimeout,
            contentTimeout: contentTimeout
        )
    }

    private func jsonObjects(_ lines: [Data]) throws -> [[String: Any]] {
        try lines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

final class StdioFactory: FSearchTransportFactory, @unchecked Sendable {
    let binary: URL
    init(binary: URL) { self.binary = binary }
    func makeTransport(lane: FSearchClient.Lane) -> any FSearchTransport {
        StdioTransport(binary: binary, env: [:])
    }
}
