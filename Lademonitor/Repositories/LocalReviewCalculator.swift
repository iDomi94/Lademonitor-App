import Foundation

/// Jahres- und Monatsrueckblick (Reiter Tools), lokal gerechnet - auch im
/// Server-Modus und ohne Verbindung, wie das Dashboard.
///
/// Die Regeln stehen im Vertrag zu Schritt 11 und MUESSEN mit
/// `GET /api/stats/review` im Server uebereinstimmen (Android rechnet
/// dasselbe in `LocalReviewCalculator.kt`) - sonst zeigen App und Web
/// unterschiedliche Zahlen:
///
/// - Zugeordnet wird ueber den lokalen Kalendertag von `startTime`, beide
///   Enden inklusive. Vorperiode = Vorjahr bzw. Vormonat.
/// - Kosten = Saeulenpreis + Grundgebuehr-Anteil der Vorgaenge im Zeitraum,
///   dazu (nur ohne Fahrzeugfilter) die nicht umgelegten Perioden, die im
///   Zeitraum beginnen. Die Umlage selbst laeuft ueber ALLE Vorgaenge.
/// - km je Fahrzeug: letzter Stand im Zeitraum minus Anker (letzter Stand
///   VOR dem Zeitraum, sonst der erste im Zeitraum), nie negativ.
/// - Verbrauch: km-gewichtetes Mittel der Einzelwerte (Gewicht = Strecke zum
///   Vorgaenger), wie der Monatsverbrauch im Dashboard.
/// - Gleichstand bei Vorgangs-Rekorden: der fruehere Vorgang.
/// - Alles ungerundet, gerundet wird erst in der Anzeige.
enum LocalReviewCalculator {
    private static var calendar: Calendar { Calendar.current }

    /// Erster Tag (inklusive) und erster Tag DANACH (exklusive), lokale Mitternacht.
    static func bounds(period: Review.Period, year: Int, month: Int?) -> (start: Date, end: Date) {
        let startMonth = period == .year ? 1 : min(max(month ?? 1, 1), 12)
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))
            ?? calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: period == .year ? .year : .month, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Vorjahr bzw. Vormonat.
    static func previousPeriod(period: Review.Period, year: Int, month: Int?) -> (year: Int, month: Int?) {
        switch period {
        case .year:
            return (year: year - 1, month: nil)
        case .month:
            let m = month ?? 1
            if m <= 1 { return (year: year - 1, month: 12) }
            return (year: year, month: m - 1)
        }
    }

    static func compute(
        basis: ReviewBasis,
        period: Review.Period,
        year: Int,
        month: Int?,
        vehicleId: String?,
        comparison: ComparisonVehicle
    ) -> Review {
        let periodMonth: Int? = period == .month ? month : nil
        // Feste Reihenfolge (startTime, id): bestimmt "letzter Stand",
        // Vorgaenger und den Gleichstand bei Rekorden.
        let all = basis.sessions.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        let scoped = vehicleId.map { id in all.filter { $0.vehicleId == id } } ?? all

        // Verbrauch ueber die VOLLSTAENDIGE Historie je Fahrzeug - der erste
        // Vorgang im Zeitraum braucht seinen Vorgaenger davor.
        var consumption: [String: LocalConsumptionCalculator.Result] = [:]
        for (vid, list) in Dictionary(grouping: all, by: \.vehicleId) {
            let capacity = basis.vehicles.first { $0.id == vid }?.batteryCapacityKwh
            consumption.merge(LocalConsumptionCalculator.compute(sessions: list, batteryCapacityKwh: capacity)) { _, new in new }
        }

        let withOdometerByVehicle = Dictionary(grouping: scoped.filter { $0.odometerKm != nil }, by: \.vehicleId)

        func day(_ session: ChargingSession) -> Date { calendar.startOfDay(for: session.startTime) }
        func isInside(_ session: ChargingSession, _ start: Date, _ end: Date) -> Bool {
            let d = day(session)
            return start <= d && d < end
        }
        func unallocated(_ start: Date, _ end: Date) -> [LocalFeeAllocator.Period] {
            // Perioden ohne Vorgang gehoeren zu keinem Fahrzeug.
            guard vehicleId == nil else { return [] }
            return basis.unallocatedFees.filter {
                let d = calendar.startOfDay(for: $0.start)
                return start <= d && d < end
            }
        }
        func cost(_ session: ChargingSession) -> Double { (session.priceTotal ?? 0) + (session.feeShare ?? 0) }

        func totals(_ start: Date, _ end: Date) -> Review.Totals {
            let inside = scoped.filter { isInside($0, start, end) }
            let kwh = inside.reduce(0.0) { $0 + ($1.energyKwh ?? 0) }
            let fees = unallocated(start, end).reduce(0.0) { $0 + $1.amount }
            let totalCost = inside.reduce(0.0) { $0 + cost($1) } + fees

            var km = 0.0
            for (_, list) in withOdometerByVehicle {
                let insideOdo = list.filter { isInside($0, start, end) }
                guard let first = insideOdo.first?.odometerKm, let last = insideOdo.last?.odometerKm else { continue }
                let anchor = list.last(where: { day($0) < start })?.odometerKm ?? first
                km += Double(max(last - anchor, 0))
            }

            var weighted = 0.0, weight = 0.0
            for session in inside {
                if let result = consumption[session.id], let value = result.value, let resultKm = result.km, resultKm > 0 {
                    weighted += value * resultKm
                    weight += resultKm
                }
            }

            return Review.Totals(
                sessions: inside.count,
                kwh: kwh,
                cost: totalCost,
                km: km,
                avgPricePerKwh: kwh > 0 ? totalCost / kwh : nil,
                pricePer100km: km > 0 ? totalCost / km * 100 : nil,
                avgConsumptionKwhPer100km: weight > 0 ? weighted / weight : nil
            )
        }

        let (start, end) = bounds(period: period, year: year, month: periodMonth)
        let current = totals(start, end)

        let prev = previousPeriod(period: period, year: year, month: periodMonth)
        let prevBounds = bounds(period: period, year: prev.year, month: prev.month)
        let previousTotals = totals(prevBounds.start, prevBounds.end)

        // MARK: Monate (nur Jahr)

        var monthly: [Review.MonthRow] = []
        if period == .year {
            for m in 1...12 {
                let b = bounds(period: .month, year: year, month: m)
                let t = totals(b.start, b.end)
                monthly.append(Review.MonthRow(
                    month: m, sessions: t.sessions, kwh: t.kwh, cost: t.cost,
                    avgConsumptionKwhPer100km: t.avgConsumptionKwhPer100km
                ))
            }
        }

        // MARK: Ersparnis

        var savings: Review.Savings?
        if current.km > 0 {
            let fuel = comparison.fuel
            let liters = current.km * comparison.consumptionLPer100km / 100
            let fuelCost = liters * comparison.fuelPricePerL
            let co2Combustion = liters * fuel.co2KgPerLiter
            let co2Ev = current.kwh * comparison.gridCo2KgPerKwh
            savings = Review.Savings(
                fuel: fuel,
                consumptionLPer100km: comparison.consumptionLPer100km,
                fuelPricePerL: comparison.fuelPricePerL,
                gridCo2KgPerKwh: comparison.gridCo2KgPerKwh,
                configured: comparison.configured ?? false,
                fuelLiters: liters,
                fuelCost: fuelCost,
                chargingCost: current.cost,
                savedEur: fuelCost - current.cost,
                co2CombustionKg: co2Combustion,
                co2EvKg: co2Ev,
                savedCo2Kg: co2Combustion - co2Ev
            )
        }

        // MARK: Rekorde

        let inside = scoped.filter { isInside($0, start, end) }
        let locationNames = Dictionary(basis.locations.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let providerNames = Dictionary(basis.providers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let vehicleNames = Dictionary(basis.vehicles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        func locationName(_ s: ChargingSession) -> String? {
            nonEmpty(s.locationId.flatMap { locationNames[$0] }) ?? nonEmpty(s.geocodedPlace)
        }
        func providerName(_ s: ChargingSession) -> String? {
            nonEmpty(s.providerId.flatMap { providerNames[$0] })
        }
        func record(_ pick: (ChargingSession, Double)?, previousStart: Date? = nil) -> Review.SessionRecord? {
            guard let pick else { return nil }
            let s = pick.0
            return Review.SessionRecord(
                sessionId: s.id,
                startTime: s.startTime,
                value: pick.1,
                place: locationName(s) ?? providerName(s),
                vehicleName: vehicleNames[s.vehicleId],
                previousStartTime: previousStart
            )
        }

        var records = Review.Records()

        let priced = inside.filter { ($0.energyKwh ?? 0) >= 1 && ($0.priceTotal ?? 0) > 0 }
        if priced.count >= 2 {
            let perKwh: (ChargingSession) -> Double? = { s in
                guard let price = s.priceTotal, let kwh = s.energyKwh, kwh > 0 else { return nil }
                return price / kwh
            }
            records.cheapestPerKwh = record(best(priced, value: perKwh, isBetter: <))
            records.mostExpensivePerKwh = record(best(priced, value: perKwh, isBetter: >))
        }

        records.biggestCharge = record(best(inside, value: { s in
            guard let kwh = s.energyKwh, kwh > 0 else { return nil }
            return kwh
        }, isBetter: >))

        let withTemperature = inside.filter { $0.outsideTempC != nil }
        if withTemperature.count >= 2 {
            records.coldest = record(best(withTemperature, value: \.outsideTempC, isBetter: <))
            records.warmest = record(best(withTemperature, value: \.outsideTempC, isBetter: >))
        }

        // Laengste Strecke: Vorgaenger mit Kilometerstand desselben Fahrzeugs,
        // der auch vor dem Zeitraum liegen darf.
        var longest: (session: ChargingSession, previous: ChargingSession, km: Double)?
        for (_, list) in withOdometerByVehicle {
            for index in list.indices.dropFirst() {
                let session = list[index]
                guard isInside(session, start, end),
                      let now = session.odometerKm,
                      let before = list[index - 1].odometerKm else { continue }
                let km = Double(now - before)
                guard km > 0 else { continue }
                if let existing = longest {
                    let earlier = (session.startTime, session.id) < (existing.session.startTime, existing.session.id)
                    guard km > existing.km || (km == existing.km && earlier) else { continue }
                }
                longest = (session, list[index - 1], km)
            }
        }
        if let longest {
            records.longestDistance = record((longest.session, longest.km), previousStart: longest.previous.startTime)
        }

        records.topLocation = top(inside, name: locationName)
        records.topProvider = top(inside, name: providerName)

        if period == .year {
            let withValue = monthly.compactMap { row in
                row.avgConsumptionKwhPer100km.map { Review.MonthRecord(month: row.month, value: $0) }
            }
            if withValue.count >= 2 {
                var lowest = withValue[0], highest = withValue[0]
                for row in withValue.dropFirst() {
                    if row.value < lowest.value { lowest = row }
                    if row.value > highest.value { highest = row }
                }
                records.lowestConsumptionMonth = lowest
                records.highestConsumptionMonth = highest
            }
        }

        // MARK: Verteilung

        let acKwh = inside.filter { $0.chargingType == .ac }.reduce(0.0) { $0 + ($1.energyKwh ?? 0) }
        let dcKwh = inside.filter { $0.chargingType == .dc }.reduce(0.0) { $0 + ($1.energyKwh ?? 0) }
        let typed = acKwh + dcKwh
        let split = Review.Split(
            acKwh: acKwh,
            dcKwh: dcKwh,
            acSharePct: typed > 0 ? acKwh / typed * 100 : nil,
            dcSharePct: typed > 0 ? dcKwh / typed * 100 : nil,
            byPlace: LocalStatsCalculator.placeStats(
                sessions: inside,
                providers: basis.providers,
                unallocatedFees: unallocated(start, end),
                cost: cost
            )
        )

        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        return Review(
            period: period,
            year: year,
            month: periodMonth,
            startDate: start,
            endDate: lastDay,
            vehicleId: vehicleId,
            totals: current,
            previous: previousTotals.sessions > 0 ? previousTotals : nil,
            savings: savings,
            records: records,
            split: split,
            monthly: monthly
        )
    }

    /// Jahre, fuer die es Ladevorgaenge gibt, plus das laufende - neueste zuerst.
    static func availableYears(sessions: [ChargingSession], now: Date = Date()) -> [Int] {
        var years = Set(sessions.map { calendar.component(.year, from: $0.startTime) })
        years.insert(calendar.component(.year, from: now))
        return years.sorted(by: >)
    }

    // MARK: - Hilfen

    /// Erster Vorgang (in der uebergebenen Reihenfolge) mit dem besten Wert -
    /// bei Gleichstand gewinnt also der fruehere.
    private static func best(
        _ sessions: [ChargingSession],
        value: (ChargingSession) -> Double?,
        isBetter: (Double, Double) -> Bool
    ) -> (ChargingSession, Double)? {
        var result: (ChargingSession, Double)?
        for session in sessions {
            guard let v = value(session) else { continue }
            if let current = result, !isBetter(v, current.1) { continue }
            result = (session, v)
        }
        return result
    }

    /// Meiste Vorgaenge, bei Gleichstand mehr kWh, dann alphabetisch.
    /// Vorgaenge ohne Namen zaehlen nicht.
    private static func top(_ sessions: [ChargingSession], name: (ChargingSession) -> String?) -> Review.NamedRecord? {
        var counts: [String: Int] = [:]
        var kwh: [String: Double] = [:]
        for session in sessions {
            guard let key = name(session) else { continue }
            counts[key, default: 0] += 1
            kwh[key, default: 0] += session.energyKwh ?? 0
        }
        let winner = counts.keys.min { a, b in
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            let ka = kwh[a] ?? 0, kb = kwh[b] ?? 0
            if ka != kb { return ka > kb }
            return a < b
        }
        guard let winner else { return nil }
        return Review.NamedRecord(name: winner, sessions: counts[winner] ?? 0, kwh: kwh[winner] ?? 0)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
