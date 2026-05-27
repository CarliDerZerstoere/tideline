# "Mein Zyklus" Tab Design Research — User-Value Synthesis

**Date:** 2026-05-21
**Scope:** What content users actually value seeing in a cycle-tracking app, with the design question "what should the 'Mein Zyklus' tab contain to be useful rather than wasted space?"
**Methodology:** Four parallel agent passes, each focused on a non-overlapping evidence source — (1) Reddit / cycle-community deep-dive, (2) TikTok / Instagram viral content analysis, (3) UX retention research from peer-reviewed HCI literature, (4) App Store competitive screenshot analysis of 15 cycle apps. Followed by a fact-checker pass that cross-validated 11 load-bearing claims and overturned 4 of them. **Only post-fact-check findings are recorded here.**
**Supersedes:** Partially supersedes claims in `2026-05-21-market-research-synthesis.md` — see "Corrections to earlier note" below.
**Status:** Immutable per CLAUDE.md research-note convention.

---

## Corrections to the earlier 2026-05-21 market research note

Three claims in `2026-05-21-market-research-synthesis.md` were overturned by today's fact-check and must not be cited as written:

1. **Flo / Google settlement is $59.5M, preliminary approval April 22 2026** — not $56M / 2025. Distribution: Google $48M + Flo Health $8M + Flurry LLC $3.5M. Source: HIPAA Journal coverage of the April 2026 preliminary approval order. Final fairness hearing Oct 29 2026.

2. **The "Li/Dey/Forlizzi 2010 stage-based model implies integration-stage users lapse first" framing was over-stated.** The paper exists and is a foundational HCI text, but the specific causal claim ("users stuck at integration are first to lapse") is a theoretical extension, not an empirical finding. Soften any synthesis language that leaned on this as evidence.

3. **The Bearable user testimonial ("Bearable helped me finally realise how my flare-ups were syncing with my cycle") could not be traced to a primary source.** May be marketing copy, may be paraphrase, may be fabricated. Drop as social proof.

---

## Methodology + fact-check pass

Four agents launched in parallel; one fact-checker validated 11 load-bearing numerical claims afterward. Fact-checker found:
- 5 SUPPORTED (verified to primary source)
- 2 PARTIALLY SUPPORTED (correct directionally, caveats apply)
- 1 CONTESTED (could not validate but no contradictory evidence)
- 3 UNSUPPORTED (overturned outright)

The four agents are flagged in this project's memory as having historically hallucinated citations. Today's pass mitigated that with: (a) explicit instructions to mark interpretive claims as `[my interpretation]`, (b) instructions to write "I cannot verify this" rather than fabricate, (c) the fact-checker pass before any synthesis. The fact-checker also caught a prompt-injection attempt in an arxiv response — same pattern documented in this project's prior research notes.

---

## Strong-evidence findings (verified to primary source)

### 1. German privacy survey: representative national data — strongest empirical finding of the pass

Kühnel & Wilke 2025, *Frontiers in Public Health* (PMC11836014). n=1,004 stratified random CATI sample, weighted, **representative German population** (not a convenience sample). *(Originally cited as "Rietz et al. 2025" — corrected 2026-05-22 after fact-checker pass found that PMC metadata names the authors as Kühnel & Wilke. The 15% figure should be re-extracted from the paper directly before being quoted in App Store copy; only the 43% trust-in-research figure was independently confirmed.)*

- **Only 15% of Germans would share health data with technology companies.** *(re-verify against the paper before public quotation)*
- **43% would share with public research institutions.** (Nearly 3× higher trust in research vs. commercial.) *(confirmed)*
- Privacy concerns widespread, with high proportion requiring complete anonymization.

**Implication:** "On-device only" is not a niche differentiator in DACH — it is a **trust prerequisite** for the segment that already exists. This is the strongest empirical claim across all four reports.

URL: [PMC11836014](https://pmc.ncbi.nlm.nih.gov/articles/PMC11836014/)

### 2. Cycle-syncing TikTok content analysis: 96% of viral content lacks any scientific basis

Pfender, Kuijpers, Wanzer, Bleakley (2025), *Perspectives on Sexual and Reproductive Health*, doi:10.1111/psrh.70004.

- n=100 #cyclesyncing TikTok videos, content-analysed
- 57% covered exercise recommendations by phase
- 54% covered dietary recommendations by phase
- 67-second average video length
- 45,235 average likes per video
- **Only 4% cited any scientific source — and those "citations" were unspecified studies with no author/title/year (effectively zero credible sourcing across the entire viral genre)**

**Implication:** The "cycle-syncing" wellness content space is large, emotionally resonant, and almost entirely uncited. The competitive opportunity is to be the cycle product that **does cite its sources** while remaining emotionally accessible. The viral content shows what format lands (recognition + validation); the lack of citation shows where credibility is unoccupied.

URL: [PMC12204122](https://pmc.ncbi.nlm.nih.gov/articles/PMC12204122/)

### 3. Cycle prediction is the dominant use case (with a caveat)

Lee et al. 2024, Korean mixed-methods study, **n=692 total / n=431 app users** (the PMC URL and the JMIR URL point to the same paper — earlier reports double-counted them).

- **62.3% used the app "primarily" for prediction**
- 85% used it for prediction at all (broader denominator)
- 80% accessed the cycle-prediction view
- 54.5% used period records (retrospective)
- 90% rated apps as useful **despite inconsistent prediction accuracy** — the *intent to plan* drives engagement independent of whether the prediction is right

**Implication:** A cycle app whose primary view is *not* forward-looking is fighting against the dominant use case. The home view must lead with prediction. A secondary tab ("Mein Zyklus") can do retrospection without contradicting this — but cannot replace the prediction surface.

URLs: [PMC11502972](https://pmc.ncbi.nlm.nih.gov/articles/PMC11502972/) / [JMIR 2024](https://www.jmir.org/2024/1/e53146/)

### 4. Doctor-PDF export is a universal market gap

App Store competitive analysis across 15 cycle apps (Flo, Clue, Stardust, Premom, Natural Cycles, Glow, Eve, Period Tracker GP Apps, MyFlo, Kindara, Drip, Bearable, Ovia, inne, myNFP).

**Doctor reports / PDF export = present in zero lead screenshots across all 15 apps.** When data-sharing appears at all, it is buried (Clue Connect at screenshot 8, Premom doctor chat at screenshot 7).

**Implication:** The "Für meinen Frauenarzt-Termin" CTA on the Mein Zyklus tab is unoccupied territory. Existing task #46 (Doctor-Export: on-device PDF generation) should be elevated.

### 5. Plain-language insight + chart beats either alone

arxiv 2402.12634 preprint (within-subjects, n=103, six visualization pairs).

- Data-storytelling visualisations (annotated charts with narrative text) achieved 0.889 median correct-insight comprehension
- Conventional charts achieved 0.667
- p < 0.0001 for comprehension
- **No improvement in efficiency (time)** — the gain is purely comprehension

**Caveat:** Preprint, not peer-reviewed.

**Implication:** Don't write text-only insights, don't show chart-only displays. The combined format is the empirically-best comprehension surface. This validates the design proposal of "phase-band timeline + one-sentence summary per cycle row."

URL: [arxiv 2402.12634](https://arxiv.org/html/2402.12634v1)

### 6. Privacy in App Store screenshot position 1 = Clue only

15-app analysis. **Clue is the only app that puts privacy in screenshot 1.** Drip puts it at slot 8-9 with a literal padlock. Natural Cycles puts "Go Anonymous" at slot 10. **Glow does not show privacy at all** despite documented data-sharing controversies.

**Implication:** The screenshot strategy "Tideline goes further than Clue: literal architectural claim ('Daten verlassen dein Gerät nie') in screenshot 1 or 2" is unoccupied competitive territory in the App Store search-result page itself.

---

## Theoretical / directional findings (use as framing, not evidence)

### Recognition + validation framing outperforms data display

Pfender 2025 qualitative companion study + TikTok viral content analysis:

- "Now I understand why I was feeling that way" is the dominant emotional response in viral cycle-syncing content
- @wombtrition's "Dark Side of FemTech" critique of Stardust drew ~99.7K likes / ~2.4K comments (cited engagement, not directly verified due to TikTok scraping limits, time-sensitive)
- Common critique pattern: "empowerment washing" — feminist marketing language without clinical rigor

**Implication:** Insight copy on the Mein Zyklus tab should be framed as recognition ("Wenn du dich in den letzten Tagen müder gefühlt hast…") rather than fact ("Deine Lutealphase war 13 Tage."). Both are accurate; only one is emotionally resonant.

### Long-term retention is anchored to reliability + data ownership, not feature richness

Multiple sources (PMC qualitative European study, JMIR retention reviews, App Store retention patterns). The retention drivers consistently cited:
- Accuracy that improves over time
- Trust in data privacy
- Low logging burden

**Caveat:** The specific Li/Forlizzi "integration-stage = first to lapse" claim is theoretical framing, not empirical finding. Use as design principle ("don't trap users in pure data collection without reflection") not as evidence.

### Generic wellness tips are the most-abandoned surface

Trustpilot, Flo reviews, Real Nutrition review of FitrWoman, Longevity Advice comparison.

- "Didn't tell me anything different to what Google or AI can provide (for free)"
- "Static and generic. I was expecting new info every month"
- Daily sexual health tips draw active user hostility (parents flagging 12+ apps showing oral sex tips)

**Implication:** Phase explainer content ("In the luteal phase your progesterone rises…") is read once and never returned to. It belongs in onboarding or a "Was passiert gerade?" tap-to-expand. Not on the Mein Zyklus tab as a primary surface.

---

## What this means for the Mein Zyklus tab — design synthesis

The tab should be the **"Now I understand why" surface**, populated from the user's own data. Not a data dump, not generic phase content, not a paywall pitch.

### Three layers, in priority order:

**Layer 1 — Today's recognition.** The first thing the user sees on tapping the tab. Not "Tag 14 — Ovulation" (the home view's job). Instead: a recognition-framed sentence grounded in the user's own logged symptoms. *"Wenn du dich heute fitter gefühlt hast — du bist in der Ovulationsphase, das ist typisch."* Two-line. Refreshes only when there's something new to say.

**Layer 2 — One pattern observation per visit.** A single plain-language sentence + a small chart, anchored in the data-storytelling evidence (0.889 vs 0.667 comprehension). *"Deine Lutealphase hat sich in den letzten 3 Zyklen um 2 Tage verkürzt"* with a small sparkline showing the trend. Refreshes when there's a new pattern.

**Layer 3 — Collapsed retrospection.** Phase-band timeline of recent cycles + cycle-length stats + access to logged events. Tap-to-expand. Serves the 54.5% who value record-keeping per the Lee et al. study without dominating the tab for the 62.3% who came for forward-looking content.

### CTAs at the bottom of the tab:

- **"Für meinen Frauenarzt-Termin"** → triggers task #46 (German doctor PDF export). The market research established this is unoccupied territory; the App Store analysis confirmed zero competitors lead with it; the German clinical culture expects structured patient self-documentation.
- **(Future) "Ereignis hinzufügen"** → general event-creation flow, task #75. Until then, events flow through Settings (PCOS toggle) and the Resume-Sheet (task #74).

### What NOT to put on the tab:

- Generic phase explainer content read once, never returned to
- Long symptom checklists (move logging to its own action surface)
- Predictions with false precision (no "your period is on May 28th" — show ranges)
- Streaks, badges, gamification of any kind (CLAUDE.md hard rule; PMC ethics paper confirms anxiety/defeat patterns)
- AI-generated text in v1 (use templates; layer AI later if templates feel robotic)

### DACH-specific positioning that this research validates:

- The privacy framing in onboarding + screenshot 1 ("Daten verlassen dein Gerät nie") is supported by representative population data, not vibes
- German consumers accept technical, regulatory-credentialed framing (myNFP and inne demonstrate this)
- The "made in Europe / data stays in Europe" positioning Clue uses (#FromBerlinWithSolidarity) has documented creator traction; Tideline can go further with the on-device claim

---

## Key sources (post-fact-check, only verified citations)

- [Kühnel & Wilke 2025 — Health data sharing in Germany (Frontiers, PMC11836014)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11836014/) — *strongest empirical evidence in the pass; representative n=1,004 CATI* (originally mis-attributed to "Rietz et al." — corrected 2026-05-22)
- [Pfender et al. 2025 — Sync or Swim: #cyclesyncing TikTok content analysis (PMC12204122)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12204122/)
- [Lee et al. 2024 — Korean cycle tracker mixed-methods (PMC11502972 / JMIR 2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11502972/) — *single paper, do not double-count*
- [arxiv 2402.12634 — Data storytelling vs. conventional visualisation (preprint)](https://arxiv.org/html/2402.12634v1)
- [Frontiers 2023 — Reimagining the Cycle: period apps + menstrual empowerment](https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2023.1166210/full)
- [PMC 2019 — A good little tool to get to know yourself a bit better (Austria/Spain qualitative)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6724299/)
- [PMC 2021 — Ethics of Gamification in Health and Fitness-Tracking](https://pmc.ncbi.nlm.nih.gov/articles/PMC8583052/)
- [HIPAA Journal — Flo $59.5M settlement preliminary approval (April 2026)](https://www.hipaajournal.com/flo-health-google-flurry-59-5m-settlement-privacy-lawsuit/)
- App Store competitive analysis across 15 apps — see report transcript

### Not citation-grade but useful as directional input

- @wombtrition "Dark Side of FemTech" TikTok — engagement numbers time-sensitive, content verified
- Bearable testimonials in third-party reviews — couldn't trace to primary source, drop as evidence
- The Story Exchange profile of Dr. Mary Claire Haver — "0 to 1M in a year" framing is fabricated/extrapolated; the article actually cites only "2M followers" with no specific growth-rate claim
