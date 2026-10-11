import SwiftUI
import Combine

/// Gemeinsamer Navigationszustand der Reiter - damit ein Abschnitt in einem
/// Reiter (z. B. die Reichweite im Dashboard) direkt in ein Tool springen kann.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    enum Tab: Hashable {
        case dashboard, sessions, map, tools, settings
    }

    @Published var selectedTab: Tab = .dashboard
    /// Pfad des NavigationStack im Reiter Tools.
    @Published var toolsPath: [ToolRoute] = []
    /// Vorgang, dessen Bearbeiten-Formular die Ladevorgangs-Liste oeffnen
    /// soll (Kurzbefehl "Ladevorgang erfassen"). Die Liste leert es wieder.
    @Published var pendingEditSessionID: String?

    private init() {}

    /// Wechselt in den Reiter Tools und oeffnet dort den Reichweitenrechner.
    func openRangeCalculator() {
        toolsPath = [.range]
        selectedTab = .tools
    }

    /// Wechselt in den Reiter Ladevorgaenge und oeffnet dort das Formular.
    func openSessionEditor(id: String) {
        pendingEditSessionID = id
        selectedTab = .sessions
    }
}

/// Die Tools als Ziele des NavigationStack im Reiter Tools.
enum ToolRoute: Hashable {
    case tariff, combustion, battery, range, reimbursement, review
}
