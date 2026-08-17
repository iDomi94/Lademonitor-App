import SwiftUI

struct ContentView: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
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
