import Foundation

/// Menu-bar status fed by a health stream. A fake stream drives tests; the launch daemon feeds the live item.
enum ShellHealth: Equatable, Sendable {
    case starting
    case indexing(String?)
    case ready(String)
    case failed(String)
    case stopped

    var menuTitle: String {
        switch self {
        case .starting:
            return "Starting…"
        case .indexing(let detail):
            if let detail, !detail.isEmpty {
                return detail
            }
            return "Indexing…"
        case .ready(let summary):
            return summary
        case .failed(let message):
            return message
        case .stopped:
            return "Stopped"
        }
    }
}
