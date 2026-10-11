import Foundation

/// Erstattungsbericht fuer den Dienstwagen, 1:1 nach
/// `reimbursement.py::build_report` im Server (tests/test_reimbursement.py
/// haelt die Regeln fest - Aenderungen dort hier mitziehen):
///
/// - Nur Vorgaenge DIESES Fahrzeugs, deren Anbieter auf "Zuhause" steht.
///   "Arbeit", "Unterwegs" und Vorgaenge ohne Anbieter fallen heraus.
/// - Zeitraum ueber den lokalen Kalendertag von `startTime`, beide Enden
///   inklusive, sortiert nach (startTime, id).
/// - Pauschal: Satz mit dem juengsten `validFrom` <= Ladetag, davor keiner
///   (kein Betrag, gezaehlt). Betrag = round2(kWh x Satz), ohne kWh keiner.
/// - Tatsaechlich: `priceTotal`, sonst `pricePerKwh` x kWh, sonst letzter
///   Anbieterpreis der Lade-Art x kWh; auf Wunsch plus Grundgebuehr-Anteil
///   (`feeShare`, round2). Betrag = round2(Preis + Anteil), Satz =
///   round4(Betrag / kWh).
/// - Summen sind die Summe der gerundeten Betraege.
///
/// Erwartet Ladevorgaenge mit vereinheitlichter Fahrzeug- und Anbieter-ID
/// und bereits umgelegtem `feeShare` (AppRepository.reimbursementBasis).
enum LocalReimbursementCalculator {
    private static var calendar: Calendar { Calendar.current }

    static func report(
        vehicle: Vehicle,
        sessions: [ChargingSession],
        providers: [Provider],
        rates: [ReimbursementRate],
        from: Date,
        to: Date
    ) -> ReimbursementReport {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        let mode = vehicle.reimbursementModeValue
        let includeFees = (vehicle.reimbursementIncludeFees ?? false) && mode == .actual
        let providersById = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let vehicleRates = rates.filter { $0.vehicleId == vehicle.id }

        let selected = sessions
            .filter { session in
                guard session.vehicleId == vehicle.id,
                      let providerId = session.providerId,
                      let provider = providersById[providerId],
                      provider.place == .home else { return false }
                let day = calendar.startOfDay(for: session.startTime)
                return fromDay <= day && day <= toDay
            }
            .sorted { a, b in
                a.startTime != b.startTime ? a.startTime < b.startTime : a.id < b.id
            }

        var rows: [ReimbursementRow] = []
        var monthOrder: [String] = []
        var monthSums: [String: (sessions: Int, kwh: Double, est: Double, amount: Double)] = [:]

        for session in selected {
            let provider = session.providerId.flatMap { providersById[$0] }
            let source = kwhSource(session, provider: provider)
            let kwh = session.energyKwh
            let fee = includeFees ? round2(session.feeShare ?? 0) : 0
            let rate: Double?
            let amount: Double?
            switch mode {
            case .flat:
                rate = rateAt(vehicleRates, day: calendar.startOfDay(for: session.startTime))
                if let rate, let kwh {
                    amount = round2(kwh * rate)
                } else {
                    amount = nil
                }
            case .actual:
                if let price = actualPrice(session, provider: provider) {
                    amount = round2(price + fee)
                } else {
                    amount = nil
                }
                if let amount, let kwh, kwh != 0 {
                    rate = round4(amount / kwh)
                } else {
                    rate = nil
                }
            }
            rows.append(ReimbursementRow(
                sessionId: session.id,
                startTime: session.startTime,
                energyKwh: kwh,
                kwhSource: source,
                odometerKm: session.odometerKm,
                ratePerKwh: rate,
                feeShare: amount != nil ? fee : 0,
                amount: amount
            ))

            let key = monthKey(session.startTime)
            var sums = monthSums[key] ?? (sessions: 0, kwh: 0, est: 0, amount: 0)
            if monthSums[key] == nil { monthOrder.append(key) }
            sums.sessions += 1
            sums.kwh += kwh ?? 0
            if source == .estimated { sums.est += kwh ?? 0 }
            sums.amount += amount ?? 0
            monthSums[key] = sums
        }

        let months = monthOrder.compactMap { key -> ReimbursementMonth? in
            guard let sums = monthSums[key] else { return nil }
            return ReimbursementMonth(
                month: key,
                sessions: sums.sessions,
                energyKwh: round2(sums.kwh),
                estimatedKwh: round2(sums.est),
                amount: round2(sums.amount)
            )
        }
        let estimatedRows = rows.filter { $0.kwhSource == .estimated }

        return ReimbursementReport(
            vehicleId: vehicle.id,
            vehicleName: vehicle.name,
            licensePlate: vehicle.licensePlate,
            employeeName: vehicle.employeeName,
            employeeNumber: vehicle.employeeNumber,
            mode: mode,
            includeFees: includeFees,
            dateFrom: fromDay,
            dateTo: toDay,
            rows: rows,
            months: months,
            totalKwh: round2(rows.reduce(0) { $0 + ($1.energyKwh ?? 0) }),
            estimatedKwh: round2(estimatedRows.reduce(0) { $0 + ($1.energyKwh ?? 0) }),
            estimatedSessions: estimatedRows.count,
            missingAmountSessions: rows.filter { $0.amount == nil }.count,
            totalAmount: round2(rows.reduce(0) { $0 + ($1.amount ?? 0) })
        )
    }

    /// Geschaetzt schlaegt den Messort; sonst Vorgang, dann Anbieter, dann
    /// Ladesaeule - wie `reimbursement.kwh_source`.
    static func kwhSource(_ session: ChargingSession, provider: Provider?) -> ReimbursementKwhSource {
        if session.energyIsEstimated { return .estimated }
        let meter = EnergyMeter.effective(override: session.energyMeter, providerDefault: provider?.energyMeter)
        return meter == .vehicle ? .vehicle : .charger
    }

    /// Satz mit dem juengsten `validFrom` <= `day`, sonst `nil`.
    static func rateAt(_ rates: [ReimbursementRate], day: Date) -> Double? {
        var best: ReimbursementRate?
        var bestStart: Date?
        for rate in rates {
            let start = calendar.startOfDay(for: rate.validFrom)
            if start <= day, bestStart.map({ start >= $0 }) ?? true {
                best = rate
                bestStart = start
            }
        }
        return best?.ratePerKwh
    }

    private static func actualPrice(_ session: ChargingSession, provider: Provider?) -> Double? {
        if let total = session.priceTotal { return total }
        guard let kwh = session.energyKwh, kwh != 0 else { return nil }
        if let perKwh = session.pricePerKwh { return perKwh * kwh }
        guard let provider else { return nil }
        let last = session.chargingType == .dc ? provider.lastPriceDcPerKwh : provider.lastPriceAcPerKwh
        return last.map { $0 * kwh }
    }

    /// "YYYY-MM" des lokalen Kalendertags.
    static func monthKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded(.toNearestOrEven) / 100 }
    private static func round4(_ v: Double) -> Double { (v * 10000).rounded(.toNearestOrEven) / 10000 }
}
