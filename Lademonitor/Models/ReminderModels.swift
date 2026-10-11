import Foundation
import SwiftData

/// Art einer Erinnerung (Server ab 0.33.0, `reminders.KINDS`). Bestimmt die
/// Vorlage beim Anlegen, ob "Erledigt" vom alten Faelligkeitstag aus
/// weiterrechnet (`isFixedDate`) und welche Kostenkategorie es vorschlaegt.
enum ReminderKind: String, CaseIterable, Identifiable {
    case hu
    case inspection
    case brakeFluid = "brake_fluid"
    case tireWinter = "tire_winter"
    case tireSummer = "tire_summer"
    case insurance
    case tax
    case thg
    case custom

    var id: String { rawValue }

    /// Unbekannte Arten (neuerer Server) zaehlen als "Eigene".
    init(raw: String?) {
        self = raw.flatMap(ReminderKind.init(rawValue:)) ?? .custom
    }

    var displayName: String {
        switch self {
        case .hu: return String(localized: "HU/TÜV")
        case .inspection: return String(localized: "Inspektion")
        case .brakeFluid: return String(localized: "Bremsflüssigkeit")
        case .tireWinter: return String(localized: "Reifenwechsel Winter")
        case .tireSummer: return String(localized: "Reifenwechsel Sommer")
        case .insurance: return String(localized: "Versicherung")
        case .tax: return String(localized: "Kfz-Steuer")
        case .thg: return String(localized: "THG-Quote")
        case .custom: return String(localized: "Eigene")
        }
    }

    var systemImage: String {
        switch self {
        case .hu: return "checkmark.seal"
        case .inspection: return "wrench.and.screwdriver"
        case .brakeFluid: return "drop"
        case .tireWinter: return "snowflake"
        case .tireSummer: return "sun.max"
        case .insurance: return "shield"
        case .tax: return "building.columns"
        case .thg: return "leaf"
        case .custom: return "bell"
        }
    }
}

/// Status einer Erinnerung, wie `ReminderOut.status` im Server - hier aber
/// immer lokal gerechnet (LocalReminderCalculator.evaluate).
enum ReminderStatus: String {
    case ok
    case dueSoon = "due_soon"
    case overdue
    case done

    /// Wie `reminders.STATUS_RANK`: hoeher = dringender.
    var rank: Int {
        switch self {
        case .ok, .done: return 0
        case .dueSoon: return 1
        case .overdue: return 2
        }
    }

    var displayName: String {
        switch self {
        case .ok: return String(localized: "ok")
        case .dueSoon: return String(localized: "bald fällig")
        case .overdue: return String(localized: "überfällig")
        case .done: return String(localized: "erledigt")
        }
    }
}

/// Eine Erinnerung je Fahrzeug (Server ab 0.33.0, `models.Reminder`).
/// Gespeichert ist nur die NAECHSTE Faelligkeit (Datum und/oder km-Stand);
/// Status und km-Prognose rechnet die App selbst, auch im Server-Modus -
/// die nur lesenden Felder der Server-Antwort (status, current_km,
/// km_forecast_date, ...) werden bewusst nicht gelesen. Die reinen
/// Datumsangaben darunter ("2026-10-10") koennte der Decoder ohnehin nicht.
struct Reminder: Codable, Identifiable, Hashable {
    let id: String
    var vehicleId: String
    /// Roh, damit eine Art aus einem neueren Server nicht das Decodieren der
    /// ganzen Liste scheitern laesst - siehe `kindValue`.
    var kind: String
    var title: String?
    /// Reiner Kalendertag.
    var dueDate: Date?
    var dueKm: Int?
    var repeatMonths: Int?
    var repeatKm: Int?
    var leadDays: Int
    var leadKm: Int
    var notes: String?
    var lastDoneDate: Date?
    var lastDoneKm: Int?

    var kindValue: ReminderKind { ReminderKind(raw: kind) }

    /// Bezeichnung oder, wenn leer, der Name der Vorlage.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return kindValue.displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, notes
        case vehicleId = "vehicle_id"
        case dueDate = "due_date"
        case dueKm = "due_km"
        case repeatMonths = "repeat_months"
        case repeatKm = "repeat_km"
        case leadDays = "lead_days"
        case leadKm = "lead_km"
        case lastDoneDate = "last_done_date"
        case lastDoneKm = "last_done_km"
    }

    init(
        id: String, vehicleId: String, kind: String, title: String? = nil, dueDate: Date? = nil,
        dueKm: Int? = nil, repeatMonths: Int? = nil, repeatKm: Int? = nil, leadDays: Int = 30,
        leadKm: Int = 1000, notes: String? = nil, lastDoneDate: Date? = nil, lastDoneKm: Int? = nil
    ) {
        self.id = id
        self.vehicleId = vehicleId
        self.kind = kind
        self.title = title
        self.dueDate = dueDate
        self.dueKm = dueKm
        self.repeatMonths = repeatMonths
        self.repeatKm = repeatKm
        self.leadDays = leadDays
        self.leadKm = leadKm
        self.notes = notes
        self.lastDoneDate = lastDoneDate
        self.lastDoneKm = lastDoneKm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        vehicleId = try c.decode(String.self, forKey: .vehicleId)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ReminderKind.custom.rawValue
        title = try c.decodeIfPresent(String.self, forKey: .title)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        dueKm = try c.decodeIfPresent(Int.self, forKey: .dueKm)
        repeatMonths = try c.decodeIfPresent(Int.self, forKey: .repeatMonths)
        repeatKm = try c.decodeIfPresent(Int.self, forKey: .repeatKm)
        leadDays = try c.decodeIfPresent(Int.self, forKey: .leadDays) ?? 30
        leadKm = try c.decodeIfPresent(Int.self, forKey: .leadKm) ?? 1000
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        lastDoneDate = try c.decodeIfPresent(Date.self, forKey: .lastDoneDate)
        lastDoneKm = try c.decodeIfPresent(Int.self, forKey: .lastDoneKm)
    }
}

/// Payload fuer POST/PATCH /api/reminders. Schreibt JEDES Feld, auch `nil` als
/// `null` (wie VehicleCostPayload) - sonst liessen sich Faelligkeit,
/// Wiederholung, Bezeichnung oder Notiz per PATCH nie wieder leeren.
///
/// "Erledigt" geht bewusst NICHT ueber `POST /{id}/complete`: die App rechnet
/// die neue Faelligkeit selbst (LocalReminderCalculator.nextDue) und schickt
/// sie per PATCH - so verhalten sich Local-Only- und Server-Modus gleich, und
/// ein offline erledigter Eintrag geht beim naechsten Sync einfach mit hoch.
struct ReminderPayload: Encodable {
    var vehicleId: String
    var kind: String
    var title: String?
    var dueDate: Date?
    var dueKm: Int?
    var repeatMonths: Int?
    var repeatKm: Int?
    var leadDays: Int
    var leadKm: Int
    var notes: String?
    var lastDoneDate: Date?
    var lastDoneKm: Int?

    enum CodingKeys: String, CodingKey {
        case kind, title, notes
        case vehicleId = "vehicle_id"
        case dueDate = "due_date"
        case dueKm = "due_km"
        case repeatMonths = "repeat_months"
        case repeatKm = "repeat_km"
        case leadDays = "lead_days"
        case leadKm = "lead_km"
        case lastDoneDate = "last_done_date"
        case lastDoneKm = "last_done_km"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(dueKm, forKey: .dueKm)
        try c.encode(repeatMonths, forKey: .repeatMonths)
        try c.encode(repeatKm, forKey: .repeatKm)
        try c.encode(leadDays, forKey: .leadDays)
        try c.encode(leadKm, forKey: .leadKm)
        try c.encode(notes, forKey: .notes)
        try c.encode(lastDoneDate, forKey: .lastDoneDate)
        try c.encode(lastDoneKm, forKey: .lastDoneKm)
    }
}

extension Reminder {
    /// Der Payload, der diese Erinnerung unveraendert beschreibt - Ausgangspunkt
    /// fuer "Erledigt".
    var asPayload: ReminderPayload {
        ReminderPayload(
            vehicleId: vehicleId, kind: kind, title: title, dueDate: dueDate, dueKm: dueKm,
            repeatMonths: repeatMonths, repeatKm: repeatKm, leadDays: leadDays, leadKm: leadKm,
            notes: notes, lastDoneDate: lastDoneDate, lastDoneKm: lastDoneKm
        )
    }
}

/// SwiftData-Spiegel einer Erinnerung, mit denselben Sync-Metadaten wie
/// LocalVehicleCost. Neue Entitaet = leichte Migration; alle Felder haben
/// trotzdem Vorgaben, damit spaetere Ergaenzungen ebenso leicht bleiben.
@Model
final class LocalReminder {
    @Attribute(.unique) var localId: UUID = UUID()
    var serverId: String? = nil
    /// Zeigt auf `LocalVehicle.serverId ?? localId.uuidString`, wie
    /// LocalVehicleCost.vehicleId.
    var vehicleId: String = ""
    var kind: String = ReminderKind.custom.rawValue
    var title: String? = nil
    var dueDate: Date? = nil
    var dueKm: Int? = nil
    var repeatMonths: Int? = nil
    var repeatKm: Int? = nil
    var leadDays: Int = 30
    var leadKm: Int = 1000
    var notes: String? = nil
    var lastDoneDate: Date? = nil
    var lastDoneKm: Int? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var pendingDelete: Bool = false

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        vehicleId: String,
        kind: String = ReminderKind.custom.rawValue,
        isDirty: Bool = true
    ) {
        self.localId = localId
        self.serverId = serverId
        self.vehicleId = vehicleId
        self.kind = kind
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDirty = isDirty
        self.pendingDelete = false
    }

    /// Uebernimmt alle Fachfelder (nicht die Sync-Metadaten).
    func apply(_ dto: Reminder) {
        vehicleId = dto.vehicleId
        kind = dto.kind
        title = dto.title
        dueDate = dto.dueDate
        dueKm = dto.dueKm
        repeatMonths = dto.repeatMonths
        repeatKm = dto.repeatKm
        leadDays = dto.leadDays
        leadKm = dto.leadKm
        notes = dto.notes
        lastDoneDate = dto.lastDoneDate
        lastDoneKm = dto.lastDoneKm
    }

    var asDTO: Reminder {
        Reminder(
            id: serverId ?? localId.uuidString,
            vehicleId: vehicleId,
            kind: kind,
            title: title,
            dueDate: dueDate,
            dueKm: dueKm,
            repeatMonths: repeatMonths,
            repeatKm: repeatKm,
            leadDays: leadDays,
            leadKm: leadKm,
            notes: notes,
            lastDoneDate: lastDoneDate,
            lastDoneKm: lastDoneKm
        )
    }
}

extension LocalReminder: SyncMirrorable {}

/// Erinnerung samt lokal gerechnetem Zustand, fertig fuer Liste, Dashboard
/// und Mitteilungen.
struct ReminderItem: Identifiable, Hashable {
    var id: String { reminder.id }
    let reminder: Reminder
    let state: LocalReminderCalculator.State
    let currentKm: Int?
    let vehicleName: String?
}
