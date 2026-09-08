import SwiftUI

struct ContentView: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        content
            // Der Dialog haengt bewusst HIER und nicht an der AuthView: nach dem
            // Anmelden ist die schon aus der Hierarchie verschwunden (siehe
            // SyncService.pendingLocalDataDecision), ihr Alert wuerde also nie
            // erscheinen. ContentView existiert in jedem Zustand.
            .alert("Was soll mit den Daten auf diesem Gerät passieren?",
                   isPresented: $syncService.pendingLocalDataDecision) {
                Button("In dieses Konto hochladen") {
                    Task { await SyncService.shared.applyLocalDataDecision(.upload) }
                }
                Button("Vom Gerät löschen", role: .destructive) {
                    Task { await SyncService.shared.applyLocalDataDecision(.discard) }
                }
                Button("Abbrechen", role: .cancel) {
                    Task { await SyncService.shared.cancelLocalDataDecision() }
                }
            } message: {
                Text(localDataDecisionMessage)
            }
    }

    /// Erklaert beide Wege konkret - inklusive der Zusicherung, dass auf dem
    /// Server nichts verloren geht. Genau das ist die Sorge, die einen hier
    /// zoegern laesst.
    private var localDataDecisionMessage: String {
        let bestand = syncService.pendingLocalDataSummary.isEmpty
            ? String(localized: "Auf diesem Gerät liegen bereits Daten.")
            : String(localized: "Auf diesem Gerät liegen bereits: \(syncService.pendingLocalDataSummary).")
        let konto = session.currentUser?.username ?? String(localized: "diesem Konto")
        return bestand + " "
            + String(localized: "„Hochladen“ fügt sie dem Konto \(konto) hinzu. „Vom Gerät löschen“ entfernt sie hier und lädt stattdessen den Stand dieses Kontos – auf dem Server wird dabei nichts gelöscht. „Abbrechen“ meldet dich wieder ab und lässt alles unverändert.")
    }

    @ViewBuilder
    private var content: some View {
        switch settings.appMode {
        case .undecided:
            // Erster Start: Wahl zwischen Local-Only und Server-Modus, ersetzt den
            // frueher hier erzwungenen Login-Screen.
            ModeSelectionView()
        case .localOnly:
            // Kein Auth-Gate: alle Daten liegen lokal, es gibt keine Session.
            mainTabView
        case .server:
            if session.isAuthenticated {
                mainTabView
                    .task { await session.refreshCurrentUserIfNeeded() }
            } else {
                AuthView()
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            SessionsListView()
                .tabItem { Label("Ladevorgänge", systemImage: "bolt.fill") }

            MapOverviewView()
                .tabItem { Label("Karte", systemImage: "map.fill") }

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
}
