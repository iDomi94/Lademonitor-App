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

    private func clearLocalSession() {
        KeychainStore.shared.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }
}
