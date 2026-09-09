import Foundation
import Combine

/// Zentraler Auth-Zustand der App. Spiegelt den im Keychain gespeicherten Token
/// fuer die UI und steuert den Wechsel zwischen Login-Screen und Haupt-App.
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var currentUser: AuthUser?

    private init() {
        // Liegt beim Start ein Token im Keychain, gilt die Session als aktiv
        // (der Token laeuft serverseitig nicht ab). Ein ungueltiger Token faellt
        // beim ersten API-Call durch das 401-Handling auf.
        isAuthenticated = KeychainStore.shared.readToken() != nil
    }

    /// Nach erfolgreichem Login/Registrierung: Token sichern und in die App wechseln.
    func completeAuthentication(_ response: AuthResponse) {
        KeychainStore.shared.saveToken(response.token)
        currentUser = response.user
        isAuthenticated = true
    }

    /// Aktiver Logout: Server benachrichtigen (best effort), dann lokal aufraeumen.
    func logout() async {
        try? await APIClient.shared.logout()
        clearLocalSession()
    }

    /// Bei 401 auf einem authentifizierten Request: Session ist ungueltig.
    func invalidateSession() {
        clearLocalSession()
    }

    /// Aktuellen Nutzer nachladen, falls noch nicht bekannt (z.B. nach App-Neustart
    /// mit gespeichertem Token). Ein 401 fuehrt via APIClient zur Invalidierung.
    func refreshCurrentUserIfNeeded() async {
        guard isAuthenticated, currentUser == nil else { return }
        currentUser = try? await APIClient.shared.fetchMe()
    }

    /// Nutzer neu vom Server holen - z.B. nachdem die Adresse in einem anderen
    /// Client bestaetigt wurde.
    func reloadCurrentUser() async {
        guard isAuthenticated else { return }
        currentUser = try? await APIClient.shared.fetchMe()
    }

    /// Von den Konto-Einstellungen aufgerufen, wenn ein Endpunkt den
    /// aktualisierten Nutzer zurueckgibt (Adresse, Benachrichtigungen).
    func applyUpdatedUser(_ user: AuthUser) {
        currentUser = user
    }

    /// Eigenes Passwort aendern.
    ///
    /// Der Server verwirft dabei ALLE Sitzungen des Nutzers - damit eine
    /// womoeglich uebernommene Sitzung nicht weiterlaeuft - und stellt sofort
    /// eine neue aus, deren Token er seit Version 0.14.1 mitliefert. Der wird
    /// hier direkt uebernommen: die App bleibt angemeldet, ohne sich ein
    /// zweites Mal anmelden zu muessen.
    ///
    /// Andere Geraete (Home Assistant, weitere Installationen) sind danach
    /// abgemeldet und brauchen einen neuen Zugang - darauf weist die
    /// Konto-Ansicht hin.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        let response = try await APIClient.shared.changePassword(
            currentPassword: currentPassword, newPassword: newPassword
        )
        completeAuthentication(response)
    }

    /// Eigenes Konto unwiderruflich loeschen, inkl. aller eigenen Daten auf
    /// dem Server. Ein falsches Passwort (403) wirft weiter, ohne lokal etwas
    /// zu veraendern - erst nach bestaetigtem Erfolg lokal aufraeumen wie
    /// beim Logout.
    func deleteAccount(currentPassword: String) async throws {
        try await APIClient.shared.deleteAccount(currentPassword: currentPassword)
        clearLocalSession()
    }

    private func clearLocalSession() {
        KeychainStore.shared.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }
}
