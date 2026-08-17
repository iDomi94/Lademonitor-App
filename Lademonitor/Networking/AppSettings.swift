import Foundation
import Combine

/// Haelt die Server-URL persistent (UserDefaults) und in einer @Published-Form,
/// damit Views sich automatisch aktualisieren, wenn sich die Einstellung aendert.
/// Die Server-Adresse ist keine sensible Information - der Auth-Token gehoert
/// dagegen in den Keychain (siehe KeychainStore).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: "serverURL") }
    }

    @Published var appMode: AppMode {
        didSet {
            UserDefaults.standard.set(appMode.rawValue, forKey: "appMode")
            if appMode == .localOnly {
                // Sicherheitsmassnahme: Anmeldedaten beim Wechsel in den Local-Only-Modus
                // verwerfen (nur lokal, kein Server-Roundtrip), damit ein spaeterer Wechsel
                // zurueck zu Server immer eine frische Anmeldung verlangt, statt eine alte
                // Session unbemerkt weiterzuverwenden.
                SessionManager.shared.invalidateSession()
            }
        }
    }

    private init() {
        self.serverURLString = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let storedMode = UserDefaults.standard.string(forKey: "appMode").flatMap(AppMode.init(rawValue:))
        self.appMode = storedMode ?? .undecided
    }

    var serverURL: URL? {
        guard !serverURLString.isEmpty else { return nil }
        // Nutzer gibt z.B. "lademonitor.example.com" ein - falls kein Schema
        // angegeben ist, https:// ergaenzen (Server ist per Nginx+HTTPS oeffentlich
        // erreichbar). Ein explizit getipptes http:// bleibt erhalten.
        var raw = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }
        // Trailing Slash entfernen, damit die Pfad-Verkettung im APIClient sauber bleibt
        if raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    var isConfigured: Bool { serverURL != nil }

    /// Ob Views Daten laden duerfen: im Local-Only-Modus immer (kein Server noetig),
    /// im Server-Modus nur mit konfigurierter Server-Adresse.
    var isReadyForDataAccess: Bool { appMode == .localOnly || isConfigured }
}
