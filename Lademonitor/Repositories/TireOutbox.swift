import Foundation
import Combine

/// Warteschlange fuer Reifen-Eingaben ohne Netz.
///
/// Reifensaetze und Profilmessungen sind - anders als Ladevorgaenge - nicht
/// Teil des lokalen Spiegels (die Auswertung liegt allein auf dem Server, siehe
/// TiresSettingsView). Ohne Netz schlug Speichern deshalb einfach fehl. Jetzt
/// landet eine solche Eingabe hier, wird in der Reifen-Ansicht als "wartet auf
/// Upload" gezeigt und beim naechsten Sync (oder beim naechsten Oeffnen der
/// Ansicht mit Netz) in der eingegebenen Reihenfolge hochgeladen.
///
/// Gespeichert wird der fertig kodierte Request (Methode, Pfad, JSON-Body),
/// nicht das Modell - so geht genau das an den Server, was auch online
/// gegangen waere. Anlagen tragen ihre eigene UUID als `Idempotency-Key`: geht
/// die Antwort verloren und wird wiederholt, legt ein Server ab 0.51.0 nichts
/// doppelt an.
///
/// Ein Eintrag gehoert zu dem Konto, unter dem er erfasst wurde; nach einem
/// Kontowechsel wird er verworfen statt in ein fremdes Konto zu wandern.
///
/// Fehler beim Abarbeiten:
/// - keine Verbindung / Serverfehler 5xx / 408 / 429: Abbruch, spaeter erneut
///   (die Reihenfolge bleibt erhalten).
/// - 404 beim Loeschen: gilt als erledigt.
/// - sonstige 4xx (z.B. 422): der Eintrag bleibt mit Fehlertext stehen, wird
///   nicht mehr automatisch wiederholt und kann verworfen werden.
@MainActor
final class TireOutbox: ObservableObject {
    static let shared = TireOutbox()

    struct Entry: Codable, Identifiable, Equatable {
        enum Kind: String, Codable {
            case createSet, updateSet, deleteSet, createTread, deleteTread
        }

        var id: UUID
        var kind: Kind
        var method: String
        var path: String
        var body: Data?
        /// Fuer die Anzeige, schon beim Erfassen lokalisiert.
        var label: String
        var createdAt: Date
        var userId: String?
        /// Nur bei Anlagen: geht als `Idempotency-Key` mit.
        var idempotencyKey: String?
        /// Gesetzt, wenn der Server den Eintrag abgelehnt hat.
        var failure: String?
    }

    @Published private(set) var entries: [Entry] = []
    private var isFlushing = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tire-outbox.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = stored
        }
    }

    var hasPending: Bool { !entries.isEmpty }

    /// Ob ein Fehler bedeutet "gerade kein Netz/Server" - dann wird gepuffert.
    nonisolated static func isTransient(_ error: Error) -> Bool {
        switch error as? APIError {
        case .network: return true
        case .server(let code, _): return code >= 500 || code == 408 || code == 429 || code == 401
        default: return false
        }
    }

    // MARK: - Erfassen

    /// `idempotencyKey`: derselbe Schluessel wie beim gescheiterten Direktversuch -
    /// kam der doch an, legt die Wiederholung nichts doppelt an.
    func enqueueCreateSet(_ payload: TireSetPayload, label: String, idempotencyKey: String = UUID().uuidString) throws {
        try add(.createSet, method: "POST", path: "/api/tires", body: APIClient.shared.encodeBody(payload),
                label: label, idempotencyKey: idempotencyKey)
    }

    func enqueueUpdateSet(id: String, _ payload: TireSetPayload, label: String) throws {
        try add(.updateSet, method: "PATCH", path: "/api/tires/\(id)", body: APIClient.shared.encodeBody(payload), label: label)
    }

    func enqueueDeleteSet(id: String, label: String) throws {
        try add(.deleteSet, method: "DELETE", path: "/api/tires/\(id)", body: nil, label: label)
    }

    func enqueueCreateTread(tireSetId: String, _ payload: TreadMeasurementPayload, label: String,
                            idempotencyKey: String = UUID().uuidString) throws {
        try add(.createTread, method: "POST", path: "/api/tires/\(tireSetId)/tread",
                body: APIClient.shared.encodeBody(payload), label: label, idempotencyKey: idempotencyKey)
    }

    func enqueueDeleteTread(id: String, label: String) throws {
        try add(.deleteTread, method: "DELETE", path: "/api/tires/tread/\(id)", body: nil, label: label)
    }

    func discard(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// IDs, deren Loeschung noch aussteht - die Ansicht blendet sie schon aus.
    var pendingDeletedSetIds: Set<String> { pendingIds(.deleteSet, prefix: "/api/tires/") }
    var pendingDeletedTreadIds: Set<String> { pendingIds(.deleteTread, prefix: "/api/tires/tread/") }

    private func pendingIds(_ kind: Entry.Kind, prefix: String) -> Set<String> {
        Set(entries.filter { $0.kind == kind && $0.failure == nil }.map { String($0.path.dropFirst(prefix.count)) })
    }

    private func add(_ kind: Entry.Kind, method: String, path: String, body: Data?, label: String,
                     idempotencyKey: String? = nil) throws {
        entries.append(Entry(
            id: UUID(), kind: kind, method: method, path: path, body: body,
            label: label, createdAt: Date(), userId: SessionManager.shared.currentUser?.id,
            idempotencyKey: idempotencyKey, failure: nil
        ))
        save()
    }

    // MARK: - Abarbeiten

    /// Laedt alle wartenden Eintraege hoch, in der Reihenfolge der Eingabe.
    /// Wirft nie; gibt zurueck, ob danach noch etwas aussteht.
    @discardableResult
    func flush() async -> Bool {
        guard !isFlushing, AppSettings.shared.appMode == .server,
              SessionManager.shared.isAuthenticated, NetworkMonitor.shared.isOnline
        else { return hasPending }
        isFlushing = true
        defer { isFlushing = false }

        let currentUser = SessionManager.shared.currentUser?.id
        // Erfasst unter einem anderen Konto: nicht in dieses hochladen.
        entries.removeAll { $0.userId != nil && currentUser != nil && $0.userId != currentUser }
        save()

        for entry in entries where entry.failure == nil {
            do {
                try await APIClient.shared.sendQueued(
                    method: entry.method, path: entry.path, body: entry.body,
                    idempotencyKey: entry.idempotencyKey
                )
                remove(entry)
            } catch APIError.server(let code, _) where code == 404 && entry.method == "DELETE" {
                remove(entry)
            } catch {
                if Self.isTransient(error) { break }
                markFailed(entry, error.localizedDescription)
            }
        }
        return hasPending
    }

    private func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func markFailed(_ entry: Entry, _ message: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].failure = message
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Letzter Stand der Reifen-Ansicht vom Server, damit sie auch ohne Netz etwas
/// zeigt - und man dort offline eine Profilmessung oder einen Wechsel erfassen
/// kann. Reine Anzeige, nichts davon wird zurueckgeschrieben.
struct TireCache: Codable {
    var sets: [TireSet]
    var measurements: [TireTreadMeasurement]
    var overview: TireOverview?
    var comparison: TireComparison?
    var savedAt: Date
    var userId: String?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tire-cache.json")
    }

    @MainActor
    static func load() -> TireCache? {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(TireCache.self, from: data),
              cache.userId == SessionManager.shared.currentUser?.id
        else { return nil }
        return cache
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
