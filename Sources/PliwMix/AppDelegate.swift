import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: MixerViewModel?
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let vm = MixerViewModel()
        let controller = StatusBarController(viewModel: vm)
        self.viewModel = vm
        self.statusBarController = controller

        // Show popover briefly on fresh launch so the user immediately sees Pliw Mix
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            controller.showPopover()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        viewModel?.shutdown()
    }
}
