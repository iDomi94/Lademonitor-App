import AppIntents
import Foundation

/// Oeffnet die App im Bearbeiten-Formular eines Vorgangs. Folgeschritt von
/// "Ladevorgang erfassen", deshalb nicht einzeln in Kurzbefehle sichtbar.
nonisolated struct OpenChargingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ladevorgang öffnen"
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = false

    @Parameter(title: "Ladevorgang")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.openSessionEditor(id: sessionID)
        return .result()
    }
}
