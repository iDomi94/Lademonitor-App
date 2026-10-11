import AppIntents
import Foundation

/// "Was ist fällig?": bald faellige und ueberfaellige Erinnerungen.
nonisolated struct DueRemindersIntent: AppIntent {
    static let title: LocalizedStringResource = "Was ist fällig?"
    static let description: IntentDescription? = IntentDescription("Nennt bald fällige und überfällige Erinnerungen.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = try ChargingShortcuts.dueReminders()
        guard !items.isEmpty else {
            return .result(dialog: IntentDialog("Nichts fällig."))
        }
        let list = ChargingShortcuts.remindersText(items)
        return .result(dialog: IntentDialog(LocalizedStringResource("Fällig: \(list).")))
    }
}
