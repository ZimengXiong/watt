import Foundation

struct BatteryInfo {
    var voltage: Double = 0
    var nominalVoltage: Double = 11.4
    var amperage: Double = 0
    var currentCapacity: Int = 0
    var currentCapacityRaw: Int = 0
    var maxCapacity: Int = 0
    var designCapacity: Int = 0
    var cycleCount: Int = 0
    var temperature: Double = 0
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var fullyCharged: Bool = false
    var timeRemaining: Int = 0
    var timeToFull: Int = 0
    var powerUsage: Double = 0
    var batteryHealth: Double = 0

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
