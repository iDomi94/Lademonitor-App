import Foundation
import SwiftData

/// Erstattungsart eines Dienstwagens (Server ab 0.35.0,
/// `Vehicle.reimbursement_mode`). Fehlend oder unbekannt heisst pauschal, wie
/// serverseitig.
enum ReimbursementMode: String, CaseIterable, Identifiable {
    case flat
    case actual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return String(localized: "Pauschal je kWh")
        case .actual: return String(localized: "Tatsächliche Kosten")
        }
    }

    init(raw: String?) {
        self = raw.flatMap(ReimbursementMode.init(rawValue:)) ?? .flat
    }
}

/// Herkunft der kWh eines Vorgangs im Erstattungsbericht - wie
/// `reimbursement.kwh_source` im Server.
enum ReimbursementKwhSource: String {
    case charger
    case vehicle
    case estimated

    var displayName: String {
        switch self {
        case .charger: return String(localized: "Wallbox")
        case .vehicle: return String(localized: "Fahrzeug")
        case .estimated: return String(localized: "geschätzt")
        }
    }
}

/// Erstattungssatz je kWh eines Dienstwagens (Server ab 0.35.0,
/// `models.ReimbursementRate`): gilt ab `validFrom` (reiner Kalendertag) bis
/// zum naechsten Satz desselben Fahrzeugs.
struct ReimbursementRate: Codable, Identifiable, Hashable {
    let id: String
    var vehicleId: String
    var validFrom: Date
    var ratePerKwh: Double

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleId = "vehicle_id"
        case validFrom = "valid_from"
        case ratePerKwh = "rate_per_kwh"
    }

    /// Vorschlag fuer den ersten Satz (Pauschale 2026), gueltig ab dem 1.1.
    /// des laufenden Jahres - wie `reimbursement.DEFAULT_RATE_PER_KWH`.
    static let defaultRatePerKwh = 0.34

    static var defaultValidFrom: Date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: Date())
    }
}

/// Payload fuer POST/PATCH /api/reimbursement/rates - alle Felder.
struct ReimbursementRatePayload: Encodable {
    var vehicleId: String
    var validFrom: Date
    var ratePerKwh: Double

    enum CodingKeys: String, CodingKey {
        case vehicleId = "vehicle_id"
        case validFrom = "valid_from"
        case ratePerKwh = "rate_per_kwh"
    }
}

/// SwiftData-Spiegel eines Erstattungssatzes, mit denselben Sync-Metadaten
/// wie LocalVehicleCost. Eine neue Entitaet ist fuer SwiftData eine leichte
/// Migration.
@Model
final class LocalReimbursementRate {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    /// Zeigt auf `LocalVehicle.serverId ?? localId.uuidString`, wie
    /// LocalVehicleCost.vehicleId.
    var vehicleId: String
    var validFrom: Date
    var ratePerKwh: Double
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        vehicleId: String,
        validFrom: Date,
        ratePerKwh: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.vehicleId = vehicleId
        self.validFrom = validFrom
        self.ratePerKwh = ratePerKwh
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }

    var asDTO: ReimbursementRate {
        ReimbursementRate(
            id: serverId ?? localId.uuidString,
            vehicleId: vehicleId,
            validFrom: validFrom,
            ratePerKwh: ratePerKwh
        )
    }
}

extension LocalReimbursementRate: SyncMirrorable {}

// MARK: - Bericht (lokal gerechnet, LocalReimbursementCalculator)

/// Eine Zeile des Berichts, wie `schemas.ReimbursementRowOut`.
struct ReimbursementRow: Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let startTime: Date
    let energyKwh: Double?
    let kwhSource: ReimbursementKwhSource
    let odometerKm: Int?
    let ratePerKwh: Double?
    let feeShare: Double
    let amount: Double?
}

/// Summe eines Monats ("YYYY-MM"), wie `schemas.ReimbursementMonthOut`.
struct ReimbursementMonth: Identifiable {
    var id: String { month }
    let month: String
    let sessions: Int
    let energyKwh: Double
    let estimatedKwh: Double
    let amount: Double
}

/// Der ganze Bericht, wie `schemas.ReimbursementReportOut`.
struct ReimbursementReport {
    let vehicleId: String
    let vehicleName: String
    let licensePlate: String?
    let employeeName: String?
    let employeeNumber: String?
    let mode: ReimbursementMode
    let includeFees: Bool
    /// Reine Kalendertage, beide inklusive.
    let dateFrom: Date
    let dateTo: Date
    let rows: [ReimbursementRow]
    let months: [ReimbursementMonth]
    let totalKwh: Double
    let estimatedKwh: Double
    let estimatedSessions: Int
    let missingAmountSessions: Int
    let totalAmount: Double
}
