import Foundation

/// Lokaler Port von routers/stats.py (Server), fuer den Local-Only-Modus. Reihenfolge/
/// Rundung/Vorzeichenkonventionen bewusst identisch gehalten, damit Zahlen beim
/// spaeteren Wechsel in den Server-Modus (Schritt 2) nicht scheinbar "springen".
enum LocalStatsCalculator {
    /// `sessions` muessen `feeShare` bereits tragen (LocalDataStore.fetchSessions),
    /// `unallocatedFees` sind die schon nach Fahrzeug und Zeitraum gefilterten
    /// Perioden ohne Ladevorgang (siehe AppRepository.fetchStatsSummary) - wie
    /// in stats.py zaehlen Grundgebuehren in allen Kostenkennzahlen mit.
    /// `sessions` muessen ausserdem `consumptionKwhPer100km`/`consumptionKm`
    /// ueber die ganze Historie tragen (LocalDataStore.fetchSessions);
    /// `history` sind alle Vorgaenge der betrachteten Fahrzeuge OHNE
    /// Zeitraumfilter, fuer den km-Anker vor dem Zeitraum.
    static func compute(
        sessions: [ChargingSession],
        vehicles: [Vehicle],
        providers: [Provider],
        unallocatedFees: [LocalFeeAllocator.Period] = [],
        history: [ChargingSession]? = nil
    ) -> StatsSummary {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }

        func cost(_ s: ChargingSession) -> Double { (s.priceTotal ?? 0) + (s.feeShare ?? 0) }

        let totalSessions = sorted.count
        let totalKwh = round2(sorted.reduce(0) { $0 + ($1.energyKwh ?? 0) })
        let sessionFees: Double = sorted.reduce(0) { $0 + ($1.feeShare ?? 0) }
        let unallocatedSum: Double = unallocatedFees.reduce(0) { $0 + $1.amount }
        let totalFees = sessionFees + unallocatedSum
        let chargerCost: Double = sorted.reduce(0) { $0 + ($1.priceTotal ?? 0) }
        let totalCost = round2(chargerCost + totalFees)
        let avgPrice = totalKwh > 0 ? round4(totalCost / totalKwh) : nil

        let acKwh = sorted.filter { $0.chargingType == .ac }.reduce(0) { $0 + ($1.energyKwh ?? 0) }
        let dcKwh = sorted.filter { $0.chargingType == .dc }.reduce(0) { $0 + ($1.energyKwh ?? 0) }
        let typedKwh = acKwh + dcKwh
        let acShare = typedKwh > 0 ? round1(acKwh / typedKwh * 100) : nil
        let dcShare = typedKwh > 0 ? round1(dcKwh / typedKwh * 100) : nil

        // Sonnenanteil nur ueber die Vorgaenge mit bekanntem Netzbezug (Server
        // ab 0.41.0 bzw. Home Assistant) - Vorgaenge ohne Angabe wuerden den
        // Anteil sonst kuenstlich druecken.
        let shares = sorted.compactMap(\.solarShare)
        let solarShare: SolarShare? = shares.isEmpty ? nil : SolarShare(
            solarKwh: round2(shares.reduce(0) { $0 + $1.solarKwh }),
            gridKwh: round2(shares.reduce(0) { $0 + $1.gridKwh })
        )

        // Verbrauch, Preis je 100 km und km - wie stats.py seit 0.49.1. Vorher:
        // kWh ab dem zweiten Vorgang im Zeitraum / km zwischen erstem und
        // letztem km-Stand. Bei kurzen Zeitraeumen hing das am Akkustand an den
        // Raendern ("Monat bis jetzt", 04.11.2026: zwei Ladungen mit 19,4 und
        // 20,6 kWh/100 km ergaben 29,5). Jetzt das km-gewichtete Mittel der
        // Einzelwerte, die LocalDataStore ueber die GANZE Historie rechnet -
        // also genau die Werte aus der Liste.
        var consumptionNum = 0.0
        var consumptionKmSum = 0.0
        for session in sorted {
            if let value = session.consumptionKwhPer100km, let km = session.consumptionKm, km > 0 {
                consumptionNum += value * km
                consumptionKmSum += km
            }
        }
        let rawConsumption: Double? = consumptionKmSum > 0 ? consumptionNum / consumptionKmSum : nil
        let consumption = rawConsumption.map { round1($0) }
        // Verbrauch x Ø Preis je kWh (inkl. Grundgebuehren) - Kosten / km haette
        // denselben Randfehler.
        let pricePer100km: Double? = rawConsumption.flatMap { c in
            totalKwh > 0 ? round2(c * totalCost / totalKwh) : nil
        }

        // km je Fahrzeug: letzter Stand im Zeitraum minus Anker (letzter Stand
        // VOR dem Zeitraum aus `history`, sonst der erste im Zeitraum), wie
        // stats.py/review.py. Summiert, damit bei mehreren Fahrzeugen nicht
        // Kilometerstaende verschiedener Autos voneinander abgezogen werden.
        var totalKmDriven: Int?
        let firstStart = sorted.first?.startTime
        let inRangeIds = Set(sorted.map(\.id))
        let readingsSource = (history ?? sorted).sorted { $0.startTime < $1.startTime }
        for vehicleId in Set(sorted.map(\.vehicleId)) {
            let readings = readingsSource.filter { $0.vehicleId == vehicleId && $0.odometerKm != nil }
            let inside = readings.filter { inRangeIds.contains($0.id) }
            guard let last = inside.last?.odometerKm, let firstInside = inside.first?.odometerKm else { continue }
            let before = firstStart.map { start in
                readings.filter { $0.startTime < start && !inRangeIds.contains($0.id) }
            } ?? []
            if before.isEmpty && inside.count < 2 { continue }
            let anchor = before.last?.odometerKm ?? firstInside
            totalKmDriven = (totalKmDriven ?? 0) + max(last - anchor, 0)
        }

        // Anbieter-Aufteilung: Sessions ohne provider_id -> "Ohne Anbieter", damit die
        // Summen vollstaendig bleiben (siehe stats.py).
        var providerKwh: [String: Double] = [:]
        var providerCost: [String: Double] = [:]
        var providerFees: [String: Double] = [:]
        var providerCount: [String: Int] = [:]
        var providerUnpriced: [String: Int] = [:]
        // Je Anbieter und Lade-Art: (kWh, Kosten) fuer den Ø Preis je Lade-Art.
        var providerTyped: [String: [ChargingType: (kwh: Double, cost: Double)]] = [:]
        for session in sorted {
            let name = providers.first { $0.id == session.providerId }?.name ?? "Ohne Anbieter"
            providerKwh[name, default: 0] += session.energyKwh ?? 0
            providerCost[name, default: 0] += cost(session)
            providerFees[name, default: 0] += session.feeShare ?? 0
            providerCount[name, default: 0] += 1
            if session.priceTotal == nil { providerUnpriced[name, default: 0] += 1 }
            if let type = session.chargingType {
                let prev = providerTyped[name]?[type] ?? (0, 0)
                providerTyped[name, default: [:]][type] = (prev.kwh + (session.energyKwh ?? 0), prev.cost + cost(session))
            }
        }
        for period in unallocatedFees {
            let name = providers.first { $0.id == period.providerId }?.name ?? "Ohne Anbieter"
            providerKwh[name, default: 0] += 0  // Anbieter auch ohne kWh fuehren
            providerCost[name, default: 0] += period.amount
            providerFees[name, default: 0] += period.amount
        }
        let byProvider = providerKwh.keys
            .sorted { providerKwh[$0]! > providerKwh[$1]! }
            .map { name in
                let ac = providerTyped[name]?[.ac]
                let dc = providerTyped[name]?[.dc]
                return ProviderStat(
                    providerName: name,
                    totalKwh: round2(providerKwh[name]!),
                    totalCost: round2(providerCost[name]!),
                    totalFees: round2(providerFees[name] ?? 0),
                    sessionCount: providerCount[name] ?? 0,
                    sessionsWithoutPrice: providerUnpriced[name] ?? 0,
                    avgPricePerKwh: providerKwh[name]! > 0 ? round4(providerCost[name]! / providerKwh[name]!) : nil,
                    acKwh: ac.map { round2($0.kwh) },
                    acAvgPricePerKwh: ac.flatMap { $0.kwh > 0 ? round4($0.cost / $0.kwh) : nil },
                    dcKwh: dc.map { round2($0.kwh) },
                    dcAvgPricePerKwh: dc.flatMap { $0.kwh > 0 ? round4($0.cost / $0.kwh) : nil }
                )
            }

        let byPlace = placeStats(
            sessions: sorted, providers: providers, unallocatedFees: unallocatedFees, cost: cost
        )

        // Monatlicher Verbrauch: km-gewichtet ueber dieselben Einzelwerte wie oben
        // (aus der ganzen Historie - sonst fehlte dem ersten Vorgang im Zeitraum
        // sein Vorgaenger).

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.timeZone = .current

        var monthlyCost: [String: Double] = [:]
        var monthlyFees: [String: Double] = [:]
        var monthlyKwh: [String: Double] = [:]
        var monthlyCount: [String: Int] = [:]
        var monthlyConsumptionNum: [String: Double] = [:]
        var monthlyConsumptionKm: [String: Double] = [:]
        // Nicht umgelegte Gebuehren im Monat, in dem ihre Periode beginnt.
        for period in unallocatedFees {
            let key = monthFormatter.string(from: period.start)
            monthlyCost[key, default: 0] += period.amount
            monthlyFees[key, default: 0] += period.amount
        }
        for session in sorted {
            let key = monthFormatter.string(from: session.startTime)
            monthlyCost[key, default: 0] += cost(session)
            monthlyFees[key, default: 0] += session.feeShare ?? 0
            monthlyKwh[key, default: 0] += session.energyKwh ?? 0
            monthlyCount[key, default: 0] += 1
            if let value = session.consumptionKwhPer100km, let km = session.consumptionKm, km > 0 {
                monthlyConsumptionNum[key, default: 0] += value * km
                monthlyConsumptionKm[key, default: 0] += km
            }
        }
        let monthly = monthlyCost.keys.sorted(by: >).map { month in
            MonthlyStat(
                month: month,
                totalCost: round2(monthlyCost[month] ?? 0),
                totalKwh: round2(monthlyKwh[month] ?? 0),
                sessionCount: monthlyCount[month] ?? 0,
                avgConsumptionKwhPer100km: (monthlyConsumptionKm[month] ?? 0) > 0
                    ? round1(monthlyConsumptionNum[month]! / monthlyConsumptionKm[month]!)
                    : nil,
                totalFees: round2(monthlyFees[month] ?? 0)
            )
        }

        return StatsSummary(
            totalSessions: totalSessions,
            totalKwh: totalKwh,
            totalCost: totalCost,
            avgPricePerKwh: avgPrice,
            avgConsumptionKwhPer100km: consumption,
            pricePer100km: pricePer100km,
            acSharePct: acShare,
            dcSharePct: dcShare,
            acKwh: round2(acKwh),
            dcKwh: round2(dcKwh),
            totalKmDriven: totalKmDriven,
            byProvider: byProvider,
            monthly: monthly,
            totalFees: round2(totalFees),
            unallocatedFees: round2(unallocatedSum),
            byPlace: byPlace,
            solarShare: solarShare
        )
    }

    /// Zuhause/Arbeit/Unterwegs, gleiche Regeln wie stats.py::build_by_place():
    /// ohne Anbieter zaehlt als unterwegs, nicht umgelegte Gebuehren beim Ort
    /// ihres Anbieters, und leer, solange kein Vorgang Zuhause oder Arbeit ist
    /// - eine Aufteilung "100 % unterwegs" sagt nichts.
    static func placeStats(
        sessions: [ChargingSession],
        providers: [Provider],
        unallocatedFees: [LocalFeeAllocator.Period],
        cost: (ChargingSession) -> Double
    ) -> [PlaceStat] {
        func place(of providerId: String?) -> ChargingPlace {
            providers.first { $0.id == providerId }?.place ?? .public
        }
        var count: [ChargingPlace: Int] = [:]
        var kwh: [ChargingPlace: Double] = [:]
        var total: [ChargingPlace: Double] = [:]
        for session in sessions {
            let p = place(of: session.providerId)
            count[p, default: 0] += 1
            kwh[p, default: 0] += session.energyKwh ?? 0
            total[p, default: 0] += cost(session)
        }
        guard (count[.home] ?? 0) > 0 || (count[.work] ?? 0) > 0 else { return [] }
        for period in unallocatedFees {
            total[place(of: period.providerId), default: 0] += period.amount
        }
        return [ChargingPlace.home, .work, .public].compactMap { p in
            let n = count[p] ?? 0
            let k = kwh[p] ?? 0
            let c = total[p] ?? 0
            guard n > 0 || c > 0 else { return nil }
            return PlaceStat(
                placeRaw: p.rawValue,
                sessionCount: n,
                totalKwh: round2(k),
                totalCost: round2(c),
                avgPricePerKwh: k > 0 ? round4(c / k) : nil
            )
        }
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
}
