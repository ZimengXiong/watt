import Foundation

struct CPUClusterMetrics {
    var usage: Double = 0           // 0-100%
    var frequency: Double = 0       // MHz
    var power: Double = 0           // Watts
    var coreCount: Int = 0
    var coreUsages: [Double] = []   // Per-core usage percentages
}

struct GPUMetrics {
    var usage: Double = 0           // 0-100%
    var frequency: Double = 0       // MHz
    var power: Double = 0           // Watts
    var coreCount: Int = 0
}

struct ANEMetrics {
    var usage: Double = 0           // 0-100%
    var power: Double = 0           // Watts
}

struct MemoryMetrics {
    var used: UInt64 = 0            // Bytes
    var total: UInt64 = 0           // Bytes
    var swapUsed: UInt64 = 0        // Bytes
    var swapTotal: UInt64 = 0       // Bytes
    var pressure: Double = 0        // 0-100%

    var usedGB: Double { Double(used) / 1_073_741_824 }
    var totalGB: Double { Double(total) / 1_073_741_824 }
    var swapUsedGB: Double { Double(swapUsed) / 1_073_741_824 }
    var swapTotalGB: Double { Double(swapTotal) / 1_073_741_824 }
    var usagePercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

struct ChipInfo {
    var name: String = "Apple Silicon"
    var eCoreCount: Int = 0
    var pCoreCount: Int = 0
    var gpuCoreCount: Int = 0
}

struct SystemMetrics {
    var chip: ChipInfo = ChipInfo()
    var eCPU: CPUClusterMetrics = CPUClusterMetrics()
    var pCPU: CPUClusterMetrics = CPUClusterMetrics()
    var gpu: GPUMetrics = GPUMetrics()
    var ane: ANEMetrics = ANEMetrics()
    var memory: MemoryMetrics = MemoryMetrics()

    // Power breakdown
    var cpuPower: Double = 0        // Watts (E + P combined)
    var gpuPower: Double = 0        // Watts
    var anePower: Double = 0        // Watts
    var dramPower: Double = 0       // Watts
    var packagePower: Double = 0    // Watts (total SoC)
}
