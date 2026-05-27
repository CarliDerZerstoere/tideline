# Post-launch Watch — Tideline v0.9.0 First 48 Hours

After the first internal tester installs, this is what to do for the
next 48 hours. Concrete, time-boxed, no agonising.

## Daily checklist (twice a day, ~10 min each)

### Morning (within 1 hour of waking)

1. **App Store Connect → Apps → Tideline → TestFlight → Crashes tab**
   - Filter: last 24h
   - Any new crash → click → read stack trace → identify file:line
   - If reproducible from the stack trace alone: open the file, see
     "Hotfix trigger criteria" below
2. **Email inbox: niki.riedl@gmail.com**
   - Any tester message → reply within today, even if just "thanks,
     looking into it"
   - Do NOT let messages sit > 24h. Quiet senders feel ignored
3. **TestFlight Analytics tab → Sessions chart**
   - Wildly off baseline (sudden zero, sudden spike)? Investigate

### Evening (before bed)

Same three checks. Most crashes are reported at end of day in the
local timezone because testers use the app then.

## Hotfix trigger criteria (be explicit; don't agonise)

| Symptom | Severity | Action | Timeline |
|---|---|---|---|
| Crash on cold launch (any tester) | **P0** | Reproduce → fix → ship v0.9.1 | Same day |
| Crash anywhere else, reproducible (≥1 tester) | **P1** | Reproduce → fix → ship v0.9.1 | Within 24h |
| Crash on cold launch (1 tester, not reproducible by you) | **P1** | Ask tester for steps; if still un-reproducible after 2 cycles, mark as P2 | 24h |
| Data loss reported by any tester | **P0** | All-hands; reproduce, fix, ship v0.9.1 + email apology | Same day |
| Apple Account prompt on cold launch | **P0** | Verify Session 7 lazy-init regression test still passes; if so, reproduce on real device; ship v0.9.1 | Same day |
| Visual bug, no functional impact | **P2** | Document, batch with next feature work | Next batch |
| Feature request | **P3** | Document in tracker, reply with thanks + "noted for later" | Reply within 24h, work later |
| German copy correction | **P2** | Quick fix in v0.9.1 if straightforward; otherwise next | Within 1 week |
| iOS version too old (tester < 18.0) | **out of scope** | Reply: "Tideline requires iOS 18.0+. Maybe wait for a later version when you've upgraded?" | Within 24h |

## Things NOT to do

- **Don't ship a hotfix on someone's bug report without trying to
  reproduce first.** Even if the report is detailed. You lose so much
  more debug context once you've recompiled.
- **Don't add features in response to feedback in the first 48h.** The
  feedback hasn't stabilised. Note it down and revisit weekly.
- **Don't reply with auto-generated messages.** Personal short replies
  beat polished long ones for trust building.
- **Don't ship v0.9.1 unless you have a meaningful change.** TestFlight
  builds expire after 90 days and each new build re-triggers tester
  install — don't ask them to update for trivial reasons.

## What "good" looks like at 48h

- 5–10 testers installed
- ≥3 have actually used it (sessions visible in Analytics)
- Some emails in your inbox (not silence)
- Either 0 crashes OR all crashes have been triaged and you know which
  ones will need a v0.9.1
- Your morning + evening checklists ran every day

## What "bad" looks like at 48h

- Silence — install but no usage signal. Probably means the app
  doesn't surface a clear "what to do now" on first launch. Look at
  the onboarding flow.
- One tester reports something terrible (data loss, crash on cold
  launch) and you don't have a fix yet → consider pausing the build
  in ASC ("Remove from testers") while you investigate, so other
  testers don't hit the same bug
- App Store Connect shows "Invalid Binary" or similar processing
  rejection after the fact — this happens occasionally; read the
  email Apple sends, fix, re-archive, re-upload

## When to expand to external testers

After 1–2 weeks of internal testing with:
- No P0 / P1 open crashes
- ≥1 round of stable usage from each internal tester
- Your inbox is calm (not stacked with un-replied messages)

Then: ASC → TestFlight → External Testing → Create a new group →
submit the build for Beta App Review (Apple, 1–2 day wait) → invite up
to 10,000 testers via public link or email.

External testing is **Session 11+** territory, not v0.9.0.

## Where this stops

48 hours after first install, you're "out of launch mode" and into
normal-feedback mode. Keep replying to email, keep watching crashes,
but you can step back from twice-daily checks. Weekly is fine.

The next planned milestone is v1.0 public App Store release. That
needs:
- Fehring NFP licensing resolved (release blocker)
- 2+ weeks of stable TestFlight without P0/P1 hotfixes
- App Store full submission completed (Session 9 docs cover the form)
- Apple App Store review (~24–72h)
