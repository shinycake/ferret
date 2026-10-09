import XCTest
@testable import FerretCore

actor RecordingBackend: SettingsSearchBackend {
    private(set) var limits: [Int] = []

    func search(limit: Int) async {
        limits.append(limit)
    }
}

@MainActor
final class SettingsTests: XCTestCase {
    func testChangingLimitChangesSentLimit() async {
        let store = makeStore()
        store.showHiddenFiles = true
        store.excludedPaths = []
        store.resultLimit = 50
        let backend = RecordingBackend()
        let model = SettingsModel(store: store, confirm: { _ in false }, performReindex: {}, backend: backend)

        await model.sendSearch()
        store.resultLimit = 80
        await model.sendSearch()

        let limits = await backend.limits
        XCTAssertEqual(limits, [50, 80])
    }

    func testHiddenFilterOverFetchesTheSentLimit() async {
        let store = makeStore()
        store.showHiddenFiles = false
        store.excludedPaths = []
        store.resultLimit = 40
        let backend = RecordingBackend()
        let model = SettingsModel(store: store, confirm: { _ in false }, performReindex: {}, backend: backend)
        await model.sendSearch()
        let limits = await backend.limits
        XCTAssertEqual(limits, [120])
    }

    func testReindexIsGatedByConfirmation() {
        let store = makeStore()
        var prompts: [String] = []
        var calls = 0
        let model = SettingsModel(
            store: store,
            confirm: { message in
                prompts.append(message)
                return prompts.count > 1
            },
            performReindex: { calls += 1 }
        )
        model.requestReindex()
        XCTAssertEqual(calls, 0)
        model.requestReindex()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(prompts, [SettingsModel.reindexConfirmation, SettingsModel.reindexConfirmation])
        XCTAssertEqual(SettingsModel.reindexConfirmation, "This rebuilds the index shared with the fsearch CLI.")
    }

    func testLimitClampsAndPersists() {
        let name = "ferret.settings.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.resultLimit, 50)
        store.resultLimit = 4
        XCTAssertEqual(store.resultLimit, 10)
        store.resultLimit = 900
        XCTAssertEqual(store.resultLimit, 500)
        store.addExcluded("/tmp/secret/")
        store.addExcluded("/tmp/secret")
        XCTAssertEqual(store.excludedPaths, ["/tmp/secret"])

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.resultLimit, 500)
        XCTAssertEqual(reloaded.excludedPaths, ["/tmp/secret"])
    }

    private func makeStore() -> SettingsStore {
        let name = "ferret.settings.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SettingsStore(defaults: defaults)
    }
}
