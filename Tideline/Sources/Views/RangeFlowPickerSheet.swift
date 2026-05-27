import SwiftUI

/// Sheet shown after the user selects a date range in `CalendarSheet`
/// (task #79). Lets them pick a `FlowLevel` and apply it to all days in
/// the range in one batched action. Reuses the same `FlowLevelPicker`
/// the single-day `LogDaySheet` uses so the visual language stays
/// consistent.
struct RangeFlowPickerSheet: View {
    let dayCount: Int
    /// Set by parent on dismiss; nil means user cancelled.
    @Binding var chosenFlow: FlowLevel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Local pre-selection. `.medium` is the most common "I forgot to log
    /// my period" flow level — matches the LogDaySheet's default.
    @State private var flow: FlowLevel = .medium

    var body: some View {
        ZStack {
            PageBackground.color(scheme: colorScheme).ignoresSafeArea()

            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                Text(headline)
                    .font(.system(size: 22, weight: .bold, design: .serif).italic())
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Wähle eine Blutungsstärke für alle \(dayCount) Tage.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                FlowLevelPicker(selection: $flow)
                    .padding(.horizontal, 16)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        chosenFlow = flow
                        dismiss()
                    } label: {
                        Text("Auf \(dayCount) Tage anwenden")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: 0xE87070), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        chosenFlow = nil
                        dismiss()
                    } label: {
                        Text("Abbrechen")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
    }

    private var headline: String {
        dayCount == 1 ? "1 Tag eintragen" : "\(dayCount) Tage eintragen"
    }
}
