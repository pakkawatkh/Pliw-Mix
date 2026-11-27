import AppKit
import Combine
import SwiftUI

@MainActor
public final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: MixerViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?

    public init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configurePopover()
        configureStatusButton()
        observeActiveState()
    }

    public func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    public func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        viewModel.setPopoverOpen(true)
        installOutsideClickMonitor()
    }

    public func closePopover() {
        popover.performClose(nil)
        viewModel.setPopoverOpen(false)
        removeOutsideClickMonitor()
    }

    public func popoverDidClose(_ notification: Notification) {
        viewModel.setPopoverOpen(false)
        removeOutsideClickMonitor()
    }

    // MARK: - Private

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let contentView = MixerPopoverView(viewModel: viewModel) {
            NSApplication.shared.terminate(nil)
        }
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        updateButtonAppearance(activeTapCount: viewModel.activeTapCount)
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(from: sender)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        closePopover()
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Pliw Mix", action: #selector(menuOpenPopover), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let resetItem = NSMenuItem(title: "Reset All Apps to 100%", action: #selector(menuResetAll), keyEquivalent: "")
        resetItem.target = self
        resetItem.isEnabled = viewModel.hasAnyCustomSetting
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Pliw Mix", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenPopover() {
        showPopover()
    }

    @objc private func menuResetAll() {
        viewModel.resetAllApps()
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    private func observeActiveState() {
        viewModel.$activeTapCount
            .sink { [weak self] count in
                self?.updateButtonAppearance(activeTapCount: count)
            }
            .store(in: &cancellables)
    }

    private func updateButtonAppearance(activeTapCount: Int) {
        guard let button = statusItem.button else { return }
        let symbolName = activeTapCount > 0 ? "slider.horizontal.3" : "speaker.wave.2"
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pliw Mix")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img
        button.imagePosition = activeTapCount > 0 ? .imageLeading : .imageOnly
        button.title = activeTapCount > 0 ? " \(activeTapCount)" : ""
        button.toolTip = activeTapCount > 0
            ? "Pliw Mix — Controlling \(activeTapCount) \(activeTapCount == 1 ? "app" : "apps")"
            : "Pliw Mix — Per-App Audio Mixer"
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.popover.isShown == true {
                    self?.closePopover()
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
