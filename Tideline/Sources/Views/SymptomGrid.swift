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

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SymptomCategory.allCases, id: \.self) { symptom in
                let isSelected = selected.contains(symptom.rawValue)
                Button {
                    if isSelected {
                        selected.remove(symptom.rawValue)
                    } else {
                        selected.insert(symptom.rawValue)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symptom.systemImage)
                            .font(.body)
                            .foregroundStyle(isSelected ? .white : .secondary)
                        Text(symptom.label)
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symptom.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = ["cramps", "fatigue"]
    return SymptomGrid(selected: $selected)
        .padding()
}
