# Precision Nutrition (FS25) — How It Works (Alpha)

> **Version:** 0.4.0-alpha
> **Scope:** Deep-dive into the simulation pipeline, data flow, and extension points.
> **Audience:** Curious players, modpack authors, contributors.

---

## 0) Mental model (one page)

**Goal:** turn actual feed intake → **Nutrition (Nut)** → **growth (ADG)**, with sensible stage/maturity effects.

Pipeline (per barn, every heartbeat):

1. **Observe intake** since the last tick (or estimate from trough levels).
2. **Aggregate nutrients** (energy MJ, protein kg, dry matter kg).
3. **Compare to targets** for the barn’s current herd makeup → **Nut (0..1)**.
4. Map Nut to **ADG×** (multiplier), then apply **maturity taper** → **ADG (kg/day)**.
5. Slowly drift **Condition** up/down based on sustained Nut, and persist snapshot for overlay/debug.

[DIAGRAM – “Flow from trough → Nut → ADG× → ADG”; annotate delta vs estimate paths]

---

## 1) Heartbeat & time math

### 1.1 Heartbeat trigger

* The mod’s “heartbeat” runs from `Mission00.update`.
* Each call computes `dtH` (hours since last tick):

  ```
  dtH = dtMs / (1000 * 60 * 60)
  if dtH <= 0 return
  ```

### 1.2 Day scaling

* “Actuals” are tracked per tick, but **canonicals** are stored **per day** for clarity:

  ```
  scaleToDay = 24 / dtH
  E_day = E_tick * scaleToDay
  P_day = P_tick * scaleToDay
  D_day = DMI_tick * scaleToDay
  ```

---

## 2) Herd state & stages

### 2.1 Cluster scan

We iterate animal **clusters** to compute:

* counts by gender (bulls/cows),
* total head and weight,
* crude age proxy (months),
* pregnancy/lactation flags (when available).

[SCREENSHOT – console `pnStagesWhy` on a barn with mixed stock]

### 2.2 Stage resolution

Each animal is mapped to a **stage** (CALF / YEARLING / HEIFER / LACT / DRY / BULL / STEER_FINISH, etc.) using:

1. **Hard rules** for COW priority (e.g., lactation wins for females; steers/bulls split for males).
2. Project resolver (`PN_Core.resolveStage`) when present.
3. Fallback **band table** from settings if needed.
4. Last resort: sex-based default.

> Why this order? Keeps gameplay **readable** (e.g., a lactating cow shouldn’t appear as “HEIFER”) and robust across maps.

---

## 3) Feed → nutrients

### 3.1 Two input paths

* **Delta path (preferred):** measure **what was eaten** since last tick via trough deltas.
* **Estimate path:** if there’s no recent delta, we **simulate a draw** from current trough composition up to **demand**.

**Delta path** is used **whenever** `N.dm > 0` this tick; otherwise we fall back to **estimate path**.

### 3.2 Converting feed to nutrients

Each fillType index (FT) is resolved to a feed row (DM %, Energy MJ/kg as-fed, Protein kg/kg as-fed).
For each FT eaten:

```
asFedKg = liters_to_kg(FT, liters)
dmKg    = asFedKg * DM%
energyMJ += asFedKg * energyMJ_per_kg
proteinKg+= asFedKg * proteinKg_per_kg
```

> **Note:** In alpha, **FORAGE is aggregated** (we don’t parse the actual mix recipe yet), so FORAGE tends to hit **Nut ≈ 1.0**. Silage/hay land lower, by design.

---

## 4) Targets & demand

### 4.1 Per-stage targets

From species+stage we get **daily** targets:

* **E_tgt (MJ/day/head)**
* **P_tgt (kg/day/head)**
* **DMI_tgt (kg DM/day/head)**

### 4.2 Barn targets (sum over genders)

We compute daily barn-level targets by multiplying per-head targets by head counts (male/female using their stage rows). These are **not** scaled by frame; they are the “full day” bar to compare against.

### 4.3 Demand for estimate path

For estimates, we compute **reqDmBarn** for this tick:

```
reqDmF  = DMI_tgt_F * cows * (dtH/24)
reqDmM  = DMI_tgt_M * bulls * (dtH/24)
reqDmBarn = reqDmF + reqDmM
```

---

## 5) Nutrition (Nut) computation

### 5.1 Ratios

Once we have per-day canonicals **E_day**, **P_day**, **D_day**:

```
eRat = E_day / E_tgtBarnDay
pRat = P_day / P_tgtBarnDay
dRat = D_day / D_tgtBarnDay
Nut  = clamp01( min(eRat, pRat, dRat) )
```

* **Delta path:** `E_day/P_day/D_day` come from measured consumption scaled to day.
* **Estimate path:** same, but derived by proportional draw from trough composition (up to demand).

### 5.2 Overrides

* Console `pnNut <idx> N` can **pin** Nut to a value for testing; `off` restores auto.

[SCREENSHOT – `pnShowEffects` showing Nut changes after switching feed]

---

## 6) Nut → ADG (growth)

### 6.1 ADG multiplier curve (alpha tuning)

We map **Nut** to an ADG **multiplier** (**ADG×**) with a gentle S-like, piecewise-linear curve:

* Nut=0.0 → ~**0.20×** (don’t die, but grow minimally)
* Nut=0.5 → ~**0.80×**
* Nut=1.0 → up to **1.20×** (cap)

(Pulled from `PN.tuning`: `adgMinFactorAtZero`, `adgFactorAtHalf`, `adgMaxBoost`)

### 6.2 Maturity taper

To avoid silly gains near mature weight, we taper by **avgW / matureKg**:

```
frac     = clamp01(avgW / matureKg)
reserve  = max(0.10, 1 - frac^1.6)
ADG      = baseADG(stage) * ADG× * reserve
```

* **Heavy stock** (steers/bulls/overage) have low reserve.
* **Young stock** feel feed changes strongly.

[DIAGRAM – “ADG× curve” and “reserve vs weight fraction”]

---

## 7) Condition (slow drift)

* **Per-barn** variable in `[0.50 .. 1.00]`.
* Each hour:

  * Nut > 0.9 → `+drift` (default **+0.001/hr**)
  * Nut < 0.6 → `−drift` (default **−0.001/hr**)
* **ADG× is multiplied by Condition**, then clamped (alpha: overall cap ≈ 1.25 after condition).
* Intent: **long-term** reward for consistently good feeding; never crippling.

[SCREENSHOT – `pnShowEffects` after a day at high Nut; Cond ~1.02]

---

## 8) Auto consumption (optional)

If **AutoConsume** is enabled:

* After computing Nut, we **decrement trough levels** by the **DM eaten** this tick:

  * **Delta path:** convert `N.dm` back to as-fed by FT and deduct proportionally.
  * **Estimate path:** deduct `nut * reqDmBarn` (DM), proportionally to trough composition.

This keeps trough levels honest during time-warp tests. Players can toggle:

```
pnAutoConsume on|off
```

---

## 9) Data the mod persists per barn

### 9.1 Canonical snapshot (`entry.__pn_totals`)

* `animals, bulls, cows, pregnant`
* `avgWeight, weightSum`
* `nut` (0..1), `adg` (kg/day)
* `energyMJ` / `proteinKg` / `intakeKgHd` (per-day totals)
* `species, stage, gender`
* `split` (female/male lines using same rules)

### 9.2 Overlay/debug snapshot (`entry.__pn_last`)

* `nutRatio` (0..1)
* `effADG` (kg/day)
* `effects` (0–100; Nut×100 rounded)
* `adgMul` (ADG×)
* `animals` (per-animal cached list for “stages” views)
* `preg` (pregnancy summary)

### 9.3 Per-stage aggregates (`entry.__pn_stageAgg`)

* Built after `animals` snapshot; holds `{stage, gender, n, avgW, adg}` for fast `stages` printing.

[SCREENSHOT – developer overlay or console dump of `__pn_totals`]

---

## 10) Console tooling: how it plugs in

* `pnShowEffects`
  Reads `__pn_totals` / `__pn_last` for each non-empty barn; de-dupes entries; ASCII-only output.
  `pnShowEffects stages` aggregates `__pn_last.animals` and computes ADG via `PN_Core.adgFor`.

* `pnBeat <idx>`
  Triggers one heartbeat for that barn and prints **per-stage** ADG lines using the same core logic.

* `pnInspectTrough <idx>`
  Dumps fillUnits (levels, current FT, supported FTs) to verify map compatibility.

* `pnStages / pnStagesWhy`
  Aggregates stages with ages/weights or shows per-cluster reasons (gender, lactation, steer detection).

* `pnCredit / pnClearFeed / pnNut`
  Test helpers: simulate intake, clear trough, or pin Nut.

> All outputs intentionally avoid Unicode (no •/≈) to play nice with GIANTS’ debug font.

---

## 11) Performance & robustness

* **No per-animal loops on heavy math**: we aggregate by cluster, then by stage.
* **Early exits** when `dtH<=0` or no animals.
* All settings reads are guarded: `(PN and PN.tuning) or {}`.
* If **delta intake** is missing (common on some placeables), the **estimate path** provides consistent, believable results.

---

## 12) Tuning knobs (for pack authors)

In `PN.tuning` (safe defaults used if missing):

* `adgMinFactorAtZero` (default **0.20**)
* `adgFactorAtHalf` (default **0.80**)
* `adgMaxBoost` (default **0.20**) → Nut 1.0 yields **1.20×**
* `conditionDriftPerHr` (default **0.001**)
* `conditionMin`/`conditionMax` (defaults **0.50/1.00**)
* `milkBoostMax` & `milkBoostClamp` (exposed, conservative; future UI hook)

> Adjust these only if you’re comfortable balancing growth across stages.

---

## 13) Edge cases & FAQs

**Q: Why can FORAGE hit 100% Nut?**
A: In alpha, FORAGE is a “good” composite (akin to TMR). We don’t yet decode the exact recipe; that’s planned.

**Q: My heavy steers barely move even at 100% Nut.**
A: That’s the **maturity taper** doing its job. Switch earlier to finishing feeds, not just at the end.

**Q: `pnShowEffects` shows nothing.**
A: Let time run a bit, or call `pnBeat <idx>`. Ensure the barn actually has animals and a trough.

**Q: Nut looks stuck.**
A: Use `pnInspectTrough <idx>` to confirm real feed in the trough and accepted FTs on that placeable.

**Q: Milk?**
A: Internally supported via `__pn_milkMul`, conservative in alpha. Full UI/output wiring comes later.

---

## 14) Extending PN (for devs)

Hook points you can implement/override:

* `PN_Core.resolveStage(species, gender, ageM, flags)`
  Provide map-specific classification (e.g., breed tags).

* `PN_Core.nutritionForStage(species, stage, entry)`
  Return stage-specific Nut (0..1) if you want to weight groups differently.

* `PN_Core.adgFor(species, stage, avgW, nut)`
  Return ADG (kg/day) for a stage + weight + Nut. Default uses baseADG×ADG××taper.

* Feeds matrix (`PN_FeedMatrix`): expand with new FTs or adjust DM/E/P entries.

[DIAGRAM – “Where to plug custom stage & nut logic”]

---

## 15) Testing recipes (copy/paste)

**A/B/C diet sanity:**

```
pnShowEffects
# feed FORAGE only 10m
pnShowEffects
# swap SILAGE only 10m
pnShowEffects
# swap DRYGRASS 10m
pnShowEffects
```

**Force a tick after swap:**

```
pnDumpHusbandries
pnBeat <idx>
pnShowEffects stages
```

**Trough verification:**

```
pnInspectTrough <idx>
```

---

## 16) Roadmap (relevant to “how”)

* Decode **FORAGE** recipes (TMR ingredients → precise Nut).
* Milk output scaling surfaced in UI.
* Per-species/breed refinements, heat stress & weather (post-alpha), mineral balance (post-alpha).

---

## 17) Glossary

* **Nut**: Nutrition fulfillment ratio (0..1), min over energy/protein/DM.
* **ADG**: Average Daily Gain (kg/day).
* **ADG×**: Nutrition-derived multiplier before maturity taper.
* **DM**: Dry Matter (kg).
* **Delta path**: Measured intake since last tick.
* **Estimate path**: Proportional draw from trough composition up to demand.

---

## 18) Appendix — Pseudocode overview

```text
updateHusbandry(entry, clusterSystem, dtMs):
  dtH = dtMs / (1000*60*60)
  if dtH <= 0: return

  # 1) scan clusters → head, sex splits, weights, months
  head,bulls,cows,avgW,avgMonths = scanClusters()

  # 2) targets for species+stage (male/female)
  E_tF,P_tF,DMI_tF = targets(species, stageF)
  E_tM,P_tM,DMI_tM = targets(species, stageM)
  E_tDay = E_tF*cows + E_tM*bulls   # per-day barn target
  P_tDay = ...
  D_tDay = ...

  # 3) intake delta OR estimate
  N = scanDeltaIntake()  # energyMJ, proteinKg, dm
  if N.dm > 0:
     E_day,P_day,D_day = toPerDay(N)
  else:
     (E_day,P_day,D_day) = estimateFromTrough(levels, reqDmBarn, dtH)

  # 4) Nut ratios and clamp
  eRat = E_day / E_tDay
  pRat = P_day / P_tDay
  dRat = D_day / D_tDay
  Nut  = clamp01(min(eRat,pRat,dRat))

  # 5) ADG×, condition drift, maturity taper
  adgMul  = curveFromNut(Nut) * conditionDrift(Nut, dtH)
  ADG     = baseADG(stage) * adgMul
  ADG    *= maturityReserve(avgW / matureKg)

  # 6) advance weights by ADG * (dtH/24), persist snapshots, optional autoConsume
```

---

