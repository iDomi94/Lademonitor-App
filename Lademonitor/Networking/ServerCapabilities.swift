import Foundation
import Combine

/// Funktionen der App, die einen bestimmten Server-Stand brauchen.
///
/// Regel (seit 1.17.0): jede neue Funktion, die ein neues Server-Feld oder
/// einen neuen Endpunkt braucht, bekommt hier eine Mindestversion. Auf einem
/// aelteren Server bleibt sie sichtbar, ist aber gesperrt und sagt warum -
/// sonst verwirft der alte Server den Wert still und der naechste Abgleich
/// setzt ihn in der App zurueck (so geschehen bei "Verteilen auf" mit einem
/// Server vor 0.49.0). Im Local-Only-Modus ist nie etwas gesperrt.
enum ServerFeature {
    /// THG-Quote als Gutschrift (Kostenkategorie "thg").
    case thgCredit

    var minimumServerVersion: String {
        switch self {
        case .thgCredit: return "0.50.0"
        }
    }
}

/// Merkt sich die Version des Servers (aus `GET /health`, bei jedem Sync
/// aufgefrischt) und beantwortet, ob eine `ServerFeature` nutzbar ist.
@MainActor
final class ServerCapabilities: ObservableObject {
    static let shared = ServerCapabilities()

    /// Zuletzt gemeldete Version - gilt nur fuer die Adresse, unter der sie
    /// gemeldet wurde (ein Wechsel des Servers verwirft sie).
    @Published private(set) var serverVersion: String?

    private static let versionKey = "serverVersion"
    private static let urlKey = "serverVersionURL"

    private init() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.urlKey) == AppSettings.shared.serverURLString {
            serverVersion = defaults.string(forKey: Self.versionKey)
        }
    }

    /// Fragt `/health` ab und merkt sich die Version. Wirft nie - ohne Antwort
    /// bleibt der letzte bekannte Stand.
    func refresh() async {
        guard AppSettings.shared.appMode == .server, AppSettings.shared.isConfigured else { return }
        guard let version = try? await APIClient.shared.fetchServerVersion() else { return }
        serverVersion = version
        UserDefaults.standard.set(version, forKey: Self.versionKey)
        UserDefaults.standard.set(AppSettings.shared.serverURLString, forKey: Self.urlKey)
    }

    /// Version fuer die aktuelle Server-Adresse, sonst nil.
    private var currentVersion: String? {
        UserDefaults.standard.string(forKey: Self.urlKey) == AppSettings.shared.serverURLString ? serverVersion : nil
    }

    func supports(_ feature: ServerFeature) -> Bool {
        guard AppSettings.shared.appMode == .server else { return true }
        // Unbekannt (noch nie synchronisiert) zaehlt als zu alt: lieber kurz
        // gesperrt als einen Wert anlegen, den der Server verwirft.
        guard let version = currentVersion else { return false }
        return Self.compare(version, feature.minimumServerVersion) >= 0
    }

    /// Hinweis fuer eine gesperrte Funktion, nil wenn sie nutzbar ist.
    func unavailableHint(_ feature: ServerFeature) -> String? {
        guard !supports(feature) else { return nil }
        return String(localized: "Benötigt Server \(feature.minimumServerVersion) oder neuer")
    }

    /// Vergleicht "0.49.1" mit "0.50.0" Stelle fuer Stelle als Zahlen;
    /// Anhaenge wie "-beta" werden ignoriert.
    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
