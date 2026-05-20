# Tideline Visual Language

**Date:** 2026-05-20
**Status:** Approved direction. Replaces the earlier "Cycle Variance River" concept from `differentiators.md` § 8.
**Methodology:** Concept emerged from chat iteration on 2026-05-20 after user feedback that a data-grid view (Variance River) felt too dense and didn't honor the "Tideline" name. Visual research from `2026-05-20-cycle-app-calendar-ux-market.md` (fact-checked) feeds the rationale. Phase nomenclature aligns with EU MDR wellness category (descriptive, never diagnostic).

---

## Premise

Tideline literally means "Gezeitenlinie" — the line where tide meets shore. Our home view should *inhabit* that metaphor, not ignore it. The cycle has natural ebb and flow; the prediction has natural uncertainty; the visualization should make both feel like nature, not like a spreadsheet.

**The aesthetic target**: Wim Wenders sunset, not Lisa Frank. Apple Weather, not Cocomelon. Calm. Minimalist. Suggestion, not maximalism. Soft gradients, abstract waves, subtle motion at roughly the pace of breath.

---

## Four-layer architecture

The home view is a single scrollable canvas with four vertically stacked layers. Each layer answers a distinct question; together they cover every user need without redundancy.

### Layer 1 — Hero (≈40 % of screen)

Full-bleed atmospheric beach scene that *feels* the cycle phase the user is in.

- **Sky gradient** colored by phase (see palette below).
- **Sun or moon** at horizontal position proportional to current cycle day (day 1 at left horizon, predicted period at right horizon).
- **Horizon line** at a height that subtly tracks phase progression (higher at ovulation, lower at menses).
- **Wave animation** at the bottom edge: ~1 wave per 4 seconds, breath-paced. Wave amplitude scales with logged flow intensity when in menses, otherwise stays calm.
- **Approaching wave on the right horizon**: the prediction visualized as a soft, blurred lighter band — the conformal-prediction gradient rendered as atmospheric mist, not a line.
- **Center text** (3 lines, large then small):
  - "Tag 14"
  - "Ovulationsfenster"
  - "Periode zwischen 24. – 30. Mai erwartet"

**Answers**: "Wie fühlt sich mein Zyklus gerade an?" + "Welcher Tag, welche Phase, wann kommt die Periode?"

### Layer 2 — Phase-Skala (≈30 % of screen)

The data anchor. A horizontal scale that makes phase boundaries and bleeding days **explicit and glanceable**.

Top-to-bottom structure:

1. **Day-number row**: 1, 3, 5, 7, … as tiny markers.
2. **Bleeding-day overlay**: small filled droplet icons on the actual logged bleeding days. These take visual priority over phase coloring — a bleeding day is always rendered as a bleeding day.
3. **Phase bands**: a horizontal colored band split into 4–5 phases. **Transitions between phases are soft gradients, not hard lines.** Biology is fuzzy and we refuse to fake precision the model doesn't have.
4. **Today pin (↓)**: a clear vertical marker at the current cycle day, taller than the strip.

Three short sentences directly below the strip:
- **Bold/large**: "Heute: Tag 14 — Ovulationsfenster"
- Plain: "Lutealphase beginnt voraussichtlich übermorgen."
- Plain: "Letzte Blutungstage: 7. – 11. Mai."

**Answers**: "Wo genau bin ich?" + "Wann wechselt die Phase?" + "Wann waren die Blutungstage?"

### Layer 3 — Gezeitentabelle (≈20 %, expandable)

Compact sinusoidal sparkline showing the last 6 cycles as a tide curve. Each peak/trough is a cycle. Forward portion = prediction with fuzzy edge.

Default state: compressed under the Phase-Skala. Tap (or pull-up gesture) to expand into a fuller multi-cycle comparison view.

**Answers**: "Wie waren meine letzten Zyklen verglichen mit diesem?"

### Layer 4 — Aktionen (≈10 %)

Three discrete affordances:
- **"+" FAB**: opens `LogDaySheet`.
- **Five mood emojis** still in a row, no prompt, no label. Tap saves silently.
- **Lebensereignis-Button**: opens the Disruption Event sheet (Block 3, planned).

**Answers**: "Was kann ich jetzt tun?"

---

## Phase nomenclature

| Cycle phase | German label in UI | Color anchor |
|---|---|---|
| Menses (days 1–5±) | "Menses" or "Periode" | deep coral / warm peach / gold (sunrise palette) |
| Follicular (day 6 to ovulation−3) | "Follikulär" or "aufsteigende Flut" | pale turquoise / sky blue / soft sand (morning beach) |
| Ovulation window (ovulation ±2 days) | "Ovulationsfenster" or "Hochwasser" | bright gold / midday warmth |
| Luteal early (ovulation+3 to ~day 22) | "Luteal" or "fallende Flut" | amber / dusty rose (afternoon) |
| Luteal late (~day 23 to next menses) | "Späte Lutealphase" or "Dämmerung" | dusky purple / sunset-into-twilight |

User-facing language defaults to **tide-metaphor** ("aufsteigende Flut", "Hochwasser", "Dämmerung") with a settings toggle to clinical ("Follikulär", "Ovulation", "Luteal") for users who prefer it. Both stay wellness-safe per MDCG 2019-11 — phase naming alone is descriptive, not diagnostic.

---

## Phase boundary computation

Phase boundaries are computed, not observed. They are:

- **Menses end**: the last consecutive bleeding day per `DayEntry.flow >= .light`. If the user has not logged the end, fall back to the population median of ~5 days (Mumford et al. 2020 pooled cohort, PubMed 32104920 — NOT AWHS 2023, which only reports cycle length).
- **Ovulation day**: predicted cycle length − 14 days. The "subtract 14" rule is the clinical folk simplification of the canonical Lenton (1984) finding. Bull et al. 2019 (n=124,648, npj Digital Medicine) reports empirical mean luteal = **12.4 days** (not 14), with mean follicular = 16.9 days, and within-woman follicular variance significantly greater than luteal (1-year variances 11.2 vs 4.3). So the direction of "follicular dominates cycle-length variance" is verified; the 14-day constant is a heuristic, not a measured truth, and the boundary gradient transition is wide enough (~24h fade) to absorb the ~1.5-day discrepancy.
- **Ovulation window**: ovulation day ±2 days.
- **Luteal start**: ovulation day +3.
- **Luteal end**: predicted next-period day.

All boundaries rendered with **soft gradient transitions** (~24-hour fade on each side). No crisp lines.

---

## Honest uncertainty as visual property

The conformal-prediction interval (`ConformalCalibrator.shared`, 90th-percentile residual = 4.571 days on Fehring) becomes the **mist on the right horizon** in the hero, and the **width of the gradient fade** at the predicted period boundary in the Phase-Skala. When the predictor is in its recovery window (after a soft reset), the mist is wider — automatically, no special code path. When the user has 12+ cycles of consistent history, the mist narrows. The visualization is mathematically tied to the model's actual confidence.

This is why we rejected "single predicted day with sun icon" as a pattern: that would be false precision, in direct violation of CLAUDE.md Principle 3.

---

## What we explicitly do not do

- **No phase prescription**: never "you should eat X in your luteal phase" or "you may be tired in 3 days." MDCG 2019-11 Rev.1 (June 2025) does not explicitly classify forward physiological-state prediction as MDSW, but Rule 11's intended-purpose framing covers prediction/prognosis. We treat forward symptom prediction as MDR risk by analogy and avoid it.
- **No fertility window with contraceptive framing**: showing the ovulation window is descriptive; calling it "fertile" or "use for contraception" triggers EU MDR Class IIb. We show the window as a phase, never as fertility advice.
- **No lunar phase claims**: lunar synchrony in modern populations is weakened — Helfrich-Förster et al. 2025 (Sci Adv 11(39), eadw4096, n=176) reports decreased post-2010 synchrony attributable to LED/screen light exposure, with residual January synchrony explained by gravitational coupling, not luminance. The moon appears at night in the beach scene as part of the day/night rhythm, never as a cycle predictor.
- **No streaks, badges, or gamified phase transitions** (CLAUDE.md Hard Rule).
- **No literal palm trees, no cartoon suns with faces, no Lisa Frank**.

---

## Implementation order

Build in this order so each step is shippable on its own:

1. **`CyclePhaseStrip.swift`** (~200 LOC) — the Phase-Skala. The data anchor. Build first because it's the load-bearing data layer; if this fails, the hero is just vibes.
2. **`TidelineHeroView.swift`** (~300 LOC) — the atmospheric hero. Phase color system, sun/moon positioning, wave animation (`TimelineView(.animation(minimumInterval: 0.5))` — economy, not 60 FPS).
3. **`TideSparkline.swift`** (~150 LOC) — collapsed sparkline showing last 6 cycles.
4. **`ExpandedTideView.swift`** (~150 LOC) — the tap-to-expand history detail.
5. **`TidelineHomeView.swift`** (~100 LOC) — composition root replacing the current `RootView` body, stacking all four layers in a ScrollView.

Estimated total: ~900 LOC + ~200 LOC tests. About 30 % more than the original Variance River estimate, in exchange for an aesthetically defensible brand-aligned home.

---

## Dark mode

Strand bei Tag and Strand bei Nacht are both first-class. Each phase has a paired night-side palette:

- Menses: deep ember red against navy
- Follicular: phosphorescent turquoise on indigo
- Ovulation: moonlit gold on cobalt
- Luteal early: aurora amber on deep purple
- Luteal late: twilight violet on near-black

The sun becomes a moon. The mist on the right horizon becomes silver instead of warm-white. Same data, different palette.

---

## Open questions

1. **Phase naming language toggle**: tide metaphor by default, clinical as a settings option — or the reverse? User research with German-speaking beta testers would help.
2. **Wave animation in low-power mode**: pause animation when iOS reports low-power mode is active. Static hero in that case.
3. **Accessibility**: how do we surface the same phase information to a user using VoiceOver, who cannot see the gradient mist? VoiceOver labels will need explicit "Tag 14 von ca. 28, Ovulationsfenster" descriptions.
4. **Designer pass**: this doc specifies the structure but not the *exact* hex codes or curve shapes. A short visual-design block to finalize palette and motion timing would help before extensive coding.
