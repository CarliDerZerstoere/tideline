# Partner-Sharing — Design Note

**Status:** Proposal / not implemented
**Created:** 2026-05-21
**Trigger:** Competitor analysis (Flo for Partners, Ovia) flagged partner-sharing as
a feature competitors offer. Initial reaction was "SKIP — breaks the no-account
architecture pillar." That reaction was wrong.

---

## Core insight

Partner-sharing does **not** require us to operate a backend. **CloudKit's
`CKShare` API** lets one user share a subset of their CloudKit Private Database
records with another iCloud user, end-to-end via Apple's infrastructure.

- Tideline does not run a server.
- Both parties' data stays in their own iCloud, under their own Apple ID.
- Apple is the GDPR Article 28 processor; we disclose this in the privacy
  statement and link to Apple's iCloud security overview.
- The share is encrypted in transit and at rest (CloudKit standard).
- Either party can revoke at any time → the participant loses access instantly.
- No Tideline-account, no telemetry, no Tideline-operated infrastructure.

This is compatible with all four product pillars:
- ✅ On-device (the data still originates and is owned on the user's device)
- ✅ No medical advice (sharing surfaces show data, not interpretation)
- ✅ Honest uncertainty (the shared prediction carries the same CI the owner sees)
- ✅ No streaks (irrelevant here)

CLAUDE.md already lists "SwiftData local + optional iCloud private DB sync" as
the supported persistence model. Partner-sharing is the natural extension of
that.

---

## Architecture sketch

```
Owner device                                  Participant device
─────────────                                 ──────────────────
SwiftData (local)                             SwiftData (local)
   ↓ opt-in sync                                            ↑
CloudKit Private DB    ← CKShare-record →    CloudKit Shared Zone
(under Owner Apple ID)                       (read-only, scoped subset)
                       Apple = processor
```

- Owner activates "Partner-Ansicht teilen" in settings.
- System sheet (`UICloudSharingController` or its SwiftUI equivalent) drives
  invitation via iMessage / mail / link.
- Participant installs Tideline, accepts the invite → sees a read-only
  "Partner-View" of the shared zone.
- Revocation: Owner can revoke participants individually from the same sheet,
  or delete the share to revoke everyone.

---

## Open design questions

These are deliberately left undecided until the feature is scoped for build.

### Q1. What does the participant see?

Three plausible levels of disclosure, listed from most-conservative to most-permissive:

1. **Phase-only (recommended default):** current cycle day, current phase,
   next-period prediction interval. Nothing else.
2. **Phase + bleeding indicator:** above plus "actively menstruating today (Y/N)."
3. **Full read-only:** phase, bleeding, symptoms, mood, notes, history.

Strong recommendation for Level 1 as default with Level 2 as opt-in. Level 3
is a trust-boundary risk and probably overkill — what does the partner *do*
with symptom history that the owner couldn't text them?

### Q2. Bidirectional or read-only?

"Partner can also log on the owner's behalf" sounds nice but opens conflict
resolution (whose entry wins?), accountability ("who logged this?"), and
trust-boundary fallout if the relationship ends with stale entries baked in.

Recommendation: **read-only.** Owner is the only writer.

### Q3. Number of concurrent participants?

CloudKit supports many. For Tideline's social model: probably one at a time,
swappable. Multiple participants compound the "after a breakup" cleanup
problem.

### Q4. Storage cost?

Cycle data is kilobytes per year. Comfortably fits in the free iCloud tier.
No expected blocker.

### Q5. What happens during the iCloud sync prerequisite?

Partner-sharing requires the optional iCloud sync to be active for the owner.
We need to ship that first (or in the same block).

### Q6. UI surface for the participant?

Probably a stripped-down variant of the home view: hero + phase indicator
only, no logging affordances, no tab bar, no calendar. Effectively a
read-only "today" widget. Could also be surfaced as an actual iOS widget
once the data flow exists.

### Q7. Onboarding copy and consent UX?

The act of sharing health data with another person needs explicit, clear
consent every time it's enabled — not a one-time disclaimer buried in
settings. Wording is sensitive and must avoid implying clinical reliance.

---

## Prerequisites before implementation

1. **iCloud Private DB sync** as a settings opt-in must ship first. Without
   it there's no CloudKit zone to share from.
2. **A defined "Partner-View" data subset** in the SwiftData / CloudKit
   schema. The shared records must be a separate, narrow record type — not
   the full `Cycle` / `DayEntry` rows — so the surface area is auditable.
3. **Privacy statement update**: disclose Apple as iCloud processor and
   explain that activating partner-sharing puts the shared subset in
   Apple's iCloud rather than purely on-device.

---

## Risks and what to watch

- **Re-classification risk under EU MDR?** Probably not — we still don't
  interpret, just surface the same data the owner sees. But worth a fresh
  legal sanity-check before shipping; sharing health data with a third party
  through a software product is a different surface than self-tracking.
- **Trust-boundary after relationship end.** Revocation must be one-tap,
  documented, and the UI should never make it feel costly. Consider an
  auto-prompt: "Du hast die Partner-Ansicht seit X Monaten nicht überprüft —
  noch aktiv lassen?"
- **Discoverability of the share.** A participant who installs Tideline
  expecting to see their own data needs a clear "Du bist Partner — hier ist
  der Inhalt" framing, not just an empty-state confusion.

---

## Effort estimate (very rough)

- iCloud Private DB sync as prereq: 2–3 days
- Shared record type design + migration: 1 day
- Owner-side share-management UI: 1 day
- Participant-side read-only home view: 1 day
- Privacy copy + onboarding: 0.5 day
- QA on real devices (both Apple IDs): 1 day

**Total: ~7 dev-days,** assuming the iCloud sync prereq lands cleanly.

---

## Why this isn't built yet

Listed for completeness. The feature is genuinely valuable but currently
behind in priority because:

1. Tideline doesn't yet have a stable cycle-tracking core that's "worth
   sharing." First we ship the cold-start onboarding, late-mode, resume-flow,
   HealthKit-import — the table-stakes that make Tideline usable solo.
2. CloudKit sync is a separate engineering project on its own.
3. Partner-sharing benefits a specific subset (TTC couples primarily). It is
   not on the critical path to a viable v1.

The right time to revisit this is after the P0/P1 tasks (#71–#85) are closed.
