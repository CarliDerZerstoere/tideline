import SwiftUI

/// Privacy disclosure section in the Mehr tab (task #123).
///
/// Surfaces the load-bearing facts about how Tideline handles user data
/// in plain German. The framing is "the architecture itself is the
/// privacy story" — we don't ask the user to trust a privacy policy;
/// we tell them what is structurally true about where their data lives.
///
/// Content principles:
///   - **Recognition voice**, not legalese ("Deine Daten bleiben auf
///     diesem Gerät", not "We may collect...").
///   - **Honest about HealthKit** — when the user has the HK
///     integration on, data goes to Apple Health, which is a *separate*
///     Apple-owned database. We say so.
///   - **Honest about what we DON'T do** — no diagnosis, no
///     prediction-as-medical-advice. Mirrors CLAUDE.md's hard rules.
///   - **EU MDR posture** — small print at the bottom, explicit
///     wellness/lifestyle classification per Article 2(1).
///
/// No state, no actor calls — pure presentational. Code-reviewer
/// covers correctness; no unit test for the same reason
/// `AppLockSettingsSection` and `CycleIrregularitySection` don't have
/// unit tests.
struct PrivacyDisclosureSection: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privatsphäre")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                // A11y sweep (audit fix #131): give the section header the
                // `.isHeader` trait so VoiceOver users can rotor-skip to
                // this section without reading the body in between.
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                Text("Deine Zyklusdaten bleiben auf diesem Gerät.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    // The main pillar statement — also marked as a header
                    // so the rotor surfaces it.
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    bullet("Alle Eintragungen werden lokal auf deinem iPhone gespeichert.")
                    // TODO(#126): When iCloud private sync ships, revise to
                    // "kein Konto, kein Login, optionale iCloud-Synchronisation
                    // (Standard: aus)". Until then this is literally true.
                    bullet("Kein Konto, kein Login, keine Cloud-Synchronisation.")
                    bullet("Keine Analytics-Tools, keine Drittanbieter-SDKs.")
                    // Reviewer B1 — tightened from "niemand kann ... einsehen"
                    // (overpromise: a jailbroken device, forensic extraction
                    // or iOS backup can in principle expose the SQLite store)
                    // to the falsifiable architectural claim.
                    bullet("Tideline hat keinen Server, an den deine Daten gehen — sie verlassen dein Gerät nicht.")
                }

                DisclosureGroup("Was bedeutet das konkret?") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Speicherort: eine Datenbank im App-Sandbox-Verzeichnis deines iPhones (SwiftData / SQLite).")
                        bullet("Beim Deinstallieren werden alle Tideline-Daten zusammen mit der App gelöscht.")
                        bullet("Apple Health ist eine separate, von Apple verwaltete Datenbank. Wenn du Tideline mit Apple Health verbunden hast, fließen Periodendaten in beide Richtungen — die in Apple Health gespeicherten Daten verwaltest du dort eigenständig.")
                        // Reviewer B2 — acknowledge the iOS-Backup tension
                        // honestly rather than letting "keine Cloud-
                        // Synchronisation" and "iCloud-Backup" appear in
                        // the same view without explanation.
                        bullet("Tideline synchronisiert nichts in die Cloud. Falls du iOS-Backups in iCloud aktiviert hast, sichert iOS allerdings auch Tidelines lokale Datenbank dorthin — verschlüsselt, aber auf Apple-Servern.")
                        bullet("Bei Verlust des Geräts ohne Backup sind die lokalen Daten weg. Tideline bietet aktuell keine eigene Backup-Option.")
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 14))
                .foregroundStyle(.primary)

                DisclosureGroup("Was Tideline nicht macht") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Tideline stellt keine medizinische Diagnose.")
                        bullet("Tideline empfiehlt keine Behandlungen oder Medikamente.")
                        // Reviewer N2 — drop the awkward "solltest" framing
                        // and align with LateMilestoneBucket's reliability-
                        // anchored copy.
                        bullet("Vorhersagen sind statistische Schätzungen mit Unsicherheitsbereich — keine Aussage darüber, ob du schwanger bist.")
                        // Reviewer N1 — natural DACH du-form instead of
                        // "behandelndes Fachpersonal".
                        bullet("Bei medizinischen Fragen wende dich bitte an deine Ärztin oder deinen Arzt.")
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 14))
                .foregroundStyle(.primary)

                Divider()
                    .padding(.vertical, 4)

                // Reviewer B4 — Article 2(1) *defines* "medical device";
                // the wellness/lifestyle carve-out comes from being
                // OUTSIDE that definition (cf. MDCG 2019-11 on software
                // qualification). Phrasing now reflects that, and uses
                // "Artikel 2 Nummer 1" (correct German rendering of a
                // numbered definition) rather than "Absatz 1".
                Text("Tideline ist eine Wellness- und Lifestyle-App und kein Medizinprodukt im Sinne der EU-Verordnung 2017/745 (Artikel 2 Nummer 1).")
                    .font(.caption2)
                    // Task #133 — was .tertiary; bumped to .secondary so
                    // the regulatory copy meets WCAG AA contrast (4.5:1).
                    // It's small (caption2) but legally important, must
                    // be readable.
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // Reviewer N4 — dark-mode contrast; mirrors the
                    // OnboardingFlow pattern (0.08 dark / 0.04 light).
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Reviewer N6 — VoiceOver reads the whole sentence as one
        // element rather than "Bullet, ..." for every row.
        .accessibilityElement(children: .combine)
    }
}
