import SwiftUI
import MapKit

/// Read-only Vorschau eines Ladevorgangs (Antippen in der Liste oeffnet erst
/// diese Ansicht statt direkt den Bearbeiten-Dialog). Bietet von hier aus
/// Bearbeiten, Bestaetigen (needs_review) und Abbrechen an.
struct SessionDetailView: View {
    let session: ChargingSession
    let vehicles: [Vehicle]
    let providers: [Provider]
    let locations: [ChargingLocation]
    /// Wird nach Bestaetigen oder Bearbeiten aufgerufen, damit die Liste dahinter neu laedt.
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var vehicleName: String? { vehicles.first(where: { $0.id == session.vehicleId })?.name }
    private var providerName: String? { providers.first(where: { $0.id == session.providerId })?.name }
    private var locationName: String? { locations.first(where: { $0.id == session.locationId })?.name }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        f.locale = Locale.current
        return f
    }()

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = session.latitude, let lon = session.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var socText: String {
        switch (session.socStart, session.socEnd) {
        case let (start?, end?): return String(localized: "\(start) → \(end) %")
        case let (start?, nil): return String(localized: "ab \(start) %")
        case let (nil, end?): return String(localized: "bis \(end) %")
        default: return "–"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let coordinate {
                    Section {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker(locationName ?? session.geocodedPlace ?? String(localized: "Ladevorgang"), coordinate: coordinate)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section("Fahrzeug & Zeit") {
                    LabeledContent("Fahrzeug", value: vehicleName ?? "–")
                    LabeledContent("Start", value: Self.dateFormatter.string(from: session.startTime))
                    if let type = session.chargingType {
                        LabeledContent("Lade-Art", value: type.rawValue)
                    }
                }

                Section("Ort & Anbieter") {
                    LabeledContent("Anbieter", value: providerName ?? "–")
                    LabeledContent("Ort", value: session.geocodedPlace ?? locationName ?? "–")
                }

                Section("Akkustand & Energie") {
                    if session.socStart != nil || session.socEnd != nil {
                        LabeledContent("SoC", value: socText)
                    }
                    if let kwh = session.energyKwh {
                        LabeledContent(
                            "kWh",
                            value: String(format: "%.2f kWh", kwh) + (session.energyIsEstimated ? String(localized: " (geschätzt)") : "")
                        )
                    }
                    if let odo = session.odometerKm {
                        LabeledContent("Kilometerstand", value: "\(odo) km")
                    }
                    if let consumption = session.consumptionKwhPer100km {
                        LabeledContent("Verbrauch", value: String(format: "%.1f kWh/100km", consumption))
                    }
                }

                if session.priceTotal != nil || session.pricePerKwh != nil {
                    Section("Preis") {
                        if let priceTotal = session.priceTotal {
                            LabeledContent("Gesamt", value: String(format: "%.2f €", priceTotal))
                        }
                        if let pricePerKwh = session.pricePerKwh {
                            LabeledContent("Pro kWh", value: String(format: "%.4f €", pricePerKwh))
                        }
                    }
                }

                Section("Quelle") {
                    LabeledContent("Erfasst als", value: session.source.displayName)
                    LabeledContent("Status", value: session.needsReview ? String(localized: "Zu prüfen") : String(localized: "Geprüft"))
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Ladevorgang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if session.needsReview {
                        Button {
                            Task { await confirm() }
                        } label: {
                            if isConfirming {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                        .tint(.green)
                        .disabled(isConfirming)
                    }
                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                AddEditSessionView(vehicles: vehicles, providers: providers, locations: locations, session: session) {
                    onChanged()
                    dismiss()
                }
            }
        }
    }

    /// Setzt needs_review direkt zurueck, ohne den Bearbeiten-Dialog zu oeffnen.
    private func confirm() async {
        isConfirming = true
        errorMessage = nil
        do {
            _ = try await AppRepository.shared.updateSession(id: session.id, ChargingSessionPayload(needsReview: false))
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConfirming = false
    }
}

#Preview {
    SessionDetailView(
        session: ChargingSession(
            id: "1", vehicleId: "v1", providerId: nil, locationId: nil,
            startTime: Date(), endTime: nil, chargingType: .ac,
            socStart: 20, socEnd: 80, energyKwh: 30, energyIsEstimated: false,
            odometerKm: 12345, priceTotal: 12.5, pricePerKwh: 0.42,
            latitude: 48.7758, longitude: 9.1829, geocodedPlace: "Stuttgart",
            consumptionKwhPer100km: 18.2, consumptionMethod: "soc_corrected",
            notes: nil, source: .automatic, needsReview: true, externalSessionId: nil
        ),
        vehicles: [], providers: [], locations: [], onChanged: {}
    )
}
