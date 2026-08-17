import SwiftUI

struct ProvidersSettingsView: View {
    @State private var providers: [Provider] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingAdd = false
    @State private var editing: Provider?
    @State private var pendingDelete: Provider?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(providers) { provider in
                Button {
                    editing = provider
                } label: {
                    ProviderRow(provider: provider)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        pendingDelete = provider
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Anbieter")
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
            AddEditProviderView(provider: nil) { _ in Task { await load() } }
        }
        .sheet(item: $editing) { provider in
            AddEditProviderView(provider: provider) { _ in Task { await load() } }
        }
        .alert("Anbieter löschen?", isPresented: deleteAlertBinding, presenting: pendingDelete) { provider in
            Button("Löschen", role: .destructive) { Task { await delete(provider) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { provider in
            Text("„\(provider.name)“ wird gelöscht.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = "Bitte zuerst die Server-Adresse in den Einstellungen eintragen."
            return
        }
        isLoading = true
        do {
            providers = try await AppRepository.shared.fetchProviders()
            errorMessage = nil
        } catch {
            if providers.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func delete(_ provider: Provider) async {
        do {
            try await AppRepository.shared.deleteProvider(id: provider.id)
            providers.removeAll { $0.id == provider.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProviderRow: View {
    let provider: Provider

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.body)
                let prices = [
                    provider.lastPriceAcPerKwh.map { String(format: "AC %.3f €", $0) },
                    provider.lastPriceDcPerKwh.map { String(format: "DC %.3f €", $0) }
                ].compactMap { $0 }.joined(separator: " · ")
                if !prices.isEmpty {
                    Text(prices)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct AddEditProviderView: View {
    let provider: Provider?
    let onSaved: (Provider) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var lastPriceAcPerKwh: String
    @State private var lastPriceDcPerKwh: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(provider: Provider?, onSaved: @escaping (Provider) -> Void) {
        self.provider = provider
        self.onSaved = onSaved
        _name = State(initialValue: provider?.name ?? "")
        _lastPriceAcPerKwh = State(initialValue: provider?.lastPriceAcPerKwh.map { String(format: "%.4f", $0) } ?? "")
        _lastPriceDcPerKwh = State(initialValue: provider?.lastPriceDcPerKwh.map { String(format: "%.4f", $0) } ?? "")
        _notes = State(initialValue: provider?.notes ?? "")
    }

    private var isEditing: Bool { provider != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Anbieter") {
                    TextField("Name", text: $name)
                }

                Section {
                    HStack {
                        Text("Preis AC/kWh (€)")
                        Spacer()
                        TextField("optional", text: $lastPriceAcPerKwh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Preis DC/kWh (€)")
                        Spacer()
                        TextField("optional", text: $lastPriceDcPerKwh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Preise")
                } footer: {
                    Text("Diese Preise dienen als Vorschlag und werden bei jedem Ladevorgang mit Preis automatisch aktualisiert.")
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
            .navigationTitle(isEditing ? "Anbieter bearbeiten" : "Neuer Anbieter")
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

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = ProviderPayload(
            name: name.trimmingCharacters(in: .whitespaces),
            lastPriceAcPerKwh: Double(lastPriceAcPerKwh.replacingOccurrences(of: ",", with: ".")),
            lastPriceDcPerKwh: Double(lastPriceDcPerKwh.replacingOccurrences(of: ",", with: ".")),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        do {
            let saved: Provider
            if let provider {
                saved = try await AppRepository.shared.updateProvider(id: provider.id, payload)
            } else {
                saved = try await AppRepository.shared.createProvider(payload)
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack { ProvidersSettingsView() }
}
