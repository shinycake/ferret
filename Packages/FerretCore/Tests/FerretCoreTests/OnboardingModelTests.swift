import XCTest
@testable import FerretCore

@MainActor
final class OnboardingModelTests: XCTestCase {
    func testPrivacySettingsDeepLinkMatchesSpec() {
        XCTAssertEqual(
            FullDiskAccess.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        XCTAssertEqual(OnboardingModel.privacySettingsURL, FullDiskAccess.settingsURL)
        _ = FullDiskAccess.isGranted()
    }

    func testFDAFlipRestartsExactlyOnce() {
        var granted = false
        var restarts = 0
        let model = makeModel(granted: { granted }, restart: { restarts += 1 })
        XCTAssertEqual(restarts, 0)
        XCTAssertFalse(model.fullDiskAccessGranted)

        granted = true
        model.pollOnce()
        XCTAssertEqual(restarts, 1)
        XCTAssertTrue(model.fullDiskAccessGranted)

        model.pollOnce()
        XCTAssertEqual(restarts, 1)
    }

    func testAlreadyGrantedDoesNotRestart() {
        var restarts = 0
        let model = makeModel(granted: { true }, restart: { restarts += 1 })
        model.pollOnce()
        model.pollOnce()
        XCTAssertEqual(restarts, 0)
        XCTAssertTrue(model.fullDiskAccessGranted)
    }

    func testSnapshotFixtureShowsEveryWarningStep() {
        let model = OnboardingModel.snapshotFixture()
        XCTAssertFalse(model.fullDiskAccessGranted)
        XCTAssertEqual(model.phase, .scanning)
        XCTAssertFalse(model.extensionEnabled)
        XCTAssertEqual(model.login, .off)
        XCTAssertEqual(model.fullDiskBadge, .warning)
        XCTAssertEqual(model.indexingBadge, .warning)
        XCTAssertEqual(model.extensionBadge, .warning)
        XCTAssertEqual(model.loginBadge, .warning)
        XCTAssertEqual(model.indexingDetail, OnboardingModel.scanningDetail)
        XCTAssertNil(model.externalDaemonWarning)
    }

    func testExternalDaemonWarningWhenFerretHasFDA() {
        let warned = makeModel(
            granted: { true },
            health: OnboardingModel.Health(phase: .scanning, externalWithoutFDA: true)
        )
        XCTAssertEqual(warned.externalDaemonWarning, OnboardingModel.externalDaemonWarningText)

        let quiet = makeModel(
            granted: { false },
            health: OnboardingModel.Health(phase: .scanning, externalWithoutFDA: true)
        )
        XCTAssertNil(quiet.externalDaemonWarning)
    }

    func testIndexingCopy() {
        let ready = makeModel(
            granted: { false },
            health: OnboardingModel.Health(phase: .ready(items: 7_712_345, folders: 812_345, contentPending: 0), externalWithoutFDA: false)
        )
        XCTAssertEqual(ready.indexingDetail, "✓ 7,712,345 items in 812,345 folders indexed")
        XCTAssertEqual(ready.indexingBadge, .ok)

        let pending = makeModel(
            granted: { false },
            health: OnboardingModel.Health(phase: .ready(items: 10, folders: 2, contentPending: 3), externalWithoutFDA: false)
        )
        XCTAssertEqual(pending.indexingDetail, "Indexing file contents… (3 folders pending)")
        XCTAssertEqual(pending.indexingBadge, .warning)
    }

    func testAutoShowUntilCompletedAndSkippedInDemo() {
        let name = "ferret.onboarding.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertTrue(OnboardingModel.shouldAutoShow(defaults: defaults, environment: [:]))
        XCTAssertFalse(OnboardingModel.shouldAutoShow(defaults: defaults, environment: ["FERRET_DEMO": "1"]))

        let model = makeModel(granted: { false })
        model.markCompleted(defaults: defaults)
        XCTAssertFalse(OnboardingModel.shouldAutoShow(defaults: defaults, environment: [:]))
    }

    private func makeModel(
        granted: @escaping () -> Bool,
        health: OnboardingModel.Health = OnboardingModel.Health(phase: .scanning, externalWithoutFDA: false),
        restart: @escaping () -> Void = {}
    ) -> OnboardingModel {
        OnboardingModel(
            isFullDiskAccessGranted: granted,
            health: { health },
            isExtensionEnabled: { false },
            loginState: { .off },
            restartDaemon: restart
        )
    }
}
