import SwiftUI

/// Anmelde- und Registrierungs-Screen inkl. Server-Adresse. Wird angezeigt,
/// solange keine gueltige Session besteht.
struct AuthView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var isRegistering = false
    @State private var identifier = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingForgotPassword = false

    private var trimmedIdentifier: String { identifier.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var hostingBinding: Binding<AppSettings.ServerHosting> {
        Binding(get: { settings.serverHosting }, set: { settings.serverHosting = $0 })
    }

    private var canSubmit: Bool {
        guard settings.isConfigured, password.count >= 8 else { return false }
        if isRegistering {
            // Beim Registrieren ist die Eingabe der Nutzername - Mindestlaenge 3
            // wie serverseitig.
            return trimmedIdentifier.count >= 3 && password == passwordConfirm
        }
        // Beim Anmelden darf es auch eine E-Mail-Adresse sein; die kann kuerzer
        // als drei Zeichen ohnehin nicht sein, aber die Nutzernamen-Regel gilt
        // hier nicht - der Server entscheidet.
        return !trimmedIdentifier.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hosting", selection: hostingBinding) {
                        ForEach(AppSettings.ServerHosting.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settings.serverHosting == .selfHosted {
                        TextField("https://lademonitor.example.com", text: $settings.serverURLString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Server-Adresse")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        switch settings.serverHosting {
                        case .selfHosted:
                            Text("Domain deines eigenen Lademonitor-Servers. Ein „https://“ wird automatisch ergänzt, falls du es weglässt.")
                        case .cloud:
                            Text("Läuft auf lademonitor.cloud – Betrieb, Updates und Backups übernimmt der Betreiber für dich.")
                        }
                        Link("Quellcode auf GitHub", destination: URL(string: "https://github.com/iDomi94/Lademonitor-Server")!)
                    }
                }

                Section {
                    TextField(isRegistering ? "Nutzername" : "Nutzername oder E-Mail", text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(isRegistering ? .default : .emailAddress)
                    if isRegistering {
                        TextField("E-Mail-Adresse (optional)", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                    }
                    SecureField("Passwort", text: $password)
                    if isRegistering {
                        SecureField("Passwort wiederholen", text: $passwordConfirm)
                    }
                } header: {
                    Text(isRegistering ? "Registrieren" : "Anmelden")
                } footer: {
                    if isRegistering {
                        Text("Nutzername mindestens 3 Zeichen, Passwort mindestens 8 Zeichen. Ohne E-Mail-Adresse funktioniert alles wie bisher – nur „Passwort vergessen“ und Benachrichtigungen dann nicht.")
                    } else {
                        Text("Du kannst dich mit deinem Nutzernamen oder deiner E-Mail-Adresse anmelden.")
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

                    if !isRegistering {
                        Button("Passwort vergessen?") {
                            showingForgotPassword = true
                        }
                        .font(.footnote)
                        .disabled(!settings.isConfigured)
                    }
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
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView(initialIdentifier: trimmedIdentifier)
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        if isRegistering && password != passwordConfirm {
            errorMessage = String(localized: "Die Passwörter stimmen nicht überein.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response: AuthResponse
            if isRegistering {
                response = try await APIClient.shared.register(
                    username: trimmedIdentifier,
                    password: password,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail
                )
            } else {
                response = try await APIClient.shared.login(identifier: trimmedIdentifier, password: password)
            }
            SessionManager.shared.completeAuthentication(response)
            // Liegen schon Daten auf dem Geraet und ist dieses Konto hier neu,
            // fragt startAfterLogin() zuerst nach, statt sie ungefragt in das
            // gerade angemeldete Konto zu schieben (der Dialog haengt an
            // ContentView, siehe SyncService.pendingLocalDataDecision).
            // Sonst ist die Uebernahme lokaler Daten kein Sonderfall, sondern
            // einfach der erste normale Sync-Durchlauf.
            SyncService.shared.startAfterLogin()
        } catch let APIError.server(_, message) {
            // Server liefert die Fehlerursache im Klartext (z.B. "Nutzername oder Passwort falsch").
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Fordert einen Link zum Zuruecksetzen an.
///
/// Das eigentliche Setzen des Passworts passiert bewusst NICHT in der App,
/// sondern ueber den Link in der Mail im Browser: der Token gehoert in genau
/// eine Hand, und die Web-Seite dafuer existiert bereits. Die App stoesst nur
/// den Versand an.
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var identifier: String
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    /// Uebernimmt, was im Anmeldeformular schon steht - wer gerade erfolglos
    /// versucht hat sich anzumelden, soll es nicht noch einmal tippen.
    init(initialIdentifier: String) {
        _identifier = State(initialValue: initialIdentifier)
    }

    var body: some View {
        NavigationStack {
            Form {
                if didSubmit {
                    Section {
                        Label("Wenn es dazu ein Konto mit bestätigter E-Mail-Adresse gibt, ist die Nachricht unterwegs.", systemImage: "envelope.badge")
                    } footer: {
                        Text("Schau auch im Spam-Ordner nach. Den Link öffnest du im Browser – dort setzt du das neue Passwort.")
                    }
                } else {
                    Section {
                        TextField("Nutzername oder E-Mail", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                    } footer: {
                        Text("Wir schicken einen Link zum Zurücksetzen. Er gilt eine Stunde und lässt sich nur einmal verwenden.")
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                Text("Link anfordern")
                                if isSubmitting {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSubmitting || identifier.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        Text("Achtung: Beim Zurücksetzen werden alle angemeldeten Geräte abgemeldet – auch diese App und eine eventuelle Home-Assistant-Anbindung.")
                    }
                }
            }
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Fertig" : "Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIClient.shared.requestPasswordReset(
                identifier: identifier.trimmingCharacters(in: .whitespaces)
            )
            // Der Server antwortet immer gleich, egal ob es das Konto gibt -
            // also darf auch die App hier nichts unterscheiden.
            didSubmit = true
        } catch {
            // Nur echte Verbindungs-/Serverfehler landen hier; ein unbekanntes
            // Konto sieht fuer den Client wie ein Erfolg aus.
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
}
