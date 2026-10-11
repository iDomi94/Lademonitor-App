import Foundation
import SwiftData

/// Kauf oder Leasing eines Fahrzeugs (Server ab 0.32.0, `Vehicle.ownership`).
/// Rohwerte wie vom Server; fehlend oder unbekannt heisst "keine Angabe".
enum Ownership: String, CaseIterable, Identifiable {
    case none
    case purchase
    case leasing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return String(localized: "Keine Angabe")
        case .purchase: return String(localized: "Kauf")
        case .leasing: return String(localized: "Leasing")
        }
    }

    init(raw: String?) {
        self = raw.flatMap(Ownership.init(rawValue:)) ?? Ownership.none
    }
}

/// Wiederholung eines Kosteneintrags. Anders als bei den Grundgebuehren ist
/// `once` eine einzelne Zahlung am Datum, kein Zeitraum.
enum CostInterval: String, Codable, CaseIterable, Identifiable {
    case once
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: return String(localized: "Einmalig")
        case .monthly: return String(localized: "Monatlich")
        case .yearly: return String(localized: "Jährlich")
        }
    }
}

/// Feste Kategorienliste wie `vehicle_costs.CATEGORIES` im Server, "other"
/// faengt den Rest.
enum CostCategory: String, CaseIterable, Identifiable {
    case insurance
    case tax
    case maintenance
    case repair
    case tires
    case wallbox
    case parking
    case toll
    case cleaning
    case other

    var id: String { rawValue }

    init(raw: String?) {
        self = raw.flatMap(CostCategory.init(rawValue:)) ?? .other
    }

    var displayName: String { CostCategory.displayName(raw: rawValue) }

    /// Anzeigename fuer jede Kategorie der Auswertung - auch die drei, die es
    /// nur dort gibt ("charging", "depreciation", "leasing").
    static func displayName(raw: String) -> String {
        switch raw {
        case "charging": return String(localized: "Laden")
        case "depreciation": return String(localized: "Wertverlust")
        case "leasing": return String(localized: "Leasing")
        case "insurance": return String(localized: "Versicherung")
        case "tax": return String(localized: "Kfz-Steuer")
        case "maintenance": return String(localized: "Wartung/Inspektion")
        case "repair": return String(localized: "Reparatur")
        case "tires": return String(localized: "Reifen")
        case "wallbox": return String(localized: "Wallbox/Zubehör")
        case "parking": return String(localized: "Parken")
        case "toll": return String(localized: "Maut/Vignette")
        case "cleaning": return String(localized: "Wäsche/Pflege")
        default: return String(localized: "Sonstiges")
        }
    }
}

/// Sonstige Kosten eines Fahrzeugs (Server ab 0.32.0, `models.VehicleCost`):
/// Versicherung, Steuer, Wartung, ... Ein wiederkehrender Betrag ist EINE
/// Zeile; die Zahlungstermine erzeugt LocalVehicleCostCalculator.occurrences().
///
/// `startDate`/`endDate` sind reine Kalendertage wie bei ProviderFee.
struct VehicleCost: Codable, Identifiable, Hashable {
    let id: String
    var vehicleId: String
    var amount: Double
    /// Roh, damit eine Kategorie aus einem neueren Server nicht das Decodieren
    /// der ganzen Liste scheitern laesst - siehe `categoryValue`.
    var category: String
    var interval: CostInterval
    /// Datum der (ersten) Zahlung.
    var startDate: Date
    /// Nur bei wiederkehrenden: letzter Tag, an dem noch gezahlt wird.
    var endDate: Date?
    var odometerKm: Int?
    var label: String?
    var notes: String?

    var categoryValue: CostCategory { CostCategory(raw: category) }

    enum CodingKeys: String, CodingKey {
        case id, amount, category, interval, label, notes
        case vehicleId = "vehicle_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case odometerKm = "odometer_km"
    }
}

/// Payload fuer POST/PATCH /api/vehicle-costs. Schreibt wie
/// ProviderFeePayload JEDES Feld, auch `nil` als `null` - sonst liessen sich
/// Enddatum, km-Stand, Bezeichnung oder Notiz per PATCH nie wieder leeren.
struct VehicleCostPayload: Encodable {
    var vehicleId: String
    var amount: Double
    var category: String
    var interval: CostInterval
    var startDate: Date
    var endDate: Date?
    var odometerKm: Int?
    var label: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case amount, category, interval, label, notes
        case vehicleId = "vehicle_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case odometerKm = "odometer_km"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(amount, forKey: .amount)
        try c.encode(category, forKey: .category)
        try c.encode(interval, forKey: .interval)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(odometerKm, forKey: .odometerKm)
        try c.encode(label, forKey: .label)
        try c.encode(notes, forKey: .notes)
    }
}

/// SwiftData-Spiegel eines Kosteneintrags, mit denselben Sync-Metadaten wie
/// LocalProviderFee. Eine neue Entitaet ist fuer SwiftData eine leichte
/// Migration.
@Model
final class LocalVehicleCost {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    /// Zeigt auf `LocalVehicle.serverId ?? localId.uuidString`, wie
    /// LocalChargingSession.vehicleId.
    var vehicleId: String
    var amount: Double
    var category: String
    var interval: String
    var startDate: Date
    var endDate: Date?
    var odometerKm: Int?
    var label: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        vehicleId: String,
        amount: Double,
        category: String = CostCategory.other.rawValue,
        interval: String = CostInterval.once.rawValue,
        startDate: Date,
        endDate: Date? = nil,
        odometerKm: Int? = nil,
        label: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.vehicleId = vehicleId
        self.amount = amount
        self.category = category
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.odometerKm = odometerKm
        self.label = label
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }

    var asDTO: VehicleCost {
        VehicleCost(
            id: serverId ?? localId.uuidString,
            vehicleId: vehicleId,
            amount: amount,
            category: category,
            interval: CostInterval(rawValue: interval) ?? .once,
            startDate: startDate,
            endDate: endDate,
            odometerKm: odometerKm,
            label: label,
            notes: notes
        )
    }
}

extension LocalVehicleCost: SyncMirrorable {}

/// Ein Posten der Gesamtkosten: "charging", "depreciation", "leasing" oder
/// eine der `CostCategory`-Kategorien.
struct CostCategoryStat: Codable, Identifiable, Hashable {
    var id: String { category }
    let category: String
    let amount: Double
}

/// Gesamtkosten im Zeitraum (Dashboard-Abschnitt "Gesamtkosten"), wie
/// `schemas.VehicleCostSummary`. Lokal berechnet von
/// LocalVehicleCostCalculator.summary(); die uebrigen Kennzahlen der
/// StatsSummary bleiben reine Ladekosten.
struct VehicleCostSummary: Codable {
    let chargingCost: Double
    let otherCost: Double
    /// Wertverlust bzw. Leasing.
    let ownershipCost: Double
    let totalCost: Double
    let costPerKm: Double?
    /// Groesster Posten zuerst.
    let byCategory: [CostCategoryStat]

    enum CodingKeys: String, CodingKey {
        case chargingCost = "charging_cost"
        case otherCost = "other_cost"
        case ownershipCost = "ownership_cost"
        case totalCost = "total_cost"
        case costPerKm = "cost_per_km"
        case byCategory = "by_category"
    }
}

/// Kosten eines Kalenderjahres je Kategorie (Liste "Kosten" am Fahrzeug).
struct YearCostStat: Identifiable {
    var id: Int { year }
    let year: Int
    let total: Double
    let byCategory: [CostCategoryStat]
}
