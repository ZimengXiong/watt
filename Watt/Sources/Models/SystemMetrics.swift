import Foundation

struct CPUClusterMetrics {
    var usage: Double = 0
    var frequency: Double = 0
    var power: Double = 0
    var coreCount: Int = 0
    var coreUsages: [Double] = []
}

struct GPUMetrics {
    var usage: Double = 0
    var frequency: Double = 0
    var power: Double = 0
    var coreCount: Int = 0
}

struct ANEMetrics {
    var usage: Double = 0
    var power: Double = 0
}

struct MemoryMetrics {
    var used: UInt64 = 0
    var total: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: Double = 0

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
    var cpuPower: Double = 0
    var gpuPower: Double = 0
    var anePower: Double = 0
    var packagePower: Double = 0
}
