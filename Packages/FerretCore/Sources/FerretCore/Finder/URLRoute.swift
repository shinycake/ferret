import Foundation

/// `ferret://` routes. Parsing is the only validation step: a bad `in` is
/// dropped, and `q` is truncated. No route opens, reveals, or mutates files.
public enum URLRoute: Equatable {
    case search(query: String?, scope: String?)
    case settings
    case onboarding
    /// Docked Finder search (toolbar button). `in` is the Finder window's folder.
    case dock(scope: String?)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "ferret",
              let host = components.host?.lowercased()
        else {
            return nil
        }

        switch host {
        case "settings":
            self = .settings
        case "onboarding":
            self = .onboarding
        case "dock":
            let items = components.queryItems ?? []
            self = .dock(scope: Self.validatedScope(items.first { $0.name == "in" }?.value))
        case "search":
            let items = components.queryItems ?? []
            let query = Self.truncatedQuery(items.first { $0.name == "q" }?.value)
            let scope = Self.validatedScope(items.first { $0.name == "in" }?.value)
            self = .search(query: query, scope: scope)
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case let .search(query, scope):
            var components = URLComponents()
            components.scheme = "ferret"
            components.host = "search"
            var items: [URLQueryItem] = []
            if let scope {
                items.append(URLQueryItem(name: "in", value: scope))
            }
            if let query {
                items.append(URLQueryItem(name: "q", value: query))
            }
            if !items.isEmpty {
                components.queryItems = items
            }
            return components.url ?? URL(string: "ferret://search")!
        case .settings:
            return URL(string: "ferret://settings")!
        case .onboarding:
            return URL(string: "ferret://onboarding")!
        case let .dock(scope):
            var components = URLComponents()
            components.scheme = "ferret"
            components.host = "dock"
            if let scope { components.queryItems = [URLQueryItem(name: "in", value: scope)] }
            return components.url ?? URL(string: "ferret://dock")!
        }
    }

    /// `q` is truncated to 512 characters. A missing parameter stays nil.
    private static func truncatedQuery(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw.count > 512 {
            return String(raw.prefix(512))
        }
        return raw
    }

    /// `in` must be an absolute path to an existing directory. Anything else is dropped.
    private static func validatedScope(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: raw, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return raw
    }
}
