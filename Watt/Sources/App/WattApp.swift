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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var powerMonitor: PowerMonitorService?
    var systemMetrics: SystemMetricsService?
    private var cancellables = Set<AnyCancellable>()
    private var statusBarTimer: DispatchSourceTimer?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        powerMonitor = PowerMonitorService()
        systemMetrics = SystemMetricsService()

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
        statusBarTimer = DispatchSource.makeTimerSource(queue: .main)
        statusBarTimer?.schedule(deadline: .now(), repeating: .milliseconds(500))
        statusBarTimer?.setEventHandler { [weak self] in
            self?.updateStatusBarIcon()
        }
        statusBarTimer?.resume()

        powerMonitor?.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }
            .store(in: &cancellables)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true

        let hostingController = NSHostingController(rootView: ContentView(powerMonitor: powerMonitor!, systemMetrics: systemMetrics!))
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 520)
        popover?.contentViewController = hostingController
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
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }

        let power = powerMonitor?.currentPower ?? 0
        let powerText = String(format: "%.2fW", abs(power))
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        button.image = nil
        button.attributedTitle = NSAttributedString(string: powerText, attributes: textAttrs)
    }
}
