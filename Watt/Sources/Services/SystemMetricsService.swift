import Foundation
import IOKit
import Darwin
import Combine

class SystemMetricsService: ObservableObject {
    @Published var metrics: SystemMetrics = SystemMetrics()
    @Published var isReady: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var memoryTimer: Timer?

    // Cache the host port to avoid Mach port leaks
    private let hostPort: mach_port_t = mach_host_self()

    // PowerMetrics daemon for accurate metrics
    let powerMetricsDaemon = PowerMetricsDaemon.shared

    init() {
        readChipInfo()
        readMemoryInfo()
        setupPowerMetricsBinding()
        startMemoryMonitoring()

        // Check if daemon is installed, if not prompt for installation
        if !powerMetricsDaemon.isInstalled {
            powerMetricsDaemon.install()
        } else {
            powerMetricsDaemon.startReading()
        }
    }

    deinit {
        memoryTimer?.invalidate()
    }

    private func setupPowerMetricsBinding() {
        // Subscribe to daemon installation status
        powerMetricsDaemon.$isInstalled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] installed in
                self?.isReady = installed
            }
            .store(in: &cancellables)

        // Subscribe to daemon metrics - throttle to reduce UI updates
        Publishers.CombineLatest4(
            powerMetricsDaemon.$eCPUUsage,
            powerMetricsDaemon.$pCPUUsage,
            powerMetricsDaemon.$gpuUsage,
            powerMetricsDaemon.$aneUsage
        )
        .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] eCPU, pCPU, gpu, ane in
            guard let self = self else { return }
            self.metrics.eCPU.usage = eCPU
            self.metrics.pCPU.usage = pCPU
            self.metrics.gpu.usage = gpu
            self.metrics.ane.usage = ane
        }
        .store(in: &cancellables)

        // Subscribe to power metrics - throttle to reduce UI updates
        Publishers.CombineLatest4(
            powerMetricsDaemon.$cpuPower,
            powerMetricsDaemon.$gpuPower,
            powerMetricsDaemon.$anePower,
            powerMetricsDaemon.$packagePower
        )
        .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] cpu, gpu, ane, pkg in
            guard let self = self else { return }
            self.metrics.cpuPower = cpu
            self.metrics.gpuPower = gpu
            self.metrics.anePower = ane
            self.metrics.packagePower = pkg
        }
        .store(in: &cancellables)
    }

    private func readChipInfo() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brandString = String(cString: buffer)

        var chipName = "Apple Silicon"
        if brandString.contains("Apple") {
            chipName = brandString.trimmingCharacters(in: .whitespaces)
        }

        var eCores = 0
        var pCores = 0

        // Get core counts from perflevel
        var perfLevelCount: Int32 = 0
        var perfLevelSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.nperflevels", &perfLevelCount, &perfLevelSize, nil, 0) == 0 && perfLevelCount > 0 {
            for level in 0..<perfLevelCount {
                var coreCount: Int32 = 0
                var coreSize = MemoryLayout<Int32>.size
                let key = "hw.perflevel\(level).logicalcpu"
                if sysctlbyname(key, &coreCount, &coreSize, nil, 0) == 0 {
                    if level == 0 {
                        pCores = Int(coreCount)  // perflevel0 = P-cores (performance)
                    } else {
                        eCores = Int(coreCount)  // perflevel1 = E-cores (efficiency)
                    }
                }
            }
        }

        if eCores == 0 && pCores == 0 {
            var totalCores: Int32 = 0
            var totalSize = MemoryLayout<Int32>.size
            sysctlbyname("hw.ncpu", &totalCores, &totalSize, nil, 0)
            pCores = Int(totalCores)
        }

        let gpuCores = getGPUCoreCount()

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

    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.readMemoryInfo()
        }
    }

    private func readMemoryInfo() {
        var memMetrics = MemoryMetrics()

        // Get total physical memory
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        memMetrics.total = totalMem

        // Get VM statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)

            // Calculate "available" memory like psutil does:
            // available = free + inactive (memory that can be reclaimed)
            let free = UInt64(vmStats.free_count) * pageSize
            let inactive = UInt64(vmStats.inactive_count) * pageSize
            let available = free + inactive

            // Used = Total - Available (like asitop/psutil)
            memMetrics.used = totalMem - available

            // Memory pressure based on how much is actually in use
            memMetrics.pressure = Double(memMetrics.used) / Double(totalMem) * 100
        }

        // Get swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            memMetrics.swapUsed = swapUsage.xsu_used
            memMetrics.swapTotal = swapUsage.xsu_total
        }

        DispatchQueue.main.async {
            self.metrics.memory = memMetrics
            self.objectWillChange.send()
        }
    }
}
