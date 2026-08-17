import Foundation

/// Lokaler Port von routers/stats.py (Server), fuer den Local-Only-Modus. Reihenfolge/
/// Rundung/Vorzeichenkonventionen bewusst identisch gehalten, damit Zahlen beim
/// spaeteren Wechsel in den Server-Modus (Schritt 2) nicht scheinbar "springen".
enum LocalStatsCalculator {
    static func compute(sessions: [ChargingSession], vehicles: [Vehicle], providers: [Provider]) -> StatsSummary {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }

        let totalSessions = sorted.count
        let totalKwh = round2(sorted.reduce(0) { $0 + ($1.energyKwh ?? 0) })
        let totalCost = round2(sorted.reduce(0) { $0 + ($1.priceTotal ?? 0) })
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
                let costInRange = withOdo.dropFirst().reduce(0) { $0 + ($1.priceTotal ?? 0) }
                pricePer100km = round2(costInRange / Double(kmDriven) * 100)
            }
        }

        // Anbieter-Aufteilung: Sessions ohne provider_id -> "Ohne Anbieter", damit die
        // Summen vollstaendig bleiben (siehe stats.py).
        var providerKwh: [String: Double] = [:]
        var providerCost: [String: Double] = [:]
        for session in sorted {
            let name = providers.first { $0.id == session.providerId }?.name ?? "Ohne Anbieter"
            providerKwh[name, default: 0] += session.energyKwh ?? 0
            providerCost[name, default: 0] += session.priceTotal ?? 0
        }
        let byProvider = providerKwh.keys
            .sorted { providerKwh[$0]! > providerKwh[$1]! }
            .map { name in
                ProviderStat(providerName: name, totalKwh: round2(providerKwh[name]!), totalCost: round2(providerCost[name]!))
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
        var monthlyKwh: [String: Double] = [:]
        var monthlyCount: [String: Int] = [:]
        var monthlyConsumptionNum: [String: Double] = [:]
        var monthlyConsumptionKm: [String: Double] = [:]
        for session in sorted {
            let key = monthFormatter.string(from: session.startTime)
            monthlyCost[key, default: 0] += session.priceTotal ?? 0
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
                    : nil
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
            monthly: monthly
        )
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
}
