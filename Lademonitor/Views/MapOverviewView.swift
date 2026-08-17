import SwiftUI
import MapKit

/// Uebersichts-Karte (3. Tab): zeigt alle bekannten Ladeorte und alle
/// Ladevorgaenge mit eigenen Koordinaten gemeinsam auf einer Standard-Apple-Karte.
struct MapOverviewView: View {
    @State private var locations: [ChargingLocation] = []
    @State private var sessions: [ChargingSession] = []
    @State private var vehicles: [Vehicle] = []
    @State private var providers: [Provider] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showLocations = true
    @State private var showSessions = true

    /// Tag der Map-Auswahl - wird nur als einmaliger Tap-Trigger genutzt, siehe
    /// onChange unten (danach sofort wieder auf nil gesetzt).
    private enum MapTag: Hashable {
        case location(String)
        case session(String)
    }
    @State private var selectedTag: MapTag?
    @State private var locationToEdit: ChargingLocation?
    @State private var sessionToPreview: ChargingSession?

    private struct SessionPin: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let label: String
        let needsReview: Bool
    }

    private static let pinDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private var sessionPins: [SessionPin] {
        sessions.compactMap { session in
            guard let lat = session.latitude, let lon = session.longitude else { return nil }
            return SessionPin(
                id: session.id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                label: Self.pinDateFormatter.string(from: session.startTime),
                needsReview: session.needsReview
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Keine Verbindung", systemImage: "wifi.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Erneut versuchen") { Task { await load() } }
                    }
                } else if locations.isEmpty && sessionPins.isEmpty && !isLoading {
                    ContentUnavailableView("Keine Standorte vorhanden", systemImage: "map")
                } else {
                    Map(position: $cameraPosition, selection: $selectedTag) {
                        if showLocations {
                            ForEach(locations) { location in
                                Marker(
                                    location.name,
                                    systemImage: "bolt.car.fill",
                                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                                )
                                .tint(.blue)
                                .tag(MapTag.location(location.id))
                            }
                        }
                        if showSessions {
                            ForEach(sessionPins) { pin in
                                Marker(pin.label, systemImage: "bolt.fill", coordinate: pin.coordinate)
                                    .tint(pin.needsReview ? .orange : .gray)
                                    .tag(MapTag.session(pin.id))
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .safeAreaInset(edge: .bottom) { legend }
                }
            }
            .navigationTitle("Karte")
            .task { await load() }
            .refreshable { await load() }
            // Tap auf einen Marker: Ladeort -> direkt in den Bearbeiten-Dialog
            // (derselbe wie unter Einstellungen -> Ladeorte), Ladevorgang -> in
            // dieselbe Vorschau wie in der Ladevorgänge-Liste. selectedTag dient
            // dabei nur als einmaliger Trigger, deshalb sofort wieder zuruecksetzen.
            .onChange(of: selectedTag) { _, newValue in
                guard let newValue else { return }
                switch newValue {
                case .location(let id):
                    locationToEdit = locations.first { $0.id == id }
                case .session(let id):
                    sessionToPreview = sessions.first { $0.id == id }
                }
                selectedTag = nil
            }
            .sheet(item: $locationToEdit) { location in
                AddEditLocationView(location: location, providers: providers) {
                    Task { await load() }
                }
            }
            .sheet(item: $sessionToPreview) { session in
                SessionDetailView(
                    session: session,
                    vehicles: vehicles,
                    providers: providers,
                    locations: locations
                ) {
                    Task { await load() }
                }
            }
        }
    }

    /// Antippbare Legende: tippen blendet die jeweilige Marker-Gruppe auf der Karte aus/ein.
    private var legend: some View {
        HStack(spacing: 12) {
            LegendToggle(title: "Ladeorte", systemImage: "bolt.car.fill", color: .blue, isOn: $showLocations)
            LegendToggle(title: "Ladevorgänge", systemImage: "bolt.fill", color: .gray, isOn: $showSessions)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 8)
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = "Bitte zuerst die Server-Adresse in den Einstellungen eintragen."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let l = AppRepository.shared.fetchLocations()
            async let s = AppRepository.shared.fetchSessions()
            async let v = AppRepository.shared.fetchVehicles()
            async let p = AppRepository.shared.fetchProviders()
            let (fetchedLocations, fetchedSessions, fetchedVehicles, fetchedProviders) = try await (l, s, v, p)
            locations = fetchedLocations
            sessions = fetchedSessions
            vehicles = fetchedVehicles
            providers = fetchedProviders
            fitCamera()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Setzt die Kamera einmalig nach dem Laden auf einen Bereich, der alle Punkte umfasst.
    private func fitCamera() {
        let coordinates = locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            + sessionPins.map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// Ein Legenden-Eintrag, der gleichzeitig als Filter-Button dient - ausgegraut,
/// wenn die zugehoerige Marker-Gruppe gerade ausgeblendet ist.
private struct LegendToggle: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isOn ? color : .secondary)
                .strikethrough(!isOn)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MapOverviewView()
}
