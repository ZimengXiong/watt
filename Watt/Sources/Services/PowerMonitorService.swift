import Foundation
import IOKit
import IOKit.ps
import Combine

private struct SMCVersion { var data: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0,0,0,0,0) }
private struct SMCPLimitData { var data: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0,0,0,0,0) }
private struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private func fourCharCode(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for c in s.utf8 { r = (r << 8) | UInt32(c) }
    return r
}

private class SMCReader {
    private var connection: io_connect_t = 0
    private var isConnected = false

    init() {
        connect()
    }

    deinit {
        if isConnected {
            IOServiceClose(connection)
        }
    }

    private func connect() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        if IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess {
            isConnected = true
        }
    }

    func readFloat(_ key: String) -> Float? {
        guard isConnected else { return nil }

        // Get key info
        var inp = SMCParamStruct()
        inp.key = fourCharCode(key)
        inp.data8 = 9  // kSMCGetKeyInfo

        var out = SMCParamStruct()
        var outSz = MemoryLayout<SMCParamStruct>.size
        guard IOConnectCallStructMethod(connection, 2, &inp, MemoryLayout<SMCParamStruct>.size, &out, &outSz) == kIOReturnSuccess,
              out.result == 0 else { return nil }

        let size = out.keyInfo.dataSize
        guard size == 4 else { return nil }

        // Read bytes
        inp = SMCParamStruct()
        inp.key = fourCharCode(key)
        inp.keyInfo.dataSize = size
        inp.data8 = 5  // kSMCReadKey

        out = SMCParamStruct()
        outSz = MemoryLayout<SMCParamStruct>.size
        guard IOConnectCallStructMethod(connection, 2, &inp, MemoryLayout<SMCParamStruct>.size, &out, &outSz) == kIOReturnSuccess,
              out.result == 0 else { return nil }

        // Extract bytes and convert to little-endian float
        var bytes: [UInt8] = []
        withUnsafeBytes(of: out.bytes) { for i in 0..<4 { bytes.append($0[i]) } }

        let value: UInt32 = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Float(bitPattern: value)
    }
}

struct DailyEnergyRecord: Codable, Identifiable {
    var id: String { date }
    let date: String  // yyyy-MM-dd
    var energyUsed: Double  // Wh
}

class PowerMonitorService: ObservableObject {
    @Published var batteryInfo: BatteryInfo?
    @Published var chargerInfo: ChargerInfo?
    @Published var powerTelemetry: PowerTelemetry?
    @Published var portInfo: PortInfo?
    @Published var energyHistory: [EnergyReading] = []

    @Published var currentPower: Double = 0
    @Published var wallPower: Double = 0
    @Published var batteryPower: Double = 0
    @Published var systemPower: Double = 0
    @Published var lifetimeEnergyUsed: Double = 0  // Wh
    @Published var lifetimeSessionCount: Int = 0
    @Published var todayEnergyUsed: Double = 0  // Wh
    @Published var dailyHistory: [DailyEnergyRecord] = []  // Historical daily records
    @Published var batteryRatePerMinute: Double = 0  // %/min (positive = charging, negative = discharging)

    // Electricity cost tracking
    @Published var electricityCostPerKwh: Double = 0.12  // $/kWh (default US average)
    @Published var autoFindElectricityCost: Bool = false
    @Published var zipCode: String = ""

    // Lifetime cost is computed from energy to ensure consistency
    var lifetimeCost: Double {
        return (lifetimeEnergyUsed / 1000.0) * electricityCostPerKwh
    }

    private var timer: DispatchSourceTimer?
    private var lastReadingTime: Date
    private var lastPowerReading: Double = 0
    private let smcReader = SMCReader()
    private var currentDateString: String = ""

    // UserDefaults keys
    private let lifetimeEnergyKey = "com.watt.lifetimeEnergy"
    private let lifetimeSessionsKey = "com.watt.lifetimeSessions"
    private let todayEnergyKey = "com.watt.todayEnergy"
    private let todayDateKey = "com.watt.todayDate"
    private let dailyHistoryKey = "com.watt.dailyHistory"
    private let electricityCostKey = "com.watt.electricityCost"
    private let autoFindCostKey = "com.watt.autoFindCost"
    private let zipCodeKey = "com.watt.zipCode"
    private var saveTimer: DispatchSourceTimer?

    init() {
        lastReadingTime = Date()
        loadLifetimeStats()
        incrementSessionCount()
        startMonitoring()
        startPeriodicSave()
    }

    deinit {
        stopMonitoring()
        saveTimer?.cancel()
        saveLifetimeStats()
    }

    func startMonitoring() {
        updateAllReadings()

        let queue = DispatchQueue(label: "com.watt.powermonitor", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer?.setEventHandler { [weak self] in
            self?.updateAllReadings()
        }
        timer?.resume()
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    private func loadLifetimeStats() {
        lifetimeEnergyUsed = UserDefaults.standard.double(forKey: lifetimeEnergyKey)
        lifetimeSessionCount = UserDefaults.standard.integer(forKey: lifetimeSessionsKey)

        let savedCost = UserDefaults.standard.double(forKey: electricityCostKey)
        if savedCost > 0 {
            electricityCostPerKwh = savedCost
        }
        autoFindElectricityCost = UserDefaults.standard.bool(forKey: autoFindCostKey)
        zipCode = UserDefaults.standard.string(forKey: zipCodeKey) ?? ""

        if let data = UserDefaults.standard.data(forKey: dailyHistoryKey),
           let history = try? JSONDecoder().decode([DailyEnergyRecord].self, from: data) {
            dailyHistory = history
        }

        let savedDate = UserDefaults.standard.string(forKey: todayDateKey) ?? ""
        currentDateString = todayDateString()

        if savedDate == currentDateString {
            todayEnergyUsed = UserDefaults.standard.double(forKey: todayEnergyKey)
        } else {
            if !savedDate.isEmpty {
                let previousEnergy = UserDefaults.standard.double(forKey: todayEnergyKey)
                if previousEnergy > 0 {
                    archiveDay(date: savedDate, energy: previousEnergy)
                }
            }
            todayEnergyUsed = 0
            UserDefaults.standard.set(currentDateString, forKey: todayDateKey)
        }

        if autoFindElectricityCost {
            fetchElectricityCost()
        }
    }

    private func saveLifetimeStats() {
        UserDefaults.standard.set(lifetimeEnergyUsed, forKey: lifetimeEnergyKey)
        UserDefaults.standard.set(lifetimeSessionCount, forKey: lifetimeSessionsKey)
        UserDefaults.standard.set(todayEnergyUsed, forKey: todayEnergyKey)
        UserDefaults.standard.set(currentDateString, forKey: todayDateKey)
        UserDefaults.standard.set(electricityCostPerKwh, forKey: electricityCostKey)
        UserDefaults.standard.set(autoFindElectricityCost, forKey: autoFindCostKey)
        UserDefaults.standard.set(zipCode, forKey: zipCodeKey)

        if let data = try? JSONEncoder().encode(dailyHistory) {
            UserDefaults.standard.set(data, forKey: dailyHistoryKey)
        }
    }

    func setElectricityCost(_ cost: Double) {
        DispatchQueue.main.async {
            self.electricityCostPerKwh = cost
            self.autoFindElectricityCost = false
            self.objectWillChange.send()
            self.saveLifetimeStats()
        }
    }

    func setAutoFindCost(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.autoFindElectricityCost = enabled
            self.saveLifetimeStats()
            if enabled {
                self.fetchElectricityCost()
            }
        }
    }

    func setZipCode(_ zip: String) {
        DispatchQueue.main.async {
            self.zipCode = zip
            if let state = self.getStateFromZipCode(zip) {
                let rate = self.getStateElectricityRate(state: state)
                self.electricityCostPerKwh = rate
                self.autoFindElectricityCost = false
            }
            self.objectWillChange.send()
            self.saveLifetimeStats()
        }
    }

    func resetAllStatistics() {
        DispatchQueue.main.async {
            self.lifetimeEnergyUsed = 0
            self.lifetimeSessionCount = 0
            self.todayEnergyUsed = 0
            self.dailyHistory = []
            self.energyHistory = []
            self.currentDateString = self.todayDateString()
            self.objectWillChange.send()
            self.saveLifetimeStats()
        }
    }

    private func getStateFromZipCode(_ zip: String) -> String? {
        let cleanZip = zip.filter { $0.isNumber }
        guard cleanZip.count >= 3 else { return nil }

        let prefixStr = String(cleanZip.prefix(3))
        guard let prefix = Int(prefixStr) else { return nil }

        let zipToState: [(ClosedRange<Int>, String)] = [
            (005...005, "NY"), (010...027, "MA"), (028...029, "RI"), (030...038, "NH"),
            (039...049, "ME"), (050...059, "VT"), (060...069, "CT"), (070...089, "NJ"),
            (100...149, "NY"), (150...196, "PA"), (197...199, "DE"), (200...205, "DC"),
            (206...219, "MD"), (220...246, "VA"), (247...268, "WV"), (270...289, "NC"),
            (290...299, "SC"), (300...319, "GA"), (320...339, "FL"), (350...369, "AL"),
            (370...385, "TN"), (386...397, "MS"), (400...427, "KY"), (430...459, "OH"),
            (460...479, "IN"), (480...499, "MI"), (500...528, "IA"), (530...549, "WI"),
            (550...567, "MN"), (570...577, "SD"), (580...588, "ND"), (590...599, "MT"),
            (600...629, "IL"), (630...658, "MO"), (660...679, "KS"), (680...693, "NE"),
            (700...714, "LA"), (716...729, "AR"), (730...749, "OK"), (750...799, "TX"),
            (800...816, "CO"), (820...831, "WY"), (832...838, "ID"), (840...847, "UT"),
            (850...865, "AZ"), (870...884, "NM"), (889...898, "NV"), (900...961, "CA"),
            (967...968, "HI"), (970...979, "OR"), (980...994, "WA"), (995...999, "AK")
        ]

        for (range, state) in zipToState {
            if range.contains(prefix) {
                return state
            }
        }
        return nil
    }

    private func fetchElectricityCost() {
        let url = URL(string: "https://ipapi.co/json/")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let region = json["region_code"] as? String {
                let rate = self?.getStateElectricityRate(state: region) ?? 0.12
                DispatchQueue.main.async {
                    self?.electricityCostPerKwh = rate
                    self?.saveLifetimeStats()
                }
            }
        }.resume()
    }

    private func getStateElectricityRate(state: String) -> Double {
        let rates: [String: Double] = [
            "AL": 0.12, "AK": 0.22, "AZ": 0.11, "AR": 0.10, "CA": 0.23,
            "CO": 0.12, "CT": 0.21, "DE": 0.13, "FL": 0.12, "GA": 0.12,
            "HI": 0.33, "ID": 0.10, "IL": 0.13, "IN": 0.13, "IA": 0.12,
            "KS": 0.12, "KY": 0.11, "LA": 0.10, "ME": 0.17, "MD": 0.13,
            "MA": 0.22, "MI": 0.16, "MN": 0.13, "MS": 0.11, "MO": 0.11,
            "MT": 0.11, "NE": 0.10, "NV": 0.12, "NH": 0.19, "NJ": 0.16,
            "NM": 0.12, "NY": 0.19, "NC": 0.11, "ND": 0.10, "OH": 0.12,
            "OK": 0.10, "OR": 0.11, "PA": 0.14, "RI": 0.21, "SC": 0.12,
            "SD": 0.11, "TN": 0.11, "TX": 0.12, "UT": 0.10, "VT": 0.17,
            "VA": 0.12, "WA": 0.10, "WV": 0.12, "WI": 0.14, "WY": 0.11,
            "DC": 0.13
        ]
        return rates[state] ?? 0.12
    }

    private func archiveDay(date: String, energy: Double) {
        if let index = dailyHistory.firstIndex(where: { $0.date == date }) {
            dailyHistory[index].energyUsed = energy
        } else {
            dailyHistory.append(DailyEnergyRecord(date: date, energyUsed: energy))
        }
        if dailyHistory.count > 365 {
            dailyHistory.removeFirst(dailyHistory.count - 365)
        }
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func checkDayChange() {
        let now = todayDateString()
        if now != currentDateString {
            if todayEnergyUsed > 0 {
                archiveDay(date: currentDateString, energy: todayEnergyUsed)
            }
            todayEnergyUsed = 0
            currentDateString = now
            UserDefaults.standard.set(currentDateString, forKey: todayDateKey)
            saveLifetimeStats()
        }
    }

    private func incrementSessionCount() {
        lifetimeSessionCount += 1
        saveLifetimeStats()
    }

    private func startPeriodicSave() {
        let queue = DispatchQueue(label: "com.watt.save", qos: .utility)
        saveTimer = DispatchSource.makeTimerSource(queue: queue)
        saveTimer?.schedule(deadline: .now() + 30, repeating: .seconds(30))
        saveTimer?.setEventHandler { [weak self] in
            self?.saveLifetimeStats()
        }
        saveTimer?.resume()
    }

    private func updateAllReadings() {
        let battery = readBatteryInfo()
        let charger = readChargerInfo()
        let telemetry = readPowerTelemetry()
        let port = readPortInfo()

        let smcSystem = smcReader.readFloat("PSTR") ?? 0
        let smcWall = smcReader.readFloat("PDTR") ?? 0
        let smcBattery = smcReader.readFloat("SBAP") ?? 0

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.batteryInfo = battery
            self.chargerInfo = charger
            self.powerTelemetry = telemetry
            self.portInfo = port

            self.systemPower = Double(smcSystem)
            self.batteryPower = Double(smcBattery)

            // Compute wall power from system + charging for better sync
            // batteryPower is positive when discharging, negative when charging
            // When charging: wallPower = systemPower + |chargingPower|
            // When discharging: wallPower should be 0 (on battery)
            if self.batteryPower < 0 {
                // Charging: wall supplies system + battery charging
                self.wallPower = self.systemPower + abs(self.batteryPower)
            } else if battery?.isPluggedIn == true {
                // Plugged in but not charging (or discharging to supplement)
                self.wallPower = max(0, self.systemPower - self.batteryPower)
            } else {
                // On battery
                self.wallPower = 0
            }

            // If computed wall power seems off, fall back to SMC reading
            if self.wallPower <= 0 && smcWall > 0 && battery?.isPluggedIn == true {
                self.wallPower = Double(smcWall)
            }

            // currentPower = system power (compute usage only, excludes charging)
            // Priority: SMC system > telemetry system > battery discharge > computed from V*A
            if self.systemPower > 0 {
                self.currentPower = self.systemPower
            } else if let telemetry = telemetry, telemetry.systemPower > 0 {
                self.currentPower = telemetry.systemPower
            } else if self.batteryPower > 0 {
                // On battery: battery discharge = system consumption
                self.currentPower = self.batteryPower
            } else if let telemetry = telemetry, telemetry.batteryPower > 0 {
                self.currentPower = telemetry.batteryPower
            } else if let battery = battery, battery.powerUsage > 0 {
                self.currentPower = battery.powerUsage
            } else {
                self.currentPower = 0
            }

            self.objectWillChange.send()
            self.updateEnergyTracking()
        }
    }

    private func updateEnergyTracking() {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastReadingTime) / 3600.0

        checkDayChange()

        // Track system power consumption using trapezoidal integration
        // Energy = (P1 + P2) / 2 × Δt - more accurate than simple P × t
        // This excludes battery charging - going 0→100% doesn't inflate stats
        if currentPower > 0 || lastPowerReading > 0 {
            let avgPower = (currentPower + lastPowerReading) / 2.0
            if avgPower > 0 {
                let energyDelta = avgPower * timeDelta
                todayEnergyUsed += energyDelta
                lifetimeEnergyUsed += energyDelta
            }
        }

        let reading = EnergyReading(timestamp: now, power: currentPower)
        energyHistory.append(reading)
        if energyHistory.count > 60 {
            energyHistory.removeFirst()
        }

        updateBatteryRate()

        lastPowerReading = currentPower
        lastReadingTime = now
    }

    private func updateBatteryRate() {
        guard let battery = batteryInfo else {
            batteryRatePerMinute = 0
            return
        }

        // Use consistent nominal voltage (mAh × V / 1000 = Wh)
        let maxCapacityWh = Double(battery.maxCapacity) * battery.nominalVoltage / 1000.0
        guard maxCapacityWh > 0 else {
            batteryRatePerMinute = 0
            return
        }

        // chargingPower: positive = charging, negative = discharging
        // batteryPower from SMC: positive = discharging, negative = charging
        let chargingPower = -batteryPower
        // Rate = (Power / Capacity) × 100% / 60min = %/min
        batteryRatePerMinute = (chargingPower / maxCapacityWh) * 100.0 / 60.0
    }

    private func readBatteryInfo() -> BatteryInfo? {
        var info = BatteryInfo()

        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]

        if let sources = sources {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    info.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                    info.isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                    info.currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
                    info.timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int ?? 0
                    info.timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? 0
                }
            }
        }

        guard let properties = getAppleSmartBatteryProperties() else { return info }

        if let voltage = properties["Voltage"] as? Int {
            info.voltage = Double(voltage) / 1000.0
        }

        let minVoltage = 10.0
        let maxVoltage = 12.6
        info.nominalVoltage = (minVoltage + maxVoltage) / 2.0

        if let amperage = properties["InstantAmperage"] as? UInt64 {
            info.amperage = convertSignedValue(amperage)
        } else if let amperage = properties["Amperage"] as? UInt64 {
            info.amperage = convertSignedValue(amperage)
        } else if let amperage = properties["InstantAmperage"] as? Int {
            info.amperage = Double(amperage)
        } else if let amperage = properties["Amperage"] as? Int {
            info.amperage = Double(amperage)
        }

        if let current = properties["CurrentCapacity"] as? Int {
            info.currentCapacity = current
        }
        if let currentRaw = properties["AppleRawCurrentCapacity"] as? Int {
            info.currentCapacityRaw = currentRaw
        }
        if let max = properties["AppleRawMaxCapacity"] as? Int {
            info.maxCapacity = max
        }
        if let design = properties["DesignCapacity"] as? Int {
            info.designCapacity = design
        }

        if let cycles = properties["CycleCount"] as? Int {
            info.cycleCount = cycles
        }

        if let temp = properties["Temperature"] as? Int {
            info.temperature = (Double(temp) / 10.0) - 273.15
        }

        if let charging = properties["IsCharging"] as? Bool {
            info.isCharging = charging
        }
        if let external = properties["ExternalConnected"] as? Bool {
            info.isPluggedIn = external
        }
        if let full = properties["FullyCharged"] as? Bool {
            info.fullyCharged = full
        }

        if let remaining = properties["TimeRemaining"] as? Int, remaining != 65535 {
            info.timeRemaining = remaining
        }
        if let toFull = properties["AvgTimeToFull"] as? Int, toFull != 65535 {
            info.timeToFull = toFull
        }

        info.powerUsage = abs(info.voltage * info.amperage / 1000.0)

        if info.designCapacity > 0 {
            info.batteryHealth = (Double(info.maxCapacity) / Double(info.designCapacity)) * 100.0
        }

        return info
    }

    private func readChargerInfo() -> ChargerInfo? {
        var charger = ChargerInfo()

        if let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            charger.isConnected = true
            charger.watts = adapterDetails["Watts"] as? Int ?? 0
            charger.familyCode = adapterDetails["FamilyCode"] as? Int ?? 0
            charger.name = adapterDetails["Name"] as? String ?? ""
            charger.serialNumber = adapterDetails["SerialNumber"] as? String ?? ""
            charger.isAppleAdapter = charger.familyCode > 0
        }

        guard let properties = getAppleSmartBatteryProperties() else { return charger }

        if let external = properties["ExternalConnected"] as? Bool {
            charger.isConnected = external
        }

        if let chargerData = properties["ChargerData"] as? [String: Any] {
            if let chargerId = chargerData["ChargerID"] as? Int {
                charger.chargerId = chargerId
            }
            if let voltage = chargerData["ChargingVoltage"] as? Int {
                charger.chargingVoltage = Double(voltage) / 1000.0
            }
            if let current = chargerData["ChargingCurrent"] as? Int {
                charger.chargingCurrent = Double(current)
            }
        }

        if let adapterDetails = properties["AdapterDetails"] as? [String: Any] {
            if let familyCode = adapterDetails["FamilyCode"] as? Int {
                charger.familyCode = familyCode
                if familyCode > 0 {
                    charger.isAppleAdapter = true
                }
            }
            if let watts = adapterDetails["Watts"] as? Int {
                charger.watts = watts
            }
            if let isApple = adapterDetails["IsAppleBrand"] as? Bool {
                charger.isAppleAdapter = isApple
            }
            if let manufacturer = adapterDetails["Manufacturer"] as? String {
                if manufacturer.lowercased().contains("apple") {
                    charger.isAppleAdapter = true
                }
            }
            if let name = adapterDetails["Name"] as? String, !name.isEmpty {
                charger.name = name
                if name.lowercased().contains("apple") {
                    charger.isAppleAdapter = true
                }
            }
        }

        if charger.name.lowercased().contains("apple") {
            charger.isAppleAdapter = true
        }

        return charger
    }

    private func readPowerTelemetry() -> PowerTelemetry? {
        guard let properties = getAppleSmartBatteryProperties(),
              let powerData = properties["PowerTelemetryData"] as? [String: Any] else { return nil }

        var telemetry = PowerTelemetry()

        if let batteryPower = powerData["BatteryPower"] as? Int {
            telemetry.batteryPower = Double(batteryPower) / 1000.0
        } else if let batteryPower = powerData["BatteryPower"] as? UInt64 {
            if batteryPower < UInt64(Int32.max) {
                telemetry.batteryPower = Double(batteryPower) / 1000.0
            }
        }

        if let systemLoad = powerData["SystemLoad"] as? UInt64 {
            let signed = convertSignedValue(systemLoad)
            telemetry.systemPower = abs(signed) / 1000.0
        } else if let systemLoad = powerData["SystemLoad"] as? Int {
            telemetry.systemPower = abs(Double(systemLoad)) / 1000.0
        }

        if let systemPowerIn = powerData["SystemPowerIn"] as? UInt64 {
            telemetry.systemPowerIn = Double(systemPowerIn) / 1000.0
        } else if let systemPowerIn = powerData["SystemPowerIn"] as? Int {
            telemetry.systemPowerIn = Double(systemPowerIn) / 1000.0
        }

        if let wallEnergy = powerData["AccumulatedWallEnergyEstimate"] as? UInt64 {
            telemetry.accumulatedWallEnergy = Double(wallEnergy) / 1000.0
        }
        if let systemEnergy = powerData["AccumulatedSystemEnergyConsumed"] as? UInt64 {
            telemetry.accumulatedSystemEnergy = Double(systemEnergy) / 1000.0
        }
        if let batteryEnergy = powerData["AccumulatedBatteryPower"] as? UInt64 {
            telemetry.accumulatedBatteryPower = Double(batteryEnergy) / 1000.0
        }

        return telemetry
    }

    private func readPortInfo() -> PortInfo? {
        guard let properties = getAppleSmartBatteryProperties(),
              let portControllers = properties["PortControllerInfo"] as? [[String: Any]] else { return nil }

        var ports: [USBCPort] = []

        for (index, controller) in portControllers.enumerated() {
            var port = USBCPort(index: index)

            port.attachCount = controller["PortControllerAttachCount"] as? Int ?? 0
            port.detachCount = controller["PortControllerDetachCount"] as? Int ?? 0
            port.nPDOs = controller["PortControllerNPDOs"] as? Int ?? 0
            port.maxPower = controller["PortControllerMaxPower"] as? Int ?? 0
            port.portMode = controller["PortControllerPortMode"] as? Int ?? 0

            if let pdos = controller["PortControllerPortPDO"] as? [Int] {
                port.pdos = pdos.filter { $0 > 0 }
            }

            ports.append(port)
        }

        let activePortIndex = ports.firstIndex { $0.attachCount > 0 && $0.nPDOs > 0 }

        return PortInfo(ports: ports, activePortIndex: activePortIndex)
    }

    private func getAppleSmartBatteryProperties() -> [String: Any]? {
        var serviceIterator: io_iterator_t = 0
        let matchingDict = IOServiceNameMatching("AppleSmartBattery")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &serviceIterator) == KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(serviceIterator) }

        let service = IOIteratorNext(serviceIterator)
        defer { if service != 0 { IOObjectRelease(service) } }

        guard service != 0 else { return nil }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }

        return props?.takeRetainedValue() as? [String: Any]
    }

    private func convertSignedValue(_ value: UInt64) -> Double {
        if value > UInt64(Int64.max) {
            return Double(Int64(bitPattern: value))
        }
        return Double(value)
    }

    var costPerHour: Double {
        // Cost based on system power consumption (compute usage)
        // Returns dollars per hour (consistent with todayCost, lifetimeCost)
        guard currentPower > 0 else { return 0 }
        return (currentPower / 1000.0) * electricityCostPerKwh
    }

    var todayCost: Double {
        return (todayEnergyUsed / 1000.0) * electricityCostPerKwh
    }
}
