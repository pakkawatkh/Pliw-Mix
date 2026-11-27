import CoreAudio
import Foundation

/// Manages the lifecycle of all active per-app `AppTapPipeline` instances.
/// Uses lazy tapping: an app is only tapped when its volume != 100%, muted,
/// or routed to a specific non-default output device.
@MainActor
public final class AudioRoutingEngine: ObservableObject {
    @Published public private(set) var lastError: String?
    @Published public private(set) var needsAudioCapturePermission: Bool = false
    @Published public private(set) var activeTapAppIDs: Set<String> = []

    private var pipelines: [String: AppTapPipeline] = [:]

    public init() {}

    /// Synchronizes all active process taps against the latest discovered apps,
    /// persisted per-app settings, and available audio output devices.
    public func sync(
        apps: [AudioApp],
        settingsProvider: (String) -> AppAudioSetting,
        deviceManager: AudioDeviceManager
    ) {
        let appByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        // 1. Tear down taps for apps that quit or returned to pure default passthrough
        for appID in Array(pipelines.keys) {
            guard let app = appByID[appID] else {
                destroyPipeline(for: appID)
                continue
            }
            let setting = settingsProvider(appID)
            if !setting.requiresTap {
                destroyPipeline(for: appID)
            } else if app.processObjectIDs.isEmpty {
                destroyPipeline(for: appID)
            }
        }

        // 2. Create, update, or recreate taps for apps that require custom volume/mute/routing
        for app in apps {
            let setting = settingsProvider(app.id)
            guard setting.requiresTap else { continue }
            guard !app.processObjectIDs.isEmpty else { continue }

            guard let targetDevice = resolveTargetDevice(
                requestedUID: setting.outputDeviceUID,
                deviceManager: deviceManager
            ) else {
                continue
            }

            if let existing = pipelines[app.id] {
                let processesChanged = existing.processObjectIDs != app.processObjectIDs
                let deviceChanged = existing.targetDeviceUID != targetDevice.uid

                if !processesChanged && !deviceChanged {
                    existing.updateParameters(volume: setting.volume, isMuted: setting.isMuted)
                    continue
                }
                // Process list or target output device changed — cleanly rebuild pipeline
                destroyPipeline(for: app.id)
            }

            do {
                let pipeline = try AppTapPipeline(
                    appID: app.id,
                    processObjectIDs: app.processObjectIDs,
                    targetDevice: targetDevice,
                    initialVolume: setting.volume,
                    initialMuted: setting.isMuted
                )
                pipelines[app.id] = pipeline
                needsAudioCapturePermission = false
                lastError = nil
            } catch let error as CoreAudioError {
                if case .tapPermissionDenied = error {
                    needsAudioCapturePermission = true
                }
                lastError = error.localizedDescription
            } catch {
                lastError = error.localizedDescription
            }
        }

        let activeIDs = Set(pipelines.keys)
        if activeIDs != activeTapAppIDs {
            activeTapAppIDs = activeIDs
        }
    }

    /// Fast lock-free gain/mute update for an already-tapped app during live slider drags.
    public func fastUpdateParameters(appID: String, setting: AppAudioSetting) -> Bool {
        guard let pipeline = pipelines[appID] else { return false }
        if !setting.requiresTap {
            destroyPipeline(for: appID)
            activeTapAppIDs = Set(pipelines.keys)
            return true
        }
        pipeline.updateParameters(volume: setting.volume, isMuted: setting.isMuted)
        return true
    }

    public func peakLevel(for appID: String) -> Double {
        guard let pipeline = pipelines[appID] else { return 0.0 }
        return AudioMath.normalizedMeterLevel(fromPeak: pipeline.currentPeakLevel())
    }

    public func retryAfterPermissionGrant(
        apps: [AudioApp],
        settingsProvider: (String) -> AppAudioSetting,
        deviceManager: AudioDeviceManager
    ) {
        needsAudioCapturePermission = false
        lastError = nil
        sync(apps: apps, settingsProvider: settingsProvider, deviceManager: deviceManager)
    }

    public func teardownAll() {
        for appID in Array(pipelines.keys) {
            destroyPipeline(for: appID)
        }
        activeTapAppIDs = []
    }

    private func destroyPipeline(for appID: String) {
        if let pipeline = pipelines.removeValue(forKey: appID) {
            pipeline.stopAndDestroy()
        }
    }

    private func resolveTargetDevice(
        requestedUID: String?,
        deviceManager: AudioDeviceManager
    ) -> AudioDevice? {
        if let uid = requestedUID, let matched = deviceManager.device(forUID: uid) {
            return matched
        }
        // Fallback cleanly to current System Default if requested headphones/DAC were unplugged
        return deviceManager.defaultOutputDevice
    }
}
