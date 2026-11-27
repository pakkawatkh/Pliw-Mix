import AudioToolbox
import CoreAudio
import Foundation

public enum CoreAudioError: LocalizedError {
    case status(OSStatus, String)
    case missingProperty(String)
    case tapPermissionDenied
    case deviceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .status(let code, let context):
            return "\(context) (OSStatus: \(code))"
        case .missingProperty(let name):
            return "Missing Core Audio property: \(name)"
        case .tapPermissionDenied:
            return "System Audio Recording permission is required."
        case .deviceNotFound(let uid):
            return "Output device not found: \(uid)"
        }
    }
}

public enum CoreAudioHelpers {
    public static func makeAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    public static func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        return AudioObjectHasProperty(objectID, &address)
    }

    public static func isPropertySettable(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(objectID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    public static func getProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) -> T? {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value = defaultValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        guard status == noErr else { return nil }
        return value
    }

    public static func setProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: T
    ) -> OSStatus {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        var mutableValue = value
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &mutableValue) { ptr in
            AudioObjectSetPropertyData(objectID, &address, 0, nil, size, UnsafeRawPointer(ptr))
        }
    }

    public static func getStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> String? {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var unmanagedRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &unmanagedRef)
        guard status == noErr, let cfStr = unmanagedRef?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }

    public static func getArrayProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> [T] {
        var address = makeAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return [] }
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        var actualSize = dataSize
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &actualSize, buffer)
        guard status == noErr else { return [] }
        let actualCount = Int(actualSize) / MemoryLayout<T>.stride
        return Array(UnsafeBufferPointer(start: buffer, count: actualCount))
    }

    /// Returns the number of AudioBuffers configured for a device in the given scope (input/output).
    public static func streamBufferCount(
        deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = makeAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: scope,
            element: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return 0 }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        var actualSize = size
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &actualSize, rawPtr) == noErr else {
            return 0
        }
        let listPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        return Int(listPtr.pointee.mNumberBuffers)
    }

    /// Returns total channel count configured for a device in the given scope.
    public static func streamChannelCount(
        deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> Int {
        var address = makeAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: scope,
            element: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return 0 }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        var actualSize = size
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &actualSize, rawPtr) == noErr else {
            return 0
        }
        let listPtr = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
