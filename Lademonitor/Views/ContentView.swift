import SwiftUI

struct ContentView: View {
    @ObservedObject private var session = SessionManager.shared

    var body: some View {
        if session.isAuthenticated {
            TabView {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

                SessionsListView()
                    .tabItem { Label("Ladevorgänge", systemImage: "bolt.fill") }

                SettingsView()
                    .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
            }
            .task { await session.refreshCurrentUserIfNeeded() }
        } else {
            // Ohne gueltige Session: Login/Registrierung (inkl. Server-Adresse).
            AuthView()
        }
    }
}

#Preview {
    ContentView()
}
