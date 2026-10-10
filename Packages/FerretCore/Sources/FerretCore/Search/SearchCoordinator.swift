import Foundation

public struct ResultRow: Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let parent: String
    public let kind: HitKind
    public let size: UInt64?
    public let mtime: Date?
    public let snippet: String?
    public let extraMatches: Int

    public init(path: String, kind: HitKind, size: UInt64?, mtime: Date?, snippet: String? = nil, extraMatches: Int = 0) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        self.name = url.lastPathComponent
        self.parent = url.deletingLastPathComponent().path
        self.kind = kind
        self.size = size
        self.mtime = mtime
        self.snippet = snippet
        self.extraMatches = extraMatches
    }
}

public struct ResultSet: Equatable, Sendable {
    public let query: String
    public let rows: [ResultRow]
    public let tookUs: UInt64
    public let truncated: Bool
    public let partial: Bool
    public let contentPending: Int

    public init(query: String, rows: [ResultRow], tookUs: UInt64, truncated: Bool = false, partial: Bool = false, contentPending: Int = 0) {
        self.query = query
        self.rows = rows
        self.tookUs = tookUs
        self.truncated = truncated
        self.partial = partial
        self.contentPending = contentPending
    }
}

/// Latest-wins search driver (SPEC §4.5). Name queries are never debounced; content queries wait 120 ms.
@MainActor
public final class SearchCoordinator {
    public enum State: Equatable {
        case idle
        case indexing(DaemonStatus?)
        case results(ResultSet)
        case hint(String, keeping: ResultSet?)
        case daemonDown(String)

        public var isTerminal: Bool { true }
    }

    public static let emptyPatternHint = "type a pattern after grep:"

    public var onChange: ((State) -> Void)?
    public private(set) var state: State = .idle {
        didSet { onChange?(state) }
    }
    public private(set) var sendCount = 0

    public var backend: SearchBackend
    private let settings: SettingsStore
    private let clock: any Clock<Duration>
    private let contentDebounce: Duration
    private let indexingPoll: Duration

    private var currentText = ""
    private var currentScope: String?
    private var inFlight = false
    private var pending: (String, String?)?
    private var debounceTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var lastResults: ResultSet?

    public init(
        backend: SearchBackend,
        settings: SettingsStore,
        clock: any Clock<Duration> = ContinuousClock(),
        contentDebounce: Duration = .milliseconds(120),
        indexingPoll: Duration = .seconds(1)
    ) {
        self.backend = backend
        self.settings = settings
        self.clock = clock
        self.contentDebounce = contentDebounce
        self.indexingPoll = indexingPoll
    }

    public var currentQuery: String { currentText }
    public var scope: String? { currentScope }
    public var rows: [ResultRow] {
        switch state {
        case .results(let set): return set.rows
        case .hint(_, let keeping): return keeping?.rows ?? []
        default: return []
        }
    }

    public func update(text: String, scope: String?) {
        let normalized = QueryText.normalized(text)
        currentText = normalized
        currentScope = scope
        debounceTask?.cancel()
        debounceTask = nil
        indexingTask?.cancel()
        indexingTask = nil
        guard !normalized.isEmpty else {
            pending = nil
            state = .idle
            return
        }
        if QueryText.isContent(normalized) {
            guard QueryText.isSendable(normalized) else {
                pending = nil
                state = .hint(Self.emptyPatternHint, keeping: lastResults)
                return
            }
            let clock = clock
            let delay = contentDebounce
            debounceTask = Task { [weak self] in
                do { try await clock.sleep(for: delay) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.enqueue(normalized, scope)
            }
        } else {
            enqueue(normalized, scope)
        }
    }

    /// Re-sends the current query (used by the indexing poll and after a daemon restart).
    public func refresh() {
        guard !currentText.isEmpty else { return }
        enqueue(currentText, currentScope)
    }

    private func enqueue(_ text: String, _ scope: String?) {
        if inFlight {
            pending = (text, scope)
            return
        }
        send(text, scope)
    }

    private func send(_ text: String, _ scope: String?) {
        inFlight = true
        sendCount += 1
        let excluded = settings.excludedPaths
        let showHidden = settings.showHiddenFiles
        let userLimit = settings.resultLimit
        let limit = ResultFilter.requestLimit(userLimit: userLimit, excluded: excluded, showHidden: showHidden)
        let request = FSearchClient.SearchRequest(text: text, scope: scope, limit: limit)
        let backend = backend
        Task { [weak self] in
            let outcome: Result<ResultSet, Error>
            do {
                let payload = try await backend.search(request)
                outcome = .success(Self.map(payload, query: text, userLimit: userLimit, excluded: excluded, showHidden: showHidden, scope: scope))
            } catch {
                outcome = .failure(error)
            }
            self?.complete(text: text, scope: scope, outcome: outcome)
        }
    }

    private func complete(text: String, scope: String?, outcome: Result<ResultSet, Error>) {
        inFlight = false
        let isCurrent = text == currentText && scope == currentScope
        if isCurrent {
            switch outcome {
            case .success(let set):
                lastResults = set
                state = .results(set)
            case .failure(let error):
                apply(error)
            }
        }
        if let next = pending {
            pending = nil
            send(next.0, next.1)
        }
    }

    private func apply(_ error: Error) {
        switch error as? FSearchError {
        case .indexing?:
            state = .indexing(nil)
            scheduleIndexingPoll()
        case .server(let message)?:
            state = .hint(message, keeping: lastResults)
        case let other?:
            state = .daemonDown(String(describing: other))
        case nil:
            state = .daemonDown(error.localizedDescription)
        }
    }

    private func scheduleIndexingPoll() {
        indexingTask?.cancel()
        let clock = clock
        let interval = indexingPoll
        indexingTask = Task { [weak self] in
            do { try await clock.sleep(for: interval) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if case .indexing = self.state { self.refresh() }
        }
    }

    nonisolated static func map(_ payload: SearchPayload, query: String, userLimit: Int, excluded: [String], showHidden: Bool, scope: String?) -> ResultSet {
        let limit = ResultFilter.clampUserLimit(userLimit)
        switch payload {
        case .names(let hits, let tookUs):
            var rows: [ResultRow] = []
            for hit in hits where ResultFilter.keeps(path: hit.path, excluded: excluded, showHidden: showHidden, scope: scope) {
                if rows.count == limit { break }
                rows.append(ResultRow(
                    path: hit.path,
                    kind: hit.kind ?? .other,
                    size: hit.size,
                    mtime: hit.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ))
            }
            return ResultSet(query: query, rows: rows, tookUs: tookUs, truncated: hits.count >= limit)
        case .content(let files, let tookUs, let complete, _, let pendingCount):
            var rows: [ResultRow] = []
            for file in files where ResultFilter.keeps(path: file.path, excluded: excluded, showHidden: showHidden, scope: scope) {
                if rows.count == limit { break }
                let first = file.matches.first
                let snippet = first.map { "L\($0.line): \(Self.trimSnippet($0.text))" }
                rows.append(ResultRow(path: file.path, kind: .file, size: nil, mtime: nil, snippet: snippet, extraMatches: max(file.matches.count - 1, 0)))
            }
            return ResultSet(query: query, rows: rows, tookUs: tookUs, truncated: files.count >= limit, partial: !complete, contentPending: pendingCount)
        }
    }

    nonisolated static func trimSnippet(_ text: String, max: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }
}
