import SwiftUI

/// Erinnerungen eines Fahrzeugs (HU, Inspektion, Reifenwechsel, ...) bzw.
/// aller Fahrzeuge, wenn `vehicle` fehlt (Einstieg vom Dashboard). In beiden
/// Modi verfuegbar - Status, km-Prognose und "Erledigt" rechnet die App
/// selbst (LocalReminderCalculator).
struct RemindersView: View {
    let vehicle: Vehicle?

    @State private var items: [ReminderItem] = []
    @State private var vehicles: [Vehicle] = []
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var editing: ReminderItem?
    @State private var completing: ReminderItem?
    @State private var pendingDelete: ReminderItem?
    /// Nach "Erledigt" mit gewuenschtem Kosteneintrag - oeffnet das
    /// Kostenformular, sobald das Erledigt-Blatt zu ist.
    @State private var pendingCost: VehicleCostPrefill?
    @State private var costPrefill: VehicleCostPrefill?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        Button {
                            editing = item
                        } label: {
                            ReminderRow(item: item, showVehicle: vehicle == nil && vehicles.count > 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                completing = item
                            } label: {
                                Label("Erledigt", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                        .contextMenu {
                            Button {
                                completing = item
                            } label: {
                                Label("Erledigt", systemImage: "checkmark")
                            }
                        }
                    }
                } footer: {
                    Text("Den km-Stand musst du nicht eintippen: er kommt aus den Ladevorgängen, und aus deiner Fahrleistung der letzten 90 Tage schätzt die App, wann er erreicht ist. Nach rechts wischen hakt eine Erinnerung ab.")
                }
            }
        }
        .overlay {
            if items.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "Keine Erinnerungen",
                    systemImage: "bell",
                    description: Text("Zum Beispiel für HU, Inspektion oder den Reifenwechsel – fällig nach Datum und/oder km-Stand.")
                )
            }
        }
        .navigationTitle("Erinnerungen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(vehicle == nil && vehicles.isEmpty)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) {
            AddEditReminderView(
                reminder: nil, vehicleId: vehicle?.id, vehicles: vehicles,
                currentKm: nil
            ) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            AddEditReminderView(
                reminder: item.reminder, vehicleId: item.reminder.vehicleId, vehicles: vehicles,
                currentKm: item.currentKm
            ) { Task { await load() } }
        }
        .sheet(item: $completing, onDismiss: {
            if let pendingCost {
                self.pendingCost = nil
                costPrefill = pendingCost
            }
        }) { item in
            CompleteReminderView(item: item) { prefill in
                pendingCost = prefill
                Task { await load() }
            }
        }
        .sheet(item: $costPrefill) { prefill in
            AddEditVehicleCostView(cost: nil, vehicleId: prefill.vehicleId, prefill: prefill) {}
        }
        .alert("Erinnerung löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { item in
            Button("Löschen", role: .destructive) { Task { await delete(item) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { item in
            Text("„\(item.reminder.displayTitle)“ wird gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func load() async {
        do {
            items = try await AppRepository.shared.fetchReminderItems(vehicleId: vehicle?.id)
            vehicles = try await AppRepository.shared.fetchVehicles()
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ item: ReminderItem) async {
        do {
            try await AppRepository.shared.deleteReminder(id: item.reminder.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Darstellung

/// Status als kleines farbiges Etikett: ok gruen, bald faellig orange,
/// ueberfaellig rot, erledigt grau.
struct ReminderStatusBadge: View {
    let status: ReminderStatus

    var color: Color {
        switch status {
        case .ok: return .green
        case .dueSoon: return .orange
        case .overdue: return .red
        case .done: return .gray
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// Texte zu Faelligkeit und Wiederholung, gemeinsam fuer Liste und Dashboard.
enum ReminderTexts {
    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func km(_ value: Int) -> String {
        "\(value.formatted()) km"
    }

    /// "15.10.2026 · in 5 Tagen" bzw. "bei 30.000 km · noch 400 km".
    static func dueLines(_ item: ReminderItem) -> [String] {
        let reminder = item.reminder
        let state = item.state
        var lines: [String] = []
        if let due = reminder.dueDate, let days = state.daysRemaining {
            let relative: String
            switch days {
            case 0: relative = String(localized: "heute")
            case 1: relative = String(localized: "morgen")
            case -1: relative = String(localized: "seit gestern")
            case let n where n > 1: relative = String(localized: "in \(n) Tagen")
            default: relative = String(localized: "seit \(-days) Tagen")
            }
            lines.append("\(dateText(due)) · \(relative)")
        }
        if let dueKm = reminder.dueKm {
            var parts = [String(localized: "bei \(km(dueKm))")]
            if let remaining = state.kmRemaining {
                parts.append(remaining > 0
                    ? String(localized: "noch \(km(remaining))")
                    : String(localized: "\(km(-remaining)) drüber"))
            }
            lines.append(parts.joined(separator: " · "))
            if let forecast = state.kmForecastDate, let remaining = state.kmRemaining, remaining > 0 {
                lines.append(String(localized: "bei deiner Fahrleistung etwa am \(dateText(forecast))"))
            }
        }
        if reminder.dueDate == nil && reminder.dueKm == nil {
            lines.append(String(localized: "keine Fälligkeit"))
        }
        return lines
    }

    /// "alle 24 Monate · alle 30.000 km" bzw. "einmalig".
    static func repeatText(_ reminder: Reminder) -> String {
        var parts: [String] = []
        if let months = reminder.repeatMonths, months > 0 {
            parts.append(String(localized: "alle \(months) Monate"))
        }
        if let repeatKm = reminder.repeatKm, repeatKm > 0 {
            parts.append(String(localized: "alle \(km(repeatKm))"))
        }
        return parts.isEmpty ? String(localized: "einmalig") : parts.joined(separator: " · ")
    }

    static func lastDoneText(_ reminder: Reminder) -> String? {
        guard let done = reminder.lastDoneDate else { return nil }
        var text = String(localized: "zuletzt erledigt am \(dateText(done))")
        if let doneKm = reminder.lastDoneKm { text += " · \(km(doneKm))" }
        return text
    }
}

struct ReminderRow: View {
    let item: ReminderItem
    var showVehicle = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.reminder.kindValue.systemImage)
                .foregroundStyle(ReminderStatusBadge(status: item.state.status).color)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.reminder.displayTitle)
                        .font(.body)
                    Spacer()
                    ReminderStatusBadge(status: item.state.status)
                }
                if showVehicle, let name = item.vehicleName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(ReminderTexts.dueLines(item), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(ReminderTexts.repeatText(item.reminder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastDone = ReminderTexts.lastDoneText(item.reminder) {
                    Text(lastDone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = item.reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Anlegen / Bearbeiten

struct AddEditReminderView: View {
    let reminder: Reminder?
    let vehicles: [Vehicle]
    let currentKm: Int?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String
    @State private var kind: ReminderKind
    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var dueKm: String
    @State private var repeatMonths: String
    @State private var repeatKm: String
    @State private var leadDays: String
    @State private var leadKm: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// `vehicleId` = festes Fahrzeug (aus dessen Einstellungen); fehlt es,
    /// zeigt das Formular eine Fahrzeugauswahl.
    init(reminder: Reminder?, vehicleId: String?, vehicles: [Vehicle], currentKm: Int?, onSaved: @escaping () -> Void) {
        self.reminder = reminder
        self.vehicles = vehicles
        self.currentKm = currentKm
        self.onSaved = onSaved
        let today = Calendar.current.startOfDay(for: Date())
        let kind = reminder?.kindValue ?? .hu
        let template = LocalReminderCalculator.template(for: kind)
        let number = { (value: Int?) in value.map { String($0) } ?? "" }
        _vehicleId = State(initialValue: reminder?.vehicleId ?? vehicleId ?? vehicles.first?.id ?? "")
        _kind = State(initialValue: kind)
        _title = State(initialValue: reminder?.title ?? "")
        if let reminder {
            _hasDueDate = State(initialValue: reminder.dueDate != nil)
            _dueDate = State(initialValue: reminder.dueDate ?? today)
            _dueKm = State(initialValue: number(reminder.dueKm))
            _repeatMonths = State(initialValue: number(reminder.repeatMonths))
            _repeatKm = State(initialValue: number(reminder.repeatKm))
            _leadDays = State(initialValue: String(reminder.leadDays))
            _leadKm = State(initialValue: String(reminder.leadKm))
        } else {
            let first = LocalReminderCalculator.firstDueDate(kind: kind)
            _hasDueDate = State(initialValue: first != nil)
            _dueDate = State(initialValue: first ?? today)
            _dueKm = State(initialValue: "")
            _repeatMonths = State(initialValue: number(template.repeatMonths))
            _repeatKm = State(initialValue: number(template.repeatKm))
            _leadDays = State(initialValue: String(LocalReminderCalculator.defaultLeadDays))
            _leadKm = State(initialValue: String(LocalReminderCalculator.defaultLeadKm))
        }
        _notes = State(initialValue: reminder?.notes ?? "")
        self.fixedVehicle = vehicleId != nil || reminder != nil
    }

    private let fixedVehicle: Bool

    private func int(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ""))
    }

    /// Wie die Web-Oberflaeche: eine neue Erinnerung braucht ein Datum oder
    /// einen km-Stand. Eine erledigte ohne Wiederholung darf leer bleiben.
    private var canSave: Bool {
        guard !vehicleId.isEmpty else { return false }
        if reminder == nil && !hasDueDate && int(dueKm) == nil { return false }
        if let months = int(repeatMonths), !(1...240).contains(months) { return false }
        if let km = int(repeatKm), km < 1 { return false }
        if let days = int(leadDays), !(0...365).contains(days) { return false }
        return true
    }

    /// Beim Anlegen fuellt die Vorlage Wiederholung und ggf. den festen
    /// Faelligkeitstag vor - beim Bearbeiten bleibt alles, wie es ist.
    private func applyTemplate(_ kind: ReminderKind) {
        guard reminder == nil else { return }
        let template = LocalReminderCalculator.template(for: kind)
        repeatMonths = template.repeatMonths.map { String($0) } ?? ""
        repeatKm = template.repeatKm.map { String($0) } ?? ""
        if let first = LocalReminderCalculator.firstDueDate(kind: kind) {
            hasDueDate = true
            dueDate = first
        } else {
            hasDueDate = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !fixedVehicle && vehicles.count > 1 {
                        Picker("Fahrzeug", selection: $vehicleId) {
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(vehicle.id)
                            }
                        }
                    }
                    Picker("Vorlage", selection: $kind) {
                        ForEach(ReminderKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .onChange(of: kind) { _, newKind in applyTemplate(newKind) }
                    TextField("Bezeichnung (leer = Name der Vorlage)", text: $title)
                }

                Section {
                    Toggle("Fällig an einem Datum", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                    numberField("Fällig bei km", text: $dueKm, prompt: currentKm.map { String($0) } ?? String(localized: "optional"))
                } header: {
                    Text("Fälligkeit")
                } footer: {
                    Text("Datum oder km-Stand genügt, beides geht auch: dann zählt, was zuerst erreicht ist.")
                }

                Section {
                    numberField("Wiederholung (Monate)", text: $repeatMonths, prompt: String(localized: "keine"))
                    numberField("Wiederholung (km)", text: $repeatKm, prompt: String(localized: "keine"))
                } header: {
                    Text("Wiederholung")
                } footer: {
                    Text("„Erledigt“ setzt daraus die nächste Fälligkeit. Reifenwechsel, Versicherung, Steuer und THG bleiben dabei an ihrem Kalendertag.")
                }

                Section {
                    numberField("Vorlauf (Tage)", text: $leadDays, prompt: String(LocalReminderCalculator.defaultLeadDays))
                    numberField("Vorlauf (km)", text: $leadKm, prompt: String(LocalReminderCalculator.defaultLeadKm))
                } footer: {
                    Text("Im Vorlauf gilt die Erinnerung als „bald fällig“ und erscheint im Dashboard.")
                }

                Section {
                    TextField("Notiz", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(reminder == nil ? "Neue Erinnerung" : "Erinnerung bearbeiten")
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

    private func numberField(_ title: LocalizedStringKey, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(prompt, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ReminderPayload(
            vehicleId: vehicleId,
            kind: kind.rawValue,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            dueDate: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil,
            dueKm: int(dueKm),
            repeatMonths: int(repeatMonths),
            repeatKm: int(repeatKm),
            leadDays: int(leadDays) ?? LocalReminderCalculator.defaultLeadDays,
            leadKm: int(leadKm) ?? LocalReminderCalculator.defaultLeadKm,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            lastDoneDate: reminder?.lastDoneDate,
            lastDoneKm: reminder?.lastDoneKm
        )
        do {
            if let reminder {
                _ = try await AppRepository.shared.updateReminder(id: reminder.id, payload)
            } else {
                _ = try await AppRepository.shared.createReminder(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Erledigt

/// "Erledigt": Datum (Standard heute) und km-Stand (Standard der juengste aus
/// den Ladevorgaengen). Schreibt die Merker und die naechste Faelligkeit
/// (LocalReminderCalculator.completedPayload) und bietet danach einen
/// vorbelegten Kosteneintrag an, wenn die Art eine Kostenkategorie hat.
struct CompleteReminderView: View {
    let item: ReminderItem
    /// Mit Vorbelegung, wenn danach das Kostenformular aufgehen soll.
    let onCompleted: (VehicleCostPrefill?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var doneDate: Date
    @State private var doneKm: String
    @State private var addCost: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: ReminderItem, onCompleted: @escaping (VehicleCostPrefill?) -> Void) {
        self.item = item
        self.onCompleted = onCompleted
        _doneDate = State(initialValue: Calendar.current.startOfDay(for: Date()))
        _doneKm = State(initialValue: item.currentKm.map { String($0) } ?? "")
        _addCost = State(initialValue: LocalReminderCalculator.costCategory(for: item.reminder.kindValue) != nil)
    }

    private var category: CostCategory? {
        LocalReminderCalculator.costCategory(for: item.reminder.kindValue)
    }

    private var parsedKm: Int? {
        Int(doneKm.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ""))
    }

    private var preview: (date: Date?, km: Int?) {
        LocalReminderCalculator.nextDue(item.reminder, doneDay: doneDate, doneKm: parsedKm)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Erledigt am", selection: $doneDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("km-Stand")
                        Spacer()
                        TextField("optional", text: $doneKm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text(item.reminder.displayTitle)
                }

                Section {
                    let next = preview
                    if next.date == nil && next.km == nil {
                        Text("Ohne Wiederholung bleibt die Erinnerung als erledigt stehen.")
                            .foregroundStyle(.secondary)
                    } else {
                        if let date = next.date {
                            LabeledContent("Nächstes Mal am", value: date.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let km = next.km {
                            LabeledContent("Nächstes Mal bei", value: "\(km.formatted()) km")
                        }
                    }
                } header: {
                    Text("Danach")
                }

                if category != nil {
                    Section {
                        Toggle("Danach einen Kosteneintrag anlegen", isOn: $addCost)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Erledigt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Erledigt") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let reminder = item.reminder
        let payload = LocalReminderCalculator.completedPayload(reminder, doneDay: doneDate, doneKm: parsedKm)
        do {
            _ = try await AppRepository.shared.updateReminder(id: reminder.id, payload)
            var prefill: VehicleCostPrefill?
            if addCost, let category {
                prefill = VehicleCostPrefill(
                    vehicleId: reminder.vehicleId,
                    category: category,
                    date: Calendar.current.startOfDay(for: doneDate),
                    odometerKm: parsedKm,
                    label: reminder.displayTitle
                )
            }
            onCompleted(prefill)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
