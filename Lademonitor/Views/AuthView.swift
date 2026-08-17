import SwiftUI

/// Anmelde- und Registrierungs-Screen inkl. Server-Adresse. Wird angezeigt,
/// solange keine gueltige Session besteht.
struct AuthView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var isRegistering = false
    @State private var username = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        guard settings.isConfigured,
              trimmedUsername.count >= 3,
              password.count >= 8 else { return false }
        if isRegistering { return password == passwordConfirm }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://lademonitor.example.com", text: $settings.serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server-Adresse")
                } footer: {
                    Text("Domain deines Lademonitor-Servers. Ein „https://“ wird automatisch ergänzt, falls du es weglässt.")
                }

                Section {
                    TextField("Nutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                    if isRegistering {
                        SecureField("Passwort wiederholen", text: $passwordConfirm)
                    }
                } header: {
                    Text(isRegistering ? "Registrieren" : "Anmelden")
                } footer: {
                    if isRegistering {
                        Text("Nutzername mindestens 3 Zeichen, Passwort mindestens 8 Zeichen.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text(isRegistering ? "Registrieren" : "Anmelden")
                            if isSubmitting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSubmitting || !canSubmit)

                    Button(isRegistering ? "Schon ein Konto? Anmelden" : "Neu hier? Konto erstellen") {
                        withAnimation {
                            isRegistering.toggle()
                            errorMessage = nil
                            passwordConfirm = ""
                        }
                    }
                    .font(.footnote)
                }

                Section {
                    Button {
                        settings.appMode = .localOnly
                    } label: {
                        Label("Stattdessen nur lokal nutzen", systemImage: "iphone")
                    }
                } footer: {
                    Text("Ohne Server, alle Daten bleiben auf diesem Gerät.")
                }
            }
            .navigationTitle("Lademonitor")
        }
    }

    private func submit() async {
        errorMessage = nil
        if isRegistering && password != passwordConfirm {
            errorMessage = "Die Passwörter stimmen nicht überein."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response: AuthResponse
            if isRegistering {
                response = try await APIClient.shared.register(username: trimmedUsername, password: password)
            } else {
                response = try await APIClient.shared.login(username: trimmedUsername, password: password)
            }
            SessionManager.shared.completeAuthentication(response)
            // Migration lokaler Daten (falls vorhanden) ist kein Sonderfall, sondern
            // einfach der erste normale Sync-Durchlauf - siehe SyncService.
            Task { await SyncService.shared.syncNow() }
        } catch let APIError.server(_, message) {
            // Server liefert die Fehlerursache im Klartext (z.B. "Nutzername oder Passwort falsch").
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
}
