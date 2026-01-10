import Foundation

struct PowerTelemetry {
    var systemPower: Double = 0
    var batteryPower: Double = 0
    var systemPowerIn: Double = 0
    var accumulatedWallEnergy: Double = 0
    var accumulatedSystemEnergy: Double = 0
    var accumulatedBatteryPower: Double = 0
}

struct EnergyReading: Identifiable {
    private static var counter: Int = 0
    let id: Int
    let timestamp: Date
    let power: Double

    init(timestamp: Date, power: Double) {
        EnergyReading.counter += 1
        self.id = EnergyReading.counter
        self.timestamp = timestamp
        self.power = power
    }
}
