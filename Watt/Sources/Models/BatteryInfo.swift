import Foundation

struct BatteryInfo {
    var voltage: Double = 0              // Volts (current, varies with charge)
    var nominalVoltage: Double = 11.4    // Volts (nominal/design voltage for Wh calc)
    var amperage: Double = 0             // mA (negative = discharging, positive = charging)
    var currentCapacity: Int = 0         // Current charge %
    var currentCapacityRaw: Int = 0      // Current capacity mAh (raw)
    var maxCapacity: Int = 0             // Max capacity mAh
    var designCapacity: Int = 0          // Original design capacity mAh
    var cycleCount: Int = 0
    var temperature: Double = 0          // Celsius
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var fullyCharged: Bool = false
    var timeRemaining: Int = 0           // Minutes
    var timeToFull: Int = 0              // Minutes
    var powerUsage: Double = 0           // Watts (calculated)
    var batteryHealth: Double = 0        // Percentage

    var formattedTimeRemaining: String {
        guard timeRemaining > 0 else { return "--" }
        let hours = timeRemaining / 60
        let minutes = timeRemaining % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedTimeToFull: String {
        guard timeToFull > 0 else { return "--" }
        let hours = timeToFull / 60
        let minutes = timeToFull % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
