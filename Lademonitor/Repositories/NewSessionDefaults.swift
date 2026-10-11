import Foundation

/// Vorbelegung eines neuen Ladevorgangs - gemeinsam fuer das Formular und den
/// Kurzbefehl "Ladevorgang erfassen", damit beide dasselbe anlegen.
enum NewSessionDefaults {
    static let chargingType: ChargingType = .ac
    static let energyMeter: EnergyMeter = .charger

    /// Erstes aktives Fahrzeug, sonst das erste (Reihenfolge wie geladen,
    /// also nach Anlagedatum).
    static func vehicleId(in vehicles: [Vehicle]) -> String? {
        (vehicles.first { $0.isActive } ?? vehicles.first)?.id
    }

    /// Preis je kWh aus dem Preis-Gedaechtnis des Anbieters.
    static func suggestedPricePerKwh(provider: Provider?, chargingType: ChargingType) -> Double? {
        guard let provider else { return nil }
        return chargingType == .dc ? provider.lastPriceDcPerKwh : provider.lastPriceAcPerKwh
    }
}
