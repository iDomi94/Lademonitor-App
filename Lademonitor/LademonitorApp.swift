import SwiftUI

@main
struct LademonitorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Beim Verlassen der App den Widget-Stand festhalten - danach
            // hat das Widget keine andere Quelle mehr (siehe WidgetSnapshot).
            if phase == .background, AppSettings.shared.isReadyForDataAccess {
                WidgetSnapshotWriter.refresh()
            }
            // Beim Start und bei jeder Rueckkehr die Mitteilungen der
            // Erinnerungen neu planen - die km-Prognose und "heute" haben sich
            // seit dem letzten Mal womoeglich verschoben.
            if phase == .active {
                ReminderNotificationScheduler.reschedule()
            }
        }
    }
}
