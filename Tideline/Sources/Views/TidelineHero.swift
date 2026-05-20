import SwiftUI

/// Atmospheric beach hero. Renders as a vertical gradient sky (phase-colored)
/// with a sun/moon at horizontal position proportional to the cycle day, and
/// the `WaveLayer` ambient sea at the bottom. The right-edge "approaching
/// wave" is the conformal-prediction interval rendered as atmospheric mist.
///
/// See `docs/design/tideline-visual-language.md` § Layer 1.
struct TidelineHero: View {
    /// Current cycle state. nil = empty database (0 cycles logged yet).
    let state: HeroState
    let useTideNaming: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let heroHeight: CGFloat = 320

    var body: some View {
        ZStack(alignment: .bottom) {
            skyGradient

            // Sun/moon (or sunrise dot for empty state) — at horizontal
            // position proportional to cycle progress.
            celestialBody

            // Approaching mist on the right horizon (only active mode).
            if case .active(let model) = state {
                approachingMist(model: model)
            }

            // Ambient sea at the bottom.
            WaveLayer(tint: waveTint, amplitudeScale: waveAmplitudeScale)
                .frame(height: 72)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 0
                    )
                )

            // Center text.
            VStack(spacing: 4) {
                centerText
            }
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Sky gradient

    @ViewBuilder
    private var skyGradient: some View {
        let colors = skyColors
        LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var skyColors: [Color] {
        switch state {
        case .empty:
            // Sunrise palette for the empty state.
            let dawn = Color(red: 0.98, green: 0.78, blue: 0.62)
            let warm = Color(red: 0.95, green: 0.60, blue: 0.50)
            return colorScheme == .dark
                ? [Color(red: 0.18, green: 0.14, blue: 0.30), Color(red: 0.40, green: 0.22, blue: 0.32)]
                : [dawn, warm]
        case .active(let model):
            let phaseColor = PhasePalette.color(for: model.phase, scheme: colorScheme)
            return [phaseColor.opacity(0.45), phaseColor.opacity(0.85)]
        case .paused, .retired:
            let neutral = PhasePalette.neutralColor(scheme: colorScheme)
            return [neutral.opacity(0.55), neutral.opacity(0.85)]
        }
    }

    private var waveTint: Color {
        switch state {
        case .empty:
            return colorScheme == .dark ? Color(red: 0.30, green: 0.22, blue: 0.42) : Color(red: 0.88, green: 0.45, blue: 0.38)
        case .active(let model):
            return PhasePalette.color(for: model.phase, scheme: colorScheme)
        case .paused, .retired:
            return PhasePalette.neutralColor(scheme: colorScheme)
        }
    }

    private var waveAmplitudeScale: CGFloat {
        if case .active(let model) = state, model.phase == .menses {
            return 1.4    // rougher sea during menses
        }
        return 1.0
    }

    // MARK: - Celestial body

    @ViewBuilder
    private var celestialBody: some View {
        GeometryReader { proxy in
            let xPos = celestialXPosition(width: proxy.size.width)
            let yPos = celestialYPosition(height: proxy.size.height)
            ZStack {
                Circle()
                    .fill(celestialColor)
                    .frame(width: 44, height: 44)
                    .blur(radius: 8)
                    .opacity(0.6)
                Circle()
                    .fill(celestialColor)
                    .frame(width: 32, height: 32)
            }
            .position(x: xPos, y: yPos)
            .accessibilityHidden(true)
        }
    }

    private var celestialColor: Color {
        if colorScheme == .dark { return Color(red: 0.92, green: 0.92, blue: 0.78) }  // moon
        switch state {
        case .empty: return Color(red: 1.0, green: 0.85, blue: 0.55)
        case .active(let model):
            return model.phase == .ovulation
                ? Color(red: 1.0, green: 0.92, blue: 0.55)
                : Color(red: 1.0, green: 0.85, blue: 0.55)
        case .paused, .retired: return Color(white: 0.85)
        }
    }

    /// X position: left for day 1, right for predicted period day.
    private func celestialXPosition(width: CGFloat) -> CGFloat {
        switch state {
        case .empty: return width * 0.25
        case .active(let model):
            let frac = max(0.05, min(0.92, Double(model.todayDay) / Double(model.cycleLength)))
            return width * CGFloat(frac)
        case .paused, .retired: return width * 0.5
        }
    }

    /// Y position: arcs from horizon to peak at ovulation, back to horizon.
    private func celestialYPosition(height: CGFloat) -> CGFloat {
        let belowMiddle = height * 0.55
        switch state {
        case .empty: return belowMiddle * 0.85  // dawn — low on horizon
        case .active(let model):
            // Arc: y = -sin(π · frac) shifted into screen coords.
            let frac = Double(model.todayDay) / Double(model.cycleLength)
            let arc = sin(.pi * frac)            // 0 at endpoints, 1 at midday/ovulation
            return belowMiddle - (belowMiddle * 0.5) * CGFloat(arc)
        case .paused, .retired: return belowMiddle * 0.7
        }
    }

    // MARK: - Approaching mist (prediction)

    @ViewBuilder
    private func approachingMist(model: ActiveHeroModel) -> some View {
        // The mist begins at the predicted lower-bound day and fades out by
        // the upper-bound day. Width is proportional to the conformal interval.
        GeometryReader { proxy in
            let cycleLength = max(1, model.cycleLength)
            let lowerFrac = Double(model.predictedLowerDay) / Double(cycleLength)
            let upperFrac = Double(min(model.predictedUpperDay, cycleLength)) / Double(cycleLength)
            let startX = proxy.size.width * CGFloat(lowerFrac)
            let endX = proxy.size.width * CGFloat(upperFrac)
            LinearGradient(
                colors: [
                    celestialColor.opacity(0.0),
                    celestialColor.opacity(0.4),
                    celestialColor.opacity(0.55)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(40, endX - startX))
            .blur(radius: 16)
            .position(x: (startX + endX) / 2, y: proxy.size.height * 0.45)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Center text

    @ViewBuilder
    private var centerText: some View {
        switch state {
        case .empty:
            VStack(spacing: 4) {
                Text("Willkommen")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Logge deine erste Periode,")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("damit wir deinen Rhythmus lernen.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(radius: 4)
            .multilineTextAlignment(.center)

        case .active(let model):
            VStack(spacing: 4) {
                Text("Tag \(model.todayDay)")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
                Text(useTideNaming ? model.phase.tideName : model.phase.clinicalName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.95))
                if let intervalText = model.predictionIntervalText {
                    Text(intervalText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .shadow(radius: 4)

        case .paused(let label):
            VStack(spacing: 4) {
                Text("Pausiert")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(radius: 4)

        case .retired(let label):
            VStack(spacing: 4) {
                Text("Beendet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(radius: 4)
        }
    }
}

// MARK: - Hero state

enum HeroState: Equatable {
    case empty
    case active(ActiveHeroModel)
    case paused(reasonLabel: String)
    case retired(reasonLabel: String)
}

struct ActiveHeroModel: Equatable {
    let todayDay: Int
    let cycleLength: Int
    let phase: CyclePhase
    let predictedLowerDay: Int
    let predictedUpperDay: Int
    let predictionIntervalText: String?
}

#Preview("Active") {
    TidelineHero(
        state: .active(ActiveHeroModel(
            todayDay: 14,
            cycleLength: 29,
            phase: .ovulation,
            predictedLowerDay: 24,
            predictedUpperDay: 32,
            predictionIntervalText: "Periode zwischen 24. und 30. Mai erwartet"
        )),
        useTideNaming: true
    )
    .padding()
}

#Preview("Empty") {
    TidelineHero(state: .empty, useTideNaming: true)
        .padding()
}

#Preview("Paused") {
    TidelineHero(state: .paused(reasonLabel: "Stillzeit"), useTideNaming: true)
        .padding()
}
