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
        for session in sorted {
            let name = providers.first { $0.id == session.providerId }?.name ?? "Ohne Anbieter"
            providerKwh[name, default: 0] += session.energyKwh ?? 0
            providerCost[name, default: 0] += cost(session)
            providerFees[name, default: 0] += session.feeShare ?? 0
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
                ProviderStat(
                    providerName: name,
                    totalKwh: round2(providerKwh[name]!),
                    totalCost: round2(providerCost[name]!),
                    totalFees: round2(providerFees[name] ?? 0)
                )
            }

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
            unallocatedFees: round2(unallocatedSum)
        )
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
}
