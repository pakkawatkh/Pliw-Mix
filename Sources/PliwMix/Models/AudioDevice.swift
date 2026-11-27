import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let transportType: UInt32
    public let isDefault: Bool
    public let inputBufferCount: Int

    public init(
        id: AudioObjectID,
        uid: String,
        name: String,
        transportType: UInt32,
        isDefault: Bool,
        inputBufferCount: Int = 0
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.isDefault = isDefault
        self.inputBufferCount = inputBufferCount
    }

    public var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            if name.localizedCaseInsensitiveContains("headphone") || name.localizedCaseInsensitiveContains("หูฟัง") {
                return "headphones"
            }
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.localizedCaseInsensitiveContains("airpods") {
                return "airpodspro"
            }
            return "headphones"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform.path"
        default:
            return "hifispeaker.fill"
        }
    }
}
