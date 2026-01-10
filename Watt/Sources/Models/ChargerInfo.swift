import Foundation

struct ChargerInfo {
    var isConnected: Bool = false
    var watts: Int = 0
    var chargingVoltage: Double = 0
    var chargingCurrent: Double = 0
    var chargerId: Int = 0
    var familyCode: Int = 0
    var isAppleAdapter: Bool = false
    var name: String = ""
    var serialNumber: String = ""
}
