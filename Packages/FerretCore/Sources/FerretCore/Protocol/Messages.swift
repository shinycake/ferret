import Foundation

public enum Op: String, Codable, Sendable {
    case ping, status, save, search, grep
}

public enum GrepMode: String, Codable, Sendable {
    case literal, regex, symbol
}

public struct Request: Encodable, Sendable, Equatable {
    public var id: Int
    public var op: Op?
    public var q: String?
    public var scope: String?
    public var limit: Int?
    public var pattern: String?
    public var mode: GrepMode?
    public var perFile: Int?
    public var budgetMs: Int?

    public enum CodingKeys: String, CodingKey {
        case id, op, q, scope = "in", limit, pattern, mode
        case perFile = "per_file"
        case budgetMs = "budget_ms"
    }

    public init(
        id: Int,
        op: Op? = nil,
        q: String? = nil,
        scope: String? = nil,
        limit: Int? = nil,
        pattern: String? = nil,
        mode: GrepMode? = nil,
        perFile: Int? = nil,
        budgetMs: Int? = nil
    ) {
        self.id = id
        self.op = op
        self.q = q
        self.scope = scope
        self.limit = limit
        self.pattern = pattern
        self.mode = mode
        self.perFile = perFile
        self.budgetMs = budgetMs
    }

    /// Omits every nil field. A JSON null would be parsed upstream as the filter value `"null"`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(op, forKey: .op)
        try container.encodeIfPresent(q, forKey: .q)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(perFile, forKey: .perFile)
        try container.encodeIfPresent(budgetMs, forKey: .budgetMs)
    }
}

public enum HitKind: String, Decodable, Sendable, Hashable {
    case file, dir, link, other
}

public struct Hit: Decodable, Sendable, Hashable {
    public let path: String
    public let kind: HitKind?
    public let size: UInt64?
    public let mtime: UInt32?
    public let score: Int32?

    public init(path: String, kind: HitKind? = nil, size: UInt64? = nil, mtime: UInt32? = nil, score: Int32? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.mtime = mtime
        self.score = score
    }

    private enum CodingKeys: String, CodingKey {
        case path, kind, size, mtime, score
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        if let raw = try container.decodeIfPresent(String.self, forKey: .kind) {
            kind = HitKind(rawValue: raw)
        } else {
            kind = nil
        }
        size = try container.decodeIfPresent(UInt64.self, forKey: .size)
        mtime = try container.decodeIfPresent(UInt32.self, forKey: .mtime)
        score = try container.decodeIfPresent(Int32.self, forKey: .score)
    }
}

public struct GrepLine: Decodable, Sendable, Hashable {
    public let line: Int
    public let text: String

    public init(line: Int, text: String) {
        self.line = line
        self.text = text
    }
}

public struct GrepFile: Decodable, Sendable, Hashable {
    public let path: String
    public let matches: [GrepLine]

    public init(path: String, matches: [GrepLine]) {
        self.path = path
        self.matches = matches
    }
}

public struct DaemonStatus: Decodable, Sendable, Equatable {
    public let entries: Int?
    public let dirs: Int?
    public let overlay: Int?
    public let removed: Int?
    public let eventId: UInt64?
    public let indexBytes: Int?
    public let contentDocs: Int?
    public let contentSegments: Int?
    public let contentBytes: Int?
    public let contentPending: Int?
    public let fullDiskAccess: Bool?
    public let owner: Bool?

    public init(
        entries: Int? = nil,
        dirs: Int? = nil,
        overlay: Int? = nil,
        removed: Int? = nil,
        eventId: UInt64? = nil,
        indexBytes: Int? = nil,
        contentDocs: Int? = nil,
        contentSegments: Int? = nil,
        contentBytes: Int? = nil,
        contentPending: Int? = nil,
        fullDiskAccess: Bool? = nil,
        owner: Bool? = nil
    ) {
        self.entries = entries
        self.dirs = dirs
        self.overlay = overlay
        self.removed = removed
        self.eventId = eventId
        self.indexBytes = indexBytes
        self.contentDocs = contentDocs
        self.contentSegments = contentSegments
        self.contentBytes = contentBytes
        self.contentPending = contentPending
        self.fullDiskAccess = fullDiskAccess
        self.owner = owner
    }
}

/// One response line. Every field except `ok` is optional, and unknown keys are ignored.
public struct RawResponse: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let id: Int?
    public let error: String?
    public let tookUs: UInt64?
    public let hits: [Hit]?
    public let source: String?
    public let candidates: Int?
    public let read: Int?
    public let complete: Bool?
    public let indexing: Int?
    public let files: [GrepFile]?
    public let scheduled: Bool?

    public init(
        ok: Bool,
        id: Int? = nil,
        error: String? = nil,
        tookUs: UInt64? = nil,
        hits: [Hit]? = nil,
        source: String? = nil,
        candidates: Int? = nil,
        read: Int? = nil,
        complete: Bool? = nil,
        indexing: Int? = nil,
        files: [GrepFile]? = nil,
        scheduled: Bool? = nil
    ) {
        self.ok = ok
        self.id = id
        self.error = error
        self.tookUs = tookUs
        self.hits = hits
        self.source = source
        self.candidates = candidates
        self.read = read
        self.complete = complete
        self.indexing = indexing
        self.files = files
        self.scheduled = scheduled
    }

    public func searchPayload() throws -> SearchPayload {
        if let failure = FSearchError.from(response: self) {
            throw failure
        }
        if let files {
            return .content(
                files: files,
                tookUs: tookUs ?? 0,
                complete: complete ?? false,
                fromIndex: source == "index",
                pending: indexing ?? 0
            )
        }
        if let hits {
            return .names(hits: hits, tookUs: tookUs ?? 0)
        }
        throw FSearchError.badJSONResponse("response has neither hits nor files")
    }
}

public enum SearchPayload: Sendable, Equatable {
    case names(hits: [Hit], tookUs: UInt64)
    case content(files: [GrepFile], tookUs: UInt64, complete: Bool, fromIndex: Bool, pending: Int)
}

public enum FSearchError: Error, Equatable, Sendable {
    /// `ok: false` and `error` has the prefix `indexing`.
    case indexing
    case server(String)
    case badJSONResponse(String)
    case notConnected
    case socketPathTooLong
    case timeout
    case transportClosed
    /// Last lines of the daemon log.
    case daemonFailedToStart(String)
    case binaryMissing
    /// The operation is refused because this process does not own the daemon.
    case externalDaemon

    public static func from(response: RawResponse) -> FSearchError? {
        guard response.ok == false else { return nil }
        if let error = response.error, error.hasPrefix("indexing") {
            return .indexing
        }
        return .server(response.error ?? "")
    }
}

public enum FSearchJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func encodeRequest(_ request: Request) throws -> Data {
        try makeEncoder().encode(request)
    }

    public static func encodeRequestLine(_ request: Request) throws -> String {
        let data = try encodeRequest(request)
        guard let line = String(data: data, encoding: .utf8) else {
            throw FSearchError.badJSONResponse("request is not utf-8")
        }
        return line
    }

    public static func decodeResponse(_ data: Data) throws -> RawResponse {
        do {
            return try makeDecoder().decode(RawResponse.self, from: data)
        } catch let error as FSearchError {
            throw error
        } catch {
            throw FSearchError.badJSONResponse(String(describing: error))
        }
    }

    public static func decodeStatus(_ data: Data) throws -> DaemonStatus {
        do {
            return try makeDecoder().decode(DaemonStatus.self, from: data)
        } catch let error as FSearchError {
            throw error
        } catch {
            throw FSearchError.badJSONResponse(String(describing: error))
        }
    }
}
