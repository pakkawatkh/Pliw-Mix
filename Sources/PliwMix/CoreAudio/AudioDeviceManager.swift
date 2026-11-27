import AudioToolbox
import CoreAudio
import Foundation

@MainActor
public final class AudioDeviceManager: ObservableObject {
    nonisolated public static let aggregateUIDPrefix = "com.pliw-mix.agg."

    @Published public private(set) var outputDevices: [AudioDevice] = []
    @Published public private(set) var defaultOutputDevice: AudioDevice?
    @Published public private(set) var masterVolume: Double = 1.0
    @Published public private(set) var isMasterMuted: Bool = false
    @Published public private(set) var masterVolumeSupported: Bool = true

    public var onDefaultDeviceChanged: ((AudioDevice?) -> Void)?
    public var onDeviceListChanged: (([AudioDevice]) -> Void)?

    private let listenerQueue = DispatchQueue(label: "com.pliw-mix.device-listeners")
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedMasterDeviceID: AudioObjectID = kAudioObjectUnknown

    public init() {
        refreshDevices()
        installSystemListeners()
    }

    public func stop() {
        removeSystemListeners()
        removeMasterDeviceListeners()
    }

    public func refreshDevices() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        let defaultID = CoreAudioHelpers.getProperty(
            objectID: systemObj,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            defaultValue: AudioObjectID(kAudioObjectUnknown)
        ) ?? kAudioObjectUnknown

        let allDeviceIDs: [AudioObjectID] = CoreAudioHelpers.getArrayProperty(
            objectID: systemObj,
            selector: kAudioHardwarePropertyDevices
        )

        var results: [AudioDevice] = []
        for devID in allDeviceIDs {
            guard let uid = CoreAudioHelpers.getStringProperty(
                objectID: devID,
                selector: kAudioDevicePropertyDeviceUID
            ) else { continue }

            // Exclude our own private routing aggregate devices
            if uid.hasPrefix(Self.aggregateUIDPrefix) { continue }

            // Only include devices that have at least 1 output channel
            let outputChannels = CoreAudioHelpers.streamChannelCount(
                deviceID: devID,
                scope: kAudioObjectPropertyScopeOutput
            )
            guard outputChannels > 0 else { continue }

            let name = CoreAudioHelpers.getStringProperty(
                objectID: devID,
                selector: kAudioObjectPropertyName
            ) ?? "Audio Device"

            let transport = CoreAudioHelpers.getProperty(
                objectID: devID,
                selector: kAudioDevicePropertyTransportType,
                defaultValue: UInt32(kAudioDeviceTransportTypeUnknown)
            ) ?? kAudioDeviceTransportTypeUnknown

            let inputBufferCount = CoreAudioHelpers.streamBufferCount(
                deviceID: devID,
                scope: kAudioObjectPropertyScopeInput
            )

            results.append(
                AudioDevice(
                    id: devID,
                    uid: uid,
                    name: name,
                    transportType: transport,
                    isDefault: devID == defaultID,
                    inputBufferCount: inputBufferCount
                )
            )
        }

        results.sort { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let previousDefaultUID = defaultOutputDevice?.uid
        let previousDevices = outputDevices

        outputDevices = results
        defaultOutputDevice = results.first(where: \.isDefault) ?? results.first

        if observedMasterDeviceID != (defaultOutputDevice?.id ?? kAudioObjectUnknown) {
            removeMasterDeviceListeners()
            if let dev = defaultOutputDevice {
                installMasterDeviceListeners(for: dev.id)
            }
        }

        refreshMasterVolumeAndMute()

        if previousDevices != results {
            onDeviceListChanged?(results)
        }
        if previousDefaultUID != defaultOutputDevice?.uid {
            onDefaultDeviceChanged?(defaultOutputDevice)
        }
    }

    public func device(forUID uid: String?) -> AudioDevice? {
        guard let uid else { return defaultOutputDevice }
        return outputDevices.first(where: { $0.uid == uid })
    }

    public func setSystemDefaultOutputDevice(_ device: AudioDevice) {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        _ = CoreAudioHelpers.setProperty(
            objectID: systemObj,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            value: device.id
        )
        refreshDevices()
    }

    public func setMasterVolume(_ volume: Double) {
        guard let devID = defaultOutputDevice?.id else { return }
        let clamped = Float32(min(max(volume, 0.0), 1.0))

        // Prefer VirtualMainVolume (works seamlessly across Built-in Speakers, AirPods, USB DACs)
        if CoreAudioHelpers.isPropertySettable(
            objectID: devID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            _ = CoreAudioHelpers.setProperty(
                objectID: devID,
                selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain,
                value: clamped
            )
        } else if CoreAudioHelpers.isPropertySettable(
            objectID: devID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            _ = CoreAudioHelpers.setProperty(
                objectID: devID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain,
                value: clamped
            )
        } else {
            // Fallback to setting L/R channels (1 and 2)
            for ch: UInt32 in [1, 2] {
                if CoreAudioHelpers.isPropertySettable(
                    objectID: devID,
                    selector: kAudioDevicePropertyVolumeScalar,
                    scope: kAudioDevicePropertyScopeOutput,
                    element: ch
                ) {
                    _ = CoreAudioHelpers.setProperty(
                        objectID: devID,
                        selector: kAudioDevicePropertyVolumeScalar,
                        scope: kAudioDevicePropertyScopeOutput,
                        element: ch,
                        value: clamped
                    )
                }
            }
        }

        // Unmute master automatically if raising volume above 0 while muted
        if clamped > 0.01 && isMasterMuted {
            setMasterMuted(false)
        }
        masterVolume = Double(clamped)
    }

    public func setMasterMuted(_ muted: Bool) {
        guard let devID = defaultOutputDevice?.id else { return }
        let val: UInt32 = muted ? 1 : 0

        if CoreAudioHelpers.isPropertySettable(
            objectID: devID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            _ = CoreAudioHelpers.setProperty(
                objectID: devID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain,
                value: val
            )
        } else {
            for ch: UInt32 in [1, 2] {
                if CoreAudioHelpers.isPropertySettable(
                    objectID: devID,
                    selector: kAudioDevicePropertyMute,
                    scope: kAudioDevicePropertyScopeOutput,
                    element: ch
                ) {
                    _ = CoreAudioHelpers.setProperty(
                        objectID: devID,
                        selector: kAudioDevicePropertyMute,
                        scope: kAudioDevicePropertyScopeOutput,
                        element: ch,
                        value: val
                    )
                }
            }
        }
        isMasterMuted = muted
    }

    public func refreshMasterVolumeAndMute() {
        guard let devID = defaultOutputDevice?.id else {
            masterVolume = 1.0
            isMasterMuted = false
            masterVolumeSupported = false
            return
        }

        if let v: Float32 = CoreAudioHelpers.getProperty(
            objectID: devID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            defaultValue: 1.0
        ) {
            masterVolume = Double(v)
            masterVolumeSupported = CoreAudioHelpers.isPropertySettable(
                objectID: devID,
                selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
        } else if let v: Float32 = CoreAudioHelpers.getProperty(
            objectID: devID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            defaultValue: 1.0
        ) {
            masterVolume = Double(v)
            masterVolumeSupported = CoreAudioHelpers.isPropertySettable(
                objectID: devID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
        } else if let v1: Float32 = CoreAudioHelpers.getProperty(
            objectID: devID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1,
            defaultValue: 1.0
        ) {
            masterVolume = Double(v1)
            masterVolumeSupported = CoreAudioHelpers.isPropertySettable(
                objectID: devID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: 1
            )
        } else {
            masterVolume = 1.0
            masterVolumeSupported = false
        }

        if let m: UInt32 = CoreAudioHelpers.getProperty(
            objectID: devID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            defaultValue: 0
        ) {
            isMasterMuted = m != 0
        } else if let m1: UInt32 = CoreAudioHelpers.getProperty(
            objectID: devID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1,
            defaultValue: 0
        ) {
            isMasterMuted = m1 != 0
        } else {
            isMasterMuted = false
        }
    }

    // MARK: - Core Audio Listeners

    private func installSystemListeners() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)

        let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        devicesListenerBlock = devBlock
        var devAddr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(systemObj, &devAddr, listenerQueue, devBlock)

        let defBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        defaultDeviceListenerBlock = defBlock
        var defAddr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(systemObj, &defAddr, listenerQueue, defBlock)
    }

    private func removeSystemListeners() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        if let devBlock = devicesListenerBlock {
            var devAddr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(systemObj, &devAddr, listenerQueue, devBlock)
            devicesListenerBlock = nil
        }
        if let defBlock = defaultDeviceListenerBlock {
            var defAddr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(systemObj, &defAddr, listenerQueue, defBlock)
            defaultDeviceListenerBlock = nil
        }
    }

    private func installMasterDeviceListeners(for deviceID: AudioObjectID) {
        observedMasterDeviceID = deviceID

        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshMasterVolumeAndMute()
            }
        }
        volumeListenerBlock = volBlock
        var volAddr = CoreAudioHelpers.makeAddress(
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &volAddr, listenerQueue, volBlock)

        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshMasterVolumeAndMute()
            }
        }
        muteListenerBlock = muteBlock
        var muteAddr = CoreAudioHelpers.makeAddress(
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, listenerQueue, muteBlock)
    }

    private func removeMasterDeviceListeners() {
        guard observedMasterDeviceID != kAudioObjectUnknown else { return }
        let devID = observedMasterDeviceID
        if let volBlock = volumeListenerBlock {
            var volAddr = CoreAudioHelpers.makeAddress(
                selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(devID, &volAddr, listenerQueue, volBlock)
            volumeListenerBlock = nil
        }
        if let muteBlock = muteListenerBlock {
            var muteAddr = CoreAudioHelpers.makeAddress(
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(devID, &muteAddr, listenerQueue, muteBlock)
            muteListenerBlock = nil
        }
        observedMasterDeviceID = kAudioObjectUnknown
    }
}
