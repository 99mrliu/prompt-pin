import AppKit
import SwiftUI

@main struct PromptPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = Store()
    private let preview = ProcessInfo.processInfo.environment["PROMPT_PIN_UI_PREVIEW"] == "1"
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid two menu-bar instances editing the same library.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: "Prompt Pin 提示词")
            button.image?.isTemplate = true
            button.toolTip = "Prompt Pin · 你的随身提示词库"
            button.target = self; button.action = #selector(toggle)
        }
        popover.contentSize = NSSize(width: 780, height: 580)
        popover.behavior = preview ? .applicationDefined : .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: LibraryView(store: store))
        store.holdOpen = { [weak self] hold in self?.popover.behavior = (hold || self?.preview == true) ? .applicationDefined : .transient }
        if CommandLine.arguments.contains("--show") { toggle() }
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
