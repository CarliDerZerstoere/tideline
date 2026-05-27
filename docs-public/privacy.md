---
layout: default
title: Datenschutz · Tideline
---

# Datenschutz

*Stand: 2026-05-26*

Tideline ist so gebaut, dass diese Datenschutzerklärung kurz sein
kann. Wir verarbeiten keine personenbezogenen Daten auf Servern, weil
Tideline keine Server hat.

Diese Seite erklärt, was das konkret bedeutet — und welche wenigen
Ausnahmen es gibt (Apple-Dienste wie HealthKit oder dein iCloud-Backup,
über die du selbst entscheidest).

## Wer ist verantwortlich?

Verantwortlicher im Sinne der DSGVO (Artikel 4 Absatz 7) ist die
Entwicklerin / der Entwickler der App, erreichbar über die auf der
[Support-Seite](support) genannte E-Mail-Adresse.

## Welche Daten verarbeitet Tideline?

Tideline verarbeitet die Daten, die du in der App selbst einträgst:

- Zyklustage (Periodentage, Stärke der Blutung)
- Optionale Eintragungen: Symptome, Stimmungen, Notizen
- Optionale Ereignisse: Schwangerschaftsverlust, hormonelle Verhütung,
  Stillzeit, andere Zyklus-Unterbrechungen
- Optionale Einstellungen: Altersgruppe, PCOS-Selbstdeklaration,
  Notification-Präferenzen

Diese Daten werden **ausschliesslich auf deinem iPhone** gespeichert,
in einer App-Sandbox-Datenbank (SwiftData / SQLite). Sie verlassen dein
Gerät nicht.

## Was Tideline NICHT macht

- **Keine Konten, kein Login.** Du kannst die App ohne jegliche
  Registrierung verwenden. Es gibt keinen "Sign-in"-Bildschirm.
- **Keine Cloud-Synchronisation seitens Tideline.** Wir betreiben
  weder Server noch Datenbanken in der Cloud. (Eine optionale, freiwillig
  einschaltbare iCloud-Synchronisation ist in einer zukünftigen Version
  geplant und wird klar als Opt-in gekennzeichnet sein.)
- **Keine Analytics-Tools.** Kein Google Analytics, kein Firebase, kein
  Mixpanel, kein Sentry, kein Plausible, kein Fathom. Nichts.
- **Keine Drittanbieter-SDKs**, die Daten übertragen.
- **Keine Werbung**, weder eigene noch externe.
- **Kein Tracking** über App-Grenzen hinweg
  (`NSPrivacyTracking = false` im Privacy-Manifest).
- **Keine Personalisierung** deiner Daten an Werbenetzwerke.

## Welche Apple-Dienste werden genutzt?

Tideline nutzt einige Apple-Funktionen, bei denen Apple — nicht die
Tideline-Entwicklung — die Datenverarbeitung übernimmt. Du entscheidest
selbst, ob du sie aktivierst:

### Apple HealthKit (optional)

Wenn du Tideline mit Apple Health verbindest, kann die App:

- bestehende Periodendaten aus Apple Health **lesen** (für den
  Import-Flow beim ersten Start), und
- die in Tideline eingetragenen Periodentage **zurück in Apple Health
  schreiben** (damit deine Daten zusammenhängend bleiben).

Apple Health ist eine separate, von Apple verwaltete Datenbank. Tideline
hat keinen Zugriff auf andere Apple-Health-Datentypen ausser den von
dir explizit erlaubten. Du kannst die Berechtigung jederzeit unter
Einstellungen → Health → Datenzugriff & Geräte → Tideline widerrufen.

### iCloud-Backup (optional, von dir gesteuert)

Falls du in deinem iCloud-Konto die App-Sicherung für Tideline aktiviert
hast, sichert Apple — nicht Tideline — die App-Datenbank ins iCloud-
Backup. Diese Sicherung ist Ende-zu-Ende verschlüsselt, wenn du die
Erweiterte Datenschutzfunktion (Advanced Data Protection) aktiviert
hast; sonst standardmässig verschlüsselt mit Apple's Schlüsseln.

Du kannst diese Sicherung unter iOS-Einstellungen → Apple-ID → iCloud
→ iCloud-Backup → Backups verwalten → Tideline deaktivieren.

Tideline hat keinen Einfluss darauf, ob du iCloud-Backups verwendest.

### App Store In-App-Kauf (nur bei freiwilligem Beitrag)

Die einmalige "Tideline unterstützen"-Zahlung (4,99 €) wird
ausschliesslich durch Apple's StoreKit verarbeitet. Wir erhalten **keine
Kreditkartendaten und keine Identifikationsdaten** — nur das anonyme
Auszahlungsstatement, das Apple uns periodisch zur Verfügung stellt.

Du musst diesen Beitrag nicht leisten. Tideline funktioniert für alle
gleich.

### Apple App Store Analytics

Apple stellt App-Entwicklern aggregierte, anonymisierte Statistiken zur
App-Nutzung zur Verfügung (Installationen, Updates, Abstürze). Diese
Daten sind nicht auf einzelne Nutzerinnen oder Nutzer rückführbar.
Tideline-seitig findet keine zusätzliche Auswertung statt. Du kannst die
Teilnahme unter iOS-Einstellungen → Privatsphäre → Analyse & Verbesserungen
→ "App-Analyse mit Entwicklern teilen" deaktivieren.

## Welche iOS-APIs nutzt Tideline?

Pro Apple-Richtlinie geben wir im Privacy-Manifest
(`PrivacyInfo.xcprivacy`) die genutzten "Required Reason APIs" an. Stand
heute sind das:

- `NSPrivacyAccessedAPICategoryUserDefaults` — App-Statusflags
  (Onboarding-Fortschritt, App-Sperre an/aus, Notification-Präferenzen,
  Alterskategorie, Phasennamen-Variante). Grund-Code `CA92.1`: Zugriff auf
  Informationen aus der gleichen App, gemäss Dokumentation.
- `NSPrivacyAccessedAPICategoryFileTimestamp` — SwiftData verwendet
  Dateisystem-Zeitstempel auf der lokalen Datenbank. Grund-Code `C617.1`:
  Zugriff auf Informationen über eine Datei oder ein Verzeichnis im
  App-Container.
- `NSPrivacyAccessedAPICategorySystemBootTime` — defensiv deklariert für
  System-Zeit-Berechnungen (Foundation kann darüber laufen). Grund-Code
  `35F9.1`: Zeitabstand zwischen zwei Ereignissen innerhalb der App.

Keine dieser APIs überträgt Daten an Server.

## Welche Rechtsgrundlage und welche Rechte?

Da Tideline keine personenbezogenen Daten verarbeitet (alle Daten
bleiben auf deinem Gerät, ohne dass wir Zugriff darauf haben), greift
für den Verantwortlichen keine eigenständige Verarbeitungsgrundlage
nach DSGVO Art. 6.

Falls du gegenüber Apple Rechte geltend machen möchtest, die deine
HealthKit-Daten, iCloud-Backup oder App-Store-Kaufhistorie betreffen,
wende dich bitte direkt an Apple — Apple ist Verantwortlicher für diese
Datenkategorien.

Falls du gegenüber Tideline Auskunft möchtest, ob wir Daten von dir
verarbeiten: Die ehrliche Antwort ist Nein. Wir können dir keine
Datenauskunft geben, weil wir nichts haben, worüber wir Auskunft geben
könnten.

## Daten besonderer Kategorien (DSGVO Art. 9)

Zyklusdaten gelten nach DSGVO Art. 9 als Gesundheitsdaten und damit als
"besondere Kategorien personenbezogener Daten". Genau deshalb ist
Tideline so gebaut, dass diese Daten dein Gerät nicht verlassen müssen.
Eine Übermittlung an Tideline-Server findet nicht statt — es gibt
keine.

## Kinder

Tideline ist für Personen ab 12 Jahren freigegeben (Apple-Altersfreigabe
12+). Jüngere Kinder sollten die App nicht eigenständig verwenden. Eine
gezielte Adressierung von Kindern unter 13 (US: COPPA, EU: DSGVO Art. 8)
findet nicht statt.

Eine eigene Onboarding-Variante für Jugendliche (gynäkologisches Alter
< 16) ist in Planung. Sie ändert nichts an dieser
Datenschutzerklärung — Datenverarbeitung bleibt vollständig on-device.

## Wellness- und Lifestyle-App, kein Medizinprodukt

Tideline ist eine Wellness- und Lifestyle-App und kein Medizinprodukt
im Sinne der EU-Verordnung 2017/745 (Artikel 2 Nummer 1). Die App
stellt keine medizinische Diagnose, empfiehlt keine Behandlungen und
trifft keine Aussagen zur Empfängnisverhütung oder
Empfängnis-Förderung.

Bei medizinischen Fragen wende dich bitte an deine Ärztin oder deinen
Arzt.

## Änderungen dieser Erklärung

Wenn sich Tideline ändert (z.B. wenn die optionale iCloud-Synchronisation
ergänzt wird), passen wir diese Seite an. Den jeweils aktuellen Stand
findest du am Anfang der Seite ("Stand: …").

## Kontakt

Fragen zum Datenschutz beantworten wir gerne per E-Mail. Die aktuelle
Adresse findest du auf der [Support-Seite](support).

---

## English

*Last updated: 2026-05-26*

Tideline is built so this privacy policy can be short. We don't process
any personal data on servers, because Tideline doesn't have servers.

This page explains what that means concretely — and which few
exceptions exist (Apple services like HealthKit and your iCloud backup,
which you yourself control).

### Who is the controller?

The controller under GDPR Article 4(7) is the app's developer,
reachable via the email address listed on the
[support page](support).

### What data does Tideline process?

Tideline processes the data you enter in the app:

- Cycle days (period days, flow level)
- Optional entries: symptoms, moods, notes
- Optional events: pregnancy loss, hormonal contraception, breastfeeding,
  other cycle disruptions
- Optional settings: age band, PCOS self-declaration, notification
  preferences

This data is stored **only on your iPhone**, in an app-sandbox database
(SwiftData / SQLite). It does not leave your device.

### What Tideline does NOT do

- **No accounts, no login.** You can use the app without any
  registration. There is no sign-in screen.
- **No cloud sync on Tideline's side.** We operate no servers, no
  databases in the cloud. (Optional, opt-in iCloud sync is planned for
  a future version and will be clearly opt-in.)
- **No analytics.** No Google Analytics, no Firebase, no Mixpanel, no
  Sentry, no Plausible, no Fathom. Nothing.
- **No third-party SDKs** that transmit data.
- **No advertising**, neither first-party nor external.
- **No cross-app tracking** (`NSPrivacyTracking = false` in the privacy
  manifest).
- **No personalisation** of your data to ad networks.

### Apple services

Tideline uses several Apple features in which Apple — not Tideline —
processes data. You decide whether to enable them:

- **Apple HealthKit (optional)**: when enabled, Tideline can read your
  existing period data from Apple Health (for first-launch import) and
  write logged period days back to Apple Health. You revoke this any
  time at Settings → Health → Data Access & Devices → Tideline.
- **iCloud Backup (optional, your choice)**: if you have iCloud app
  backup enabled for Tideline, Apple — not Tideline — backs up the
  app database to iCloud. Encryption depends on whether you've enabled
  Advanced Data Protection. You disable this at Settings → Apple ID →
  iCloud → Backup → Manage Backups → Tideline.
- **App Store in-app purchase (only on optional contribution)**: the
  one-time "Support Tideline" payment (€4.99) is processed solely by
  Apple's StoreKit. We receive no card data and no identifying
  information — only Apple's anonymous payout statement.
- **App Store analytics**: Apple provides aggregated, anonymised app
  usage statistics. Disable at Settings → Privacy → Analytics &
  Improvements → "Share with App Developers."

### Required-reason APIs

Per Apple's policy, we declare in `PrivacyInfo.xcprivacy`:

- `NSPrivacyAccessedAPICategoryUserDefaults` — app state flags. Reason
  code `CA92.1`.
- `NSPrivacyAccessedAPICategoryFileTimestamp` — SwiftData local DB
  metadata. Reason code `C617.1`.
- `NSPrivacyAccessedAPICategorySystemBootTime` — defensive declaration
  for Foundation time-delta APIs. Reason code `35F9.1`.

None transmit data to servers.

### Special categories of data (GDPR Art. 9)

Cycle data qualifies as health data under GDPR Art. 9. That's exactly
why Tideline is built so the data never has to leave your device.

### Children

Tideline is rated 12+ (Apple's age rating). Younger children should not
use the app independently.

### Wellness/lifestyle app, not a medical device

Tideline is a wellness and lifestyle app, not a medical device under
EU Regulation 2017/745 (Article 2(1)). The app does not provide medical
diagnosis, treatment recommendations, contraceptive efficacy claims, or
conception efficacy claims.

For medical questions, please consult your doctor.

### Contact

Privacy questions are welcome by email. The current address is on the
[support page](support).
