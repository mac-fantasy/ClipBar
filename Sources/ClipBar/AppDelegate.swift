import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let controller = ClipboardController()
    private let updater = UpdateController()
    private var previousApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
        {
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipBar 剪贴板历史")
            button.image?.isTemplate = true
            button.toolTip = "ClipBar · 剪贴板历史"
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.contentViewController = NSHostingController(
            rootView: HistoryView(controller: controller, updater: updater))
        updater.onCheckForUpdates = { [weak self] in self?.popover.performClose(nil) }
        controller.onCopied = { [weak self] in
            self?.popover.performClose(nil)
            self?.previousApplication?.activate(options: [])
        }
        controller.start()
        updater.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }

    func popoverDidShow(_ notification: Notification) {
        // Start without a focused control on every opening; Tab can still enter the key-view loop.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            previousApplication = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }
}
