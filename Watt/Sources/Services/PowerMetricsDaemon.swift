import Foundation

// MARK: - PowerMetrics Daemon Manager
// Manages a LaunchDaemon that runs powermetrics with root privileges
// User authorizes ONCE during installation, then it works forever

class PowerMetricsDaemon: ObservableObject {
    static let shared = PowerMetricsDaemon()

    private let daemonLabel = "com.watt.powermetrics"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.watt.powermetrics.plist"
    private let metricsFilePath = "/tmp/watt_powermetrics.plist"

    @Published var isInstalled: Bool = false
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    // Parsed metrics (from powermetrics idle_ratio)
    @Published var eCPUUsage: Double = 0
    @Published var pCPUUsage: Double = 0
    @Published var gpuUsage: Double = 0
    @Published var aneUsage: Double = 0

    // Power in Watts (from energy / interval)
    @Published var anePower: Double = 0
    @Published var cpuPower: Double = 0
    @Published var gpuPower: Double = 0
    @Published var packagePower: Double = 0

    private var readTimer: Timer?
    private let sampleIntervalMs: Double = 500

    init() {
        checkInstallation()
    }

    deinit {
        stopReading()
    }

    // MARK: - Installation Check

    func checkInstallation() {
        let daemonExists = FileManager.default.fileExists(atPath: daemonPlistPath)

        // Set synchronously so callers can check immediately
        isInstalled = daemonExists

        if daemonExists {
            startReading()
        }
    }

    // MARK: - Installation with Custom Dialog

    func install() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // No wrapper script - run powermetrics directly from launchd
            // This matches how asitop runs it
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

            // Write temp plist
            let tempPlist = "/tmp/watt-install-plist.plist"

            do {
                try daemonPlist.write(toFile: tempPlist, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Failed to create temp file: \(error.localizedDescription)"
                }
                return
            }

            // Install command - run powermetrics directly via launchd (no wrapper script)
            let installCmd = """
cp '\(tempPlist)' '\(self.daemonPlistPath)' && \
chmod 644 '\(self.daemonPlistPath)' && \
chown root:wheel '\(self.daemonPlistPath)' && \
launchctl bootout system '\(self.daemonPlistPath)' 2>/dev/null; \
launchctl bootstrap system '\(self.daemonPlistPath)' && \
rm -f '\(tempPlist)'
"""

            // Use AppleScript with custom prompt - detailed explanation for user
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

    // MARK: - Uninstall

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

    // MARK: - Reading Metrics

    func startReading() {
        stopReading()

        // Read immediately
        readMetricsFile()

        // Read at same rate as powermetrics samples
        readTimer = Timer.scheduledTimer(withTimeInterval: sampleIntervalMs / 1000.0, repeats: true) { [weak self] _ in
            self?.readMetricsFile()
        }
    }

    func stopReading() {
        readTimer?.invalidate()
        readTimer = nil
    }

    private func readMetricsFile() {
        guard FileManager.default.fileExists(atPath: metricsFilePath),
              let data = FileManager.default.contents(atPath: metricsFilePath) else {
            return
        }

        // powermetrics outputs NUL-separated plists, we need the last one
        // Split by NUL byte and take the last complete plist
        let chunks = data.split(separator: 0)
        guard let lastChunk = chunks.last, lastChunk.count > 100 else {
            return
        }

        // Parse the last plist
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(lastChunk), options: [], format: nil) as? [String: Any] else {
            return
        }

        parseMetrics(plist)
    }

    // MARK: - Parse Metrics (following asitop's approach)

    private func parseMetrics(_ plist: [String: Any]) {
        var eCPU: Double = 0
        var pCPU: Double = 0
        var gpu: Double = 0
        var cpuPwr: Double = 0
        var gpuPwr: Double = 0
        var anePwr: Double = 0
        var pkgPwr: Double = 0

        // Parse processor data
        if let processor = plist["processor"] as? [String: Any] {

            // CPU cluster usage from idle_ratio (like asitop)
            // M4 Max has E-Cluster, P0-Cluster, P1-Cluster - we average same-type clusters
            if let clusters = processor["clusters"] as? [[String: Any]] {
                var eClusterUsages: [Double] = []
                var pClusterUsages: [Double] = []

                for cluster in clusters {
                    guard let name = cluster["name"] as? String,
                          let idleRatio = cluster["idle_ratio"] as? Double else { continue }

                    let usage = (1.0 - idleRatio) * 100.0

                    if name.hasPrefix("E") {
                        eClusterUsages.append(usage)
                    } else if name.hasPrefix("P") {
                        pClusterUsages.append(usage)
                    }
                }

                // Average all E-clusters and P-clusters (like asitop does)
                if !eClusterUsages.isEmpty {
                    eCPU = eClusterUsages.reduce(0, +) / Double(eClusterUsages.count)
                }
                if !pClusterUsages.isEmpty {
                    pCPU = pClusterUsages.reduce(0, +) / Double(pClusterUsages.count)
                }
            }

            // CPU power: cpu_energy is in mJ, convert to W
            // Power = Energy / Time, where time = sampleIntervalMs / 1000
            if let cpuEnergy = processor["cpu_energy"] as? Double {
                cpuPwr = cpuEnergy / sampleIntervalMs  // mJ / ms = W
            }

            // Package/combined power
            if let combinedPower = processor["combined_power"] as? Double {
                pkgPwr = combinedPower / sampleIntervalMs
            } else if let packageEnergy = processor["package_energy"] as? Double {
                pkgPwr = packageEnergy / sampleIntervalMs
            }

            // ANE power
            if let aneEnergy = processor["ane_energy"] as? Double {
                anePwr = aneEnergy / sampleIntervalMs
            }
        }

        // GPU usage from idle_ratio
        if let gpuData = plist["gpu"] as? [String: Any],
           let idleRatio = gpuData["idle_ratio"] as? Double {
            gpu = (1.0 - idleRatio) * 100.0
        }

        // GPU power
        if let gpuData = plist["gpu"] as? [String: Any],
           let gpuEnergy = gpuData["gpu_energy"] as? Double {
            gpuPwr = gpuEnergy / sampleIntervalMs
        }

        // ANE usage estimate (based on power, max ~8W)
        let aneUsageEst = anePwr > 0 ? min((anePwr / 8.0) * 100.0, 100.0) : 0

        // Update on main thread
        DispatchQueue.main.async {
            self.eCPUUsage = max(0, min(100, eCPU))
            self.pCPUUsage = max(0, min(100, pCPU))
            self.gpuUsage = max(0, min(100, gpu))
            self.aneUsage = max(0, min(100, aneUsageEst))
            self.anePower = max(0, anePwr)
            self.cpuPower = max(0, cpuPwr)
            self.gpuPower = max(0, gpuPwr)
            self.packagePower = max(0, pkgPwr)
        }
    }
}
