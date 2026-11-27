import CAtomicBridge
import CoreAudio
import Foundation

/// Owns one Core Audio Process Tap + Private Aggregate Device + real-time IOProc
/// for a single grouped application, routing its audio to `targetDevice` with
/// smooth lock-free gain, boost soft-limiting, mute, and live peak metering.
public final class AppTapPipeline {
    public let appID: String
    public let processObjectIDs: [AudioObjectID]
    public let targetDeviceUID: String

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private let audioState: OpaquePointer
    private let tapInputStartBufferIndex: Int
    private var isStarted = false

    public init(
        appID: String,
        processObjectIDs: [AudioObjectID],
        targetDevice: AudioDevice,
        initialVolume: Double,
        initialMuted: Bool
    ) throws {
        guard !processObjectIDs.isEmpty else {
            throw CoreAudioError.missingProperty("No process audio IDs for \(appID)")
        }

        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.targetDeviceUID = targetDevice.uid
        self.tapInputStartBufferIndex = max(0, targetDevice.inputBufferCount)

        let initialGain = AudioMath.linearGain(forVolume: initialVolume)
        self.audioState = pm_audio_state_create(initialGain, initialMuted)

        do {
            try setupTapAndAggregateDevice(targetDevice: targetDevice)
        } catch {
            cleanupCoreAudio()
            throw error
        }
    }

    deinit {
        cleanupCoreAudio()
        pm_audio_state_destroy(audioState)
    }

    /// Lock-free parameter update safe to call from any thread (including slider drags at 60-120Hz).
    public func updateParameters(volume: Double, isMuted: Bool) {
        let gain = AudioMath.linearGain(forVolume: volume)
        pm_audio_state_set_params(audioState, gain, isMuted)
    }

    /// Reads the latest peak output level in `[0.0, 1.0]` lock-free.
    public func currentPeakLevel() -> Float {
        pm_audio_state_load_level(audioState)
    }

    public func stopAndDestroy() {
        cleanupCoreAudio()
    }

    private func cleanupCoreAudio() {
        if let procID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            if isStarted {
                AudioDeviceStop(aggregateDeviceID, procID)
                isStarted = false
            }
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        pm_audio_state_store_level(audioState, 0.0)
    }

    // MARK: - Core Audio Pipeline Setup

    private func setupTapAndAggregateDevice(targetDevice: AudioDevice) throws {
        // 1. Create Process Tap (stereo mixdown of all process objects belonging to this app)
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        let tapUUID = UUID()
        tapDescription.uuid = tapUUID
        tapDescription.name = "PliwMixTap-\(appID)"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var createdTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard tapStatus == noErr, createdTapID != kAudioObjectUnknown else {
            if tapStatus == kAudioHardwareIllegalOperationError || tapStatus == -66748 || tapStatus == 560947818 {
                throw CoreAudioError.tapPermissionDenied
            }
            throw CoreAudioError.status(tapStatus, "Failed to create process tap for \(appID)")
        }
        self.tapID = createdTapID

        // 2. Create Private Aggregate Device combining target output device + process tap
        let aggUID = "\(AudioDeviceManager.aggregateUIDPrefix)\(UUID().uuidString)"
        let subDeviceDict: [String: Any] = [
            kAudioSubDeviceUIDKey: targetDevice.uid
        ]
        let subTapDict: [String: Any] = [
            kAudioSubTapUIDKey: tapUUID.uuidString,
            kAudioSubTapDriftCompensationKey: true
        ]

        let aggDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PliwMix-\(appID)",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: targetDevice.uid,
            kAudioAggregateDeviceSubDeviceListKey: [subDeviceDict],
            kAudioAggregateDeviceTapListKey: [subTapDict],
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        var createdAggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDescription as CFDictionary, &createdAggID)
        guard aggStatus == noErr, createdAggID != kAudioObjectUnknown else {
            throw CoreAudioError.status(aggStatus, "Failed to create aggregate device for \(appID)")
        }
        self.aggregateDeviceID = createdAggID

        // 3. Register real-time lock-free IOProc
        let statePtr = self.audioState
        let tapStartIndex = self.tapInputStartBufferIndex

        var createdIOProcID: AudioDeviceIOProcID?
        let ioProcBlock: AudioDeviceIOBlock = { _, inInputData, _, outOutputData, _ in
            AppTapPipeline.processAudioBlock(
                inInputData: inInputData,
                outOutputData: outOutputData,
                statePtr: statePtr,
                tapInputStartBufferIndex: tapStartIndex
            )
        }

        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            createdAggID,
            nil,
            ioProcBlock
        )
        guard procStatus == noErr, let validProcID = createdIOProcID else {
            throw CoreAudioError.status(procStatus, "Failed to register audio IOProc for \(appID)")
        }
        self.ioProcID = validProcID

        let startStatus = AudioDeviceStart(createdAggID, validProcID)
        guard startStatus == noErr else {
            throw CoreAudioError.status(startStatus, "Failed to start audio pipeline for \(appID)")
        }
        self.isStarted = true
    }

    // MARK: - Real-Time Audio Callback (Zero Allocation, Lock-Free)

    private static func processAudioBlock(
        inInputData: UnsafePointer<AudioBufferList>,
        outOutputData: UnsafeMutablePointer<AudioBufferList>,
        statePtr: OpaquePointer,
        tapInputStartBufferIndex: Int
    ) {
        let outBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
        guard !outBuffers.isEmpty else { return }

        let inListPtr = UnsafeMutablePointer(mutating: inInputData)
        let inBuffers = UnsafeMutableAudioBufferListPointer(inListPtr)

        // Ensure tap input buffer exists after any hardware input streams on duplex devices
        guard tapInputStartBufferIndex < inBuffers.count else {
            zeroOutputBuffers(outBuffers)
            pm_audio_state_store_level(statePtr, 0.0)
            return
        }

        let tapBufferCount = inBuffers.count - tapInputStartBufferIndex
        let tapFirstBuf = inBuffers[tapInputStartBufferIndex]
        guard let tapFirstData = tapFirstBuf.mData else {
            zeroOutputBuffers(outBuffers)
            pm_audio_state_store_level(statePtr, 0.0)
            return
        }

        let inChannels0 = max(1, Int(tapFirstBuf.mNumberChannels))
        let inIsNonInterleaved = (tapBufferCount >= 2 && inChannels0 == 1)
        let inSampleCount0 = Int(tapFirstBuf.mDataByteSize) / MemoryLayout<Float>.size
        let inFrameCount = inIsNonInterleaved ? inSampleCount0 : (inSampleCount0 / inChannels0)

        let outFirstBuf = outBuffers[0]
        guard outFirstBuf.mData != nil else { return }
        let outChannels0 = max(1, Int(outFirstBuf.mNumberChannels))
        let outIsNonInterleaved = (outBuffers.count >= 2 && outChannels0 == 1)
        let outSampleCount0 = Int(outFirstBuf.mDataByteSize) / MemoryLayout<Float>.size
        let outFrameCount = outIsNonInterleaved ? outSampleCount0 : (outSampleCount0 / outChannels0)

        let frameCount = min(inFrameCount, outFrameCount)
        guard frameCount > 0 else {
            zeroOutputBuffers(outBuffers)
            pm_audio_state_store_level(statePtr, 0.0)
            return
        }

        let targetGain = pm_audio_state_load_target_gain(statePtr)
        var currentGain = pm_audio_state_get_current_gain(statePtr)
        let rampAlpha: Float = 0.005 // ~5ms smooth ramp at 48kHz to prevent zipper noise & mute clicks

        let inPtr0 = tapFirstData.assumingMemoryBound(to: Float.self)
        let inPtr1: UnsafeMutablePointer<Float>? = inIsNonInterleaved
            ? inBuffers[tapInputStartBufferIndex + 1].mData?.assumingMemoryBound(to: Float.self)
            : nil

        let outPtr0 = outFirstBuf.mData!.assumingMemoryBound(to: Float.self)
        let outPtr1: UnsafeMutablePointer<Float>? = outIsNonInterleaved
            ? outBuffers[1].mData?.assumingMemoryBound(to: Float.self)
            : nil

        // Zero any extra output buffers (e.g., channels 3+ on multi-channel interfaces)
        if outIsNonInterleaved && outBuffers.count > 2 {
            for bIdx in 2..<outBuffers.count {
                if let ptr = outBuffers[bIdx].mData {
                    memset(ptr, 0, Int(outBuffers[bIdx].mDataByteSize))
                }
            }
        }

        var maxPeak: Float = 0.0

        for frame in 0..<frameCount {
            currentGain += (targetGain - currentGain) * rampAlpha

            let rawL: Float
            let rawR: Float
            if inIsNonInterleaved {
                rawL = inPtr0[frame]
                rawR = inPtr1?[frame] ?? rawL
            } else if inChannels0 >= 2 {
                let base = frame * inChannels0
                rawL = inPtr0[base]
                rawR = inPtr0[base + 1]
            } else {
                rawL = inPtr0[frame]
                rawR = rawL
            }

            let outL = AudioMath.processSample(rawL, gain: currentGain)
            let outR = AudioMath.processSample(rawR, gain: currentGain)

            let peak = max(abs(outL), abs(outR))
            if peak > maxPeak {
                maxPeak = peak
            }

            if outIsNonInterleaved {
                outPtr0[frame] = outL
                outPtr1?[frame] = outR
            } else if outChannels0 >= 2 {
                let base = frame * outChannels0
                outPtr0[base] = outL
                outPtr0[base + 1] = outR
                if outChannels0 > 2 {
                    for ch in 2..<outChannels0 {
                        outPtr0[base + ch] = 0.0
                    }
                }
            } else {
                outPtr0[frame] = 0.5 * (outL + outR)
            }
        }

        // Snap near-zero gain to exact 0 to avoid denormal floats
        if abs(targetGain - currentGain) < 0.00001 {
            currentGain = targetGain
        }
        pm_audio_state_set_current_gain(statePtr, currentGain)
        pm_audio_state_store_level(statePtr, min(maxPeak, 1.0))
    }

    @inline(__always)
    private static func zeroOutputBuffers(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for buf in buffers {
            if let ptr = buf.mData {
                memset(ptr, 0, Int(buf.mDataByteSize))
            }
        }
    }
}
