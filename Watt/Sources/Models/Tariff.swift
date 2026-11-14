import Foundation

/// A half-open `[start, end)` window inside a day, expressed in minutes from local midnight.
/// An `endMinute` that is not after `startMinute` wraps past midnight (e.g. 22:00-06:00).
struct TariffWindow: Equatable, Hashable {
    let startMinute: Int
    let endMinute: Int

    init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, let start = TariffWindow.minute(of: parts[0]), let end = TariffWindow.minute(of: parts[1]) else {
            return nil
        }
        // A window that starts and ends at the same reading wraps past midnight and so
        // covers every minute of the day: "06:00-06:00" would put the whole day off-peak
        // and silently halve what the panel says the day cost. Refuse the typo.
        guard start != end else { return nil }
        startMinute = start
        endMinute = end
    }

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// "22:00-06:00"
    var text: String { "\(TariffWindow.clock(startMinute))-\(TariffWindow.clock(endMinute))" }

    var wrapsMidnight: Bool { endMinute <= startMinute }

    func contains(_ minute: Int) -> Bool {
        wrapsMidnight ? (minute >= startMinute || minute < endMinute)
                      : (minute >= startMinute && minute < endMinute)
    }

    /// Minutes from local midnight at which this window starts or stops.
    /// Kept for the schedule display; transitions are found by asking the calendar.
    var boundaries: [Int] { [startMinute, endMinute] }

    private static func minute(of clock: String) -> Int? {
        let parts = clock.split(separator: ":", maxSplits: 1).map { Int($0) }
        guard parts.count == 2, let h = parts[0], let m = parts[1] else { return nil }
        // "22:00-24:00" is how the end of a night window is written on a contract, so 24:00
        // is accepted as midnight — the only 24-hour form allowed, and it round-trips.
        if h == 24 { return m == 0 ? 1440 : nil }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

/// Electricity pricing: a single flat rate, or separate peak / off-peak rates with
/// off-peak windows. Windows are compared against the machine's local time zone, so a
/// laptop that travels charges the tariff of wherever it currently is.
struct Tariff: Equatable {
    enum Mode: String, Codable {
        case flat
        case peakOffPeak
    }

    var mode: Mode = .flat
    /// Price per kWh while the clock is outside every off-peak window — and the only
    /// price there is in `.flat` mode.
    var peakRate: Double = 0.12
    /// Price per kWh inside an off-peak window.
    var offPeakRate: Double = 0.09
    var offPeakWindows: [TariffWindow] = [TariffWindow(startMinute: 22 * 60, endMinute: 6 * 60)]

    var isTimeOfUse: Bool { mode == .peakOffPeak }

    // MARK: Rates

    func rate(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        isTimeOfUse && isOffPeak(at: date, calendar: calendar) ? offPeakRate : peakRate
    }

    func isOffPeak(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isTimeOfUse else { return false }
        return contains(minuteOfDay(date, calendar: calendar))
    }

    func contains(_ minute: Int) -> Bool {
        offPeakWindows.contains { $0.contains(minute) }
    }

    // MARK: Transitions

    /// When the current rate stops applying: the first minute-granularity instant after
    /// `date` at which the band differs from the band `date` is in.
    ///
    /// Deliberately a scan rather than boundary arithmetic. A boundary is a wall-clock
    /// reading, and on a changeover day a reading either does not exist (Paris skips
    /// 02:00-03:00 on 2026-03-29, so a window ending at 02:30 ends at the jump) or exists
    /// twice (02:00-03:00 repeats on 2026-10-25, and the first pass is the one that ends
    /// the window). Both answers fall out of asking the calendar what the clock reads at
    /// each step; neither falls out of adding `(boundary - now)` absolute minutes to a
    /// number, which is what an earlier version here did and was an hour wrong twice a
    /// year. Cost is bounded by the length of the current band, worst case ~1500 steps of
    /// date arithmetic, and it runs once per label render.
    func nextTransition(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isTimeOfUse, !offPeakWindows.isEmpty else { return nil }
        let bandNow = isOffPeak(at: date, calendar: calendar)

        var probe = date
        for _ in 0..<1500 {
            guard let next = calendar.date(byAdding: .minute, value: 1, to: probe) else { return nil }
            probe = next
            if isOffPeak(at: probe, calendar: calendar) != bandNow { return probe }
        }
        return nil
    }

    /// "Off-peak · 0.090/kWh · until 06:00", without the leading band word.
    var nextTransitionText: String? {
        guard let next = nextTransition() else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "until \(f.string(from: next))"
    }

    // MARK: Text

    /// Parses a user-entered schedule, e.g. "22:00-06:00, 14:00-16:00".
    /// Returns nil when any entry is unreadable, so a typo never silently changes a bill.
    static func parseWindows(_ text: String) -> [TariffWindow]? {
        let entries = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
                          .map { $0.trimmingCharacters(in: .whitespaces) }
                          .filter { !$0.isEmpty }
        guard !entries.isEmpty else { return nil }
        var windows: [TariffWindow] = []
        for entry in entries {
            guard let window = TariffWindow(text: entry) else { return nil }
            windows.append(window)
        }
        return windows
    }

    static func windowsText(_ windows: [TariffWindow]) -> String {
        windows.map(\.text).joined(separator: ", ")
    }

    // MARK: Minutes

    private func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
