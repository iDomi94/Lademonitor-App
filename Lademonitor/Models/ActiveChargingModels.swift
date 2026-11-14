import Foundation

/// Antwort von `GET /api/sessions/active` (Server ab 0.45.0): ein gerade
/// laufender Ladevorgang ("Lädt gerade").
///
/// Kein `ChargingSession` - der Vorgang entsteht auf dem Server erst beim
/// Ausstecken. Bis dahin ist das ein Zwischenstand der Quelle (MyŠkoda,
/// VW-Datenportal, Renault oder die Startmeldung aus Home Assistant), nur
/// zum Anzeigen, nicht im lokalen Spiegel und nicht im Sync. Deshalb auch
/// nur im Server-Modus.
struct ActiveCharging: Codable, Identifiable {
    var id: String { vehicleId }
    let vehicleId: String
    let vehicleName: String?
    /// myskoda | vw_data_act | renault | home_assistant
    let source: String
    let startTime: Date?
    let chargingType: String?
    let socStart: Int?
    /// Juengster bekannter SoC (letzter Bericht der Quelle).
    let socCurrent: Int?
    let energyKwh: Double?
    let energyIsEstimated: Bool
    let maxPowerKw: Double?
    let odometerKm: Int?
    let outsideTempC: Double?
    /// Zeitpunkt des Berichts, aus dem die Werte stammen - beim
    /// VW-Datenportal gern Stunden alt.
    let updatedAt: Date?
    /// Preisschaetzung (Server ab 0.55.0, sonst nil): Ladeort und Anbieter nur,
    /// wenn die Position zu einem Ladeort passt.
    let locationName: String?
    let providerName: String?
    let pricePerKwh: Double?
    let priceTotal: Double?
    /// "provider" = letzter Preis des Anbieters am Ladeort, "average" =
    /// Durchschnittspreis, nil = keine Schaetzung moeglich.
    let priceSource: String?

    enum CodingKeys: String, CodingKey {
        case vehicleId = "vehicle_id"
        case vehicleName = "vehicle_name"
        case source
        case startTime = "start_time"
        case chargingType = "charging_type"
        case socStart = "soc_start"
        case socCurrent = "soc_current"
        case energyKwh = "energy_kwh"
        case energyIsEstimated = "energy_is_estimated"
        case maxPowerKw = "max_power_kw"
        case odometerKm = "odometer_km"
        case outsideTempC = "outside_temp_c"
        case updatedAt = "updated_at"
        case locationName = "location_name"
        case providerName = "provider_name"
        case pricePerKwh = "price_per_kwh"
        case priceTotal = "price_total"
        case priceSource = "price_source"
    }

    var priceIsAverage: Bool { priceSource == "average" }

    var sourceLabel: String {
        switch source {
        case "myskoda": return "MyŠkoda"
        case "vw_data_act": return String(localized: "VW-Datenportal")
        case "renault": return "Renault"
        case "home_assistant": return "Home Assistant"
        default: return source
        }
    }
}
