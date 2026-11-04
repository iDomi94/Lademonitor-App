import SwiftUI

/// Sonstige Kosten eines Fahrzeugs (Versicherung, Steuer, Wartung, ...) plus
/// eine kleine Uebersicht je Kalenderjahr. Wie die Grundgebuehren in beiden
/// Modi verfuegbar - gerechnet wird lokal (LocalVehicleCostCalculator).
struct VehicleCostsView: View {
    let vehicle: Vehicle

    @State private var costs: [VehicleCost] = []
    /// Gespeicherter Stand des Fahrzeugs (Kaufdatum fuer die THG-Quote).
    @State private var current: Vehicle?
    @State private var years: [YearCostStat] = []
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var editing: VehicleCost?
    @State private var pendingDelete: VehicleCost?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            if !years.isEmpty {
                Section {
                    ForEach(years) { year in
                        YearCostRow(stat: year)
                    }
                } header: {
                    Text("Kosten je Jahr")
                } footer: {
                    Text("Laden inklusive Grundgebühren, dazu die Kosten unten und Wertverlust bzw. Leasing.")
                }
            }
            if !costs.isEmpty {
                Section("Einträge") {
                    ForEach(costs) { cost in
                        Button {
                            editing = cost
                        } label: {
                            VehicleCostRow(cost: cost, vehicle: current ?? vehicle)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = cost
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if costs.isEmpty && years.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "Keine Kosten",
                    systemImage: "eurosign.circle",
                    description: Text("Zum Beispiel Versicherung, Kfz-Steuer oder die nächste Inspektion. Wiederkehrende Beträge sind ein Eintrag.")
                )
            }
        }
        .navigationTitle("Kosten")
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
            AddEditVehicleCostView(cost: nil, vehicleId: vehicle.id) { Task { await load() } }
        }
        .sheet(item: $editing) { cost in
            AddEditVehicleCostView(cost: cost, vehicleId: vehicle.id) { Task { await load() } }
        }
        .alert("Eintrag löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { cost in
            Button("Löschen", role: .destructive) { Task { await delete(cost) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { cost in
            Text("„\(cost.label ?? cost.categoryValue.displayName)“ wird gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func load() async {
        do {
            let basis = try await AppRepository.shared.vehicleCostBasis()
            // Der gespeicherte Stand des Fahrzeugs, nicht der aus dem
            // Formular - Kauf/Leasing zaehlt erst nach dem Speichern.
            let current = basis.vehicles.first { $0.id == vehicle.id } ?? vehicle
            self.current = current
            costs = basis.costs.filter { $0.vehicleId == current.id }
            years = LocalVehicleCostCalculator.yearly(vehicle: current, costs: basis.costs, sessions: basis.sessions)
            errorMessage = nil
        } catch {
            if costs.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ cost: VehicleCost) async {
        do {
            try await AppRepository.shared.deleteVehicleCost(id: cost.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct YearCostRow: View {
    let stat: YearCostStat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(stat.year))
                    .font(.headline)
                Spacer()
                Text(stat.total.formatted(.currency(code: "EUR")))
                    .font(.headline.monospacedDigit())
            }
            CostCategoryBars(categories: stat.byCategory)
        }
        .padding(.vertical, 4)
    }
}

private struct VehicleCostRow: View {
    let cost: VehicleCost
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(CostCategoryStyle.color(cost.categoryValue.rawValue))
                    .frame(width: 9, height: 9)
                Text(cost.label.map { "\(cost.categoryValue.displayName) · \($0)" } ?? cost.categoryValue.displayName)
                    .font(.body)
                Spacer()
                Text((cost.categoryValue.isCredit ? -cost.amount : cost.amount).formatted(.currency(code: "EUR")))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(cost.categoryValue.isCredit ? Color.green : Color.primary)
            }
            Text(scheduleText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if cost.interval != .once {
                Text("Bisher bezahlt \(LocalVehicleCostCalculator.paidToDate(cost).formatted(.currency(code: "EUR")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if cost.categoryValue.isCredit, let monthly = LocalVehicleCostCalculator.spreadMonthly(cost, vehicle: vehicle) {
                Text("Gutschrift · \(monthly.formatted(.currency(code: "EUR")))/Monat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Davon in den Kosten \(LocalVehicleCostCalculator.spreadToDate(cost, vehicle: vehicle).formatted(.currency(code: "EUR")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let months = cost.spreadMonths, let monthly = LocalVehicleCostCalculator.spreadMonthly(cost) {
                Text("Verteilt auf \(months) Monate · \(monthly.formatted(.currency(code: "EUR")))/Monat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Davon in den Kosten \(LocalVehicleCostCalculator.spreadToDate(cost).formatted(.currency(code: "EUR")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notes = cost.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    /// "12.03.2026 · 45.210 km" bzw. "ab 01.01.2025 · jährlich · bis 31.12.2027".
    private var scheduleText: String {
        let start = cost.startDate.formatted(date: .abbreviated, time: .omitted)
        var parts: [String]
        switch cost.interval {
        case .once:
            parts = [start]
        case .monthly, .yearly:
            parts = [String(localized: "ab \(start)"),
                     cost.interval == .monthly ? String(localized: "monatlich") : String(localized: "jährlich")]
            if let end = cost.endDate {
                parts.append(String(localized: "bis \(end.formatted(date: .abbreviated, time: .omitted))"))
            }
        }
        if let km = cost.odometerKm {
            parts.append("\(km.formatted()) km")
        }
        return parts.joined(separator: " · ")
    }
}

/// Vorbelegung des Kostenformulars, z. B. nach "Erledigt" einer Erinnerung
/// (Kategorie, Datum, km-Stand und Bezeichnung).
struct VehicleCostPrefill: Identifiable {
    let id = UUID()
    let vehicleId: String
    let category: CostCategory
    let date: Date
    let odometerKm: Int?
    let label: String?
}

struct AddEditVehicleCostView: View {
    let cost: VehicleCost?
    let vehicleId: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var capabilities = ServerCapabilities.shared

    @State private var category: CostCategory
    @State private var amount: String
    @State private var interval: CostInterval
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var odometerKm: String
    @State private var label: String
    @State private var notes: String
    @State private var isSpread: Bool
    @State private var spreadCount: String
    @State private var spreadInYears: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// `prefill` gilt nur beim Anlegen (ohne `cost`).
    init(cost: VehicleCost?, vehicleId: String, prefill: VehicleCostPrefill? = nil, onSaved: @escaping () -> Void) {
        self.cost = cost
        self.vehicleId = vehicleId
        self.onSaved = onSaved
        let preset = cost == nil ? prefill : nil
        let start = cost?.startDate ?? preset?.date ?? Calendar.current.startOfDay(for: Date())
        _category = State(initialValue: cost?.categoryValue ?? preset?.category ?? .insurance)
        _amount = State(initialValue: cost.map { String(format: "%.2f", $0.amount) } ?? "")
        _interval = State(initialValue: cost?.interval ?? .once)
        _startDate = State(initialValue: start)
        _hasEndDate = State(initialValue: cost?.endDate != nil)
        _endDate = State(initialValue: cost?.endDate
            ?? Calendar.current.date(byAdding: .year, value: 1, to: start) ?? start)
        _odometerKm = State(initialValue: (cost?.odometerKm ?? preset?.odometerKm).map { String($0) } ?? "")
        _label = State(initialValue: cost?.label ?? preset?.label ?? "")
        _notes = State(initialValue: cost?.notes ?? "")
        let months = cost?.spreadMonths
        let years = months.map { $0 % 12 == 0 } ?? true
        _isSpread = State(initialValue: months != nil)
        _spreadInYears = State(initialValue: years)
        _spreadCount = State(initialValue: months.map { String(years ? $0 / 12 : $0) } ?? "4")
    }

    /// Monate, auf die verteilt wird; nil = nicht verteilen.
    private var spreadMonths: Int? {
        guard isSpread, let n = Int(spreadCount.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        let months = spreadInYears ? n * 12 : n
        return months > 1 ? min(months, LocalVehicleCostCalculator.maxSpreadMonths) : nil
    }

    private var parsedAmount: Double? {
        Double(amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var isRecurring: Bool { interval != .once }

    private var isThg: Bool { category == .thg }

    /// Gesperrt auf einem Server vor 0.50.0 - ein bestehender Eintrag laesst
    /// sich aber weiter bearbeiten (er kam ja von irgendwo).
    private var thgLockedHint: String? {
        cost?.categoryValue == .thg ? nil : capabilities.unavailableHint(.thgCredit)
    }

    private var canSave: Bool {
        guard let parsedAmount, parsedAmount >= 0 else { return false }
        if isThg && thgLockedHint != nil { return false }
        if isRecurring && hasEndDate && endDate < startDate { return false }
        if !isThg && isSpread && spreadMonths == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kategorie", selection: $category) {
                        ForEach(CostCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                                .disabled(category == .thg && thgLockedHint != nil)
                        }
                    }
                    TextField("Bezeichnung (z. B. Vollkasko)", text: $label)
                } footer: {
                    if isThg {
                        if let thgLockedHint {
                            Label(thgLockedHint, systemImage: "lock")
                        } else {
                            Text("Die THG-Quote ist eine Gutschrift: Sie zählt negativ für das Kalenderjahr des Datums, gleichmäßig auf die Monate verteilt (300 € = 25 € pro Monat). Wurde das Auto erst im Laufe des Jahres gekauft oder geleast, verteilt sie sich nur auf die Monate ab dann. „Jährlich“ wiederholt sie für jedes Folgejahr.")
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Betrag (€)")
                        Spacer()
                        TextField("0,00" as String, text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Wiederholung", selection: $interval) {
                        ForEach(CostInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    DatePicker(isThg ? LocalizedStringKey("Datum im Jahr der Quote")
                               : (isRecurring ? LocalizedStringKey("Erste Zahlung") : LocalizedStringKey("Datum")),
                               selection: $startDate, displayedComponents: .date)
                    if isRecurring {
                        Toggle("Letzte Zahlung", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Letzte Zahlung am", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                    }
                } footer: {
                    if isRecurring && !isThg {
                        Text("Ein Jahresbetrag zählt in dem Monat, in dem er fällig ist. Eine Beitragsänderung ist ein neuer Eintrag, beim alten wird die letzte Zahlung gesetzt.")
                    }
                }

                if !isThg {
                Section {
                    Toggle("Auf längeren Zeitraum verteilen", isOn: $isSpread)
                    if isSpread {
                        HStack {
                            TextField("4" as String, text: $spreadCount)
                                .keyboardType(.numberPad)
                            Picker("Einheit", selection: $spreadInYears) {
                                Text("Monate").tag(false)
                                Text("Jahre").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        if let months = spreadMonths, let parsedAmount {
                            Text("\((parsedAmount / Double(months)).formatted(.currency(code: "EUR"))) je Monat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Jede Zahlung zählt dann gleichmäßig über die gewählte Zeit in die Kosten, Monat für Monat ab dem Zahltag – z. B. Reifen auf 4 Jahre oder die Jahresversicherung auf 12 Monate.")
                }
                }

                Section {
                    HStack {
                        Text("km-Stand")
                        Spacer()
                        TextField("optional", text: $odometerKm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Notiz", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(cost == nil ? "Neue Kosten" : "Kosten bearbeiten")
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
        guard let parsedAmount else { return }
        isSaving = true
        errorMessage = nil
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = VehicleCostPayload(
            vehicleId: cost?.vehicleId ?? vehicleId,
            amount: parsedAmount,
            category: category.rawValue,
            interval: interval,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: (isRecurring && hasEndDate) ? Calendar.current.startOfDay(for: endDate) : nil,
            odometerKm: Int(odometerKm.trimmingCharacters(in: .whitespaces)),
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            spreadMonths: isThg ? nil : spreadMonths
        )
        do {
            if let cost {
                _ = try await AppRepository.shared.updateVehicleCost(id: cost.id, payload)
            } else {
                _ = try await AppRepository.shared.createVehicleCost(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
