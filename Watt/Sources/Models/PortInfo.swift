import Foundation

struct USBCPort: Identifiable {
    let id = UUID()
    var index: Int
    var attachCount: Int = 0
    var detachCount: Int = 0
    var nPDOs: Int = 0
    var maxPower: Int = 0
    var portMode: Int = 0
    var pdos: [Int] = []
}

struct PortInfo {
    var ports: [USBCPort]
    var activePortIndex: Int?
}
