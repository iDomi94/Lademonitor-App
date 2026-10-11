import Foundation
import Combine

/// Haelt das Vergleichsfahrzeug (siehe `ComparisonVehicle`) auf dem Geraet,
/// in UserDefaults samt Dirty-Flag - bewusst kein SwiftData-Modell: es ist
/// genau ein Datensatz je Nutzer, ohne Referenzen und ohne Grabstein.
///
/// Im Server-Modus gleicht der SyncService es ab (`syncComparisonVehicle`):
/// dirty -> PUT, danach Flag weg; sonst GET und lokal uebernehmen. Im
/// Local-Only-Modus bleibt es einfach hier.
@MainActor
final class ComparisonVehicleStore: ObservableObject {
    static let shared = ComparisonVehicleStore()

    private enum Key {
        static let fuel = "comparisonVehicle.fuel"
        static let consumption = "comparisonVehicle.consumption"
        static let price = "comparisonVehicle.price"
        static let gridCo2 = "comparisonVehicle.gridCo2"
        static let configured = "comparisonVehicle.configured"
        static let dirty = "comparisonVehicle.dirty"
    }

    /// Immer mit gesetztem `configured` (true/false).
    @Published private(set) var vehicle: ComparisonVehicle
    /// Lokal geaendert und noch nicht zum Server hochgeladen.
    @Published private(set) var isDirty: Bool

    private init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Key.configured) || defaults.object(forKey: Key.fuel) != nil {
            let fuel = CombustionComparison.Fuel(rawValue: defaults.string(forKey: Key.fuel) ?? "") ?? .petrol
            vehicle = ComparisonVehicle(
                fuelType: fuel.rawValue,
                consumptionLPer100km: defaults.object(forKey: Key.consumption) as? Double ?? fuel.defaultConsumption,
                fuelPricePerL: defaults.object(forKey: Key.price) as? Double ?? fuel.defaultPrice,
                gridCo2KgPerKwh: defaults.object(forKey: Key.gridCo2) as? Double ?? CombustionComparison.defaultGridCo2KgPerKwh,
                configured: defaults.bool(forKey: Key.configured)
            )
        } else if let legacyFuel = defaults.string(forKey: "combustion.fuel") {
            // Bis 1.7.0 hielt das Verbrenner-Tool seine Regler selbst - die
            // zuletzt eingestellten Werte als Startwert uebernehmen, aber noch
            // nicht als "eingerichtet" (gespeichert hat sie niemand bewusst).
            let fuel = CombustionComparison.Fuel(rawValue: legacyFuel) ?? .petrol
            vehicle = ComparisonVehicle(
                fuelType: fuel.rawValue,
                consumptionLPer100km: defaults.object(forKey: "combustion.consumption") as? Double ?? fuel.defaultConsumption,
                fuelPricePerL: defaults.object(forKey: "combustion.price") as? Double ?? fuel.defaultPrice,
                gridCo2KgPerKwh: defaults.object(forKey: "combustion.gridCo2") as? Double ?? CombustionComparison.defaultGridCo2KgPerKwh,
                configured: false
            )
        } else {
            vehicle = .defaults()
        }
        isDirty = defaults.bool(forKey: Key.dirty)
    }

    var isConfigured: Bool { vehicle.configured ?? false }

    /// Vom Nutzer gespeichert (Einstellungen oder Verbrenner-Tool): gilt ab
    /// jetzt als eingerichtet und geht beim naechsten Sync hoch.
    func save(_ newValue: ComparisonVehicle) {
        var stored = newValue
        stored.configured = true
        write(stored, dirty: true)
    }

    /// Stand vom Server uebernehmen (nur, wenn lokal nichts offen ist).
    func applyFromServer(_ server: ComparisonVehicle) {
        var stored = server
        stored.configured = server.configured ?? false
        write(stored, dirty: false)
    }

    /// Nach erfolgreichem PUT.
    func markSynced() {
        isDirty = false
        UserDefaults.standard.set(false, forKey: Key.dirty)
    }

    /// Beim Wechsel des Server-Kontos: ein eingerichtetes Fahrzeug soll ins
    /// neue Konto hochgehen wie die uebrigen lokalen Daten.
    func markDirtyIfConfigured() {
        guard isConfigured else { return }
        isDirty = true
        UserDefaults.standard.set(true, forKey: Key.dirty)
    }

    private func write(_ value: ComparisonVehicle, dirty: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(value.fuelType, forKey: Key.fuel)
        defaults.set(value.consumptionLPer100km, forKey: Key.consumption)
        defaults.set(value.fuelPricePerL, forKey: Key.price)
        defaults.set(value.gridCo2KgPerKwh, forKey: Key.gridCo2)
        defaults.set(value.configured ?? false, forKey: Key.configured)
        defaults.set(dirty, forKey: Key.dirty)
        vehicle = value
        isDirty = dirty
    }
}
