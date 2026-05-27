import SwiftUI

/// Five-segment picker for `FlowLevel`. Horizontal row of tappable chips
/// with droplet icons that scale with intensity.
struct FlowLevelPicker: View {
    @Binding var selection: FlowLevel
    @Environment(\.colorScheme) private var colorScheme
 
    var body: some View {
        HStack(spacing: 8) {
            ForEach(FlowLevel.allCases, id: \.self) { level in
                let isSelected = selection == level
                Button {
                    selection = level
                } label: {
                    VStack(spacing: 4) {
                        icon(for: level)
                            .font(.title3)
                            .frame(height: 24)
                        Text(label(for: level))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color(hex: 0xE87070).opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected 
                                    ? Color(hex: 0xE87070).opacity(0.8) 
                                    : Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.15),
                                lineWidth: 1.0
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: level))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private func icon(for level: FlowLevel) -> some View {
        let coral = Color(hex: 0xE87070)
        switch level {
        case .none:
            Image(systemName: "minus")
                .foregroundStyle(.secondary)
        case .spotting:
            Image(systemName: "drop")
                .foregroundStyle(coral.opacity(0.6))
        case .light:
            Image(systemName: "drop.fill")
                .foregroundStyle(coral.opacity(0.75))
        case .medium:
            HStack(spacing: 1) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(coral.opacity(0.90))
        case .heavy:
            HStack(spacing: 1) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(coral)
        }
    }

    private func label(for level: FlowLevel) -> String {
        switch level {
        case .none: return "keine"
        case .spotting: return "Schmieren"
        case .light: return "leicht"
        case .medium: return "mittel"
        case .heavy: return "stark"
        }
    }

    private func accessibilityLabel(for level: FlowLevel) -> String {
        switch level {
        case .none: return "Keine Blutung"
        case .spotting: return "Schmierblutung"
        case .light: return "Leichter Fluss"
        case .medium: return "Mittlerer Fluss"
        case .heavy: return "Starker Fluss"
        }
    }
}

#Preview {
    @Previewable @State var selection: FlowLevel = .none
    return VStack {
        FlowLevelPicker(selection: $selection)
            .padding()
        Text("Ausgewählt: \(String(describing: selection))")
            .foregroundStyle(.secondary)
    }
}
