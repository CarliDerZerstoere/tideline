import SwiftUI

/// Information card shown below the cycle phase strip when the home
/// view is in late mode (`HeroState.late`). The card renders one of
/// five buckets per `LateMilestone.bucket(daysLate:)` — the copy itself
/// lives on `LateMilestoneBucket` so this view stays a pure renderer.
///
/// **Design notes:**
/// - The card matches the `opaqueCard` shape used elsewhere on the home
///   view (rounded 20pt, cream/dark fill, hairline border, soft shadow).
/// - An `info.circle` glyph signals "context, not action" — there is no
///   tap target on this card. Per CLAUDE.md, the app never tells the
///   user to do anything; it shows information and lets them decide.
/// - Returns `EmptyView()` for `daysLate <= 0` so callers can hand any
///   integer without guarding (defensive: `HeroStateBuilder` only emits
///   `.late` with `daysLate >= 1`, but if the contract ever loosens we
///   degrade silently instead of crashing).
struct LateMilestoneCard: View {
    let daysLate: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let bucket = LateMilestone.bucket(daysLate: daysLate) {
            content(for: bucket)
        } else {
            EmptyView()
        }
    }

    private func content(for bucket: LateMilestoneBucket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(bucket.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Text(bucket.body(daysLate: daysLate))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Match opaqueCard styling for visual consistency with the
        // phase strip and sparkline cards above.
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 7, x: 0, y: 2)
        // VoiceOver: read headline + body as one combined utterance so
        // the user doesn't get a pause break between the bucket name
        // and the supporting context.
        .accessibilityElement(children: .combine)
        // A11y sweep (audit fix #131): info card is informational only —
        // declaring `.isHeader` on the bucket name + a hint pointing at
        // the body lets VoiceOver users skim with rotor navigation.
        .accessibilityLabel("\(bucket.headline). \(bucket.body(daysLate: daysLate))")
        .accessibilityAddTraits(.isStaticText)
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.17, blue: 0.18)
            : Color.white.opacity(0.96)
    }
}

#Preview("Slightly late (3 days)") {
    LateMilestoneCard(daysLate: 3)
        .padding()
        .background(Color(red: 0.96, green: 0.93, blue: 0.85))
}

#Preview("Pregnancy-test window (12 days)") {
    LateMilestoneCard(daysLate: 12)
        .padding()
        .background(Color(red: 0.96, green: 0.93, blue: 0.85))
}

#Preview("Long overdue (35 days)") {
    LateMilestoneCard(daysLate: 35)
        .padding()
        .background(Color(red: 0.96, green: 0.93, blue: 0.85))
}
