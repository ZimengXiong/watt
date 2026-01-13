import Foundation
import IOKit
import Darwin
import Combine

class SystemMetricsService: ObservableObject {
    @Published var metrics: SystemMetrics = SystemMetrics()
    @Published var isReady: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var memoryTimer: Timer?
    private var isAppVisible: Bool = false

    private let hostPort: mach_port_t = mach_host_self()

    let powerMetricsDaemon = PowerMetricsDaemon.shared

    init() {
        readChipInfo()
        readMemoryInfo()
        setupPowerMetricsBinding()
        startMemoryMonitoring()
        powerMetricsDaemon.isInstalled ? powerMetricsDaemon.startReading() : powerMetricsDaemon.install()
    }

    deinit {
        memoryTimer?.invalidate()
    }

    private func setupPowerMetricsBinding() {
        powerMetricsDaemon.$isInstalled.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isReady = $0 }.store(in: &cancellables)

        Publishers.CombineLatest4(powerMetricsDaemon.$eCPUUsage, powerMetricsDaemon.$pCPUUsage,
                                   powerMetricsDaemon.$gpuUsage, powerMetricsDaemon.$aneUsage)
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] e, p, g, a in
                self?.metrics.eCPU.usage = e; self?.metrics.pCPU.usage = p
                self?.metrics.gpu.usage = g; self?.metrics.ane.usage = a
            }.store(in: &cancellables)

        Publishers.CombineLatest4(powerMetricsDaemon.$cpuPower, powerMetricsDaemon.$gpuPower,
                                   powerMetricsDaemon.$anePower, powerMetricsDaemon.$packagePower)
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] cpu, gpu, ane, pkg in
                self?.metrics.cpuPower = cpu; self?.metrics.gpuPower = gpu
                self?.metrics.anePower = ane; self?.metrics.packagePower = pkg
            }.store(in: &cancellables)
    }

    private func readChipInfo() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let chipName = String(cString: buffer).contains("Apple") ? String(cString: buffer).trimmingCharacters(in: .whitespaces) : "Apple Silicon"

        var (eCores, pCores) = (0, 0)
        var perfLevelCount: Int32 = 0, perfLevelSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.nperflevels", &perfLevelCount, &perfLevelSize, nil, 0) == 0 && perfLevelCount > 0 {
            for level in 0..<perfLevelCount {
                var coreCount: Int32 = 0, coreSize = MemoryLayout<Int32>.size
                if sysctlbyname("hw.perflevel\(level).logicalcpu", &coreCount, &coreSize, nil, 0) == 0 {
                    if level == 0 { pCores = Int(coreCount) } else { eCores = Int(coreCount) }
                }
            }
        }

        if eCores == 0 && pCores == 0 {
            var totalCores: Int32 = 0, totalSize = MemoryLayout<Int32>.size
            sysctlbyname("hw.ncpu", &totalCores, &totalSize, nil, 0)
            pCores = Int(totalCores)
        }

        let gpuCores = getGPUCoreCount()
        DispatchQueue.main.async {
            self.metrics.chip = ChipInfo(name: chipName, eCoreCount: eCores, pCoreCount: pCores, gpuCoreCount: gpuCores)
            (self.metrics.eCPU.coreCount, self.metrics.pCPU.coreCount, self.metrics.gpu.coreCount) = (eCores, pCores, gpuCores)
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

    func setAppVisible(_ visible: Bool) {
        isAppVisible = visible
        powerMetricsDaemon.setAppVisible(visible)
        restartMemoryTimer()
    }

    private func startMemoryMonitoring() { restartMemoryTimer() }

    private func restartMemoryTimer() {
        memoryTimer?.invalidate()
        let (interval, tolerance) = isAppVisible ? (2.0, 0.5) : (5.0, 1.0)
        memoryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.readMemoryInfo() }
        memoryTimer?.tolerance = tolerance
    }

    private func readMemoryInfo() {
        var memMetrics = MemoryMetrics()

        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        memMetrics.total = totalMem

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)

            let free = UInt64(vmStats.free_count) * pageSize
            let inactive = UInt64(vmStats.inactive_count) * pageSize
            let available = free + inactive

            memMetrics.used = totalMem - available

            memMetrics.pressure = Double(memMetrics.used) / Double(totalMem) * 100
        }

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
