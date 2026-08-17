import SwiftUI

struct LocationsSettingsView: View {
    @State private var locations: [ChargingLocation] = []
    @State private var providers: [Provider] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingAdd = false
    @State private var editing: ChargingLocation?
    @State private var pendingDelete: ChargingLocation?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(locations) { location in
                Button {
                    editing = location
                } label: {
                    LocationRow(
                        location: location,
                        providerName: providers.first(where: { $0.id == location.defaultProviderId })?.name
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDelete = location
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Ladeorte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) {
            AddEditLocationView(location: nil, providers: providers) { Task { await load() } }
        }
        .sheet(item: $editing) { location in
            AddEditLocationView(location: location, providers: providers) { Task { await load() } }
        }
        .alert("Ladeort löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { location in
            Button("Löschen", role: .destructive) { Task { await delete(location) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { location in
            Text("„\(location.name)“ wird gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = "Bitte zuerst die Server-Adresse in den Einstellungen eintragen."
            return
        }
        isLoading = true
        do {
            async let l = AppRepository.shared.fetchLocations()
            async let p = AppRepository.shared.fetchProviders()
            let (fetchedLocations, fetchedProviders) = try await (l, p)
            locations = fetchedLocations
            providers = fetchedProviders
            errorMessage = nil
        } catch {
            if locations.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func delete(_ location: ChargingLocation) async {
        do {
            try await AppRepository.shared.deleteLocation(id: location.id)
            locations.removeAll { $0.id == location.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LocationRow: View {
    let location: ChargingLocation
    let providerName: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.body)
                let detail = [
                    String(format: "%.5f, %.5f", location.latitude, location.longitude),
                    "Radius \(location.radiusM) m",
                    providerName
                ].compactMap { $0 }.joined(separator: " · ")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct AddEditLocationView: View {
    let location: ChargingLocation?
    let providers: [Provider]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radiusM: String
    @State private var defaultProviderId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Adresssuche (Forward-Geocoding)
    @State private var addressQuery: String = ""
    @State private var searchResults: [GeocodeResult] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    // Aktueller Standort (GPS)
    @StateObject private var locationProvider = CurrentLocationProvider()
    @State private var isLocating = false

    init(location: ChargingLocation?, providers: [Provider], onSaved: @escaping () -> Void) {
        self.location = location
        self.providers = providers
        self.onSaved = onSaved
        _name = State(initialValue: location?.name ?? "")
        _latitude = State(initialValue: location.map { String(format: "%.6f", $0.latitude) } ?? "")
        _longitude = State(initialValue: location.map { String(format: "%.6f", $0.longitude) } ?? "")
        _radiusM = State(initialValue: location.map { String($0.radiusM) } ?? "100")
        _defaultProviderId = State(initialValue: location?.defaultProviderId)
    }

    private var isEditing: Bool { location != nil }

    private var parsedLatitude: Double? { Double(latitude.replacingOccurrences(of: ",", with: ".")) }
    private var parsedLongitude: Double? { Double(longitude.replacingOccurrences(of: ",", with: ".")) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedLatitude != nil
            && parsedLongitude != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ladeort") {
                    TextField("Name", text: $name)
                }

                Section {
                    HStack {
                        TextField("Adresse suchen", text: $addressQuery)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit { Task { await searchAddress() } }
                        if isSearching {
                            ProgressView()
                        } else {
                            Button {
                                Task { await searchAddress() }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .disabled(addressQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    if let searchMessage {
                        Text(searchMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(searchResults, id: \.self) { result in
                        Button {
                            select(result)
                        } label: {
                            Text(result.displayName)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text("Adresssuche")
                } footer: {
                    Text("Freitext wie „Straße Hausnummer, Ort“, ein Ortsname oder ein POI. Ein Treffer füllt Breite/Länge unten aus – du kannst die Werte danach weiter anpassen.")
                }

                Section {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack {
                            Label("Aktueller Standort", systemImage: "location.fill")
                            if isLocating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLocating)

                    HStack {
                        Text("Breite (lat)")
                        Spacer()
                        TextField("z.B. 48.153770", text: $latitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Länge (lon)")
                        Spacer()
                        TextField("z.B. 8.299507", text: $longitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Radius (m)")
                        Spacer()
                        TextField("100", text: $radiusM)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Position")
                } footer: {
                    Text("Koordinaten in Dezimalgrad. Der Radius bestimmt, wie nah ein Ladevorgang sein muss, um automatisch diesem Ort zugeordnet zu werden.")
                }

                Section("Standard-Anbieter") {
                    Picker("Anbieter", selection: $defaultProviderId) {
                        Text("– keiner –").tag(String?.none)
                        ForEach(providers) { provider in
                            Text(provider.name).tag(String?.some(provider.id))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Ladeort bearbeiten" : "Neuer Ladeort")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !canSave)
                }
            }
        }
    }

    private func searchAddress() async {
        let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        do {
            let results = try await AppRepository.shared.forwardGeocode(query: query)
            searchResults = results
            if results.isEmpty {
                searchMessage = "Keine Treffer. Bitte die Koordinaten unten manuell eintragen."
            }
        } catch {
            searchResults = []
            searchMessage = "Suche fehlgeschlagen. Bitte die Koordinaten unten manuell eintragen."
        }
        isSearching = false
    }

    private func select(_ result: GeocodeResult) {
        latitude = String(format: "%.6f", result.latitude)
        longitude = String(format: "%.6f", result.longitude)
        addressQuery = result.displayName
        searchResults = []
        searchMessage = nil
    }

    private func useCurrentLocation() async {
        isLocating = true
        errorMessage = nil
        do {
            let coordinate = try await locationProvider.requestCurrentLocation()
            latitude = String(format: "%.6f", coordinate.latitude)
            longitude = String(format: "%.6f", coordinate.longitude)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLocating = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let payload = LocationPayload(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: parsedLatitude,
            longitude: parsedLongitude,
            radiusM: Int(radiusM) ?? 100,
            defaultProviderId: defaultProviderId
        )

        do {
            if let location {
                _ = try await AppRepository.shared.updateLocation(id: location.id, payload)
            } else {
                _ = try await AppRepository.shared.createLocation(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack { LocationsSettingsView() }
}
