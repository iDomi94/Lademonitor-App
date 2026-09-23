import SwiftUI

/// Reiter "Tools": eine Liste kleiner Rechner. Weitere Tools kommen hier als
/// Zeilen dazu, nicht als weitere Reiter - ab dem sechsten Reiter versteckt
/// iOS alles hinter "Mehr".
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TariffCalculatorView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lohnt sich der Tarif?")
                                Text("Effektiver Preis pro kWh mit Grundgebühr, verglichen mit dem Laden ohne Tarif")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "eurosign.circle")
                        }
                    }
                }
            }
            .navigationTitle("Tools")
        }
    }
}

#Preview {
    ToolsView()
}
