import Foundation

enum ChargingType: String, Codable, CaseIterable, Identifiable {
    case ac = "AC"
    case dc = "DC"
    var id: String { rawValue }
}

enum SessionSource: String, Codable {
    case manual
    case automatic
    case importSource = "import"

    var displayName: String {
        switch self {
        case .manual: return "Manuell"
        case .automatic: return "Automatisch"
        case .importSource: return "Import"
        }
    }
}

struct Vehicle: Codable, Identifiable, Hashable {
    let id: String
    var externalId: String
    var name: String
    var brand: String?
    var model: String?
    var batteryCapacityKwh: Double?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, brand, model
        case externalId = "external_id"
        case batteryCapacityKwh = "battery_capacity_kwh"
        case isActive = "is_active"
    }
}

struct Provider: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var lastPriceAcPerKwh: Double?
    var lastPriceDcPerKwh: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastPriceAcPerKwh = "last_price_ac_per_kwh"
        case lastPriceDcPerKwh = "last_price_dc_per_kwh"
    }
}

struct ChargingLocation: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusM: Int
    var defaultProviderId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude
        case radiusM = "radius_m"
        case defaultProviderId = "default_provider_id"
    }
}

/// Methode, mit der der Server den Verbrauch (kWh/100km) fuer einen Ladevorgang
/// berechnet hat. Bestimmt Marker-Icon und Erklaerungstext in der Liste.
enum ConsumptionMethod: String {
    case fullChargeInterval = "full_charge_interval"
    case socCorrected = "soc_corrected"
    case naive
    case estimatedEnergy = "estimated_energy"
    case unavailable

    /// Kompaktes Marker-Zeichen analog zum Web-UI.
    var marker: String {
        switch self {
        case .fullChargeInterval: return "🎯"
        case .socCorrected: return "✓"
        case .naive, .estimatedEnergy: return "~"
        case .unavailable: return ""
        }
    }

    var shortLabel: String {
        switch self {
        case .fullChargeInterval: return "Exakt (Vollladung)"
        case .socCorrected: return "SoC-korrigiert"
        case .naive: return "Einfach (ohne SoC)"
        case .estimatedEnergy: return "Geschätzte Energie"
        case .unavailable: return "Nicht verfügbar"
        }
    }

    var explanation: String {
        switch self {
        case .fullChargeInterval:
            return "Exakter Wert aus einem Vollladungs-Intervall – der genaueste Fall (Goldstandard)."
        case .socCorrected:
            return "SoC-korrigiert auf Basis einer gemessenen kWh-Angabe."
        case .naive:
            return "Einfache kWh/km-Rechnung ohne SoC-Korrektur (keine SoC-Werte verfügbar)."
        case .estimatedEnergy:
            return "Basiert auf einer geschätzten Energiemenge statt eines gemessenen kWh-Werts – Fehler können sich hier häufen."
        case .unavailable:
            return "Keine Verbrauchsberechnung möglich (z. B. erster Ladevorgang oder fehlender Kilometerstand)."
        }
    }
}

struct ChargingSession: Codable, Identifiable, Hashable {
    let id: String
    var vehicleId: String
    var providerId: String?
    var locationId: String?
    var startTime: Date
    var endTime: Date?
    var chargingType: ChargingType?
    var socStart: Int?
    var socEnd: Int?
    var energyKwh: Double?
    var energyIsEstimated: Bool
    var odometerKm: Int?
    var priceTotal: Double?
    var pricePerKwh: Double?
    var latitude: Double?
    var longitude: Double?
    var geocodedPlace: String?
    var consumptionKwhPer100km: Double?
    var consumptionMethod: String?
    var notes: String?
    var source: SessionSource
    var needsReview: Bool
    var externalSessionId: String?

    enum CodingKeys: String, CodingKey {
        case id, notes, source, latitude, longitude
        case geocodedPlace = "geocoded_place"
        case consumptionKwhPer100km = "consumption_kwh_per_100km"
        case consumptionMethod = "consumption_method"
        case vehicleId = "vehicle_id"
        case providerId = "provider_id"
        case locationId = "location_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case chargingType = "charging_type"
        case socStart = "soc_start"
        case socEnd = "soc_end"
        case energyKwh = "energy_kwh"
        case energyIsEstimated = "energy_is_estimated"
        case odometerKm = "odometer_km"
        case priceTotal = "price_total"
        case pricePerKwh = "price_per_kwh"
        case needsReview = "needs_review"
        case externalSessionId = "external_session_id"
    }

    /// Getypte Variante des Server-Strings `consumption_method`; unbekannte oder
    /// fehlende Werte ergeben nil.
    var consumptionMethodValue: ConsumptionMethod? {
        consumptionMethod.flatMap(ConsumptionMethod.init(rawValue:))
    }
}

/// Payload zum Anlegen/Bearbeiten - alle Felder optional, damit dieselbe Struct
/// fuer POST (Create) und PATCH (Update) genutzt werden kann.
struct ChargingSessionPayload: Codable {
    var vehicleId: String?
    var providerId: String?
    var startTime: Date?
    var chargingType: ChargingType?
    var socStart: Int?
    var socEnd: Int?
    var energyKwh: Double?
    var pricePerKwh: Double?
    var priceTotal: Double?
    var odometerKm: Int?
    var geocodedPlace: String?
    var notes: String?
    var needsReview: Bool?

    enum CodingKeys: String, CodingKey {
        case notes
        case vehicleId = "vehicle_id"
        case providerId = "provider_id"
        case startTime = "start_time"
        case chargingType = "charging_type"
        case socStart = "soc_start"
        case socEnd = "soc_end"
        case energyKwh = "energy_kwh"
        case pricePerKwh = "price_per_kwh"
        case priceTotal = "price_total"
        case odometerKm = "odometer_km"
        case geocodedPlace = "geocoded_place"
        case needsReview = "needs_review"
    }
}

/// Payload fuer Fahrzeuge. Bei PATCH werden nur gesetzte (non-nil) Felder gesendet.
/// `externalId` nur beim Anlegen setzen - es ist serverseitig unveraenderlich.
struct VehiclePayload: Codable {
    var externalId: String?
    var name: String?
    var brand: String?
    var model: String?
    var batteryCapacityKwh: Double?
    var isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name, brand, model
        case externalId = "external_id"
        case batteryCapacityKwh = "battery_capacity_kwh"
        case isActive = "is_active"
    }
}

/// Payload fuer Anbieter. Bei PATCH werden nur gesetzte (non-nil) Felder gesendet.
struct ProviderPayload: Codable {
    var name: String?
    var lastPriceAcPerKwh: Double?
    var lastPriceDcPerKwh: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, notes
        case lastPriceAcPerKwh = "last_price_ac_per_kwh"
        case lastPriceDcPerKwh = "last_price_dc_per_kwh"
    }
}

/// Payload fuer Ladeorte. Bei PATCH werden nur gesetzte (non-nil) Felder gesendet.
struct LocationPayload: Codable {
    var name: String?
    var latitude: Double?
    var longitude: Double?
    var radiusM: Int?
    var defaultProviderId: String?

    enum CodingKeys: String, CodingKey {
        case name, latitude, longitude
        case radiusM = "radius_m"
        case defaultProviderId = "default_provider_id"
    }
}

/// Ein angemeldeter Nutzer (aus der Auth-Response bzw. /api/auth/me).
struct AuthUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let isAdmin: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username
        case isAdmin = "is_admin"
        case createdAt = "created_at"
    }
}

/// Antwort von /api/auth/login und /api/auth/register.
struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
}

/// Request-Body fuer Login und Registrierung.
struct AuthCredentials: Codable {
    let username: String
    let password: String
}

/// Ein Treffer der Adresssuche (Forward-Geocoding) vom Backend.
/// `displayName` stammt aus einer externen Quelle (Nominatim) und ist nicht
/// vertrauenswuerdig - immer nur als reiner Text (SwiftUI `Text`) anzeigen.
struct GeocodeResult: Codable, Hashable {
    let displayName: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case latitude, longitude
    }
}

/// Anbieter-Statistik aus dem by_provider-Array der Stats-API.
/// Bereits nach kWh absteigend vorsortiert; Sessions ohne Anbieter laufen unter
/// "Ohne Anbieter".
struct ProviderStat: Codable, Identifiable {
    var id: String { providerName }
    let providerName: String
    let totalKwh: Double
    let totalCost: Double

    enum CodingKeys: String, CodingKey {
        case providerName = "provider_name"
        case totalKwh = "total_kwh"
        case totalCost = "total_cost"
    }
}

struct MonthlyStat: Codable, Identifiable {
    var id: String { month }
    let month: String
    let totalCost: Double
    let totalKwh: Double
    let sessionCount: Int
    let avgConsumptionKwhPer100km: Double?

    enum CodingKeys: String, CodingKey {
        case month
        case totalCost = "total_cost"
        case totalKwh = "total_kwh"
        case sessionCount = "session_count"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
    }

    /// Wandelt das Server-Format "YYYY-MM" (z.B. "2026-08") in einen deutschen
    /// Klartext um (z.B. "August 2026"), passend zur Darstellung im Web-UI.
    /// Faellt bei unerwartetem Format auf den Rohwert zurueck.
    var displayMonth: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let monthIndex = Int(parts[1]),
              (1...12).contains(monthIndex) else {
            return month
        }
        let names = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                     "Juli", "August", "September", "Oktober", "November", "Dezember"]
        return "\(names[monthIndex - 1]) \(parts[0])"
    }

    /// Kurze Variante fuer Diagramm-Achsen, z.B. "Aug '26". Eindeutig, weil
    /// Jahr-Kuerzel enthalten ist (kein Merge bei gleichen Monatsnamen aus
    /// verschiedenen Jahren).
    var shortMonth: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let monthIndex = Int(parts[1]),
              (1...12).contains(monthIndex) else {
            return month
        }
        let names = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
                     "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        let yearSuffix = parts[0].suffix(2)
        return "\(names[monthIndex - 1]) '\(yearSuffix)"
    }
}

struct StatsSummary: Codable {
    let totalSessions: Int
    let totalKwh: Double
    let totalCost: Double
    let avgPricePerKwh: Double?
    let avgConsumptionKwhPer100km: Double?
    let pricePer100km: Double?
    let acSharePct: Double?
    let dcSharePct: Double?
    let acKwh: Double?
    let dcKwh: Double?
    let totalKmDriven: Int?
    let byProvider: [ProviderStat]
    let monthly: [MonthlyStat]

    enum CodingKeys: String, CodingKey {
        case totalSessions = "total_sessions"
        case totalKwh = "total_kwh"
        case totalCost = "total_cost"
        case avgPricePerKwh = "avg_price_per_kwh"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
        case pricePer100km = "price_per_100km"
        case acSharePct = "ac_share_pct"
        case dcSharePct = "dc_share_pct"
        case acKwh = "ac_kwh"
        case dcKwh = "dc_kwh"
        case totalKmDriven = "total_km_driven"
        case byProvider = "by_provider"
        case monthly
    }
}
