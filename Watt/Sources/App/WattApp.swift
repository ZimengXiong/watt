import SwiftUI

@main
struct WattApp: App {
    @StateObject private var powerMonitor = PowerMonitorService()
    @StateObject private var systemMetrics = SystemMetricsService()

    var body: some Scene {
        MenuBarExtra {
            ContentView(powerMonitor: powerMonitor, systemMetrics: systemMetrics)
                .onAppear {
                    powerMonitor.setAppVisible(true)
                    systemMetrics.setAppVisible(true)
                }
                .onDisappear {
                    powerMonitor.setAppVisible(false)
                    systemMetrics.setAppVisible(false)
                }
        } label: {
            Text(String(format: "%.2fW", abs(powerMonitor.currentPower)))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
