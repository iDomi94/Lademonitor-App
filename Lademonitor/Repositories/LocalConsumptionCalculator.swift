import Foundation

/// Lokaler, vereinfachter Port von consumption.py (Server) fuer den Local-Only-Modus.
/// Grundformel wie serverseitig: verbrauchte_energie = energy_kwh(N) - Akkukapazitaet *
/// (socEnd(N) - socEnd(N-1)) / 100, verbrauch = verbrauchte_energie / km_delta * 100.
///
/// Bewusste Vereinfachung ggue. dem Server: die "full_charge_interval"-Kalibrierung
/// (Methode 1, exakte Verteilung ueber ein komplettes Vollladungs-Intervall) ist NICHT
/// portiert - lokal erfasste Vorgaenge fallen fuer diesen Fall auf soc_corrected/naive
/// zurueck statt auf den rechnerisch exakten Intervall-Wert. Relevant nur bei
/// laufenden Vollladungen; bei Sync auf den Server (Schritt 2) wird ohnehin serverseitig
/// neu berechnet, der lokale Wert ist also nur eine Naeherung fuer die Anzeige.
enum LocalConsumptionCalculator {
    struct Result {
        var value: Double?
        var method: String?
        /// km-Delta zum Vorgaenger - nur als Gewicht fuer die monatliche Mittelung
        /// gedacht (siehe LocalStatsCalculator), nicht zur Anzeige.
        var km: Double?
    }

    static func compute(sessions: [ChargingSession], batteryCapacityKwh: Double?) -> [String: Result] {
        let sorted = sessions.sorted { $0.startTime < $1.startTime }
        var result: [String: Result] = [:]

        for (index, session) in sorted.enumerated() {
            guard index > 0 else {
                result[session.id] = Result(value: nil, method: ConsumptionMethod.unavailable.rawValue, km: nil)
                continue
            }
            let previous = sorted[index - 1]
            guard let odometerNow = session.odometerKm,
                  let odometerPrevious = previous.odometerKm,
                  odometerNow > odometerPrevious,
                  let energyKwh = session.energyKwh else {
                result[session.id] = Result(value: nil, method: ConsumptionMethod.unavailable.rawValue, km: nil)
                continue
            }

            let kmDriven = Double(odometerNow - odometerPrevious)
            var consumedEnergy = energyKwh
            let method: ConsumptionMethod
            if let capacity = batteryCapacityKwh, let socEndNow = session.socEnd, let socEndPrevious = previous.socEnd {
                let socDelta = Double(socEndNow - socEndPrevious)
                consumedEnergy = energyKwh - capacity * socDelta / 100
                method = session.energyIsEstimated ? .estimatedEnergy : .socCorrected
            } else {
                method = session.energyIsEstimated ? .estimatedEnergy : .naive
            }

            let value = (consumedEnergy / kmDriven * 100 * 10).rounded() / 10
            result[session.id] = Result(value: value, method: method.rawValue, km: kmDriven)
        }
        return result
    }
}
