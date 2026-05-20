import SwiftUI

/// Five-segment picker for `FlowLevel`. Horizontal row of tappable chips
/// with droplet icons that scale with intensity.
struct FlowLevelPicker: View {
    @Binding var selection: FlowLevel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FlowLevel.allCases, id: \.self) { level in
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
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == level ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selection == level ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: level))
                .accessibilityAddTraits(selection == level ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func icon(for level: FlowLevel) -> some View {
        switch level {
        case .none:
            Image(systemName: "minus")
                .foregroundStyle(.secondary)
        case .spotting:
            Image(systemName: "drop")
                .foregroundStyle(.pink.opacity(0.6))
        case .light:
            Image(systemName: "drop.fill")
                .foregroundStyle(.pink.opacity(0.7))
        case .medium:
            HStack(spacing: 1) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(.pink.opacity(0.85))
        case .heavy:
            HStack(spacing: 1) {
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
                Image(systemName: "drop.fill")
            }
            .foregroundStyle(.pink)
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
