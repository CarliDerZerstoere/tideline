# Late-Mode Implementation — Design Doc

**Status:** Planned / ready to implement
**Bundles:** Task #72 (HeroState.late + conditionalInterval wiring), #73 (pregnancy-test milestone card), and Task #78 ("no clear estimate" surface at CI > 14 days)
**Created:** 2026-05-21
**Authoritative spec:** `docs/design/late-and-missed-periods.md`
**Trigger:** UX-researcher Szenario #5 found the home view shows "Tag 35 / Lutealphase" stoically when a user is 7 days overdue. Backend math (`conditionalInterval`) is correct and untested in UI. This block wires it through.

---

## Goal

When the user's cycle has run longer than the predicted length, the home view
switches to a "late mode" that:

1. **Tells her honestly** that she's past the expected period start, without
   alarm or diagnosis.
2. **Replaces the false-precise date range** with a widened conditional
   credible interval that reflects the genuine uncertainty.
3. **Surfaces a quiet pregnancy-test population-context line** at 10–14 days
   late — never personalized advice.
4. **Switches to a "no clear estimate"** surface when the interval becomes
   too wide to be meaningful (CI > 14 days) — instead of showing a useless
   30-day range.

---

## Non-goals

- No diagnostic suggestions ("you might be pregnant", "you might have PCOS",
  "you might be perimenopausal"). These violate EU MDR wellness boundary —
  hard rule in CLAUDE.md.
- No push notifications — those land in Task #85 (notification scaffolding).
  This block is in-app UI only.
- No retroactive "I had my period 3 days ago"-prompt. That's a logging flow,
  not a late-mode display.
- No automatic pregnancy mode switch. Even if the user tests positive, the
  app does not detect that — she logs the event manually.

---

## EU MDR + clinical compliance

The pregnancy-test mention is the regulatory hairline. The wording is
intentionally framed as **population behavior**, not personalized advice:

✅ "Viele Personen machen um diese Zeit einen Schwangerschaftstest."
✅ "Information, nicht Empfehlung."
❌ "Du solltest einen Test machen."
❌ "Das könnte auf eine Schwangerschaft hindeuten."

The doc `late-and-missed-periods.md` § "Pregnancy test suggestion — the
regulatory hairline" is the source of truth on this. Any future copy
revision must pass that section.

---

## Architecture

### 1. New HeroState case

```swift
enum HeroState: Equatable {
    case empty
    case active(ActiveHeroModel)
    case late(LatePeriodHeroModel)   // ← NEW
    case paused(reasonLabel: String)
    case retired(reasonLabel: String)
}

struct LatePeriodHeroModel: Equatable {
    let todayDay: Int                // current cycle day, e.g. 35
    let cycleLength: Int             // expected, e.g. 29
    let daysLate: Int                // todayDay - cycleLength, e.g. 6
    let conditionalIntervalText: String?   // "Nächste Periode etwa 28. – 5. Juni"
    let isWide: Bool                 // CI width > 14 days → "no clear estimate"
}
```

### 2. Detection in refresh()

In `TidelineHomeView.refresh()`, after computing `todayDayInCycle`:

```swift
if todayDayInCycle > currentCycleBoundaries.cycleLength {
    // Late mode — call conditionalInterval, not nextCalibratedPrediction
    let conditional = await store.conditionalIntervalForLatePeriod(
        daysSinceLastPeriod: Double(todayDayInCycle - 1),
        confidence: 0.90
    )
    let (text, isWide) = formatConditional(conditional)
    heroState = .late(LatePeriodHeroModel(
        todayDay: todayDayInCycle,
        cycleLength: currentCycleBoundaries.cycleLength,
        daysLate: todayDayInCycle - currentCycleBoundaries.cycleLength,
        conditionalIntervalText: text,
        isWide: isWide
    ))
} else {
    // Normal active path (existing logic)
}
```

`isWide` flag: true when `conditional.upperBound - conditional.lowerBound > 14`.
This is the criterion from `mixture-predictor.md` open question #2 — when the
band is so wide that a date range is misleading, switch to the neutral
"no clear estimate" copy.

### 3. Hero rendering (TidelineHero.swift)

A new `case .late(let model)` branch in `centerText`:

```
Tag 35                          ← big serif (same size as active)
6 Tage über deiner Erwartung    ← medium, replaces phase name
[conditional interval OR        ← small footnote
 "Zu früh für eine genaue Schätzung"]
```

**Visual changes vs `.active`:**
- Phase name suppressed entirely (would say "Lutealphase" which is misleading)
- Approaching-mist on the right horizon: keep, but its position now reflects
  the wider conditional interval — naturally widens visually
- Hero background: same beach photo as the user's last known phase, no
  switch to a "late" palette (would feel alarming)

### 4. LateMilestoneCard

A new card view inserted in `TidelineHomeView`'s scroll content, between
`CyclePhaseStrip` and `TideSparkline`. Only renders when the hero state is
`.late`. Content depends on `daysLate`:

| daysLate | Title | Body |
|---|---|---|
| 1–4 | "Etwas später als erwartet" | "Deine Periode liegt {N} Tage über der erwarteten Zeit. Bei den meisten Personen schwankt ein Zyklus um ±5 Tage. Beobachte ruhig weiter." |
| 5–9 | "Spürbar später" | "{N} Tage über der Erwartung. Stress, Schlafmangel, Reise oder Krankheit können einen Zyklus verschieben. Du kannst ein Ereignis loggen, falls dir eines davon einfällt." |
| 10–14 | "Information zum Zeitpunkt" | "Tag {N} über der Erwartung. Viele Personen machen um diese Zeit einen Schwangerschaftstest — als Orientierung, nicht als Empfehlung." |
| 15–29 | "Weiterhin später als erwartet" | "Tag {N} über der Erwartung. Wenn du dir Sorgen machst, ist eine ärztliche Einschätzung der nächste Schritt — die App diagnostiziert nicht." |
| 30+ | "Lange überfällig" | "Tag {N} über der Erwartung. Bei dieser Verzögerung ist eine ärztliche Einschätzung sinnvoll. Tideline bleibt hier — du kannst die Vorhersage zurücksetzen, wenn dein Rhythmus sich neu sortiert." |

Card visual style: solid card identical to existing `opaqueCard`, with a
small `info.circle` icon next to the title. No red, no urgency colors. The
copy carries the gravity, not the chrome.

---

## Files

### New

| Path | Responsibility |
|---|---|
| `Tideline/Sources/Views/LateMilestoneCard.swift` | The milestone card. Pure function of `daysLate`. |

### Modified

| Path | Change |
|---|---|
| `Tideline/Sources/Views/TidelineHero.swift` | Add `HeroState.late(LatePeriodHeroModel)` + struct; new `case .late` branch in `centerText`; preview entries. |
| `Tideline/Sources/Views/TidelineHomeView.swift` | `refresh()` late-mode detection + `conditionalIntervalForLatePeriod` call + new card insertion in scroll content. |
| `Tideline/Sources/Services/CycleStore.swift` | Already has `conditionalIntervalForLatePeriod(daysSinceLastPeriod:confidence:)` — no change needed. Verify. |
| `Tideline/Tests/TidelineHomeViewTests.swift` (new or extend) | Test `refresh()` correctly routes to `.late` when day > cycleLength, and that `LateMilestoneCard` picks the right bucket for each `daysLate` value. |

---

## Edge cases & hard rules

| Case | Behavior |
|---|---|
| User is on Day 30 of a predicted 29-day cycle | `daysLate = 1` → first bucket card. Subtle, no alarm. |
| User is on Day 60 of a predicted 29-day cycle | `daysLate = 31` → 30+ bucket. Doctor-referral copy, no diagnosis. |
| User in `.paused` mode (e.g. breastfeeding) — no expected end date | `.paused` takes priority over `.late`. Never enter `.late` while paused. |
| User in `.retired` mode | Same — never enter `.late`. |
| User logs new period today while we're showing `.late` | `currentCycleStart` shifts to today, `todayDayInCycle = 1`, hero returns to `.active`. The card disappears. No manual reset needed. |
| 4 weeks post-loss event (CycleEvent of category C) | Per CLAUDE.md hard rule, no notifications. But the in-app UI: late mode would still show — verify with research before shipping. May need to suppress LateMilestoneCard entirely in this window. **Open question.** |
| Conditional interval is `nil` (no historical data) | Hide the interval line, show only "Tag {N} über der Erwartung." |
| `daysLate == 0` (exactly on predicted day) | Stay in `.active`, not `.late`. Day 29 of a 29-day cycle is "the day", not "late". |

---

## Test strategy

`TidelineHomeViewTests` (or new `LateModeTests.swift`):
- `refresh()` produces `.late` when `todayDayInCycle == cycleLength + 1`.
- `refresh()` stays `.active` when `todayDayInCycle <= cycleLength`.
- `refresh()` stays `.paused` if the predictor mode is paused, even past cycleLength.
- `LatePeriodHeroModel.daysLate` is computed correctly.
- `isWide` flag flips at the 14-day CI-width threshold.

`LateMilestoneCardTests`:
- daysLate=1 → first bucket
- daysLate=4 → first bucket boundary
- daysLate=5 → second bucket
- daysLate=10 → third (pregnancy-test) bucket
- daysLate=15 → fourth bucket
- daysLate=30 → fifth bucket
- daysLate=29 → fourth bucket boundary (so 30 lands cleanly in the next)

---

## Implementation order

1. Add `HeroState.late` + `LatePeriodHeroModel` to `TidelineHero.swift`. Existing tests should still compile (Equatable derivation handles it).
2. Hero `centerText` gets the `.late` branch. Preview entries.
3. Verify `CycleStore.conditionalIntervalForLatePeriod` is reachable from `TidelineHomeView.refresh()`. Add if missing — but the existing code already shows it exists.
4. `LateMilestoneCard.swift` with the five-bucket switch. Static, pure function of `daysLate`.
5. `TidelineHomeView.refresh()` gets the late-mode detection branch. Hero state routing changes.
6. Insert `LateMilestoneCard` into the scroll content, conditional on `heroState` being `.late`.
7. Tests + manual QA on simulator (set system clock or hand-log a backdated period to simulate "overdue today").

---

## Effort estimate

- `HeroState.late` + struct: 0.25 h
- Hero `centerText.late` branch + previews: 0.5 h
- `refresh()` late detection + wiring: 0.5 h
- `LateMilestoneCard` + bucket copy: 1 h
- Tests: 0.75 h
- Manual QA pass (log backdated period to trigger late mode): 0.5 h

**Total: ~3.5 h** — half a dev-day. Backend is already done; this is pure
UI wiring of well-tested math into a well-spec'd UX surface.

---

## Open questions before build

1. **Post-loss suppression window.** Should the LateMilestoneCard be hidden
   for 4 weeks after a logged Category C event (miscarriage, abortion,
   birth)? CLAUDE.md hard rule says no *notifications* in that window —
   does it extend to in-app reminders too? Lean yes (the spirit of the
   rule), but worth a one-line check with the user before shipping the
   card.

2. **Day 30+ doctor referral copy.** Current draft says "eine ärztliche
   Einschätzung ist sinnvoll" — verify with user that this stays on the
   wellness side of MDR (it's a referral to the medical system, not a
   diagnosis from the app, so should be safe).

Both can be settled when implementing — they're copy decisions, not
architectural.
