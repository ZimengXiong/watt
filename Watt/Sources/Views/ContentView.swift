import SwiftUI
import ServiceManagement

private func batteryColor(for level: Int) -> Color { level <= 20 ? .red : level <= 40 ? .orange : .green }
private func batteryIcon(for level: Int) -> String { level <= 10 ? "battery.0" : level <= 25 ? "battery.25" : level <= 50 ? "battery.50" : level <= 75 ? "battery.75" : "battery.100" }

// MARK: - Liquid Glass helpers (macOS 26+), with graceful fallback

extension View {
    /// Applies a Liquid Glass material clipped to `shape` on macOS 26+,
    /// falling back to a translucent material + hairline on older systems.
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(Color.primary.opacity(0.035))
                .clipShape(shape)
                .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }

    /// A circular glass control on macOS 26+, falling back to the custom footer style.
    @ViewBuilder
    func glassControl() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            self.buttonStyle(FooterButtonStyle())
        }
    }
}

struct ContentView: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @ObservedObject var systemMetrics: SystemMetricsService
    @Environment(\.colorScheme) var colorScheme
    @State private var route: PanelRoute = .main

    var body: some View {
        panel
            .frame(width: 288)
            .fixedSize()
    }

    @ViewBuilder
    private var panel: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                routedContent
            }
        } else {
            routedContent
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        ZStack(alignment: .top) {
            panelBackground
                .ignoresSafeArea()

            Group {
                switch route {
                case .main:
                    mainPanel
                        .transition(.opacity)
                case .settings:
                    SettingsView(powerMonitor: powerMonitor, onBack: { goMain() })
                        .transition(.opacity)
                case .about:
                    AboutView(onBack: { goMain() })
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: route)
    }

    private func goMain() { route = .main }

    /// The whole-panel backing: the standard legible menu material (as native menus use),
    /// so text stays readable. Liquid Glass is reserved for the cards and control chips.
    private var panelBackground: some View {
        VisualEffectView(material: .menu, blendingMode: .behindWindow)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            HeroHeaderView(powerMonitor: powerMonitor)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    SystemMetricsSection(metricsService: systemMetrics)
                    PowerFlowSection(powerMonitor: powerMonitor)
                    BatterySection(powerMonitor: powerMonitor)
                    HistorySection(powerMonitor: powerMonitor)
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 2)
            }

            AppFooterView(powerMonitor: powerMonitor, route: $route)
        }
    }
}

enum PanelRoute {
    case main, settings, about
}

// MARK: - Inline panel header with a back control

struct InlinePanelHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .glassControl()

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Hero Header

struct HeroHeaderView: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", powerMonitor.currentPower))
                    .font(.system(size: 44, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)

            if let time = timeText {
                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }

    private var timeText: String? {
        guard let b = powerMonitor.batteryInfo else { return nil }
        if b.isCharging { return b.formattedTimeToFull == "--" ? nil : "\(b.formattedTimeToFull) to full" }
        if !b.isPluggedIn { return b.formattedTimeRemaining == "--" ? nil : "\(b.formattedTimeRemaining) left" }
        return "Fully Charged"
    }
}

// MARK: - Battery Section

struct BatterySection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        NativeSectionView(title: "Battery") {
            if let battery = powerMonitor.batteryInfo {
                HStack(alignment: .top, spacing: 10) {
                    BatteryIconView(
                        percentage: battery.currentCapacity,
                        voltage: battery.voltage,
                        currentCapacityRaw: battery.currentCapacityRaw,
                        maxCapacity: battery.maxCapacity,
                        nominalVoltage: battery.nominalVoltage,
                        color: batteryColor(for: battery.currentCapacity)
                    )
                    .frame(maxHeight: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        StatRow(label: "Cycles", value: "\(battery.cycleCount)")
                        StatRow(label: "Temp", value: battery.temperature > 0 ? String(format: "%.0f°C", battery.temperature) : "—")
                        StatRow(label: "Health", value: battery.batteryHealth > 0 ? String(format: "%.0f%%", battery.batteryHealth) : "—")
                    }

                    Spacer()

                    if let charger = powerMonitor.chargerInfo, charger.isConnected {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 3) {
                                if charger.isAppleAdapter {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                if charger.watts > 0 {
                                    Text("\(charger.watts)W")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }

                            if charger.watts > 0 {
                                let (voltage, current) = usbcPDSpecs(watts: charger.watts)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0fV", voltage))
                                    Text(String(format: "%.1fA", current))
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }

    private func usbcPDSpecs(watts: Int) -> (Double, Double) {
        let v: Double = watts <= 15 ? 5 : watts <= 27 ? 9 : watts <= 45 ? 15 : watts <= 100 ? 20 : watts <= 140 ? 28 : watts <= 180 ? 36 : 48
        return (v, Double(watts) / v)
    }
}

enum BatteryDisplayMode: CaseIterable {
    case percentage
    case voltage
    case wattHours
}

struct BatteryIconView: View {
    let percentage: Int
    let voltage: Double
    let currentCapacityRaw: Int
    let maxCapacity: Int
    let nominalVoltage: Double
    let color: Color

    @State private var displayMode: BatteryDisplayMode = .percentage
    @State private var isHovered: Bool = false

    private let batteryWidth: CGFloat = 72
    private let batteryHeight: CGFloat = 36

    private var currentWh: Double { Double(currentCapacityRaw) * nominalVoltage / 1000.0 }
    private var maxWh: Double { Double(maxCapacity) * nominalVoltage / 1000.0 }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.35 : 0.2), lineWidth: 1)
                .frame(width: batteryWidth, height: batteryHeight)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.4 : 0.25))
                .frame(width: 3, height: 12)
                .offset(x: batteryWidth + 0.5)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color.gradient)
                .frame(width: max(3, (batteryWidth - 4) * CGFloat(percentage) / 100), height: batteryHeight - 4)
                .padding(.leading, 2)

            displayText
                .foregroundStyle(percentage > 50 ? .black : .white)
                .frame(width: batteryWidth, height: batteryHeight)
        }
        .frame(width: batteryWidth + 4, height: batteryHeight)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                cycleDisplayMode()
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var displayText: some View {
        switch displayMode {
        case .percentage:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(percentage)")
                    .font(.system(size: 14, weight: .semibold))
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.7)
            }
        case .voltage:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", voltage))
                    .font(.system(size: 13, weight: .semibold))
                Text("V")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.7)
            }
        case .wattHours:
            VStack(spacing: 0) {
                Text(String(format: "%.1f", currentWh))
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: "/ %.0f Wh", maxWh))
                    .font(.system(size: 8, weight: .medium))
                    .opacity(0.7)
            }
        }
    }

    private func cycleDisplayMode() {
        let allModes = BatteryDisplayMode.allCases
        if let currentIndex = allModes.firstIndex(of: displayMode) {
            let nextIndex = (currentIndex + 1) % allModes.count
            displayMode = allModes[nextIndex]
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(width: 80)
    }
}

// MARK: - Power Flow Section

struct PowerFlowSection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    private var isPluggedIn: Bool { powerMonitor.batteryInfo?.isPluggedIn ?? false }
    private var batteryPower: Double { powerMonitor.batteryPower }
    private var wallPower: Double { powerMonitor.wallPower }
    private var systemPower: Double { powerMonitor.systemPower }

    private var isBatteryCharging: Bool { batteryPower < -0.5 }
    private var isBatteryDischarging: Bool { batteryPower > 0.5 }

    var body: some View {
        NativeSectionView(title: "Power Flow") {
            HStack(alignment: .center, spacing: 6) {
                if isPluggedIn && isBatteryDischarging {
                    VStack(spacing: 4) {
                        PowerNodeView(
                            label: "Wall",
                            value: String(format: "%.1fW", wallPower),
                            icon: "bolt.fill",
                            color: .orange
                        )
                        PowerNodeView(
                            label: "Battery",
                            value: String(format: "%.1fW", batteryPower),
                            icon: batteryIcon(for: powerMonitor.batteryInfo?.currentCapacity ?? 50),
                            color: .orange
                        )
                    }
                } else if isPluggedIn {
                    PowerNodeView(
                        label: "Wall",
                        value: String(format: "%.1fW", wallPower),
                        icon: "bolt.fill",
                        color: .orange
                    )
                } else {
                    PowerNodeView(
                        label: "Battery",
                        value: String(format: "%.1fW", batteryPower),
                        icon: batteryIcon(for: powerMonitor.batteryInfo?.currentCapacity ?? 50),
                        color: batteryColor(for: powerMonitor.batteryInfo?.currentCapacity ?? 50)
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                if isPluggedIn && isBatteryCharging {
                    VStack(spacing: 4) {
                        PowerNodeView(
                            label: "System",
                            value: String(format: "%.1fW", systemPower),
                            icon: "laptopcomputer",
                            color: .blue
                        )
                        PowerNodeView(
                            label: "Battery",
                            value: String(format: "%.1fW", abs(batteryPower)),
                            icon: "battery.100.bolt",
                            color: .green
                        )
                    }
                } else {
                    PowerNodeView(
                        label: "System",
                        value: String(format: "%.1fW", systemPower),
                        icon: "laptopcomputer",
                        color: .blue
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: flowLayoutKey)
        }
    }

    /// Changes whenever the number of rows on either side flips, so the
    /// resize can animate smoothly instead of snapping the whole window.
    private var flowLayoutKey: Int {
        (isPluggedIn ? 1 : 0) | (isBatteryCharging ? 2 : 0) | (isBatteryDischarging ? 4 : 0)
    }
}

// MARK: - Native Section View

struct NativeSectionView<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            content
                .padding(8)
                .frame(maxWidth: .infinity)
                .glassCard(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct PowerNodeView: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - History Section

struct HistorySection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        NativeSectionView(title: "Statistics") {
            VStack(spacing: 8) {
                PowerGraph(readings: powerMonitor.energyHistory)
                    .frame(height: 32)

                Divider()
                    .opacity(0.3)

                HStack(spacing: 0) {
                    StatColumn(
                        items: [
                            ("Rate", formatBatteryRate(powerMonitor.batteryRatePerMinute), powerMonitor.batteryRatePerMinute >= 0 ? .green : .orange),
                            ("", String(format: "%.1f¢/hr", powerMonitor.costPerHour * 100), .red)
                        ]
                    )

                    Divider()
                        .opacity(0.3)
                        .frame(height: 36)

                    StatColumn(
                        items: [
                            ("Today", formatEnergy(powerMonitor.todayEnergyUsed), nil),
                            ("", String(format: "%.1f¢", powerMonitor.todayCost * 100), nil)
                        ]
                    )

                    Divider()
                        .opacity(0.3)
                        .frame(height: 36)

                    StatColumn(
                        items: [
                            ("Lifetime", formatEnergy(powerMonitor.lifetimeEnergyUsed), nil),
                            ("", String(format: "%.1f¢", powerMonitor.lifetimeCost * 100), nil)
                        ]
                    )
                }
            }
        }
    }

    private func formatEnergy(_ wh: Double) -> String { wh >= 1000 ? String(format: "%.1f kWh", wh / 1000) : String(format: "%.0f Wh", wh) }
    private func formatBatteryRate(_ rate: Double) -> String { String(format: "%@%.2f%%/m", rate >= 0 ? "+" : "", rate) }
}

struct StatColumn: View {
    let items: [(label: String, value: String, color: Color?)]

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if !item.label.isEmpty {
                    Text(item.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text(item.value)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.color ?? .primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PowerGraph: View {
    let readings: [EnergyReading]

    private var powerValues: [Double] { readings.map { $0.power } }
    private var maxP: Double { max(powerValues.max() ?? 1, 1) }
    private var minP: Double { max(0, (powerValues.min() ?? 0) * 0.8) }
    private var range: Double { max(maxP - minP, 0.1) }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard readings.count > 1 else { return }

                let step = size.width / CGFloat(readings.count - 1)

                var fillPath = Path()
                fillPath.move(to: CGPoint(x: 0, y: size.height))
                for (i, power) in powerValues.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat((power - minP) / range))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.closeSubpath()

                var strokePath = Path()
                for (i, power) in powerValues.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat((power - minP) / range))
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
                    else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }

                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.02)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                context.stroke(
                    strokePath,
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - Footer

struct AppFooterView: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @Binding var route: PanelRoute

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .glassControl()

            Spacer()

            Link(destination: URL(string: "https://github.com/zimengxiong/watt")!) {
                GitHubIcon()
                    .frame(width: 15, height: 15)
                    .frame(width: 20, height: 20)
            }
            .glassControl()

            Button(action: { route = .about }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .glassControl()

            Button(action: { route = .settings }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .glassControl()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

struct FooterButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { isHovered = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @ObservedObject var daemon = PowerMetricsDaemon.shared
    var onBack: () -> Void
    @State private var costInput: String = ""
    @State private var zipCodeInput: String = ""
    @State private var showResetConfirmation: Bool = false
    @State private var showUninstallConfirmation: Bool = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InlinePanelHeader(title: "Settings", onBack: onBack)

            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Electricity Cost") {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0.120", text: $costInput)
                                .textFieldStyle(.plain)
                                .frame(width: 52)
                                .onSubmit { applyCost() }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )

                        Text("per kWh")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Apply") { applyCost() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    HStack(spacing: 4) {
                        Text("Current:")
                            .foregroundStyle(.secondary)
                        Text("$\(String(format: "%.3f", powerMonitor.electricityCostPerKwh))/kWh")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 11, weight: .medium))
                }

                SettingsSection(title: "Auto-detect Rate") {
                    HStack(spacing: 8) {
                        TextField("ZIP Code", text: $zipCodeInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        Button("Lookup") {
                            powerMonitor.setZipCode(zipCodeInput)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                costInput = String(format: "%.3f", powerMonitor.electricityCostPerKwh)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()
                    }

                    Toggle(isOn: Binding(
                        get: { powerMonitor.autoFindElectricityCost },
                        set: { powerMonitor.setAutoFindCost($0) }
                    )) {
                        Text("Auto-detect by IP location")
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }

                SettingsSection(title: "Startup") {
                    Toggle(isOn: $launchAtLogin) {
                        Text("Launch at login")
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                }

                SettingsSection(title: "Data") {
                    if showResetConfirmation {
                        HStack(spacing: 8) {
                            Text("Reset all statistics?")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                showResetConfirmation = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Reset") {
                                powerMonitor.resetAllStatistics()
                                showResetConfirmation = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.red)
                        }
                    } else {
                        Button("Reset All Statistics") {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if daemon.isInstalled {
                    SettingsSection(title: "Metrics Service") {
                        if showUninstallConfirmation {
                            HStack(spacing: 8) {
                                Text("Remove service?")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel") {
                                    showUninstallConfirmation = false
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Remove") {
                                    daemon.uninstall()
                                    showUninstallConfirmation = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(.red)
                            }
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 10))
                                Text("Installed")
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button("Uninstall") {
                                    showUninstallConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            costInput = String(format: "%.3f", powerMonitor.electricityCostPerKwh)
            zipCodeInput = powerMonitor.zipCode
        }
    }

    private func applyCost() {
        if let cost = Double(costInput), cost > 0 {
            powerMonitor.setElectricityCost(cost)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .font(.system(size: 12))
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView(powerMonitor: PowerMonitorService(), systemMetrics: SystemMetricsService())
}