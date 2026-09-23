import SwiftUI

/// Welche Anbieter zum automatischen Vergleichspreis des Tarifrechners zaehlen.
///
/// Gespeichert wird lokal (TariffCalculatorSettings), bewusst ohne Sync. Neben
/// jedem Anbieter steht, was dort im letzten Jahr im Schnitt bezahlt wurde -
/// die eigene Wallbox faellt zwischen den oeffentlichen Preisen meist sofort
/// auf.
struct PublicProvidersView: View {
    @State private var providers: [Provider] = []
    @State private var excluded: Set<String> = []
    @State private var paid: [String: TariffCalculator.PaidPrice] = [:]
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(providers) { provider in
                    Toggle(isOn: isPublic(provider.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                            if let price = paid[provider.id] {
                                Text("Ø \(TariffCalculatorView.perKwh(price.pricePerKwh)) bezahlt, \(price.sessionCount) Ladevorgänge")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Keine Ladevorgänge mit Preis im letzten Jahr")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Nur eingeschaltete Anbieter zählen zum automatischen Preis ohne Tarif im Tarifrechner. Schalte private Anbieter wie die eigene Wallbox aus. Neue Anbieter zählen automatisch als öffentlich. Die Auswahl gilt nur auf diesem Gerät.")
            }
        }
        .navigationTitle("Öffentliche Anbieter")
        .task { await load() }
    }

    private func isPublic(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(id) },
            set: { isOn in
                if isOn { excluded.remove(id) } else { excluded.insert(id) }
                TariffCalculatorSettings.setExcluded(excluded)
            }
        )
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            let basis = try await AppRepository.shared.tariffBasis()
            providers = basis.providers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // Nur die IDs vorhandener Anbieter behalten - so faellt beim
            // naechsten Speichern auch eine alte lokale UUID heraus.
            excluded = basis.excludedProviderIds.intersection(providers.map(\.id))
            var byProvider: [String: TariffCalculator.PaidPrice] = [:]
            for provider in providers {
                byProvider[provider.id] = TariffCalculator.paidPrice(sessions: basis.sessions) { $0.providerId == provider.id }
            }
            paid = byProvider
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { PublicProvidersView() }
}
