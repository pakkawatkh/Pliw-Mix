import CoreAudio
import XCTest
@testable import PliwMix

final class ProcessGrouperTests: XCTestCase {
    func testGroupsChromeBraveAndSafariHelpersUnderMainApps() {
        let runningApps: [RunningAppInfo] = [
            RunningAppInfo(pid: 100, bundleID: "com.google.Chrome", name: "Google Chrome", isRegularApp: true),
            RunningAppInfo(pid: 200, bundleID: "com.brave.Browser", name: "Brave Browser", isRegularApp: true),
            RunningAppInfo(pid: 300, bundleID: "com.apple.Safari", name: "Safari", isRegularApp: true)
        ]

        let rawProcesses: [RawAudioProcess] = [
            RawAudioProcess(objectID: 10, pid: 100, bundleID: "com.google.Chrome", processName: "Google Chrome", isRunningOutput: false, isRunning: true),
            RawAudioProcess(objectID: 11, pid: 101, bundleID: "com.google.Chrome.helper.renderer", processName: "Google Chrome Helper (Renderer)", isRunningOutput: true, isRunning: true),
            RawAudioProcess(objectID: 20, pid: 201, bundleID: "com.brave.Browser.helper", processName: "Brave Browser Helper", isRunningOutput: true, isRunning: true),
            RawAudioProcess(objectID: 30, pid: 301, bundleID: "com.apple.WebKit.GPU", processName: "com.apple.WebKit.GPU", isRunningOutput: false, isRunning: true),
            RawAudioProcess(objectID: 99, pid: 999, bundleID: "com.local.pliw-mix", processName: "pliw-mix", isRunningOutput: true, isRunning: true)
        ]

        let grouped = ProcessGrouper.group(
            processes: rawProcesses,
            runningApps: runningApps,
            selfPID: 999,
            parentPIDProvider: { _ in nil }
        )

        XCTAssertEqual(grouped.count, 3)
        XCTAssertEqual(grouped[0].id, "com.brave.Browser")
        XCTAssertEqual(grouped[0].processObjectIDs, [20])
        XCTAssertTrue(grouped[0].isRunningOutput)

        XCTAssertEqual(grouped[1].id, "com.google.Chrome")
        XCTAssertEqual(grouped[1].processObjectIDs, [10, 11])
        XCTAssertTrue(grouped[1].isRunningOutput)

        XCTAssertEqual(grouped[2].id, "com.apple.Safari")
        XCTAssertEqual(grouped[2].processObjectIDs, [30])
        XCTAssertFalse(grouped[2].isRunningOutput)
    }

    func testSeparatesSystemAndBackgroundProcessesIntoHiddenList() {
        let runningApps: [RunningAppInfo] = [
            RunningAppInfo(pid: 100, bundleID: "com.google.Chrome", name: "Google Chrome", isRegularApp: true),
            RunningAppInfo(pid: 400, bundleID: "com.apple.finder", name: "Finder", isRegularApp: true),
            RunningAppInfo(pid: 450, bundleID: "com.example.menubar-helper", name: "Menu Helper", isRegularApp: false)
        ]

        let rawProcesses: [RawAudioProcess] = [
            RawAudioProcess(objectID: 10, pid: 100, bundleID: "com.google.Chrome", processName: "Google Chrome", isRunningOutput: true, isRunning: true),
            RawAudioProcess(objectID: 40, pid: 400, bundleID: "com.apple.finder", processName: "Finder", isRunningOutput: false, isRunning: true),
            RawAudioProcess(objectID: 45, pid: 450, bundleID: "com.example.menubar-helper", processName: "Menu Helper", isRunningOutput: true, isRunning: true),
            RawAudioProcess(objectID: 50, pid: 500, bundleID: "com.apple.audio.DriverHelper", processName: "coreaudiod", isRunningOutput: false, isRunning: true)
        ]

        let result = ProcessGrouper.groupWithHidden(
            processes: rawProcesses,
            runningApps: runningApps,
            selfPID: 999,
            parentPIDProvider: { _ in nil }
        )

        // Only Chrome belongs in mainApps; Finder & non-regular Menu Helper move to hiddenProcesses; coreaudiod dropped
        XCTAssertEqual(result.mainApps.map(\.id), ["com.google.Chrome"])
        XCTAssertEqual(Set(result.hiddenProcesses.map(\.id)), Set(["com.apple.finder", "com.example.menubar-helper"]))
    }

    func testResolvesHelperViaParentPIDTree() {
        let runningApps: [RunningAppInfo] = [
            RunningAppInfo(pid: 500, bundleID: "com.valvesoftware.steam.game", name: "My Game", isRegularApp: true)
        ]
        let rawProcesses: [RawAudioProcess] = [
            RawAudioProcess(objectID: 55, pid: 502, bundleID: nil, processName: "audio-worker", isRunningOutput: true, isRunning: true)
        ]

        let parentMap: [pid_t: pid_t] = [502: 501, 501: 500]
        let grouped = ProcessGrouper.group(
            processes: rawProcesses,
            runningApps: runningApps,
            selfPID: 999,
            parentPIDProvider: { parentMap[$0] }
        )

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].id, "com.valvesoftware.steam.game")
        XCTAssertEqual(grouped[0].name, "My Game")
        XCTAssertEqual(grouped[0].processObjectIDs, [55])
    }
}
