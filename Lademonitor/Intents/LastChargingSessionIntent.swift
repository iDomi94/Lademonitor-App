import AppIntents
import Foundation

/// "Letzter Ladevorgang": Datum, Ort, kWh, Kosten und SoC, soweit bekannt.
nonisolated struct LastChargingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Letzter Ladevorgang"
    static let description: IntentDescription? = IntentDescription("Nennt Datum, Ort, kWh, Kosten und Ladestand des letzten Ladevorgangs.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let info = try ChargingShortcuts.lastSession() else {
            return .result(dialog: IntentDialog("Noch kein Ladevorgang erfasst."))
        }
        let text = ChargingShortcuts.lastSessionDetails(info)
        if text.details.isEmpty {
            return .result(dialog: IntentDialog(LocalizedStringResource("Letzter Ladevorgang: \(text.head).")))
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("Letzter Ladevorgang: \(text.head) – \(text.details).")))
    }
}
