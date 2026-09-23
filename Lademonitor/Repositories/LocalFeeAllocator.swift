import Foundation

/// Lokaler Port von fees.py (Server ab 0.27.0): legt die Grundgebuehren/Abos
/// der Anbieter nach kWh auf die Ladevorgaenge um.
///
/// Noetig, weil das Dashboard auch im Server-Modus lokal entsteht
/// (AppRepository.fetchStatsSummary). Die Regeln MUESSEN mit fees.py
/// uebereinstimmen, sonst zeigen App und Web andere Kosten - die Faelle in
/// tests/test_fees.py (Server-Repo) gelten hier genauso:
///
/// - Perioden sind halboffen `[Beginn, naechster Beginn)` und werden immer vom
///   URSPRUENGLICHEN Ankertag aus gerechnet (31.01. -> 28.02. -> 31.03.).
/// - Es zaehlen nur Perioden, die bis heute begonnen haben - dann aber voll.
/// - `endDate` ist inklusive: die Periode, in die es faellt, zaehlt voll, ihre
///   Ladevorgaenge aber nur bis zu diesem Tag.
/// - Zugeordnet wird ueber den Kalendertag von `startTime`.
/// - Umgelegt nach kWh; haben alle Vorgaenge keine Energie, gleichmaessig.
///   Auf den Cent gerundet, der Rest landet beim ersten groessten Vorgang.
enum LocalFeeAllocator {
    struct Period {
        let feeId: String
        let providerId: String
        /// Inklusive, lokale Mitternacht.
        let start: Date
        /// Exklusive, lokale Mitternacht.
        let end: Date
        let amount: Double
    }

    struct Allocation {
        /// Ladevorgang-ID -> umgelegter Anteil in EUR.
        var shares: [String: Double] = [:]
        /// Perioden ohne einen einzigen Ladevorgang des Anbieters. Bezahlt sind
        /// sie trotzdem, die Statistik zaehlt sie deshalb mit.
        var unallocated: [Period] = []
    }

    private static var calendar: Calendar { Calendar.current }

    /// Monate addieren, immer vom Ankertag aus. `Calendar` kuerzt dabei selbst
    /// aufs Monatsende (31.01. + 1 Monat = 28.02.), wie `add_months()` im Server.
    static func addMonths(_ anchor: Date, _ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }

    private static func nextDay(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    /// Alle Perioden einer Gebuehr, die bis `until` (einschliesslich) begonnen haben.
    static func periods(of fee: ProviderFee, until: Date = Date()) -> [Period] {
        let start = calendar.startOfDay(for: fee.startDate)
        let endIncl = fee.endDate.map { calendar.startOfDay(for: $0) }
        let untilDay = calendar.startOfDay(for: until)
        if start > untilDay { return [] }

        if fee.interval == .once {
            let last = endIncl.flatMap { $0 >= start ? $0 : nil } ?? start
            return [Period(feeId: fee.id, providerId: fee.providerId, start: start, end: nextDay(last), amount: fee.amount)]
        }

        let step = fee.interval == .yearly ? 12 : 1
        var result: [Period] = []
        var k = 0
        while true {
            let pStart = addMonths(start, k * step)
            if pStart > untilDay { break }
            if let endIncl, pStart > endIncl { break }
            var pEnd = addMonths(start, (k + 1) * step)
            if let endIncl { pEnd = min(pEnd, nextDay(endIncl)) }
            result.append(Period(feeId: fee.id, providerId: fee.providerId, start: pStart, end: pEnd, amount: fee.amount))
            k += 1
        }
        return result
    }

    /// Was die Gebuehr bis heute insgesamt gekostet hat.
    static func chargedToDate(_ fee: ProviderFee, until: Date = Date()) -> Double {
        round2(periods(of: fee, until: until).reduce(0) { $0 + $1.amount })
    }

    private static func split(_ amount: Double, over sessions: [ChargingSession]) -> [(String, Double)] {
        var weights = sessions.map { max($0.energyKwh ?? 0, 0) }
        var total = weights.reduce(0, +)
        if total <= 0 {
            weights = Array(repeating: 1, count: sessions.count)
            total = Double(sessions.count)
        }
        var shares = weights.map { round2(amount * $0 / total) }
        let remainder = round2(amount - shares.reduce(0, +))
        if remainder != 0 {
            // Erster Index mit dem groessten Gewicht, wie Pythons max().
            var biggest = 0
            for i in weights.indices where weights[i] > weights[biggest] { biggest = i }
            shares[biggest] = round2(shares[biggest] + remainder)
        }
        return zip(sessions.map(\.id), shares).map { ($0, $1) }
    }

    /// Legt alle Perioden aller Gebuehren auf die Ladevorgaenge um.
    ///
    /// `sessions` muss die VOLLSTAENDIGE Menge sein (alle Fahrzeuge, kein
    /// Datumsfilter) - ein Filter darf erst nach der Umlage greifen, sonst
    /// bekaeme der letzte Vorgang vor der Filtergrenze die ganze Gebuehr.
    /// `providerId` muss in Gebuehren und Vorgaengen dieselbe Form haben (siehe
    /// LocalDataStore.feeAllocation(), das beide vereinheitlicht).
    static func allocate(fees: [ProviderFee], sessions: [ChargingSession], until: Date = Date()) -> Allocation {
        var byProvider: [String: [ChargingSession]] = [:]
        for session in sessions {
            if let providerId = session.providerId { byProvider[providerId, default: []].append(session) }
        }
        // Feste Reihenfolge wie im Server, damit der Rundungsrest bei gleich
        // grossen Vorgaengen immer beim fruehesten landet.
        for key in byProvider.keys {
            byProvider[key]?.sort { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        }

        var result = Allocation()
        for fee in fees {
            let candidates = byProvider[fee.providerId] ?? []
            for period in periods(of: fee, until: until) {
                let inPeriod = candidates.filter {
                    let day = calendar.startOfDay(for: $0.startTime)
                    return period.start <= day && day < period.end
                }
                if inPeriod.isEmpty {
                    result.unallocated.append(period)
                    continue
                }
                for (sessionId, share) in split(period.amount, over: inPeriod) {
                    result.shares[sessionId] = round2((result.shares[sessionId] ?? 0) + share)
                }
            }
        }
        return result
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded(.toNearestOrEven) / 100 }
}
