import Foundation

public protocol SearchBackend: Sendable {
    func search(_ request: FSearchClient.SearchRequest) async throws -> SearchPayload
    func status() async throws -> DaemonStatus
}
