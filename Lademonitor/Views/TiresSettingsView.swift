import SwiftUI

/// Reifenwechsel erfassen und sehen, was auf welchem Satz gelaufen ist.
///
/// **Nur im Server-Modus erreichbar** (SettingsView blendet den Punkt sonst
/// aus): die Zuordnung der Fahrten zu den Saetzen und der temperaturbereinigte
/// Vergleich liegen komplett auf dem Server. Siehe TireModels.swift.
struct TiresSettingsView: View {
    @State private var sets: [TireSet] = []
    @State private var overview: TireOverview?
    @State private var comparison: TireComparison?
    @State private var vehicles: [Vehicle] = []
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var editing: TireSet?
    @State private var pendingDelete: TireMounting?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            comparisonSection
            setsSection
            mountingsSection
        }
        .navigationTitle("Reifen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .disabled(vehicles.isEmpty)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) {
            AddEditTireSetView(tireSet: nil, vehicles: vehicles) { Task { await load() } }
        }
        .sheet(item: $editing) { tireSet in
            AddEditTireSetView(tireSet: tireSet, vehicles: vehicles) { Task { await load() } }
        }
        .alert("Reifenwechsel löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { mounting in
            Button("Löschen", role: .destructive) { Task { await delete(mounting) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Die Ladevorgänge bleiben erhalten – sie werden danach nur keinem Reifensatz mehr zugeordnet.")
        }
    }

    // MARK: - Abschnitte

    @ViewBuilder
    private var comparisonSection: some View {
        if let comparison, let winterVsSummer = comparison.winterVsSummerPct {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(signed(winterVsSummer, digits: 1) + " %")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mehrverbrauch Winter- gegenüber Sommerreifen")
                            .font(.subheadline)
                        if let reference = comparison.referenceTempC {
                            // Bewusst ueber String(format:) statt Text-Interpolation
                            // mit specifier: so ist der Schluessel in
                            // Localizable.xcstrings eindeutig "%@".
                            Text(String(format: String(localized: "Temperaturbereinigt auf %@ °C"),
                                        String(format: "%.0f", reference)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                // Ohne gemeinsamen Temperaturbereich ist die Bereinigung eine
                // Hochrechnung - das gehoert an die Zahl, nicht in eine Fussnote.
                if !comparison.overlapOk {
                    Label(overlapHint(comparison), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Vergleich")
            } footer: {
                Text("Verglichen wird nicht der rohe Saison-Durchschnitt – der würde nur messen, dass Winterreifen im Winter gefahren werden –, sondern die Abweichung von der Verbrauchskurve über der Außentemperatur.")
            }
        }
    }

    @ViewBuilder
    private var setsSection: some View {
        if let overview, !overview.sets.isEmpty {
            Section("Reifensätze") {
                ForEach(overview.sets) { summary in
                    TireSetSummaryRow(summary: summary)
                }
            }
        }
    }

    @ViewBuilder
    private var mountingsSection: some View {
        Section {
            if mountings.isEmpty {
                Text("Noch kein Reifenwechsel eingetragen. Trage den ersten ein – ab diesem Datum gilt der Satz, bis der nächste Eintrag folgt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(mountings) { mounting in
                Button {
                    editing = sets.first { $0.id == mounting.tireSetId }
                } label: {
                    TireMountingRow(mounting: mounting, vehicleName: vehicleName(mounting.vehicleId))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDelete = mounting
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Reifenwechsel")
        } footer: {
            if let overview, overview.drivesWithoutSet + overview.drivesSpanningChange > 0 {
                Text("Nicht berücksichtigt: \(overview.drivesWithoutSet) Fahrten ohne zugeordneten Reifensatz, \(overview.drivesSpanningChange) Fahrten über einen Wechsel hinweg.")
            }
        }
    }

    /// Die Wechsel-Liste kommt aus der Uebersicht, weil nur sie Zeitraum und
    /// Laufleistung kennt. Fehlt sie (alter Server, Abruf gescheitert), werden
    /// die reinen Stammdaten gezeigt statt gar nichts.
    private var mountings: [TireMounting] {
        if let overview, !overview.mountings.isEmpty { return overview.mountings }
        return sets.map {
            TireMounting(tireSetId: $0.id, vehicleId: $0.vehicleId, kind: $0.kind,
                         label: $0.label, installedOn: $0.installedOn, removedOn: nil,
                         isCurrent: false, days: 0, drives: 0, km: 0, energyKwh: 0,
                         avgConsumptionKwhPer100km: nil)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func vehicleName(_ id: String) -> String {
        vehicles.first { $0.id == id }?.name ?? ""
    }

    private func overlapHint(_ comparison: TireComparison) -> String {
        guard let span = comparison.overlapSpanC, span > 0 else {
            return String(localized: "Die Sätze wurden in getrennten Temperaturbereichen gefahren – der bereinigte Vergleich ist damit eine Hochrechnung.")
        }
        return String(localized: "Die Sätze überlappen sich nur um \(String(format: "%.1f", span)) K Temperatur – die Zahl ist überwiegend eine Hochrechnung.")
    }

    private func signed(_ value: Double, digits: Int) -> String {
        (value >= 0 ? "+" : "") + String(format: "%.\(digits)f", value)
    }

    // MARK: - Laden

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            async let sets = APIClient.shared.fetchTireSets()
            async let vehicles = AppRepository.shared.fetchVehicles()
            self.sets = try await sets
            self.vehicles = try await vehicles
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Auswertungen einzeln und fehlertolerant: gegen einen Server ohne
        // diese Endpunkte bleibt die Verwaltung trotzdem benutzbar.
        overview = try? await APIClient.shared.fetchTireOverview()
        comparison = try? await APIClient.shared.fetchTireComparison()
    }

    private func delete(_ mounting: TireMounting) async {
        do {
            try await APIClient.shared.deleteTireSet(id: mounting.tireSetId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Zeilen

private struct TireSetSummaryRow: View {
    let summary: TireSetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: summary.kind.symbolName)
                    .foregroundStyle(.secondary)
                Text(summary.label.isEmpty ? summary.kind.label : summary.label)
                    .font(.body)
                if summary.isCurrent {
                    Text("aufgezogen")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 12) {
                Text("\(Int(summary.km.rounded())) km")
                Text("\(summary.drives) Fahrten")
                if let consumption = summary.avgConsumptionKwhPer100km {
                    Text(String(format: "%.1f kWh/100 km", consumption))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Alter und montierte Zeit nebeneinander: Gummi altert auch im
            // Keller, die Laufleistung tut es nicht.
            Text("\(TireFormat.duration(summary.daysMounted)) montiert · \(TireFormat.duration(summary.ageDays)) alt · \(summary.mountings)×")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct TireMountingRow: View {
    let mounting: TireMounting
    let vehicleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: mounting.kind.symbolName)
                    .foregroundStyle(.secondary)
                Text(mounting.label.isEmpty ? mounting.kind.label : mounting.label)
                Spacer()
                Text(mounting.installedOn, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(period)
                .font(.caption)
                .foregroundStyle(.secondary)
            if mounting.drives > 0 {
                Text("\(Int(mounting.km.rounded())) km · \(mounting.drives) Fahrten · \(TireFormat.duration(mounting.days))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Das Ende einer Montage steht nicht am Datensatz - es ist der naechste
    /// Wechsel, und solange keiner folgt, liegt der Satz noch drauf.
    private var period: String {
        var parts = [mounting.kind.label]
        if !vehicleName.isEmpty { parts.append(vehicleName) }
        if let removed = mounting.removedOn {
            parts.append(String(localized: "bis \(removed.formatted(.dateTime.day().month().year()))"))
        } else {
            parts.append(String(localized: "bis heute"))
        }
        return parts.joined(separator: " · ")
    }
}

enum TireFormat {
    /// Ein Reifen laeuft ueber Jahre - in Tagen ist das ab einem gewissen
    /// Punkt keine ablesbare Zahl mehr.
    static func duration(_ days: Int) -> String {
        days >= 365
            ? String(format: "%.1f ", Double(days) / 365.0) + String(localized: "Jahre")
            : "\(days) " + String(localized: "Tage")
    }
}

// MARK: - Formular

struct AddEditTireSetView: View {
    let tireSet: TireSet?
    let vehicles: [Vehicle]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String
    @State private var kind: TireKind
    @State private var installedOn: Date
    @State private var size: String
    @State private var brand: String
    @State private var model: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(tireSet: TireSet?, vehicles: [Vehicle], onSaved: @escaping () -> Void) {
        self.tireSet = tireSet
        self.vehicles = vehicles
        self.onSaved = onSaved
        _vehicleId = State(initialValue: tireSet?.vehicleId ?? vehicles.first?.id ?? "")
        _kind = State(initialValue: tireSet?.kind ?? .summer)
        _installedOn = State(initialValue: tireSet?.installedOn ?? Date())
        _size = State(initialValue: tireSet?.size ?? "")
        _brand = State(initialValue: tireSet?.brand ?? "")
        _model = State(initialValue: tireSet?.model ?? "")
        _notes = State(initialValue: tireSet?.notes ?? "")
    }

    private var isEditing: Bool { tireSet != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Fahrzeug", selection: $vehicleId) {
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.name).tag(vehicle.id)
                        }
                    }
                    .disabled(isEditing)
                    Picker("Art", selection: $kind) {
                        ForEach(TireKind.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    DatePicker("Montiert am", selection: $installedOn, displayedComponents: .date)
                } footer: {
                    Text("Ab diesem Datum gilt der Satz, bis der nächste Wechsel folgt. Ein Enddatum gibt es deshalb nicht.")
                }

                Section("Reifen") {
                    TextField("Größe (z. B. 235/45 R21)", text: $size)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Modell (optional)", text: $model)
                    TextField("Notiz (optional)", text: $notes)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "Reifenwechsel bearbeiten" : "Neuer Reifenwechsel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") { Task { await save() } }
                        .disabled(isSaving || vehicleId.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        func cleaned(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        // Der Server rechnet in naiven datetimes; die Uhrzeit des Wechsels
        // weiss ohnehin niemand mehr, deshalb Tagesbeginn.
        let day = Calendar.current.startOfDay(for: installedOn)
        let payload = TireSetPayload(
            vehicleId: isEditing ? nil : vehicleId,
            kind: kind,
            installedOn: day,
            size: cleaned(size),
            brand: cleaned(brand),
            model: cleaned(model),
            notes: cleaned(notes)
        )

        do {
            if let tireSet {
                _ = try await APIClient.shared.updateTireSet(id: tireSet.id, payload)
            } else {
                _ = try await APIClient.shared.createTireSet(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { TiresSettingsView() }
}
