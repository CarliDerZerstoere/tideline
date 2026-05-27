# App-Lock — Design Doc

**Status:** Planned / ready to implement
**Created:** 2026-05-21
**Trigger:** Competitor analysis found Tideline has no app-level passcode/biometric
lock. Inconsistent with the privacy-first positioning — Flo, Clue, Ovia all ship
this. Direct credibility gap.

---

## Goal

Optional, opt-in biometric or device-passcode lock on the entire app. When
enabled, the home view and all sheets are gated behind Face ID / Touch ID /
device passcode. Honors `LocalAuthentication.LAPolicy.deviceOwnerAuthentication`
so any device with biometrics OR a passcode can use it; devices with neither
gracefully fall back (toggle disabled with an explanatory hint).

**Hard rule:** opt-in only. Default OFF. A user who doesn't want the feature
sees and notices nothing. Privacy-by-architecture is unaffected by whether the
lock is on or off — this is an *additional* layer the user can choose to add.

---

## Non-goals

- Tideline-specific PIN as an alternative to the device passcode. That would
  be its own crypto story (where do we store the PIN hash, how do we handle
  reset, etc.) — the device passcode is already authenticated by the OS, we
  shouldn't reinvent it.
- Per-section locks ("notes are extra-locked"). Single binary lock for now.
- Decoy mode / "fake home view" for coerced unlocks. Too risky to ship without
  legal review and out of scope for v1.
- Cloud-sync encryption (separate, future concern).

---

## Architecture

```
TidelineApp.body
  └── AppLockGate                   ← new container, lives at the root
       │
       ├── @AppStorage("appLockEnabled") Bool = false
       ├── @AppStorage("appLockTimeoutSeconds") Int = 0    // 0 = immediate
       ├── @State isUnlocked: Bool
       ├── @State lastBackgroundedAt: Date?
       ├── @Environment(\.scenePhase)
       │
       ├── if !appLockEnabled           → RootView (passthrough)
       ├── else if !isUnlocked          → AppLockView (auth UI)
       └── else                          → RootView
                                          + PrivacyOverlay during .inactive
```

**`AppLockService`** is a `@MainActor final class` wrapping
`LAContext`. Methods:

```swift
func capability() -> AppLockCapability
   // .biometric(.faceID|.touchID) | .passcodeOnly | .none

func authenticate(reason: String) async -> AuthResult
   // .success | .userCancelled | .failed | .unavailable(Error)
```

Uses `.deviceOwnerAuthentication` (not `.deviceOwnerAuthenticationWithBiometrics`)
so the system handles biometric-then-passcode fallback internally — we don't
have to.

**`AppLockView`** is a static lock-screen: cream background, Tideline wordmark
centered, "Entsperren"-button with the capability-appropriate icon (face/finger/lock).
Tapping it triggers `authenticate(reason:)`. No tab bar, no peek of content.

**`PrivacyOverlay`** is a SwiftUI view shown over the root content whenever
`scenePhase != .active && appLockEnabled`. Identical to the lock screen
visually — wordmark on cream — so the app-switcher preview never reveals
cycle data.

---

## UX flow

### Activating the lock

1. User opens "Mehr" tab → settings sheet (currently a placeholder; this
   feature replaces the placeholder for the lock section).
2. Toggles "App-Sperre" ON.
3. **Immediately** triggers `authenticate(reason:)` with copy "App-Sperre
   aktivieren" — this both confirms the device can auth and is a safety check
   to prevent lockouts.
4. On success: toggle stays ON, timeout picker appears inline below.
5. On cancel/failure: toggle reverts to OFF. No state change, no lockout
   risk.

### Deactivating the lock

1. Toggle "App-Sperre" OFF.
2. Triggers `authenticate(reason:)` with copy "App-Sperre deaktivieren".
3. On success: toggle goes OFF.
4. On cancel/failure: toggle reverts to ON.

This prevents someone with brief physical access to an unlocked phone from
silently disabling the lock.

### App launch (cold start)

- If `appLockEnabled`: immediately show `AppLockView` and fire `authenticate()`.
- User dismisses Face ID sheet → stays on lock screen with "Erneut versuchen".
- No skip, no bypass.

### Background → Foreground (re-lock)

- `scenePhase` transitions `.background` → `.active`:
  - If `appLockEnabled` and `now - lastBackgroundedAt > timeoutSeconds` → re-lock.
  - Otherwise → stay unlocked.
- On `.active` → `.background` transition: stamp `lastBackgroundedAt = .now`.

### Inactive scene (system sheets, app switcher)

- `scenePhase == .inactive` while `appLockEnabled`: show `PrivacyOverlay`
  over the content.
- Re-revealed when `.active` returns.

### Capability edge cases

| Device state | Toggle behavior |
|---|---|
| Face ID enrolled, device passcode set | Toggle enabled. `capability() == .biometric(.faceID)`. |
| Touch ID enrolled, device passcode set | Toggle enabled. `capability() == .biometric(.touchID)`. |
| Biometrics not enrolled but device passcode set | Toggle enabled. `capability() == .passcodeOnly`. |
| Device has no passcode at all | Toggle disabled with hint: "Stelle einen Code oder Face ID in den iOS-Einstellungen ein, um die App-Sperre zu aktivieren." |
| Biometrics enrolled but locked out (too many failed attempts) | iOS shows its own passcode-fallback sheet. We pass through. |

---

## Default timeout

**Decision: 0 seconds (immediate).** Picker default is "Sofort sperren beim
Verlassen". User can change to 1 min / 5 min / 15 min if they find immediate
locking too aggressive.

Rationale: privacy-first positioning argues for the strict default. Users who
want comfort over strictness will find and change the setting; users who never
think about it get maximum protection.

The picker:
- Sofort (0 s)        ← default
- Nach 1 Minute        (60 s)
- Nach 5 Minuten       (300 s)
- Nach 15 Minuten      (900 s)

---

## Files

**New:**

| Path | Responsibility |
|---|---|
| `Tideline/Sources/Services/AppLockService.swift` | `LAContext` wrapper, capability check, authenticate(reason:). `@MainActor`. |
| `Tideline/Sources/Views/AppLockView.swift` | Static lock screen with wordmark + Entsperren-button. |
| `Tideline/Sources/Views/AppLockGate.swift` | Container that gates RootView on the lock state, handles scenePhase. |
| `Tideline/Sources/Views/AppLockSettingsSection.swift` | Toggle + timeout picker + capability-aware enable/disable. |
| `Tideline/Sources/Views/PrivacyOverlay.swift` | Cream + wordmark overlay shown during `.inactive`. |
| `Tideline/Sources/Views/MoreSettingsSheet.swift` | Replaces the "Mehr" `PlaceholderSheet` with a real settings sheet. First section: `AppLockSettingsSection`. Future sections (naming toggle, export, etc.) plug in here. |
| `Tideline/Tests/AppLockServiceTests.swift` | LAContext mock via protocol; tests capability mapping + error mapping. |

**Modified:**

| Path | Change |
|---|---|
| `Tideline/Sources/App/TidelineApp.swift` | Wrap `RootView` in `AppLockGate`. |
| `Tideline/Sources/Views/TidelineHomeView.swift` | "Mehr" button presents `MoreSettingsSheet` instead of `PlaceholderSheet`. Removes one of the three placeholder usages. |
| `project.yml` | Add `INFOPLIST_KEY_NSFaceIDUsageDescription: "Tideline kann mit Face ID gesperrt werden, damit deine Zyklusdaten privat bleiben."` — required by iOS, app crashes on first Face ID call without it. |

---

## Test strategy

`AppLockServiceTests` (Swift Testing framework):
- `capability()` correctly maps to each `.biometricType` + `passcode-only` combinations using a mocked LAContext
- `authenticate()` maps each `LAError.Code` to the right `AuthResult`
- Concurrent calls to `authenticate()` are safe (`@MainActor` serialization)
- `canEvaluatePolicy(_:error:)` returning false yields `.unavailable(Error)`

Manual QA (cannot be fully automated without UI tests):
- iPhone Simulator with Face ID enrolled: enable lock → kill app → reopen → Face ID sheet appears → cancel → stays on lock screen → "Erneut versuchen" works.
- Simulator without Face ID: capability check shows `.passcodeOnly`, toggle still works.
- Simulator with no passcode set: toggle disabled with correct hint.
- Background → foreground while locked: stays locked.
- Background timeout exceeded: re-locks on foreground.
- Inactive (e.g. swipe down for share sheet): privacy overlay covers content.

---

## Effort estimate

- `AppLockService` + tests: 2 h
- `AppLockView` static: 0.5 h
- `AppLockGate` + scenePhase wiring + privacy overlay: 2 h
- `AppLockSettingsSection` + activation/deactivation flow + capability handling: 2 h
- `MoreSettingsSheet` scaffold (just enough to host the section): 0.5 h
- `INFOPLIST_KEY_NSFaceIDUsageDescription` + xcodegen + build verification: 0.25 h
- Manual QA on simulator + real device: 1.5 h

**Total: ~1 dev-day.**

---

## Implementation order

1. `AppLockService.swift` + `AppLockServiceTests.swift` → tests green.
2. `AppLockView.swift` (static UI, no auth wiring yet).
3. `AppLockGate.swift` — connects Service ↔ View, owns lock state.
4. `PrivacyOverlay.swift` + `scenePhase` integration in the gate.
5. Wrap `RootView` in the gate inside `TidelineApp.swift`.
6. `AppLockSettingsSection.swift` — toggle + timeout picker + activation auth.
7. `MoreSettingsSheet.swift` + wire from "Mehr"-tab.
8. `INFOPLIST_KEY_NSFaceIDUsageDescription` in `project.yml`. Run `xcodegen generate`.
9. Build, manual QA pass on simulator. Then on real device.

---

## Open questions before build

None — defaults and edge cases are decided above. Greenlight to implement.
