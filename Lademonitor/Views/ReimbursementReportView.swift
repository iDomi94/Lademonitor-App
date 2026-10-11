import SwiftUI

/// Tool "Erstattungsbericht": Nachweis der Heimladungen eines Dienstwagens
/// fuer den Arbeitgeber - je Vorgang kWh, Herkunft der kWh und Betrag, dazu
/// Summen je Monat. Gerechnet wird immer LOKAL
/// (LocalReimbursementCalculator, gleiche Regeln wie reimbursement.py),
/// auch im Local-Only-Modus; geteilt wird als PDF oder CSV.
struct ReimbursementReportView: View {
    private enum PeriodKind: String, CaseIterable, Identifiable {
        case month, custom
        var id: String { rawValue }
    }

    @ObservedObject private var settings = AppSettings.shared

    @State private var vehicles: [Vehicle] = []
    @State private var providers: [Provider] = []
    @State private var sessions: [ChargingSession] = []
    @State private var rates: [ReimbursementRate] = []
    @State private var vehicleId: String?
    @State private var loadError: String?
    @State private var isSavingVehicle = false
    /// Hochgezaehlt nach jedem Laden/Speichern - loest das Neuschreiben der
    /// Dateien zum Teilen aus.
    @State private var dataVersion = 0

    @State private var periodKind: PeriodKind = .month
    /// Erster Tag des gewaehlten Monats, Standard Vormonat.
    @State private var month: Date = ReimbursementReportView.previousMonthStart()
    @State private var customFrom: Date = ReimbursementReportView.previousMonthStart()
    @State private var customTo: Date = Calendar.current.startOfDay(for: Date())

    @State private var showingSettings = false
    @State private var showingAddRate = false
    @State private var editingRate: ReimbursementRate?
    @State private var exportFiles: (csv: URL, pdf: URL)?

    private static func previousMonthStart() -> Date {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == vehicleId }
    }

    private var vehicleRates: [ReimbursementRate] {
        rates.filter { $0.vehicleId == vehicleId }.sorted { $0.validFrom > $1.validFrom }
    }

    private var period: (from: Date, to: Date) {
        let calendar = Calendar.current
        switch periodKind {
        case .month:
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month) ?? month
            return (month, end)
        case .custom:
            let from = calendar.startOfDay(for: customFrom)
            let to = calendar.startOfDay(for: customTo)
            return from <= to ? (from, to) : (to, from)
        }
    }

    private var report: ReimbursementReport? {
        guard let vehicle = selectedVehicle, vehicle.isCompanyCarValue else { return nil }
        let p = period
        return LocalReimbursementCalculator.report(
            vehicle: vehicle, sessions: sessions, providers: providers, rates: rates, from: p.from, to: p.to
        )
    }

    /// Wechselt, sobald sich etwas am Bericht aendern kann.
    private var exportKey: String {
        let p = period
        return "\(vehicleId ?? "-")|\(p.from.timeIntervalSince1970)|\(p.to.timeIntervalSince1970)|\(dataVersion)"
    }

    var body: some View {
        Form {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            vehicleSection
            if let vehicle = selectedVehicle, vehicle.isCompanyCarValue {
                if vehicle.reimbursementModeValue == .flat {
                    ratesSection
                }
                periodSection
                if let report {
                    reportSections(report)
                }
            }
        }
        .navigationTitle("Erstattungsbericht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let exportFiles, report != nil {
                    Menu {
                        ShareLink(item: exportFiles.pdf) {
                            Label("Als PDF teilen", systemImage: "doc.richtext")
                        }
                        ShareLink(item: exportFiles.csv) {
                            Label("Als CSV teilen", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await load() }
        .task(id: exportKey) { await refreshExports() }
        .sheet(isPresented: $showingSettings) {
            if let vehicle = selectedVehicle {
                ReimbursementSettingsSheet(vehicle: vehicle, isServerMode: settings.appMode == .server) { updated in
                    replace(updated)
                }
            }
        }
        .sheet(isPresented: $showingAddRate) {
            if let vehicleId {
                ReimbursementRateSheet(vehicleId: vehicleId, rate: nil, suggestion: vehicleRates.first) {
                    Task { await load() }
                }
            }
        }
        .sheet(item: $editingRate) { rate in
            ReimbursementRateSheet(vehicleId: rate.vehicleId, rate: rate, suggestion: nil) {
                Task { await load() }
            }
        }
    }

    // MARK: - Abschnitte

    private var vehicleSection: some View {
        Section {
            if vehicles.count > 1 {
                Picker("Fahrzeug", selection: $vehicleId) {
                    ForEach(vehicles) { vehicle in
                        Text(vehicle.name).tag(Optional(vehicle.id))
                    }
                }
            }
            if let vehicle = selectedVehicle {
                Toggle("Dienstwagen", isOn: companyCarBinding(vehicle))
                    .disabled(isSavingVehicle)
                if vehicle.isCompanyCarValue {
                    LabeledContent("Erstattungsart", value: modeText(vehicle))
                    if let plate = vehicle.licensePlate {
                        LabeledContent("Kennzeichen", value: plate)
                    }
                    if let name = vehicle.employeeName {
                        LabeledContent("Name", value: name)
                    }
                    if let number = vehicle.employeeNumber {
                        LabeledContent("Personalnummer", value: number)
                    }
                    Button("Angaben bearbeiten") { showingSettings = true }
                }
            } else if loadError == nil {
                Text("Noch kein Fahrzeug angelegt.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Fahrzeug")
        } footer: {
            if let vehicle = selectedVehicle, !vehicle.isCompanyCarValue {
                Text("Dieses Fahrzeug ist nicht als Dienstwagen markiert. Schalte „Dienstwagen“ ein, um den Bericht über die Heimladungen zu erstellen.")
            } else if selectedVehicle != nil {
                Text("Der Bericht enthält nur Ladevorgänge an Anbietern mit dem Ladeort „Zuhause“.")
            }
        }
    }

    private func modeText(_ vehicle: Vehicle) -> String {
        let mode = vehicle.reimbursementModeValue
        guard mode == .actual, vehicle.reimbursementIncludeFees ?? false else { return mode.displayName }
        return mode.displayName + " (" + String(localized: "inkl. Grundgebühr") + ")"
    }

    private var ratesSection: some View {
        Section {
            ForEach(vehicleRates) { rate in
                Button {
                    editingRate = rate
                } label: {
                    HStack {
                        Text("ab \(rate.validFrom.formatted(date: .numeric, time: .omitted))")
                        Spacer()
                        Text(ReimbursementExport.number(rate.ratePerKwh, digits: 4) + " €/kWh")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await deleteRate(rate) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
            Button {
                showingAddRate = true
            } label: {
                Label("Satz hinzufügen", systemImage: "plus")
            }
        } header: {
            Text("Erstattungssätze")
        } footer: {
            Text("Es gilt jeweils der Satz mit dem jüngsten „gültig ab“ vor dem Ladetag. Ladungen davor bekommen keinen Betrag.")
        }
    }

    private var periodSection: some View {
        Section {
            Picker("Zeitraum", selection: $periodKind) {
                Text("Monat").tag(PeriodKind.month)
                Text("Von – bis").tag(PeriodKind.custom)
            }
            .pickerStyle(.segmented)
            switch periodKind {
            case .month:
                HStack {
                    Button {
                        shiftMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Spacer()
                    Button {
                        shiftMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }
            case .custom:
                DatePicker("Von", selection: $customFrom, displayedComponents: .date)
                DatePicker("Bis", selection: $customTo, displayedComponents: .date)
            }
        } header: {
            Text("Zeitraum")
        }
    }

    @ViewBuilder
    private func reportSections(_ report: ReimbursementReport) -> some View {
        Section {
            LabeledContent("Ladungen", value: String(report.rows.count))
            LabeledContent("Energie", value: ReimbursementExport.number(report.totalKwh) + " kWh")
            LabeledContent("Erstattung", value: TariffCalculatorView.euro(report.totalAmount))
                .font(.headline)
        } header: {
            Text("Summe")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let note = ReimbursementExport.estimatedNote(report) { Text(note) }
                if let note = ReimbursementExport.missingNote(report) { Text(note) }
            }
        }

        if report.months.count > 1 {
            Section("Monatssummen") {
                ForEach(report.months) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.month)
                            Text("\(m.sessions) Ladungen · \(ReimbursementExport.number(m.energyKwh)) kWh")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(TariffCalculatorView.euro(m.amount))
                    }
                }
            }
        }

        Section {
            if report.rows.isEmpty {
                Text("Keine Heimladungen im Zeitraum.")
                    .foregroundStyle(.secondary)
            }
            ForEach(report.rows) { row in
                ReimbursementRowView(row: row, showsFee: report.includeFees)
            }
        } header: {
            Text("Ladevorgänge")
        }
    }

    // MARK: - Aktionen

    private func companyCarBinding(_ vehicle: Vehicle) -> Binding<Bool> {
        Binding(
            get: { vehicle.isCompanyCarValue },
            set: { newValue in Task { await setCompanyCar(vehicle, newValue) } }
        )
    }

    private func shiftMonth(_ delta: Int) {
        month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            loadError = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            let basis = try await AppRepository.shared.reimbursementBasis()
            // Dienstwagen zuerst, dann die aktiven.
            vehicles = basis.vehicles.sorted { a, b in
                if a.isCompanyCarValue != b.isCompanyCarValue { return a.isCompanyCarValue }
                return a.isActive && !b.isActive
            }
            providers = basis.providers
            sessions = basis.sessions
            rates = basis.rates
            if vehicleId == nil || !vehicles.contains(where: { $0.id == vehicleId }) {
                vehicleId = vehicles.first?.id
            }
            loadError = nil
            dataVersion += 1
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func replace(_ vehicle: Vehicle) {
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        }
        dataVersion += 1
    }

    private func setCompanyCar(_ vehicle: Vehicle, _ value: Bool) async {
        isSavingVehicle = true
        defer { isSavingVehicle = false }
        do {
            let updated = try await AppRepository.shared.updateVehicle(
                id: vehicle.id, ReimbursementSettingsSheet.payload(for: vehicle, isCompanyCar: value)
            )
            replace(updated)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteRate(_ rate: ReimbursementRate) async {
        do {
            try await AppRepository.shared.deleteReimbursementRate(id: rate.id)
            rates.removeAll { $0.id == rate.id }
            dataVersion += 1
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshExports() async {
        guard let report else {
            exportFiles = nil
            return
        }
        exportFiles = try? ReimbursementExport.writeFiles(report)
    }
}

private struct ReimbursementRowView: View {
    let row: ReimbursementRow
    let showsFee: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.startTime.formatted(date: .numeric, time: .shortened))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.amount.map { TariffCalculatorView.euro($0) } ?? "–")
                Text(row.energyKwh.map { ReimbursementExport.number($0) + " kWh" } ?? "– kWh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailText: String {
        var parts = [ReimbursementExport.sourceText(row.kwhSource)]
        if let km = row.odometerKm { parts.append("\(km) km") }
        if let rate = row.ratePerKwh { parts.append(ReimbursementExport.number(rate, digits: 4) + " €/kWh") }
        if showsFee, row.feeShare != 0 {
            parts.append(String(localized: "Grundgebühr") + " " + TariffCalculatorView.euro(row.feeShare))
        }
        return parts.joined(separator: " · ")
    }
}

/// Angaben zum Dienstwagen: Erstattungsart, Grundgebuehr, Name,
/// Personalnummer, Kennzeichen und (nur Server-Modus) die Monatsmail.
struct ReimbursementSettingsSheet: View {
    let vehicle: Vehicle
    let isServerMode: Bool
    let onSaved: (Vehicle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: ReimbursementMode
    @State private var includeFees: Bool
    @State private var employeeName: String
    @State private var employeeNumber: String
    @State private var licensePlate: String
    @State private var monthlyMail: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(vehicle: Vehicle, isServerMode: Bool, onSaved: @escaping (Vehicle) -> Void) {
        self.vehicle = vehicle
        self.isServerMode = isServerMode
        self.onSaved = onSaved
        _mode = State(initialValue: vehicle.reimbursementModeValue)
        _includeFees = State(initialValue: vehicle.reimbursementIncludeFees ?? false)
        _employeeName = State(initialValue: vehicle.employeeName ?? "")
        _employeeNumber = State(initialValue: vehicle.employeeNumber ?? "")
        _licensePlate = State(initialValue: vehicle.licensePlate ?? "")
        _monthlyMail = State(initialValue: vehicle.reimbursementMonthlyMail ?? false)
    }

    /// Alle Dienstwagen-Felder vom Fahrzeug, mit den angegebenen Aenderungen.
    static func payload(
        for vehicle: Vehicle,
        isCompanyCar: Bool? = nil,
        mode: ReimbursementMode? = nil,
        includeFees: Bool? = nil,
        employeeName: String?? = nil,
        employeeNumber: String?? = nil,
        licensePlate: String?? = nil,
        monthlyMail: Bool? = nil
    ) -> VehiclePayload {
        var p = VehiclePayload()
        p.sendsReimbursement = true
        p.isCompanyCar = isCompanyCar ?? vehicle.isCompanyCarValue
        p.reimbursementMode = (mode ?? vehicle.reimbursementModeValue).rawValue
        p.reimbursementIncludeFees = includeFees ?? (vehicle.reimbursementIncludeFees ?? false)
        p.employeeName = employeeName ?? vehicle.employeeName
        p.employeeNumber = employeeNumber ?? vehicle.employeeNumber
        p.licensePlate = licensePlate ?? vehicle.licensePlate
        p.reimbursementMonthlyMail = monthlyMail ?? (vehicle.reimbursementMonthlyMail ?? false)
        return p
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Erstattungsart", selection: $mode) {
                        ForEach(ReimbursementMode.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    if mode == .actual {
                        Toggle("Grundgebühr mit erstatten", isOn: $includeFees)
                    }
                } header: {
                    Text("Erstattung")
                } footer: {
                    switch mode {
                    case .flat:
                        Text("Je kWh ein fester Satz, den du unter „Erstattungssätze“ einträgst – z. B. die Pauschale deines Arbeitgebers.")
                    case .actual:
                        Text("Der Preis am Ladevorgang, sonst der letzte Preis des Anbieters. Die Grundgebühr wird wie im Dashboard nach kWh umgelegt.")
                    }
                }

                Section("Angaben für den Bericht") {
                    TextField("Name", text: $employeeName)
                    TextField("Personalnummer", text: $employeeNumber)
                    TextField("Kennzeichen", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                }

                if isServerMode {
                    Section {
                        Toggle("Monatsbericht per E-Mail", isOn: $monthlyMail)
                    } footer: {
                        Text("Der Server schickt Anfang jedes Monats den Bericht des Vormonats als CSV an die E-Mail-Adresse deines Kontos. Dafür muss auf dem Server der E-Mail-Versand eingerichtet sein.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Dienstwagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") {
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
        let text = { (value: String) -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let payload = Self.payload(
            for: vehicle,
            mode: mode,
            includeFees: mode == .actual ? includeFees : (vehicle.reimbursementIncludeFees ?? false),
            employeeName: .some(text(employeeName)),
            employeeNumber: .some(text(employeeNumber)),
            licensePlate: .some(text(licensePlate)),
            monthlyMail: isServerMode ? monthlyMail : nil
        )
        do {
            let updated = try await AppRepository.shared.updateVehicle(id: vehicle.id, payload)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

/// Erstattungssatz anlegen oder aendern.
private struct ReimbursementRateSheet: View {
    let vehicleId: String
    let rate: ReimbursementRate?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var validFrom: Date
    @State private var rateText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// `suggestion`: der juengste vorhandene Satz - ohne einen gilt der
    /// Vorschlag 0,34 EUR/kWh ab dem 1.1. des laufenden Jahres.
    init(vehicleId: String, rate: ReimbursementRate?, suggestion: ReimbursementRate?, onSaved: @escaping () -> Void) {
        self.vehicleId = vehicleId
        self.rate = rate
        self.onSaved = onSaved
        let validFrom: Date
        let value: Double
        if let rate {
            validFrom = rate.validFrom
            value = rate.ratePerKwh
        } else if let suggestion {
            validFrom = Calendar.current.startOfDay(for: Date())
            value = suggestion.ratePerKwh
        } else {
            validFrom = ReimbursementRate.defaultValidFrom
            value = ReimbursementRate.defaultRatePerKwh
        }
        _validFrom = State(initialValue: validFrom)
        _rateText = State(initialValue: ReimbursementExport.number(value, digits: abs(value * 100 - (value * 100).rounded()) < 1e-9 ? 2 : 4))
    }

    private var parsedRate: Double? {
        guard let value = Double(rateText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              value >= 0, value <= 10 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Gültig ab", selection: $validFrom, displayedComponents: .date)
                    HStack {
                        Text("Satz (€/kWh)")
                        Spacer()
                        TextField("0,34", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Der Satz gilt ab diesem Tag bis zum nächsten eingetragenen Satz.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(rate == nil ? "Neuer Erstattungssatz" : "Erstattungssatz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert…" : "Speichern") {
                        Task { await save() }
                    }
                    .disabled(isSaving || parsedRate == nil)
                }
            }
        }
    }

    private func save() async {
        guard let value = parsedRate else { return }
        isSaving = true
        errorMessage = nil
        let payload = ReimbursementRatePayload(
            vehicleId: rate?.vehicleId ?? vehicleId,
            validFrom: Calendar.current.startOfDay(for: validFrom),
            ratePerKwh: value
        )
        do {
            if let rate {
                _ = try await AppRepository.shared.updateReimbursementRate(id: rate.id, payload)
            } else {
                _ = try await AppRepository.shared.createReimbursementRate(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
