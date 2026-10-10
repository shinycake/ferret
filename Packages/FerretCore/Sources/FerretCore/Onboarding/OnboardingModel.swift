import Foundation
import Observation

/// The four setup steps. Probes and side effects are injected so tests and the
/// snapshot can drive FDA, indexing, the Finder extension, and login at launch.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Badge: Equatable, Sendable {
        case ok
        case warning
    }

    public enum Step: String, Hashable, Sendable {
        case fullDiskAccess
        case indexing
        case finderExtension
        case launchAtLogin
    }

    public enum Login: Equatable, Sendable {
        case off
        case on
        case requiresApproval
    }

    public enum Phase: Equatable, Sendable {
        case scanning
        case ready(items: Int, folders: Int, contentPending: Int)
        case failed(String)
    }

    public struct Health: Equatable, Sendable {
        public var phase: Phase
        public var externalWithoutFDA: Bool

        public init(phase: Phase, externalWithoutFDA: Bool) {
            self.phase = phase
            self.externalWithoutFDA = externalWithoutFDA
        }
    }

    public static let privacySettingsURL = FullDiskAccess.settingsURL
    public static let completedDefaultsKey = "ferret.hasCompletedOnboarding"
    public static let scanningDetail = "Scanning your disk… (first run ~20 s or more)"
    public static let fullDiskDetail = "Turn on Ferret (click + and choose /Applications/Ferret.app if it isn't listed)."
    public static let extensionDetail = "1. Click Turn On (or Open Extensions Settings and tick Ferret under File Providers / Finder extensions). 2. In Finder choose View → Customize Toolbar… and drag the Ferret magnifier into the toolbar. 3. Click it (or press the hotkey with Finder in front) to search the current folder."
    public static let hotkeyFooter = "Press ⌥Space anywhere to search"
    public static let externalDaemonWarningText = "Your fsearch CLI daemon doesn't have Full Disk Access. Grant it to ~/.local/bin/fsearch, or run fsearch uninstall so Ferret can run its own."

    public private(set) var fullDiskAccessGranted = false
    public private(set) var phase: Phase = .scanning
    public private(set) var extensionEnabled = false
    public private(set) var login: Login = .off
    public private(set) var externalDaemonWarning: String?
    public private(set) var skipped: Set<Step> = []

    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private var sampledAccess = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let isFullDiskAccessGranted: () -> Bool
    @ObservationIgnored private let health: () -> Health
    @ObservationIgnored private let isExtensionEnabled: () -> Bool
    @ObservationIgnored private let loginState: () -> Login
    @ObservationIgnored private let restartDaemon: () -> Void
    @ObservationIgnored private let applyLaunchAtLogin: (Bool) -> Void

    @ObservationIgnored public let openPrivacySettings: () -> Void
    @ObservationIgnored public let openExtensionManagement: () -> Void
    @ObservationIgnored public let openLoginItemsSettings: () -> Void

    public init(
        isFullDiskAccessGranted: @escaping () -> Bool,
        health: @escaping () -> Health,
        isExtensionEnabled: @escaping () -> Bool,
        loginState: @escaping () -> Login,
        restartDaemon: @escaping () -> Void,
        applyLaunchAtLogin: @escaping (Bool) -> Void = { _ in },
        openPrivacySettings: @escaping () -> Void = {},
        openExtensionManagement: @escaping () -> Void = {},
        openLoginItemsSettings: @escaping () -> Void = {}
    ) {
        self.isFullDiskAccessGranted = isFullDiskAccessGranted
        self.health = health
        self.isExtensionEnabled = isExtensionEnabled
        self.loginState = loginState
        self.restartDaemon = restartDaemon
        self.applyLaunchAtLogin = applyLaunchAtLogin
        self.openPrivacySettings = openPrivacySettings
        self.openExtensionManagement = openExtensionManagement
        self.openLoginItemsSettings = openLoginItemsSettings
        pollOnce()
    }

    /// FDA denied, index still scanning, extension off, login off.
    public static func snapshotFixture() -> OnboardingModel {
        OnboardingModel(
            isFullDiskAccessGranted: { false },
            health: { Health(phase: .scanning, externalWithoutFDA: false) },
            isExtensionEnabled: { false },
            loginState: { .off },
            restartDaemon: {}
        )
    }

    public static func shouldAutoShow(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["FERRET_DEMO"] == "1" { return false }
        return !defaults.bool(forKey: completedDefaultsKey)
    }

    public func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.completedDefaultsKey)
    }

    public func skip(_ step: Step) {
        skipped.insert(step)
        onChange?()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
        login = loginState()
        onChange?()
    }

    public func pollOnce() {
        let granted = isFullDiskAccessGranted()
        if sampledAccess, granted, !fullDiskAccessGranted {
            restartDaemon()
        }
        sampledAccess = true
        fullDiskAccessGranted = granted

        let snapshot = health()
        phase = snapshot.phase
        externalDaemonWarning = (granted && snapshot.externalWithoutFDA) ? Self.externalDaemonWarningText : nil
        extensionEnabled = isExtensionEnabled()
        login = loginState()
        onChange?()
    }

    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.pollOnce()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public var fullDiskBadge: Badge { fullDiskAccessGranted ? .ok : .warning }
    public var extensionBadge: Badge { extensionEnabled ? .ok : .warning }
    public var loginBadge: Badge { login == .on ? .ok : .warning }

    public var indexingBadge: Badge {
        if case .ready(_, _, 0) = phase { return .ok }
        return .warning
    }

    public var indexingDetail: String {
        switch phase {
        case .scanning:
            return Self.scanningDetail
        case .failed(let message):
            return message
        case .ready(let items, let folders, let pending):
            if pending > 0 {
                return "Indexing file contents… (\(Self.formatCount(pending)) folders pending)"
            }
            return "✓ \(Self.formatCount(items)) items in \(Self.formatCount(folders)) folders indexed"
        }
    }

    public static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
