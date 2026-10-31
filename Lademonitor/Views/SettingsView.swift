import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var syncService = SyncService.shared
    @State private var showingResetConfirmation = false
    @State private var resetErrorMessage: String?
    @State private var showingOnboarding = false
    @AppStorage(ReminderNotificationScheduler.enabledKey) private var reminderNotifications = true

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        return f
    }()

    /// Aufgeklappt (iPhone Duo innen, iPad) wie die iOS-Einstellungen:
    /// Liste links, Unterseite rechts. Zugeklappt ein NavigationStack wie
    /// bisher. Die Auswahl liegt hier, damit sie das Auf- und Zuklappen
    /// uebersteht.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedRoute: SettingsRoute?

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    settingsList
                        .navigationDestination(for: SettingsRoute.self) { route in
                            destination(route)
                        }
                }
            } else {
                NavigationSplitView {
                    settingsList
                } detail: {
                    if let selectedRoute {
                        NavigationStack {
                            destination(selectedRoute)
                        }
                        .id(selectedRoute)
                    } else {
                        ContentUnavailableView("Bereich auswählen", systemImage: "gearshape")
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(context: .replay) { showingOnboarding = false }
        }
        .alert("Alle lokalen Daten löschen?", isPresented: $showingResetConfirmation) {
            Button("Löschen", role: .destructive) { resetAllData() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das kann nicht rückgängig gemacht werden.")
        }
    }

    /// Nur aufgeklappt eine Auswahl - im NavigationStack schieben die
    /// Wert-Links die Unterseite ueber `navigationDestination`.
    private var listSelection: Binding<SettingsRoute?>? {
        horizontalSizeClass == .compact ? nil : $selectedRoute
    }

    private var settingsList: some View {
        List(selection: listSelection) {
            Section("Verwaltung") {
                NavigationLink(value: SettingsRoute.locations) {
                    Label("Ladeorte", systemImage: "mappin.and.ellipse")
                }
                NavigationLink(value: SettingsRoute.vehicles) {
                    Label("Fahrzeuge", systemImage: "car.fill")
                }
                NavigationLink(value: SettingsRoute.providers) {
                    Label("Anbieter", systemImage: "bolt.fill")
                }
                NavigationLink(value: SettingsRoute.fees) {
                    Label("Grundgebühren", systemImage: "creditcard")
                }
                // Kosten und Erinnerungen hingen frueher in der
                // Fahrzeug-Detailansicht - dort waren sie zu versteckt.
                NavigationLink(value: SettingsRoute.costs) {
                    Label("Kosten", systemImage: "eurosign.circle")
                }
                NavigationLink(value: SettingsRoute.reminders) {
                    Label("Erinnerungen", systemImage: "bell")
                }
                // Fuer den Rueckblick und das Verbrenner-Tool, in beiden Modi.
                NavigationLink(value: SettingsRoute.comparisonVehicle) {
                    Label("Vergleichsfahrzeug", systemImage: "fuelpump")
                }
                // Reifen gibt es bewusst nur im Server-Modus: die Zuordnung
                // der Fahrten und der temperaturbereinigte Vergleich liegen
                // komplett auf dem Server (siehe TireModels.swift).
                if settings.appMode == .server {
                    NavigationLink(value: SettingsRoute.tires) {
                        Label("Reifen", systemImage: "circle.circle")
                    }
                }
            }

            Section("Darstellung") {
                NavigationLink(value: SettingsRoute.chargeBar) {
                    Label("Ladebalken", systemImage: "battery.75percent")
                }
            }

            Section {
                Toggle(isOn: $reminderNotifications) {
                    Label("Mitteilungen für Erinnerungen", systemImage: "bell.badge")
                }
                .onChange(of: reminderNotifications) { _, enabled in
                    Task {
                        if enabled { await ReminderNotificationScheduler.requestAuthorizationIfNeeded() }
                        await ReminderNotificationScheduler.rescheduleNow()
                    }
                }
            } header: {
                Text("Mitteilungen")
            } footer: {
                Text("Zu Beginn des Vorlaufs und am Fälligkeitstag um 9 Uhr, auch ohne Server. Wurden Mitteilungen abgelehnt, lassen sie sich in den iOS-Einstellungen wieder erlauben.")
            }

            Section("Server") {
                NavigationLink(value: SettingsRoute.server) {
                    Label("Server & Verbindung", systemImage: "network")
                }
            }

            Section("Hilfe") {
                Button {
                    showingOnboarding = true
                } label: {
                    Label("Einführung erneut ansehen", systemImage: "sparkles")
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
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .locations: LocationsSettingsView()
        case .vehicles: VehiclesSettingsView()
        case .providers: ProvidersSettingsView()
        case .fees: FeesSettingsView()
        case .costs: VehicleScopedView(title: "Kosten") { VehicleCostsView(vehicle: $0) }
        case .reminders: VehicleScopedView(title: "Erinnerungen") { RemindersView(vehicle: $0) }
        case .comparisonVehicle: ComparisonVehicleSettingsView()
        case .tires: TiresSettingsView()
        case .chargeBar: ChargeBarSettingsView()
        case .server: ServerSettingsView()
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

/// Unterseiten der Einstellungen - als Werte, damit dieselbe Liste im
/// NavigationStack (zugeklappt) und als Seitenleiste (aufgeklappt) dient.
enum SettingsRoute: Hashable {
    case locations, vehicles, providers, fees, costs, reminders, comparisonVehicle, tires, chargeBar, server
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

    private var hostingBinding: Binding<AppSettings.ServerHosting> {
        Binding(get: { settings.serverHosting }, set: { settings.serverHosting = $0 })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Aktuell", value: settings.appMode == .localOnly ? String(localized: "Nur lokal") : String(localized: "Server"))
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
                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        Label("E-Mail, Passwort & Benachrichtigungen", systemImage: "person.crop.circle")
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
                Picker("Hosting", selection: hostingBinding) {
                    ForEach(AppSettings.ServerHosting.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                if settings.serverHosting == .selfHosted {
                    TextField("https://lademonitor.example.com", text: $settings.serverURLString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            } header: {
                Text("Server-Adresse")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    switch settings.serverHosting {
                    case .selfHosted:
                        Text("Domain deines eigenen Lademonitor-Servers. Ein \"https://\" wird automatisch ergänzt, falls du es weglässt.")
                    case .cloud:
                        Text("Läuft auf lademonitor.cloud – Betrieb, Updates und Backups übernimmt der Betreiber für dich.")
                    }
                    Link("Quellcode auf GitHub", destination: URL(string: "https://github.com/iDomi94/Lademonitor-Server")!)
                }
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
            Text("Nach der Anmeldung wirst du gefragt, ob deine bisherigen lokalen Daten in das Konto hochgeladen oder vom Gerät gelöscht werden sollen. Du kannst jederzeit in den Einstellungen zurück zu \"Nur lokal\" wechseln.")
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let ok = try await APIClient.shared.checkHealth()
            testResult = ok ? .success : .failure(String(localized: "Server antwortet, aber Status ist nicht \"ok\"."))
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
