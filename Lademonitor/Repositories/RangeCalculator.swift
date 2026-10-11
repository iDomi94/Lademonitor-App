import Foundation

/// Rechnung hinter dem "Reichweitenrechner" (Reiter Tools).
///
/// Bewusst nur ein Dreisatz plus Interpolation: das Kurvenmodell (Gerade oder
/// Knick, Ladeverlust herausgerechnet) kennt allein der Server
/// (`range_estimate.py`) und liefert es fertig als `TempRange.curve`, ein Wert
/// je ganzem Grad. Die App interpoliert nur dazwischen - so koennen App und
/// Web nicht auseinanderlaufen.
///
/// Die Android-App rechnet denselben Reichweitenrechner - Aenderungen hier
/// dort mitziehen.
enum RangeCalculator {
    /// Richtwert, wenn es weder Kurve noch eigenen Durchschnitt gibt.
    static let fallbackConsumption = 18.0
    /// Akkugroesse, falls am Fahrzeug keine hinterlegt ist.
    static let fallbackCapacityKwh = 77.0

    /// Verbrauch ab Akku bei `tempC`, linear zwischen den beiden benachbarten
    /// Stuetzstellen. Ausserhalb der Kurve gilt ihr Randwert - die Kurve
    /// selbst reicht schon bis -20/40 Grad, fehlende Raender waren unplausibel.
    static func consumption(at tempC: Double, curve: [TempCurveVertex]) -> Double? {
        let sorted = curve.sorted { $0.tempC < $1.tempC }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if tempC <= first.tempC { return first.consumption }
        if tempC >= last.tempC { return last.consumption }
        for (a, b) in zip(sorted, sorted.dropFirst()) where tempC >= a.tempC && tempC <= b.tempC {
            let span = b.tempC - a.tempC
            guard span > 0 else { return a.consumption }
            let f = (tempC - a.tempC) / span
            return a.consumption + (b.consumption - a.consumption) * f
        }
        return last.consumption
    }

    /// Energie aus dem Akku zwischen zwei Ladestaenden.
    static func usableKwh(capacityKwh: Double, socStart: Double, socEnd: Double) -> Double {
        max(capacityKwh * (socStart - socEnd) / 100, 0)
    }

    /// Reichweite in km: Energie aus dem Akku / Verbrauch je 100 km.
    static func rangeKm(capacityKwh: Double, socStart: Double, socEnd: Double,
                        consumptionKwhPer100km: Double) -> Double? {
        guard consumptionKwhPer100km > 0 else { return nil }
        return usableKwh(capacityKwh: capacityKwh, socStart: socStart, socEnd: socEnd)
            / consumptionKwhPer100km * 100
    }
}
