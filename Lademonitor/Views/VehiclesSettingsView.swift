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
    // Kauf/Leasing. Datumsfelder brauchen einen Wert fuer den DatePicker -
    // gespeichert werden sie nur fuer die gewaehlte Art (siehe ownershipPayload).
    @State private var ownership: Ownership
    @State private var purchasePrice: String
    @State private var purchaseDate: Date
    @State private var purchaseOdometerKm: String
    @State private var hasFirstRegistration: Bool
    @State private var firstRegistration: Date
    @State private var depreciationOverride: String
    @State private var leasingRate: String
    @State private var leasingDownPayment: String
    @State private var leasingStart: Date
    @State private var hasLeasingEnd: Bool
    @State private var leasingEnd: Date
    /// Ladevorgaenge dieses Fahrzeugs, fuer die km-Staende der Restwertkurve.
    @State private var sessions: [ChargingSession] = []
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
        let today = Calendar.current.startOfDay(for: Date())
        let money = { (value: Double?) in value.map { String(format: "%.2f", $0) } ?? "" }
        _ownership = State(initialValue: vehicle?.ownershipValue ?? Ownership.none)
        _purchasePrice = State(initialValue: money(vehicle?.purchasePrice))
        _purchaseDate = State(initialValue: vehicle?.purchaseDate ?? today)
        _purchaseOdometerKm = State(initialValue: vehicle?.purchaseOdometerKm.map { String($0) } ?? "")
        _hasFirstRegistration = State(initialValue: vehicle?.firstRegistration != nil)
        _firstRegistration = State(initialValue: vehicle?.firstRegistration ?? vehicle?.purchaseDate ?? today)
        _depreciationOverride = State(initialValue: money(vehicle?.depreciationMonthlyOverride))
        _leasingRate = State(initialValue: money(vehicle?.leasingRateMonthly))
        _leasingDownPayment = State(initialValue: money(vehicle?.leasingDownPayment))
        _leasingStart = State(initialValue: vehicle?.leasingStart ?? today)
        _hasLeasingEnd = State(initialValue: vehicle?.leasingEnd != nil)
        _leasingEnd = State(initialValue: vehicle?.leasingEnd
            ?? Calendar.current.date(byAdding: DateComponents(year: 3, day: -1), to: vehicle?.leasingStart ?? today) ?? today)
    }

    private func parseAmount(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Kauf-/Leasingfelder, wie sie gespeichert werden: die der gewaehlten Art
    /// aus dem Formular, die der anderen unveraendert vom Fahrzeug - so geht
    /// beim Umschalten nichts verloren, und ein nie benutztes Datum landet
    /// nicht als "heute" in der Datenbank.
    private var ownershipPayload: VehiclePayload {
        let day = { (date: Date) in Calendar.current.startOfDay(for: date) }
        var p = VehiclePayload(
            sendsOwnership: true,
            ownership: ownership.rawValue,
            purchasePrice: vehicle?.purchasePrice,
            purchaseDate: vehicle?.purchaseDate,
            firstRegistration: vehicle?.firstRegistration,
            purchaseOdometerKm: vehicle?.purchaseOdometerKm,
            depreciationMonthlyOverride: vehicle?.depreciationMonthlyOverride,
            leasingRateMonthly: vehicle?.leasingRateMonthly,
            leasingStart: vehicle?.leasingStart,
            leasingEnd: vehicle?.leasingEnd,
            leasingDownPayment: vehicle?.leasingDownPayment
        )
        switch ownership {
        case .purchase:
            p.purchasePrice = parseAmount(purchasePrice)
            p.purchaseDate = day(purchaseDate)
            p.firstRegistration = hasFirstRegistration ? day(firstRegistration) : nil
            p.purchaseOdometerKm = Int(purchaseOdometerKm.trimmingCharacters(in: .whitespaces))
            p.depreciationMonthlyOverride = parseAmount(depreciationOverride)
        case .leasing:
            p.leasingRateMonthly = parseAmount(leasingRate)
            p.leasingDownPayment = parseAmount(leasingDownPayment)
            p.leasingStart = day(leasingStart)
            p.leasingEnd = hasLeasingEnd ? day(leasingEnd) : nil
        case .none:
            break
        }
        return p
    }

    /// Kennzahlen zum aktuellen Formularstand, lokal gerechnet wie auf dem
    /// Server (LocalVehicleCostCalculator.ownershipInfo).
    private var ownershipInfo: LocalVehicleCostCalculator.OwnershipInfo {
        let p = ownershipPayload
        let draft = Vehicle(
            id: vehicle?.id ?? "draft", externalId: externalId, name: name,
            brand: nil, model: nil, batteryCapacityKwh: nil, isActive: isActive,
            ownership: p.ownership, purchasePrice: p.purchasePrice, purchaseDate: p.purchaseDate,
            firstRegistration: p.firstRegistration, purchaseOdometerKm: p.purchaseOdometerKm,
            depreciationMonthlyOverride: p.depreciationMonthlyOverride,
            leasingRateMonthly: p.leasingRateMonthly, leasingStart: p.leasingStart,
            leasingEnd: p.leasingEnd, leasingDownPayment: p.leasingDownPayment
        )
        return LocalVehicleCostCalculator.ownershipInfo(vehicle: draft, sessions: sessions)
    }

    private func euro(_ value: Double?) -> String {
        value.map { $0.formatted(.currency(code: "EUR")) } ?? "–"
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

                Section {
                    Picker("Kauf / Leasing", selection: $ownership) {
                        ForEach(Ownership.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    switch ownership {
                    case .purchase:
                        purchaseFields
                    case .leasing:
                        leasingFields
                    case .none:
                        EmptyView()
                    }
                } header: {
                    Text("Kauf / Leasing")
                } footer: {
                    switch ownership {
                    case .purchase:
                        Text("Der Wertverlust folgt einer Restwertkurve (im ersten Jahr auf 75 Prozent, danach 13 Prozent je Jahr), viel gefahrene Kilometer altern das Auto schneller. Er zählt in den Gesamtkosten im Dashboard.")
                    case .leasing:
                        Text("Die Sonderzahlung wird gleichmäßig auf die Laufzeit verteilt, ohne Ende zählt sie im ersten Monat.")
                    case .none:
                        EmptyView()
                    }
                }

                if let vehicle {
                    Section {
                        NavigationLink {
                            VehicleCostsView(vehicle: vehicle)
                        } label: {
                            Label("Kosten", systemImage: "eurosign.circle")
                        }
                        NavigationLink {
                            RemindersView(vehicle: vehicle)
                        } label: {
                            Label("Erinnerungen", systemImage: "bell")
                        }
                    } footer: {
                        Text("Versicherung, Steuer, Wartung und alles Weitere rund ums Auto.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Fahrzeug bearbeiten" : "Neues Fahrzeug")
            .task { await loadSessions() }
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

    @ViewBuilder
    private var purchaseFields: some View {
        amountField("Kaufpreis (€)", text: $purchasePrice, prompt: "40000")
        DatePicker("Kaufdatum", selection: $purchaseDate, displayedComponents: .date)
        HStack {
            Text("km-Stand beim Kauf")
            Spacer()
            TextField("optional", text: $purchaseOdometerKm)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
        Toggle("Gebraucht gekauft", isOn: $hasFirstRegistration)
        if hasFirstRegistration {
            DatePicker("Erstzulassung", selection: $firstRegistration, in: ...purchaseDate, displayedComponents: .date)
        }
        let info = ownershipInfo
        LabeledContent("Geschätzter Wert heute", value: euro(info.estimatedValue))
        LabeledContent("Vorschlag Wertverlust je Monat", value: euro(info.suggestedMonthly))
        amountField("Wertverlust je Monat (€)", text: $depreciationOverride, prompt: String(localized: "leer = Vorschlag"))
    }

    @ViewBuilder
    private var leasingFields: some View {
        amountField("Monatsrate (€)", text: $leasingRate, prompt: "299")
        amountField("Sonderzahlung (€)", text: $leasingDownPayment, prompt: String(localized: "optional"))
        DatePicker("Leasingbeginn", selection: $leasingStart, displayedComponents: .date)
        Toggle("Ende bekannt", isOn: $hasLeasingEnd)
        if hasLeasingEnd {
            DatePicker("Leasingende", selection: $leasingEnd, in: leasingStart..., displayedComponents: .date)
        }
        LabeledContent("Monatlich inkl. Sonderzahlung", value: euro(ownershipInfo.ownershipMonthly))
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(prompt, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadSessions() async {
        guard let vehicle else { return }
        sessions = (try? await AppRepository.shared.vehicleCostBasis())?
            .sessions.filter { $0.vehicleId == vehicle.id } ?? []
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)

        var payload = ownershipPayload
        payload.externalId = isEditing ? nil : externalId.trimmingCharacters(in: .whitespaces)
        payload.name = name.trimmingCharacters(in: .whitespaces)
        payload.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
        payload.model = trimmedModel.isEmpty ? nil : trimmedModel
        payload.batteryCapacityKwh = Double(batteryCapacityKwh.replacingOccurrences(of: ",", with: "."))
        payload.isActive = isActive

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
