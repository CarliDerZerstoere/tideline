import SwiftUI
import SwiftData

@main
struct TidelineApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Cycle.self, DayEntry.self])
    }
}
