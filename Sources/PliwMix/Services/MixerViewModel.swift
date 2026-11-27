import AppKit
import Combine
import Foundation

@MainActor
public final class MixerViewModel: ObservableObject {
    @Published public private(set) var apps: [AudioApp] = []
    @Published public private(set) var hiddenProcesses: [AudioApp] = []
    @Published public private(set) var outputDevices: [AudioDevice] = []
    @Published public private(set) var defaultOutputDevice: AudioDevice?
    @Published public private(set) var masterVolume: Double = 1.0
    @Published public private(set) var isMasterMuted: Bool = false
    @Published public private(set) var masterVolumeSupported: Bool = true
    @Published public private(set) var appSettings: [String: AppAudioSetting] = [:]
    @Published public private(set) var pinnedAppIDs: Set<String> = []
    @Published public private(set) var appLevels: [String: Double] = [:]
    @Published public private(set) var activeTapCount: Int = 0
    @Published public private(set) var needsAudioCapturePermission: Bool = false
    @Published public private(set) var lastError: String?

    public let deviceManager: AudioDeviceManager
    public let processMonitor: AudioProcessMonitor
    public let routingEngine: AudioRoutingEngine
    public let settingsStore: SettingsStore
    public let launchAtLogin: LaunchAtLoginService

    private var cancellables: Set<AnyCancellable> = []
    private var meterTimer: Timer?
    private var isPopoverOpen = false

    public init(
        deviceManager: AudioDeviceManager? = nil,
        processMonitor: AudioProcessMonitor? = nil,
        routingEngine: AudioRoutingEngine? = nil,
        settingsStore: SettingsStore = SettingsStore(),
        launchAtLogin: LaunchAtLoginService? = nil
    ) {
        self.deviceManager = deviceManager ?? AudioDeviceManager()
        self.processMonitor = processMonitor ?? AudioProcessMonitor()
        self.routingEngine = routingEngine ?? AudioRoutingEngine()
        self.settingsStore = settingsStore
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginService()
        self.appSettings = settingsStore.allSettings()
        self.pinnedAppIDs = settingsStore.allPinnedAppIDs()

        bindSubsystems()
        syncAll()
    }

    /// All discovered audio apps (main + hidden) for routing lookups.
    private var allControllableApps: [AudioApp] {
        apps + hiddenProcesses
    }

    /// Clean list shown in the main mixer:
    /// - Main user apps that are actively playing audio, customized, or pinned via "+"
    /// - Plus any hidden process ONLY if explicitly pinned/customized by the user via "+"
    public var visibleApps: [AudioApp] {
        let visibleMain = apps.filter { app in
            app.isRunningOutput || setting(for: app.id).requiresTap || pinnedAppIDs.contains(app.id)
        }
        let visiblePinnedHidden = hiddenProcesses.filter { proc in
            pinnedAppIDs.contains(proc.id) || setting(for: proc.id).requiresTap
        }
        return (visibleMain + visiblePinnedHidden).sorted { lhs, rhs in
            if lhs.isRunningOutput != rhs.isRunningOutput {
                return lhs.isRunningOutput && !rhs.isRunningOutput
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Idle main apps not currently shown in the mixer — ready to be added with "+".
    public var addableMainApps: [AudioApp] {
        let visibleIDs = Set(visibleApps.map(\.id))
        return apps.filter { !visibleIDs.contains($0.id) }
    }

    /// Hidden/background audio processes not currently shown — available under "Other Processes" in "+".
    public var addableOtherProcesses: [AudioApp] {
        let visibleIDs = Set(visibleApps.map(\.id))
        return hiddenProcesses.filter { !visibleIDs.contains($0.id) }
    }

    public var hasAddableApps: Bool {
        !addableMainApps.isEmpty || !addableOtherProcesses.isEmpty
    }

    public var hasAnyCustomSetting: Bool {
        allControllableApps.contains { setting(for: $0.id).requiresTap } || !appSettings.isEmpty
    }

    public func isPinned(_ appID: String) -> Bool {
        pinnedAppIDs.contains(appID)
    }

    public func setting(for appID: String) -> AppAudioSetting {
        appSettings[appID] ?? .defaultSetting
    }

    public func deviceName(for deviceUID: String?) -> String {
        guard let uid = deviceUID else {
            if let def = defaultOutputDevice {
                return "Default (\(def.name))"
            }
            return "System Default"
        }
        if let dev = outputDevices.first(where: { $0.uid == uid }) {
            return dev.name
        }
        return "Unavailable (Using Default)"
    }

    public func deviceSymbol(for deviceUID: String?) -> String {
        guard let uid = deviceUID else {
            return defaultOutputDevice?.symbolName ?? "speaker.wave.2"
        }
        return outputDevices.first(where: { $0.uid == uid })?.symbolName ?? "exclamationmark.triangle"
    }

    // MARK: - User Actions

    public func setMasterVolume(_ value: Double) {
        deviceManager.setMasterVolume(value)
    }

    public func toggleMasterMute() {
        deviceManager.setMasterMuted(!isMasterMuted)
    }

    public func setSystemDefaultOutput(_ device: AudioDevice) {
        deviceManager.setSystemDefaultOutputDevice(device)
    }

    public func pinApp(_ app: AudioApp) {
        settingsStore.pinApp(app.id)
        pinnedAppIDs = settingsStore.allPinnedAppIDs()
    }

    public func unpinApp(_ app: AudioApp) {
        settingsStore.unpinApp(app.id)
        pinnedAppIDs = settingsStore.allPinnedAppIDs()
        // If unpinning a hidden process, also reset its custom settings so it cleanly leaves the mixer
        if hiddenProcesses.contains(where: { $0.id == app.id }) {
            resetApp(app)
        }
    }

    public func setVolume(_ volume: Double, for app: AudioApp) {
        var next = setting(for: app.id)
        let clamped = AppAudioSetting.clampVolume(volume)
        // Snap smoothly to exact 100% at the top edge for clean zero-overhead passthrough
        let snapped = clamped > 0.985 ? 1.0 : clamped
        next.volume = snapped
        if snapped > 0.01 && next.isMuted {
            next.isMuted = false
        }
        applySetting(next, for: app, preferFastPath: true)
    }

    public func toggleMute(for app: AudioApp) {
        var next = setting(for: app.id)
        next.isMuted.toggle()
        applySetting(next, for: app, preferFastPath: true)
    }

    public func setOutputDevice(_ deviceUID: String?, for app: AudioApp) {
        var next = setting(for: app.id)
        next.outputDeviceUID = deviceUID
        applySetting(next, for: app, preferFastPath: false)
    }

    public func resetApp(_ app: AudioApp) {
        settingsStore.reset(for: app.id)
        appSettings.removeValue(forKey: app.id)
        appLevels[app.id] = 0.0
        syncRouting()
    }

    public func resetAllApps() {
        settingsStore.resetAll()
        appSettings.removeAll()
        appLevels.removeAll()
        syncRouting()
    }

    public func refreshNow() {
        deviceManager.refreshDevices()
        processMonitor.refresh()
        syncRouting()
    }

    public func retryPermissions() {
        routingEngine.retryAfterPermissionGrant(
            apps: allControllableApps,
            settingsProvider: { [weak self] id in self?.setting(for: id) ?? .defaultSetting },
            deviceManager: deviceManager
        )
    }

    public func openSystemAudioPermissionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for str in urls {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Popover Lifecycle & Live Metering

    public func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
        if open {
            refreshNow()
            startMeterTimer()
        } else {
            stopMeterTimer()
        }
    }

    public func shutdown() {
        stopMeterTimer()
        routingEngine.teardownAll()
        processMonitor.stop()
        deviceManager.stop()
    }

    // MARK: - Private Wiring

    private func applySetting(_ next: AppAudioSetting, for app: AudioApp, preferFastPath: Bool) {
        settingsStore.save(next, for: app.id)
        if next.requiresTap {
            appSettings[app.id] = next
        } else {
            appSettings.removeValue(forKey: app.id)
            appLevels[app.id] = 0.0
        }

        if preferFastPath && routingEngine.fastUpdateParameters(appID: app.id, setting: next) {
            return
        }
        syncRouting()
    }

    private func bindSubsystems() {
        deviceManager.$outputDevices
            .sink { [weak self] devices in
                self?.outputDevices = devices
            }
            .store(in: &cancellables)

        deviceManager.$defaultOutputDevice
            .sink { [weak self] dev in
                self?.defaultOutputDevice = dev
            }
            .store(in: &cancellables)

        deviceManager.$masterVolume
            .sink { [weak self] vol in
                self?.masterVolume = vol
            }
            .store(in: &cancellables)

        deviceManager.$isMasterMuted
            .sink { [weak self] muted in
                self?.isMasterMuted = muted
            }
            .store(in: &cancellables)

        deviceManager.$masterVolumeSupported
            .sink { [weak self] supported in
                self?.masterVolumeSupported = supported
            }
            .store(in: &cancellables)

        deviceManager.onDefaultDeviceChanged = { [weak self] _ in
            self?.syncRouting()
        }
        deviceManager.onDeviceListChanged = { [weak self] _ in
            self?.syncRouting()
        }

        processMonitor.$apps
            .sink { [weak self] discovered in
                self?.apps = discovered
                self?.syncRouting()
            }
            .store(in: &cancellables)

        processMonitor.$hiddenProcesses
            .sink { [weak self] hidden in
                self?.hiddenProcesses = hidden
                self?.syncRouting()
            }
            .store(in: &cancellables)

        routingEngine.$activeTapAppIDs
            .sink { [weak self] ids in
                self?.activeTapCount = ids.count
            }
            .store(in: &cancellables)

        routingEngine.$needsAudioCapturePermission
            .sink { [weak self] needs in
                self?.needsAudioCapturePermission = needs
            }
            .store(in: &cancellables)

        routingEngine.$lastError
            .sink { [weak self] err in
                self?.lastError = err
            }
            .store(in: &cancellables)
    }

    private func syncAll() {
        outputDevices = deviceManager.outputDevices
        defaultOutputDevice = deviceManager.defaultOutputDevice
        masterVolume = deviceManager.masterVolume
        isMasterMuted = deviceManager.isMasterMuted
        masterVolumeSupported = deviceManager.masterVolumeSupported
        apps = processMonitor.apps
        hiddenProcesses = processMonitor.hiddenProcesses
        syncRouting()
    }

    private func syncRouting() {
        routingEngine.sync(
            apps: allControllableApps,
            settingsProvider: { [weak self] id in
                self?.setting(for: id) ?? .defaultSetting
            },
            deviceManager: deviceManager
        )
    }

    private func startMeterTimer() {
        guard meterTimer == nil else { return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPopoverOpen else { return }
                var nextLevels: [String: Double] = [:]
                for app in self.visibleApps {
                    let level = self.routingEngine.peakLevel(for: app.id)
                    if level > 0.005 {
                        nextLevels[app.id] = level
                    }
                }
                self.appLevels = nextLevels
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
}
