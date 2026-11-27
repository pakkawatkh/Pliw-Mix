import Foundation

public enum AudioMath {
    /// Converts a logical slider value in `[0.0, 1.0]` to a linear amplitude gain multiplier
    /// using a smooth perceptual power curve (`v^1.8`), capped strictly at unity gain (`1.0`).
    @inline(__always)
    public static func linearGain(forVolume volume: Double) -> Float {
        let clamped = min(max(volume, 0.0), 1.0)
        if clamped <= 0.0001 {
            return 0.0
        }
        return Float(pow(clamped, 1.8))
    }

    /// Applies attenuation gain in `[0.0, 1.0]` cleanly to a single audio sample.
    @inline(__always)
    public static func processSample(_ sample: Float, gain: Float) -> Float {
        let clampedGain = min(max(gain, 0.0), 1.0)
        return sample * clampedGain
    }

    /// Smooths peak meter level into normalized `[0.0, 1.0]` visual meter fraction.
    @inline(__always)
    public static func normalizedMeterLevel(fromPeak peak: Float) -> Double {
        let clamped = min(max(Double(peak), 0.0), 1.0)
        if clamped < 0.001 { return 0.0 }
        // Perceptual dB scaling from -50 dB to 0 dB
        let db = 20.0 * log10(clamped)
        let normalized = (db + 50.0) / 50.0
        return min(max(normalized, 0.0), 1.0)
    }
}
