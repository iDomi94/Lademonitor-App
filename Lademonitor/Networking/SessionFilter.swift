import Foundation
import Combine

/// Globaler Datums-Filter fuer Dashboard/Ladevorgaenge/Karte - ein gemeinsamer Zustand
/// statt drei einzelner Filter pro Screen, damit die Auswahl beim Tab-Wechsel erhalten
/// bleibt. Bewusst nicht in UserDefaults persistiert (gilt nur fuer die laufende
/// App-Sitzung) - ein "vergessener" Filter aus einer frueheren Sitzung, der beim naechsten
/// Start unbemerkt weiter aktiv ist, waere verwirrender als ihn einfach neu setzen zu muessen.
@MainActor
final class SessionFilter: ObservableObject {
    static let shared = SessionFilter()
    private init() {}

    @Published var dateRange: ClosedRange<Date>?

    var isActive: Bool { dateRange != nil }

    func clear() { dateRange = nil }
}
