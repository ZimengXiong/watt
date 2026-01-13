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
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

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

    private func getKeyInfo(_ keyCode: UInt32) -> SMCKeyInfoData? {
        if let cached = keyInfoCache[keyCode] {
            return cached
        }

        var inp = SMCParamStruct()
        inp.key = keyCode
        inp.data8 = 9  // kSMCGetKeyInfo

        var out = SMCParamStruct()
        var outSz = MemoryLayout<SMCParamStruct>.size
        guard IOConnectCallStructMethod(connection, 2, &inp, MemoryLayout<SMCParamStruct>.size, &out, &outSz) == kIOReturnSuccess,
              out.result == 0 else { return nil }

        keyInfoCache[keyCode] = out.keyInfo
        return out.keyInfo
    }

    func readFloat(_ key: String) -> Float? {
        guard isConnected else { return nil }

        let keyCode = fourCharCode(key)

        guard let keyInfo = getKeyInfo(keyCode), keyInfo.dataSize == 4 else { return nil }

        var inp = SMCParamStruct()
        inp.key = keyCode
        inp.keyInfo.dataSize = keyInfo.dataSize
        inp.data8 = 5

        var out = SMCParamStruct()
        var outSz = MemoryLayout<SMCParamStruct>.size
        guard IOConnectCallStructMethod(connection, 2, &inp, MemoryLayout<SMCParamStruct>.size, &out, &outSz) == kIOReturnSuccess,
              out.result == 0 else { return nil }

        let bytes = out.bytes
        let value: UInt32 = UInt32(bytes.0) | UInt32(bytes.1) << 8 | UInt32(bytes.2) << 16 | UInt32(bytes.3) << 24
        return Float(bitPattern: value)
    }
}

struct DailyEnergyRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    var energyUsed: Double
}

class PowerMonitorService: ObservableObject {
    @Published var batteryInfo: BatteryInfo?
    @Published var chargerInfo: ChargerInfo?
    @Published var powerTelemetry: PowerTelemetry?
    @Published var portInfo: PortInfo?
    @Published var energyHistory: [EnergyReading] = []

    @Published private(set) var currentPower: Double = 0
    @Published private(set) var wallPower: Double = 0
    @Published private(set) var batteryPower: Double = 0
    @Published private(set) var systemPower: Double = 0
    private let powerChangeThreshold: Double = 0.2
    @Published var lifetimeEnergyUsed: Double = 0
    @Published var lifetimeSessionCount: Int = 0
    @Published var todayEnergyUsed: Double = 0
    @Published var dailyHistory: [DailyEnergyRecord] = []
    @Published var batteryRatePerMinute: Double = 0

    @Published var electricityCostPerKwh: Double = 0.12
    @Published var autoFindElectricityCost: Bool = false
    @Published var zipCode: String = ""

    var lifetimeCost: Double {
        return (lifetimeEnergyUsed / 1000.0) * electricityCostPerKwh
    }

    private var timer: DispatchSourceTimer?
    private var lastReadingTime: Date
    private var lastPowerReading: Double = 0
    private let smcReader = SMCReader()
    private var currentDateString: String = ""
    private var isAppVisible: Bool = false
    private let timerQueue = DispatchQueue(label: "com.watt.powermonitor", qos: .utility)
    private var saveTimer: DispatchSourceTimer?

    private enum Keys {
        static let lifetimeEnergy = "com.watt.lifetimeEnergy"
        static let lifetimeSessions = "com.watt.lifetimeSessions"
        static let todayEnergy = "com.watt.todayEnergy"
        static let todayDate = "com.watt.todayDate"
        static let dailyHistory = "com.watt.dailyHistory"
        static let electricityCost = "com.watt.electricityCost"
        static let autoFindCost = "com.watt.autoFindCost"
        static let zipCode = "com.watt.zipCode"
    }

    init() {
        lastReadingTime = Date()
        loadLifetimeStats()
        lifetimeSessionCount += 1
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
        restartTimerWithCurrentInterval()
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    func setAppVisible(_ visible: Bool) {
        isAppVisible = visible
        restartTimerWithCurrentInterval()
    }

    private func restartTimerWithCurrentInterval() {
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: timerQueue)

        let interval: DispatchTimeInterval = isAppVisible ? .seconds(1) : .seconds(3)
        let leeway: DispatchTimeInterval = isAppVisible ? .milliseconds(100) : .milliseconds(500)

        timer?.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        timer?.setEventHandler { [weak self] in
            self?.updateAllReadings()
        }
        timer?.resume()
    }

    private func loadLifetimeStats() {
        let defaults = UserDefaults.standard
        lifetimeEnergyUsed = defaults.double(forKey: Keys.lifetimeEnergy)
        lifetimeSessionCount = defaults.integer(forKey: Keys.lifetimeSessions)
        electricityCostPerKwh = max(0.01, defaults.double(forKey: Keys.electricityCost))
        if electricityCostPerKwh == 0.01 { electricityCostPerKwh = 0.12 }
        autoFindElectricityCost = defaults.bool(forKey: Keys.autoFindCost)
        zipCode = defaults.string(forKey: Keys.zipCode) ?? ""
        dailyHistory = (try? JSONDecoder().decode([DailyEnergyRecord].self, from: defaults.data(forKey: Keys.dailyHistory) ?? Data())) ?? []

        currentDateString = todayDateString()
        let savedDate = defaults.string(forKey: Keys.todayDate) ?? ""

        if savedDate == currentDateString {
            todayEnergyUsed = defaults.double(forKey: Keys.todayEnergy)
        } else if !savedDate.isEmpty, defaults.double(forKey: Keys.todayEnergy) > 0 {
            archiveDay(date: savedDate, energy: defaults.double(forKey: Keys.todayEnergy))
            todayEnergyUsed = 0
            defaults.set(currentDateString, forKey: Keys.todayDate)
        }

        if autoFindElectricityCost { fetchElectricityCost() }
    }

    private func saveLifetimeStats() {
        let defaults = UserDefaults.standard
        defaults.set(lifetimeEnergyUsed, forKey: Keys.lifetimeEnergy)
        defaults.set(lifetimeSessionCount, forKey: Keys.lifetimeSessions)
        defaults.set(todayEnergyUsed, forKey: Keys.todayEnergy)
        defaults.set(currentDateString, forKey: Keys.todayDate)
        defaults.set(electricityCostPerKwh, forKey: Keys.electricityCost)
        defaults.set(autoFindElectricityCost, forKey: Keys.autoFindCost)
        defaults.set(zipCode, forKey: Keys.zipCode)
        if let data = try? JSONEncoder().encode(dailyHistory) {
            defaults.set(data, forKey: Keys.dailyHistory)
        }
    }

    func setElectricityCost(_ cost: Double) {
        DispatchQueue.main.async {
            self.electricityCostPerKwh = cost
            self.autoFindElectricityCost = false
            self.saveLifetimeStats()
        }
    }

    func setAutoFindCost(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.autoFindElectricityCost = enabled
            self.saveLifetimeStats()
            if enabled { self.fetchElectricityCost() }
        }
    }

    func setZipCode(_ zip: String) {
        DispatchQueue.main.async {
            self.zipCode = zip
            if let state = self.getStateFromZipCode(zip) {
                self.electricityCostPerKwh = self.getStateElectricityRate(state: state)
                self.autoFindElectricityCost = false
            }
            self.saveLifetimeStats()
        }
    }

    func resetAllStatistics() {
        DispatchQueue.main.async {
            (self.lifetimeEnergyUsed, self.lifetimeSessionCount, self.todayEnergyUsed) = (0, 0, 0)
            (self.dailyHistory, self.energyHistory) = ([], [])
            self.currentDateString = self.todayDateString()
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
        switch state {
        case "HI": return 0.33
        case "AK": return 0.22
        case "CA", "MA": return 0.22
        case "CT", "RI": return 0.21
        case "NH", "NY": return 0.19
        case "ME", "VT": return 0.17
        case "MI", "NJ": return 0.16
        case "PA", "WI": return 0.14
        case "DE", "IL", "IN", "MD", "MN", "DC": return 0.13
        case "AZ", "KY", "MS", "MO", "MT", "NC", "SD", "TN", "WY": return 0.11
        case "AR", "ID", "LA", "NE", "ND", "OK", "UT", "WA": return 0.10
        default: return 0.12
        }
    }

    private func archiveDay(date: String, energy: Double) {
        if let index = dailyHistory.firstIndex(where: { $0.date == date }) {
            dailyHistory[index].energyUsed = energy
        } else {
            dailyHistory.append(DailyEnergyRecord(date: date, energyUsed: energy))
            if dailyHistory.count > 90 { dailyHistory.removeFirst(dailyHistory.count - 90) }
        }
    }

    private func todayDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func checkDayChange() {
        let now = todayDateString()
        guard now != currentDateString else { return }
        if todayEnergyUsed > 0 { archiveDay(date: currentDateString, energy: todayEnergyUsed) }
        todayEnergyUsed = 0
        currentDateString = now
        UserDefaults.standard.set(now, forKey: Keys.todayDate)
        saveLifetimeStats()
    }

    private func startPeriodicSave() {
        let queue = DispatchQueue(label: "com.watt.save", qos: .utility)
        saveTimer = DispatchSource.makeTimerSource(queue: queue)
        saveTimer?.schedule(deadline: .now() + 60, repeating: .seconds(60), leeway: .seconds(10))
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

            let newSystemPower = Double(smcSystem)
            let newBatteryPower = Double(smcBattery)
            if abs(newSystemPower - self.systemPower) > self.powerChangeThreshold {
                self.systemPower = newSystemPower
            }
            if abs(newBatteryPower - self.batteryPower) > self.powerChangeThreshold {
                self.batteryPower = newBatteryPower
            }

            var newWallPower: Double
            if self.batteryPower < 0 {
                newWallPower = self.systemPower + abs(self.batteryPower)
            } else if battery?.isPluggedIn == true {
                newWallPower = max(0, self.systemPower - self.batteryPower)
            } else {
                newWallPower = 0
            }

            if newWallPower <= 0 && smcWall > 0 && battery?.isPluggedIn == true {
                newWallPower = Double(smcWall)
            }

            if abs(newWallPower - self.wallPower) > self.powerChangeThreshold {
                self.wallPower = newWallPower
            }

            var newCurrentPower: Double = 0
            if self.systemPower > 0 {
                newCurrentPower = self.systemPower
            } else if let telemetry = telemetry, telemetry.systemPower > 0 {
                newCurrentPower = telemetry.systemPower
            } else if self.batteryPower > 0 {
                newCurrentPower = self.batteryPower
            } else if let telemetry = telemetry, telemetry.batteryPower > 0 {
                newCurrentPower = telemetry.batteryPower
            } else if let battery = battery, battery.powerUsage > 0 {
                newCurrentPower = battery.powerUsage
            }

            if abs(newCurrentPower - self.currentPower) > self.powerChangeThreshold {
                self.currentPower = newCurrentPower
            }

            self.updateEnergyTracking()
        }
    }

    private func updateEnergyTracking() {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastReadingTime) / 3600.0

        checkDayChange()

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
        if energyHistory.count > 30 {
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

        let maxCapacityWh = Double(battery.maxCapacity) * battery.nominalVoltage / 1000.0
        guard maxCapacityWh > 0 else {
            batteryRatePerMinute = 0
            return
        }

        let chargingPower = -batteryPower
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
        guard currentPower > 0 else { return 0 }
        return (currentPower / 1000.0) * electricityCostPerKwh
    }

    var todayCost: Double {
        return (todayEnergyUsed / 1000.0) * electricityCostPerKwh
    }
}
