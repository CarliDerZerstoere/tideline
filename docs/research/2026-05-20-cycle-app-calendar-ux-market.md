# Verified Research: Calendar / History UX in Cycle-Tracking Apps

**Date:** 2026-05-20
**Status:** Write-once, dated immutable. Market analysis + UX gap survey for Tideline's calendar view.
**Methodology:** Market-researcher output, fact-checked against App Store listings, app documentation, and peer-reviewed survey data. Only verified or partially-verified claims are recorded here; unverified or hallucinated claims are explicitly excluded or flagged.

---

## Scope

Block 2 of the Phase 1 roadmap calls for a calendar/history view (~500 LOC SwiftUI). The first sketch — a monthly grid with bleeding days colored and the prediction shaded — was rejected as too generic. This note surveys what major apps actually offer, where users complain, and which UX patterns remain unexploited.

---

## What major apps actually show (verified by App Store + product docs)

**Clue (Berlin).** Monthly grid calendar with phase bands. Free tier shows a "cycle circle" status widget. The Analysis tab and advanced predictions are paywalled in **Clue Plus** ([verified via support docs](https://support.helloclue.com/hc/en-us/articles/15007319214493)). No year view in free tier; no multi-cycle overlay; no visual confidence interval. **Clue Plus paywalls Oura integration and 12-month predictions.**

**Flo.** Standard monthly grid. Centerpiece is AI-generated text "Insights" cards, not calendar sophistication. No multi-cycle visualization, no year view. **Flo MAU is ~70–77 million as of 2024–2026** (corrected from earlier "50M" claim; source: [Business of Apps](https://www.businessofapps.com/data/flo-statistics/)). Subject to **FTC consent order June 2021** (verified: https://www.ftc.gov/news-events/news/press-releases/2021/06/ftc-finalizes-order-flo-health) and **$56M class action settlement 2025** with Google ([Inside Privacy coverage](https://www.insideprivacy.com/health-privacy/flo-health-google-settle-class-action-privacy-lawsuit-for-56-million/)).

**Apple Health Cycle Tracking.** Horizontal scrollable timeline + secondary monthly grid. No history compression, no trend view, no year-at-a-glance. Prediction shown as a flat band, no gradient.

**Natural Cycles (FDA-cleared, CE-marked).** Primary view is a BBT temperature chart. **Has a `Compare Mode` overlaying past cycles** (verified via [Natural Cycles help docs](https://help.naturalcycles.com/hc/en-us/articles/9209631867933)) — the only mainstream app with this feature, and it requires BBT data. Calendar tab is secondary.

**Ovia, Glow, Eve, Period Tracker.** All use standard monthly grids. No year view, no overlay, no confidence visualization.

**Veiltrack.app.** Verified live as a privacy-first on-device competitor with AES encryption and no account ([veiltrack.app](https://veiltrack.app/)). Gestures at on-device visual moves (cervical mucus heatmap, pattern mirror) but execution quality is minimal.

### Structural truth across all of them

The Gregorian monthly grid is universal. **Only Natural Cycles** uses a non-calendar primary view, and **only Natural Cycles** has a multi-cycle comparison mode. Zero apps visualize prediction uncertainty as a gradient or distribution. Zero apps offer a year-at-a-glance heat map.

---

## User-experience evidence (verified survey data)

**PMC9047811 — Period tracker accuracy survey (n=330 complete responses; corrected from earlier "1,237"):**
- **6.7%** of users said their app "always" predicted correctly.
- **54.9%** experienced periods *earlier* than predicted.
- **72.1%** experienced periods *later* than predicted.
- **10.9%** reported making sexual behavior decisions based on inaccurate fertile-window predictions.

Late predictions cause significant pregnancy anxiety per the same survey. The cited paper concludes apps need "transparency about their intended use and capabilities" — which no mainstream app currently delivers visually.

### Recurring complaints (App Store + Reddit, descriptive evidence)

1. **Irregular cycles are invisible.** PCOS, perimenopausal, and postpartum users report apps "silently shift expected dates."
2. **Prediction confidence is opaque.** No app shows users "your last 6 cycles ranged from 24–34 days, so your next period could arrive in this window."
3. **Long-term trends are buried or paywalled.** Free tier of Flo and Clue is effectively stateless beyond a few cycles.

---

## Unexploited UX directions

| Direction | Status | Notes |
|---|---|---|
| **Cycle-as-clock / phase ring as primary view** | Partially exploited (Clue, shallow) | Free design space if used as the *primary* history canvas |
| **Year-at-a-glance heat map (GitHub-style)** | **Unexploited** in cycle apps | Bearable does it for general symptoms |
| **Multi-cycle overlay** | Partially exploited (Natural Cycles only, BBT-based) | Open field for non-BBT calendar overlay |
| **Probability density / gradient prediction** | **Unexploited** | Aligns directly with Tideline's "honest uncertainty" doctrine |
| **Phase narrative** | Heavily exploited (Flo, Clue) + MDR risk | Skip |
| **Body-literacy / teaching mode** | Partially exploited (Spot On) | Market has moved on; weak differentiator |
| **Temporal echo ("this day last cycle…")** | **Unexploited** | Small feature, not a primary view |

---

## The privacy-first competitive moat

On-device-only enables **dense longitudinal correlation across years of fine-grained data**, shown to the user in full, with no sampling, no server costs, and no incentive to paywall. Cloud-backed competitors structurally cannot match this without redesign. The visual design language of "every pixel was computed on your phone" is a copywriting opportunity unavailable to Flo or Clue.

---

## Recommended visualization for Tideline: **Cycle Variance River**

Multi-cycle comparison view, primary history canvas (replaces monthly grid):

- Last 6–12 cycles stacked vertically, each as a horizontal row of day-cells, **all aligned to cycle day 1 (not Gregorian date)** so bleeding lines up across rows.
- Row background colored by phase (menses / follicular / ovulatory / luteal), desaturated palette.
- Current cycle is the top row.
- **The prediction is a fading gradient band** across the last 5–10 cells of the current row — opacity derived from the empirical distribution of the user's historical cycle lengths. If their last 8 cycles ranged 26–31 days, the gradient runs from day 26 to day 31, denser in the middle, fading at the tails.
- Tap a row → expand to day-level detail.
- Tap a column → see logged symptoms for that cycle-day across all visible cycles ("temporal echo" delivered as a structural property).

**Why this design is defensible:**

- "Honest uncertainty over false precision" is expressed *visually*, not textually.
- Categorically different from Clue's circle, Flo's grid-plus-cards, Natural Cycles' BBT chart.
- No diagnostic claims — shows logged data + a statistical distribution. Wellness-category safe under EU MDR.
- Achievable in ~500 LOC of SwiftUI: `LinearGradient` applied to a `HStack` of `Rectangle` cells.

---

## Citation hygiene notes

- Flo MAU was originally cited as 50M; correct value is **~70–77M** per Business of Apps (2024–2026).
- PMC9047811 survey sample was originally cited as n=1,237; correct value is **n=330 complete responses**. The percentage findings (6.7 / 54.9 / 72.1 / 10.9) are correctly reported.
- All app-feature claims above were re-verified against current product documentation or App Store listings.

## Sources

- [Flo statistics — Business of Apps](https://www.businessofapps.com/data/flo-statistics/)
- [Clue 1M paid subscribers announcement](https://www.globenewswire.com/news-release/2025/05/22/3086276/0/en/Clue-Reaches-1-Million-Paid-Subscribers-As-the-Cycle-Tracking-Pioneer-Becomes-Top-Choice-for-Women-25-Years.html)
- [FTC consent order — Flo Health 2021](https://www.ftc.gov/news-events/news/press-releases/2021/06/ftc-finalizes-order-flo-health)
- [Flo–Google $56M class settlement 2025 — Inside Privacy](https://www.insideprivacy.com/health-privacy/flo-health-google-settle-class-action-privacy-lawsuit-for-56-million/)
- [PMC9047811 — Period tracker accuracy survey](https://pmc.ncbi.nlm.nih.gov/articles/PMC9047811/)
- [Natural Cycles Compare Mode — help docs](https://help.naturalcycles.com/hc/en-us/articles/9209631867933)
- [Clue Plus features — support docs](https://support.helloclue.com/hc/en-us/articles/15007319214493)
- [Veiltrack.app](https://veiltrack.app/)
