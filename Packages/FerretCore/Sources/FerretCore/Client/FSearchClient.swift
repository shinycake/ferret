import Foundation
import os

public actor FSearchClient: SearchBackend {
    public enum Lane: Sendable, Hashable {
        case interactive
        case content
    }

    public struct SearchRequest: Sendable, Equatable {
        public var text: String
        public var scope: String?
        public var limit: Int

        public init(text: String, scope: String? = nil, limit: Int) {
            self.text = text
            self.scope = scope
            self.limit = limit
        }
    }

    public let interactiveTimeout: Duration
    public let contentTimeout: Duration

    private let factory: any FSearchTransportFactory
    private var lanes: [Lane: LaneState] = [:]
    private var connectInFlight: Set<Lane> = []
    private var connectWaiters: [Lane: [CheckedContinuation<Void, Error>]] = [:]
    private let log = Logger(subsystem: "com.shinycake.ferret", category: "FSearchClient")

    public init(
        factory: any FSearchTransportFactory,
        interactiveTimeout: Duration = .seconds(2),
        contentTimeout: Duration = .seconds(5)
    ) {
        self.factory = factory
        self.interactiveTimeout = interactiveTimeout
        self.contentTimeout = contentTimeout
    }

    public func ping() async throws {
        await assertOffMain()
        let reply = try await perform(lane: .interactive, request: Request(id: 0, op: .ping))
        if let failure = FSearchError.from(response: reply.response) {
            throw failure
        }
    }

    public func status() async throws -> DaemonStatus {
        await assertOffMain()
        let reply = try await perform(lane: .interactive, request: Request(id: 0, op: .status))
        if let failure = FSearchError.from(response: reply.response) {
            throw failure
        }
        return try FSearchJSON.decodeStatus(reply.raw)
    }

    public func save() async throws {
        await assertOffMain()
        let reply = try await perform(lane: .interactive, request: Request(id: 0, op: .save))
        if let failure = FSearchError.from(response: reply.response) {
            throw failure
        }
    }

    public func search(_ request: SearchRequest) async throws -> SearchPayload {
        await assertOffMain()
        let content = QueryText.isContent(request.text)
        if content && !QueryText.isSendable(request.text) {
            throw FSearchError.server("type a pattern after grep:")
        }
        let lane: Lane = content ? .content : .interactive
        var message = Request(id: 0, q: request.text, scope: request.scope, limit: request.limit)
        if content {
            message.perFile = 3
            message.budgetMs = 150
        }
        let reply = try await perform(lane: lane, request: message)
        return try reply.response.searchPayload()
    }

    public func close() {
        for lane in [Lane.interactive, Lane.content] {
            retire(lane, error: FSearchError.transportClosed)
        }
    }

    func isLaneConnected(_ lane: Lane) -> Bool {
        guard let state = lanes[lane] else { return false }
        return state.transport != nil && !state.dead
    }

    private struct Reply: Sendable {
        var response: RawResponse
        var raw: Data
    }

    private struct LaneState {
        var transport: (any FSearchTransport)?
        var nextID = 1
        var waiters: [Int: CheckedContinuation<Reply, Error>] = [:]
        var timeouts: [Int: Task<Void, Never>] = [:]
        var dead = true
        var generation = 0
        var reader: Task<Void, Never>?
    }

    private func assertOffMain() async {
        if Thread.isMainThread {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume()
                }
            }
        }
        OffMain.precondition()
    }

    private func perform(lane: Lane, request: Request) async throws -> Reply {
        try await ensureConnected(lane)
        let id = allocateID(lane)
        var request = request
        request.id = id
        let line = try FSearchJSON.encodeRequest(request)
        let timeout = lane == .content ? contentTimeout : interactiveTimeout
        let generation = lanes[lane]?.generation ?? 0

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, Error>) in
            var state = lanes[lane] ?? LaneState()
            state.waiters[id] = continuation
            state.timeouts[id] = Task { [timeout] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                await self.timedOut(id: id, lane: lane, generation: generation)
            }
            lanes[lane] = state
            Task {
                await self.send(line, id: id, lane: lane, generation: generation)
            }
        }
    }

    private func send(_ line: Data, id: Int, lane: Lane, generation: Int) async {
        guard let transport = transportIfCurrent(lane, generation: generation) else {
            complete(id: id, lane: lane, result: .failure(FSearchError.notConnected))
            return
        }
        do {
            try await transport.send(line: line)
        } catch {
            retire(lane, error: error, generation: generation)
        }
    }

    private func ensureConnected(_ lane: Lane) async throws {
        if let state = lanes[lane], state.transport != nil, !state.dead {
            return
        }
        if connectInFlight.contains(lane) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var waiters = connectWaiters[lane] ?? []
                waiters.append(continuation)
                connectWaiters[lane] = waiters
            }
            guard let state = lanes[lane], state.transport != nil, !state.dead else {
                throw FSearchError.notConnected
            }
            return
        }
        connectInFlight.insert(lane)
        do {
            try await openLane(lane)
            connectInFlight.remove(lane)
            let waiters = connectWaiters.removeValue(forKey: lane) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        } catch {
            connectInFlight.remove(lane)
            let waiters = connectWaiters.removeValue(forKey: lane) ?? []
            for waiter in waiters {
                waiter.resume(throwing: error)
            }
            throw error
        }
    }

    private func openLane(_ lane: Lane) async throws {
        let transport = factory.makeTransport(lane: lane)
        do {
            try await transport.connect()
        } catch {
            var state = lanes[lane] ?? LaneState()
            state.dead = true
            state.transport = nil
            lanes[lane] = state
            throw error
        }
        var state = lanes[lane] ?? LaneState()
        state.generation += 1
        state.dead = false
        state.transport = transport
        let generation = state.generation
        lanes[lane] = state
        startReader(lane: lane, generation: generation, transport: transport)
    }

    private func startReader(lane: Lane, generation: Int, transport: any FSearchTransport) {
        let stream = transport.lines
        let reader = Task {
            do {
                for try await line in stream {
                    if Task.isCancelled { return }
                    await self.receive(line, lane: lane, generation: generation)
                }
                await self.retire(lane, error: FSearchError.transportClosed, generation: generation)
            } catch {
                await self.retire(lane, error: error, generation: generation)
            }
        }
        var state = lanes[lane] ?? LaneState()
        state.reader?.cancel()
        state.reader = reader
        lanes[lane] = state
    }

    private func receive(_ data: Data, lane: Lane, generation: Int) {
        guard lanes[lane]?.generation == generation, lanes[lane]?.dead == false else { return }
        let response: RawResponse
        do {
            response = try FSearchJSON.decodeResponse(data)
        } catch {
            failOldest(lane, error: error)
            return
        }
        guard let id = response.id else {
            log.debug("dropped response with null id")
            return
        }
        guard lanes[lane]?.waiters[id] != nil else {
            log.debug("dropped stale response id \(id, privacy: .public)")
            return
        }
        if let failure = FSearchError.from(response: response) {
            complete(id: id, lane: lane, result: .failure(failure))
        } else {
            complete(id: id, lane: lane, result: .success(Reply(response: response, raw: data)))
        }
    }

    private func timedOut(id: Int, lane: Lane, generation: Int) {
        guard lanes[lane]?.generation == generation, lanes[lane]?.waiters[id] != nil else { return }
        retire(lane, error: FSearchError.timeout, generation: generation)
    }

    private func retire(_ lane: Lane, error: Error, generation: Int? = nil) {
        guard var state = lanes[lane] else { return }
        if let generation {
            guard state.generation == generation, state.dead == false else { return }
        }
        let transport = state.transport
        let waiters = state.waiters
        let timeouts = state.timeouts
        state.waiters.removeAll()
        state.timeouts.removeAll()
        state.transport = nil
        state.dead = true
        state.generation += 1
        state.reader?.cancel()
        state.reader = nil
        lanes[lane] = state
        for task in timeouts.values {
            task.cancel()
        }
        transport?.close()
        for (_, continuation) in waiters {
            continuation.resume(throwing: error)
        }
    }

    private func complete(id: Int, lane: Lane, result: Result<Reply, Error>) {
        guard var state = lanes[lane] else { return }
        guard let continuation = state.waiters.removeValue(forKey: id) else { return }
        let timeout = state.timeouts.removeValue(forKey: id)
        lanes[lane] = state
        timeout?.cancel()
        continuation.resume(with: result)
    }

    private func failOldest(_ lane: Lane, error: Error) {
        guard let id = lanes[lane]?.waiters.keys.min() else {
            log.debug("dropped undecodable response with no waiter")
            return
        }
        complete(id: id, lane: lane, result: .failure(error))
    }

    private func allocateID(_ lane: Lane) -> Int {
        var state = lanes[lane] ?? LaneState()
        let id = state.nextID
        state.nextID += 1
        lanes[lane] = state
        return id
    }

    private func transportIfCurrent(_ lane: Lane, generation: Int) -> (any FSearchTransport)? {
        guard let state = lanes[lane], state.generation == generation, !state.dead else { return nil }
        return state.transport
    }
}

public protocol FSearchTransportFactory: Sendable {
    func makeTransport(lane: FSearchClient.Lane) -> any FSearchTransport
}
