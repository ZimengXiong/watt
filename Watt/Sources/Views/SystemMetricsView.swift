import SwiftUI

// MARK: - System Metrics Section

struct SystemMetricsSection: View {
    @ObservedObject var metricsService: SystemMetricsService

    var body: some View {
        NativeSectionView(title: metricsService.metrics.chip.name + " (cores: \(metricsService.metrics.chip.eCoreCount)E+\(metricsService.metrics.chip.pCoreCount)P+\(metricsService.metrics.chip.gpuCoreCount)GPU)") {
            VStack(spacing: 8) {
                // E-CPU and P-CPU side by side
                HStack(spacing: 8) {
                    CPUClusterView(
                        title: "E-CPU",
                        cluster: metricsService.metrics.eCPU,
                        color: .green
                    )
                    CPUClusterView(
                        title: "P-CPU",
                        cluster: metricsService.metrics.pCPU,
                        color: .orange
                    )
                }

                // GPU and ANE side by side
                HStack(spacing: 8) {
                    GPUView(gpu: metricsService.metrics.gpu)
                    ANEView(ane: metricsService.metrics.ane)
                }

                // Memory bar
                MemoryBarView(memory: metricsService.metrics.memory)
            }
        }
    }
}

// MARK: - CPU Cluster View

struct CPUClusterView: View {
    let title: String
    let cluster: CPUClusterMetrics
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(title) Usage: \(String(format: "%.0f%%", cluster.usage))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("@ \(formatFrequency(cluster.frequency))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            UsageBarGraph(
                value: cluster.usage / 100,
                coreCount: cluster.coreCount,
                color: color
            )
            .frame(height: 50)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func formatFrequency(_ mhz: Double) -> String {
        if mhz >= 1000 {
            return String(format: "%.1f GHz", mhz / 1000)
        }
        return String(format: "%.0f MHz", mhz)
    }
}

// MARK: - GPU View

struct GPUView: View {
    let gpu: GPUMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GPU Usage: \(String(format: "%.0f%%", gpu.usage))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("@ \(formatFrequency(gpu.frequency))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            UsageBarGraph(
                value: gpu.usage / 100,
                coreCount: max(gpu.coreCount, 8),
                color: .yellow
            )
            .frame(height: 50)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func formatFrequency(_ mhz: Double) -> String {
        if mhz >= 1000 {
            return String(format: "%.1f GHz", mhz / 1000)
        }
        return String(format: "%.0f MHz", mhz)
    }
}

// MARK: - ANE View

struct ANEView: View {
    let ane: ANEMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ANE Usage: \(String(format: "%.0f%%", ane.usage))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("@ \(String(format: "%.1f W", ane.power))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            UsageBarGraph(
                value: ane.usage / 100,
                coreCount: 16,  // ANE has multiple engines
                color: .cyan
            )
            .frame(height: 50)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Memory Bar View

struct MemoryBarView: View {
    let memory: MemoryMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Memory")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            Text("RAM Usage: \(String(format: "%.1f", memory.usedGB))/\(String(format: "%.1f", memory.totalGB))GB - swap:\(String(format: "%.1f", memory.swapUsedGB))/\(String(format: "%.1f", memory.swapTotalGB))GB")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            LinearUsageBar(
                value: memory.usagePercent / 100,
                color: memoryColor
            )
            .frame(height: 20)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var memoryColor: Color {
        if memory.usagePercent > 90 { return .red }
        if memory.usagePercent > 70 { return .orange }
        return .green
    }
}

// MARK: - Usage Bar Graph (htop-style)

struct UsageBarGraph: View {
    let value: Double  // 0.0 - 1.0
    let coreCount: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let barCount = coreCount > 0 ? coreCount : 8
            let spacing: CGFloat = 1
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(barCount)

            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    VerticalBar(
                        fillPercent: barFillPercent(for: index, total: barCount),
                        color: color
                    )
                    .frame(width: barWidth)
                }
            }
        }
    }

    private func barFillPercent(for index: Int, total: Int) -> Double {
        // Simulate per-core usage based on overall usage
        // Bars fill from left to right based on total usage
        let filledBars = value * Double(total)
        let barIndex = Double(index)

        if barIndex < filledBars - 1 {
            return 1.0  // Fully filled
        } else if barIndex < filledBars {
            return filledBars - barIndex  // Partially filled
        } else {
            return 0.05  // Minimum visible
        }
    }
}

struct VerticalBar: View {
    let fillPercent: Double  // 0.0 - 1.0
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(Color.primary.opacity(0.08))

                // Fill
                Rectangle()
                    .fill(color.opacity(0.8))
                    .frame(height: geo.size.height * CGFloat(min(max(fillPercent, 0), 1)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
    }
}

// MARK: - Linear Usage Bar

struct LinearUsageBar: View {
    let value: Double  // 0.0 - 1.0
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let barCount = Int(geo.size.width / 4)  // One bar every 4 points
            let spacing: CGFloat = 1
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(barCount)

            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let isFilled = Double(index) / Double(barCount) < value
                    Rectangle()
                        .fill(isFilled ? color.opacity(0.8) : Color.primary.opacity(0.08))
                        .frame(width: barWidth)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    SystemMetricsSection(metricsService: SystemMetricsService())
        .padding()
        .frame(width: 320)
}
