import Foundation
import IOKit
import Darwin

// MARK: - System Metrics Service

class SystemMetricsService: ObservableObject {
    @Published var metrics: SystemMetrics = SystemMetrics()

    private var timer: DispatchSourceTimer?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)
    private var previousPerCPUTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

    init() {
        readChipInfo()
        readMemoryInfo()
        readCPUUsage()  // Initialize CPU ticks
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        let queue = DispatchQueue(label: "com.watt.systemmetrics", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
        timer?.setEventHandler { [weak self] in
            self?.updateMetrics()
        }
        timer?.resume()
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Chip Info

    private func readChipInfo() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brandString = String(cString: buffer)

        // Parse chip name
        var chipName = "Apple Silicon"
        if brandString.contains("Apple") {
            chipName = brandString.trimmingCharacters(in: .whitespaces)
        }

        // Get core counts
        var eCores = 0
        var pCores = 0
        var gpuCores = 0

        // Try to get from hw.perflevel counters (Apple Silicon specific)
        var perfLevelCount: Int32 = 0
        var perfLevelSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.nperflevels", &perfLevelCount, &perfLevelSize, nil, 0) == 0 && perfLevelCount > 0 {
            for level in 0..<perfLevelCount {
                var coreCount: Int32 = 0
                var coreSize = MemoryLayout<Int32>.size
                let key = "hw.perflevel\(level).logicalcpu"
                if sysctlbyname(key, &coreCount, &coreSize, nil, 0) == 0 {
                    if level == 0 {
                        pCores = Int(coreCount)  // Level 0 is performance
                    } else {
                        eCores = Int(coreCount)  // Level 1 is efficiency
                    }
                }
            }
        }

        // Fallback: use total core count
        if eCores == 0 && pCores == 0 {
            var totalCores: Int32 = 0
            var totalSize = MemoryLayout<Int32>.size
            sysctlbyname("hw.ncpu", &totalCores, &totalSize, nil, 0)
            pCores = Int(totalCores)
        }

        // Get GPU core count from IOKit
        gpuCores = getGPUCoreCount()

        DispatchQueue.main.async {
            self.metrics.chip = ChipInfo(
                name: chipName,
                eCoreCount: eCores,
                pCoreCount: pCores,
                gpuCoreCount: gpuCores
            )
            self.metrics.eCPU.coreCount = eCores
            self.metrics.pCPU.coreCount = pCores
            self.metrics.gpu.coreCount = gpuCores
        }
    }

    private func getGPUCoreCount() -> Int {
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                if let gpuCores = dict["gpu-core-count"] as? Int {
                    return gpuCores
                }
            }
        }
        return 0
    }

    // MARK: - Memory Info

    private func readMemoryInfo() {
        var memMetrics = MemoryMetrics()

        // Get total RAM
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        memMetrics.total = totalMem

        // Get memory stats using host_statistics64
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let active = UInt64(vmStats.active_count) * pageSize
            let wired = UInt64(vmStats.wire_count) * pageSize
            let compressed = UInt64(vmStats.compressor_page_count) * pageSize
            let speculative = UInt64(vmStats.speculative_count) * pageSize

            // Used = Active + Wired + Compressed (excluding speculative/cached)
            memMetrics.used = active + wired + compressed

            // Memory pressure calculation
            let free = UInt64(vmStats.free_count) * pageSize
            memMetrics.pressure = Double(totalMem - free - speculative) / Double(totalMem) * 100
        }

        // Get swap info
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            memMetrics.swapUsed = swapUsage.xsu_used
            memMetrics.swapTotal = swapUsage.xsu_total
        }

        DispatchQueue.main.async {
            self.metrics.memory = memMetrics
        }
    }

    // MARK: - CPU Usage

    private func readCPUUsage() {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                        PROCESSOR_CPU_LOAD_INFO,
                                        &numCPUs,
                                        &cpuInfo,
                                        &numCPUInfo)

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var perCPUTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int32(i) * CPU_STATE_MAX
            let user = UInt64(cpuInfo[Int(offset + CPU_STATE_USER)])
            let system = UInt64(cpuInfo[Int(offset + CPU_STATE_SYSTEM)])
            let idle = UInt64(cpuInfo[Int(offset + CPU_STATE_IDLE)])
            let nice = UInt64(cpuInfo[Int(offset + CPU_STATE_NICE)])

            perCPUTicks.append((user: user, system: system, idle: idle, nice: nice))
            totalUser += user
            totalSystem += system
            totalIdle += idle
            totalNice += nice
        }

        // Calculate usage if we have previous data
        if !previousPerCPUTicks.isEmpty && previousPerCPUTicks.count == perCPUTicks.count {
            let eCoreCount = metrics.chip.eCoreCount
            let pCoreCount = metrics.chip.pCoreCount
            let totalCores = eCoreCount + pCoreCount

            // Calculate E-CPU usage (cores at the end)
            var eCPUUsage: Double = 0
            if eCoreCount > 0 && totalCores <= perCPUTicks.count {
                let eStart = pCoreCount  // E-cores come after P-cores
                for i in eStart..<(eStart + eCoreCount) {
                    let prev = previousPerCPUTicks[i]
                    let curr = perCPUTicks[i]
                    let used = (curr.user - prev.user) + (curr.system - prev.system) + (curr.nice - prev.nice)
                    let total = used + (curr.idle - prev.idle)
                    if total > 0 {
                        eCPUUsage += Double(used) / Double(total) * 100
                    }
                }
                eCPUUsage /= Double(eCoreCount)
            }

            // Calculate P-CPU usage (cores at the beginning)
            var pCPUUsage: Double = 0
            if pCoreCount > 0 {
                for i in 0..<pCoreCount {
                    let prev = previousPerCPUTicks[i]
                    let curr = perCPUTicks[i]
                    let used = (curr.user - prev.user) + (curr.system - prev.system) + (curr.nice - prev.nice)
                    let total = used + (curr.idle - prev.idle)
                    if total > 0 {
                        pCPUUsage += Double(used) / Double(total) * 100
                    }
                }
                pCPUUsage /= Double(pCoreCount)
            }

            // If we don't have perflevel info, use overall usage
            if eCoreCount == 0 && pCoreCount == 0 {
                let prevTotal = previousCPUTicks
                let used = (totalUser - prevTotal.user) + (totalSystem - prevTotal.system) + (totalNice - prevTotal.nice)
                let total = used + (totalIdle - prevTotal.idle)
                if total > 0 {
                    pCPUUsage = Double(used) / Double(total) * 100
                }
            }

            // Get CPU frequencies
            let (eFreq, pFreq) = getCPUFrequencies()

            DispatchQueue.main.async {
                self.metrics.eCPU.usage = eCPUUsage
                self.metrics.eCPU.frequency = eFreq
                self.metrics.pCPU.usage = pCPUUsage
                self.metrics.pCPU.frequency = pFreq
            }
        }

        previousCPUTicks = (user: totalUser, system: totalSystem, idle: totalIdle, nice: totalNice)
        previousPerCPUTicks = perCPUTicks
    }

    private func getCPUFrequencies() -> (eFreq: Double, pFreq: Double) {
        var eFreq: Double = 0
        var pFreq: Double = 0

        // Try to get per-cluster frequencies
        var perfLevelCount: Int32 = 0
        var perfLevelSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.nperflevels", &perfLevelCount, &perfLevelSize, nil, 0) == 0 && perfLevelCount > 0 {
            for level in 0..<perfLevelCount {
                var maxFreq: UInt64 = 0
                var freqSize = MemoryLayout<UInt64>.size
                let key = "hw.perflevel\(level).cpuspeeds"

                // Try cpufreq_max first
                let maxKey = "hw.perflevel\(level).cpufreq_max"
                if sysctlbyname(maxKey, &maxFreq, &freqSize, nil, 0) == 0 {
                    let freqMHz = Double(maxFreq) / 1_000_000
                    if level == 0 {
                        pFreq = freqMHz
                    } else {
                        eFreq = freqMHz
                    }
                }
            }
        }

        // Fallback to general CPU frequency
        if pFreq == 0 {
            var freq: UInt64 = 0
            var freqSize = MemoryLayout<UInt64>.size
            if sysctlbyname("hw.cpufrequency_max", &freq, &freqSize, nil, 0) == 0 {
                pFreq = Double(freq) / 1_000_000
            }
        }

        return (eFreq, pFreq)
    }

    // MARK: - GPU Usage

    private func readGPUUsage() {
        // Get GPU usage from IOKit
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {

                // Try to get performance statistics
                if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                    if let deviceUtil = perfStats["Device Utilization %"] as? Double {
                        DispatchQueue.main.async {
                            self.metrics.gpu.usage = deviceUtil
                        }
                    }
                    if let gpuActivity = perfStats["GPU Activity(%)"] as? Double {
                        DispatchQueue.main.async {
                            self.metrics.gpu.usage = gpuActivity
                        }
                    }
                }

                // Get GPU frequency if available
                if let frequency = dict["gpu-freq"] as? Int {
                    DispatchQueue.main.async {
                        self.metrics.gpu.frequency = Double(frequency)
                    }
                }
            }
        }
    }

    // MARK: - ANE Usage

    private func readANEUsage() {
        // ANE usage is typically obtained through private APIs or powermetrics
        // For now, we'll show 0% unless actively in use
        // This could be enhanced by monitoring process activity that uses ANE
        DispatchQueue.main.async {
            self.metrics.ane.usage = 0
            self.metrics.ane.power = 0
        }
    }

    // MARK: - Update Metrics

    private func updateMetrics() {
        readMemoryInfo()
        readCPUUsage()
        readGPUUsage()
        readANEUsage()

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
