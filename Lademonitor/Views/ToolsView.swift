import SwiftUI

/// Reiter "Tools": eine Liste kleiner Rechner. Weitere Tools kommen hier als
/// Zeilen dazu, nicht als weitere Reiter - ab dem sechsten Reiter versteckt
/// iOS alles hinter "Mehr".
struct ToolsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var navigation = AppNavigation.shared

    var body: some View {
        // Wertbasierte Links ueber einen gemeinsamen Pfad: so kann das
        // Dashboard direkt ein Tool oeffnen (AppNavigation.openRangeCalculator).
        NavigationStack(path: $navigation.toolsPath) {
            List {
                Section {
                    NavigationLink(value: ToolRoute.tariff) {
                        ToolLabel(
                            title: "Lohnt sich der Tarif?",
                            subtitle: "Effektiver Preis pro kWh mit Grundgebühr, verglichen mit dem Laden ohne Tarif",
                            icon: "eurosign.circle"
                        )
                    }
                    NavigationLink(value: ToolRoute.combustion) {
                        ToolLabel(
                            title: "Vergleich mit Verbrenner",
                            subtitle: "Was dieselben Kilometer mit Benzin oder Diesel gekostet hätten, und wie viel CO₂",
                            icon: "fuelpump"
                        )
                    }
                    // Nur im Server-Modus, wie die Reifen in den Einstellungen:
                    // die Auswertung rechnet allein der Server (battery.py).
                    if settings.appMode == .server {
                        NavigationLink(value: ToolRoute.battery) {
                            ToolLabel(
                                title: "Akku und Ladeverluste",
                                subtitle: "Wie viel beim Laden verloren geht und ob der Akku mit der Zeit weniger aufnimmt",
                                icon: "battery.75percent"
                            )
                        }
                    }
                    NavigationLink(value: ToolRoute.range) {
                        ToolLabel(
                            title: "Reichweitenrechner",
                            subtitle: "Wie weit du mit einem Ladestand bei einer bestimmten Außentemperatur kommst",
                            icon: "road.lanes"
                        )
                    }
                    NavigationLink(value: ToolRoute.reimbursement) {
                        ToolLabel(
                            title: "Erstattungsbericht",
                            subtitle: "Heimladungen des Dienstwagens als Nachweis für den Arbeitgeber, als PDF oder CSV",
                            icon: "briefcase"
                        )
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .tariff: TariffCalculatorView()
                case .combustion: CombustionComparisonView()
                case .battery: BatteryHealthView()
                case .range: RangeCalculatorView()
                case .reimbursement: ReimbursementReportView()
                }
            }
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
