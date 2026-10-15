import AppKit
import SwiftUI
import Carbon.HIToolbox
import PromptPinCore

@main struct PromptPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = Store()
    private var quickSearch: QuickSearchWindowController?
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

        quickSearch = QuickSearchWindowController(store: store)
        HotKeyManager.shared.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: [UInt32(controlKey | cmdKey), UInt32(optionKey | cmdKey)]) { [weak self] in
                DispatchQueue.main.async { self?.quickSearch?.toggle() }
            }
        NotificationCenter.default.addObserver(
            forName: .promptPinPresentQuickSearch,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.quickSearch?.show() }
            }

        if CommandLine.arguments.contains("--show") { toggle() }
        #if DEBUG
        if CommandLine.arguments.contains("--quick-search-self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.runQuickSearchSelfTest()
            }
        }
        #endif
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

    #if DEBUG
    /// Debug-only end-to-end check without Accessibility permission: posts key events to our own
    /// process. The pasteboard must already contain the search query; asserts the copied hit value.
    private func runQuickSearchSelfTest() {
        guard let dataDirectory = ProcessInfo.processInfo.environment["PROMPT_PIN_DATA_DIR"],
              !dataDirectory.isEmpty,
              URL(fileURLWithPath: dataDirectory, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
                != LibraryDisk.standard.directory.standardizedFileURL.resolvingSymlinksInPath(),
              store.library.prompts.contains(where: { $0.body.contains("COPIED_BODY_MARKER_9f3k") }) else {
            print("SELFTEST FAIL: an isolated PROMPT_PIN_DATA_DIR with the synthetic fixture is required")
            exit(1)
        }
        let snapshotDir = ProcessInfo.processInfo.environment["PROMPT_PIN_SNAPSHOT_DIR"] ?? "/tmp"
        quickSearch?.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Self.postKey(virtualKey: 9, flags: .maskCommand) // Cmd+V: paste the query
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            Self.writeSnapshot(from: self.quickSearch, to: snapshotDir + "/qs-panel-search.png")
            Self.postKey(virtualKey: 36) // Return: copy selected hit
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Self.writeSnapshot(from: self.quickSearch, to: snapshotDir + "/qs-panel-copied.png")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let result = NSPasteboard.general.string(forType: .string) ?? ""
            if result.contains("COPIED_BODY_MARKER_9f3k") {
                print("SELFTEST PASS: panel, paste, search and copy-on-return work")
                exit(0)
            }
            print("SELFTEST FAIL: copied value did not match the synthetic fixture (clipboard content omitted)")
            exit(1)
        }
    }

    private static func writeSnapshot(from controller: QuickSearchWindowController?, to path: String) {
        guard let data = controller?.snapshotPNG() else {
            print("SELFTEST WARN: no snapshot data for \(path)")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func postKey(virtualKey: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.postToPid(getpid())
        up?.postToPid(getpid())
    }
    #endif
}
