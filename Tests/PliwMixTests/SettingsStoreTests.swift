import XCTest
@testable import PliwMix

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.local.pliw-mix.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveReloadClampsTo100PercentAndResets() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.setting(for: "com.google.Chrome"), .defaultSetting)

        let custom = AppAudioSetting(volume: 0.65, isMuted: false, outputDeviceUID: "AirPods-UID")
        store.save(custom, for: "com.google.Chrome")

        // Attempting to save > 100% clamps cleanly to 1.0 (default passthrough when unmuted & default device)
        store.save(AppAudioSetting(volume: 1.8, isMuted: false, outputDeviceUID: nil), for: "com.apple.Safari")
        XCTAssertEqual(store.setting(for: "com.apple.Safari").volume, 1.0, accuracy: 0.0001)

        let reloaded = SettingsStore(defaults: defaults)
        let fetched = reloaded.setting(for: "com.google.Chrome")
        XCTAssertEqual(fetched.volume, 0.65, accuracy: 0.0001)
        XCTAssertFalse(fetched.isMuted)
        XCTAssertEqual(fetched.outputDeviceUID, "AirPods-UID")
        XCTAssertTrue(fetched.requiresTap)

        reloaded.save(.defaultSetting, for: "com.google.Chrome")
        XCTAssertTrue(reloaded.allSettings().isEmpty)
    }

    func testPinAndUnpinAppsPersistAcrossReloads() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.isPinned("com.spotify.client"))

        store.pinApp("com.spotify.client")
        XCTAssertTrue(store.isPinned("com.spotify.client"))

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.isPinned("com.spotify.client"))

        reloaded.unpinApp("com.spotify.client")
        XCTAssertFalse(reloaded.isPinned("com.spotify.client"))
    }

    func testResetAllClearsPersistedEntries() {
        let store = SettingsStore(defaults: defaults)
        store.save(AppAudioSetting(volume: 0.4, isMuted: false, outputDeviceUID: nil), for: "com.brave.Browser")
        store.save(AppAudioSetting(volume: 1.0, isMuted: true, outputDeviceUID: nil), for: "com.apple.Safari")
        XCTAssertEqual(store.allSettings().count, 2)

        store.resetAll()
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.allSettings().isEmpty)
    }
}
