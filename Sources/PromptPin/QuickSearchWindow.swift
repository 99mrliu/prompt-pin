import AppKit
import SwiftUI
import Combine

/// Borderless floating panel in the Spotlight position (top center of the active screen).
final class QuickSearchPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Appear over full-screen Spaces and other apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class QuickSearchWindowController: NSObject {
    private let panel: QuickSearchPanel
    private let model: QuickSearchModel
    private var heightSink: AnyCancellable?
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private var hideWorkItem: DispatchWorkItem?

    init(store: Store) {
        let model = QuickSearchModel(store: store)
        self.model = model
        let hosting = NSHostingController(rootView: QuickSearchView(model: model))
        panel = QuickSearchPanel(contentViewController: hosting)
        super.init()
        model.onCopied = { [weak self] in self?.scheduleHide() }
        heightSink = model.$panelHeight
            .removeDuplicates()
            .sink { [weak self] height in
                self?.resizePanel(to: height)
            }
    }

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        cancelScheduledHide()
        model.reset()
        positionPanel(height: model.panelHeight)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installEventHandling()
    }

    func hide() {
        cancelScheduledHide()
        removeEventHandling()
        panel.orderOut(nil)
    }

    private func scheduleHide() {
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    // MARK: - Positioning / sizing

    private func resizePanel(to height: CGFloat) {
        guard panel.isVisible else { return }
        let frame = panel.frame
        // Keep the top edge fixed while height changes.
        let nextFrame = NSRect(x: frame.origin.x, y: frame.maxY - height,
                               width: frame.width, height: height)
        panel.setFrame(nextFrame, display: true, animate: false)
    }

    private func positionPanel(height: CGFloat) {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let width: CGFloat = 640
        let originX = visible.midX - width / 2
        // Roughly a quarter of the way down from the top, Spotlight-style.
        let originY = visible.maxY - visible.height * 0.26 - height
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: false)
    }

    // MARK: - Keyboard / focus events

    private func installEventHandling() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case Self.escapeKey:
                    Task { @MainActor in self.hide() }
                    return nil
                case Self.returnKey, Self.numpadReturnKey:
                    Task { @MainActor in self.model.commit() }
                    return nil
                case Self.downArrowKey:
                    Task { @MainActor in self.model.move(by: 1) }
                    return nil
                case Self.upArrowKey:
                    Task { @MainActor in self.model.move(by: -1) }
                    return nil
                default:
                    return event
                }
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.hide() }
                }
        }
    }

    private func removeEventHandling() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
    }

    // Carbon virtual key codes (same values as HIToolbox kVK_*).
    private static let escapeKey: UInt16 = 53
    private static let returnKey: UInt16 = 36
    private static let numpadReturnKey: UInt16 = 76
    private static let downArrowKey: UInt16 = 125
    private static let upArrowKey: UInt16 = 126

    #if DEBUG
    /// Renders the panel's own view tree to PNG without requiring Screen Recording permission.
    func snapshotPNG() -> Data? {
        guard let view = panel.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
    #endif
}

extension Notification.Name {
    /// Posted by the settings menu to present the quick-search panel without a hot key.
    static let promptPinPresentQuickSearch = Notification.Name("PromptPin.presentQuickSearch")
}
