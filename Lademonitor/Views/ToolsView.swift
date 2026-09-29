import SwiftUI

/// Reiter "Tools": eine Liste kleiner Rechner. Weitere Tools kommen hier als
/// Zeilen dazu, nicht als weitere Reiter - ab dem sechsten Reiter versteckt
/// iOS alles hinter "Mehr".
struct ToolsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TariffCalculatorView()
                    } label: {
                        ToolLabel(
                            title: "Lohnt sich der Tarif?",
                            subtitle: "Effektiver Preis pro kWh mit Grundgebühr, verglichen mit dem Laden ohne Tarif",
                            icon: "eurosign.circle"
                        )
                    }
                    NavigationLink {
                        CombustionComparisonView()
                    } label: {
                        ToolLabel(
                            title: "Vergleich mit Verbrenner",
                            subtitle: "Was dieselben Kilometer mit Benzin oder Diesel gekostet hätten, und wie viel CO₂",
                            icon: "fuelpump"
                        )
                    }
                    // Nur im Server-Modus, wie die Reifen in den Einstellungen:
                    // die Auswertung rechnet allein der Server (battery.py).
                    if settings.appMode == .server {
                        NavigationLink {
                            BatteryHealthView()
                        } label: {
                            ToolLabel(
                                title: "Akku und Ladeverluste",
                                subtitle: "Wie viel beim Laden verloren geht und ob der Akku mit der Zeit weniger aufnimmt",
                                icon: "battery.75percent"
                            )
                        }
                    }
                }
            }
            .navigationTitle("Tools")
        }
    }
}

private struct ToolLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

#Preview {
    ToolsView()
}
