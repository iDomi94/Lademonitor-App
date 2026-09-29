import Foundation

/// Antwort von `GET /api/stats/battery` (Server ab 0.28.0): Akku-Index und
/// Ladeverluste je Fahrzeug.
///
/// Wie die Temperaturauswertung bewusst NUR im Server-Modus - die Regeln
/// (Mindest-Hub, Plausibilitaetsgrenzen, Normierung je Lade-Art) liegen allein
/// in `battery.py`; ein Nachbau hier wuerde frueher oder spaeter andere Zahlen
/// zeigen als das Web-Dashboard.
struct BatteryStats: Codable {
    let vehicles: [BatteryVehicleStats]
}

struct BatteryVehicleStats: Codable, Identifiable {
    var id: String { vehicleId }
    let vehicleId: String
    let vehicleName: String
    let nominalCapacityKwh: Double?
    let points: [BatteryPoint]
    let lossesByType: [BatteryLossGroup]
    let lossesByProvider: [BatteryLossGroup]
    /// Index 100 = wie zu Beginn der Aufzeichnung, je Quartal.
    let healthPeriods: [BatteryHealthPeriod]
    let healthLatestIndexPct: Double?
    let healthTrendPctPerYear: Double?
    let excluded: BatteryExclusions
    let minSocDelta: Int

    enum CodingKeys: String, CodingKey {
        case vehicleId = "vehicle_id"
        case vehicleName = "vehicle_name"
        case nominalCapacityKwh = "nominal_capacity_kwh"
        case points
        case lossesByType = "losses_by_type"
        case lossesByProvider = "losses_by_provider"
        case healthPeriods = "health_periods"
        case healthLatestIndexPct = "health_latest_index_pct"
        case healthTrendPctPerYear = "health_trend_pct_per_year"
        case excluded
        case minSocDelta = "min_soc_delta"
    }
}

struct BatteryPoint: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let startTime: Date
    /// "AC", "DC" oder "unknown"
    let chargingType: String
    let socDelta: Int
    let energyKwh: Double
    let apparentCapacityKwh: Double
    let lossPct: Double?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startTime = "start_time"
        case chargingType = "charging_type"
        case socDelta = "soc_delta"
        case energyKwh = "energy_kwh"
        case apparentCapacityKwh = "apparent_capacity_kwh"
        case lossPct = "loss_pct"
    }
}

struct BatteryLossGroup: Codable, Identifiable {
    var id: String { key }
    /// Lade-Art (AC/DC/unknown) bzw. Anbietername ("" = ohne Anbieter).
    let key: String
    let sessionCount: Int
    let energyKwh: Double
    let apparentCapacityKwh: Double
    /// Mehrbedarf gegenueber der Nennkapazitaet in Prozent.
    let lossPct: Double?

    enum CodingKeys: String, CodingKey {
        case key
        case sessionCount = "session_count"
        case energyKwh = "energy_kwh"
        case apparentCapacityKwh = "apparent_capacity_kwh"
        case lossPct = "loss_pct"
    }
}

struct BatteryHealthPeriod: Codable, Identifiable {
    var id: String { period }
    /// "2026-Q3"
    let period: String
    let indexPct: Double
    let sessionCount: Int

    var label: String { period.replacingOccurrences(of: "-", with: " ") }

    enum CodingKeys: String, CodingKey {
        case period
        case indexPct = "index_pct"
        case sessionCount = "session_count"
    }
}

struct BatteryExclusions: Codable {
    let estimatedEnergy: Int
    let missingValues: Int
    let smallSocDelta: Int
    let implausible: Int

    var total: Int { estimatedEnergy + missingValues + smallSocDelta + implausible }

    enum CodingKeys: String, CodingKey {
        case estimatedEnergy = "estimated_energy"
        case missingValues = "missing_values"
        case smallSocDelta = "small_soc_delta"
        case implausible
    }
}
