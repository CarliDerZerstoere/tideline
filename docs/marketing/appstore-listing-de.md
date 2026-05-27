# App Store Connect — Tideline DE Listing

**Locale**: `de-DE` (primary)
**Last revised**: 2026-05-26

Paste each block into the corresponding App Store Connect field on the
"App Information" page. Character counts at the top of each field;
Apple's form will hard-stop at the limit so the lengths below are
verified.

---

## Name (max 30 Zeichen)

```
Tideline — Dein Zyklus
```

22 Zeichen. Behält Wortmarke + Zweck.

---

## Subtitle (max 30 Zeichen)

```
Privat. Ehrlich. On-Device.
```

27 Zeichen. Die drei Differentiatoren komprimiert. "On-Device" ist
technisch genug, um Tech-affine Frauen anzusprechen, und kurz genug
für die Subtitle-Länge.

**Alternativen** (falls der Reviewer "On-Device" als unklar moniert):
- "Privat. Ehrlich. Auf deinem iPhone." (35 Zeichen — zu lang)
- "Zyklus privat tracken. Ohne Cloud." (33 Zeichen — zu lang)
- "Zyklus tracken. Ohne Cloud." (26 Zeichen — funktioniert)

---

## Promotional text (max 170 Zeichen — editierbar ohne Re-Review)

```
Privater Zyklus-Tracker für iOS. Alle Daten bleiben auf deinem iPhone. Kein Konto, keine Cloud, keine Analytics. Mit Periodenkalender, Phasenansicht und Arzt-PDF.
```

165 Zeichen. Liest sich wie ein One-Liner; deckt drei Funktionen ab.

---

## Description (max 4000 Zeichen)

```
Tideline ist ein Zyklus-Tracker, der vollständig auf deinem iPhone läuft. Kein Konto, keine Cloud-Synchronisation, keine Analytics-Tools, keine Drittanbieter-SDKs. Die App zeigt dir, was sie weiss — und sagt offen, was sie nicht weiss.

WAS TIDELINE ANDERS MACHT

• Privatsphäre by design: Daten verlassen dein Gerät nicht. Tideline hat keinen Server, an den irgendetwas gehen könnte.
• Ehrliche Unsicherheit: Vorhersagen kommen als Bereich, nicht als Scheinpräzision. Lieber "in 12–16 Tagen" als "Mittwoch um 18:42".
• Keine Streaks, kein Beschämen: Abwesenheit ist keine Schwäche — Krankheit, Verlust, Erholung sind normal. Engagement entsteht durch Nutzen, nicht durch Strafe.
• Keine medizinische Beratung: Tideline ist eine Wellness- und Lifestyle-App und macht keine Diagnose-Aussagen.
• Generös kostenlos: Alle Funktionen sind frei. Wer mag, kann mit einem einmaligen Beitrag die Entwicklung unterstützen — ohne dadurch Funktionen freizuschalten.

FUNKTIONEN

• Periodenkalender mit Phasen-Visualisierung
• Mein-Zyklus-Übersicht mit Mustererkennung über mehrere Zyklen hinweg
• Bericht für deinen Frauenarzt-Termin: PDF wird auf deinem Gerät erstellt, keine Cloud-Verarbeitung
• Apple-Health-Synchronisation in beide Richtungen (du entscheidest)
• Logging von Symptomen, Stimmungen, Notizen — alles optional
• Ereignisse: Schwangerschaftsverlust, Stillzeit, hormonelle Verhütung, Krankheit, Reise — die App reagiert sinnvoll
• Vorhersage-Intervall mit ehrlicher Konfidenzangabe; bei zu wenig Datenlage sagt sie das auch
• App-Sperre mit Face ID, Touch ID oder Code
• Deutsch und Englisch komplett übersetzt
• Dynamic Type für grosse Schriftgrössen

WAS TIDELINE NICHT MACHT

• Keine Empfängnisverhütungs-Aussagen — die App ist kein Medizinprodukt
• Keine Aussagen über Empfängnis-Förderung oder Fruchtbarkeit
• Keine Diagnose-Hinweise ("du könntest PCOS haben")
• Keine Werbung, weder eigene noch externe
• Kein Tracking, keine Analytics, kein Verkauf von Daten

REGULATORISCHER STATUS

Tideline ist eine Wellness- und Lifestyle-App und kein Medizinprodukt im Sinne der EU-Verordnung 2017/745 (Artikel 2 Nummer 1). Bei medizinischen Fragen wende dich bitte an deine Ärztin oder deinen Arzt.

ÜBER DIE ENTWICKLUNG

Tideline wird von einer Einzelperson in der EU entwickelt. Deutsche Muttersprache, kein Risikokapital, keine Werbe-Geschäftsmodelle. Die Architektur ist die Datenschutzerklärung: kein Server bedeutet keine Datenpanne.

Feedback und Bug-Reports per E-Mail (siehe Support-Seite). Antwortzeit normalerweise 2–5 Werktage.

iOS 18.0 oder neuer benötigt.
```

~2150 Zeichen. Strukturiert mit Versalien-Überschriften (Apple-Konvention
für App-Store-Beschreibungen) statt Markdown. Lesbar auf engen Bildschirmen.

---

## Keywords (max 100 Zeichen, kommagetrennt, keine Leerzeichen nach Komma)

```
Zyklus,Periode,Menstruation,Tracker,Privat,DSGVO,Frauengesundheit,Wellness,Kalender,Mein Zyklus
```

98 Zeichen. Begründung pro Keyword:
- `Zyklus` / `Periode` / `Menstruation`: Suchvolumen-Anker
- `Tracker`: was die App ist
- `Privat` / `DSGVO`: Differentiator vs Flo/Clue
- `Frauengesundheit`: breit gefasste DACH-Suche
- `Wellness`: regulatorisch korrekter Begriff
- `Kalender`: Feature-Suche
- `Mein Zyklus`: Matched die Tab-Bezeichnung der App

**Nicht verwenden** (regulatorisch riskant):
- `Verhütung` / `Fruchtbarkeit` / `Empfängnis` / `Eisprung` / `Ovulation`
  — würden Apple Review veranlassen, Klassifizierung zu prüfen
- `Diagnose` / `PCOS` als alleinstehende Begriffe — diagnostische Konnotation

---

## URLs

| Feld | Wert |
|---|---|
| Support URL | `https://carliderzerstoere.github.io/tideline/support` |
| Marketing URL (optional) | `https://carliderzerstoere.github.io/tideline/` |
| Privacy Policy URL | `https://carliderzerstoere.github.io/tideline/privacy` |

*Die URL-Form `carliderzerstoere.github.io/tideline` ergibt sich aus
dem Standard-GitHub-Pages-Pfad für ein Projekt-Repo. Sobald GitHub
Pages aktiviert ist, zeigt Settings → Pages die finale URL — falls sie
abweicht, hier aktualisieren.*

---

## What's New in this Version (max 4000 Zeichen — pro Version-Bump)

Für Version 0.9.0 (TestFlight-Erstauslieferung):

```
Erste öffentliche Version von Tideline.

• Periodenkalender mit Phasen-Visualisierung
• Mein-Zyklus-Übersicht mit Mustererkennung
• Bericht für deinen Frauenarzt-Termin (PDF auf dem Gerät)
• Apple-Health-Synchronisation in beide Richtungen
• App-Sperre mit Face ID, Touch ID oder Code
• Vollständig on-device — keine Cloud, keine Analytics
• Optionaler Unterstützer-Beitrag (4,99 €) — entsperrt keine Funktionen

Feedback gerne per E-Mail.
```

---

## App-Information-Felder (nicht editierbar von Nutzern)

| Feld | Wert |
|---|---|
| Bundle ID | `com.carliderzerstoere.tideline` |
| SKU | `tideline-ios-001` (frei wählbar; eindeutiger interner Bezeichner) |
| User Access | Full Access |
| Primary Language | German |
| Primary Category | Health & Fitness |
| Secondary Category | Lifestyle |
| Content Rights | Does NOT contain third-party content |
