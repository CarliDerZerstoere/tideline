# Tideline

A privacy-first, gamified menstrual cycle tracking app for iOS. Your data never leaves your phone.

## Pillars

- **On-device only** — no accounts, no servers, no telemetry. Cycle data stays on the phone.
- **Gamified logging** — streaks, daily quests, and progression so logging feels rewarding instead of tedious.
- **On-device AI summaries** — Apple's Foundation Models framework generates natural-language summaries of your own logged patterns. Strictly no medical advice.

## Status

Pre-alpha. Project scaffold only.

## Requirements

- Xcode 26+
- iOS 18.0+ deployment target
- Apple Intelligence-capable device for AI summaries (iPhone 15 Pro / 16+); deterministic fallback otherwise

## Generate the Xcode project

The `.xcodeproj` is not committed. Regenerate it from `project.yml`:

```sh
brew install xcodegen   # one-time
xcodegen generate
open Tideline.xcodeproj
```

## Project layout

```
Tideline/
├── Sources/
│   ├── App/         # App entry point
│   ├── Models/      # SwiftData models (Cycle, DayEntry)
│   ├── Views/       # SwiftUI views
│   └── Services/    # HealthKit, prediction engine, AI summaries
├── Resources/       # Assets, entitlements
└── Tests/           # Unit tests (Swift Testing framework)
```

## Privacy posture

- No analytics SDKs, no crash reporters that upload, no third-party SDKs that phone home
- HealthKit data is read with user permission and processed on-device
- No backend; no account required to use the app

## License

Proprietary. All rights reserved (for now).
