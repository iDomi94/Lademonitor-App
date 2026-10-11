import Foundation

/// Lokaler Port von reminders.py (Server ab 0.33.0): Status, km-Prognose und
/// "Erledigt" der Erinnerungen.
///
/// Die App rechnet das IMMER selbst, auch im Server-Modus - so zeigen Liste,
/// Dashboard und Mitteilungen auch offline und im Local-Only-Modus dasselbe.
/// Die Regeln MUESSEN mit reminders.py uebereinstimmen; die Faelle in
/// tests/test_reminders.py (Server-Repo) gelten hier genauso:
///
/// - Status `overdue`, sobald das Datum VERSTRICHEN ist (der Tag selbst ist
///   noch `due_soon`) oder der km-Stand erreicht ist; `due_soon` im Vorlauf;
///   ohne jede Faelligkeit `done` (schon erledigt) bzw. `ok`.
/// - km-Stand = juengster der Ladevorgaenge, Fahrleistung aus 90 Tagen mit dem
///   letzten Stand VOR dem Fenster als Anker, mindestens 14 Tage Spanne, sonst
///   die ganze Historie.
/// - Prognose = heute + round(km_remaining / km_per_day) Tage (Python-`round`,
///   also kaufmaennisch zur geraden Zahl).
/// - "Erledigt": naechstes Datum ab Erledigungsdatum, ausser bei Arten mit
///   festem Kalendertag (Reifenwechsel, Versicherung, Steuer, THG) - dort
///   laeuft der ALTE Faelligkeitstag in Wiederholungsschritten weiter, bis er
///   nach dem Erledigen liegt. km ab dem km-Stand beim Erledigen.
///
/// Nicht portiert: das automatische Abhaken durch einen Reifenwechsel - das
/// macht der Server selbst, Reifen gibt es in der App nur im Server-Modus.
enum LocalReminderCalculator {
    static let mileageWindowDays = 90
    static let minMileageSpanDays = 14
    static let defaultLeadDays = 30
    static let defaultLeadKm = 1000

    /// Arten, deren Faelligkeit an einem festen Kalendertag haengt.
    static let fixedDateKinds: Set<ReminderKind> = [.tireWinter, .tireSummer, .insurance, .tax, .thg]

    /// Vorlage beim Anlegen (alle Werte aenderbar). `day` = fester
    /// Kalendertag (Monat, Tag) fuer die erste Faelligkeit.
    struct Template {
        var repeatMonths: Int?
        var repeatKm: Int?
        var day: (month: Int, day: Int)?
    }

    static func template(for kind: ReminderKind) -> Template {
        switch kind {
        case .hu: return Template(repeatMonths: 24)
        case .inspection: return Template(repeatMonths: 12, repeatKm: 30000)
        case .brakeFluid: return Template(repeatMonths: 24)
        case .tireWinter: return Template(repeatMonths: 12, day: (10, 15))
        case .tireSummer: return Template(repeatMonths: 12, day: (4, 15))
        case .insurance, .tax, .thg: return Template(repeatMonths: 12)
        case .custom: return Template()
        }
    }

    /// Welche Kostenkategorie "Erledigt" vorschlaegt. THG ist eine Einnahme,
    /// keine Kosten - dafuer gibt es keinen Vorschlag.
    static func costCategory(for kind: ReminderKind) -> CostCategory? {
        switch kind {
        case .hu, .inspection, .brakeFluid: return .maintenance
        case .tireWinter, .tireSummer: return .tires
        case .insurance: return .insurance
        case .tax: return .tax
        case .custom: return .other
        case .thg: return nil
        }
    }

    private static var calendar: Calendar { Calendar.current }

    private static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    private static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    // MARK: - Fahrleistung

    struct Mileage: Hashable {
        let currentKm: Int?
        let kmPerDay: Double?

        static let unknown = Mileage(currentKm: nil, kmPerDay: nil)
    }

    /// Aus den Ladevorgaengen EINES Fahrzeugs (beliebige Reihenfolge).
    static func mileage(sessions: [ChargingSession]) -> Mileage {
        let points = sessions
            .compactMap { s in s.odometerKm.map { (time: s.startTime, km: $0) } }
            .sorted { ($0.time, $0.km) < ($1.time, $1.km) }
        guard let last = points.last, let first = points.first else { return .unknown }
        // Wie `(a - b).days` mit Python-`datetime`: ganze Tage, abgerundet.
        func span(_ from: Date) -> Int {
            calendar.dateComponents([.day], from: from, to: last.time).day ?? 0
        }
        let windowStart = addDays(last.time, -mileageWindowDays)
        // Anker: der letzte Stand VOR dem Fenster, damit die Spanne das ganze
        // Fenster abdeckt (wie im Tarifrechner).
        var anchor = points.last { $0.time < windowStart } ?? first
        var days = span(anchor.time)
        if days < minMileageSpanDays {
            anchor = first
            days = span(anchor.time)
        }
        var rate: Double?
        if days >= minMileageSpanDays && last.km >= anchor.km {
            rate = Double(last.km - anchor.km) / Double(days)
        }
        return Mileage(currentKm: last.km, kmPerDay: rate)
    }

    // MARK: - Status

    struct State: Hashable {
        let status: ReminderStatus
        /// Datum, an dem `dueKm` bei der aktuellen Fahrleistung erreicht ist.
        let kmForecastDate: Date?
        let kmRemaining: Int?
        let daysRemaining: Int?
        /// Frueheres aus Datum und Prognose - zum Sortieren und fuer die
        /// Mitteilungen.
        let nextDueDate: Date?
    }

    static func evaluate(_ reminder: Reminder, mileage m: Mileage, today: Date = Date()) -> State {
        let todayDay = day(today)
        let dueDay = reminder.dueDate.map(day)
        let dueKm = reminder.dueKm
        let leadDays = reminder.leadDays
        let leadKm = reminder.leadKm

        let daysRemaining = dueDay.map { calendar.dateComponents([.day], from: todayDay, to: $0).day ?? 0 }
        var kmRemaining: Int?
        var forecast: Date?
        if let dueKm, let current = m.currentKm {
            let remaining = dueKm - current
            kmRemaining = remaining
            if remaining <= 0 {
                forecast = todayDay
            } else if let rate = m.kmPerDay, rate != 0 {
                let days = (Double(remaining) / rate).rounded(.toNearestOrEven)
                forecast = addDays(todayDay, Int(days))
            }
        }

        let status: ReminderStatus
        if dueDay == nil && dueKm == nil {
            status = reminder.lastDoneDate != nil ? .done : .ok
        } else if (daysRemaining.map { $0 < 0 } ?? false) || (kmRemaining.map { $0 <= 0 } ?? false) {
            status = .overdue
        } else if (daysRemaining.map { $0 <= leadDays } ?? false) || (kmRemaining.map { $0 <= leadKm } ?? false) {
            status = .dueSoon
        } else {
            status = .ok
        }

        let candidates = [dueDay, forecast].compactMap { $0 }
        return State(
            status: status,
            kmForecastDate: forecast,
            kmRemaining: kmRemaining,
            daysRemaining: daysRemaining,
            nextDueDate: candidates.min()
        )
    }

    /// Dringendste zuerst: ueberfaellig, bald faellig, dann nach naechstem
    /// Termin; ohne Termin zum Schluss (wie routers/reminders.py).
    static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { a, b in
            if a.state.status.rank != b.state.status.rank { return a.state.status.rank > b.state.status.rank }
            switch (a.state.nextDueDate, b.state.nextDueDate) {
            case let (x?, y?):
                if x != y { return x < y }
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): break
            }
            return a.reminder.displayTitle.localizedCompare(b.reminder.displayTitle) == .orderedAscending
        }
    }

    // MARK: - Vorlagen und "Erledigt"

    /// Vorschlag fuer die erste Faelligkeit einer Vorlage mit festem Tag.
    static func firstDueDate(kind: ReminderKind, today: Date = Date()) -> Date? {
        guard let fixed = template(for: kind).day else { return nil }
        let todayDay = day(today)
        let year = calendar.component(.year, from: todayDay)
        func make(_ year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: fixed.month, day: fixed.day))
        }
        guard let candidate = make(year) else { return nil }
        return candidate >= todayDay ? candidate : make(year + 1)
    }

    /// Naechste Faelligkeit nach "Erledigt" (siehe oben).
    static func nextDue(_ reminder: Reminder, doneDay: Date, doneKm: Int?) -> (date: Date?, km: Int?) {
        let done = day(doneDay)
        var nextDay: Date?
        if let months = reminder.repeatMonths, months != 0 {
            if fixedDateKinds.contains(reminder.kindValue), let oldDay = reminder.dueDate.map(day) {
                var k = 1
                var candidate = LocalFeeAllocator.addMonths(oldDay, months)
                while candidate <= done {
                    k += 1
                    candidate = LocalFeeAllocator.addMonths(oldDay, months * k)
                }
                nextDay = candidate
            } else {
                nextDay = LocalFeeAllocator.addMonths(done, months)
            }
        }
        var nextKm: Int?
        if let repeatKm = reminder.repeatKm, repeatKm != 0, let doneKm {
            nextKm = doneKm + repeatKm
        }
        return (nextDay, nextKm)
    }

    /// Der komplette Payload nach "Erledigt": Merker gesetzt, Faelligkeit
    /// fortgeschrieben - wie routers/reminders.py::complete().
    static func completedPayload(_ reminder: Reminder, doneDay: Date, doneKm: Int?) -> ReminderPayload {
        let next = nextDue(reminder, doneDay: doneDay, doneKm: doneKm)
        var payload = reminder.asPayload
        payload.lastDoneDate = day(doneDay)
        payload.lastDoneKm = doneKm
        payload.dueDate = next.date
        payload.dueKm = next.km
        return payload
    }

    // MARK: - Zusammenbauen

    /// Alle Erinnerungen mit Zustand, dringendste zuerst. `sessions` und
    /// `reminders` muessen dieselbe Fahrzeug-ID-Form benutzen (siehe
    /// LocalDataStore.canonicalVehicleIds).
    static func items(
        reminders: [Reminder], sessions: [ChargingSession], vehicles: [Vehicle], today: Date = Date()
    ) -> [ReminderItem] {
        let byVehicle = Dictionary(grouping: sessions, by: \.vehicleId)
        let names = Dictionary(vehicles.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var mileages: [String: Mileage] = [:]
        let result = reminders.map { reminder -> ReminderItem in
            let m = mileages[reminder.vehicleId] ?? mileage(sessions: byVehicle[reminder.vehicleId] ?? [])
            mileages[reminder.vehicleId] = m
            return ReminderItem(
                reminder: reminder,
                state: evaluate(reminder, mileage: m, today: today),
                currentKm: m.currentKm,
                vehicleName: names[reminder.vehicleId]
            )
        }
        return sorted(result)
    }
}
