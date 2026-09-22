import Foundation

/// Reifensaetze und ihre Auswertung (Server ab 0.26.1 fuer die zweite Groesse).
///
/// Bewusst **nur im Server-Modus**: die Zuordnung von Fahrten zu Saetzen und
/// die temperaturbereinigte Rechnung liegen komplett in `tires.py`. Sie lokal
/// nachzubauen hiesse, die Kurve aus `temperature.py` ein zweites Mal zu
/// implementieren - mit der Aussicht, dass App und Web frueher oder spaeter
/// andere Zahlen zeigen. Dieselbe Entscheidung wie bei der
/// Temperaturauswertung auf dem Dashboard.

enum TireKind: String, Codable, CaseIterable, Identifiable {
    case summer
    case winter
    case allSeason = "all_season"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summer: return String(localized: "Sommer")
        case .winter: return String(localized: "Winter")
        case .allSeason: return String(localized: "Ganzjahr")
        }
    }

    var symbolName: String {
        switch self {
        case .summer: return "sun.max"
        case .winter: return "snowflake"
        case .allSeason: return "calendar"
        }
    }
}

/// Eine MONTAGE, kein physischer Satz: wird derselbe Reifen im Herbst wieder
/// aufgezogen, ist das ein zweiter Eintrag. Ein Enddatum gibt es deshalb
/// nicht - der naechste Wechsel beendet den vorherigen Satz.
struct TireSet: Codable, Identifiable, Hashable {
    let id: String
    let vehicleId: String
    let kind: TireKind
    let installedOn: Date
    /// Kilometerstand beim Wechsel. Optional, aber die genauere Quelle fuer die
    /// Laufleistung: die Differenz zweier Wechsel enthaelt auch die Fahrt, die
    /// ueber den Wechsel hinweg lief und keinem Satz zugeordnet werden kann.
    let odometerKm: Double?
    /// Groesse aller vier Raeder - oder, wenn `sizeRear` gesetzt ist, die der
    /// Vorderachse (Mischbereifung).
    let size: String?
    let sizeRear: String?
    let brand: String?
    let model: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, size, brand, model, notes
        case vehicleId = "vehicle_id"
        case installedOn = "installed_on"
        case odometerKm = "odometer_km"
        case sizeRear = "size_rear"
    }

    /// Bei Mischbereifung beide Achsen ("vorne / hinten"), sonst die eine
    /// Groesse - dieselbe Regel wie serverseitig in `tires.py::size_label()`.
    var sizeLabel: String {
        if let size, let sizeRear, !size.isEmpty, !sizeRear.isEmpty {
            return "\(size) / \(sizeRear)"
        }
        return [size, sizeRear].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? ""
    }

    /// Marke, Modell und Groesse in einer Zeile - leere Felder fallen weg.
    var label: String {
        [brand, model, sizeLabel.isEmpty ? nil : sizeLabel]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
    }
}

struct TireSetPayload: Codable {
    /// Beim Bearbeiten laesst der Server das Fahrzeug unveraendert (das Feld
    /// fehlt dort im Schema), deshalb optional.
    let vehicleId: String?
    let kind: TireKind
    let installedOn: Date
    let odometerKm: Double?
    let size: String?
    let sizeRear: String?
    let brand: String?
    let model: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case kind, size, brand, model, notes
        case vehicleId = "vehicle_id"
        case installedOn = "installed_on"
        case odometerKm = "odometer_km"
        case sizeRear = "size_rear"
    }

    /// Leere Textfelder werden als `null` GESCHICKT, nicht weggelassen: der
    /// Server wendet `exclude_unset` an, ein fehlendes Feld liesse den alten
    /// Wert stehen - eine geleerte Marke waere also nicht zu loeschen. Das
    /// Fahrzeug dagegen faellt beim Bearbeiten bewusst weg (das Schema dort
    /// kennt es nicht, es bleibt unveraenderlich).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(vehicleId, forKey: .vehicleId)
        try container.encode(kind, forKey: .kind)
        try container.encode(installedOn, forKey: .installedOn)
        try container.encode(odometerKm, forKey: .odometerKm)
        try container.encode(size, forKey: .size)
        try container.encode(sizeRear, forKey: .sizeRear)
        try container.encode(brand, forKey: .brand)
        try container.encode(model, forKey: .model)
        try container.encode(notes, forKey: .notes)
    }
}

/// Kennzahlen einer einzelnen Montage. `removedOn` leitet der Server ab (der
/// naechste Wechsel an diesem Fahrzeug) - nil heisst "liegt noch drauf".
struct TireMounting: Codable, Identifiable {
    let tireSetId: String
    let vehicleId: String
    let kind: TireKind
    let label: String
    let installedOn: Date
    let removedOn: Date?
    let isCurrent: Bool
    let days: Int
    let drives: Int
    let km: Double
    /// "odometer" (Differenz der Kilometerstaende, exakt) oder "drives" (Summe
    /// der zugeordneten Fahrten - die Fahrt ueber den Wechsel fehlt dort).
    let kmSource: String?
    let energyKwh: Double
    let avgConsumptionKwhPer100km: Double?

    var id: String { tireSetId }
    var kmIsExact: Bool { kmSource == "odometer" }

    enum CodingKeys: String, CodingKey {
        case kind, label, days, drives, km
        case kmSource = "km_source"
        case tireSetId = "tire_set_id"
        case vehicleId = "vehicle_id"
        case installedOn = "installed_on"
        case removedOn = "removed_on"
        case isCurrent = "is_current"
        case energyKwh = "energy_kwh"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
    }
}

/// Ein Satz ueber alle seine Montagen hinweg - erst so ergibt "wieviel km sind
/// da drauf" eine Zahl.
struct TireSetSummary: Codable, Identifiable {
    let key: String
    let label: String
    let kind: TireKind
    let mountings: Int
    let firstInstalledOn: Date
    /// Alter seit der ersten Montage. Steht neben `daysMounted`, weil Gummi
    /// auch im Keller altert, die Laufleistung aber nicht.
    let ageDays: Int
    let daysMounted: Int
    let drives: Int
    let km: Double
    /// "odometer" nur, wenn JEDE Montage dieses Satzes gemessene Kilometer hat.
    let kmSource: String?
    let energyKwh: Double
    let isCurrent: Bool
    let avgConsumptionKwhPer100km: Double?

    var id: String { key }
    var kmIsExact: Bool { kmSource == "odometer" }

    enum CodingKeys: String, CodingKey {
        case key, label, kind, mountings, drives, km
        case kmSource = "km_source"
        case firstInstalledOn = "first_installed_on"
        case ageDays = "age_days"
        case daysMounted = "days_mounted"
        case energyKwh = "energy_kwh"
        case isCurrent = "is_current"
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
    }
}

struct TireOverview: Codable {
    let mountings: [TireMounting]
    let sets: [TireSetSummary]
    let drivesWithoutSet: Int
    let drivesSpanningChange: Int

    enum CodingKeys: String, CodingKey {
        case mountings, sets
        case drivesWithoutSet = "drives_without_set"
        case drivesSpanningChange = "drives_spanning_change"
    }
}

struct TireGroup: Codable, Identifiable {
    let key: String
    let label: String
    let kind: TireKind
    let drives: Int
    let km: Double
    let avgConsumptionKwhPer100km: Double
    let avgTempC: Double
    let minTempC: Double
    let maxTempC: Double
    /// Erst dieser Wert ist zwischen den Gruppen vergleichbar: der rohe
    /// Durchschnitt misst vor allem, bei welchen Temperaturen gefahren wurde.
    let adjustedConsumptionKwhPer100km: Double?
    let deltaPctVsModel: Double?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, kind, drives, km
        case avgConsumptionKwhPer100km = "avg_consumption_kwh_per_100km"
        case avgTempC = "avg_temp_c"
        case minTempC = "min_temp_c"
        case maxTempC = "max_temp_c"
        case adjustedConsumptionKwhPer100km = "adjusted_consumption_kwh_per_100km"
        case deltaPctVsModel = "delta_pct_vs_model"
    }
}

struct TireComparison: Codable {
    let byKind: [TireGroup]
    let bySet: [TireGroup]
    let referenceTempC: Double?
    let r2: Double?
    let drivesWithoutSet: Int
    let drivesSpanningChange: Int
    /// Gemeinsamer Temperaturbereich der Arten. Ohne ihn rechnet das Modell
    /// jeden Satz in Temperaturen hoch, in denen er nie gefahren ist - die
    /// Ansicht sagt das dann auch, statt die Zahl unkommentiert zu zeigen.
    let overlapSpanC: Double?
    let overlapOk: Bool
    let winterVsSummerPct: Double?

    enum CodingKeys: String, CodingKey {
        case r2
        case byKind = "by_kind"
        case bySet = "by_set"
        case referenceTempC = "reference_temp_c"
        case drivesWithoutSet = "drives_without_set"
        case drivesSpanningChange = "drives_spanning_change"
        case overlapSpanC = "overlap_span_c"
        case overlapOk = "overlap_ok"
        case winterVsSummerPct = "winter_vs_summer_pct"
    }
}
