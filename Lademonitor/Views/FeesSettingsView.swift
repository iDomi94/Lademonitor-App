import SwiftUI

/// Grundgebuehren und Abos der Anbieter (z.B. Ionity Powerpass 15 € im Monat).
///
/// Anders als die Reifen in beiden Modi verfuegbar: die Umlage rechnet die App
/// selbst (LocalFeeAllocator), weil sie in die lokal berechneten
/// Dashboard-Kosten eingeht.
struct FeesSettingsView: View {
    @State private var fees: [ProviderFee] = []
    @State private var providers: [Provider] = []
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var editing: ProviderFee?
    @State private var pendingDelete: ProviderFee?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(fees) { fee in
                    Button {
                        editing = fee
                    } label: {
                        FeeRow(fee: fee, providerName: providerName(fee.providerId))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = fee
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("Die Gebühr wird nach kWh auf die Ladevorgänge des Anbieters im jeweiligen Zeitraum umgelegt und zählt in Gesamtkosten, Preis pro kWh und Kosten pro 100 km mit. Der Preis an der Säule bleibt unverändert. Eine Gutschrift (Rabatt, Gutschein) wird genauso umgelegt, nur abgezogen.")
            }
        }
        .overlay {
            if fees.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "Keine Grundgebühren",
                    systemImage: "creditcard",
                    description: Text("Zum Beispiel ein Abo mit monatlicher Gebühr, das einen günstigeren kWh-Preis bringt, oder ein Gutschein des Anbieters.")
                )
            }
        }
        .navigationTitle("Grundgebühren & Gutschriften")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(providers.isEmpty)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingAdd) {
            AddEditFeeView(fee: nil, providers: providers) { Task { await load() } }
        }
        .sheet(item: $editing) { fee in
            AddEditFeeView(fee: fee, providers: providers) { Task { await load() } }
        }
        .alert("Eintrag löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { fee in
            Button("Löschen", role: .destructive) { Task { await delete(fee) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { fee in
            Text("„\(fee.label ?? providerName(fee.providerId))“ wird gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func providerName(_ id: String) -> String {
        providers.first { $0.id == id }?.name ?? String(localized: "Unbekannter Anbieter")
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            providers = try await AppRepository.shared.fetchProviders()
            fees = try await AppRepository.shared.fetchFees()
            errorMessage = providers.isEmpty
                ? String(localized: "Lege zuerst einen Anbieter an.")
                : nil
        } catch {
            if fees.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ fee: ProviderFee) async {
        do {
            try await AppRepository.shared.deleteFee(id: fee.id)
            fees.removeAll { $0.id == fee.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeeRow: View {
    let fee: ProviderFee
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fee.label.map { "\(providerName) · \($0)" } ?? providerName)
                    .font(.body)
                Spacer()
                Text(amountText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(fee.isCredit ? Color.green : Color.primary)
            }
            Text(periodText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Bisher insgesamt \(LocalFeeAllocator.chargedToDate(fee).formatted(.currency(code: "EUR")))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var amountText: String {
        if fee.isCredit {
            return "\(fee.amount.formatted(.currency(code: "EUR"))) " + String(localized: "Gutschrift")
        }
        return "\(fee.amount.formatted(.currency(code: "EUR"))) \(fee.interval.perLabel)"
    }

    private var periodText: String {
        let start = fee.startDate.formatted(date: .abbreviated, time: .omitted)
        if fee.interval == .once && fee.singleSession {
            return String(format: String(localized: "Nächste Ladung ab %@"), start)
        }
        if let end = fee.endDate, let months = fee.spreadMonths, fee.interval == .once {
            return "\(start) – \(end.formatted(date: .abbreviated, time: .omitted)) · "
                + String(format: String(localized: "%lld Monate"), months)
        }
        if let end = fee.endDate {
            return "\(start) – \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return String(localized: "ab \(start)")
    }
}

struct AddEditFeeView: View {
    let fee: ProviderFee?
    let providers: [Provider]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var capabilities = ServerCapabilities.shared

    @State private var providerId: String
    @State private var kind: FeeKind
    @State private var amount: String
    @State private var interval: FeeInterval
    @State private var spread: FeeSpread
    @State private var months: Int
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var label: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(fee: ProviderFee?, providers: [Provider], onSaved: @escaping () -> Void) {
        self.fee = fee
        self.providers = providers
        self.onSaved = onSaved
        let start = fee?.startDate ?? Calendar.current.startOfDay(for: Date())
        _providerId = State(initialValue: fee?.providerId ?? providers.first?.id ?? "")
        _kind = State(initialValue: (fee?.isCredit ?? false) ? .credit : .fee)
        _amount = State(initialValue: fee.map { String(format: "%.2f", abs($0.amount)) } ?? "")
        _interval = State(initialValue: fee?.interval ?? .monthly)
        _spread = State(initialValue: fee.map { $0.singleSession ? .session : ($0.spreadMonths != nil ? .months : .range) }
            ?? .range)
        _months = State(initialValue: fee?.spreadMonths ?? 1)
        _startDate = State(initialValue: start)
        _hasEndDate = State(initialValue: fee?.endDate != nil)
        _endDate = State(initialValue: fee?.endDate
            ?? Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start)
        _label = State(initialValue: fee?.label ?? "")
        _notes = State(initialValue: fee?.notes ?? "")
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }

    /// Gutschriften und "eine Ladung"/"x Monate" braucht Server 0.56.0.
    private var creditHint: String? { capabilities.unavailableHint(.providerCredit) }

    /// Worauf ein einmaliger Betrag verteilt wird. Ohne Server 0.56.0 bleibt
    /// nur der Zeitraum bis zum Enddatum.
    private var effectiveSpread: FeeSpread { creditHint == nil ? spread : .range }

    /// Einmalige Betraege auf einen Zeitraum brauchen ein Enddatum - sonst
    /// waere der Zeitraum ein einziger Tag. Der Server verlangt das genauso (422).
    private var needsEndDate: Bool { interval == .once && effectiveSpread == .range }

    private var canSave: Bool {
        guard !providerId.isEmpty, let parsedAmount, parsedAmount > 0 else { return false }
        if kind == .credit && creditHint != nil { return false }
        if ((hasEndDate && interval != .once) || needsEndDate) && endDate < startDate { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Anbieter", selection: $providerId) {
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    TextField("Bezeichnung (z. B. Powerpass)", text: $label)
                }

                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(FeeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .disabled(creditHint != nil && kind == .fee)
                    .onChange(of: kind) { _, newKind in
                        // Eine Gutschrift ist fast immer einmalig.
                        if newKind == .credit && fee == nil { interval = .once }
                    }
                } footer: {
                    if let creditHint {
                        Text(String(localized: "Gutschriften: ") + creditHint)
                    }
                }

                Section {
                    HStack {
                        Text("Betrag (€)")
                        Spacer()
                        TextField("15,00" as String, text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Rhythmus", selection: $interval) {
                        ForEach(FeeInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    if interval == .once {
                        Picker("Verteilen auf", selection: $spread) {
                            ForEach(FeeSpread.allCases) { spread in
                                Text(spread.displayName).tag(spread)
                            }
                        }
                        .disabled(creditHint != nil)
                        if effectiveSpread == .months {
                            Stepper(value: $months, in: 1...120) {
                                Text(String(format: String(localized: "%lld Monate"), months))
                            }
                        }
                    }
                } footer: {
                    Text(intervalFooter)
                }

                Section {
                    DatePicker(startLabel, selection: $startDate, displayedComponents: .date)
                    if interval != .once {
                        Toggle("Gekündigt", isOn: $hasEndDate)
                    }
                    if (hasEndDate && interval != .once) || needsEndDate {
                        DatePicker(needsEndDate ? LocalizedStringKey("Bis") : LocalizedStringKey("Letzter Tag"), selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Zeitraum")
                } footer: {
                    if interval == .once && effectiveSpread == .months {
                        Text(String(format: String(localized: "Bis einschließlich %@."),
                                    ProviderFee.spreadEndDate(start: startDate, months: months)
                                        .formatted(date: .abbreviated, time: .omitted)))
                    } else if interval != .once {
                        Text("Eine Preiserhöhung ist ein neuer Eintrag ab dem Stichtag, beim alten wird „Gekündigt“ gesetzt.")
                    }
                }

                Section("Notizen") {
                    TextField("optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(navigationTitle)
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

    private var navigationTitle: LocalizedStringKey {
        switch (fee == nil, kind) {
        case (true, .fee): return "Neue Grundgebühr"
        case (false, .fee): return "Grundgebühr bearbeiten"
        case (true, .credit): return "Neue Gutschrift"
        case (false, .credit): return "Gutschrift bearbeiten"
        }
    }

    private var startLabel: LocalizedStringKey {
        if interval == .once && effectiveSpread == .session { return "Ab (nächste Ladung)" }
        return needsEndDate ? "Von" : "Ab"
    }

    private var intervalFooter: String {
        switch interval {
        case .monthly: return String(localized: "Jeden Monat ab dem Starttag, z. B. 03.05.–02.06., 03.06.–02.07. usw.")
        case .yearly: return String(localized: "Jedes Jahr ab dem Starttag.")
        case .once:
            switch effectiveSpread {
            case .session: return String(localized: "Der ganze Betrag zählt bei der nächsten Ladung dieses Anbieters ab dem Datum.")
            case .months: return String(localized: "Verteilt nach kWh auf die Ladungen dieses Anbieters in den Monaten ab dem Datum.")
            case .range: return String(localized: "Einmal für den gewählten Zeitraum.")
            }
        }
    }

    private func save() async {
        guard let parsedAmount else { return }
        isSaving = true
        errorMessage = nil
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let once = interval == .once
        let payload = ProviderFeePayload(
            providerId: providerId,
            amount: kind == .credit ? -abs(parsedAmount) : abs(parsedAmount),
            interval: interval,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: ((hasEndDate && !once) || needsEndDate) ? Calendar.current.startOfDay(for: endDate) : nil,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            singleSession: once && effectiveSpread == .session,
            spreadMonths: once && effectiveSpread == .months ? months : nil
        ).normalized()
        do {
            if let fee {
                _ = try await AppRepository.shared.updateFee(id: fee.id, payload)
            } else {
                _ = try await AppRepository.shared.createFee(payload)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

/// Gebuehr oder Gutschrift - gespeichert wird nur das Vorzeichen des Betrags.
enum FeeKind: String, CaseIterable, Identifiable {
    case fee
    case credit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fee: return String(localized: "Gebühr / Abo")
        case .credit: return String(localized: "Gutschrift (Rabatt, Gutschein)")
        }
    }
}

/// Worauf ein einmaliger Betrag verteilt wird (Server ab 0.56.0).
enum FeeSpread: String, CaseIterable, Identifiable {
    case session
    case months
    case range

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return String(localized: "Eine Ladung")
        case .months: return String(localized: "Monate")
        case .range: return String(localized: "Zeitraum bis Enddatum")
        }
    }
}

#Preview {
    NavigationStack { FeesSettingsView() }
}
