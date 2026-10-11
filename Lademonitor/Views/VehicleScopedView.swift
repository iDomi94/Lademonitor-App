import SwiftUI

/// Einstieg aus dem Einstellungs-Hauptmenue in einen Bereich, der an einem
/// Fahrzeug haengt (Kosten, Erinnerungen): mit einem Fahrzeug direkt hinein,
/// mit mehreren zuerst die Auswahl.
struct VehicleScopedView<Destination: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let destination: (Vehicle) -> Destination

    @State private var vehicles: [Vehicle] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Keine Verbindung", systemImage: "wifi.slash")
                } description: {
                    Text(errorMessage)
                }
            } else if vehicles.count == 1, let vehicle = vehicles.first {
                destination(vehicle)
            } else if vehicles.isEmpty {
                ContentUnavailableView {
                    Label("Noch kein Fahrzeug", systemImage: "car")
                } description: {
                    Text("Lege zuerst unter Einstellungen → Fahrzeuge eines an.")
                }
            } else {
                List(vehicles) { vehicle in
                    NavigationLink {
                        destination(vehicle)
                    } label: {
                        Text(vehicle.name)
                    }
                }
                .navigationTitle(title)
            }
        }
        .task {
            do {
                // Aktive Fahrzeuge zuerst, sonst in der gewohnten Reihenfolge.
                let all = try await AppRepository.shared.fetchVehicles()
                vehicles = all.filter(\.isActive) + all.filter { !$0.isActive }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            loaded = true
        }
    }
}
