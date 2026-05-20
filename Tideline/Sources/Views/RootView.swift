import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        NavigationStack {
            TidelineHomeView()
                .navigationTitle("Tideline")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Cycle.self, DayEntry.self, CycleEvent.self], inMemory: true)
}
