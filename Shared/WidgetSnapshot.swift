import Foundation

/// Was das Homescreen-Widget anzeigt. Die App schreibt es in den gemeinsamen
/// App-Group-Speicher, das Widget liest es nur.
///
/// Bewusst ein fertig gerechneter Stand statt eines eigenen Datenzugriffs im
/// Widget: die Monatskosten brauchen die Grundgebuehren-Umlage und im
/// Server-Modus den Sync - beides lebt in der App. Das Widget zeigt deshalb
/// den Stand vom letzten Oeffnen bzw. Speichern; `updatedAt` steht dabei.
///
/// Liegt in `Shared/` und gehoert zu BEIDEN Targets (App und Widget).
struct WidgetSnapshot: Codable, Equatable {
    struct LastSession: Codable, Equatable {
        let startTime: Date
        let energyKwh: Double?
        /// Saeulenpreis plus Grundgebuehrenanteil.
        let cost: Double?
        let providerName: String?
        let socStart: Int?
        let socEnd: Int?
    }

    /// Erster Tag des Monats, fuer den die Summen gelten.
    let month: Date
    let monthSessions: Int
    let monthKwh: Double
    /// Inklusive Grundgebuehren, wie im Dashboard.
    let monthCost: Double
    let lastSession: LastSession?
    let updatedAt: Date

    static let appGroup = "group.com.dominiqueherbrigpersonalteam.Lademonitor"
    static let widgetKind = "LademonitorWidget"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// true, wenn sich etwas geaendert hat (dann lohnt ein Neuladen des Widgets).
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        if let old = load(), old.sameContent(as: snapshot) { return false }
        defaults.set(data, forKey: key)
        return true
    }

    private func sameContent(as other: WidgetSnapshot) -> Bool {
        month == other.month && monthSessions == other.monthSessions
            && monthKwh == other.monthKwh && monthCost == other.monthCost
            && lastSession == other.lastSession
    }

    static let placeholder = WidgetSnapshot(
        month: Date(), monthSessions: 6, monthKwh: 214.5, monthCost: 71.30,
        lastSession: .init(startTime: Date(), energyKwh: 38.2, cost: 12.40,
                           providerName: "Wallbox", socStart: 32, socEnd: 80),
        updatedAt: Date()
    )
}
