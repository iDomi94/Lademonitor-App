import SwiftUI
import MapKit

/// Uebersichts-Karte (3. Tab): zeigt alle bekannten Ladeorte (inkl. Matching-Radius) und
/// alle Ladevorgaenge mit eigenen Koordinaten gemeinsam auf einer Standard-Apple-Karte.
/// Ladevorgaenge werden je nach aktuellem Zoom geclustert (siehe sessionClusters).
struct MapOverviewView: View {
    @State private var locations: [ChargingLocation] = []
    @State private var sessions: [ChargingSession] = []
    @State private var vehicles: [Vehicle] = []
    @State private var providers: [Provider] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentSpan = MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
    @State private var showLocations = true
    @State private var showSessions = true
    @State private var showingFilterSheet = false
    @ObservedObject private var sessionFilter = SessionFilter.shared

    /// Tag der Map-Auswahl fuer Ladeorte - wird nur als einmaliger Tap-Trigger genutzt,
    /// siehe onChange unten (danach sofort wieder auf nil gesetzt). Ladevorgaenge laufen
    /// NICHT mehr hierueber, da sie geclustert und per eigenem Button-Tap behandelt werden
    /// (siehe handleClusterTap).
    private enum MapTag: Hashable {
        case location(String)
    }
    @State private var selectedTag: MapTag?
    @State private var locationToEdit: ChargingLocation?
    @State private var sessionToPreview: ChargingSession?

    /// Kapselt die Ladevorgaenge eines anzuzeigenden Clusters als Identifiable, damit
    /// .sheet(item:) verwendet werden kann – das vermeidet den SwiftUI-Timing-Bug,
    /// bei dem der Sheet-Inhalt clusterListSessions vor dem Commit des State-Updates liest.
    private struct ClusterListItem: Identifiable {
        let id = UUID()
        let sessions: [ChargingSession]
    }
    @State private var clusterListItem: ClusterListItem?

    private struct SessionPin: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let label: String
        let needsReview: Bool
    }

    /// Eine oder mehrere raeumlich nahe beieinanderliegende Sessions, siehe sessionClusters.
    private struct SessionCluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let pins: [SessionPin]
        var count: Int { pins.count }
        var needsReview: Bool { pins.contains(where: \.needsReview) }
    }

    private static let pinDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale.current
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

    /// Gruppiert Pins, die naeher beieinanderliegen als ein an den aktuellen Zoom
    /// gekoppelter Schwellwert (einfaches Single-Linkage-Clustering, reicht fuer die
    /// ueblichen Groessenordnungen eines persoenlichen Lade-Logs). Bei einem einzelnen
    /// Mitglied entspricht das Cluster einem normalen Einzel-Pin.
    private var sessionClusters: [SessionCluster] {
        let threshold = max(currentSpan.latitudeDelta, currentSpan.longitudeDelta) * 0.06
        var remaining = sessionPins
        var clusters: [SessionCluster] = []
        while let first = remaining.first {
            var group = [first]
            remaining.removeFirst()
            remaining.removeAll { pin in
                let close = abs(pin.coordinate.latitude - first.coordinate.latitude) < threshold
                    && abs(pin.coordinate.longitude - first.coordinate.longitude) < threshold
                if close { group.append(pin) }
                return close
            }
            let avgLat = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
            let avgLon = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
            clusters.append(SessionCluster(
                id: group.map(\.id).sorted().joined(separator: "|"),
                coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                pins: group
            ))
        }
        return clusters
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
                                let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                                // Matching-Radius als Kreis, damit sichtbar wird, wie nah ein
                                // Ladevorgang liegen muss, um automatisch diesem Ort zugeordnet
                                // zu werden - vor dem Marker gezeichnet, damit der Pin oben liegt.
                                MapCircle(center: coordinate, radius: Double(location.radiusM))
                                    .foregroundStyle(.blue.opacity(0.12))
                                    .stroke(.blue.opacity(0.5), lineWidth: 1)
                                Marker(location.name, systemImage: "bolt.car.fill", coordinate: coordinate)
                                    .tint(.blue)
                                    .tag(MapTag.location(location.id))
                            }
                        }
                        if showSessions {
                            ForEach(sessionClusters) { cluster in
                                Annotation(
                                    cluster.count > 1 ? String(localized: "\(cluster.count) Ladevorgänge") : (cluster.pins.first?.label ?? ""),
                                    coordinate: cluster.coordinate
                                ) {
                                    Button {
                                        handleClusterTap(cluster)
                                    } label: {
                                        if cluster.count > 1 {
                                            ClusterBadge(count: cluster.count, needsReview: cluster.needsReview)
                                        } else {
                                            SessionPinBadge(needsReview: cluster.needsReview)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        currentSpan = context.region.span
                    }
                    .safeAreaInset(edge: .bottom) { legend }
                }
            }
            .navigationTitle("Karte")
            .toolbar {
                FilterToolbarItem(isPresented: $showingFilterSheet)
            }
            .task(id: sessionFilter.dateRange) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheetView()
            }
            // Tap auf einen Ladeort-Marker -> direkt in den Bearbeiten-Dialog (derselbe wie
            // unter Einstellungen -> Ladeorte). selectedTag dient dabei nur als einmaliger
            // Trigger, deshalb sofort wieder zuruecksetzen.
            .onChange(of: selectedTag) { _, newValue in
                guard let newValue else { return }
                switch newValue {
                case .location(let id):
                    locationToEdit = locations.first { $0.id == id }
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
            // sheet(item:) statt sheet(isPresented:) + separater State-Variable, damit
            // die Sessions atomar mit der Sheet-Praesentation uebergeben werden und kein
            // SwiftUI-Timing-Bug zu einer leeren Liste fuehren kann.
            .sheet(item: $clusterListItem) { item in
                ClusterSessionListSheet(sessions: item.sessions, vehicles: vehicles, providers: providers) { session in
                    clusterListItem = nil
                    sessionToPreview = session
                }
            }
        }
    }

    /// Tap auf ein Cluster: bei genau einer Session direkt die Vorschau oeffnen. Bei
    /// mehreren wird geprueft, ob sie geografisch tatsaechlich auseinanderliegen (dann
    /// reinzoomen, bis sie einzeln sichtbar sind) oder praktisch am selben Punkt liegen
    /// (z.B. mehrmals an derselben Wallbox geladen) - dann bringt weiteres Zoomen nichts,
    /// stattdessen oeffnet sich eine Liste der betroffenen Ladevorgaenge.
    private func handleClusterTap(_ cluster: SessionCluster) {
        guard cluster.count > 1 else {
            sessionToPreview = sessions.first { $0.id == cluster.pins[0].id }
            return
        }
        let lats = cluster.pins.map { $0.coordinate.latitude }
        let lons = cluster.pins.map { $0.coordinate.longitude }
        let rawLatSpan = (lats.max() ?? 0) - (lats.min() ?? 0)
        let rawLonSpan = (lons.max() ?? 0) - (lons.min() ?? 0)
        // ~11m - innerhalb dieser Distanz gelten Punkte als "derselbe Ort", Zoomen wuerde
        // sie nicht mehr sichtbar trennen.
        let sameSpotEpsilon = 0.0001
        if rawLatSpan < sameSpotEpsilon && rawLonSpan < sameSpotEpsilon {
            let matched = cluster.pins.compactMap { pin in sessions.first { $0.id == pin.id } }
            clusterListItem = ClusterListItem(sessions: matched)
            return
        }
        let center = CLLocationCoordinate2D(
            latitude: ((lats.max() ?? 0) + (lats.min() ?? 0)) / 2,
            longitude: ((lons.max() ?? 0) + (lons.min() ?? 0)) / 2
        )
        let minZoomSpan = 0.001
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: max(rawLatSpan * 2.5, minZoomSpan),
                    longitudeDelta: max(rawLonSpan * 2.5, minZoomSpan)
                )
            ))
        }
    }

    /// Antippbare Legende: tippen blendet die jeweilige Marker-Gruppe auf der Karte aus/ein.
    private var legend: some View {
        HStack(spacing: 12) {
            LegendToggle(title: String(localized: "Ladeorte"), systemImage: "bolt.car.fill", color: .blue, isOn: $showLocations)
            LegendToggle(title: String(localized: "Ladevorgänge"), systemImage: "bolt.fill", color: .gray, isOn: $showSessions)
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
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let l = AppRepository.shared.fetchLocations()
            async let s = AppRepository.shared.fetchSessions(dateRange: sessionFilter.dateRange)
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
        // .onMapCameraChange feuert erst nach Nutzerinteraktion - ohne das hier direkt
        // zu setzen, wuerde bis zur ersten Beruehrung der Karte mit einem viel zu groben
        // Default-Span geclustert (siehe currentSpan-Initialwert oben).
        currentSpan = span
    }
}

/// Zahlen-Badge fuer ein Cluster mit mehreren Ladevorgaengen.
private struct ClusterBadge: View {
    let count: Int
    let needsReview: Bool

    var body: some View {
        Text("\(count)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(minWidth: 28, minHeight: 28)
            .background(needsReview ? Color.orange : Color.blue)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }
}

/// Pin fuer ein Cluster mit genau einer Session (visuell identisch zum frueheren Marker).
private struct SessionPinBadge: View {
    let needsReview: Bool

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(6)
            .background(needsReview ? Color.orange : Color.gray)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(radius: 2)
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

/// Liste der Ladevorgaenge eines Clusters, das geografisch nicht weiter auftrennbar ist
/// (siehe handleClusterTap) - Antippen einer Zeile oeffnet die normale Detail-Vorschau.
private struct ClusterSessionListSheet: View {
    let sessions: [ChargingSession]
    let vehicles: [Vehicle]
    let providers: [Provider]
    let onSelect: (ChargingSession) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                Button {
                    onSelect(session)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.dateFormatter.string(from: session.startTime))
                                .font(.subheadline)
                            let vehicleName = vehicles.first { $0.id == session.vehicleId }?.name
                            let providerName = providers.first { $0.id == session.providerId }?.name
                            let subtitle = [vehicleName, providerName].compactMap { $0 }.joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let kwh = session.energyKwh {
                            Text(String(format: "%.1f kWh", kwh))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("\(sessions.count) Ladevorgänge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    MapOverviewView()
}
