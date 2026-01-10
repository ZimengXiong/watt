import SwiftUI
import ServiceManagement

private func batteryColor(for level: Int) -> Color {
    if level <= 20 { return .red }
    if level <= 40 { return .orange }
    return .green
}

private func batteryIcon(for level: Int) -> String {
    if level <= 10 { return "battery.0" }
    if level <= 25 { return "battery.25" }
    if level <= 50 { return "battery.50" }
    if level <= 75 { return "battery.75" }
    return "battery.100"
}

struct ContentView: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @ObservedObject var systemMetrics: SystemMetricsService
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeroHeaderView(powerMonitor: powerMonitor)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        SystemMetricsSection(metricsService: systemMetrics)
                        PowerFlowSection(powerMonitor: powerMonitor)
                        BatterySection(powerMonitor: powerMonitor)
                        HistorySection(powerMonitor: powerMonitor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }

                Divider()
                    .opacity(0.3)

                AppFooterView(powerMonitor: powerMonitor)
            }
        }
        .frame(width: 320)
        .fixedSize()
    }
}

// MARK: - Hero Header

struct HeroHeaderView: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let time = timeText {
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", powerMonitor.currentPower))
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("W")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var statusText: String {
        if powerMonitor.batteryInfo?.isCharging == true { return "Charging" }
        if powerMonitor.batteryInfo?.isPluggedIn == true { return "Plugged In" }
        return "On Battery"
    }

    private var statusColor: Color {
        if powerMonitor.batteryInfo?.isCharging == true { return .green }
        if powerMonitor.batteryInfo?.isPluggedIn == true { return .blue }
        return .orange
    }

    private var timeText: String? {
        guard let battery = powerMonitor.batteryInfo else { return nil }
        if battery.isCharging {
            return battery.formattedTimeToFull == "--" ? nil : "\(battery.formattedTimeToFull) to full"
        } else if !battery.isPluggedIn {
            return battery.formattedTimeRemaining == "--" ? nil : "\(battery.formattedTimeRemaining) left"
        }
        return "Fully Charged"
    }
}

// MARK: - Battery Section

struct BatterySection: View {
    @ObservedObject var powerMonitor: PowerMonitorService

    var body: some View {
        NativeSectionView(title: "Battery") {
            if let battery = powerMonitor.batteryInfo {
                HStack(spacing: 10) {
                    BatteryIconView(
                        percentage: battery.currentCapacity,
                        voltage: battery.voltage,
                        currentCapacityRaw: battery.currentCapacityRaw,
                        maxCapacity: battery.maxCapacity,
                        nominalVoltage: battery.nominalVoltage,
                        color: batteryColor(for: battery.currentCapacity)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        StatRow(label: "Cycles", value: "\(battery.cycleCount)")
                        StatRow(label: "Temp", value: String(format: "%.0f°C", battery.temperature))
                        StatRow(label: "Health", value: String(format: "%.0f%%", battery.batteryHealth))
                    }

                    Spacer()

                    if let charger = powerMonitor.chargerInfo, charger.isConnected {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                if charger.isAppleAdapter {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                if charger.watts > 0 {
                                    Text("\(charger.watts)W")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                            }

                            if charger.watts > 0 {
                                let (voltage, current) = usbcPDSpecs(watts: charger.watts)
                                Text(String(format: "%.0fV @ %.1fA", voltage, current))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
    }

    private func usbcPDSpecs(watts: Int) -> (voltage: Double, current: Double) {
        // USB-PD SPR: 5V, 9V, 15V, 20V (up to 100W)
        // USB-PD 3.1 EPR: 28V, 36V, 48V (up to 240W)
        switch watts {
        case ...15: return (5, Double(watts) / 5.0)
        case ...27: return (9, Double(watts) / 9.0)
        case ...45: return (15, Double(watts) / 15.0)
        case ...100: return (20, Double(watts) / 20.0)
        case ...140: return (28, Double(watts) / 28.0)
        case ...180: return (36, Double(watts) / 36.0)
        default: return (48, Double(watts) / 48.0)
        }
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
    let currentCapacityRaw: Int  // mAh
    let maxCapacity: Int         // mAh
    let nominalVoltage: Double   // V
    let color: Color

    @State private var displayMode: BatteryDisplayMode = .percentage
    @State private var isHovered: Bool = false

    private let batteryWidth: CGFloat = 72
    private let batteryHeight: CGFloat = 36

    private var currentWh: Double {
        Double(currentCapacityRaw) * nominalVoltage / 1000.0
    }

    private var maxWh: Double {
        Double(maxCapacity) * nominalVoltage / 1000.0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.4 : 0.25), lineWidth: 1.5)
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
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.7)
            }
        case .voltage:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.2f", voltage))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("V")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.7)
            }
        case .wattHours:
            VStack(spacing: 0) {
                Text(String(format: "%.1f", currentWh))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
        }
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
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            content
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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
                    .frame(height: 40)

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

    private func formatEnergy(_ wh: Double) -> String {
        if wh >= 1000 {
            return String(format: "%.1f kWh", wh / 1000)
        }
        return String(format: "%.0f Wh", wh)
    }

    private func formatBatteryRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : ""
        return String(format: "%@%.2f%%/m", sign, rate)
    }
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
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.color ?? .primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PowerGraph: View {
    let readings: [EnergyReading]

    // Pre-compute values to avoid repeated calculations
    private var powerValues: [Double] {
        readings.map { $0.power }
    }

    private var maxP: Double {
        max(powerValues.max() ?? 1, 1)
    }

    private var minP: Double {
        max(0, (powerValues.min() ?? 0) * 0.8)
    }

    private var range: Double {
        max(maxP - minP, 0.1)
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard readings.count > 1 else { return }

                let step = size.width / CGFloat(readings.count - 1)

                // Build fill path
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: 0, y: size.height))
                for (i, power) in powerValues.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat((power - minP) / range))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.closeSubpath()

                // Build stroke path
                var strokePath = Path()
                for (i, power) in powerValues.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat((power - minP) / range))
                    if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
                    else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
                }

                // Draw fill
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.02)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Draw stroke
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
    @State private var showSettings = false
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(FooterButtonStyle())

            Spacer()

            Link(destination: URL(string: "https://github.com/zimengxiong/watt")!) {
                GitHubIcon()
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(FooterButtonStyle())

            Button(action: { showAbout.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(FooterButtonStyle())
            .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                AboutView()
            }

            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(FooterButtonStyle())
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsView(powerMonitor: powerMonitor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
    @State private var costInput: String = ""
    @State private var zipCodeInput: String = ""
    @State private var showResetConfirmation: Bool = false
    @State private var showUninstallConfirmation: Bool = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)

            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Electricity Cost") {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0.120", text: $costInput)
                                .textFieldStyle(.plain)
                                .frame(width: 50)
                                .onSubmit { applyCost() }
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        Text("per kWh")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Apply") { applyCost() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    HStack {
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

                SettingsSection(title: "Extras") {
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

                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 4)

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

                    if daemon.isInstalled {
                        Divider()
                            .opacity(0.3)
                            .padding(.vertical, 4)

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
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 10))
                                    Text("Metrics service installed")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(size: 11))

                                Button("Uninstall Service") {
                                    showUninstallConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        }
        .frame(width: 280)
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

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