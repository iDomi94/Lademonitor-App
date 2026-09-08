import SwiftUI

/// Konto-Einstellungen im Server-Modus: E-Mail-Adresse, eigenes Passwort und
/// Benachrichtigungen.
///
/// Alles hier setzt einen Server ab 0.14.0 voraus. Ein aelterer Server liefert
/// die entsprechenden Felder in `/api/auth/me` gar nicht mit - dann zeigt die
/// Ansicht statt der Formulare einen Hinweis, statt Knoepfe anzubieten, die
/// mit 404 antworten (siehe AuthUser.supportsAccountFeatures).
struct AccountSettingsView: View {
    @ObservedObject private var session = SessionManager.shared

    // E-Mail
    @State private var email = ""
    @State private var emailPassword = ""
    @State private var isSavingEmail = false
    @State private var emailStatus: StatusMessage?

    // Passwort
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var newPasswordConfirm = ""
    @State private var isChangingPassword = false
    @State private var passwordStatus: StatusMessage?

    // Benachrichtigungen
    @State private var notifyBackupFailed = true
    @State private var notifyMyskodaError = true
    @State private var notifyMonthlyReport = false
    @State private var notifyNewRegistration = true
    @State private var reviewDigest: ReviewDigestFrequency = .off
    @State private var isSavingNotifications = false
    @State private var notificationStatus: StatusMessage?

    /// Kleine Rueckmeldung unter einem Abschnitt - Erfolg gruen, Fehler rot.
    private struct StatusMessage {
        let text: String
        let isError: Bool
    }

    private var user: AuthUser? { session.currentUser }

    private var canSaveEmail: Bool {
        !emailPassword.isEmpty && !isSavingEmail
    }

    private var canChangePassword: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 8
            && newPassword == newPasswordConfirm
            && !isChangingPassword
    }

    var body: some View {
        Form {
            if let user {
                Section("Angemeldet") {
                    LabeledContent("Nutzername", value: user.username)
                    if user.isAdmin {
                        LabeledContent("Rolle", value: String(localized: "Admin"))
                    }
                }

                if user.supportsAccountFeatures {
                    emailSection(user: user)
                    passwordSection
                    notificationsSection(user: user)
                } else {
                    Section {
                        Label("Dein Server unterstützt diese Funktionen noch nicht. Sie brauchen Lademonitor-Server 0.14.0 oder neuer.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Konto")
        .task { await load() }
    }

    // MARK: - E-Mail

    @ViewBuilder
    private func emailSection(user: AuthUser) -> some View {
        Section {
            TextField("E-Mail-Adresse", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)

            if !(user.email ?? "").isEmpty {
                if user.isEmailVerified {
                    Label("Bestätigt", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                } else {
                    Label("Noch nicht bestätigt", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    Button("Bestätigungsmail erneut senden") {
                        Task { await resendVerification() }
                    }
                    .font(.footnote)
                }
            }

            SecureField("Aktuelles Passwort", text: $emailPassword)

            Button {
                Task { await saveEmail() }
            } label: {
                HStack {
                    Text("Adresse speichern")
                    if isSavingEmail {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canSaveEmail)

            if let emailStatus {
                Text(emailStatus.text)
                    .font(.footnote)
                    .foregroundStyle(emailStatus.isError ? .red : .green)
            }
        } header: {
            Text("E-Mail-Adresse")
        } footer: {
            // Beide Begruendungen gehoeren sichtbar an die Stelle, an der man
            // sich fragt, warum ueberhaupt ein Passwort noetig ist.
            Text("Wird für „Passwort vergessen“ und für Benachrichtigungen gebraucht. Leer lassen entfernt die Adresse. Das Passwort ist eine Sicherheitsabfrage: wer die Adresse ändern kann, kann anschließend das Passwort zurücksetzen lassen. Eine geänderte Adresse muss erneut bestätigt werden – bis dahin kann sie kein Passwort zurücksetzen.")
        }
    }

    // MARK: - Passwort

    @ViewBuilder
    private var passwordSection: some View {
        Section {
            SecureField("Aktuelles Passwort", text: $currentPassword)
            SecureField("Neues Passwort", text: $newPassword)
            SecureField("Neues Passwort wiederholen", text: $newPasswordConfirm)

            Button {
                Task { await changePassword() }
            } label: {
                HStack {
                    Text("Passwort ändern")
                    if isChangingPassword {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canChangePassword)

            if let passwordStatus {
                Text(passwordStatus.text)
                    .font(.footnote)
                    .foregroundStyle(passwordStatus.isError ? .red : .green)
            }
        } header: {
            Text("Passwort ändern")
        } footer: {
            Text("Mindestens 8 Zeichen. Beim Ändern meldet der Server alle Geräte ab – diese App bleibt angemeldet, Home Assistant und andere Geräte brauchen aber einen neuen Zugang.")
        }
    }

    // MARK: - Benachrichtigungen

    @ViewBuilder
    private func notificationsSection(user: AuthUser) -> some View {
        Section {
            Toggle("Backup fehlgeschlagen", isOn: $notifyBackupFailed)
            Toggle("MyŠkoda-Fehler oder Key-Ablauf", isOn: $notifyMyskodaError)
            Toggle("Monatsbericht", isOn: $notifyMonthlyReport)
            if user.isAdmin {
                Toggle("Neue Registrierung", isOn: $notifyNewRegistration)
            }
            Picker("Zu prüfende Ladevorgänge", selection: $reviewDigest) {
                ForEach(ReviewDigestFrequency.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Button {
                Task { await saveNotifications() }
            } label: {
                HStack {
                    Text("Speichern")
                    if isSavingNotifications {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSavingNotifications)

            if let notificationStatus {
                Text(notificationStatus.text)
                    .font(.footnote)
                    .foregroundStyle(notificationStatus.isError ? .red : .green)
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            if user.email == nil || (user.email?.isEmpty ?? true) {
                Text("Trage oben eine E-Mail-Adresse ein, damit Benachrichtigungen ankommen können. Zusätzlich muss auf dem Server ein SMTP-Zugang eingerichtet sein.")
            } else {
                Text("Wird per E-Mail verschickt. Setzt voraus, dass auf dem Server ein SMTP-Zugang eingerichtet ist.")
            }
        }
    }

    // MARK: - Aktionen

    private func load() async {
        await session.reloadCurrentUser()
        applyFromUser()
    }

    /// Formularfelder aus dem aktuellen Nutzer befuellen. Die Schalter haben
    /// serverseitig Vorgabewerte; fehlen sie (aelterer Server), bleiben die
    /// hier gesetzten Standardwerte stehen.
    private func applyFromUser() {
        guard let user else { return }
        email = user.email ?? ""
        notifyBackupFailed = user.notifyBackupFailed ?? true
        notifyMyskodaError = user.notifyMyskodaError ?? true
        notifyMonthlyReport = user.notifyMonthlyReport ?? false
        notifyNewRegistration = user.notifyNewRegistration ?? true
        reviewDigest = user.reviewDigest ?? .off
    }

    private func saveEmail() async {
        emailStatus = nil
        isSavingEmail = true
        defer { isSavingEmail = false }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        do {
            let updated = try await APIClient.shared.updateEmail(
                trimmed.isEmpty ? nil : trimmed,
                currentPassword: emailPassword
            )
            session.applyUpdatedUser(updated)
            applyFromUser()
            emailPassword = ""
            emailStatus = StatusMessage(text: String(localized: "Gespeichert."), isError: false)
        } catch {
            emailStatus = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }

    private func resendVerification() async {
        emailStatus = nil
        do {
            try await APIClient.shared.resendEmailVerification()
            emailStatus = StatusMessage(text: String(localized: "Bestätigungsmail verschickt."), isError: false)
        } catch {
            emailStatus = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }

    private func changePassword() async {
        passwordStatus = nil
        isChangingPassword = true
        defer { isChangingPassword = false }
        do {
            try await session.changePassword(
                currentPassword: currentPassword, newPassword: newPassword
            )
            currentPassword = ""
            newPassword = ""
            newPasswordConfirm = ""
            passwordStatus = StatusMessage(text: String(localized: "Passwort geändert."), isError: false)
        } catch {
            passwordStatus = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }

    private func saveNotifications() async {
        notificationStatus = nil
        isSavingNotifications = true
        defer { isSavingNotifications = false }
        do {
            let updated = try await APIClient.shared.updateNotifications(
                NotificationSettingsPayload(
                    notifyBackupFailed: notifyBackupFailed,
                    notifyMyskodaError: notifyMyskodaError,
                    notifyMonthlyReport: notifyMonthlyReport,
                    notifyNewRegistration: notifyNewRegistration,
                    reviewDigest: reviewDigest
                )
            )
            session.applyUpdatedUser(updated)
            notificationStatus = StatusMessage(text: String(localized: "Gespeichert."), isError: false)
        } catch {
            notificationStatus = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }
}

#Preview {
    NavigationStack { AccountSettingsView() }
}
