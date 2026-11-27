import AppKit
import CoreAudio
import Foundation

public struct AudioApp: Identifiable, Equatable {
    /// Canonical app identifier (bundle identifier when available, otherwise fallback process key).
    public let id: String
    public let name: String
    public let bundleID: String
    public let icon: NSImage?
    /// All Core Audio process object IDs associated with this app (e.g. main process + helper renderers).
    public let processObjectIDs: [AudioObjectID]
    /// True if at least one associated process is currently outputting audio.
    public let isRunningOutput: Bool

    public init(
        id: String,
        name: String,
        bundleID: String,
        icon: NSImage?,
        processObjectIDs: [AudioObjectID],
        isRunningOutput: Bool
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.icon = icon
        self.processObjectIDs = processObjectIDs
        self.isRunningOutput = isRunningOutput
    }

    public static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.bundleID == rhs.bundleID
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.isRunningOutput == rhs.isRunningOutput
    }
}
