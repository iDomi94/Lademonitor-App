import SwiftUI

struct AddEditSessionView: View {
    let vehicles: [Vehicle]
    let providers: [Provider]
    let session: ChargingSession?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String
    @State private var providerId: String?
    @State private var startTime: Date
    @State private var chargingType: ChargingType
    @State private var socEnabled: Bool
    @State private var socStartValue: Double
    @State private var socEndValue: Double
    @State private var energyKwh: String
    @State private var pricePerKwh: String
    @State private var priceTotal: String
    @State private var odometerKm: String
    @State private var geocodedPlace: String

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(vehicles: [Vehicle], providers: [Provider], session: ChargingSession?, onSaved: @escaping () -> Void) {
        self.vehicles = vehicles
        self.providers = providers
        self.session = session
        self.onSaved = onSaved

        _vehicleId = State(initialValue: session?.vehicleId ?? vehicles.first?.id ?? "")
        _providerId = State(initialValue: session?.providerId)
        _startTime = State(initialValue: session?.startTime ?? Date())
        _chargingType = State(initialValue: session?.chargingType ?? .ac)
        _socEnabled = State(initialValue: session?.socStart != nil || session?.socEnd != nil)
        _socStartValue = State(initialValue: Double(session?.socStart ?? 20))
        _socEndValue = State(initialValue: Double(session?.socEnd ?? 80))
        _energyKwh = State(initialValue: session?.energyKwh.map { String(format: "%.2f", $0) } ?? "")
        _pricePerKwh = State(initialValue: session?.pricePerKwh.map { String(format: "%.4f", $0) } ?? "")
        _priceTotal = State(initialValue: session?.priceTotal.map { String(format: "%.2f", $0) } ?? "")
        _odometerKm = State(initialValue: session?.odometerKm.map(String.init) ?? "")
        _geocodedPlace = State(initialValue: session?.geocodedPlace ?? "")
    }

    private var isEditing: Bool { session != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fahrzeug & Zeit") {
                    Picker("Fahrzeug", selection: $vehicleId) {
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.name).tag(vehicle.id)
                        }
                    }
                    DatePicker("Start", selection: $startTime)
                }

                Section("Anbieter & Typ") {
                    Picker("Anbieter", selection: $providerId) {
                        Text("– keiner –").tag(String?.none)
                        ForEach(providers) { provider in
                            Text(provider.name).tag(String?.some(provider.id))
                        }
                    }
                    .onChange(of: providerId) { _, _ in suggestPrice() }

                    HStack {
                        Text("Lade-Art")
                        Spacer()
                        Picker("Lade-Art", selection: $chargingType) {
                            ForEach(ChargingType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: chargingType) { _, _ in suggestPrice() }
                    }
                }

                Section("Akkustand") {
                    Toggle("SoC-Werte angeben", isOn: $socEnabled.animation())
                    if socEnabled {
                        SoCSlider(title: "Start", value: $socStartValue, tint: .orange)
                        SoCSlider(title: "Ende", value: $socEndValue, tint: .green)
                    }
                }

                Section("Energie & Preis") {
                    HStack {
                        Text("kWh")
                        Spacer()
                        TextField("automatisch, falls leer", text: $energyKwh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Preis/kWh (€)")
                        Spacer()
                        TextField("optional", text: $pricePerKwh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Gesamtpreis (€)")
                        Spacer()
                        TextField("optional", text: $priceTotal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Sonstiges") {
                    HStack {
                        Text("Ladeort")
                        Spacer()
                        TextField("optional", text: $geocodedPlace)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Kilometerstand")
                        Spacer()
                        TextField("optional", text: $odometerKm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Bearbeiten" : "Neuer Ladevorgang")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled(isSaving || vehicleId.isEmpty)
                }
            }
        }
    }

    private func suggestPrice() {
        guard !isEditing, let providerId, let provider = providers.first(where: { $0.id == providerId }) else { return }
        guard pricePerKwh.isEmpty else { return }
        let price = chargingType == .dc ? provider.lastPriceDcPerKwh : provider.lastPriceAcPerKwh
        if let price {
            pricePerKwh = String(format: "%.4f", price)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let payload = ChargingSessionPayload(
            vehicleId: isEditing ? nil : vehicleId, // vehicle_id kann beim Bearbeiten nicht geaendert werden
            providerId: providerId,
            startTime: startTime,
            chargingType: chargingType,
            socStart: socEnabled ? Int(socStartValue.rounded()) : nil,
            socEnd: socEnabled ? Int(socEndValue.rounded()) : nil,
            energyKwh: Double(energyKwh.replacingOccurrences(of: ",", with: ".")),
            pricePerKwh: Double(pricePerKwh.replacingOccurrences(of: ",", with: ".")),
            priceTotal: Double(priceTotal.replacingOccurrences(of: ",", with: ".")),
            odometerKm: Int(odometerKm),
            geocodedPlace: geocodedPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : geocodedPlace.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: nil,
            // Manuelles Öffnen + Speichern gilt als Review: automatisch erkannte
            // Ladevorgänge verlieren dadurch ihr needs_review-Flag, ohne dass es
            // ein eigenes UI-Element dafür braucht.
            needsReview: isEditing ? false : nil
        )

        do {
            if let session {
                _ = try await AppRepository.shared.updateSession(id: session.id, payload)
            } else {
                _ = try await AppRepository.shared.createSession(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

/// Prozent-Schieberegler fuer den Akkustand (SoC): Titel links, Wert rechts,
/// darunter ein farbig getönter Slider (0–100 %).
private struct SoCSlider: View {
    let title: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value.rounded())) %")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...100, step: 1)
                .tint(tint)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddEditSessionView(vehicles: [], providers: [], session: nil, onSaved: {})
}
