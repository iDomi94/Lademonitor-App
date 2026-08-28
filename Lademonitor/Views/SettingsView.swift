import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var syncService = SyncService.shared
    @State private var showingResetConfirmation = false
    @State private var resetErrorMessage: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("Verwaltung") {
                    NavigationLink {
                        LocationsSettingsView()
                    } label: {
                        Label("Ladeorte", systemImage: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        VehiclesSettingsView()
                    } label: {
                        Label("Fahrzeuge", systemImage: "car.fill")
                    }
                    NavigationLink {
                        ProvidersSettingsView()
                    } label: {
                        Label("Anbieter", systemImage: "bolt.fill")
                    }
                }

                Section("Server") {
                    NavigationLink {
                        ServerSettingsView()
                    } label: {
                        Label("Server & Verbindung", systemImage: "network")
                    }
                }

                if settings.appMode == .server {
                    Section {
                        if let lastSync = syncService.lastSyncDate {
                            LabeledContent("Zuletzt synchronisiert", value: Self.relativeFormatter.localizedString(for: lastSync, relativeTo: Date()))
                        } else {
                            Text("Noch nicht synchronisiert")
                                .foregroundStyle(.secondary)
                        }
                        if let error = syncService.lastSyncError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button {
                            Task { await SyncService.shared.syncNow() }
                        } label: {
                            HStack {
                                Text("Jetzt synchronisieren")
                                if syncService.isSyncing {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(syncService.isSyncing)
                    } header: {
                        Text("Synchronisierung")
                    } footer: {
                        Text("Änderungen werden automatisch hochgeladen, auch nach kurzzeitigem Verbindungsverlust. \"Jetzt synchronisieren\" stößt das manuell an.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Alle lokalen Daten zurücksetzen", systemImage: "trash")
                    }
                    if let resetErrorMessage {
                        Text(resetErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(settings.appMode == .server
                        ? "Löscht Fahrzeuge, Anbieter, Ladeorte und Ladevorgänge auf diesem Gerät. Bereits synchronisierte Daten bleiben auf dem Server und werden danach automatisch zurückgeholt – noch nicht hochgeladene Änderungen gehen verloren."
                        : "Löscht Fahrzeuge, Anbieter, Ladeorte und Ladevorgänge unwiderruflich von diesem Gerät. Es gibt keine weitere Kopie.")
                }
            }
            .navigationTitle("Einstellungen")
            .alert("Alle lokalen Daten löschen?", isPresented: $showingResetConfirmation) {
                Button("Löschen", role: .destructive) { resetAllData() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das kann nicht rückgängig gemacht werden.")
            }
        }
    }

    private func resetAllData() {
        resetErrorMessage = nil
        do {
            try LocalDataStore.shared.resetAllData()
            if settings.appMode == .server {
                Task { await SyncService.shared.syncNow() }
            }
        } catch {
            resetErrorMessage = error.localizedDescription
        }
    }
}

/// Unterseite: Modus, Konto (nur Server-Modus) und Server-Verbindung in einer Ansicht.
struct ServerSettingsView: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isLoggingOut = false
    @State private var showingServerSwitchConfirmation = false
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Aktuell", value: settings.appMode == .localOnly ? "Nur lokal" : "Server")
                if settings.appMode == .localOnly {
                    Button {
                        showingServerSwitchConfirmation = true
                    } label: {
                        Label("Zu Server wechseln", systemImage: "network")
                    }
                } else {
                    Button {
                        settings.appMode = .localOnly
                    } label: {
                        Label("Zu \"Nur lokal\" wechseln", systemImage: "iphone")
                    }
                }
            } header: {
                Text("Modus")
            } footer: {
                if settings.appMode == .localOnly {
                    Text("Alle Daten liegen ausschließlich auf diesem Gerät.")
                }
            }

            if settings.appMode == .server {
                Section("Konto") {
                    if let user = session.currentUser {
                        LabeledContent("Angemeldet als", value: user.username)
                    }
                    Button(role: .destructive) {
                        Task {
                            isLoggingOut = true
                            await session.logout()
                            isLoggingOut = false
                        }
                    } label: {
                        HStack {
                            Text("Abmelden")
                            if isLoggingOut {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoggingOut)
                }
            }

            Section {
                TextField("https://lademonitor.example.com", text: $settings.serverURLString)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } header: {
                Text("Server-Adresse")
            } footer: {
                Text("Domain deines Lademonitor-Servers. Ein \"https://\" wird automatisch ergänzt, falls du es weglässt.")
            }

            if !settings.isConfigured {
                Section {
                    Label("Trage zuerst deine Server-Adresse ein, um loszulegen.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Verbindung testen")
                        if isTesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!settings.isConfigured || isTesting)

                if let testResult {
                    switch testResult {
                    case .success:
                        Label("Verbindung erfolgreich", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Server & Verbindung")
        .alert("Zu Server wechseln?", isPresented: $showingServerSwitchConfirmation) {
            Button("Wechseln", role: .destructive) {
                settings.appMode = .server
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Nach der Anmeldung werden deine bisherigen lokalen Daten automatisch zum Server hochgeladen. Du kannst jederzeit in den Einstellungen zurück zu \"Nur lokal\" wechseln.")
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let ok = try await APIClient.shared.checkHealth()
            testResult = ok ? .success : .failure("Server antwortet, aber Status ist nicht \"ok\".")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}

// ConnectionSettingsView wird nicht mehr direkt verwendet, bleibt aber fuer
// eventuelle externe Aufrufer erhalten und delegiert an ServerSettingsView.
struct ConnectionSettingsView: View {
    var body: some View {
        ServerSettingsView()
    }
}

#Preview {
    SettingsView()
}
