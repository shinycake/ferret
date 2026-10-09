import Foundation
import Observation

/// `ferret.` keys in UserDefaults. Result limit is clamped to 10...500.
@MainActor
@Observable
public final class SettingsStore {
    public static let limitKey = "ferret.resultLimit"
    public static let showHiddenKey = "ferret.showHidden"
    public static let excludedPathsKey = "ferret.excludedPaths"
    public static let launchAtLoginKey = "ferret.launchAtLogin"
    public static let defaultResultLimit = 50
    public static let exclusionCopy = "Hidden from results. fsearch still indexes these."

    @ObservationIgnored private let defaults: UserDefaults

    public var resultLimit: Int {
        didSet { writeLimit() }
    }

    public var showHiddenFiles: Bool {
        didSet { defaults.set(showHiddenFiles, forKey: Self.showHiddenKey) }
    }

    public var excludedPaths: [String] {
        didSet { defaults.set(excludedPaths, forKey: Self.excludedPathsKey) }
    }

    public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Self.launchAtLoginKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.limitKey) == nil {
            self.resultLimit = Self.defaultResultLimit
        } else {
            self.resultLimit = ResultFilter.clampUserLimit(defaults.integer(forKey: Self.limitKey))
        }
        self.showHiddenFiles = defaults.bool(forKey: Self.showHiddenKey)
        self.excludedPaths = defaults.stringArray(forKey: Self.excludedPathsKey) ?? []
        self.launchAtLogin = defaults.bool(forKey: Self.launchAtLoginKey)
    }

    public func addExcluded(_ path: String) {
        let trimmed = (path.hasSuffix("/") && path.count > 1) ? String(path.dropLast()) : path
        guard !trimmed.isEmpty, !excludedPaths.contains(trimmed) else { return }
        excludedPaths.append(trimmed)
    }

    public func removeExcluded(at index: Int) {
        guard excludedPaths.indices.contains(index) else { return }
        excludedPaths.remove(at: index)
    }

    /// Over-fetches when exclusions or the hidden-file filter are active.
    public var requestLimit: Int {
        ResultFilter.requestLimit(
            userLimit: resultLimit,
            excluded: excludedPaths,
            showHidden: showHiddenFiles
        )
    }

    private func writeLimit() {
        let clamped = ResultFilter.clampUserLimit(resultLimit)
        if resultLimit != clamped {
            resultLimit = clamped
            return
        }
        defaults.set(clamped, forKey: Self.limitKey)
    }
}

public struct AboutSnapshot: Equatable, Sendable {
    public var marketingVersion: String
    public var gitSHA: String
    public var fsearchPin: String
    public var daemonSummary: String
    public var fullDiskAccess: Bool

    public init(
        marketingVersion: String,
        gitSHA: String,
        fsearchPin: String,
        daemonSummary: String,
        fullDiskAccess: Bool
    ) {
        self.marketingVersion = marketingVersion
        self.gitSHA = gitSHA
        self.fsearchPin = fsearchPin
        self.daemonSummary = daemonSummary
        self.fullDiskAccess = fullDiskAccess
    }
}

public protocol SettingsSearchBackend: Sendable {
    func search(limit: Int) async
}

@MainActor
public final class SettingsModel {
    public static let reindexConfirmation = "This rebuilds the index shared with the fsearch CLI."

    public let store: SettingsStore
    public var confirm: (String) -> Bool
    public var performReindex: () -> Void
    public var backend: (any SettingsSearchBackend)?

    public init(
        store: SettingsStore,
        confirm: @escaping (String) -> Bool,
        performReindex: @escaping () -> Void,
        backend: (any SettingsSearchBackend)? = nil
    ) {
        self.store = store
        self.confirm = confirm
        self.performReindex = performReindex
        self.backend = backend
    }

    public func requestReindex() {
        guard confirm(Self.reindexConfirmation) else { return }
        performReindex()
    }

    public func sendSearch() async {
        guard let backend else { return }
        await backend.search(limit: store.requestLimit)
    }
}
