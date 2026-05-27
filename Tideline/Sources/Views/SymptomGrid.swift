import SwiftUI

/// The eight symptom categories Tideline offers. Derived from the DRSP
/// (Endicott, Nee & Harrison 2006, *Arch Womens Ment Health* 9:41–49) —
/// the only peer-reviewed validated PMS/PMDD instrument. The full DRSP
/// has 24 items; we surface the eight most commonly logged in cycle apps
/// as quick-toggle chips, with the free-text `note` field on the day
/// editor serving as a safety valve for everything else.
public enum SymptomCategory: String, CaseIterable, Sendable {
    case cramps
    case breastTenderness
    case bloating
    case headache
    case fatigue
    case moodSwings
    case cravings
    case sleepDisturbance

    var label: String {
        switch self {
        case .cramps: return "Krämpfe"
        case .breastTenderness: return "Brustspannen"
        case .bloating: return "Blähungen"
        case .headache: return "Kopfschmerz"
        case .fatigue: return "Müdigkeit"
        case .moodSwings: return "Stimmung"
        case .cravings: return "Heißhunger"
        case .sleepDisturbance: return "Schlafstörung"
        }
    }

    var systemImage: String {
        switch self {
        case .cramps: return "bolt"
        case .breastTenderness: return "circle.dashed"
        case .bloating: return "wave.3.right.circle"
        case .headache: return "brain.head.profile"
        case .fatigue: return "battery.25"
        case .moodSwings: return "cloud.rain"
        case .cravings: return "fork.knife"
        case .sleepDisturbance: return "moon.zzz"
        }
    }
}

/// Grid of symptom toggle-chips. Tap to add/remove.
/// Stored as `[String]` (rawValues) so it lines up with `DayEntry.symptoms`.
struct SymptomGrid: View {
    @Binding var selected: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)
    ]
    
    private let coral = Color(hex: 0xE87070)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SymptomCategory.allCases, id: \.self) { symptom in
                let isSelected = selected.contains(symptom.rawValue)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isSelected {
                            selected.remove(symptom.rawValue)
                        } else {
                            selected.insert(symptom.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symptom.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isSelected ? .white : coral.opacity(0.9))
                        Text(symptom.label)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                isSelected 
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [coral, Color(hex: 0xF28E8E)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected 
                                ? Color.white.opacity(0.15) 
                                : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(
                        color: isSelected ? coral.opacity(0.25) : Color.clear,
                        radius: 8, x: 0, y: 3
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symptom.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = ["cramps", "fatigue"]
    return SymptomGrid(selected: $selected)
        .padding()
}
