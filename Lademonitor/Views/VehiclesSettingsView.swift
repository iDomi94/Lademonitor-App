import SwiftUI

struct VehiclesSettingsView: View {
    @State private var vehicles: [Vehicle] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingAdd = false
    @State private var editing: Vehicle?
    @State private var pendingDelete: Vehicle?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(vehicles) { vehicle in
                Button {
                    editing = vehicle
                } label: {
                    VehicleRow(vehicle: vehicle)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDelete = vehicle
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Fahrzeuge")
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
            AddEditVehicleView(vehicle: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { vehicle in
            AddEditVehicleView(vehicle: vehicle) { Task { await load() } }
        }
        .alert("Fahrzeug löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { vehicle in
            Button("Löschen", role: .destructive) { Task { await delete(vehicle) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Achtung: Dabei werden auch ALLE zugehörigen Ladevorgänge dieses Fahrzeugs unwiderruflich gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        isLoading = true
        do {
            vehicles = try await AppRepository.shared.fetchVehicles()
            errorMessage = nil
        } catch {
            if vehicles.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func delete(_ vehicle: Vehicle) async {
        do {
            try await AppRepository.shared.deleteVehicle(id: vehicle.id)
            vehicles.removeAll { $0.id == vehicle.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vehicle.name)
                        .font(.body)
                    if !vehicle.isActive {
                        Text("inaktiv")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemFill))
                            .clipShape(Capsule())
                    }
                }
                let subtitle = [vehicle.brand, vehicle.model].compactMap { $0 }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let capacity = vehicle.batteryCapacityKwh {
                Text(String(format: "%.0f kWh", capacity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddEditVehicleView: View {
    let vehicle: Vehicle?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var externalId: String
    @State private var name: String
    @State private var brand: String
    @State private var model: String
    @State private var batteryCapacityKwh: String
    @State private var isActive: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(vehicle: Vehicle?, onSaved: @escaping () -> Void) {
        self.vehicle = vehicle
        self.onSaved = onSaved
        _externalId = State(initialValue: vehicle?.externalId ?? "")
        _name = State(initialValue: vehicle?.name ?? "")
        _brand = State(initialValue: vehicle?.brand ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _batteryCapacityKwh = State(initialValue: vehicle?.batteryCapacityKwh.map { String(format: "%.1f", $0) } ?? "")
        _isActive = State(initialValue: vehicle?.isActive ?? true)
    }

    private var isEditing: Bool { vehicle != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (isEditing || !externalId.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Externe ID")
                        Spacer()
                        TextField("z.B. enyaq", text: $externalId)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .disabled(isEditing)
                            .foregroundStyle(isEditing ? .secondary : .primary)
                    }
                    TextField("Name", text: $name)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Modell (optional)", text: $model)
                } header: {
                    Text("Fahrzeug")
                } footer: {
                    if isEditing {
                        Text("Die externe ID ist nach dem Anlegen nicht mehr änderbar.")
                    }
                }

                Section("Technik") {
                    HStack {
                        Text("Akkukapazität (kWh)")
                        Spacer()
                        TextField("optional", text: $batteryCapacityKwh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Aktiv", isOn: $isActive)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Fahrzeug bearbeiten" : "Neues Fahrzeug")
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

    private func save() async {
        isSaving = true
        errorMessage = nil

        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)

        let payload = VehiclePayload(
            externalId: isEditing ? nil : externalId.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            model: trimmedModel.isEmpty ? nil : trimmedModel,
            batteryCapacityKwh: Double(batteryCapacityKwh.replacingOccurrences(of: ",", with: ".")),
            isActive: isActive
        )

        do {
            if let vehicle {
                _ = try await AppRepository.shared.updateVehicle(id: vehicle.id, payload)
            } else {
                _ = try await AppRepository.shared.createVehicle(payload)
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
    NavigationStack { VehiclesSettingsView() }
}
