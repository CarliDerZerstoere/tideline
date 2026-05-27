import SwiftUI

/// Five-emoji mood scale. Optional — the user can leave it nil.
/// Values 1–5 map to `DayEntry.moodRaw`.
struct MoodPicker: View {
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var colorScheme

    private let emojis: [(Int, String, String)] = [
        (1, "😞", "sehr schlecht"),
        (2, "😐", "schlecht"),
        (3, "🙂", "okay"),
        (4, "😊", "gut"),
        (5, "🤩", "großartig")
    ]
    
    private let coral = Color(hex: 0xE87070)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.0) { value, emoji, label in
                let isSelected = selection == value
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                        selection = (selection == value) ? nil : value
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(emoji)
                            .font(.system(size: 28))
                            .scaleEffect(isSelected ? 1.25 : 1.0)
                        
                        Text(label)
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? coral : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? coral.opacity(colorScheme == .dark ? 0.16 : 0.08) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected 
                                    ? coral.opacity(0.8) 
                                    : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: isSelected ? coral.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
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
