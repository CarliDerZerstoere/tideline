import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        NavigationStack {
            TidelineHomeView()
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Cycle.self, DayEntry.self, CycleEvent.self], inMemory: true)
}
