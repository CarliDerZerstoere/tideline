---
date: 2026-05-24
status: immutable evidence record (v3 — full app-wide audit + fact-check)
author: Claude (owner-requested audit after #162 incident)
---

# Tideline whole-app audit — 2026-05-24

## Background and scope expansion

This document is v3. The history of scope expansion:

- **v1 (rejected)**: shallow grep of 10 tasks I personally remembered. Owner: "you only did a search for some strings".
- **v2 (rejected)**: deep read of ~50 tracker tasks. Owner: "Why wouldn't you make a complete one?" — applied to fact-checking, but also pointed at the audit itself.
- **v3 (this doc)**: every tracker COMPLETE claim fact-checked + app-wide investigation across dimensions the tracker doesn't cover (build config, fonts, assets, privacy artifacts, lifecycle, code quality, force-unwraps, error handling, SwiftData migration, App Store readiness).

Owner instruction that shaped this version: *"Also, don't focus only on the features. When I say the whole app, I mean the whole app."*

Methodology: every claim has file:line evidence. Where evidence is thin or unverified, the verdict says so. Fact-checks were run via 8 parallel sub-agents covering every COMPLETE tracker item; their reports are summarised below with the original-claim verdict + the fact-check's refinement (if any).

---

## 🔴 Critical app-wide findings (NOT in tracker)

### 1. Custom font referenced but NOT bundled
- `CormorantGaramond-BoldItalic` is called via `.font(.custom("CormorantGaramond-BoldItalic", ...))` 10+ times: HealthKitExportSheet (multiple), HealthKitImportSheet, TidelineHero, onboarding sheets, doctor PDF.
- No `.ttf`/`.otf` file exists anywhere in the repo (`find . -name "*.ttf" -o -name "*.otf"` returns empty).
- No `UIAppFonts` declaration in project.yml.
- No `Tideline/Resources/Fonts/` directory.
- **Effect**: every `.font(.custom("CormorantGaramond-BoldItalic", ...))` falls through to system font; the `.fontDesign(.serif)` modifier kicks the fallback to system serif (Georgia/New York). All branded headline typography renders in a generic system font. Visual regression vs. design intent.

### 2. App icon set is incomplete (likely App Store rejection)
- `Tideline/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` declares only a single 1024×1024 universal iOS image.
- iOS HIG requires at least 60pt @2x/@3x (= 120, 180 px) for home screen plus several smaller variants for Settings, Spotlight, Notification Center.
- An extra `tideline_app_logo.imageset/` exists outside AppIcon.appiconset, suggesting an incomplete migration.
- **Effect**: home-screen icon may render as a blurred upscale or fall back to a default. App Store metadata upload likely fails.

### 3. PrivacyInfo.xcprivacy is MISSING
- `find . -name "PrivacyInfo.xcprivacy"` returns nothing.
- Required for App Store submissions since spring 2024 (NSPrivacyAccessedAPI, NSPrivacyTracking, NSPrivacyCollectedDataTypes).
- **Effect**: App Store Connect upload will be rejected at validation.

### 4. SwiftData migration plan is MISSING
- Grep for `VersionedSchema|SchemaMigrationPlan|MigrationStage` in Sources/ returns nothing.
- Models (`Cycle`, `DayEntry`, `CycleEvent`) are wired into `ModelContainer` (AppContainer.swift:22) without a migration plan.
- **Effect**: any post-launch field addition/rename/relationship change to a `@Model` class will corrupt existing user installs. The first migration this app needs (almost any post-1.0 feature) will require a retroactive `VersionedSchema` rewrite **and** a one-time on-launch migration. Now is the cheap time to wire it in; after TestFlight, every change pays an integration tax.

### 5. HealthKit & FaceID permission prompts are hard-coded language-mismatched
- `INFOPLIST_KEY_NSHealthShareUsageDescription` and `INFOPLIST_KEY_NSHealthUpdateUsageDescription` are English (project.yml).
- `INFOPLIST_KEY_NSFaceIDUsageDescription` is German.
- No `InfoPlist.strings` file in `de.lproj/` or `en.lproj/`.
- **Effect**: a DE-locale user sees an English HealthKit prompt + a German FaceID prompt. An EN-locale user sees the opposite mismatch on FaceID. Inconsistent, unprofessional, and unfair to the DACH target market.

### 6. Notification subsystem is dead code (already in v2; restated for completeness)
- `NotificationGate.shouldDeliver` and `NotificationService.schedule` exist but have **zero callers in production source code** (verified by FC-agent).
- The CLAUDE.md hard rule "no cycle notifications within 28 days of a logged loss" is vacuously satisfied — no notifications fire at all.
- **User-visible knock-on**: `LateMilestoneCard.swift` (the 10–14-day pregnancy-test card) does NOT gate on the loss-suppression window either. If a user logs `.miscarriageEarly` and the hero subsequently enters `.late` state on day 10+ of the next cycle, the pregnancy-test card displays — verified by FC-8.

### 7. App-Lock fail-open on `.unavailable`
- `AppLockGate.swift:134`: when `LAContext.canEvaluatePolicy` returns false at runtime (user disabled device passcode after enabling Tideline app-lock), the gate sets `isUnlocked = true`.
- Comment acknowledges "settings flow should have prevented this" but this is a real bypass surface.
- **For a privacy-first app (Pillar 1), the safer default is fail-closed** — keep `isUnlocked = false` and surface an "App-Lock unavailable — re-enable device passcode" screen.

---

## 🟠 Code-quality findings (NOT in tracker)

### Force-unwraps with potentially-unsafe operands

Verified by `grep -n "[a-z\\]\\)\\!\\." Tideline/Sources/`:

| File:Line | Expression | Risk |
|---|---|---|
| TideSparkline.swift:155, 166, 196, 207 | `points.first!.y` / `points.last!.y` | Guarded upstream by `guard !cycles.isEmpty` (line 136); `points` mirrors `cycles.count` so safe in practice. ✅ Low. |
| CyclePredictor.swift:362 | `quantileTable[nearest]!` | `nearest` is `tableConfidences.min(...)` which is non-empty (4 entries hardcoded). Safe. ✅ |
| CyclePredictor.swift:375, 376, 384 | `xs.first!`, `xs.last!`, `ys.last!` | Inputs are hardcoded constant tables in `quantileTable`. Safe. ✅ |
| HealthKitService.swift:145 | `Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!` | Theoretically can fail on year-9999 edge dates. Practically unreachable for cycle data. ⚠️ Low. |
| CivilDay.swift:37 | `TimeZone(identifier: "UTC")!` | UTC is guaranteed-present. ✅ |

Net: 10 force-unwraps; **none of them are actually unsafe given the surrounding guards or hardcoded inputs**. Acceptable.

### Privacy/exfiltration check (Pillar 1)

- ✅ Zero `URLSession`, `URLRequest`, `http://`, `https://`, `WebSocket`, `Network.` references in Sources/.
- ✅ Zero `print`, `NSLog`, `debugPrint`, `os_log` references.
- ✅ Zero third-party SDK imports.
- ✅ Strict concurrency enabled: `SWIFT_STRICT_CONCURRENCY: complete`.

The codebase upholds Pillar 1 at the static-source level. (Runtime traffic verification with Charles/Proxyman would be the final proof — not done here.)

### Error swallowing

40 `try?` instances across Sources/. SwiftData `fetch(...)` defaults to `[]` on failure are mostly legitimate, but a focused review pass would surface any that silently mask real errors (e.g. `try? modelContext.save()` swallows write failures — not great for data integrity).

### Dead UI affordance

- `TidelineHomeView.swift:214` contains `onCycleTap: { _ in /* TODO: detail view */ }`. The sparkline supports tap-to-expand but the per-cycle detail view is not implemented. User taps → nothing happens. Silent dead-end.

### Tracker-label drift

- Task #66 title says "5 buttons (Mein Zyklus / Kalender / Loggen / Statistik / Mehr)" but TidelineHomeView.swift:30-33 documents that Statistik was dropped per D1 decision on 2026-05-22. Implementation is 4-button; tracker title is stale.

---

## Tracker COMPLETE claims — fact-checked

Eight parallel fact-checker agents ran. Verdicts:

### FC-1 (predictor math) — **11/11 TRUE**
#9, #94, #95, #96, #97, #99, #100, #102, #108, #114, #158 — all citations match. Minor: #102 cited path was "Views/" but file lives in "Services/" (typo in audit doc, not a code defect).

### FC-2 (services + models) — **substantively TRUE; agent path-resolution errors flagged**

| Claim | Verdict |
|---|---|
| #22 CycleEvent | TRUE — file at Models/CycleEvent.swift, 246 LOC |
| #23 PredictorMode | TRUE (FC-2 agent looked in `Sources/Models/` but file is at `Sources/Services/PredictorMode.swift` — I verified directly: enum at line 5, cases active/paused/retired at 6-8). |
| #24 PredictorService | TRUE |
| #38, #39 ModelContainer + AppContainer | TRUE (FC-2 agent failed to find AppContainer.swift; it's at `Sources/Services/AppContainer.swift`. I verified directly: line 22 registers `for: Cycle.self, DayEntry.self, CycleEvent.self`). |
| #40 CycleStore @ModelActor | PARTIAL — annotation at line 18, `actor` declaration at line 19. Off-by-one. |
| #41 ConformalCalibrator | TRUE (FC-2 said unverifiable; I verified directly — both `ConformalCalibrator.swift` and `ConformalResiduals.swift` exist in `Sources/Services/`). |
| #42 HealthKitService | TRUE — reads + writes confirmed |
| #48 logDay | TRUE — :247-303 |
| #103 startPeriod orphan | TRUE — :206-230 |
| #104 magic numbers dedup | PARTIAL — only 2 internal uses confirmed by FC-agent. Audit said "3+ sites" — slightly overstated. |
| #117 disappearing log | TRUE — civilDay() at :186 + :254 |
| #118 delete bugs | TRUE — wasBleeding captured before mutate at :268; rebuild gate at :301 |

### FC-3 (P0/P1 feature wiring) — **15/15 substantively TRUE; 2 line-number drifts**
#71, #74, #75, #76, #77, #78, #79, #80, #88, #89, #90, #91, #92, #93, #98 all verify.
- #88 cited line :386, actual is :381. Off by 5.
- #92 cited :380/:393, actual :375/:387. Off by ~5.
- Substance fully verified in both cases.

### FC-4 (NEW-* features + tests) — **mostly TRUE; audit vagueness flagged**

| Claim | Verdict |
|---|---|
| #105 sparkline empty state | TRUE |
| #107 test regression suite | TRUE |
| #111 loadAndReplay race | TRUE — local-then-swap at :104-168 |
| #112 test gaps | UNVERIFIED — FC-agent says audit cites LOC, not specific test names. Owner should run test suite. |
| #113 eventBetweenCycles fix | UNVERIFIED — same vagueness; audit says "Search for the new discrimination" without naming the test |
| #115 Fehring CSV trap | PARTIAL — file exists with matching docstring; specific array-subscript guard not line-confirmed |
| #120 Mein Zyklus 3-layer | TRUE |
| #121 recognition templates | TRUE |
| #123 privacy disclosure | TRUE — mounted at MoreSettingsSheet.swift:30 |
| #135 vaccine/illness | TRUE — but audit phrasing was vague. Actual cases: `.mildIllness` (CycleEvent.swift:71), `.vaccination` (line 72). |
| #136 standalone loss | TRUE — but `isPregnancyLoss` at :137-148 covers FIVE cases, not 4 as audit listed (audit missed `.pregnancyLoss` itself, the new NEW-J neutral catchall at line 51). |
| #137 privacy in onboarding | TRUE |

### FC-5 (bug fixes #59-70) — **11/11 TRUE**
Every functional bug fix verified end-to-end.

### FC-6 (docs + research) — **5/5 substantive existing docs TRUE; research-note count refined**
- #15, #17, #18, #20, #30, #32 all EXIST + SUBSTANTIVE.
- Audit's "12 dated research notes" is incorrect: actual count is **15** (7 dated 2026-05-19; additional notes 2026-05-20, 2026-05-21, 2026-05-22, 2026-05-24).
- #18 edge-cases.md is 196 LOC, not "≥200" — still substantive, but exact figure off.

### FC-7 (UI build #49-58) — **6/10 TRUE; 4 ASSERTED-NOT-VERIFIED (visual)**
- #49-#54 (LogDaySheet, CyclePhaseStrip, WaveLayer, TidelineHero, TideSparkline, TidelineHomeView): TRUE.
- #55, #56, #57, #58 (Phase A polish, cream/tab/larger hero, design-handoff quick wins, CyclePhaseStrip visual rewrite): ASSERTED-NOT-VERIFIED. Visual outcomes can't be confirmed from source alone, but all files contain matching code patterns (wave interference math, glass card structures, slider scrubbing).

### FC-8 (late mode + pregnancy test) — **5/6 TRUE; 1 UNVERIFIABLE; 1 CRITICAL KNOCK-ON**
- #72, #73, #81, #82, #84 verify.
- #119 ("Cluster B + #118 implementation") — UNVERIFIABLE; audit cites no specific deliverable. Owner-knowledge required to assess.
- **CRITICAL CROSS-FINDING**: `LateMilestoneCard.swift` does NOT gate on `hasRecentPregnancyLoss`. Combined with the unwired NotificationGate, this means the 10-14-day pregnancy-test card displays for any user whose hero enters `.late` regardless of recent loss logging. Confirms the #122 user-visible impact.

### Fact-checks of FAKE/PARTIAL findings (from v2)

| Claim | Fact-checked |
|---|---|
| #122 + #85 notifications dead code | ✅ TRUE — zero callers found across 5 files |
| #162 resume() same-pattern miss | ✅ TRUE — PredictorService.swift:187 + design doc silent on AgeBand |
| #131 a11y zero-count | ⚠️ PARTIALLY TRUE — 18 files with zero `.accessibilityLabel/Hint/Value` (confirmed by `for f in Views/*; do grep -c ...; done` returning 18). BUT 4 of the 11 named files have OTHER a11y modifiers (`.accessibilityElement`, `.accessibilityHidden`, `.accessibilityAddTraits`). Audit's phrasing "ZERO accessibility annotations" overclaims; the narrow Label/Hint/Value count is correct. |
| #133 contrast | ✅ TRUE — zero contrast/wcag/luminance hits in Tests/ or Sources/ |
| #101 widened-recovery dead code | ✅ TRUE — author-documented |
| #129 EN strings | ⚠️ WORSE THAN AUDIT CLAIMED — 4 of 7 spot-checked inline German literals have NO key in en.lproj: "In Apple Health speichern", "Aus Apple Health importieren", "Entsperren", "Willkommen". EN-locale users see raw German for these. |
| #46 Doctor PDF SHA256 | ✅ TRUE — hash over canonical content, embedded in PDF Keywords metadata, surfaced via shortHex |
| #87 App-Lock | ⚠️ PARTIAL — wiring is correct, but fail-open path at AppLockGate.swift:134 on `.unavailable` warrants Pillar-1 review |

---

## Build / project config

- ✅ project.yml: Swift 6.0, iOS 18.0, strict concurrency complete, development language `de`, CFBundleLocalizations `de en`, HealthKit entitlement present.
- ✅ TidelineTests target is configured with depends-on Tideline; scheme has test action wired.
- ❌ No `Tests/Plans/*.xctestplan` — tests run via default scheme test action only. No test-impact-grouping for CI.
- ❌ No CI configuration in repo (`.github/workflows/`, `xcode-cloud-config.yml`, or similar).

---

## What this audit STILL does NOT cover

1. **Test runtime status.** I read test files and verified they exist; I did not execute `xcodebuild test`. Owner must run the suite before TestFlight. Specific gaps: #112 / #113 / #115 / #119 fact-checks were inconclusive because audit cited LOC instead of test names; running the suite would close those.
2. **Simulator manual smoke test.** None of the user flows were exercised in a running app during this audit.
3. **Localization runtime.** Inline-German `Text` literals depend on implicit LocalizedStringKey lookup. I confirmed 4 of 7 spot-checked sites have no EN key, but did not enumerate all ~25 inline literals.
4. **VoiceOver runtime traversal.** Counted missing annotations; did not run an actual VoiceOver sweep.
5. **WCAG contrast measurement.** Confirmed no contrast test; did not run a Color Contrast Analyzer on the running app.
6. **Network traffic verification.** Static-source clean for Pillar 1; runtime proof (Charles/Proxyman) not done.
7. **App Store metadata.** Screenshots, descriptions, App Store keywords (#134 pending).
8. **Dynamic Type compatibility.** Pending per #132.
9. **Code-reviewer subagent retroactive pass.** Standing directive not retro-applied to past completions.

---

## Consolidated fix list (severity-ranked, owner's call to open)

### 🔴 P0 — must fix before TestFlight

| New tracker | Scope |
|---|---|
| Wire NotificationGate → NotificationService.schedule for late-period + pregnancy-test categories | Bake the 28-day suppression into actual scheduling. Add wiring tests. ~3 h. |
| LateMilestoneCard gate on hasRecentPregnancyLoss | Same loss-suppression check at LateMilestoneCard.swift:24 before dispatching to bucket. ~30 min. |
| Bundle CormorantGaramond font OR remove all `.font(.custom("CormorantGaramond-..."))` calls | Decide: ship a free open-source clone of Cormorant via Google Fonts (Apache 2.0), bundle in Resources/Fonts/, register in project.yml `UIAppFonts`, OR fall back uniformly to `.serif`. ~1 h either way. |
| Complete AppIcon.appiconset | Generate all required iOS icon sizes from the 1024×1024 source. ~30 min using Bakery/Asset Catalog Compiler. |
| Add PrivacyInfo.xcprivacy | Declare NSPrivacyAccessedAPI (UserDefaults, FileTimestamp), NSPrivacyTracking=false, NSPrivacyCollectedDataTypes=empty. ~30 min. |
| Fix #162 resume() | PredictorService.swift:187 — pass ageBand. Update design doc. ~30 min. |
| SwiftData migration plan scaffold | Wrap current models in `SchemaV1` (VersionedSchema), declare `MigrationPlan = .init(...)`, pass into ModelContainer. Even with no migrations yet, this future-proofs the first one. ~1 h. |

### 🟠 P1 — must fix before TestFlight or address as known limitation

| New tracker | Scope |
|---|---|
| AppLockGate fail-open on `.unavailable` (line 134) | Decide policy: fail-closed with re-enable prompt, or document the fail-open as acceptable per the Settings UX contract. ~30 min decision + 15 min code. |
| InfoPlist.strings DE+EN | Move NSHealthShareUsageDescription / NSHealthUpdateUsageDescription / NSFaceIDUsageDescription out of project.yml hardcodes and into per-locale InfoPlist.strings files. ~45 min. |
| #131 finish a11y sweep | Add `.accessibilityLabel` to 11 user-facing zero-Label/Hint/Value views (DoctorPDFSheet, LateMilestoneCard, ResumeAfterPauseSheet, NotificationSettingsSection, PrivacyDisclosureSection, AgeBandSettingsSection, MoreSettingsSheet, AppLockSettingsSection, OnboardingGate, CycleIrregularitySection, PhaseNamingSettingsSection). ~3-4 h. |
| #133 actual contrast measurement | Add `Luminance.contrast(...)` Swift Testing test asserting ratios for hero-image overlays + 6 known surfaces. ~2 h. |
| #129 finish EN extraction | At minimum: add EN keys for "In Apple Health speichern", "Aus Apple Health importieren", "Entsperren", "Willkommen" (bare). Audit all ~25 inline literals against en.lproj. ~2 h. |
| #130 finish locale audit | Set `.locale = .current` on the 7 DoctorPDF DateFormatter instances. ~1 h. |

### 🟡 P2 — polish / hardening

| New tracker | Scope |
|---|---|
| #101 widened-recovery dead-code resolution | Either rewire `isInRecoveryWindow` to actually fire (e.g. "post-softReset for 30 days") or remove the suffix branch + its test. ~1 h. |
| TidelineHomeView.swift:214 sparkline detail view | Implement or remove the TODO. Silent dead-end on tap is bad UX. ~1-3 h depending on scope. |
| Tracker label #66 | Rename "5 buttons" → "4 buttons (post-D1)" for accuracy. 5 min. |
| Test names for #112/#113/#115 | Audit-evidence cited LOC; owner should confirm by name. 15 min audit + 0-2 h fixes. |
| CI / xctestplan | Add basic GitHub Actions or Xcode Cloud config to run tests on push. ~2 h. |
| `try?` audit | Review the 40 sites; convert any that mask real data-integrity errors to explicit `do/catch` with logging-to-OSLog. ~2 h. |

---

## Confidence + provenance

- **High confidence**: all 🔴 critical findings (notification dead code, missing font, incomplete AppIcon, missing PrivacyInfo, missing SwiftData migration, Permission-prompt localization mismatch, App-Lock fail-open, LateMilestoneCard ungated, #162 resume bug). Each verified by direct file inspection.
- **High confidence**: 80%+ of tracker COMPLETE claims, via 8 parallel fact-checker agents.
- **Medium confidence**: a few claims where audit-evidence was LOC-based not test-name-based (#112, #113, #115, #119) — flagged.
- **Self-corrections from FC pass**: FC-2 reported some "FALSE/UNVERIFIABLE" verdicts for #23, #38, #39, #41 — these were FC-agent path-resolution errors (searched wrong subdir); I verified directly that the files exist with the cited content.

---

## What changed v2 → v3

- Added 7 critical app-wide findings outside the tracker (font, icon, privacy file, SwiftData migration, permission-prompt localization, LateMilestoneCard ungated, AppLockGate fail-open).
- Replaced "verified COMPLETE" assertions with fact-check verdicts from 8 sub-agents.
- Refined #129 PARTIAL → "worse than claimed" with 4 specific missing EN keys.
- Refined #131 from "ZERO accessibility annotations" to the narrower true claim about Label/Hint/Value.
- Documented FC-agent errors (path lookups) so the original audit isn't unfairly flagged.
- Added Build/Project config section and CI status.
- Reorganized fix list by severity for actionability.
