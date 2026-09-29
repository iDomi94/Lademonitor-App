import SwiftUI

@main
struct LademonitorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Beim Verlassen der App den Widget-Stand festhalten - danach
            // hat das Widget keine andere Quelle mehr (siehe WidgetSnapshot).
            if phase == .background, AppSettings.shared.isReadyForDataAccess {
                WidgetSnapshotWriter.refresh()
            }
        }
    }
}
