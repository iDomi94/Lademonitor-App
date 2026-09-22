import Foundation
import SwiftData

/// Rhythmus einer Grundgebuehr (Server ab 0.27.0, `models.FeeInterval`).
enum FeeInterval: String, Codable, CaseIterable, Identifiable {
    case monthly
    case yearly
    case once

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly: return String(localized: "Monatlich")
        case .yearly: return String(localized: "Jährlich")
        case .once: return String(localized: "Einmalig (Zeitraum)")
        }
    }

    /// Kurzform hinter dem Betrag ("15,00 € / Monat").
    var perLabel: String {
        switch self {
        case .monthly: return String(localized: "/ Monat")
        case .yearly: return String(localized: "/ Jahr")
        case .once: return String(localized: "einmalig")
        }
    }
}

/// Grundgebuehr bzw. Abo eines Anbieters, z.B. Ionity Powerpass 15 € im Monat.
///
/// Haengt am Anbieter, nicht am Ladevorgang: umgelegt wird sie erst beim
/// Anzeigen, nach kWh auf alle Ladevorgaenge des Anbieters in der Periode
/// (siehe LocalFeeAllocator). `priceTotal` eines Ladevorgangs bleibt der an
/// der Saeule bezahlte Betrag.
///
/// `startDate`/`endDate` sind reine Kalendertage (lokale Mitternacht) - der
/// Server kennt sie als naive datetime um 00:00 und verwirft jede Uhrzeit.
struct ProviderFee: Codable, Identifiable, Hashable {
    let id: String
    var providerId: String
    var amount: Double
    var interval: FeeInterval
    var startDate: Date
    /// Letzter Tag, an dem die Gebuehr gilt (inklusive). Bei `.once` Pflicht,
    /// sonst optional (= Kuendigung).
    var endDate: Date?
    var label: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, interval, label, notes
        case providerId = "provider_id"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// Payload fuer POST/PATCH /api/provider-fees.
///
/// Anders als die uebrigen Payloads schreibt sie JEDES Feld, auch `nil` als
/// `null`: sonst liesse sich ein einmal gesetztes Enddatum (Kuendigung) per
/// PATCH nie wieder entfernen - der Server uebernimmt nur Felder, die im
/// JSON stehen. `null` bei Anbieter/Betrag/Rhythmus/Beginn ignoriert er.
struct ProviderFeePayload: Encodable {
    var providerId: String
    var amount: Double
    var interval: FeeInterval
    var startDate: Date
    var endDate: Date?
    var label: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case amount, interval, label, notes
        case providerId = "provider_id"
        case startDate = "start_date"
        case endDate = "end_date"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providerId, forKey: .providerId)
        try c.encode(amount, forKey: .amount)
        try c.encode(interval, forKey: .interval)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(label, forKey: .label)
        try c.encode(notes, forKey: .notes)
    }
}

/// SwiftData-Spiegel einer Grundgebuehr, mit denselben Sync-Metadaten wie
/// die vier Kern-Entitaeten (siehe LocalModels.swift). Eine neue Entitaet ist
/// fuer SwiftData eine leichte Migration - bestehende Stores bekommen die
/// Tabelle einfach dazu.
@Model
final class LocalProviderFee {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    /// Zeigt auf `LocalProvider.serverId ?? localId.uuidString`, wie
    /// LocalChargingSession.providerId.
    var providerId: String
    var amount: Double
    var interval: String
    var startDate: Date
    var endDate: Date?
    var label: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        providerId: String,
        amount: Double,
        interval: String = FeeInterval.monthly.rawValue,
        startDate: Date,
        endDate: Date? = nil,
        label: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.providerId = providerId
        self.amount = amount
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.label = label
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }

    var asDTO: ProviderFee {
        ProviderFee(
            id: serverId ?? localId.uuidString,
            providerId: providerId,
            amount: amount,
            interval: FeeInterval(rawValue: interval) ?? .monthly,
            startDate: startDate,
            endDate: endDate,
            label: label,
            notes: notes
        )
    }
}

extension LocalProviderFee: SyncMirrorable {}
