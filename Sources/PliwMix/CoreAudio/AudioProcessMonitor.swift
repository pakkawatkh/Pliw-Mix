import AppKit
import CoreAudio
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class AudioProcessMonitor: ObservableObject {
    /// Main user-facing applications (Chrome, Brave, Safari, games, music players, etc.).
    @Published public private(set) var apps: [AudioApp] = []
    /// Hidden background/utility audio processes (available only via manual "+" Add App picker).
    @Published public private(set) var hiddenProcesses: [AudioApp] = []

    public var onAppsChanged: (([AudioApp]) -> Void)?

    private let listenerQueue = DispatchQueue(label: "com.pliw-mix.process-listeners")
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedProcessListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    public init() {
        refresh()
        installListeners()
    }

    public func stop() {
        removeListeners()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public var allKnownAudioApps: [AudioApp] {
        apps + hiddenProcesses
    }

    public func refresh() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        let processIDs: [AudioObjectID] = CoreAudioHelpers.getArrayProperty(
            objectID: systemObj,
            selector: kAudioHardwarePropertyProcessObjectList
        )

        syncPerProcessOutputListeners(currentProcessIDs: Set(processIDs))

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let rawProcesses: [RawAudioProcess] = processIDs.compactMap { objID in
            guard let pid: pid_t = CoreAudioHelpers.getProperty(
                objectID: objID,
                selector: kAudioProcessPropertyPID,
                defaultValue: 0
            ), pid > 0 else {
                return nil
            }

            let bundleID = CoreAudioHelpers.getStringProperty(
                objectID: objID,
                selector: kAudioProcessPropertyBundleID
            )
            let isRunningOutput: UInt32 = CoreAudioHelpers.getProperty(
                objectID: objID,
                selector: kAudioProcessPropertyIsRunningOutput,
                defaultValue: 0
            ) ?? 0
            let isRunning: UInt32 = CoreAudioHelpers.getProperty(
                objectID: objID,
                selector: kAudioProcessPropertyIsRunning,
                defaultValue: 0
            ) ?? 0

            let name = ProcessGrouper.systemProcessName(for: pid)
            return RawAudioProcess(
                objectID: objID,
                pid: pid,
                bundleID: bundleID,
                processName: name,
                isRunningOutput: isRunningOutput != 0,
                isRunning: isRunning != 0
            )
        }

        let wsApps = NSWorkspace.shared.runningApplications
        var iconsByBundleID: [String: NSImage] = [:]
        var iconsByPID: [pid_t: NSImage] = [:]

        let runningAppInfos: [RunningAppInfo] = wsApps.compactMap { app in
            if let icon = app.icon {
                iconsByPID[app.processIdentifier] = icon
                if let bid = app.bundleIdentifier {
                    iconsByBundleID[bid] = icon
                }
            }
            guard let bid = app.bundleIdentifier, !bid.isEmpty else { return nil }
            let name = app.localizedName ?? bid
            return RunningAppInfo(
                pid: app.processIdentifier,
                bundleID: bid,
                name: name,
                isRegularApp: app.activationPolicy == .regular
            )
        }

        let groupedResult = ProcessGrouper.groupWithHidden(
            processes: rawProcesses,
            runningApps: runningAppInfos,
            selfPID: selfPID
        )

        func mapDescriptor(_ desc: ProcessGrouper.GroupedDescriptor) -> AudioApp {
            let icon = iconsByBundleID[desc.bundleID]
                ?? iconsByPID[desc.primaryPID]
                ?? NSWorkspace.shared.icon(for: .applicationBundle)
            return AudioApp(
                id: desc.id,
                name: desc.name,
                bundleID: desc.bundleID,
                icon: icon,
                processObjectIDs: desc.processObjectIDs,
                isRunningOutput: desc.isRunningOutput
            )
        }

        let nextMain = groupedResult.mainApps.map(mapDescriptor)
        let nextHidden = groupedResult.hiddenProcesses.map(mapDescriptor)

        let changed = (nextMain != apps) || (nextHidden != hiddenProcesses)
        if nextMain != apps {
            apps = nextMain
        }
        if nextHidden != hiddenProcesses {
            hiddenProcesses = nextHidden
        }
        if changed {
            onAppsChanged?(nextMain + nextHidden)
        }
    }

    // MARK: - Listeners

    private func installListeners() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        processListListenerBlock = block
        var addr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(systemObj, &addr, listenerQueue, block)

        let center = NSWorkspace.shared.notificationCenter
        for notifName in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = center.addObserver(forName: notifName, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
            workspaceObservers.append(token)
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func removeListeners() {
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        if let block = processListListenerBlock {
            var addr = CoreAudioHelpers.makeAddress(selector: kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(systemObj, &addr, listenerQueue, block)
            processListListenerBlock = nil
        }

        for (procID, block) in observedProcessListeners {
            var addr = CoreAudioHelpers.makeAddress(selector: kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(procID, &addr, listenerQueue, block)
        }
        observedProcessListeners.removeAll()

        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    private func syncPerProcessOutputListeners(currentProcessIDs: Set<AudioObjectID>) {
        for (procID, block) in observedProcessListeners where !currentProcessIDs.contains(procID) {
            var addr = CoreAudioHelpers.makeAddress(selector: kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(procID, &addr, listenerQueue, block)
            observedProcessListeners.removeValue(forKey: procID)
        }

        for procID in currentProcessIDs where observedProcessListeners[procID] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
            var addr = CoreAudioHelpers.makeAddress(selector: kAudioProcessPropertyIsRunningOutput)
            let status = AudioObjectAddPropertyListenerBlock(procID, &addr, listenerQueue, block)
            if status == noErr {
                observedProcessListeners[procID] = block
            }
        }
    }
}
