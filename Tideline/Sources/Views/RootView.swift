import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date, order: .reverse) private var entries: [DayEntry]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "water.waves")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Tideline")
                    .font(.largeTitle.bold())

                Text("Your cycle, on your phone. Nothing else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(entries.count) entries logged")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Cycle.self, DayEntry.self], inMemory: true)
}
