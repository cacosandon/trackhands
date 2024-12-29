import Cocoa
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var warningWindow: WarningOverlay?
    private var cancellable: AnyCancellable?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupWarningOverlay()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "✋🏼"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Preview", action: #selector(togglePopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(quitApp: quitApp)
                .environmentObject(CameraManager.shared)
        )

        self.popover = popover

        if let button = statusItem?.button {
            button.action = #selector(NSStatusBarButton.rightMouseDown)
            button.target = self
        }
    }

    @objc private func togglePopover() {
        guard let statusBarButton = statusItem?.button else { return }

        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
                CameraManager.shared.isPopoverOpen = false
            } else {
                popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: .minY)
                CameraManager.shared.isPopoverOpen = true
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupWarningOverlay() {
        warningWindow = WarningOverlay()
        cancellable = CameraManager.shared.$handInMouth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] handInMouth in
                if handInMouth {
                    self?.showWarningOverlay()
                } else {
                    self?.hideWarningOverlay()
                }
            }
    }

    private func showWarningOverlay() {
        guard let screen = NSScreen.main else { return }
        warningWindow?.setFrame(screen.frame, display: true)
        warningWindow?.orderFront(nil)
    }

    private func hideWarningOverlay() {
        warningWindow?.orderOut(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        CameraManager.shared.cleanup()
        cancellable?.cancel()
    }
}
