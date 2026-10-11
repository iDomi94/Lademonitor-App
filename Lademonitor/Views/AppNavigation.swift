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

    private init() {}

    /// Wechselt in den Reiter Tools und oeffnet dort den Reichweitenrechner.
    func openRangeCalculator() {
        toolsPath = [.range]
        selectedTab = .tools
    }
}

/// Die Tools als Ziele des NavigationStack im Reiter Tools.
enum ToolRoute: Hashable {
    case tariff, combustion, battery, range, reimbursement
}
