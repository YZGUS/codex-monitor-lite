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
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var viewModel: MonitorViewModel?
    private var sizeCancellable: AnyCancellable?
    private var preferredContentHeight: CGFloat = 700

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = fixtureKind(in: arguments)
        let adapter: any SourceAdapter = fixture.map(FixtureSourceAdapter.init(kind:)) ?? CodexSourceAdapter()
        let store = fixture.map { _ in
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexMonitorLite-Fixture-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            return JSONTaskStore(fileURL: temporaryRoot.appendingPathComponent("state.json"))
        } ?? JSONTaskStore()
        let model = MonitorViewModel(adapter: adapter, store: store)
        viewModel = model
        sizeCancellable = Publishers.CombineLatest(model.$tasks, model.$connectionState)
            .sink { [weak self] tasks, connectionState in
                self?.resizePopover(taskCount: tasks.count, connectionState: connectionState)
            }

        let root = MonitorView(
            viewModel: model,
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentSize = NSSize(width: popoverWidth, height: preferredContentHeight)
        popover.behavior = arguments.contains("--show-popover") ? .applicationDefined : .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: root)

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

        if arguments.contains("--show-popover") {
            scheduleTestPopover(attempt: 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
    }

    @objc private func togglePopover(_ sender: Any?) {
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

    private func resizePopover(taskCount: Int, connectionState: SourceConnectionState) {
        let bannerHeight: CGFloat = if case .failed = connectionState { 44 } else { 0 }
        if taskCount == 0 {
            preferredContentHeight = 320 + bannerHeight
        } else {
            preferredContentHeight = min(
                700,
                max(320, 150 + CGFloat(min(taskCount, 5)) * 110 + bannerHeight)
            )
        }
        if popover.isShown {
            let maximumHeight = max(320, (statusItem?.button?.window?.screen?.visibleFrame.height ?? 720) - 24)
            popover.contentSize.height = min(preferredContentHeight, maximumHeight)
        }
    }

    private func fixtureKind(in arguments: [String]) -> FixtureKind? {
        guard let index = arguments.firstIndex(of: "--fixture"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return FixtureKind(rawValue: arguments[index + 1])
    }
}
