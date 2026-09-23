import Foundation

/// Rechnung hinter "Lohnt sich der Tarif?" (Reiter Tools).
///
/// Bewusst nur in den Apps, ohne Server: es ist eine Vorausrechnung ueber ein
/// paar Schieberegler, die Vorschlagswerte kommen aus der lokalen Kopie und
/// funktionieren damit auch im Local-Only-Modus. Den RUECKBLICK (was hat ein
/// Abo tatsaechlich gekostet) liefert schon die Gebuehrenumlage
/// (LocalFeeAllocator, `feeShare`).
///
/// Android hat dieselbe Rechnung in `TariffCalculator.kt` - Aenderungen an den
/// Regeln hier dort mitziehen.
enum TariffCalculator {
    /// Durchschnittliche Monatslaenge fuer "km pro Tag -> km pro Monat".
    static let daysPerMonth = 30.44
    /// Zeitfenster der Vorschlaege: km und Anteil aus den letzten 90 Tagen,
    /// Verbrauch und Vergleichspreis aus dem letzten Jahr (die schwanken mit
    /// der Jahreszeit, ein Quartal waere einseitig).
    static let recentDays = 90
    static let yearDays = 365
    /// Unter zwei Wochen Abstand zwischen zwei Kilometerstaenden ist eine
    /// Hochrechnung auf den Monat reine Zufallszahl.
    static let minSpanDays = 14.0

    struct Input {
        var tariffPricePerKwh: Double
        var monthlyFee: Double
        /// Anteil der gefahrenen Energie, der beim Tarif geladen wird (0...100).
        var sharePct: Double
        var kmPerMonth: Double
        var consumptionKwhPer100km: Double
        /// Preis je kWh ohne diesen Tarif; nil = kein Vergleich moeglich.
        var comparisonPricePerKwh: Double?
    }

    enum Verdict {
        case cheaper, moreExpensive, equal, unknown
    }

    struct Result {
        /// kWh im Monat, die beim Tarif geladen werden.
        let kwhPerMonth: Double
        /// nil, wenn keine einzige kWh beim Tarif geladen wird.
        let effectivePricePerKwh: Double?
        /// Grundgebuehr je geladene kWh, der Aufschlag auf den Tarifpreis.
        let feePerKwh: Double?
        let costWithTariff: Double
        let costWithoutTariff: Double?
        /// Positiv = mit Tarif guenstiger.
        let savingsPerMonth: Double?
        /// kWh bzw. km im Monat, ab denen der Tarif guenstiger ist. nil, wenn es
        /// keinen Vergleichspreis gibt oder der Tarif nie guenstiger wird.
        let breakEvenKwh: Double?
        let breakEvenKm: Double?
        /// Der Tarifpreis liegt nicht unter dem Vergleichspreis - dann holt die
        /// Grundgebuehr sich bei keiner Fahrleistung wieder herein.
        let neverPaysOff: Bool
        let verdict: Verdict
    }

    static func compute(_ input: Input) -> Result {
        let share = min(max(input.sharePct, 0), 100) / 100
        let kwhPerKm = max(input.consumptionKwhPer100km, 0) / 100
        let kwh = max(input.kmPerMonth, 0) * kwhPerKm * share
        let withTariff = input.monthlyFee + kwh * input.tariffPricePerKwh
        let effective = kwh > 0 ? withTariff / kwh : nil
        let feePerKwh = kwh > 0 ? input.monthlyFee / kwh : nil

        guard let comparison = input.comparisonPricePerKwh else {
            return Result(
                kwhPerMonth: kwh, effectivePricePerKwh: effective, feePerKwh: feePerKwh,
                costWithTariff: withTariff, costWithoutTariff: nil, savingsPerMonth: nil,
                breakEvenKwh: nil, breakEvenKm: nil, neverPaysOff: false, verdict: .unknown
            )
        }

        let withoutTariff = kwh * comparison
        let savings = withoutTariff - withTariff
        let advantage = comparison - input.tariffPricePerKwh
        var breakEvenKwh: Double?
        var breakEvenKm: Double?
        var neverPaysOff = false
        if advantage > 0 {
            let e = input.monthlyFee / advantage
            breakEvenKwh = e
            if kwhPerKm * share > 0 { breakEvenKm = e / (kwhPerKm * share) }
        } else {
            // Ohne Preisvorteil je kWh gleicht nichts die Grundgebuehr aus. Ohne
            // Grundgebuehr und bei gleichem Preis sind beide Wege gleich teuer.
            neverPaysOff = input.monthlyFee > 0 || advantage < 0
        }

        // Unter einem halben Cent ist "guenstiger"/"teurer" Rundungsrauschen.
        let verdict: Verdict = savings > 0.005 ? .cheaper : (savings < -0.005 ? .moreExpensive : .equal)
        return Result(
            kwhPerMonth: kwh, effectivePricePerKwh: effective, feePerKwh: feePerKwh,
            costWithTariff: withTariff, costWithoutTariff: withoutTariff, savingsPerMonth: savings,
            breakEvenKwh: breakEvenKwh, breakEvenKm: breakEvenKm, neverPaysOff: neverPaysOff, verdict: verdict
        )
    }

    // MARK: - Vorschlagswerte

    private static var calendar: Calendar { Calendar.current }

    private static func daysAgo(_ days: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// Ab dem letzten Vorgang VOR `from`, damit das Fenster wirklich die ganze
    /// Spanne abdeckt und nicht erst beim ersten Einstecken darin beginnt.
    private static func window(_ sorted: [ChargingSession], from: Date) -> ArraySlice<ChargingSession> {
        guard let firstInside = sorted.firstIndex(where: { $0.startTime >= from }) else { return [] }
        return sorted[max(firstInside - 1, 0)...]
    }

    /// Gefahrene km im Monat, je Fahrzeug aus dem Kilometerstand hochgerechnet
    /// und ueber die Fahrzeuge summiert (ein Tarif gilt fuers Konto). Nimmt die
    /// letzten 90 Tage, reicht das nicht fuer zwei Wochen Abstand, die ganze
    /// Historie - aber nur fuer Fahrzeuge, die im letzten Jahr ueberhaupt
    /// geladen wurden (ein verkauftes Auto soll nicht mitzaehlen).
    static func suggestedKmPerMonth(sessions: [ChargingSession], now: Date = Date()) -> Double? {
        let recentFrom = daysAgo(recentDays, from: now)
        let activeFrom = daysAgo(yearDays, from: now)
        var total = 0.0
        var found = false
        let withOdometer = sessions.filter { $0.odometerKm != nil && $0.startTime <= now }
        for (_, list) in Dictionary(grouping: withOdometer, by: \.vehicleId) {
            let sorted = list.sorted { $0.startTime < $1.startTime }
            guard let latest = sorted.last, latest.startTime >= activeFrom else { continue }
            for candidate in [window(sorted, from: recentFrom), sorted[...]] {
                guard let first = candidate.first, let last = candidate.last,
                      let a = first.odometerKm, let b = last.odometerKm else { continue }
                let days = last.startTime.timeIntervalSince(first.startTime) / 86_400
                guard days >= minSpanDays, b > a else { continue }
                total += Double(b - a) / days * daysPerMonth
                found = true
                break
            }
        }
        return found ? total : nil
    }

    /// Verbrauch kWh/100 km im letzten Jahr, je Fahrzeug wie das Dashboard
    /// gerechnet (geladene kWh ab dem zweiten Vorgang durch die Strecke,
    /// enthaelt also Ladeverluste - genau die Energie, die man bezahlt) und
    /// ueber alle Fahrzeuge km-gewichtet zusammengefasst.
    static func suggestedConsumption(sessions: [ChargingSession], now: Date = Date()) -> Double? {
        let from = daysAgo(yearDays, from: now)
        var kwh = 0.0
        var km = 0.0
        let withOdometer = sessions.filter { $0.odometerKm != nil && $0.startTime <= now }
        for (_, list) in Dictionary(grouping: withOdometer, by: \.vehicleId) {
            let slice = window(list.sorted { $0.startTime < $1.startTime }, from: from)
            guard let a = slice.first?.odometerKm, let b = slice.last?.odometerKm, b > a else { continue }
            kwh += slice.dropFirst().reduce(0) { $0 + ($1.energyKwh ?? 0) }
            km += Double(b - a)
        }
        guard km > 0, kwh > 0 else { return nil }
        return kwh / km * 100
    }

    /// kWh-Anteil der Ladevorgaenge, auf die `matches` zutrifft, an allen
    /// geladenen kWh. Letzte 90 Tage, ohne Ladungen darin das letzte Jahr.
    static func suggestedSharePct(
        sessions: [ChargingSession],
        now: Date = Date(),
        matches: (ChargingSession) -> Bool
    ) -> Double? {
        for days in [recentDays, yearDays] {
            let from = daysAgo(days, from: now)
            let inRange = sessions.filter { $0.startTime >= from && $0.startTime <= now && ($0.energyKwh ?? 0) > 0 }
            let total = inRange.reduce(0) { $0 + ($1.energyKwh ?? 0) }
            guard total > 0 else { continue }
            let matched = inRange.filter(matches).reduce(0) { $0 + ($1.energyKwh ?? 0) }
            return matched / total * 100
        }
        return nil
    }

    /// Aktive Grundgebuehren eines Anbieters, auf einen Monat umgerechnet
    /// (jaehrlich / 12, einmalig ueber die Laenge ihres Zeitraums). nil, wenn
    /// heute keine gilt.
    static func suggestedMonthlyFee(providerId: String, fees: [ProviderFee], now: Date = Date()) -> Double? {
        let today = calendar.startOfDay(for: now)
        let active = fees.filter { fee in
            guard fee.providerId == providerId, calendar.startOfDay(for: fee.startDate) <= today else { return false }
            if let end = fee.endDate { return calendar.startOfDay(for: end) >= today }
            return true
        }
        guard !active.isEmpty else { return nil }
        return active.reduce(0.0) { sum, fee in
            switch fee.interval {
            case .monthly:
                return sum + fee.amount
            case .yearly:
                return sum + fee.amount / 12
            case .once:
                let end = fee.endDate ?? fee.startDate
                let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: fee.startDate),
                                                    to: calendar.startOfDay(for: end)).day ?? 0) + 1
                return sum + fee.amount / max(Double(days) / daysPerMonth, 1)
            }
        }
    }

    struct PaidPrice {
        let pricePerKwh: Double
        let sessionCount: Int
    }

    /// Nach kWh gewichteter Preis, der wirklich bezahlt wurde: Saeulenpreis
    /// plus Grundgebuehrenanteil, im letzten Jahr, nur Vorgaenge mit Preis und
    /// Energie. Vorgaenge ohne Anbieter zaehlen nie mit - von denen weiss man
    /// nicht, ob sie oeffentlich waren.
    static func paidPrice(
        sessions: [ChargingSession],
        now: Date = Date(),
        matches: (ChargingSession) -> Bool
    ) -> PaidPrice? {
        let from = daysAgo(yearDays, from: now)
        let relevant = sessions.filter {
            $0.startTime >= from && $0.startTime <= now && $0.providerId != nil
                && $0.priceTotal != nil && ($0.energyKwh ?? 0) > 0 && matches($0)
        }
        let kwh = relevant.reduce(0) { $0 + ($1.energyKwh ?? 0) }
        guard kwh > 0 else { return nil }
        let paid = relevant.reduce(0) { $0 + ($1.priceTotal ?? 0) + ($1.feeShare ?? 0) }
        return PaidPrice(pricePerKwh: paid / kwh, sessionCount: relevant.count)
    }

    /// Automatischer Vergleichspreis "ohne Tarif": was an oeffentlichen
    /// Anbietern bezahlt wurde, ohne den gerade betrachteten (dort wurde ja
    /// schon zum Tarifpreis geladen) und nur fuer dieselbe Lade-Art.
    static func automaticComparisonPrice(
        sessions: [ChargingSession],
        excludedProviderIds: Set<String>,
        selectedProviderId: String?,
        chargingType: ChargingType,
        now: Date = Date()
    ) -> PaidPrice? {
        paidPrice(sessions: sessions, now: now) { session in
            guard let providerId = session.providerId else { return false }
            return !excludedProviderIds.contains(providerId)
                && providerId != selectedProviderId
                && session.chargingType == chargingType
        }
    }
}

/// Lokale Einstellungen des Tarifrechners. Bewusst NICHT synchronisiert
/// (Entscheidung 23.09.2026): auf einem zweiten Geraet waehlt man die privaten
/// Anbieter neu ab. Gespeichert werden die ABGEWAEHLTEN Anbieter, damit neue
/// Anbieter automatisch als oeffentlich zaehlen.
enum TariffCalculatorSettings {
    private static let excludedKey = "tariffCalculator.excludedProviderIds"

    /// Roh gespeicherte IDs. Ein Anbieter kann hier noch unter seiner lokalen
    /// UUID stehen, obwohl er inzwischen eine Server-ID hat - AppRepository
    /// bildet sie deshalb vor der Verwendung ab (tariffBasis()).
    static var storedExcludedProviderIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: excludedKey) ?? [])
    }

    static func setExcluded(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: excludedKey)
    }
}
