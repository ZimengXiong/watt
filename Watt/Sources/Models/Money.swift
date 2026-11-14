import Foundation

/// Money display for the narrow stat columns. Amounts are stored in major units per kWh,
/// so a rate of 0.1750 means "0.1750 currency units per kWh".
enum Money {
    /// Rate as written on a bill, trailing zeros trimmed but never below two decimals:
    /// 0.12 -> "0.12", 0.1750 -> "0.175", 0.2000 -> "0.20".
    static func rateText(_ value: Double) -> String {
        let scaled = Int((max(0, value) * 10_000).rounded())
        var digits = String(format: "%04d", scaled % 10_000)
        while digits.count > 2, digits.hasSuffix("0") { digits.removeLast() }
        return "\(scaled / 10_000).\(digits)"
    }

    static func rate(_ value: Double, _ currency: Currency) -> String {
        "\(rateText(value)) \(currency.symbol)/kWh"
    }

    /// A cost in minor units, e.g. 24.5¢ or 3.1p.
    static func minor(_ amount: Double, _ currency: Currency) -> String {
        String(format: "%.1f%@", amount * 100, currency.minorSymbol)
    }
}

/// Display currency for money figures. The minor unit is what the narrow stat columns show.
enum Currency: String, CaseIterable, Codable {
    case usd, eur, gbp, cad, sek

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .cad: return "C$"
        case .sek: return "kr"
        }
    }

    var minorSymbol: String {
        switch self {
        case .usd, .cad: return "¢"
        case .eur: return "c"
        case .gbp: return "p"
        case .sek: return "ö"
        }
    }
}