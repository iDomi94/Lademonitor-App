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
                Text("Die Gebühr wird nach kWh auf die Ladevorgänge des Anbieters im jeweiligen Zeitraum umgelegt und zählt in Gesamtkosten, Preis pro kWh und Kosten pro 100 km mit. Der Preis an der Säule bleibt unverändert.")
            }
        }
        .overlay {
            if fees.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "Keine Grundgebühren",
                    systemImage: "creditcard",
                    description: Text("Zum Beispiel ein Abo mit monatlicher Gebühr, das einen günstigeren kWh-Preis bringt.")
                )
            }
        }
        .navigationTitle("Grundgebühren")
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
        .alert("Grundgebühr löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { fee in
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
                Text("\(fee.amount.formatted(.currency(code: "EUR"))) \(fee.interval.perLabel)")
                    .font(.body.monospacedDigit())
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

    private var periodText: String {
        let start = fee.startDate.formatted(date: .abbreviated, time: .omitted)
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

    @State private var providerId: String
    @State private var amount: String
    @State private var interval: FeeInterval
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
        _amount = State(initialValue: fee.map { String(format: "%.2f", $0.amount) } ?? "")
        _interval = State(initialValue: fee?.interval ?? .monthly)
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

    /// Einmalige Gebuehren brauchen ein Enddatum - sonst waere der Zeitraum,
    /// auf den sie umgelegt wird, ein einziger Tag. Der Server verlangt das
    /// genauso (422).
    private var needsEndDate: Bool { interval == .once }

    private var canSave: Bool {
        guard !providerId.isEmpty, let parsedAmount, parsedAmount >= 0 else { return false }
        if (hasEndDate || needsEndDate) && endDate < startDate { return false }
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
                } footer: {
                    Text(intervalFooter)
                }

                Section {
                    DatePicker(needsEndDate ? LocalizedStringKey("Von") : LocalizedStringKey("Ab"), selection: $startDate, displayedComponents: .date)
                    if !needsEndDate {
                        Toggle("Gekündigt", isOn: $hasEndDate)
                    }
                    if hasEndDate || needsEndDate {
                        DatePicker(needsEndDate ? LocalizedStringKey("Bis") : LocalizedStringKey("Letzter Tag"), selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Zeitraum")
                } footer: {
                    if !needsEndDate {
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
            .navigationTitle(fee == nil ? "Neue Grundgebühr" : "Grundgebühr bearbeiten")
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

    private var intervalFooter: String {
        switch interval {
        case .monthly: return String(localized: "Jeden Monat ab dem Starttag, z. B. 03.05.–02.06., 03.06.–02.07. usw.")
        case .yearly: return String(localized: "Jedes Jahr ab dem Starttag.")
        case .once: return String(localized: "Einmal für den gewählten Zeitraum.")
        }
    }

    private func save() async {
        guard let parsedAmount else { return }
        isSaving = true
        errorMessage = nil
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ProviderFeePayload(
            providerId: providerId,
            amount: parsedAmount,
            interval: interval,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: (hasEndDate || needsEndDate) ? Calendar.current.startOfDay(for: endDate) : nil,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
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

#Preview {
    NavigationStack { FeesSettingsView() }
}
