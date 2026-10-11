import AppIntents
import Foundation

/// "Ladevorgang erfassen": fragt nur kWh und Gesamtpreis ab, speichert sofort
/// und oeffnet danach das Formular dieses Vorgangs zum Pruefen.
///
/// Gespeichert wird auch bei gesperrtem Geraet und per Sprache allein - nur
/// das anschliessende Oeffnen der App verlangt das Entsperren.
/// `nonisolated` wie bei `ShortcutError`: App Intents greift ausserhalb des
/// MainActors auf Titel und Parameter zu; `perform()` laeuft auf ihm.
nonisolated struct LogChargingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ladevorgang erfassen"
    static let description: IntentDescription? = IntentDescription("Erfasst einen Ladevorgang mit kWh und Gesamtpreis und öffnet ihn danach zur Prüfung.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Energie (kWh)", requestValueDialog: IntentDialog("Wie viele kWh?"))
    var energyKwh: Double

    @Parameter(title: "Gesamtpreis (€)", requestValueDialog: IntentDialog("Was hat es gekostet?"))
    var priceTotal: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        let session = try await ChargingShortcuts.logSession(energyKwh: energyKwh, priceTotal: priceTotal)
        let kwh = ChargingShortcuts.kwhText(energyKwh)
        let price = ChargingShortcuts.euroText(priceTotal)
        return .result(
            opensIntent: OpenChargingSessionIntent(sessionID: session.id),
            dialog: IntentDialog(LocalizedStringResource("Gespeichert: \(kwh) kWh, \(price). Bitte im Formular prüfen."))
        )
    }
}
