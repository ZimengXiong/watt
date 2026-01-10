import Foundation

enum ChargerType: String, CaseIterable {
    case none = "Not Connected"
    case usbcApple = "USB-C (Apple)"
    case usbcThirdParty = "USB-C (Third Party)"
    case magsafeApple = "MagSafe (Apple)"
    case magsafeThirdParty = "MagSafe (Third Party)"
}

struct ChargerInfo {
    var isConnected: Bool = false
    var watts: Int = 0
    var chargingVoltage: Double = 0      // V
    var chargingCurrent: Double = 0      // mA
    var chargerId: Int = 0
    var familyCode: Int = 0
    var isAppleAdapter: Bool = false
    var name: String = ""
    var serialNumber: String = ""
    var chargerType: ChargerType = .none
}
