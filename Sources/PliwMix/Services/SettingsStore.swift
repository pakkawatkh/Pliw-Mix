import Foundation

public final class SettingsStore {
    private static let appSettingsKey = "pliw_mix.app_settings.v1"
    private static let pinnedAppIDsKey = "pliw_mix.pinned_app_ids.v1"

    private let defaults: UserDefaults
    private var cache: [String: AppAudioSetting]
    private var pinnedIDs: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.appSettingsKey),
           let decoded = try? JSONDecoder().decode([String: AppAudioSetting].self, from: data) {
            // Clamp any previously saved >100% values cleanly to 100%
            var sanitized: [String: AppAudioSetting] = [:]
            for (key, value) in decoded {
                let clamped = AppAudioSetting(
                    volume: value.volume,
                    isMuted: value.isMuted,
                    outputDeviceUID: value.outputDeviceUID
                )
                if clamped.requiresTap {
                    sanitized[key] = clamped
                }
            }
            self.cache = sanitized
        } else {
            self.cache = [:]
        }

        if let savedPins = defaults.stringArray(forKey: Self.pinnedAppIDsKey) {
            self.pinnedIDs = Set(savedPins)
        } else {
            self.pinnedIDs = []
        }
    }

    public func setting(for appID: String) -> AppAudioSetting {
        cache[appID] ?? .defaultSetting
    }

    public func allSettings() -> [String: AppAudioSetting] {
        cache
    }

    public func save(_ setting: AppAudioSetting, for appID: String) {
        let clamped = AppAudioSetting(
            volume: setting.volume,
            isMuted: setting.isMuted,
            outputDeviceUID: setting.outputDeviceUID
        )
        if !clamped.requiresTap {
            cache.removeValue(forKey: appID)
        } else {
            cache[appID] = clamped
        }
        persistSettings()
    }

    public func reset(for appID: String) {
        cache.removeValue(forKey: appID)
        persistSettings()
    }

    public func resetAll() {
        cache.removeAll()
        persistSettings()
    }

    // MARK: - Pinned / Manually Added Apps

    public func allPinnedAppIDs() -> Set<String> {
        pinnedIDs
    }

    public func isPinned(_ appID: String) -> Bool {
        pinnedIDs.contains(appID)
    }

    public func pinApp(_ appID: String) {
        pinnedIDs.insert(appID)
        persistPins()
    }

    public func unpinApp(_ appID: String) {
        pinnedIDs.remove(appID)
        persistPins()
    }

    private func persistSettings() {
        if let encoded = try? JSONEncoder().encode(cache) {
            defaults.set(encoded, forKey: Self.appSettingsKey)
        }
    }

    private func persistPins() {
        defaults.set(Array(pinnedIDs).sorted(), forKey: Self.pinnedAppIDsKey)
    }
}
