import Foundation

/// Lokaler Port von vehicle_costs.py (Server ab 0.32.0): sonstige
/// Fahrzeugkosten, Wertverlust und Leasing.
///
/// Noetig, weil das Dashboard auch im Server-Modus lokal entsteht
/// (AppRepository.fetchStatsSummary) und Kauf/Leasing auch im
/// Local-Only-Modus funktionieren sollen. Die Regeln MUESSEN mit
/// vehicle_costs.py uebereinstimmen - die Faelle in
/// tests/test_vehicle_costs.py (Server-Repo) gelten hier genauso:
///
/// - Sonstige Kosten: `once` ist eine Zahlung am Startdatum, wiederkehrende
///   laufen vom URSPRUENGLICHEN Ankertag aus (31.01. -> 28.02. -> 31.03.) bis
///   zum Enddatum (inklusive) oder bis heute. Ein Jahresbetrag zaehlt in dem
///   Monat, in dem er faellig ist - nicht auf zwoelf Monate verteilt.
/// - Leasing: Rate plus Sonderzahlung / Laufzeit in Monaten; ohne Enddatum
///   zaehlt die Sonderzahlung im ersten Monat.
/// - Wertverlust: Restwertkurve (1. Jahr linear auf 75 %, danach x0,87 je
///   Jahr) ueber ein "wirksames Alter" = max(Kalenderalter, km / 15.000);
///   der Kaufpreis gilt als Wert BEIM KAUF. Monatsbetraege laufen in Perioden
///   ab dem Kaufdatum und zaehlen voll, sobald sie begonnen haben; ein
///   ueberschriebener Monatsbetrag ersetzt die Kurve komplett.
/// - Jeder Monatsbetrag wird einzeln auf den Cent gerundet (wie Pythons
///   `round(x, 2)`).
enum LocalVehicleCostCalculator {
    /// Jahresfahrleistung, die das "wirksame Alter" einem Kalenderjahr gleichsetzt.
    static let kmPerYearReference = 15000.0
    static let firstYearResidual = 0.75
    static let yearlyResidualFactor = 0.87
    static let daysPerYear = 365.25
    /// Zeitraum, aus dem die aktuelle Fahrleistung geschaetzt wird.
    static let mileageWindowDays = 365
    static let minMileageSpanDays = 30

    /// Eine einzelne Zahlung bzw. ein Monatsbetrag, fertig zum Aufsummieren.
    struct Entry {
        let vehicleId: String
        /// Lokale Mitternacht.
        let day: Date
        let amount: Double
        /// Kategorie aus `CostCategory`, bzw. "depreciation" / "leasing".
        let category: String
    }

    private static var calendar: Calendar { Calendar.current }

    private static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Kalendertage zwischen zwei Tagen, wie `(b - a).days` mit Python-`date`.
    private static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }

    private static func addMonths(_ anchor: Date, _ months: Int) -> Date {
        LocalFeeAllocator.addMonths(anchor, months)
    }

    // MARK: - Sonstige Kosten

    /// Zahlungstermine eines Kosteneintrags bis `until` (einschliesslich).
    static func occurrences(_ cost: VehicleCost, until: Date) -> [Date] {
        let start = day(cost.startDate)
        let untilDay = day(until)
        if start > untilDay { return [] }
        guard cost.interval != .once else { return [start] }
        let end = cost.endDate.map(day)
        let step = cost.interval == .yearly ? 12 : 1
        var result: [Date] = []
        var k = 0
        while true {
            let d = addMonths(start, k * step)
            if d > untilDay { break }
            if let end, d > end { break }
            result.append(d)
            k += 1
        }
        return result
    }

    static func costEntries(_ costs: [VehicleCost], until: Date) -> [Entry] {
        costs.flatMap { cost in
            occurrences(cost, until: until).map {
                Entry(vehicleId: cost.vehicleId, day: $0, amount: cost.amount, category: cost.categoryValue.rawValue)
            }
        }
    }

    /// Summe aller Zahlungen bis heute ("bisher bezahlt"), wie `paid_to_date`.
    static func paidToDate(_ cost: VehicleCost, until: Date = Date()) -> Double {
        round2(cost.amount * Double(occurrences(cost, until: until).count))
    }

    // MARK: - Wertverlust

    /// Restwert in Anteilen des Neupreises nach `ageYears` wirksamen Jahren.
    static func residualFraction(_ ageYears: Double) -> Double {
        if ageYears <= 0 { return 1.0 }
        if ageYears <= 1 { return 1.0 - (1.0 - firstYearResidual) * ageYears }
        return firstYearResidual * pow(yearlyResidualFactor, ageYears - 1)
    }

    /// Wertverlauf eines gekauften Fahrzeugs. `odometer` sind (Tag, km-Stand)-
    /// Paare aus den Ladevorgaengen; zwischen zwei Staenden wird linear
    /// interpoliert, nach dem letzten mit der aktuellen Fahrleistung
    /// fortgeschrieben - sonst stuende der Wertverlust bei Ladepausen still.
    struct Depreciation {
        let price: Double
        let purchaseDay: Date?
        let registrationDay: Date?
        let today: Date
        let points: [(day: Date, km: Double)]
        private(set) var kmPerYear: Double = LocalVehicleCostCalculator.kmPerYearReference

        init(vehicle: Vehicle, odometer: [(Date, Int)], today: Date) {
            price = vehicle.purchasePrice ?? 0
            purchaseDay = vehicle.purchaseDate.map(LocalVehicleCostCalculator.day)
            registrationDay = vehicle.firstRegistration.map(LocalVehicleCostCalculator.day) ?? purchaseDay
            self.today = LocalVehicleCostCalculator.day(today)
            var pts: [(day: Date, km: Double)] = []
            if let purchaseDay, let km = vehicle.purchaseOdometerKm {
                pts.append((day: purchaseDay, km: Double(km)))
            }
            // Sortiert wie Pythons Tupel-Sortierung: Tag, dann km.
            let sorted = odometer
                .map { (day: LocalVehicleCostCalculator.day($0.0), km: $0.1) }
                .sorted { ($0.day, $0.km) < ($1.day, $1.km) }
            for (d, km) in sorted {
                if let purchaseDay, d < purchaseDay { continue }
                // Ein rueckwaerts laufender Stand (Zahlendreher) wird ignoriert.
                if let last = pts.last, Double(km) < last.km { continue }
                pts.append((day: d, km: Double(km)))
            }
            points = pts
            kmPerYear = computeKmPerYear()
        }

        var valid: Bool { price > 0 && purchaseDay != nil }

        private func computeKmPerYear() -> Double {
            typealias C = LocalVehicleCostCalculator
            guard points.count >= 2, let last = points.last else { return C.kmPerYearReference }
            let windowStart = C.calendar.date(byAdding: .day, value: -C.mileageWindowDays, to: last.day) ?? last.day
            let recent = points.filter { $0.day >= windowStart }
            var first = recent.count >= 2 ? recent[0] : points[0]
            var span = C.days(from: first.day, to: last.day)
            if span < C.minMileageSpanDays {
                first = points[0]
                span = C.days(from: first.day, to: last.day)
            }
            if span < C.minMileageSpanDays { return C.kmPerYearReference }
            return max(last.km - first.km, 0) / Double(span) * C.daysPerYear
        }

        func kmAt(_ date: Date) -> Double {
            typealias C = LocalVehicleCostCalculator
            // Ohne jeden km-Stand zaehlt allein das Kalenderalter.
            guard let first = points.first, let last = points.last else { return 0 }
            let d = C.day(date)
            if d <= first.day { return first.km }
            for (p0, p1) in zip(points, points.dropFirst()) where p0.day <= d && d <= p1.day {
                let span = C.days(from: p0.day, to: p1.day)
                return span == 0
                    ? p0.km
                    : p0.km + (p1.km - p0.km) * Double(C.days(from: p0.day, to: d)) / Double(span)
            }
            return last.km + kmPerYear * Double(C.days(from: last.day, to: d)) / C.daysPerYear
        }

        func effectiveAge(_ date: Date) -> Double {
            typealias C = LocalVehicleCostCalculator
            let calendarAge = registrationDay.map { Double(max(C.days(from: $0, to: date), 0)) / C.daysPerYear } ?? 0
            return max(calendarAge, kmAt(date) / C.kmPerYearReference)
        }

        func valueAt(_ date: Date) -> Double {
            guard let purchaseDay else { return 0 }
            let base = LocalVehicleCostCalculator.residualFraction(effectiveAge(purchaseDay))
            return price * LocalVehicleCostCalculator.residualFraction(effectiveAge(date)) / base
        }

        func lossBetween(_ start: Date, _ end: Date) -> Double {
            max(valueAt(start) - valueAt(end), 0)
        }

        func suggestedMonthly() -> Double {
            lossBetween(today, LocalVehicleCostCalculator.addMonths(today, 1))
        }
    }

    static func odometerPoints(_ sessions: [ChargingSession]) -> [(Date, Int)] {
        sessions.compactMap { s in s.odometerKm.map { (s.startTime, $0) } }
    }

    /// Monatsbetraege fuer Wertverlust bzw. Leasing bis `until`. `sessions`
    /// sind die Ladevorgaenge DIESES Fahrzeugs (fuer die km-Staende).
    static func ownershipEntries(vehicle: Vehicle, sessions: [ChargingSession], until: Date) -> [Entry] {
        switch vehicle.ownershipValue {
        case .leasing:
            return leasingEntries(vehicle: vehicle, until: until)
        case .none:
            return []
        case .purchase:
            break
        }
        let untilDay = day(until)
        guard let purchaseDate = vehicle.purchaseDate else { return [] }
        let start = day(purchaseDate)
        // Wie Pythons Wahrheitswert: 0 und None zaehlen beide als "keine Angabe".
        if start > untilDay || ((vehicle.purchasePrice ?? 0) == 0 && (vehicle.depreciationMonthlyOverride ?? 0) == 0) {
            return []
        }
        let override = vehicle.depreciationMonthlyOverride
        let curve = override == nil
            ? Depreciation(vehicle: vehicle, odometer: odometerPoints(sessions), today: untilDay)
            : nil
        if let curve, !curve.valid { return [] }
        var result: [Entry] = []
        var k = 0
        while true {
            let pStart = addMonths(start, k)
            if pStart > untilDay { break }
            let amount = override ?? curve?.lossBetween(pStart, addMonths(start, k + 1)) ?? 0
            result.append(Entry(vehicleId: vehicle.id, day: pStart, amount: round2(amount), category: "depreciation"))
            k += 1
        }
        return result
    }

    static func leasingTermMonths(_ vehicle: Vehicle) -> Int? {
        guard let s = vehicle.leasingStart, let e = vehicle.leasingEnd else { return nil }
        let start = day(s)
        let end = day(e)
        if end < start { return nil }
        var k = 0
        while addMonths(start, k) <= end { k += 1 }
        return k
    }

    private static func leasingEntries(vehicle: Vehicle, until: Date) -> [Entry] {
        let untilDay = day(until)
        guard let s = vehicle.leasingStart else { return [] }
        let start = day(s)
        if start > untilDay { return [] }
        let end = vehicle.leasingEnd.map(day)
        let rate = vehicle.leasingRateMonthly ?? 0
        let term = leasingTermMonths(vehicle)
        let down = vehicle.leasingDownPayment ?? 0
        var result: [Entry] = []
        var k = 0
        while true {
            let pStart = addMonths(start, k)
            if pStart > untilDay { break }
            if let end, pStart > end { break }
            // Ohne Enddatum laesst sich die Sonderzahlung nicht verteilen -
            // dann zaehlt sie im ersten Monat.
            let share: Double
            if let term, term > 0 {
                share = down / Double(term)
            } else {
                share = k == 0 ? down : 0
            }
            result.append(Entry(vehicleId: vehicle.id, day: pStart, amount: round2(rate + share), category: "leasing"))
            k += 1
        }
        return result
    }

    /// Kennzahlen fuer die Anzeige am Fahrzeug, wie `ownership_info()`.
    struct OwnershipInfo {
        var estimatedValue: Double?
        var suggestedMonthly: Double?
        /// Was tatsaechlich je Monat zaehlt: Vorschlag oder ueberschriebener
        /// Wert bzw. Leasingrate inkl. Anteil Sonderzahlung.
        var ownershipMonthly: Double?
    }

    static func ownershipInfo(vehicle: Vehicle, sessions: [ChargingSession], today: Date = Date()) -> OwnershipInfo {
        var info = OwnershipInfo()
        switch vehicle.ownershipValue {
        case .leasing:
            let term = leasingTermMonths(vehicle)
            let down = vehicle.leasingDownPayment ?? 0
            if vehicle.leasingRateMonthly != nil || down != 0 {
                let share = (term ?? 0) > 0 ? down / Double(term!) : 0
                info.ownershipMonthly = round2((vehicle.leasingRateMonthly ?? 0) + share)
            }
        case .purchase:
            let curve = Depreciation(vehicle: vehicle, odometer: odometerPoints(sessions), today: today)
            if curve.valid {
                info.estimatedValue = round2(curve.valueAt(day(today)))
                info.suggestedMonthly = round2(curve.suggestedMonthly())
            }
            info.ownershipMonthly = vehicle.depreciationMonthlyOverride ?? info.suggestedMonthly
        case .none:
            break
        }
        return info
    }

    /// Ob es fuer dieses Fahrzeug ueberhaupt etwas jenseits des Ladens gibt -
    /// sonst blendet das Dashboard den Abschnitt aus.
    static func hasCostData(vehicle: Vehicle, costs: [VehicleCost]) -> Bool {
        vehicle.ownershipValue != Ownership.none || costs.contains { $0.vehicleId == vehicle.id }
    }

    // MARK: - Auswertung

    /// Dashboard-Abschnitt "Gesamtkosten", wie stats.py::build_vehicle_costs.
    ///
    /// `vehicles` sind die betrachteten Fahrzeuge (Fahrzeugfilter schon
    /// angewandt), `costs`/`sessions` duerfen alle sein - gebraucht werden nur
    /// die der betrachteten Fahrzeuge. Die km-Staende kommen aus der GANZEN
    /// Historie, nicht nur aus dem Zeitraum. `chargingCost` und `kmDriven`
    /// stammen aus der Zusammenfassung (inkl. Grundgebuehren).
    static func summary(
        vehicles: [Vehicle],
        costs: [VehicleCost],
        sessions: [ChargingSession],
        dateRange: ClosedRange<Date>?,
        chargingCost: Double,
        kmDriven: Int?,
        today: Date = Date()
    ) -> VehicleCostSummary? {
        guard !vehicles.isEmpty else { return nil }
        let ids = Set(vehicles.map(\.id))
        let relevant = costs.filter { ids.contains($0.vehicleId) }
        guard vehicles.contains(where: { hasCostData(vehicle: $0, costs: relevant) }) else { return nil }

        let todayDay = day(today)
        let startDay = dateRange.map { day($0.lowerBound) }
        let until = dateRange.map { min(day($0.upperBound), todayDay) } ?? todayDay
        var entries = costEntries(relevant, until: until)
        for vehicle in vehicles where vehicle.ownershipValue != Ownership.none {
            let history = sessions.filter { $0.vehicleId == vehicle.id && $0.odometerKm != nil }
            entries += ownershipEntries(vehicle: vehicle, sessions: history, until: until)
        }
        if let startDay { entries = entries.filter { $0.day >= startDay } }

        var byCat: [String: Double] = [:]
        if chargingCost != 0 { byCat["charging"] = chargingCost }
        for entry in entries { byCat[entry.category, default: 0] += entry.amount }
        let ownershipCost = byCat.filter { ["depreciation", "leasing"].contains($0.key) }.values.reduce(0, +)
        let otherCost = byCat.filter { !["charging", "depreciation", "leasing"].contains($0.key) }.values.reduce(0, +)
        let total = chargingCost + otherCost + ownershipCost
        return VehicleCostSummary(
            chargingCost: round2(chargingCost),
            otherCost: round2(otherCost),
            ownershipCost: round2(ownershipCost),
            totalCost: round2(total),
            costPerKm: (kmDriven ?? 0) > 0 ? round3(total / Double(kmDriven!)) : nil,
            byCategory: categoryStats(byCat)
        )
    }

    /// Kosten je Kalenderjahr und Kategorie fuer EIN Fahrzeug, neuestes Jahr
    /// zuerst - wie GET /api/vehicle-costs/summary mit `vehicle_id`: Laden
    /// inkl. Grundgebuehr-Anteil (ohne Perioden ohne Ladevorgang, die
    /// gehoeren zu keinem Fahrzeug), sonstige Kosten, Wertverlust bzw. Leasing.
    static func yearly(vehicle: Vehicle, costs: [VehicleCost], sessions: [ChargingSession], today: Date = Date()) -> [YearCostStat] {
        let own = sessions.filter { $0.vehicleId == vehicle.id }
        var entries = costEntries(costs.filter { $0.vehicleId == vehicle.id }, until: today)
        entries += ownershipEntries(vehicle: vehicle, sessions: own, until: today)
        var byYear: [Int: [String: Double]] = [:]
        for session in own {
            let amount = (session.priceTotal ?? 0) + (session.feeShare ?? 0)
            if amount != 0 {
                byYear[calendar.component(.year, from: session.startTime), default: [:]]["charging", default: 0] += amount
            }
        }
        for entry in entries {
            byYear[calendar.component(.year, from: entry.day), default: [:]][entry.category, default: 0] += entry.amount
        }
        return byYear.keys.sorted(by: >).map { year in
            let cats = byYear[year] ?? [:]
            return YearCostStat(year: year, total: round2(cats.values.reduce(0, +)), byCategory: categoryStats(cats))
        }
    }

    /// Groesster Posten zuerst, Posten ohne Betrag fallen weg.
    private static func categoryStats(_ byCat: [String: Double]) -> [CostCategoryStat] {
        byCat
            .sorted { $0.value > $1.value }
            .filter { $0.value != 0 }
            .map { CostCategoryStat(category: $0.key, amount: round2($0.value)) }
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded(.toNearestOrEven) / 100 }
    private static func round3(_ v: Double) -> Double { (v * 1000).rounded(.toNearestOrEven) / 1000 }
}
