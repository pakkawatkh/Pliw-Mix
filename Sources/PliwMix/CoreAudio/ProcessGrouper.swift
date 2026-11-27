import AppKit
import CoreAudio
import Darwin
import Foundation

/// Lightweight snapshot of a single Core Audio process object for pure, unit-testable grouping.
public struct RawAudioProcess: Equatable, Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let processName: String
    public let isRunningOutput: Bool
    public let isRunning: Bool

    public init(
        objectID: AudioObjectID,
        pid: pid_t,
        bundleID: String?,
        processName: String,
        isRunningOutput: Bool,
        isRunning: Bool
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.processName = processName
        self.isRunningOutput = isRunningOutput
        self.isRunning = isRunning
    }
}

/// Lightweight snapshot of a running macOS GUI application for grouping helper processes.
public struct RunningAppInfo: Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String
    public let isRegularApp: Bool

    public init(pid: pid_t, bundleID: String, name: String, isRegularApp: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isRegularApp = isRegularApp
    }
}

/// Pure grouping engine that maps Chromium Helpers (Chrome, Brave, Edge, Arc), Electron Helpers,
/// and Safari WebKit audio helpers cleanly onto their parent main user-facing macOS application,
/// while filtering out background system daemons and non-essential utility processes.
public enum ProcessGrouper {
    public struct GroupedDescriptor: Equatable, Sendable {
        public let id: String
        public let name: String
        public let bundleID: String
        public let primaryPID: pid_t
        public let processObjectIDs: [AudioObjectID]
        public let isRunningOutput: Bool
    }

    /// System/utility macOS apps that users don't want cluttering an audio mixer.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.spotlight",
        "com.apple.notificationcenterui",
        "com.apple.windowserver",
        "com.apple.siri",
        "com.apple.siri.launcher",
        "com.apple.activitymonitor",
        "com.apple.console",
        "com.apple.terminal",
        "com.apple.textedit",
        "com.apple.preview",
        "com.apple.screencaptureui",
        "com.apple.airplayuiagent",
        "com.apple.universalcontrol",
        "com.apple.wallpaper.agent",
        "com.apple.accessibility.universalaccessd"
    ]

    private static let excludedBundlePrefixes: [String] = [
        "com.apple.audio.",
        "com.apple.coreaudio",
        "com.apple.accessibility.",
        "com.apple.inputmethod.",
        "com.apple.textinput",
        "com.apple.avconference",
        "com.apple.telephony",
        "com.apple.callkit",
        "com.apple.siri."
    ]

    public struct GroupingResult: Equatable, Sendable {
        /// Clean main user-facing GUI applications (Chrome, Brave, Safari, games, music apps, etc.).
        public let mainApps: [GroupedDescriptor]
        /// Hidden background or system audio processes, only shown when user explicitly adds them via "+".
        public let hiddenProcesses: [GroupedDescriptor]

        public init(mainApps: [GroupedDescriptor], hiddenProcesses: [GroupedDescriptor]) {
            self.mainApps = mainApps
            self.hiddenProcesses = hiddenProcesses
        }
    }

    public static func group(
        processes: [RawAudioProcess],
        runningApps: [RunningAppInfo],
        selfPID: pid_t,
        parentPIDProvider: (pid_t) -> pid_t? = ProcessGrouper.systemParentPID
    ) -> [GroupedDescriptor] {
        groupWithHidden(
            processes: processes,
            runningApps: runningApps,
            selfPID: selfPID,
            parentPIDProvider: parentPIDProvider
        ).mainApps
    }

    public static func groupWithHidden(
        processes: [RawAudioProcess],
        runningApps: [RunningAppInfo],
        selfPID: pid_t,
        parentPIDProvider: (pid_t) -> pid_t? = ProcessGrouper.systemParentPID
    ) -> GroupingResult {
        let regularApps = runningApps.filter(\.isRegularApp)
        let appByPID: [pid_t: RunningAppInfo] = Dictionary(
            runningApps.map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let regularByBundle: [String: RunningAppInfo] = Dictionary(
            regularApps.map { ($0.bundleID.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let regularAppsByBundleLength = regularApps.sorted { $0.bundleID.count > $1.bundleID.count }

        var mainGrouped: [String: (name: String, bundleID: String, primaryPID: pid_t, objectIDs: [AudioObjectID], isRunningOutput: Bool)] = [:]
        var hiddenGrouped: [String: (name: String, bundleID: String, primaryPID: pid_t, objectIDs: [AudioObjectID], isRunningOutput: Bool)] = [:]

        for proc in processes {
            if proc.pid == selfPID { continue }

            if let owner = resolveRegularOwnerApp(
                for: proc,
                appByPID: appByPID,
                regularByBundle: regularByBundle,
                regularAppsByBundleLength: regularAppsByBundleLength,
                parentPIDProvider: parentPIDProvider
            ), !isExcludedSystemApp(bundleID: owner.bundleID) {
                append(
                    proc: proc,
                    id: owner.bundleID,
                    name: owner.name,
                    bundleID: owner.bundleID,
                    primaryPID: owner.pid,
                    into: &mainGrouped
                )
            } else {
                // Keep hidden processes cleanly grouped so the user can still add one manually via "+"
                let fallback = resolveHiddenDescriptor(for: proc, appByPID: appByPID)
                if !isLowLevelAudioDaemon(bundleID: fallback.bundleID, processName: fallback.name) {
                    append(
                        proc: proc,
                        id: fallback.id,
                        name: fallback.name,
                        bundleID: fallback.bundleID,
                        primaryPID: fallback.primaryPID,
                        into: &hiddenGrouped
                    )
                }
            }
        }

        return GroupingResult(
            mainApps: finalize(mainGrouped),
            hiddenProcesses: finalize(hiddenGrouped)
        )
    }

    private static func append(
        proc: RawAudioProcess,
        id: String,
        name: String,
        bundleID: String,
        primaryPID: pid_t,
        into dict: inout [String: (name: String, bundleID: String, primaryPID: pid_t, objectIDs: [AudioObjectID], isRunningOutput: Bool)]
    ) {
        if var existing = dict[id] {
            if !existing.objectIDs.contains(proc.objectID) {
                existing.objectIDs.append(proc.objectID)
            }
            existing.isRunningOutput = existing.isRunningOutput || proc.isRunningOutput
            dict[id] = existing
        } else {
            dict[id] = (
                name: name,
                bundleID: bundleID,
                primaryPID: primaryPID,
                objectIDs: [proc.objectID],
                isRunningOutput: proc.isRunningOutput
            )
        }
    }

    private static func finalize(
        _ dict: [String: (name: String, bundleID: String, primaryPID: pid_t, objectIDs: [AudioObjectID], isRunningOutput: Bool)]
    ) -> [GroupedDescriptor] {
        dict.map { key, value in
            GroupedDescriptor(
                id: key,
                name: value.name,
                bundleID: value.bundleID,
                primaryPID: value.primaryPID,
                processObjectIDs: value.objectIDs.sorted(),
                isRunningOutput: value.isRunningOutput
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRunningOutput != rhs.isRunningOutput {
                return lhs.isRunningOutput && !rhs.isRunningOutput
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func resolveHiddenDescriptor(
        for proc: RawAudioProcess,
        appByPID: [pid_t: RunningAppInfo]
    ) -> (id: String, name: String, bundleID: String, primaryPID: pid_t) {
        if let app = appByPID[proc.pid] {
            return (app.bundleID, app.name, app.bundleID, app.pid)
        }
        if let rawBid = proc.bundleID, !rawBid.isEmpty {
            let cleanName = proc.processName.isEmpty
                ? (rawBid.components(separatedBy: ".").last ?? rawBid)
                : proc.processName
            return (rawBid, cleanName, rawBid, proc.pid)
        }
        let cleanName = proc.processName.isEmpty ? "Process \(proc.pid)" : proc.processName
        let id = "pid:\(proc.pid)"
        return (id, cleanName, id, proc.pid)
    }

    private static func isLowLevelAudioDaemon(bundleID: String, processName: String) -> Bool {
        let lowerBid = bundleID.lowercased()
        let lowerName = processName.lowercased()
        return lowerBid.hasPrefix("com.apple.audio.")
            || lowerBid.hasPrefix("com.apple.coreaudio")
            || lowerName == "coreaudiod"
            || lowerName == "audiomxd"
    }

    private static func isExcludedSystemApp(bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        if excludedBundleIDs.contains(lower) {
            return true
        }
        return excludedBundlePrefixes.contains { lower.hasPrefix($0) }
    }

    private static func resolveRegularOwnerApp(
        for proc: RawAudioProcess,
        appByPID: [pid_t: RunningAppInfo],
        regularByBundle: [String: RunningAppInfo],
        regularAppsByBundleLength: [RunningAppInfo],
        parentPIDProvider: (pid_t) -> pid_t?
    ) -> RunningAppInfo? {
        // 1. Direct regular GUI app PID match
        if let direct = appByPID[proc.pid], direct.isRegularApp {
            return direct
        }

        // 2. Walk ancestor PIDs up to 6 levels to find an owning regular GUI app
        var cursorPID = proc.pid
        var visited = Set<pid_t>([cursorPID])
        for _ in 0..<6 {
            guard let ppid = parentPIDProvider(cursorPID), ppid > 1, !visited.contains(ppid) else {
                break
            }
            visited.insert(ppid)
            if let ancestor = appByPID[ppid], ancestor.isRegularApp {
                return ancestor
            }
            cursorPID = ppid
        }

        // 3. Bundle ID matching (handles Chromium/Brave/Edge/Arc/Electron/Safari helpers)
        if let rawBid = proc.bundleID, !rawBid.isEmpty {
            let lowerBid = rawBid.lowercased()

            if let exact = regularByBundle[lowerBid] {
                return exact
            }

            // Prefix match (e.g., com.google.Chrome.helper.renderer -> com.google.Chrome)
            for regular in regularAppsByBundleLength {
                let prefix = regular.bundleID.lowercased() + "."
                if lowerBid.hasPrefix(prefix) {
                    return regular
                }
            }

            // Safari WebKit audio helpers (com.apple.WebKit.GPU / WebContent)
            if lowerBid.hasPrefix("com.apple.webkit."), let safari = regularByBundle["com.apple.safari"] {
                return safari
            }
        }

        // 4. Process name heuristic for helpers whose bundleID is missing (e.g., "Google Chrome Helper (Renderer)")
        if let matchedRegular = matchByHelperName(proc.processName, regularApps: regularAppsByBundleLength) {
            return matchedRegular
        }

        // Background daemons, menu bar agents, and non-GUI system processes are excluded
        return nil
    }

    private static func matchByHelperName(_ processName: String, regularApps: [RunningAppInfo]) -> RunningAppInfo? {
        let lowerName = processName.lowercased()
        guard lowerName.contains("helper") || lowerName.contains("renderer") || lowerName.contains("gpu") else {
            return nil
        }
        for app in regularApps {
            let appLower = app.name.lowercased()
            if !appLower.isEmpty && lowerName.hasPrefix(appLower + " ") {
                return app
            }
        }
        return nil
    }

    public static func systemParentPID(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    public static func systemProcessName(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            return String(cString: buffer)
        }
        return ""
    }
}
