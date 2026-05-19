# Research Note — Hormone Tracking via Mobile App

**Date:** 2026-05-19
**Researcher:** research-analyst sub-agent
**Fact-checked:** No (queued)
**Drove decisions in:** Hormone tracking roadmap (not yet a design doc)

---

## Question driving this research

Can hormones (estrogen, progesterone, LH, FSH) be accurately tracked by an app, and what's the right scope for Tideline?

---

## Key findings

### Direct hormone measurement (consumer-accessible)

| Method | Hormones | Accuracy vs. lab | Cost (USD) | iOS integration |
|---|---|---|---|---|
| Basic LH strips (Wondfo, Easy@Home) | LH binary | 90-97% sensitivity, ~100% specificity | $0.20-0.50/strip | Manual / photo |
| Clearblue Digital OPK | LH + E3G | Detects 2-day fertile window ~97% | $1.50-3/test | Bluetooth (Clearblue app only; no public SDK) |
| Premom quantitative (camera scan) | LH (numerical) | High in lab; lighting-dependent in real use | $0.30-0.50/strip | Premom SDK or Core ML |
| **Inito (iPhone-attached)** | LH + E3G + PdG | **r² = 0.99 vs. ELISA, CV < 6%** (Scientific Reports 2023, n=152) | $99 + $29-49/mo | **Plugs directly into iPhone port** ✅ |
| Mira analyzer | LH + E3G + PdG + FSH | 99.5% claimed | $199 + $30-45/mo | Bluetooth (no public API) |
| Proov PdG | PdG only | 82.4% detection at 5 µg/mL (pilot n=34) | $1.50-3/strip | Photo |
| Saliva ferning | Estrogen indirect | 86.5% (KNOWHEN) | $20-80 | Manual |
| Mail-in blood spot | E2, P4, LH, FSH, AMH, etc. | Clinical-grade | $79-199/test | Manual entry of PDF |
| Continuous biosensors (Clair, sweat patches) | Inferred | 87-94% phase classification (not direct measurement) | Unreleased (Dec 2026) | TBD |

### Indirect hormone inference from wearable signals

| Signal | Hormone proxied | Correlation strength |
|---|---|---|
| Wrist/finger temperature | Progesterone (luteal rise) | Strong; best non-invasive proxy |
| HRV | Progesterone (inverse) | Within-person r ~ -0.03; statistically significant, tiny effect size |
| RHR | Progesterone | ~1-2 bpm luteal elevation; useful in ensemble only |
| Respiratory rate | Progesterone | Small luteal elevation; weak alone |
| Voice F0 | Estrogen | 81% of users showed shift in fertile window (n=16); experimental |
| EDA | Autonomic state | 87% phase classification with multi-signal ML |

### Multi-signal fusion benchmarks
- Multi-signal ML (Apple WHS 2025): 87% accuracy on 3-phase classification, 68% on 4-phase daily
- Clair (Dec 2026 launch): 94.1% phase classification, 87% LH surge sensitivity within 1.2 days
- These are *phase inference*, not hormone *measurement*

### The Inito standout

Inito is the most accurate consumer device:
- r² = 0.99 for LH, E3G, PdG vs. ELISA
- Plugs into iPhone's port → all processing on-device
- $99 device + strip subscription
- Architecturally aligned with Tideline's privacy model

### Regulatory implications

| What the app does | Status |
|---|---|
| Show raw values the user logged | ✅ Wellness |
| Show trend charts | ✅ Wellness |
| Show reference ranges next to values | ✅ Wellness |
| AI text: "you ovulated on day X" | ⚠ Grey zone, possibly SaMD |
| AI text: "your luteal phase is short, may affect fertility" | ❌ Medical device — never ship |
| Flag FSH as "diminished ovarian reserve" | ❌ Medical device — never ship |

---

## Decisions made from this research

### Tier 1 (build now)
1. HealthKit reads: wrist temp, HRV, RHR, sleep, respiratory rate
2. HealthKit standard types: `OvulationTestResult`, `MenstrualFlow`, `CervicalMucusQuality`
3. Manual entry for quantitative OPK values (Inito/Mira/Proov)
4. Manual entry for blood lab results with cycle-day context — **genuinely differentiating; no privacy-first app does this well**

### Tier 2 (defer)
- Camera-based strip scanning (Premom does it well)
- Clearblue BLE (no public SDK)
- Clair (not shipping until Dec 2026)

### Tier 3 (never)
- AI diagnostic interpretation of hormone values
- Voice F0 analysis (privacy + accuracy concerns)
- FSH/AMH clinical flagging

### AI summary scope
Apple Intelligence may summarize what the user logged ("you logged 3 LH tests this week showing a peak on Thursday") — never interpret it ("this suggests X about your fertility").

---

## Verification status

Not yet fact-checked. Specific accuracy numbers are mostly from vendor materials and one peer-reviewed study (Scientific Reports 2023 for Inito). The HRV correlation figures (very small r) are from Bechke et al. 2020 (PMC7141121). Fact-check pending.
