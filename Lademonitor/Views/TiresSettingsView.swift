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
    @State private var measurements: [TireTreadMeasurement] = []
    @State private var measuringFor: TireSet?

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
            treadSection
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
            AddEditTireSetView(tireSet: nil, vehicles: vehicles, existing: sets) { Task { await load() } }
        }
        .sheet(item: $editing) { tireSet in
            AddEditTireSetView(tireSet: tireSet, vehicles: vehicles, existing: sets) { Task { await load() } }
        }
        .sheet(item: $measuringFor) { tireSet in
            AddTreadMeasurementView(tireSet: tireSet) { Task { await load() } }
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
            Section {
                ForEach(overview.sets) { summary in
                    TireSetSummaryRow(summary: summary)
                }
            } header: {
                Text("Reifensätze")
            } footer: {
                if overview.sets.contains(where: { !$0.kmIsExact }) {
                    Text("* Nur aus den zugeordneten Fahrten gezählt – die Fahrt über den Wechsel hinweg fehlt. Trage den Kilometerstand beim Wechsel ein, dann wird der Wert exakt.")
                }
            }
        }
    }

    @ViewBuilder
    private var mountingsSection: some View {
        Section {
            // Der Einstiegstext steht hier und nicht in einer Hilfe: gebraucht
            // wird er genau in dem Moment, in dem die Liste leer ist.
            if mountings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("So fängst du an")
                        .font(.footnote.weight(.semibold))
                    Text("Trag den Satz ein, der gerade aufgezogen ist – mit dem Datum, an dem er montiert wurde, auch wenn das ein Jahr zurückliegt, und dem Kilometerstand von damals, falls du ihn noch findest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Fahrten VOR diesem Datum bleiben ohne Reifensatz – was damals drauf war, weiß die App nicht. Beim Raten lieber ein etwas späteres Datum als ein zu frühes: zu früh schreibt diesem Satz fremde Fahrten zu, zu spät lässt nur ein paar Fahrten weg.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
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
                // Profil messen: zwischendurch, ohne Wechsel. Beim Wechsel
                // selbst geht es direkt im Wechsel-Formular.
                .swipeActions(edge: .leading) {
                    if let tireSet = sets.first(where: { $0.id == mounting.tireSetId }) {
                        Button {
                            measuringFor = tireSet
                        } label: {
                            Label("Profil messen", systemImage: "ruler")
                        }
                        .tint(.blue)
                    }
                }
                .contextMenu {
                    if let tireSet = sets.first(where: { $0.id == mounting.tireSetId }) {
                        Button { measuringFor = tireSet } label: {
                            Label("Profil messen", systemImage: "ruler")
                        }
                        Button { editing = tireSet } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
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

    @ViewBuilder
    private var treadSection: some View {
        if !sets.isEmpty {
            Section {
                if measurements.isEmpty {
                    Text("Noch keine Messung eingetragen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(measurements) { measurement in
                    TreadMeasurementRow(
                        measurement: measurement,
                        tireSet: sets.first { $0.id == measurement.tireSetId }
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await deleteMeasurement(measurement) }
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
                Button {
                    measuringFor = currentSet
                } label: {
                    Label("Messung eintragen", systemImage: "ruler")
                }
            } header: {
                Text("Profiltiefe")
            } footer: {
                Text("Gemessen wird in den Hauptrillen an der flachsten Stelle. Gesetzliches Minimum sind 1,6 mm; empfohlen werden mindestens 3 mm bei Sommer- und 4 mm bei Winter- und Ganzjahresreifen. Einen Satz zwischendurch messen: in der Liste der Reifenwechsel nach rechts wischen.")
            }
        }
    }

    /// Fuer "Messung eintragen": der zuletzt aufgezogene Satz - das ist der,
    /// den man zwischendurch am haeufigsten misst.
    private var currentSet: TireSet? {
        sets.max { $0.installedOn < $1.installedOn }
    }

    /// Die Wechsel-Liste kommt aus der Uebersicht, weil nur sie Zeitraum und
    /// Laufleistung kennt. Fehlt sie (alter Server, Abruf gescheitert), werden
    /// die reinen Stammdaten gezeigt statt gar nichts.
    private var mountings: [TireMounting] {
        if let overview, !overview.mountings.isEmpty { return overview.mountings }
        return sets.map {
            TireMounting(tireSetId: $0.id, vehicleId: $0.vehicleId, kind: $0.kind,
                         label: $0.label, installedOn: $0.installedOn, removedOn: nil,
                         isCurrent: false, days: 0, drives: 0, km: 0, kmSource: nil,
                         energyKwh: 0, avgConsumptionKwhPer100km: nil)
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
        // Server vor 0.30.0 kennt keine Messungen - dann bleibt die Liste leer.
        measurements = (try? await APIClient.shared.fetchTreadMeasurements()) ?? []
    }

    private func deleteMeasurement(_ measurement: TireTreadMeasurement) async {
        do {
            try await APIClient.shared.deleteTreadMeasurement(id: measurement.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                // Ein Sternchen an der Zahl, wenn sie nur aus den zugeordneten
                // Fahrten stammt - dort fehlt die Fahrt ueber den Wechsel.
                Text(summary.kmIsExact
                     ? "\(Int(summary.km.rounded())) km"
                     : "\(Int(summary.km.rounded())) km *")
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
            if summary.productionAgeDays != nil || summary.treadDepthMm != nil {
                HStack(spacing: 12) {
                    if let days = summary.productionAgeDays {
                        HStack(spacing: 4) {
                            Text("DOT \(summary.producedLabel ?? "") · \(TireFormat.duration(days))")
                            TireStatusLabel(ageStatus: summary.ageStatus)
                        }
                    }
                    if let depth = summary.treadDepthMm {
                        HStack(spacing: 4) {
                            Text(TireFormat.millimetres(depth))
                            TireStatusLabel(treadStatus: summary.treadStatus)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
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
            if mounting.drives > 0 || mounting.km > 0 {
                Text(mounting.kmIsExact
                     ? "\(Int(mounting.km.rounded())) km · \(mounting.drives) Fahrten · \(TireFormat.duration(mounting.days))"
                     : "\(Int(mounting.km.rounded())) km * · \(mounting.drives) Fahrten · \(TireFormat.duration(mounting.days))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let depth = mounting.treadDepthMm {
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                    Text(TireFormat.millimetres(depth))
                    TireStatusLabel(treadStatus: mounting.treadStatus)
                }
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

private struct TreadMeasurementRow: View {
    let measurement: TireTreadMeasurement
    let tireSet: TireSet?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(TireFormat.millimetres(measurement.depthMm))
                    .font(.body.monospacedDigit())
                Spacer()
                Text(measurement.measuredOn, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let tireSet {
                Text("\(tireSet.kind.label) · \(tireSet.label.isEmpty ? tireSet.kind.label : tireSet.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Einzelwerte in Fahrzeug-Reihenfolge VL/VR/HL/HR, nur wenn da.
            if measurement.wheels.contains(where: { $0 != nil }) {
                Text(String(localized: "VL/VR/HL/HR") + ": " + measurement.wheels
                    .map { $0.map { String(format: "%.1f", $0) } ?? "–" }
                    .joined(separator: " / "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let km = measurement.odometerKm {
                Text("\(Int(km.rounded())) km")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Wort plus Farbe, nie Farbe allein: orange = genauer hinsehen, rot =
/// handeln. Die Schwellen liegen auf dem Server (tires.py).
private struct TireStatusLabel: View {
    var ageStatus: String? = nil
    var treadStatus: String? = nil

    var body: some View {
        if let content {
            Text(content.text)
                .foregroundStyle(content.color)
        }
    }

    private var content: (text: String, color: Color)? {
        switch ageStatus {
        case "check": return (String(localized: "prüfen"), .orange)
        case "replace": return (String(localized: "tauschen"), .red)
        default: break
        }
        switch treadStatus {
        case "low": return (String(localized: "unter Empfehlung"), .orange)
        case "legal_min": return (String(localized: "Mindestprofil"), .red)
        default: return nil
        }
    }
}

enum TireFormat {
    static func millimetres(_ value: Double) -> String {
        String(format: "%.1f mm", value)
    }

    /// "4,5" oder "4.5" - leer heisst nil.
    static func parseMillimetres(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

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
    /// Alle bisherigen Montagen - nur um zu wissen, ob es einen "abgenommenen"
    /// Satz gibt, dessen Profil man beim Wechsel mitmessen kann.
    var existing: [TireSet] = []
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleId: String
    @State private var kind: TireKind
    @State private var installedOn: Date
    @State private var odometerKm: String
    @State private var size: String
    @State private var sizeRear: String
    @State private var brand: String
    @State private var model: String
    @State private var notes: String
    @State private var dot: String
    @State private var dotRear: String
    @State private var treadNew = TreadDraft()
    @State private var treadRemoved = TreadDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(tireSet: TireSet?, vehicles: [Vehicle], existing: [TireSet] = [], onSaved: @escaping () -> Void) {
        self.tireSet = tireSet
        self.vehicles = vehicles
        self.existing = existing
        self.onSaved = onSaved
        _dot = State(initialValue: tireSet?.dot ?? "")
        _dotRear = State(initialValue: tireSet?.dotRear ?? "")
        _vehicleId = State(initialValue: tireSet?.vehicleId ?? vehicles.first?.id ?? "")
        _kind = State(initialValue: tireSet?.kind ?? .summer)
        _installedOn = State(initialValue: tireSet?.installedOn ?? Date())
        _odometerKm = State(initialValue: tireSet?.odometerKm.map { String(format: "%.0f", $0) } ?? "")
        _size = State(initialValue: tireSet?.size ?? "")
        _sizeRear = State(initialValue: tireSet?.sizeRear ?? "")
        _brand = State(initialValue: tireSet?.brand ?? "")
        _model = State(initialValue: tireSet?.model ?? "")
        _notes = State(initialValue: tireSet?.notes ?? "")
    }

    private var isEditing: Bool { tireSet != nil }

    /// Die Montage, die dieser Wechsel beendet - dieselbe Regel wie auf dem
    /// Server (letzte Montage VOR dem Datum an diesem Fahrzeug).
    private var removedSet: TireSet? {
        let day = Calendar.current.startOfDay(for: installedOn)
        return existing
            .filter { $0.vehicleId == vehicleId && $0.installedOn < day }
            .max { $0.installedOn < $1.installedOn }
    }

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
                    HStack {
                        Text("Kilometerstand")
                        Spacer()
                        TextField("optional", text: $odometerKm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Ab diesem Datum gilt der Satz, bis der nächste Wechsel folgt. Ein Enddatum gibt es deshalb nicht. Der Kilometerstand macht die Laufleistung exakt – ohne ihn wird sie aus den zugeordneten Fahrten gezählt, und die eine Fahrt über den Wechsel hinweg fehlt darin.")
                }

                Section {
                    TextField("Größe (z. B. 235/45 R21)", text: $size)
                    TextField("Größe hinten (nur bei Mischbereifung)", text: $sizeRear)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Modell (optional)", text: $model)
                    TextField("Notiz (optional)", text: $notes)
                } header: {
                    Text("Reifen")
                } footer: {
                    Text("Gleiche Größe rundum? Dann reicht das erste Feld. Bei Mischbereifung steht dort die Vorderachse und darunter die Hinterachse.")
                }

                Section {
                    TextField("DOT (z. B. 2323)", text: $dot)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("DOT hinten (nur wenn abweichend)", text: $dotRear)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Alter (DOT)")
                } footer: {
                    Text("Die letzten vier Ziffern der DOT-Nummer an der Reifenflanke: Produktionswoche und -jahr (2323 = KW 23/2023). Daraus ergibt sich das Reifenalter – ab 6 Jahren genauer hinsehen, nach spätestens 10 Jahren tauschen. Haben die Reifen einer Achse verschiedene Daten, trag das ältere ein. Bei Wiedermontage desselben Satzes reicht die DOT an einem Eintrag.")
                }

                // Gemessen wird beim Anlegen des Wechsels; spaeter ueber
                // "Profil messen" in der Liste.
                if !isEditing {
                    Section {
                        TreadFields(draft: $treadNew)
                    } header: {
                        Text("Profil aufgezogener Satz")
                    } footer: {
                        Text("Optional: die geringste gemessene Tiefe in mm – oder je Reifen, dann zählt der geringste Wert.")
                    }
                    if let removedSet {
                        Section {
                            TreadFields(draft: $treadRemoved)
                        } header: {
                            Text("Profil abgenommener Satz")
                        } footer: {
                            Text("Gilt für \(removedSet.label.isEmpty ? removedSet.kind.label : removedSet.label), den bisher montierten Satz. Beide Messungen bekommen Datum und Kilometerstand dieses Wechsels.")
                        }
                    }
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
            // Ohne Angabe bewusst nil statt 0 - die Auswertung faellt dann auf
            // die Fahrten zurueck, statt bei Kilometerstand 0 zu beginnen.
            odometerKm: Double(odometerKm.replacingOccurrences(of: ",", with: ".")),
            size: cleaned(size),
            sizeRear: cleaned(sizeRear),
            brand: cleaned(brand),
            model: cleaned(model),
            notes: cleaned(notes),
            dot: cleaned(dot),
            dotRear: cleaned(dotRear),
            tread: isEditing ? nil : treadNew.input,
            removedTread: isEditing || removedSet == nil ? nil : treadRemoved.input
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

// MARK: - Profiltiefe

/// Eingabe einer Profilmessung als Text - leere Felder bleiben nil.
struct TreadDraft {
    var minimum = ""
    var frontLeft = ""
    var frontRight = ""
    var rearLeft = ""
    var rearRight = ""

    var input: TreadInput? {
        let tread = TreadInput(
            depthMm: TireFormat.parseMillimetres(minimum),
            frontLeftMm: TireFormat.parseMillimetres(frontLeft),
            frontRightMm: TireFormat.parseMillimetres(frontRight),
            rearLeftMm: TireFormat.parseMillimetres(rearLeft),
            rearRightMm: TireFormat.parseMillimetres(rearRight)
        )
        return tread.isEmpty ? nil : tread
    }
}

/// Ein Gesamtwert plus - zugeklappt - die vier Raeder, 2x2 wie am Fahrzeug.
struct TreadFields: View {
    @Binding var draft: TreadDraft

    var body: some View {
        HStack {
            Text("Geringste Tiefe")
            Spacer()
            TextField("mm", text: $draft.minimum)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        DisclosureGroup("Je Reifen") {
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    wheelField("VL", text: $draft.frontLeft)
                    wheelField("VR", text: $draft.frontRight)
                }
                GridRow {
                    wheelField("HL", text: $draft.rearLeft)
                    wheelField("HR", text: $draft.rearRight)
                }
            }
        }
    }

    private func wheelField(_ label: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            TextField("mm", text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct AddTreadMeasurementView: View {
    let tireSet: TireSet
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var measuredOn = Date()
    @State private var odometerKm = ""
    @State private var draft = TreadDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(tireSet.kind.label) · \(tireSet.label.isEmpty ? tireSet.kind.label : tireSet.label)")
                        .foregroundStyle(.secondary)
                    DatePicker("Gemessen am", selection: $measuredOn, displayedComponents: .date)
                    HStack {
                        Text("Kilometerstand")
                        Spacer()
                        TextField("optional", text: $odometerKm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    TreadFields(draft: $draft)
                } header: {
                    Text("Profiltiefe")
                } footer: {
                    Text("Gesetzliches Minimum sind 1,6 mm; empfohlen werden mindestens 3 mm bei Sommer- und 4 mm bei Winter- und Ganzjahresreifen.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Profil messen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") { Task { await save() } }
                        .disabled(isSaving || draft.input == nil)
                }
            }
        }
    }

    private func save() async {
        guard let tread = draft.input else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let payload = TreadMeasurementPayload(
            measuredOn: Calendar.current.startOfDay(for: measuredOn),
            odometerKm: Double(odometerKm.replacingOccurrences(of: ",", with: ".")),
            tread: tread
        )
        do {
            _ = try await APIClient.shared.createTreadMeasurement(tireSetId: tireSet.id, payload)
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
