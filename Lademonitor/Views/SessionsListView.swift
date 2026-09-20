import SwiftUI

struct SessionsListView: View {
    @State private var sessions: [ChargingSession] = []
    @State private var vehicles: [Vehicle] = []
    @State private var providers: [Provider] = []
    @State private var locations: [ChargingLocation] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingAddSheet = false
    @State private var showingNoVehicleAlert = false
    @State private var showingAddVehicleSheet = false
    @State private var showingFilterSheet = false
    /// Nur die ID wird gehalten, damit nach einem Reload (z.B. nach Bestaetigen)
    /// automatisch die frische Session-Instanz aus `sessions` angezeigt wird statt
    /// eines veralteten Snapshots.
    @State private var selectedSessionID: ChargingSession.ID?
    @ObservedObject private var sessionFilter = SessionFilter.shared

    /// Auf dem iPhone (compact) ist die Liste ein klassischer NavigationStack, auf
    /// dem iPad eine Master-Detail-Ansicht. Beide Wege teilen sich Liste, Toolbar
    /// und Sheets; nur die Navigation unterscheidet sich.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var selectedSession: ChargingSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            // Auf dem iPhone bewusst KEIN NavigationSplitView: dessen
            // zusammengefaltete Darstellung hat das Antippen einer Zeile nicht
            // zuverlaessig in die Detailansicht weitergeleitet. Ein expliziter
            // Push ueber navigationDestination(item:) tut das immer.
            NavigationStack {
                sessionsColumn(usesListSelection: false)
                    .navigationDestination(item: $selectedSessionID) { id in
                        if let session = sessions.first(where: { $0.id == id }) {
                            SessionDetailView(
                                session: session,
                                vehicles: vehicles,
                                providers: providers,
                                locations: locations,
                                // Zurueck-Pfeil der Navigation genuegt, der
                                // zusaetzliche Schliessen-Knopf entfaellt hier.
                                showsCloseButton: false,
                                onChanged: { Task { await load() } },
                                onClose: { selectedSessionID = nil }
                            )
                        } else {
                            ContentUnavailableView("Ladevorgang nicht gefunden", systemImage: "bolt.slash")
                        }
                    }
            }
        } else {
            NavigationSplitView {
                sessionsColumn(usesListSelection: true)
            } detail: {
                if let selectedSession {
                    SessionDetailView(
                        session: selectedSession,
                        vehicles: vehicles,
                        providers: providers,
                        locations: locations,
                        showsCloseButton: true,
                        onChanged: { Task { await load() } },
                        onClose: { selectedSessionID = nil }
                    )
                } else {
                    ContentUnavailableView("Ladevorgang auswählen", systemImage: "bolt.fill")
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    /// Die Liste samt Toolbar, Laden und Sheets - einmal fuer beide Navigationsarten.
    /// `usesListSelection` steuert, ob die Auswahl ueber `List(selection:)` (iPad)
    /// oder ueber einen Tap-Handler pro Zeile (iPhone) gesetzt wird.
    @ViewBuilder
    private func sessionsColumn(usesListSelection: Bool) -> some View {
        Group {
            if let errorMessage {
                ContentUnavailableView {
                    Label("Keine Verbindung", systemImage: "wifi.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Erneut versuchen") { Task { await load() } }
                }
            } else if sessions.isEmpty && !isLoading {
                ContentUnavailableView("Noch keine Ladevorgänge", systemImage: "bolt.slash")
            } else if usesListSelection {
                List(selection: $selectedSessionID) {
                    sessionRows(tagged: true)
                }
                .listStyle(.plain)
            } else {
                List {
                    sessionRows(tagged: false)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Ladevorgänge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if vehicles.isEmpty {
                        showingNoVehicleAlert = true
                    } else {
                        showingAddSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            FilterToolbarItem(isPresented: $showingFilterSheet)
        }
        .task(id: sessionFilter.dateRange) { await load() }
        .refreshable { await load() }
        .alert("Kein Fahrzeug vorhanden", isPresented: $showingNoVehicleAlert) {
            Button("Fahrzeug anlegen") { showingAddVehicleSheet = true }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bevor du einen Ladevorgang erfassen kannst, musst du mindestens ein Fahrzeug anlegen.")
        }
        .sheet(isPresented: $showingAddVehicleSheet) {
            AddEditVehicleView(vehicle: nil) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditSessionView(vehicles: vehicles, providers: providers, locations: locations, session: nil) {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func sessionRows(tagged: Bool) -> some View {
        ForEach(sessions) { session in
            if tagged {
                row(for: session)
                    .tag(session.id)
                    .swipeActions(edge: .leading) { confirmSwipeButton(for: session) }
            } else {
                Button {
                    selectedSessionID = session.id
                } label: {
                    row(for: session)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) { confirmSwipeButton(for: session) }
            }
        }
        .onDelete(perform: delete)
    }

    private func row(for session: ChargingSession) -> some View {
        SessionRow(
            session: session,
            vehicleName: vehicles.first(where: { $0.id == session.vehicleId })?.name,
            providerName: providers.first(where: { $0.id == session.providerId })?.name,
            locationName: locations.first(where: { $0.id == session.locationId })?.name
        )
    }

    @ViewBuilder
    private func confirmSwipeButton(for session: ChargingSession) -> some View {
        if session.needsReview {
            Button {
                Task { await confirm(session) }
            } label: {
                Label("Bestätigen", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let s = AppRepository.shared.fetchSessions(dateRange: sessionFilter.dateRange)
            async let v = AppRepository.shared.fetchVehicles()
            async let p = AppRepository.shared.fetchProviders()
            async let l = AppRepository.shared.fetchLocations()
            let (fetchedSessions, fetchedVehicles, fetchedProviders, fetchedLocations) = try await (s, v, p, l)
            sessions = fetchedSessions
            vehicles = fetchedVehicles
            providers = fetchedProviders
            locations = fetchedLocations
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { sessions[$0] }
        sessions.remove(atOffsets: offsets)
        Task {
            for session in toDelete {
                try? await AppRepository.shared.deleteSession(id: session.id)
            }
        }
    }

    /// Markiert einen automatisch erkannten Ladevorgang als geprüft (Swipe-Geste),
    /// ohne den vollen Bearbeiten-Dialog zu öffnen.
    private func confirm(_ session: ChargingSession) async {
        guard let updated = try? await AppRepository.shared.updateSession(
            id: session.id,
            ChargingSessionPayload(needsReview: false)
        ) else { return }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updated
        }
    }
}

private struct SessionRow: View {
    let session: ChargingSession
    let vehicleName: String?
    let providerName: String?
    /// Name des verknuepften Ladeorts (aus locationId). Fallback wenn geocodedPlace nil ist,
    /// z.B. bei automatisch importierten Sessions ohne freien Ortstext.
    let locationName: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    private static let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        f.maximumFractionDigits = 0
        return f
    }()

    /// Zweite Detailzeile: SoC-Verlauf und Kilometerstand, falls vorhanden.
    private var detailsLine: String {
        var parts: [String] = []
        switch (session.socStart, session.socEnd) {
        case let (start?, end?):
            parts.append(String(localized: "SoC \(start) → \(end) %"))
        case let (start?, nil):
            parts.append(String(localized: "SoC ab \(start) %"))
        case let (nil, end?):
            parts.append(String(localized: "SoC bis \(end) %"))
        default:
            break
        }
        if let km = session.odometerKm {
            let formatted = Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(km)"
            parts.append("\(formatted) km")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: session.startTime))
                        .font(.subheadline.bold())
                    if let type = session.chargingType {
                        ChargingTypeBadge(type: type)
                    }
                    if session.needsReview {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                // geocodedPlace hat Vorrang; locationName dient als Fallback fuer
                // auto-importierte Sessions ohne freien Ortstext.
                let place = session.geocodedPlace ?? locationName
                let subtitle = [vehicleName, providerName, place].compactMap { $0 }.joined(separator: " · ")
                let hasCoordinates = session.latitude != nil && session.longitude != nil
                if !subtitle.isEmpty || hasCoordinates {
                    HStack(spacing: 3) {
                        if !subtitle.isEmpty {
                            Text(subtitle)
                        }
                        if hasCoordinates {
                            Image(systemName: "mappin.circle.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !detailsLine.isEmpty {
                    Text(detailsLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let consumption = session.consumptionKwhPer100km,
                   let method = session.consumptionMethodValue,
                   method != .unavailable {
                    HStack(spacing: 4) {
                        if !method.marker.isEmpty {
                            Text(method.marker)
                        }
                        Text(String(format: "%.1f kWh/100km", consumption))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Text("\(method.marker) \(method.shortLabel)")
                        Text(method.explanation)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let kwh = session.energyKwh {
                    Text(String(format: "%.1f kWh", kwh))
                        .font(.subheadline)
                }
                if let price = session.priceTotal {
                    Text(String(format: "%.2f €", price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pricePerKwh = session.pricePerKwh {
                    Text(String(format: "%.3f €/kWh", pricePerKwh))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Kleines ovales Badge mit "AC" bzw. "DC".
private struct ChargingTypeBadge: View {
    let type: ChargingType

    private var color: Color { type == .dc ? .orange : .blue }

    var body: some View {
        Text(type.rawValue)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    SessionsListView()
}
