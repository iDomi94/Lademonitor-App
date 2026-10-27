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

/// Wo die kWh eines Ladevorgangs abgelesen wurden (Server ab 0.29.0): an der
/// Ladesaeule bzw. Wallbox ("charger") oder im Fahrzeug ("vehicle"). Im
/// Fahrzeug gemessene kWh enthalten keine Ladeverluste - die Akku-Auswertung
/// laesst solche Vorgaenge deshalb bei den Ladeverlusten weg, zaehlt sie aber
/// im Akku-Index mit.
///
/// Der Anbieter traegt die Voreinstellung, ein Ladevorgang optional eine
/// Abweichung davon (`nil` = folgt dem Anbieter). Rohwerte wie vom Server.
enum EnergyMeter: String, CaseIterable, Identifiable {
    case charger
    case vehicle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .charger: return String(localized: "Ladesäule")
        case .vehicle: return String(localized: "Fahrzeug")
        }
    }

    /// Unbekannte oder fehlende Werte (aelterer Server) gelten als Ladesaeule,
    /// wie serverseitig.
    init(raw: String?) {
        self = raw.flatMap(EnergyMeter.init(rawValue:)) ?? .charger
    }

    /// Wirksamer Messort: Abweichung am Vorgang, sonst die Voreinstellung des
    /// Anbieters, sonst Ladesaeule. Gleiche Regel wie
    /// `energy_meter_effective` auf dem Server.
    static func effective(override: String?, providerDefault: String?) -> EnergyMeter {
        EnergyMeter(raw: override ?? providerDefault)
    }

    /// Was am Vorgang gespeichert wird: `nil`, wenn die Wahl der Voreinstellung
    /// des Anbieters entspricht, sonst die Wahl selbst - dieselbe
    /// Normalisierung wie auf dem Server. So folgt ein Vorgang ohne echte
    /// Abweichung weiter seinem Anbieter, auch wenn dessen Einstellung sich
    /// spaeter aendert.
    static func storedOverride(choice: EnergyMeter, providerDefault: String?) -> String? {
        choice == EnergyMeter(raw: providerDefault) ? nil : choice.rawValue
    }
}

/// Wo geladen wird (Server ab 0.31.0, `Provider.charging_place`). Trennt im
/// Dashboard Zuhause/Arbeit/Unterwegs und bestimmt, welche Anbieter der
/// Tarifrechner als "ohne Tarif" heranzieht.
enum ChargingPlace: String, CaseIterable, Identifiable {
    case home
    case work
    case `public`

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return String(localized: "Zuhause")
        case .work: return String(localized: "Arbeit")
        case .public: return String(localized: "Unterwegs")
        }
    }

    /// Unbekannt oder fehlend (aelterer Server) heisst unterwegs, wie
    /// serverseitig.
    init(raw: String?) {
        self = raw.flatMap(ChargingPlace.init(rawValue:)) ?? .public
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
    // Kauf/Leasing (Server ab 0.32.0). Alle optional, damit ein aelterer
    // Server ohne die Felder weiter decodiert - ein neuerer schickt
    // `ownership` immer mit, daran erkennt der SyncService, ob er die
    // uebrigen Felder uebernehmen darf. Datumsangaben sind reine Kalendertage.
    // Die nur lesenden Kennzahlen des Servers (estimated_value usw.) werden
    // bewusst nicht gelesen: die App rechnet sie selbst
    // (LocalVehicleCostCalculator.ownershipInfo), auch im Local-Only-Modus.
    var ownership: String? = nil
    var purchasePrice: Double? = nil
    var purchaseDate: Date? = nil
    var firstRegistration: Date? = nil
    var purchaseOdometerKm: Int? = nil
    var depreciationMonthlyOverride: Double? = nil
    var leasingRateMonthly: Double? = nil
    var leasingStart: Date? = nil
    var leasingEnd: Date? = nil
    var leasingDownPayment: Double? = nil
    // Dienstwagen/Erstattung (Server ab 0.35.0). Optional wie Kauf/Leasing:
    // ein neuerer Server schickt `is_company_car` immer mit, daran erkennt
    // der SyncService, ob er die uebrigen Felder uebernehmen darf - ein
    // aelterer wuerde sonst die lokale Angabe bei jedem Sync leeren.
    var isCompanyCar: Bool? = nil
    var reimbursementMode: String? = nil
    var reimbursementIncludeFees: Bool? = nil
    var employeeName: String? = nil
    var employeeNumber: String? = nil
    var licensePlate: String? = nil
    /// Monatsmail mit dem Bericht - nur eine Serverfunktion.
    var reimbursementMonthlyMail: Bool? = nil

    var ownershipValue: Ownership { Ownership(raw: ownership) }
    var isCompanyCarValue: Bool { isCompanyCar ?? false }
    var reimbursementModeValue: ReimbursementMode { ReimbursementMode(raw: reimbursementMode) }

    enum CodingKeys: String, CodingKey {
        case id, name, brand, model, ownership
        case isCompanyCar = "is_company_car"
        case reimbursementMode = "reimbursement_mode"
        case reimbursementIncludeFees = "reimbursement_include_fees"
        case employeeName = "employee_name"
        case employeeNumber = "employee_number"
        case licensePlate = "license_plate"
        case reimbursementMonthlyMail = "reimbursement_monthly_mail"
        case externalId = "external_id"
        case batteryCapacityKwh = "battery_capacity_kwh"
        case isActive = "is_active"
        case purchasePrice = "purchase_price"
        case purchaseDate = "purchase_date"
        case firstRegistration = "first_registration"
        case purchaseOdometerKm = "purchase_odometer_km"
        case depreciationMonthlyOverride = "depreciation_monthly_override"
        case leasingRateMonthly = "leasing_rate_monthly"
        case leasingStart = "leasing_start"
        case leasingEnd = "leasing_end"
        case leasingDownPayment = "leasing_down_payment"
    }
}

struct Provider: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var lastPriceAcPerKwh: Double?
    var lastPriceDcPerKwh: Double?
    var notes: String?
    /// Voreinstellung "charger" | "vehicle" (Server ab 0.29.0). Optional, damit
    /// ein aelterer Server ohne das Feld weiter decodiert - fehlend heisst
    /// Ladesaeule, siehe `energyMeterDefault`.
    var energyMeter: String? = nil
    /// "home" | "work" | "public" (Server ab 0.31.0), fehlend heisst
    /// unterwegs, siehe `place`.
    var chargingPlace: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastPriceAcPerKwh = "last_price_ac_per_kwh"
        case lastPriceDcPerKwh = "last_price_dc_per_kwh"
        case energyMeter = "energy_meter"
        case chargingPlace = "charging_place"
    }

    var energyMeterDefault: EnergyMeter { EnergyMeter(raw: energyMeter) }
    var place: ChargingPlace { ChargingPlace(raw: chargingPlace) }
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
    /// Anteil an den Grundgebuehren/Abos des Anbieters in EUR (Server ab
    /// 0.27.0), nach kWh auf die Vorgaenge der Periode umgelegt. Kommt NICHT
    /// in `priceTotal` vor - das bleibt der Saeulenpreis. Nur lesend und
    /// lokal immer frisch berechnet (LocalFeeAllocator), wie der Verbrauch.
    var feeShare: Double? = nil
    /// Abweichender Messort der kWh ("charger" | "vehicle"), `nil` = folgt dem
    /// Anbieter (Server ab 0.29.0). Bewusst der ROHE Wert, nicht
    /// `energy_meter_effective` - sonst wuerde eine spaetere Aenderung am
    /// Anbieter diesen Vorgang nicht mehr erreichen. Wirksam: `EnergyMeter.effective`.
    var energyMeter: String? = nil
    /// Durchschnittsgeschwindigkeit seit dem letzten Laden in km/h, aus dem
    /// Bordcomputer abgelesen (Server ab 0.47.0). Beschreibt dieselbe Strecke
    /// wie der Verbrauch dieses Vorgangs und teilt dessen Mehrverbrauch in
    /// Tempo und Temperatur auf (`DriveBreakdownStats`).
    var avgSpeedKmh: Double? = nil

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
        case feeShare = "fee_share"
        case energyMeter = "energy_meter"
        case avgSpeedKmh = "avg_speed_kmh"
    }

    /// Wirksamer Messort der kWh - Abweichung am Vorgang, sonst die
    /// Voreinstellung seines Anbieters.
    func effectiveEnergyMeter(providers: [Provider]) -> EnergyMeter {
        EnergyMeter.effective(
            override: energyMeter,
            providerDefault: providers.first { $0.id == providerId }?.energyMeter
        )
    }

    /// Saeulenpreis plus Grundgebuehranteil - das, was der Vorgang effektiv
    /// gekostet hat. `nil` nur, wenn beides fehlt.
    var effectiveTotal: Double? {
        guard priceTotal != nil || feeShare != nil else { return nil }
        return (priceTotal ?? 0) + (feeShare ?? 0)
    }

    /// Uebersetzter Klartext zur Herkunft der Temperatur, `nil` wenn keine
    /// hinterlegt ist. Die Rohwerte bleiben unangetastet - sie sind Daten,
    /// keine Anzeige (siehe models.TemperatureSource im Backend).
    var outsideTempSourceLabel: String? {
        switch outsideTempSource {
        case "vehicle": return String(localized: "vom Fahrzeug")
        case "manual": return String(localized: "von Hand")
        case "weather": return String(localized: "vom Wetterdienst")
        // Der Wetterdienst mittelt serverseitig ab 0.24.1 die Tagstunden ueber
        // den ganzen Zeitraum seit dem vorherigen Ladevorgang - das ist keine
        // Messung zu einem Zeitpunkt wie beim Fahrzeugsensor und heisst
        // deshalb anders. "weather" gibt es nur noch bei Bestandsdaten.
        case "weather_daily": return String(localized: "vom Wetterdienst (Zeitraummittel)")
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
    /// Nur gesetzt, wenn die App die Zuordnung selbst herstellt ("Als Ladeort
    /// anlegen"). nil wird nicht gesendet, eine bestehende Zuordnung bleibt also
    /// beim normalen Speichern stehen.
    var locationId: String? = nil
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
    /// Gewaehlter Messort der kWh ("charger" | "vehicle"). Bewusst die
    /// WIRKSAME Wahl, nicht die gespeicherte Abweichung: `nil` wird wie bei
    /// den uebrigen Feldern gar nicht gesendet und hiesse "unveraendert" - das
    /// Zuruecksetzen auf die Anbieter-Voreinstellung kaeme so nie an. Server
    /// und LocalDataStore normalisieren beide (gleich Voreinstellung -> null).
    var energyMeter: String? = nil
    /// Ø km/h seit dem letzten Laden. `nil` = unveraendert, wie die uebrigen
    /// Felder.
    var avgSpeedKmh: Double? = nil

    enum CodingKeys: String, CodingKey {
        case notes
        case latitude
        case longitude
        case vehicleId = "vehicle_id"
        case providerId = "provider_id"
        case locationId = "location_id"
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
        case energyMeter = "energy_meter"
        case avgSpeedKmh = "avg_speed_kmh"
    }
}

/// Payload fuer Fahrzeuge. Bei PATCH werden nur gesetzte (non-nil) Felder gesendet.
/// `externalId` nur beim Anlegen setzen - es ist serverseitig unveraenderlich.
///
/// Ausnahme Kauf/Leasing: mit `sendsOwnership` gehen ALLE diese Felder mit,
/// auch `nil` als `null` (wie bei ProviderFeePayload) - sonst liesse sich z.B.
/// ein ueberschriebener Wertverlust nie wieder leeren. `ownership` selbst
/// geht dabei immer als Wert raus ("none" statt null), weil der Server beim
/// Anlegen kein null annimmt. Ein aelterer Server ignoriert die Felder.
struct VehiclePayload: Codable {
    var externalId: String?
    var name: String?
    var brand: String?
    var model: String?
    var batteryCapacityKwh: Double?
    var isActive: Bool?
    var sendsOwnership = false
    var ownership: String? = nil
    var purchasePrice: Double? = nil
    var purchaseDate: Date? = nil
    var firstRegistration: Date? = nil
    var purchaseOdometerKm: Int? = nil
    var depreciationMonthlyOverride: Double? = nil
    var leasingRateMonthly: Double? = nil
    var leasingStart: Date? = nil
    var leasingEnd: Date? = nil
    var leasingDownPayment: Double? = nil
    /// Dienstwagen/Erstattung (Server ab 0.35.0). Gesetzt, schreibt der
    /// Payload alle diese Felder: die Texte auch als `null` (leert sie), die
    /// Schalter und die Art nur mit Wert - `null` hiesse dort "unveraendert".
    var sendsReimbursement = false
    var isCompanyCar: Bool? = nil
    var reimbursementMode: String? = nil
    var reimbursementIncludeFees: Bool? = nil
    var employeeName: String? = nil
    var employeeNumber: String? = nil
    var licensePlate: String? = nil
    var reimbursementMonthlyMail: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, brand, model, ownership
        case isCompanyCar = "is_company_car"
        case reimbursementMode = "reimbursement_mode"
        case reimbursementIncludeFees = "reimbursement_include_fees"
        case employeeName = "employee_name"
        case employeeNumber = "employee_number"
        case licensePlate = "license_plate"
        case reimbursementMonthlyMail = "reimbursement_monthly_mail"
        case externalId = "external_id"
        case batteryCapacityKwh = "battery_capacity_kwh"
        case isActive = "is_active"
        case purchasePrice = "purchase_price"
        case purchaseDate = "purchase_date"
        case firstRegistration = "first_registration"
        case purchaseOdometerKm = "purchase_odometer_km"
        case depreciationMonthlyOverride = "depreciation_monthly_override"
        case leasingRateMonthly = "leasing_rate_monthly"
        case leasingStart = "leasing_start"
        case leasingEnd = "leasing_end"
        case leasingDownPayment = "leasing_down_payment"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(externalId, forKey: .externalId)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(batteryCapacityKwh, forKey: .batteryCapacityKwh)
        try c.encodeIfPresent(isActive, forKey: .isActive)
        if sendsReimbursement {
            try c.encodeIfPresent(isCompanyCar, forKey: .isCompanyCar)
            try c.encodeIfPresent(reimbursementMode.map { ReimbursementMode(raw: $0).rawValue }, forKey: .reimbursementMode)
            try c.encodeIfPresent(reimbursementIncludeFees, forKey: .reimbursementIncludeFees)
            try c.encodeIfPresent(reimbursementMonthlyMail, forKey: .reimbursementMonthlyMail)
            try c.encode(employeeName, forKey: .employeeName)
            try c.encode(employeeNumber, forKey: .employeeNumber)
            try c.encode(licensePlate, forKey: .licensePlate)
        }
        guard sendsOwnership else { return }
        try c.encode(Ownership(raw: ownership).rawValue, forKey: .ownership)
        try c.encode(purchasePrice, forKey: .purchasePrice)
        try c.encode(purchaseDate, forKey: .purchaseDate)
        try c.encode(firstRegistration, forKey: .firstRegistration)
        try c.encode(purchaseOdometerKm, forKey: .purchaseOdometerKm)
        try c.encode(depreciationMonthlyOverride, forKey: .depreciationMonthlyOverride)
        try c.encode(leasingRateMonthly, forKey: .leasingRateMonthly)
        try c.encode(leasingStart, forKey: .leasingStart)
        try c.encode(leasingEnd, forKey: .leasingEnd)
        try c.encode(leasingDownPayment, forKey: .leasingDownPayment)
    }
}

/// Payload fuer Anbieter. Bei PATCH werden nur gesetzte (non-nil) Felder gesendet.
struct ProviderPayload: Codable {
    var name: String?
    var lastPriceAcPerKwh: Double?
    var lastPriceDcPerKwh: Double?
    var notes: String?
    /// "charger" | "vehicle" (Server ab 0.29.0); ein aelterer Server
    /// ignoriert das unbekannte Feld.
    var energyMeter: String? = nil
    /// "home" | "work" | "public" (Server ab 0.31.0); ein aelterer Server
    /// ignoriert das unbekannte Feld.
    var chargingPlace: String? = nil

    enum CodingKeys: String, CodingKey {
        case name, notes
        case lastPriceAcPerKwh = "last_price_ac_per_kwh"
        case lastPriceDcPerKwh = "last_price_dc_per_kwh"
        case energyMeter = "energy_meter"
        case chargingPlace = "charging_place"
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
    /// Jahresrueckblick per Mail (Server ab 0.36.0, Standard an). Fehlt bei
    /// aelteren Servern - dann blendet die App den Schalter aus.
    let notifyYearlyReview: Bool?

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
        case notifyYearlyReview = "notify_yearly_review"
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
    /// Ab Server 0.36.0; `nil` laesst das Feld weg (aelterer Server bzw. der
    /// Wert bleibt serverseitig, wie er ist).
    var notifyYearlyReview: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case notifyBackupFailed = "notify_backup_failed"
        case notifyMyskodaError = "notify_myskoda_error"
        case notifyMonthlyReport = "notify_monthly_report"
        case notifyNewRegistration = "notify_new_registration"
        case reviewDigest = "review_digest"
        case notifyYearlyReview = "notify_yearly_review"
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
    /// Inklusive Grundgebuehren (ab Server 0.27.0).
    let totalCost: Double
    /// Davon Grundgebuehren/Abos.
    var totalFees: Double? = nil

    enum CodingKeys: String, CodingKey {
        case providerName = "provider_name"
        case totalKwh = "total_kwh"
        case totalCost = "total_cost"
        case totalFees = "total_fees"
    }
}

/// Kennzahlen je Ladeort (by_place, Server ab 0.31.0). Leer, solange kein
/// Vorgang im Zeitraum "Zuhause" oder "Arbeit" ist.
struct PlaceStat: Codable, Identifiable {
    var id: String { placeRaw }
    let placeRaw: String
    let sessionCount: Int
    let totalKwh: Double
    /// Inklusive Grundgebuehren.
    let totalCost: Double
    let avgPricePerKwh: Double?

    var place: ChargingPlace { ChargingPlace(raw: placeRaw) }

    enum CodingKeys: String, CodingKey {
        case placeRaw = "place"
        case sessionCount = "session_count"
        case totalKwh = "total_kwh"
        case totalCost = "total_cost"
        case avgPricePerKwh = "avg_price_per_kwh"
    }
}

struct MonthlyStat: Codable, Identifiable {
    var id: String { month }
    let month: String
    let totalCost: Double
    let totalKwh: Double
    let sessionCount: Int
    let avgConsumptionKwhPer100km: Double?
    /// Davon Grundgebuehren/Abos (in `totalCost` enthalten).
    var totalFees: Double? = nil

    enum CodingKeys: String, CodingKey {
        case month
        case totalCost = "total_cost"
        case totalKwh = "total_kwh"
        case sessionCount = "session_count"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
        case totalFees = "total_fees"
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
    /// Grundgebuehren/Abos im Zeitraum, in `totalCost`, `avgPricePerKwh` und
    /// `pricePer100km` bereits enthalten (Server ab 0.27.0).
    var totalFees: Double? = nil
    /// Davon Perioden, in denen es keinen Ladevorgang des Anbieters gab.
    var unallocatedFees: Double? = nil
    /// Zuhause/Arbeit/Unterwegs, siehe `PlaceStat`.
    var byPlace: [PlaceStat]? = nil
    /// Gesamtkosten inkl. sonstiger Kosten und Wertverlust/Leasing (Server ab
    /// 0.32.0). `nil`, solange es zu keinem betrachteten Fahrzeug Kosten oder
    /// eine Kauf-/Leasingangabe gibt - dann blendet das Dashboard den
    /// Abschnitt aus. Lokal gesetzt in AppRepository.fetchStatsSummary.
    var vehicleCosts: VehicleCostSummary? = nil

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
        case totalFees = "total_fees"
        case unallocatedFees = "unallocated_fees"
        case byPlace = "by_place"
        case vehicleCosts = "vehicle_costs"
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

// MARK: - Mehrverbrauch nach Tempo und Temperatur

/// Antwort von `GET /api/stats/drive-breakdown` (Server ab 0.47.0).
///
/// Wie die Temperaturauswertung nur im Server-Modus: das Modell
/// (`drive_breakdown.py`) wird je Fahrzeug aus allen Fahrten mit Tempo
/// angepasst - lokal nachgebaut liefen App und Web auseinander.
struct DriveBreakdownStats: Codable {
    let vehicleId: String?
    let needsVehicle: Bool
    let model: DriveBreakdownModel?
    let drives: [DriveBreakdownPoint]
    let drivesWithoutSpeed: Int
    let minDrives: Int

    enum CodingKeys: String, CodingKey {
        case model, drives
        case vehicleId = "vehicle_id"
        case needsVehicle = "needs_vehicle"
        case drivesWithoutSpeed = "drives_without_speed"
        case minDrives = "min_drives"
    }
}

struct DriveBreakdownModel: Codable {
    /// Verbrauch bei Bezugstempo ohne Heizen/Kuehlen - "dein Normal".
    let normalConsumption: Double
    let referenceSpeedKmh: Double
    let heatBelowC: Double
    let coolAboveC: Double
    let driveCount: Int

    enum CodingKeys: String, CodingKey {
        case normalConsumption = "normal_consumption"
        case referenceSpeedKmh = "reference_speed_kmh"
        case heatBelowC = "heat_below_c"
        case coolAboveC = "cool_above_c"
        case driveCount = "drive_count"
    }
}

/// Eine Fahrt: base + speed + temperature + rest = consumption.
struct DriveBreakdownPoint: Codable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let speedKmh: Double
    let tempC: Double
    let consumptionKwhPer100km: Double
    let base: Double
    let speed: Double
    let temperature: Double
    let rest: Double

    enum CodingKeys: String, CodingKey {
        case base, speed, temperature, rest
        case sessionId = "session_id"
        case speedKmh = "speed_kmh"
        case tempC = "temp_c"
        case consumptionKwhPer100km = "consumption_kwh_per_100km"
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
    /// Reale Reichweite je Temperatur (Server ab 0.34.0). `nil` bei einem
    /// aelteren Server und immer dann, wenn nicht genau EIN Fahrzeug mit
    /// Akkukapazitaet in die Auswertung faellt.
    let range: TempRange?

    enum CodingKeys: String, CodingKey {
        case points, buckets, seasons, trend, range
        case sessionsWithoutTemp = "sessions_without_temp"
        case bucketWidthC = "bucket_width_c"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([TempPoint].self, forKey: .points)
        buckets = try c.decode([TempBucket].self, forKey: .buckets)
        seasons = try c.decode([SeasonStat].self, forKey: .seasons)
        trend = try c.decodeIfPresent(TempTrend.self, forKey: .trend)
        sessionsWithoutTemp = try c.decode(Int.self, forKey: .sessionsWithoutTemp)
        bucketWidthC = try c.decode(Int.self, forKey: .bucketWidthC)
        // Bewusst tolerant: eine unerwartete Form der Reichweite soll nur die
        // Kachel ausblenden, nicht die ganze Temperaturauswertung.
        range = try? c.decodeIfPresent(TempRange.self, forKey: .range)
    }
}

/// Reale Reichweite von 100 auf 0 % je Aussentemperatur (`range_estimate.py`).
///
/// Der Verbrauch ist hier der AB AKKU: ist der Ladeverlust bekannt
/// (`lossPct`), hat der Server ihn aus den an der Ladesaeule gemessenen
/// Fahrten herausgerechnet. Der Akku-Index wird bewusst nicht eingerechnet.
struct TempRange: Codable {
    let vehicleId: String?
    /// Nutzbare Kapazitaet laut Fahrzeug.
    let capacityKwh: Double
    /// `nil`, wenn zu wenige Vorgaenge mit gemessener Energie vorliegen - die
    /// Reichweite faellt dann eher zu niedrig aus.
    let lossPct: Double?
    let measuredFromC: Double?
    let measuredToC: Double?
    /// 5-Grad-Schritte ueber den gemessenen Bereich plus immer 0 und 20 Grad.
    let rows: [TempRangeRow]
    /// Ein Wert je ganzem Grad von -20 bis 40 fuer den Reichweitenrechner;
    /// an den Raendern koennen unplausible Werte fehlen.
    let curve: [TempCurveVertex]

    enum CodingKeys: String, CodingKey {
        case rows, curve
        case vehicleId = "vehicle_id"
        case capacityKwh = "capacity_kwh"
        case lossPct = "loss_pct"
        case measuredFromC = "measured_from_c"
        case measuredToC = "measured_to_c"
    }
}

struct TempRangeRow: Codable, Identifiable {
    var id: Double { tempC }
    let tempC: Double
    let consumptionKwhPer100km: Double
    let rangeKm: Double
    /// Ausserhalb der gemessenen Temperaturen - eine Hochrechnung.
    let extrapolated: Bool

    enum CodingKeys: String, CodingKey {
        case extrapolated
        case tempC = "temp_c"
        case consumptionKwhPer100km = "consumption_kwh_per_100km"
        case rangeKm = "range_km"
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

/// Ein Eckpunkt der Ausgleichskurve - die Punkte ergeben einen Streckenzug.
struct TempCurveVertex: Codable {
    let tempC: Double
    let consumption: Double

    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c"
        case consumption
    }
}

struct TempTrend: Codable {
    /// Beschreiben IMMER die einfache Ausgleichsgerade, auch beim Knickmodell -
    /// deshalb bleiben sie der Rueckfallweg fuer `curve` (aelterer Server).
    let slope: Double
    let intercept: Double
    /// Wieviel der Streuung die Temperatur ueberhaupt erklaert (0…1). Gehoert
    /// zu dem Modell, das der Server tatsaechlich benutzt hat.
    let r2: Double
    let consumptionAt0c: Double
    let consumptionAt20c: Double
    let extraPctAt0c: Double

    /// "linear" oder "breakpoint" (Server ab 0.25.0). Der Verbrauch ueber der
    /// Temperatur ist eine Wanne: unterhalb der Komfortgrenze heizt das
    /// Fahrzeug, oberhalb kuehlt es. Hat der Server dafuer genug Daten, legt er
    /// je eine Gerade nach kalt und nach warm.
    let model: String?
    /// Streckenzug des benutzten Modells: zwei Eckpunkte bei der Geraden, drei
    /// beim Knickmodell. Nur ueber den gemessenen Bereich.
    let curve: [TempCurveVertex]?
    /// Temperatur des geringsten Verbrauchs (nur beim Knickmodell).
    let breakpointC: Double?
    let slopeCold: Double?
    let slopeWarm: Double?
    /// True, wenn 0 °C unter der kaeltesten gemessenen Fahrt liegt - dann ist
    /// die Kennzahl eine Hochrechnung, keine Messung.
    let at0cIsExtrapolated: Bool?

    enum CodingKeys: String, CodingKey {
        case slope, intercept, r2, model, curve
        case consumptionAt0c = "consumption_at_0c"
        case consumptionAt20c = "consumption_at_20c"
        case extraPctAt0c = "extra_pct_at_0c"
        case breakpointC = "breakpoint_c"
        case slopeCold = "slope_cold"
        case slopeWarm = "slope_warm"
        case at0cIsExtrapolated = "at_0c_is_extrapolated"
    }
}
