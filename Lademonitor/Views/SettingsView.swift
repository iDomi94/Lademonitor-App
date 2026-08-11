import SwiftUI

struct SettingsView: View {
    @ObservedObject private var session = SessionManager.shared
    @State private var isLoggingOut = false

    var body: some View {
        NavigationStack {
            List {
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

                Section("Verbindung") {
                    NavigationLink {
                        ConnectionSettingsView()
                    } label: {
                        Label("Server & Verbindung", systemImage: "network")
                    }
                }

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
            }
            .navigationTitle("Einstellungen")
        }
    }
}

/// Server-Adresse eintragen und Verbindung testen.
struct ConnectionSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
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
        .navigationTitle("Verbindung")
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

#Preview {
    SettingsView()
}
