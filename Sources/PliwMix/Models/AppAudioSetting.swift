import Foundation

public struct AppAudioSetting: Codable, Equatable, Sendable {
    /// Logical volume slider value: 0.0 (0%) to 1.0 (100%). Default is 1.0 (100%).
    public var volume: Double
    /// Independent per-app mute toggle.
    public var isMuted: Bool
    /// Target output device UID. `nil` means follow macOS System Default Output Device.
    public var outputDeviceUID: String?

    public static let defaultSetting = AppAudioSetting(volume: 1.0, isMuted: false, outputDeviceUID: nil)

    public init(volume: Double = 1.0, isMuted: Bool = false, outputDeviceUID: String? = nil) {
        self.volume = Self.clampVolume(volume)
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
    }

    public static func clampVolume(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    /// True if this app deviates from passthrough defaults and therefore requires an active Core Audio process tap.
    public var requiresTap: Bool {
        isMuted || abs(volume - 1.0) > 0.005 || outputDeviceUID != nil
    }

    /// Display percentage string (e.g., "75%", "150%").
    public var percentageText: String {
        "\(Int((volume * 100.0).rounded()))%"
    }
}
