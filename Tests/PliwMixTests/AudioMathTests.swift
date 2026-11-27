import XCTest
@testable import PliwMix

final class AudioMathTests: XCTestCase {
    func testLinearGainCapsStrictlyAt100Percent() {
        XCTAssertEqual(AudioMath.linearGain(forVolume: 0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.linearGain(forVolume: -0.5), 0.0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.linearGain(forVolume: 1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.linearGain(forVolume: 1.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.linearGain(forVolume: 2.0), 1.0, accuracy: 0.0001)
    }

    func testPerceptualAttenuationCurveIsMonotonic() {
        let g25 = AudioMath.linearGain(forVolume: 0.25)
        let g50 = AudioMath.linearGain(forVolume: 0.50)
        let g75 = AudioMath.linearGain(forVolume: 0.75)
        let g100 = AudioMath.linearGain(forVolume: 1.0)

        XCTAssertGreaterThan(g25, 0.0)
        XCTAssertLessThan(g25, g50)
        XCTAssertLessThan(g50, g75)
        XCTAssertLessThan(g75, g100)
        XCTAssertLessThan(g50, 0.5)
    }

    func testProcessSampleNeverBoostsAboveUnity() {
        XCTAssertEqual(AudioMath.processSample(0.6, gain: 1.0), 0.6, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.processSample(0.6, gain: 2.0), 0.6, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.processSample(-0.4, gain: 0.5), -0.2, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.processSample(0.8, gain: -1.0), 0.0, accuracy: 0.0001)
    }

    func testNormalizedMeterLevelRange() {
        XCTAssertEqual(AudioMath.normalizedMeterLevel(fromPeak: 0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.normalizedMeterLevel(fromPeak: 1.0), 1.0, accuracy: 0.0001)
        let mid = AudioMath.normalizedMeterLevel(fromPeak: 0.1)
        XCTAssertEqual(mid, 0.6, accuracy: 0.01)
    }
}
