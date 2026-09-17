import AppKit
import Combine
import SwiftUI

@main
struct CodexMonitorLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let popoverWidth: CGFloat = 320
    private let pinnedPreferenceKey = "CodexMonitorLite.isPinned"
    private let pinnedFrameName = "CodexMonitorLite.PinnedPanel"
    private let fixturePinnedFrameName = "CodexMonitorLite.FixturePinnedPanel"
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var pinnedPanel: NSPanel?
    private var hostingController: NSHostingController<MonitorView>?
    private var viewModel: MonitorViewModel?
    private var sizeCancellable: AnyCancellable?
    private var preferredContentHeight: CGFloat = 590
    private var isFixtureMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = fixtureKind(in: arguments)
        isFixtureMode = fixture != nil
        let adapter: any SourceAdapter = fixture.map(FixtureSourceAdapter.init(kind:)) ?? CodexSourceAdapter()
        let store = fixture.map { _ in
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexMonitorLite-Fixture-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            return JSONTaskStore(fileURL: temporaryRoot.appendingPathComponent("state.json"))
        } ?? JSONTaskStore()
        let model = MonitorViewModel(adapter: adapter, store: store)
        viewModel = model
        let shouldStartPinned = isFixtureMode
            ? arguments.contains("--start-pinned")
            : UserDefaults.standard.bool(forKey: pinnedPreferenceKey)
        model.setPinned(shouldStartPinned)
        sizeCancellable = Publishers.CombineLatest3(
            model.$tasks,
            model.$connectionState,
            model.$selectedFilter
        )
            .sink { [weak self, weak model] _, connectionState, _ in
                guard let self, let model else { return }
                self.resizeContent(taskCount: model.visibleTasks.count, connectionState: connectionState)
            }

        let root = MonitorView(
            viewModel: model,
            onTogglePin: { [weak self] in self?.togglePinned() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: root)
        self.hostingController = hostingController
        popover.contentSize = NSSize(width: popoverWidth, height: preferredContentHeight)
        popover.behavior = arguments.contains("--show-popover") ? .applicationDefined : .transient
        popover.animates = true
        popover.contentViewController = hostingController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "Codex Monitor Lite")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Codex Monitor Lite"
        }
        statusItem = item
        model.start()

        if shouldStartPinned {
            DispatchQueue.main.async { [weak self] in self?.showPinnedPanel(initialFrame: nil, persist: false) }
        } else if arguments.contains("--show-popover") {
            scheduleTestPopover(attempt: 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if viewModel?.isPinned == true {
            pinnedPanel?.orderFrontRegardless()
            return
        }
        popover.isShown ? popover.performClose(sender) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        let screen = button.window?.screen ?? NSScreen.main
        let maximumHeight = max(320, (screen?.visibleFrame.height ?? 720) - 24)
        popover.contentSize = NSSize(width: popoverWidth, height: min(preferredContentHeight, maximumHeight))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleTestPopover(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.statusItem?.button?.window != nil else {
                if attempt < 25 { self.scheduleTestPopover(attempt: attempt + 1) }
                return
            }
            self.showPopover()
        }
    }

    private func resizeContent(taskCount: Int, connectionState: SourceConnectionState) {
        let bannerHeight: CGFloat = if case .failed = connectionState { 44 } else { 0 }
        if taskCount == 0 {
            preferredContentHeight = 320 + bannerHeight
        } else {
            preferredContentHeight = min(
                634,
                max(320, 150 + CGFloat(min(taskCount, 4)) * 110 + bannerHeight)
            )
        }
        if popover.isShown {
            let maximumHeight = max(320, (statusItem?.button?.window?.screen?.visibleFrame.height ?? 720) - 24)
            popover.contentSize.height = min(preferredContentHeight, maximumHeight)
        }
        resizePinnedPanelIfNeeded()
    }

    private func togglePinned() {
        if viewModel?.isPinned == true {
            hidePinnedPanel()
        } else {
            let popoverFrame = popover.contentViewController?.view.window?.frame
            showPinnedPanel(initialFrame: popoverFrame, persist: true)
        }
    }

    private func showPinnedPanel(initialFrame: NSRect?, persist: Bool) {
        guard let model = viewModel, let hostingController else { return }
        popover.performClose(nil)
        popover.contentViewController = nil

        let panel: NSPanel
        if let existing = pinnedPanel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: popoverWidth, height: preferredContentHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true

            let frameName = isFixtureMode ? fixturePinnedFrameName : pinnedFrameName
            let restoredFrame = panel.setFrameUsingName(frameName)
            panel.setFrameAutosaveName(frameName)
            if !restoredFrame {
                if let initialFrame {
                    panel.setFrameTopLeftPoint(NSPoint(x: initialFrame.minX, y: initialFrame.maxY))
                } else {
                    panel.center()
                }
            }
            pinnedPanel = panel
        }

        panel.contentViewController = hostingController
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true
        model.setPinned(true)
        if persist && !isFixtureMode {
            UserDefaults.standard.set(true, forKey: pinnedPreferenceKey)
        }
        resizePinnedPanelIfNeeded()
        panel.orderFrontRegardless()
    }

    private func hidePinnedPanel() {
        guard let model = viewModel, let hostingController else { return }
        pinnedPanel?.orderOut(nil)
        pinnedPanel?.contentViewController = nil
        popover.contentViewController = hostingController
        model.setPinned(false)
        if !isFixtureMode {
            UserDefaults.standard.set(false, forKey: pinnedPreferenceKey)
        }
        showPopover()
    }

    private func resizePinnedPanelIfNeeded() {
        guard viewModel?.isPinned == true, let panel = pinnedPanel else { return }
        let maximumHeight = max(320, (panel.screen?.visibleFrame.height ?? 720) - 24)
        let height = min(preferredContentHeight, maximumHeight)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: popoverWidth, height: height)
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
    }

    private func fixtureKind(in arguments: [String]) -> FixtureKind? {
        guard let index = arguments.firstIndex(of: "--fixture"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return FixtureKind(rawValue: arguments[index + 1])
    }
}
