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
    let id = UUID()
    let timestamp: Date
    let power: Double
}
