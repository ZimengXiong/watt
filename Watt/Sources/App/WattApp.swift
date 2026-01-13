import SwiftUI
import Combine

@main
struct WattApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var powerMonitor: PowerMonitorService?
    var systemMetrics: SystemMetricsService?
    private var cancellables = Set<AnyCancellable>()
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var lastDisplayedPower: Double = -1
    private var isAppVisible: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        (powerMonitor, systemMetrics) = (PowerMonitorService(), SystemMetricsService())
        setupMenuBar()
        setupPopover()
        setupRealtimeUpdates()
        setupEventMonitor()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 58)

        if let button = statusItem?.button {
            updateStatusBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupRealtimeUpdates() {
        powerMonitor?.objectWillChange
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self

        let hostingController = NSHostingController(rootView: ContentView(powerMonitor: powerMonitor!, systemMetrics: systemMetrics!))
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 520)
        popover?.contentViewController = hostingController
    }

    func popoverDidClose(_ notification: Notification) {
        onPopoverClosed()
    }

    private func setupEventMonitor() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func closePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            onPopoverClosed()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            onPopoverOpened()
        }
    }

    private func onPopoverOpened() {
        isAppVisible = true
        (powerMonitor?.setAppVisible(true), systemMetrics?.setAppVisible(true))
    }

    private func onPopoverClosed() {
        isAppVisible = false
        (powerMonitor?.setAppVisible(false), systemMetrics?.setAppVisible(false))
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button, let power = powerMonitor?.currentPower, abs(power - lastDisplayedPower) >= 0.1 else { return }
        lastDisplayedPower = power
        button.image = nil
        button.attributedTitle = NSAttributedString(string: String(format: "%.2fW", abs(power)),
                                                     attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
}
