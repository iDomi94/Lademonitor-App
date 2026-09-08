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

    /// Eigenes Passwort aendern - und danach sofort neu anmelden.
    ///
    /// Der Server verwirft beim Wechsel ALLE Sitzungen des Nutzers (damit eine
    /// womoeglich uebernommene Sitzung nicht weiterlaeuft) und stellt eine neue
    /// nur als Cookie fuer die Web-Oberflaeche aus. Die Antwort ist 204 ohne
    /// Inhalt - dieser Bearer-Client bekommt also keinen neuen Token und waere
    /// beim naechsten Aufruf abgemeldet. Da das neue Passwort hier ohnehin
    /// vorliegt, holt die App sich den frischen Token selbst.
    ///
    /// Schlaegt nur die Neuanmeldung fehl, ist das Passwort trotzdem schon
    /// geaendert - dann wird die Sitzung verworfen und der Login-Screen zeigt
    /// den Fehler, statt eine tote Sitzung vorzutaeuschen.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let username = currentUser?.username else {
            throw APIError.notConfigured
        }
        try await APIClient.shared.changePassword(
            currentPassword: currentPassword, newPassword: newPassword
        )
        do {
            let response = try await APIClient.shared.login(identifier: username, password: newPassword)
            completeAuthentication(response)
        } catch {
            clearLocalSession()
            throw error
        }
    }

    private func clearLocalSession() {
        KeychainStore.shared.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }
}
