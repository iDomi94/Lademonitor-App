import Foundation

/// Vorgefertigte Zeitraeume fuer den globalen Filter (siehe SessionFilter). Jeder Preset
/// rechnet sich beim Antippen in einen konkreten Datumsbereich um - der Filter selbst kennt
/// danach nur noch ein `ClosedRange<Date>`, keine Preset-Identitaet.
enum FilterPreset: CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case last90Days
    case lastMonth
    case monthToDate
    case yearToDate
    case lastYear

    var id: Self { self }

    var title: String {
        switch self {
        case .last7Days: return "Letzte 7 Tage"
        case .last30Days: return "Letzte 30 Tage"
        case .last90Days: return "Letzte 90 Tage"
        case .lastMonth: return "Letzter Monat"
        case .monthToDate: return "Monat bis jetzt"
        case .yearToDate: return "Jahr bis jetzt"
        case .lastYear: return "Letztes Jahr"
        }
    }

    /// Ende ist immer das Ende des aktuellen Tages (23:59:59), damit heute erfasste
    /// Ladevorgaenge nicht durch eine Uhrzeit-Grenze mitten am Tag herausfallen.
    func range(calendar: Calendar = .current, now: Date = Date()) -> ClosedRange<Date> {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? now

        switch self {
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday)...endOfToday
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday)...endOfToday
        case .last90Days:
            return (calendar.date(byAdding: .day, value: -89, to: startOfToday) ?? startOfToday)...endOfToday
        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let lastMonthEnd = calendar.date(byAdding: .second, value: -1, to: thisMonthStart) ?? thisMonthStart
            return lastMonthStart...lastMonthEnd
        case .monthToDate:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
            return start...endOfToday
        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? startOfToday
            return start...endOfToday
        case .lastYear:
            let thisYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? startOfToday
            let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYearStart) ?? thisYearStart
            let lastYearEnd = calendar.date(byAdding: .second, value: -1, to: thisYearStart) ?? thisYearStart
            return lastYearStart...lastYearEnd
        }
    }
}
