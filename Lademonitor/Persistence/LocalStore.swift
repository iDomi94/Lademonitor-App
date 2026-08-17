import Foundation
import SwiftData

/// Zentraler SwiftData-Stack fuer den Local-Only-Modus (und spaeter den lokalen
/// Puffer im Server-Modus). Ein einzelner ModelContainer/-Context fuer die ganze
/// App, analog zu den bestehenden `.shared`-Singletons (APIClient, SessionManager).
@MainActor
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        let schema = Schema([
            LocalVehicle.self,
            LocalProvider.self,
            LocalChargingLocation.self,
            LocalChargingSession.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Ein kaputter lokaler Store darf die App nicht raten: Ladevorgaenge sind
            // Nutzdaten, die es sonst nirgends gibt (im Local-Only-Modus kein Server-Backup).
            fatalError("SwiftData-Store konnte nicht initialisiert werden: \(error)")
        }
    }
}
