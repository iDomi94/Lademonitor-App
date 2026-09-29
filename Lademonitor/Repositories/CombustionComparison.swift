import Foundation

/// Rechnung hinter "Vergleich mit Verbrenner" (Reiter Tools).
///
/// Wie der Tarifrechner bewusst nur in den Apps und ohne Server: die Grundlage
/// (gefahrene km, bezahlter Strom) liegt lokal vor, der Rest sind
/// Annahmen ueber ein Vergleichsfahrzeug, die der Nutzer selbst einstellt. Es
/// gibt kein Modell und keine Schwelle, die zwischen App und Web
/// auseinanderlaufen koennte.
///
/// Android hat dieselbe Rechnung in `CombustionComparison.kt` - Aenderungen
/// hier dort mitziehen.
enum CombustionComparison {
    enum Fuel: String, CaseIterable, Identifiable {
        case petrol, diesel
        var id: Self { self }

        /// Vorschlagswerte fuer ein vergleichbares Fahrzeug (Kompakt-SUV).
        var defaultConsumption: Double { self == .petrol ? 7.0 : 5.8 }
        var defaultPrice: Double { self == .petrol ? 1.75 : 1.65 }
        /// kg CO2 je Liter bei der Verbrennung (Tank-to-Wheel), UBA-Werte.
        /// Die Vorkette (Foerderung, Raffinerie) ist nicht enthalten - beim
        /// Strom dagegen ist sie im Emissionsfaktor schon drin, der Vergleich
        /// faellt also eher zugunsten des Verbrenners aus.
        var co2KgPerLiter: Double { self == .petrol ? 2.37 : 2.65 }
    }

    /// CO2 je kWh im deutschen Strommix (UBA, 2024 rund 0,36 kg). Bei eigenem
    /// Oekostrom- oder PV-Anteil stellt man den Regler herunter.
    static let defaultGridCo2KgPerKwh = 0.36

    /// Was tatsaechlich gefahren und bezahlt wurde. Wie `price_per_100km` im
    /// Dashboard: km aus dem Kilometerstand je Fahrzeug, Kosten und kWh ab dem
    /// zweiten Vorgang mit Kilometerstand (der erste hat die Strecke davor
    /// geladen, die gar nicht mehr im Zeitraum liegt).
    struct Basis {
        let km: Double
        let kwh: Double
        /// Saeulenpreis plus Grundgebuehrenanteil.
        let cost: Double
        let sessionCount: Int
        let from: Date?
        let to: Date?
    }

    static func basis(sessions: [ChargingSession], since: Date?) -> Basis {
        var km = 0.0, kwh = 0.0, cost = 0.0, count = 0
        var from: Date?, to: Date?
        let withOdometer = sessions.filter { $0.odometerKm != nil }
        for (_, list) in Dictionary(grouping: withOdometer, by: \.vehicleId) {
            let sorted = list.sorted { $0.startTime < $1.startTime }
            var slice = sorted[...]
            if let since {
                // Ab dem letzten Vorgang VOR dem Zeitraum als Anker - sonst
                // fehlte die Strecke bis zum ersten Einstecken darin.
                guard let firstInside = sorted.firstIndex(where: { $0.startTime >= since }) else { continue }
                slice = sorted[max(firstInside - 1, 0)...]
            }
            guard let first = slice.first, let last = slice.last,
                  let a = first.odometerKm, let b = last.odometerKm, b > a else { continue }
            km += Double(b - a)
            for s in slice.dropFirst() {
                kwh += s.energyKwh ?? 0
                cost += (s.priceTotal ?? 0) + (s.feeShare ?? 0)
                count += 1
            }
            from = min(from ?? first.startTime, first.startTime)
            to = max(to ?? last.startTime, last.startTime)
        }
        return Basis(km: km, kwh: kwh, cost: cost, sessionCount: count, from: from, to: to)
    }

    struct Input {
        var litersPer100km: Double
        var pricePerLiter: Double
        var co2KgPerLiter: Double
        var gridCo2KgPerKwh: Double
    }

    struct Result {
        let liters: Double
        let combustionCost: Double
        let electricCost: Double
        /// Positiv = das E-Auto war guenstiger.
        let savings: Double
        let combustionCostPer100km: Double?
        let electricCostPer100km: Double?
        let combustionCo2Kg: Double
        let electricCo2Kg: Double
        /// Treibstoffpreis, bei dem beide gleich teuer gewesen waeren.
        let breakEvenPricePerLiter: Double?
    }

    static func compute(basis: Basis, input: Input) -> Result {
        let liters = basis.km * max(input.litersPer100km, 0) / 100
        let combustion = liters * max(input.pricePerLiter, 0)
        let per100 = { (value: Double) in basis.km > 0 ? value / basis.km * 100 : nil }
        return Result(
            liters: liters,
            combustionCost: combustion,
            electricCost: basis.cost,
            savings: combustion - basis.cost,
            combustionCostPer100km: per100(combustion),
            electricCostPer100km: per100(basis.cost),
            combustionCo2Kg: liters * input.co2KgPerLiter,
            electricCo2Kg: basis.kwh * input.gridCo2KgPerKwh,
            breakEvenPricePerLiter: liters > 0 ? basis.cost / liters : nil
        )
    }
}
