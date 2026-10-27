import Foundation

/// Lokaler Port von routers/stats.py (Server), fuer den Local-Only-Modus. Reihenfolge/
/// Rundung/Vorzeichenkonventionen bewusst identisch gehalten, damit Zahlen beim
/// spaeteren Wechsel in den Server-Modus (Schritt 2) nicht scheinbar "springen".
enum LocalStatsCalculator {
    /// `sessions` muessen `feeShare` bereits tragen (LocalDataStore.fetchSessions),
    /// `unallocatedFees` sind die schon nach Fahrzeug und Zeitraum gefilterten
    /// Perioden ohne Ladevorgang (siehe AppRepository.fetchStatsSummary) - wie
    /// in stats.py zaehlen Grundgebuehren in allen Kostenkennzahlen mit.
    static func compute(
        sessions: [ChargingSession],
        vehicles: [Vehicle],
        providers: [Provider],
        unallocatedFees: [LocalFeeAllocator.Period] = []
    ) -> StatsSummary {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }
        let calendar = Calendar.current

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

        let withOdo = sorted.filter { $0.odometerKm != nil }
        var consumption: Double?
        var pricePer100km: Double?
        var totalKmDriven: Int?
        if withOdo.count >= 2, let first = withOdo.first?.odometerKm, let last = withOdo.last?.odometerKm {
            let kmDriven = last - first
            totalKmDriven = kmDriven
            if kmDriven > 0 {
                let kwhInRange = withOdo.dropFirst().reduce(0) { $0 + ($1.energyKwh ?? 0) }
                consumption = round1(kwhInRange / Double(kmDriven) * 100)
                // Wie die kWh ab dem zweiten Vorgang, dazu nur die nicht umgelegten
                // Gebuehren, deren Periode in genau diesem Zeitraum beginnt.
                let firstDay = calendar.startOfDay(for: withOdo.first!.startTime)
                let lastDay = calendar.startOfDay(for: withOdo.last!.startTime)
                let sessionCost: Double = withOdo.dropFirst().reduce(0) { $0 + cost($1) }
                let feesInRange: Double = unallocatedFees
                    .filter { firstDay < $0.start && $0.start <= lastDay }
                    .reduce(0) { $0 + $1.amount }
                pricePer100km = round2((sessionCost + feesInRange) / Double(kmDriven) * 100)
            }
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

        // Monatlicher Verbrauch: km-gewichtet gemittelt ueber die Consumption-Ergebnisse
        // pro Fahrzeug (dieselbe Fallback-Kette wie pro Ladevorgang).
        var consumptionByVehicle: [String: LocalConsumptionCalculator.Result] = [:]
        for vehicle in vehicles {
            let vehicleSessions = sorted.filter { $0.vehicleId == vehicle.id }
            consumptionByVehicle.merge(
                LocalConsumptionCalculator.compute(sessions: vehicleSessions, batteryCapacityKwh: vehicle.batteryCapacityKwh)
            ) { _, new in new }
        }

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
            if let result = consumptionByVehicle[session.id], let value = result.value, let km = result.km, km > 0 {
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
            byPlace: byPlace
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
