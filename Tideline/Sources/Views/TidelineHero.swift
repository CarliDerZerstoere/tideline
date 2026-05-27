import SwiftUI

/// Atmospheric beach hero. Renders as a vertical multi-stop sky gradient
/// (photorealistic sunset/sunrise per phase), with a sun/moon at horizontal
/// position proportional to the cycle day, the ambient `WaveLayer` sea
/// fading into the page cream at the bottom, and the right-edge "approaching
/// wave" prediction mist.
///
/// See `docs/design/tideline-visual-language.md` § Layer 1.
struct TidelineHero: View {
    let state: HeroState
    let useTideNaming: Bool
    var scrollOffset: CGFloat = 0 // Parallax scroll position passed from home view

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Ken Burns on the hero photo — slow zoom + drift, autoreverse.
    @State private var kenBurnsScale: CGFloat = 1.0
    @State private var kenBurnsOffset: CGSize = .zero

    private let heroHeight: CGFloat = 446
      private func displayFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Hero image stays anchored — only its opacity fades as the user
            // scrolls past, so we never reveal raw cream where the photo used
            // to be (which caused the harsh edge during a drag). Ken Burns
            // gives the still image its sense of life.
            skyBackground
                .scaleEffect(kenBurnsScale, anchor: .center)
                .offset(kenBurnsOffset)
                .opacity(heroOpacity)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                        kenBurnsScale = 1.04
                        kenBurnsOffset = CGSize(width: 6, height: -6)
                    }
                }

            // Top vignette for hero-text legibility + bottom cream fade.
            overlayGradient
                .allowsHitTesting(false)
                .opacity(heroOpacity)

            // Approaching mist on the right horizon. Hidden when the
            // conditional interval is wider than 14 days (`isWide`),
            // because the mist is an interval visualisation and there
            // is no meaningful interval to show — honest uncertainty
            // beats false-precision band.
            if case .active(let model) = state {
                approachingMist(model: model)
                    .opacity(heroOpacity)
            }
            if case .late(let model) = state, !model.isWide {
                approachingMistForLate(model: model)
                    .opacity(heroOpacity)
            }

            // Centered hero text fades a touch faster than the image so the
            // photo reads cleanly as the user starts scrolling.
            centerText
                .opacity(max(0.0, 1.0 + scrollOffset / 220))
        }
        .frame(height: heroHeight)
    }

    /// Opacity used for the hero photo + overlay during scroll. Stays at 1
    /// while pulling down (overscroll), starts to fade once the user scrolls
    /// past ~half the hero height.
    private var heroOpacity: Double {
        max(0.0, min(1.0, 1.0 + Double(scrollOffset) / 320))
    }

    // MARK: - Overlay (vignette + cream fade)

    private var overlayGradient: LinearGradient {
        let cream = PageBackground.color(scheme: colorScheme)
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(0.20), location: 0.0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.48),
                .init(color: cream.opacity(0.53), location: 0.68),
                .init(color: cream.opacity(0.87), location: 0.80),
                .init(color: cream, location: 0.92),
                .init(color: cream, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Sky background & gradient

    private var phaseImageName: String {
        // Late mode keeps the user's last-known phase beach (carried on
        // the model) so the user doesn't see a sudden palette flip the
        // day after expected — that would feel like a state regime
        // change, which is misleading when the model is just uncertain.
        let phase: CyclePhase
        switch state {
        case .empty, .paused, .retired:
            return "beach_sunset_hero"
        case .active(let model):
            phase = model.phase
        case .late(let model):
            phase = model.lastKnownPhase
        }
        switch phase {
        case .menses: return "beach_menses"
        case .follicular: return "beach_follicular"
        case .ovulation: return "beach_ovulation"
        case .lutealEarly, .lutealLate: return "beach_luteal"
        }
    }

    /// Process-wide image cache. Avoids reloading the same beach photo
    /// from disk on every body re-render (which happens on every scroll
    /// tick) — that was a measurable contributor to the home-view lag.
    private static let imageCache = NSCache<NSString, UIImage>()

    private var phaseImage: Image {
        let key = phaseImageName as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return Image(uiImage: cached)
        }
        if let path = Bundle.main.path(forResource: phaseImageName, ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            Self.imageCache.setObject(uiImage, forKey: key)
            return Image(uiImage: uiImage)
        }
        if let uiImage = UIImage(named: phaseImageName) {
            Self.imageCache.setObject(uiImage, forKey: key)
            return Image(uiImage: uiImage)
        }
        return Image(phaseImageName)
    }

    @ViewBuilder
    private var skyBackground: some View {
        ZStack {
            phaseImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: heroHeight)
                .clipped()

            // Blend the phase colors softly over the image
            skyGradient
                .blendMode(.softLight)
                .opacity(0.82)
        }
    }

    @ViewBuilder
    private var skyGradient: some View {
        let stops = skyStops
        LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var skyStops: [Gradient.Stop] {
        switch state {
        case .empty:
            let light: [UInt32] = [0xfacf9a, 0xf2a37d, 0xe87a6d, 0xc25f5e]
            let dark: [UInt32] = [0x180828, 0x3a1848, 0x5a2868, 0x7a4070]
            let hexes = colorScheme == .dark ? dark : light
            let topFraction = 0.82 / Double(hexes.count - 1)
            var s = hexes.enumerated().map { i, hex in
                Gradient.Stop(color: Color(hex: hex), location: Double(i) * topFraction)
            }
            s.append(.init(color: PageBackground.color(scheme: colorScheme), location: 1.0))
            return s
        case .active(let model):
            return PhasePalette.skyGradientStops(for: model.phase, scheme: colorScheme)
        case .late(let model):
            return PhasePalette.skyGradientStops(for: model.lastKnownPhase, scheme: colorScheme)
        case .paused, .retired:
            let neutral = PhasePalette.neutralColor(scheme: colorScheme)
            return [
                .init(color: neutral.opacity(0.55), location: 0),
                .init(color: neutral.opacity(0.85), location: 0.82),
                .init(color: PageBackground.color(scheme: colorScheme), location: 1.0)
            ]
        }
    }

    private var waveTint: Color {
        switch state {
        case .empty:
            return colorScheme == .dark
                ? Color(red: 0.30, green: 0.22, blue: 0.42)
                : Color(red: 0.88, green: 0.45, blue: 0.38)
        case .active(let model):
            return PhasePalette.color(for: model.phase, scheme: colorScheme)
        case .late(let model):
            return PhasePalette.color(for: model.lastKnownPhase, scheme: colorScheme)
        case .paused, .retired:
            return PhasePalette.neutralColor(scheme: colorScheme)
        }
    }

    private var waveAmplitudeScale: CGFloat {
        if case .active(let model) = state, model.phase == .menses { return 1.4 }
        if case .late(let model) = state, model.lastKnownPhase == .menses { return 1.4 }
        return 1.0
    }

    // MARK: - Center text (big upright serif)
    private var centerText: some View {
        VStack(spacing: 8) {
            switch state {
            case .empty:
                VStack(spacing: 8) {
                    Text("Willkommen")
                        .font(displayFont(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Logge deine erste Periode,\num deinen Rhythmus zu lernen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    // Task #81 — privacy reassurance in the empty state.
                    // The first surface a new user sees should reinforce
                    // the on-device-only promise from onboarding.
                    //
                    // Opacity bumped to 0.95 + shadow added (reviewer rec):
                    // the previous `.opacity(0.78)` fell below WCAG AA
                    // contrast (≈1.6–3.6:1 across the empty-state coral
                    // gradient against a ~5:1 minimum for body-size text).
                    Label("Alles bleibt auf deinem Gerät", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(.top, 6)
                }
                .shadow(color: .black.opacity(0.25), radius: 12)

            case .active(let model):
                Text("Tag \(model.todayDay)")
                    .font(displayFont(size: 56, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12)
                
                let phaseName = useTideNaming ? model.phase.tideName : model.phase.clinicalName
                // Capitalize first letter of tide name for main display
                let capitalizedPhaseName = phaseName.prefix(1).uppercased() + phaseName.dropFirst()
                
                Text(capitalizedPhaseName)
                    .font(displayFont(size: 32, weight: .regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.22), radius: 10)
                
                if let interval = model.predictionIntervalText {
                    // Audit Wave-A fix (4.1): use the centralised serif
                    // headline helper so the line stays in the same
                    // typographic family as the lines above (`Tag N` at
                    // 56pt and the phase name at 32pt). The previous
                    // `.font(.system(size: 14))` broke into system sans
                    // mid-stack and made the hero text feel like two
                    // unrelated cards stacked.
                    Text(interval)
                        .tidelineSerifHeadline(size: 18, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 4)
                        .shadow(color: .black.opacity(0.18), radius: 6)
                }

            case .paused(let label):
                Text("Pausiert")
                    .font(displayFont(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
 
            case .retired(let label):
                Text("Beendet")
                    .font(displayFont(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))

            case .late(let model):
                VStack(spacing: 8) {
                    Text("Tag \(model.todayDay)")
                        .font(displayFont(size: 56, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 12)

                    Text("\(model.daysLate) \(model.daysLate == 1 ? "Tag" : "Tage") über deiner Erwartung")
                        .font(displayFont(size: 26, weight: .regular))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.22), radius: 10)

                    if let interval = model.intervalText {
                        // Audit Wave-A fix (4.1): same serif consistency
                        // as the .active branch above. Late-mode intervals
                        // include the wide-late "Keine klare Schätzung"
                        // headline which deserves the same typographic
                        // gravity as the rest of the hero.
                        Text(interval)
                            .tidelineSerifHeadline(size: 18, relativeTo: .subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                            .padding(.top, 4)
                            .shadow(color: .black.opacity(0.18), radius: 6)
                    }
                }
                // VoiceOver reads day-count + "über deiner Erwartung" as
                // one utterance; the emotionally-loaded "you're late by N
                // days" message lands without an awkward pause break.
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 132)            // clears wave area + gives breathing room
        .frame(maxWidth: .infinity)
    }

    // MARK: - Approaching mist (prediction)

    /// Soft warm tint used by the approaching-period mist.
    private var mistColor: Color {
        colorScheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.78)
            : Color(red: 1.0, green: 0.85, blue: 0.55)
    }

    @ViewBuilder
    private func approachingMist(model: ActiveHeroModel) -> some View {
        GeometryReader { proxy in
            let lowerFrac = Double(model.predictedLowerDay) / Double(model.cycleLength)
            let upperFrac = Double(min(model.predictedUpperDay, model.cycleLength)) / Double(model.cycleLength)
            let startX = proxy.size.width * CGFloat(lowerFrac)
            let endX = proxy.size.width * CGFloat(upperFrac)
            LinearGradient(
                colors: [mistColor.opacity(0.0), mistColor.opacity(0.40), mistColor.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(60, endX - startX))
            .blur(radius: 30)
            // Audit Wave-A fix (4.1): position at the sea-horizon line
            // (~60% down the hero) instead of the previous 45% (which
            // floated the mist mid-sky). The design doc specifies "on
            // the right horizon" — the horizon in the rendered hero
            // lands at ~55-65% of height where sky meets sea, not at
            // the vertical midpoint.
            .position(x: (startX + endX) / 2, y: proxy.size.height * 0.60)
            .accessibilityHidden(true)
        }
    }

    /// Late-mode mist. Today is past the cycle's expected length, so we
    /// rescale the strip's visual extent to `todayDay + a small margin`
    /// — the mist then sits at the right edge, anchored to the band of
    /// days the predictor still thinks are plausible. This is only
    /// invoked when `!isWide` (the band has a meaningful width).
    @ViewBuilder
    private func approachingMistForLate(model: LatePeriodHeroModel) -> some View {
        let _: Void = {
            // Late mode is only valid when today is past the cycle's
            // expected length. The state machine in
            // `HeroStateBuilder.deriveHeroState` is the single producer;
            // if it ever emits `.late` with `todayDay <= cycleLength`,
            // this assertion will trap loudly in debug builds rather
            // than silently render a confusing mist mid-strip. (See
            // docs/design/late-mode-implementation.md line 177: "Day 29
            // of 29 = active, not late".)
            assert(model.todayDay > model.cycleLength,
                   "late-mode mist requires todayDay > cycleLength")
        }()
        GeometryReader { proxy in
            let visualLength = max(model.cycleLength, model.todayDay + 3)
            let startFrac = Double(model.todayDay) / Double(visualLength)
            let endFrac = min(1.0, startFrac + 0.15)
            let startX = proxy.size.width * CGFloat(startFrac)
            let endX = proxy.size.width * CGFloat(endFrac)
            LinearGradient(
                colors: [mistColor.opacity(0.0), mistColor.opacity(0.30), mistColor.opacity(0.45)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(40, endX - startX))
            .blur(radius: 30)
            // Audit Wave-A fix (4.1): same horizon correction as the
            // .active-mode mist above. 60% lands on the sea-horizon line.
            .position(x: (startX + endX) / 2, y: proxy.size.height * 0.60)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Hero state

enum HeroState: Equatable {
    case empty
    case active(ActiveHeroModel)
    case late(LatePeriodHeroModel)
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

/// Task #78 — hero state used when `todayDayInCycle > cycleLength`. The
/// user is past the central estimate and the predictor's conditional
/// CI tells us how confident we are about *when* the period will come.
///
/// **Design contract:**
/// - `lastKnownPhase` is the phase the user was in just before the cycle
///   ran past expectation (typically `.lutealLate`). Carried so the hero
///   keeps the user's last beach/palette instead of falling back to a
///   neutral sky — a sudden palette flip on day-after-expected would
///   feel like a regime change, which is misleading. The phase strip
///   itself stays the same; only the centre text / mist semantics shift.
/// - `isWide` is `true` when the 90% conditional CI exceeds 14 days. In
///   that regime the strip's approaching-mist is hidden entirely (it's
///   an interval visualisation and there is no meaningful interval to
///   show) and the centre text falls back to "Keine klare Schätzung".
/// - `intervalText` is the composed text already including any PCOS
///   disclaimer (built by `HeroStateBuilder.predictionIntervalText`),
///   so the view never has to re-derive precedence.
struct LatePeriodHeroModel: Equatable {
    let todayDay: Int
    let cycleLength: Int
    let daysLate: Int
    let intervalText: String?
    let isWide: Bool
    let lastKnownPhase: CyclePhase
}

#Preview("Active — Ovulation") {
    TidelineHero(
        state: .active(ActiveHeroModel(
            todayDay: 14,
            cycleLength: 29,
            phase: .ovulation,
            predictedLowerDay: 24,
            predictedUpperDay: 30,
            predictionIntervalText: "Periode etwa 24. – 30. Mai"
        )),
        useTideNaming: true
    )
}

#Preview("Empty") {
    TidelineHero(state: .empty, useTideNaming: true)
}

#Preview("Late — 1 day (singular form)") {
    TidelineHero(
        state: .late(LatePeriodHeroModel(
            todayDay: 30,
            cycleLength: 29,
            daysLate: 1,
            intervalText: "Periode etwa 26. – 31. Mai",
            isWide: false,
            lastKnownPhase: .lutealLate
        )),
        useTideNaming: true
    )
}

#Preview("Late — 12 days (pregnancy-test window)") {
    TidelineHero(
        state: .late(LatePeriodHeroModel(
            todayDay: 41,
            cycleLength: 29,
            daysLate: 12,
            intervalText: "Keine klare Schätzung",
            isWide: true,
            lastKnownPhase: .lutealLate
        )),
        useTideNaming: true
    )
}
