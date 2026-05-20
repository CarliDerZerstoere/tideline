import SwiftUI

/// Five-emoji mood scale. Optional — the user can leave it nil.
/// Values 1–5 map to `DayEntry.moodRaw`.
struct MoodPicker: View {
    @Binding var selection: Int?

    private let emojis: [(Int, String, String)] = [
        (1, "😞", "sehr schlecht"),
        (2, "😐", "schlecht"),
        (3, "🙂", "okay"),
        (4, "😊", "gut"),
        (5, "🤩", "großartig")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.0) { value, emoji, label in
                let isSelected = selection == value
                Button {
                    selection = (selection == value) ? nil : value
                } label: {
                    Text(emoji)
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    @Previewable @State var mood: Int? = 3
    return VStack {
        MoodPicker(selection: $mood)
            .padding()
        Text("Mood: \(mood.map(String.init) ?? "—")")
            .foregroundStyle(.secondary)
    }
}
