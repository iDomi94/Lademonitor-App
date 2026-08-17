import Foundation
import Network
import Combine

/// Erreichbarkeits-Signal fuer den SyncService: loest einen Sync-Versuch aus, sobald
/// die Verbindung nach einer Offline-Phase wiederkommt (siehe SyncService.init).
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.dominiqueherbrigpersonalteam.Lademonitor.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }
}
