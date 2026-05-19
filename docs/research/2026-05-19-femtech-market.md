# Research Note — FemTech Cycle-Tracking Market Analysis

**Date:** 2026-05-19
**Researcher:** market-researcher + research-analyst sub-agents (synthesized)
**Fact-checked:** Partial (subset of claims; full fact-check pending)
**Drove decisions in:** Project go/no-go; positioning ("privacy + on-device AI + gamification" wedge)

---

## Question driving this research

Is there market demand for a new cycle tracking app, and what is the defensible positioning?

---

## Key findings

### Market sizing (directional figures from market research firms)

- Global femtech market: $40–60B (2024) → projected $200B+ by 2034 at ~15-17% CAGR
- European femtech: ~€2.4B (2024) → ~€9.7B by 2033
- Germany alone: ~€1.3B (2023) → ~€3.7B by 2030
- Period tracker software is the largest revenue segment (~58% of European femtech)
- 50M+ active period tracker users globally (conservative estimate)

### Competitor landscape

| App | MAU / Downloads | Pricing | Privacy posture | Key weakness |
|---|---|---|---|---|
| Flo | 75M MAU; 420M downloads | Free / $39.99/yr | Anonymous Mode (cloud-anonymized); FTC settlement history | Cloud-dependent AI; no gamification |
| Clue | ~12-15M MAU; 100M+ downloads | Free / ~$20-40/yr | Strong (Berlin/GDPR) | No AI insights of note |
| Natural Cycles | ~3-4M users | $99/yr | Medical-grade, FDA-cleared | Requires BBT thermometer; high price |
| Stardust | Spiked post-Roe 2022 | Free / $24.99/yr | Claimed local-first; once caught sharing phone numbers | Astrology theming alienates many |
| Apple Health Cycle | 1B+ iOS devices | Free | Excellent (on-device by default) | No engagement features; no AI; bundled only |
| Glow / Eve by Glow | ~5M | Free / $60-70/yr | Poor | US-only AI; ad-heavy |
| Ovia | ~3M | Free (employer-sponsored) | Moderate (employer data risk) | B2B conflict; US-focused |
| Drip (open-source) | small | $2.99 one-time | Excellent (zero server) | Bare-bones UX, no insights |
| Euki (non-profit) | small | Free | Excellent (duress PIN, no account) | Information-focused, weak prediction |

### Validated user pain points

1. **Privacy concerns** — Flo $56M settlement (Oct 2025) for sharing data with Google, Meta. Privacy International audit: 61% of cycle apps shared data with Facebook (2019). Post-Roe migrations.
2. **Logging fatigue** — Academic studies (Frontiers 2023, Oxford 2025) confirm users find logging tedious and unrewarding. Apps demand extensive input, deliver vague output.
3. **Black-box predictions** — Users want to understand *why* the app says what it says.
4. **Aggressive paywalls** — Flo, Glow particularly criticized.
5. **Clinical / cold UX** — Especially around fertility windows and pregnancy/loss handling.

### Competitive whitespace

The top-right quadrant — **high privacy + high engagement + on-device AI** — is empty. Privacy-first apps (Drip, Euki, Apple Health) are bare-bones. Engaging apps (Flo, Glow) have terrible privacy. No app combines all three.

### Gamification analog evidence

Health apps with streaks/milestones see 21–40% retention improvements (Forrester 2024; Statista-cited gamification meta-research). MyFitnessPal, Duolingo, Apple Fitness rings prove the pattern cross-category. **No major cycle app implements Duolingo-style mechanics.**

⚠ **Caveat: this finding led to "streaks for cycle logging" originally — later invalidated by `design/disrupted-cycles.md` Principle 3 (streaks shame illness, loss, recovery). Gamification needs a redesign.**

---

## Decisions made from this research

1. **Go (conditional)** on building Tideline
2. **Beachhead:** privacy-aware women 22-32 in DACH (Germany primary), currently using Flo and dissatisfied
3. **Wedge:** privacy + on-device AI + (re-thought) gamification
4. **Positioning:** "Your cycle, on your phone. Nothing else."
5. **MVP scope:** iOS only, German + English first, no backend, no accounts

---

## Verification status

Market sizing figures are from market-research firms (GlobeNewswire, Precedence, Fortune, Grand View) — treat as directional, not precise. Competitor MAU/download numbers are from company disclosures and BusinessOfApps; mostly verified, some estimates. Pain points are well-validated in peer-reviewed academic literature (Frontiers 2023, Oxford 2025). Privacy scandal facts (Flo FTC, Privacy International) are verified through primary sources.
