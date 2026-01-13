import Foundation

class PowerMetricsDaemon: ObservableObject {
    static let shared = PowerMetricsDaemon()

    private let daemonLabel = "com.watt.powermetrics"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.watt.powermetrics.plist"
    private let metricsFilePath = "/tmp/watt_powermetrics.plist"

    @Published var isInstalled: Bool = false
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    @Published var eCPUUsage: Double = 0
    @Published var pCPUUsage: Double = 0
    @Published var gpuUsage: Double = 0
    @Published var aneUsage: Double = 0
    @Published var anePower: Double = 0
    @Published var cpuPower: Double = 0
    @Published var gpuPower: Double = 0
    @Published var packagePower: Double = 0

    private var readTimer: Timer?
    private let sampleIntervalMs: Double = 1000
    private var lastFileModDate: Date?
    private var lastTruncateTime: Date = Date()
    private let truncateIntervalSeconds: TimeInterval = 300
    private var isAppVisible: Bool = false

    init() {
        checkInstallation()
    }

    deinit {
        stopReading()
    }

    func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: daemonPlistPath)
        if isInstalled { startReading() }
    }

    func install() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let daemonPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(self.daemonLabel)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/powermetrics</string>
        <string>--samplers</string>
        <string>cpu_power,gpu_power,ane_power</string>
        <string>-f</string>
        <string>plist</string>
        <string>-i</string>
        <string>\(Int(self.sampleIntervalMs))</string>
        <string>-o</string>
        <string>\(self.metricsFilePath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
"""

            let tempPlist = "/tmp/watt-install-plist.plist"

            do {
                try daemonPlist.write(toFile: tempPlist, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Failed to create temp file: \(error.localizedDescription)"
                }
                return
            }

            let installCmd = """
cp '\(tempPlist)' '\(self.daemonPlistPath)' && \
chmod 644 '\(self.daemonPlistPath)' && \
chown root:wheel '\(self.daemonPlistPath)' && \
launchctl bootout system '\(self.daemonPlistPath)' 2>/dev/null; \
launchctl bootstrap system '\(self.daemonPlistPath)' && \
rm -f '\(tempPlist)'
"""

            let promptText = """
Watt needs administrator privileges to install a system service for accurate hardware monitoring.

What this does:
• Runs Apple's 'powermetrics' tool to read CPU, GPU, and ANE usage
• Provides real-time usage data updated every \(Int(self.sampleIntervalMs))ms

Files installed:
• /Library/LaunchDaemons/com.watt.powermetrics.plist

This is a one-time setup that persists across reboots.
"""
            let appleScript = """
do shell script "\(installCmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges with prompt "\(promptText.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n"))"
"""

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.isInstalled = true
                        self.isRunning = true
                        self.lastError = nil
                        self.startReading()
                    } else {
                        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        if output.contains("User canceled") || output.contains("-128") {
                            self.lastError = "Setup cancelled"
                        } else {
                            self.lastError = "Installation failed"
                        }
                        self.isInstalled = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isInstalled = false
                }
            }
        }
    }

    func uninstall() {
        let uninstallCmd = """
launchctl bootout system '\(daemonPlistPath)' 2>/dev/null; \
rm -f '\(daemonPlistPath)' '\(metricsFilePath)'
"""

        let uninstallPrompt = """
Watt will remove the system monitoring service.

Files to be removed:
• /Library/LaunchDaemons/com.watt.powermetrics.plist

CPU, GPU, and ANE metrics will no longer be available after removal.
"""
        let appleScript = """
do shell script "\(uninstallCmd)" with administrator privileges with prompt "\(uninstallPrompt.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n"))"
"""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    self?.isInstalled = false
                    self?.isRunning = false
                    self?.stopReading()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func startReading() {
        stopReading()
        readMetricsFile()
        restartTimerWithCurrentInterval()
    }

    func stopReading() {
        readTimer?.invalidate()
        readTimer = nil
    }

    func setAppVisible(_ visible: Bool) {
        isAppVisible = visible
        restartTimerWithCurrentInterval()
    }

    private func restartTimerWithCurrentInterval() {
        readTimer?.invalidate()

        let interval: TimeInterval = isAppVisible ? 1.0 : 2.0
        let tolerance: TimeInterval = isAppVisible ? 0.1 : 0.5

        readTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.readMetricsFile()
        }
        readTimer?.tolerance = tolerance
    }

    private func readMetricsFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metricsFilePath) else { return }

        if let modDate = (try? fm.attributesOfItem(atPath: metricsFilePath))?[.modificationDate] as? Date {
            if let lastMod = lastFileModDate, modDate <= lastMod { return }
            lastFileModDate = modDate
        }

        // CRITICAL FIX: Only read the TAIL of the file (last 64KB) instead of the entire file.
        // The powermetrics file grows unbounded and can reach several GB,
        // causing massive memory usage if we read it entirely.
        guard let handle = FileHandle(forReadingAtPath: metricsFilePath) else { return }
        defer { try? handle.close() }

        let tailSize: UInt64 = 65536  // 64KB is plenty for a single plist sample (~8-15KB)
        let fileSize = handle.seekToEndOfFile()

        let readStart: UInt64
        if fileSize > tailSize {
            readStart = fileSize - tailSize
            handle.seek(toFileOffset: readStart)
        } else {
            handle.seek(toFileOffset: 0)
        }

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        let plistData: Data
        if let nullIdx = data.lastIndex(of: 0), nullIdx < data.count - 100 {
            plistData = Data(data.suffix(from: data.index(after: nullIdx)))
        } else {
            plistData = data
        }

        guard plistData.count > 100,
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else { return }
        parseMetrics(plist)

        if Date().timeIntervalSince(lastTruncateTime) > truncateIntervalSeconds && fileSize > 1_000_000 {
            truncateMetricsFile()
            lastTruncateTime = Date()
        }
    }

    private func truncateMetricsFile() {
        guard let handle = FileHandle(forUpdatingAtPath: metricsFilePath) else { return }
        defer { try? handle.close() }
        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 100_000 else { return }

        handle.seek(toFileOffset: fileSize - 32768)
        let lastData = handle.readDataToEndOfFile()
        guard let nullIdx = lastData.firstIndex(of: 0) else { return }
        let cleanData = Data(lastData.suffix(from: lastData.index(after: nullIdx)))
        guard !cleanData.isEmpty else { return }

        handle.seek(toFileOffset: 0)
        handle.write(cleanData)
        handle.truncateFile(atOffset: UInt64(cleanData.count))
    }

    private func parseMetrics(_ plist: [String: Any]) {
        var (eCPU, pCPU, gpu, cpuPwr, gpuPwr, anePwr, pkgPwr) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

        if let proc = plist["processor"] as? [String: Any] {
            if let clusters = proc["clusters"] as? [[String: Any]] {
                var (eUsages, pUsages) = ([Double](), [Double]())
                for c in clusters {
                    guard let name = c["name"] as? String, let idle = c["idle_ratio"] as? Double else { continue }
                    let usage = (1.0 - idle) * 100.0
                    (name.hasPrefix("E") ? &eUsages : &pUsages).append(usage)
                }
                if !eUsages.isEmpty { eCPU = eUsages.reduce(0, +) / Double(eUsages.count) }
                if !pUsages.isEmpty { pCPU = pUsages.reduce(0, +) / Double(pUsages.count) }
            }
            if let e = proc["cpu_energy"] as? Double { cpuPwr = e / sampleIntervalMs }
            pkgPwr = ((proc["combined_power"] ?? proc["package_energy"]) as? Double ?? 0) / sampleIntervalMs
            if let e = proc["ane_energy"] as? Double { anePwr = e / sampleIntervalMs }
        }

        if let g = plist["gpu"] as? [String: Any] {
            if let idle = g["idle_ratio"] as? Double { gpu = (1.0 - idle) * 100.0 }
            if let e = g["gpu_energy"] as? Double { gpuPwr = e / sampleIntervalMs }
        }

        DispatchQueue.main.async {
            self.eCPUUsage = min(max(eCPU, 0), 100)
            self.pCPUUsage = min(max(pCPU, 0), 100)
            self.gpuUsage = min(max(gpu, 0), 100)
            self.aneUsage = min(max(anePwr > 0 ? (anePwr / 8.0) * 100.0 : 0, 0), 100)
            (self.anePower, self.cpuPower, self.gpuPower, self.packagePower) = (max(anePwr, 0), max(cpuPwr, 0), max(gpuPwr, 0), max(pkgPwr, 0))
        }
    }
}
