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
        case .manual: return String(localized: "Manuell")
        case .automatic: return String(localized: "Automatisch")
        case .importSource: return String(localized: "Import")
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
        case .fullChargeInterval: return String(localized: "Exakt (Vollladung)")
        case .socCorrected: return String(localized: "SoC-korrigiert")
        case .naive: return String(localized: "Einfach (ohne SoC)")
        case .estimatedEnergy: return String(localized: "Geschätzte Energie")
        case .unavailable: return String(localized: "Nicht verfügbar")
        }
    }

    var explanation: String {
        switch self {
        case .fullChargeInterval:
            return String(localized: "Exakter Wert aus einem Vollladungs-Intervall – der genaueste Fall (Goldstandard).")
        case .socCorrected:
            return String(localized: "SoC-korrigiert auf Basis einer gemessenen kWh-Angabe.")
        case .naive:
            return String(localized: "Einfache kWh/km-Rechnung ohne SoC-Korrektur (keine SoC-Werte verfügbar).")
        case .estimatedEnergy:
            return String(localized: "Basiert auf einer geschätzten Energiemenge statt eines gemessenen kWh-Werts – Fehler können sich hier häufen.")
        case .unavailable:
            return String(localized: "Keine Verbrauchsberechnung möglich (z. B. erster Ladevorgang oder fehlender Kilometerstand).")
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
    /// Aussentemperatur in Grad Celsius BEIM LADEBEGINN (Server ab 0.23.0).
    /// Der Zeitpunkt ist entscheidend: der Verbrauch, den der Server diesem
    /// Vorgang zurechnet, stammt von der Fahrt davor - und die endet im
    /// Moment des Einsteckens.
    var outsideTempC: Double?
    /// Woher die Temperatur daneben stammt: "vehicle" (Fahrzeugsensor ueber
    /// Home Assistant oder den MyŠkoda-Poller), "manual" (von Hand) oder
    /// "weather" (nachtraeglich vom Wetterdienst geholt). `nil` bei
    /// Bestandsdaten aus der Zeit vor dieser Angabe.
    ///
    /// Bewusst NUR lesend: das Feld fehlt in `ChargingSessionPayload`. Der
    /// Server leitet "manual" aus einer echten Wertaenderung ab - schickte die
    /// App den alten Wert einfach zurueck, bliebe eine von Hand korrigierte
    /// Temperatur faelschlich als "vom Wetterdienst" stehen.
    var outsideTempSource: String?
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
        case outsideTempC = "outside_temp_c"
        case outsideTempSource = "outside_temp_source"
        case priceTotal = "price_total"
        case pricePerKwh = "price_per_kwh"
        case needsReview = "needs_review"
        case externalSessionId = "external_session_id"
    }

    /// Uebersetzter Klartext zur Herkunft der Temperatur, `nil` wenn keine
    /// hinterlegt ist. Die Rohwerte bleiben unangetastet - sie sind Daten,
    /// keine Anzeige (siehe models.TemperatureSource im Backend).
    var outsideTempSourceLabel: String? {
        switch outsideTempSource {
        case "vehicle": return String(localized: "vom Fahrzeug")
        case "manual": return String(localized: "von Hand")
        case "weather": return String(localized: "vom Wetterdienst")
        // Der Wetterdienst liefert serverseitig ab 0.24.1 das Tagesmittel
        // (6-20 Uhr) statt des Werts zum Ladebeginn - das ist keine Messung zu
        // einem Zeitpunkt wie beim Fahrzeugsensor und heisst deshalb anders.
        // "weather" gibt es nur noch bei Bestandsdaten.
        case "weather_daily": return String(localized: "vom Wetterdienst (Tagesmittel)")
        default: return nil
        }
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
    var outsideTempC: Double?
    var latitude: Double?
    var longitude: Double?
    var geocodedPlace: String?
    var notes: String?
    var needsReview: Bool?

    enum CodingKeys: String, CodingKey {
        case notes
        case latitude
        case longitude
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
        case outsideTempC = "outside_temp_c"
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
/// Haeufigkeit der Sammelmeldung ueber zu pruefende Ladevorgaenge.
/// Rohwerte kleingeschrieben wie vom Server geliefert (models.ReviewDigestFrequency).
enum ReviewDigestFrequency: String, Codable, CaseIterable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return String(localized: "Aus")
        case .daily: return String(localized: "Täglich")
        case .weekly: return String(localized: "Wöchentlich")
        }
    }
}

struct AuthUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let isAdmin: Bool
    let createdAt: Date?

    // Ab Server 0.14.0. ALLE neuen Felder sind optional, damit eine aktualisierte
    // App weiterhin gegen einen aelteren Server laeuft - waeren sie
    // nicht-optional, wuerde schon das Decodieren der Login-Antwort scheitern
    // und die Anmeldung komplett unmoeglich machen.
    let email: String?
    let emailVerifiedAt: Date?
    let language: String?
    let notifyBackupFailed: Bool?
    let notifyMyskodaError: Bool?
    let notifyMonthlyReport: Bool?
    let notifyNewRegistration: Bool?
    let reviewDigest: ReviewDigestFrequency?

    enum CodingKeys: String, CodingKey {
        case id, username, email, language
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case emailVerifiedAt = "email_verified_at"
        case notifyBackupFailed = "notify_backup_failed"
        case notifyMyskodaError = "notify_myskoda_error"
        case notifyMonthlyReport = "notify_monthly_report"
        case notifyNewRegistration = "notify_new_registration"
        case reviewDigest = "review_digest"
    }

    /// Ob die hinterlegte Adresse bestaetigt ist. Nur eine bestaetigte Adresse
    /// kann serverseitig ein Passwort zuruecksetzen.
    var isEmailVerified: Bool { emailVerifiedAt != nil }

    /// Ob der Server die Kontofunktionen aus 0.14.0 ueberhaupt kennt. Ein
    /// aelterer Server liefert `review_digest` nicht mit - dann werden die
    /// entsprechenden Bereiche in den Einstellungen gar nicht erst angezeigt,
    /// statt Knoepfe anzubieten, die mit 404 antworten.
    var supportsAccountFeatures: Bool { reviewDigest != nil }
}

/// Antwort von /api/auth/login und /api/auth/register.
struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
}

/// Request-Body fuer den Login. Das Feld heisst serverseitig weiterhin
/// `username`, nimmt aber auch die E-Mail-Adresse an.
struct AuthCredentials: Codable {
    let username: String
    let password: String
}

/// Request-Body fuer die Registrierung - wie AuthCredentials, plus optionaler
/// Adresse. Bewusst eine eigene Struct: bei `nil` soll das Feld gar nicht erst
/// im JSON auftauchen, was mit einem gemeinsamen Typ ein `encodeIfPresent`
/// erzwingen wuerde.
struct RegisterCredentials: Codable {
    let username: String
    let password: String
    let email: String?
}

/// Body fuer PUT /api/auth/password.
struct PasswordChangePayload: Codable {
    let currentPassword: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

/// Body fuer PUT /api/auth/email. `email == nil` entfernt die Adresse.
/// Das aktuelle Passwort verlangt der Server: wer die Adresse aendern kann,
/// kann anschliessend das Passwort zuruecksetzen lassen.
struct EmailUpdatePayload: Codable {
    let email: String?
    let currentPassword: String

    enum CodingKeys: String, CodingKey {
        case email
        case currentPassword = "current_password"
    }
}

/// Body fuer DELETE /api/auth/me. Wie bei /email und /password verlangt der
/// Server das aktuelle Passwort - ein gestohlener Bearer-Token allein darf
/// das Konto nicht vernichten koennen.
struct AccountDeletePayload: Codable {
    let currentPassword: String

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
    }
}

/// Body fuer PUT /api/auth/notifications - der Server erwartet alle Felder.
struct NotificationSettingsPayload: Codable {
    let notifyBackupFailed: Bool
    let notifyMyskodaError: Bool
    let notifyMonthlyReport: Bool
    let notifyNewRegistration: Bool
    let reviewDigest: ReviewDigestFrequency

    enum CodingKeys: String, CodingKey {
        case notifyBackupFailed = "notify_backup_failed"
        case notifyMyskodaError = "notify_myskoda_error"
        case notifyMonthlyReport = "notify_monthly_report"
        case notifyNewRegistration = "notify_new_registration"
        case reviewDigest = "review_digest"
    }
}

/// Body fuer POST /api/auth/password-reset/request. Nutzername ODER Adresse.
struct PasswordResetRequestPayload: Codable {
    let identifier: String
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

    /// Wandelt das Server-Format "YYYY-MM" (z.B. "2026-08") in einen an die
    /// aktuelle App-Sprache angepassten Klartext um (z.B. "August 2026" bzw.
    /// "August 2026" / "August 2026" fuer Englisch), passend zur Darstellung
    /// im Web-UI. Faellt bei unerwartetem Format auf den Rohwert zurueck.
    var displayMonth: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let monthIndex = Int(parts[1]),
              (1...12).contains(monthIndex) else {
            return month
        }
        let names = DateFormatter().standaloneMonthSymbols ?? []
        guard names.count == 12 else { return month }
        return "\(names[monthIndex - 1]) \(parts[0])"
    }

    /// Kurze Variante fuer Diagramm-Achsen, z.B. "Aug '26". Eindeutig, weil
    /// Jahr-Kuerzel enthalten ist (kein Merge bei gleichen Monatsnamen aus
    /// verschiedenen Jahren). Nutzt die kurzen Monatsnamen der aktuellen
    /// App-Sprache (Locale.current), damit die Achsenbeschriftung mit der
    /// UI-Sprache mitgeht.
    var shortMonth: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let monthIndex = Int(parts[1]),
              (1...12).contains(monthIndex) else {
            return month
        }
        let names = DateFormatter().shortStandaloneMonthSymbols ?? []
        guard names.count == 12 else { return month }
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

// MARK: - Sync: serverseitig geloeschte Datensaetze

/// Eine Loeschung, die auf dem Server stattgefunden hat (Web-UI, zweites
/// Geraet, ein anderer Client). Gegenstueck zu `models.DeletedRecord` im
/// Backend - siehe SyncService.applyServerDeletions() fuer das Warum.
struct DeletedRecord: Codable, Hashable {
    let entityType: String
    let entityId: String

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
    }
}

struct DeletionsResponse: Codable {
    /// Cursor fuer den naechsten Abruf. Bewusst als ROHER STRING durchgereicht
    /// und nie in ein `Date` gewandelt: der Server schickt naive UTC-Zeitstempel,
    /// die der Datums-Decoder dieser App (siehe APIClient) als LOKALE Zeit liest -
    /// hin- und zurueckgewandelt waere der Cursor um den Zeitzonen-Offset
    /// verschoben und wuerde Loeschungen ueberspringen. Als unveraendert
    /// zurueckgegebene Zeichenkette kann das nicht passieren.
    let serverTime: String
    let deletions: [DeletedRecord]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case deletions
    }
}

// MARK: - Verbrauch nach Aussentemperatur

/// Antwort von `GET /api/stats/temperature`.
///
/// Wird bewusst NICHT lokal nachgerechnet (anders als `StatsSummary`, die im
/// Local-Only-Modus aus `LocalStatsCalculator` kommt): die Auswertung in
/// `temperature.py` haengt an der Verbrauchskette, den km-Gewichten und den
/// Schwellen fuer die Ausgleichsgerade - ein dritter Nachbau davon (nach
/// `LocalConsumptionCalculator`) wuerde frueher oder spaeter andere Zahlen
/// zeigen als das Web-Dashboard. Die Ansicht gibt es deshalb nur im
/// Server-Modus.
struct TemperatureStats: Codable {
    let points: [TempPoint]
    let buckets: [TempBucket]
    let seasons: [SeasonStat]
    /// `nil`, wenn zu wenige Fahrten oder ein zu schmaler Temperaturbereich
    /// vorliegen - dann wird bewusst keine Gerade gezeigt.
    let trend: TempTrend?
    /// Vorgaenge mit berechenbarem Verbrauch, aber ohne Temperatur.
    let sessionsWithoutTemp: Int
    let bucketWidthC: Int

    enum CodingKeys: String, CodingKey {
        case points, buckets, seasons, trend
        case sessionsWithoutTemp = "sessions_without_temp"
        case bucketWidthC = "bucket_width_c"
    }
}

struct TempPoint: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let startTime: Date
    let tempC: Double
    let consumptionKwhPer100km: Double
    let km: Double
    let consumptionMethod: String
    let season: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startTime = "start_time"
        case tempC = "temp_c"
        case consumptionKwhPer100km = "consumption_kwh_per_100km"
        case km
        case consumptionMethod = "consumption_method"
        case season
    }
}

struct TempBucket: Codable, Identifiable {
    var id: Double { fromC }
    let fromC: Double
    let toC: Double
    let avgConsumptionKwhPer100km: Double
    let sessionCount: Int
    let km: Double

    enum CodingKeys: String, CodingKey {
        case fromC = "from_c"
        case toC = "to_c"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
        case sessionCount = "session_count"
        case km
    }

    /// Mitte der Klasse - der x-Wert, an dem der Klassenmittelwert im
    /// Streudiagramm sitzt.
    var centerC: Double { (fromC + toC) / 2 }

    var label: String { String(format: "%.0f…%.0f °C", fromC, toC) }
}

struct SeasonStat: Codable, Identifiable {
    var id: String { season }
    /// winter | spring | summer | autumn
    let season: String
    let avgConsumptionKwhPer100km: Double
    let sessionCount: Int
    let km: Double

    enum CodingKeys: String, CodingKey {
        case season
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
        case sessionCount = "session_count"
        case km
    }

    /// Uebersetzter Name. Die Rohwerte sind die englischen Schluessel aus
    /// `temperature.py::SEASONS` und bleiben unangetastet (sie sind Daten,
    /// keine Anzeige).
    var displayName: String {
        switch season {
        case "winter": return String(localized: "Winter")
        case "spring": return String(localized: "Frühling")
        case "summer": return String(localized: "Sommer")
        case "autumn": return String(localized: "Herbst")
        default: return season
        }
    }
}

struct TempTrend: Codable {
    let slope: Double
    let intercept: Double
    /// Wieviel der Streuung die Temperatur ueberhaupt erklaert (0…1).
    let r2: Double
    let consumptionAt0c: Double
    let consumptionAt20c: Double
    let extraPctAt0c: Double

    enum CodingKeys: String, CodingKey {
        case slope, intercept, r2
        case consumptionAt0c = "consumption_at_0c"
        case consumptionAt20c = "consumption_at_20c"
        case extraPctAt0c = "extra_pct_at_0c"
    }
}
