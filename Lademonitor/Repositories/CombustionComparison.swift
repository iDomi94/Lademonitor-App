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
        /// Zusaetzlich fuer Foerderung, Transport und Raffinerie (Well-to-Tank,
        /// grob 20 % obendrauf). Nur in der Lebenszyklus-Rechnung - dort steckt
        /// auch beim Strom die ganze Vorkette im Emissionsfaktor.
        var upstreamCo2KgPerLiter: Double { self == .petrol ? 0.52 : 0.60 }
    }

    /// Lebenszyklus: CO2 aus der Herstellung. Das Fahrzeug ohne Akku zaehlt
    /// fuer beide gleich (rund 7 t fuer einen Kompakt-SUV), beim E-Auto kommt
    /// der Akku dazu. Fuer ihn nennen Studien 60 bis 100 kg je kWh, je nach
    /// Zellchemie und Strommix des Werks.
    static let vehicleProductionCo2Kg = 7_000.0
    static let defaultBatteryCo2KgPerKwh = 75.0
    static let defaultBatteryKwh = 77.0
    static let defaultLifetimeKm = 200_000.0
    /// Richtwert fuer den Verbrauch, falls die eigenen Daten keinen hergeben.
    static let fallbackKwhPer100km = 18.0

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
        /// Nur fuer den Lebenszyklus, siehe `Fuel.upstreamCo2KgPerLiter`.
        var upstreamCo2KgPerLiter: Double
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

    struct LifecycleInput {
        var lifetimeKm: Double
        var batteryKwh: Double
        var batteryCo2KgPerKwh: Double
    }

    struct Lifecycle {
        let electricProductionCo2Kg: Double
        let combustionProductionCo2Kg: Double
        let electricTotalCo2Kg: Double
        let combustionTotalCo2Kg: Double
        let electricCo2Per100km: Double
        let combustionCo2Per100km: Double
        let electricEnergyCost: Double
        let combustionEnergyCost: Double
        /// Ab dieser Laufleistung hat das E-Auto seinen Herstellungs-Rucksack
        /// wieder eingeholt. nil, wenn es im Betrieb nicht sauberer ist.
        let co2BreakEvenKm: Double?
    }

    /// Verbrauch des E-Autos je km aus den eigenen Daten (geladene kWh, also
    /// inkl. Ladeverlusten), sonst ein Richtwert.
    static func kwhPerKm(_ basis: Basis) -> Double {
        basis.km > 0 && basis.kwh > 0 ? basis.kwh / basis.km : fallbackKwhPer100km / 100
    }

    /// Stromkosten je km aus den eigenen Daten, sonst nil.
    static func costPerKm(_ basis: Basis) -> Double? {
        basis.km > 0 ? basis.cost / basis.km : nil
    }

    static func lifecycle(basis: Basis, input: Input, lifecycle: LifecycleInput) -> Lifecycle {
        let km = max(lifecycle.lifetimeKm, 1)
        let litersPerKm = max(input.litersPer100km, 0) / 100
        let electricPerKm = kwhPerKm(basis) * input.gridCo2KgPerKwh
        let combustionPerKm = litersPerKm * (input.co2KgPerLiter + input.upstreamCo2KgPerLiter)
        let electricProduction = vehicleProductionCo2Kg + max(lifecycle.batteryKwh, 0) * max(lifecycle.batteryCo2KgPerKwh, 0)
        let combustionProduction = vehicleProductionCo2Kg
        let electricTotal = electricProduction + electricPerKm * km
        let combustionTotal = combustionProduction + combustionPerKm * km
        let advantage = combustionPerKm - electricPerKm
        return Lifecycle(
            electricProductionCo2Kg: electricProduction,
            combustionProductionCo2Kg: combustionProduction,
            electricTotalCo2Kg: electricTotal,
            combustionTotalCo2Kg: combustionTotal,
            electricCo2Per100km: electricTotal / km * 100,
            combustionCo2Per100km: combustionTotal / km * 100,
            electricEnergyCost: (costPerKm(basis) ?? 0) * km,
            combustionEnergyCost: litersPerKm * max(input.pricePerLiter, 0) * km,
            co2BreakEvenKm: advantage > 0 ? (electricProduction - combustionProduction) / advantage : nil
        )
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
