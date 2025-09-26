# Precision Nutrition (FS25) — Player Guide (Alpha)

> **Version:** 0.4.0-alpha
> **Works with:** Any map that has vanilla-style animal husbandries
> **TL;DR:** Better feed → better growth. You can *see* it live (Nut %, ADG, ADG×). Powerful console tools included.

---

## What This Mod Does

* **Nutrition (Nut %)** is calculated from what animals actually eat.
* **Growth (ADG, kg/day)** scales with nutrition using a curve:

  * Nut ≈ **1.00** → **~+20%** faster than base (before maturity taper)
  * Nut ≈ **0.84** → **~+7%**
  * Nut ≈ **0.71** → **~3–4% slower** than base
* **Maturity taper:** heavier animals gain more slowly as they approach mature weight.
* **Condition (long-term):** sustained good feeding nudges a small bonus; poor feeding nudges a small malus.

<img width="1646" height="471" alt="image" src="https://github.com/user-attachments/assets/b38b870e-37b6-4f1d-8410-080045366471" />
<img width="1677" height="464" alt="image" src="https://github.com/user-attachments/assets/3ef57714-908f-43d1-9e4d-c6785d48452e" />


---

## Quick Start (10 Minutes)

1. **Pick a barn** with animals.
2. **Feed FORAGE/TMR only** and let time run 5–10 in-game minutes.

   * Watch **Nut → ~100%**, **ADG rise**, **ADG× ≈ 1.20**.
3. **Switch to silage only** (similar availability).

   * Nut → ~**84%**, ADG dips (ADG× ~1.07).
4. **Switch to dry grass only.**

   * Nut → ~**71%**, ADG dips further (ADG× ~0.96–0.97).

[**screenshot: console** with three successive `pnShowEffects` runs after each feed change.]

---

## Core Concepts

### Nut (Nutrition Ratio)

* 0.00–1.00 (shown as %).
* Based on **energy**, **protein**, and **dry matter intake** vs targets for the barn’s current herd makeup.
* Your mix in the trough **matters** (silage vs hay vs forage/TMR).

### ADG (Average Daily Gain, kg/day)

* The growth rate your animals are currently trending toward.
* Calculated per frame; **displayed as per-day** for clarity.
* **ADG×** (multiplier) shows how nutrition scales base stage growth before maturity taper.

### Condition (slow drift)

* Moves very slowly upward with **sustained Nut > ~0.9** and downward with **Nut < ~0.6**.
* Small effect by design in alpha (long-term reward, not a hammer).

[**screenshot: console** `pnShowEffects` after a full in-game day at 100% Nut, showing Cond a little above 1.00.]

---

## Installation & Compatibility

* Drop the mod zip into your FS25 mods folder as usual.
* Compatible with most animal mods/maps; we read standard trough levels/consumption.
* **No save conversion**; can be added/removed safely (you’ll just lose the PN effects when removed).

---

## Using the Console Tools

> Open the developer console (standard FS keybind). All commands are **ASCII only** (no special symbols).

### 1) Find Your Barn Index (optional)

Some commands need an entry index.

```text
pnDumpHusbandries
```

* Prints a numbered list of husbandries PN knows about.
* Use that index with other commands like `pnBeat`, `pnInspectTrough`, etc.

<img width="1223" height="854" alt="image" src="https://github.com/user-attachments/assets/696fd6e1-652b-4508-b764-f937bd55fcf2" />

---

### 2) Effects Summary (what most players need)

#### Barn summary

```text
pnShowEffects
```

Shows one line per non-empty barn:

```
- Timber Sage Cow Barn [STEER_FINISH] | head=9 | Nut~71% | ADG x0.97 | Cond=1.00 | ADG=0.528 kg/d
```

#### Per-stage breakdown (mirror of pnBeat, aggregated)

```text
pnShowEffects stages
```

Adds a stage list under each barn:

```
  - [YEARLING] | head=8 | avgW=420.1kg | Nut~71% | ADG x0.97 | ADG=0.071 kg/d
  - [CALF]     | head=1 | avgW=80.6kg  | Nut~71% | ADG x0.97 | ADG=0.069 kg/d
```

**Tips**

* Run again after changing feed to see the difference within minutes.
* If nothing prints, let time run a bit (PN updates during the heartbeat).

<img width="1716" height="677" alt="image" src="https://github.com/user-attachments/assets/24e5219c-1417-4008-8f97-d9f04159e097" />

---

### 3) One-Shot Update (A/B testing)

```text
pnBeat <index>
```

Forces a single PN tick on the given barn and prints per-stage lines (handy after a feed swap).

Examples:

```
pnBeat 10
pnBeat 16
```

<img width="1770" height="368" alt="image" src="https://github.com/user-attachments/assets/c031dbeb-8e11-47f8-82d5-57f96e5586e0" />

---

### 4) Inspect Your Trough

```text
pnInspectTrough <index>
```

* Shows **fillUnits**, current **fillType**, supported **feed types**, and **levels**.
* Useful to verify what the map/placeable actually accepts and what’s in there right now.

[**screenshot: console** with `pnInspectTrough 10` showing supported feed types and levels.]

---

### 5) Stage & Cluster Diagnostics (advanced)

#### Stage breakdown table (with ages/weights)

```text
pnStages <index>
```

* Prints headcount and average weight per stage, min/avg/max age, and—if configured—price guidance for over-age animals.

<img width="1819" height="465" alt="image" src="https://github.com/user-attachments/assets/4c646b71-1bf5-4f15-acf4-6357e1930c91" />

#### “Why is this a steer/bull/etc.?” (debug)

```text
pnStagesWhy <index>
```

* Prints per-cluster info (gender, age, castration hints, resolved stage) for the barn.

<img width="1869" height="764" alt="image" src="https://github.com/user-attachments/assets/c075c942-15b6-4c89-9c8e-5cda0fee7eb1" />

---

### 6) Feeding Controls (testing only; optional)

* **Clear/reduce** trough:

  ```text
  pnClearFeed <index> [percent]
  ```

  Example: `pnClearFeed 10 50` (halve levels)

* **Credit intake** to the barn (simulate eating a feed instantly):

  ```text
  pnCredit <index> FILLTYPE_NAME kg
  ```

  Example: `pnCredit 10 SILAGE 200`

* **Set Nut override** (pins nutrition, for experiments):

  ```text
  pnNut <index> <0..1>     # e.g., pnNut 10 1.0
  pnNut <index> off        # return to automatic
  ```

* **Auto consumption** (let PN consume trough levels in “estimate” path):

  ```text
  pnAutoConsume on|off
  ```

* **Intake debug** (spammy):

  ```text
  pnIntakeDebug on|off
  ```

[**screenshot: console** after `pnCredit` showing effects change.]

---

### 7) Overlay & Settings

* Toggle overlay:

  ```text
  pnOverlay
  pnOverlayMine on|off|all
  pnOverlayNext
  pnOverlayPrev
  ```

* Reload PN packs/settings:

  ```text
  pnPNReload
  ```

* Heartbeat period (ms) or disable (“off”):

  ```text
  pnHeartbeat 1000
  pnHeartbeat off
  ```

* Logger level:

  ```text
  pnSetLogLevel INFO    # TRACE|DEBUG|INFO|WARN|ERROR
  ```

* Diagnostics & self-heal:

  ```text
  pnDiag
  pnFixEvents
  ```

---

## Play Patterns That Feel Good

* **Finishers:** Grow on cheaper roughage, then switch to FORAGE/TMR to finish faster.
* **Dairy:** Keep **lactating** groups near 100% Nut for steadier condition (and future milk tuning).
* **Pasture risk:** If you rely on grass-only, expect Nut in the 0.7–0.8 band; growth is slower but costs are minimal.

[**screenshot: two barns** side-by-side—one on forage (Nut~100%), one on hay (Nut~71%).]

---

## Known Limitations (Alpha)

* **FORAGE** is still an aggregated bucket; we don’t yet infer exact TMR recipes.
* **Milk multiplier** is exposed internally; some maps may not yet hook it to milk output UI.
* Balance is conservative: condition drift is subtle; ADG cap is modest.

---

## Troubleshooting

* **Font warnings (“character not found”)**
  We output only ASCII (e.g., `Nut~84%`, `- bullets`) to avoid those glyphs.

* **No barns in `pnShowEffects`**
  Let time run briefly or run `pnBeat <index>`; ensure the barn has animals and recent PN tick.

* **Nut always 100%?**
  Check your trough contents with `pnInspectTrough`. If it’s **FORAGE** only, 100% is intended. Try silage/hay to see lower Nut.

* **Crash: attempt to index nil ‘tuning’ or missing console command:**
  Ensure your mod’s load order includes **PN_Settings.lua** and **PN_Debug.lua** with:

  ```lua
  PN = PN or {}   -- very top of each file
  ```

  (Already included in the shipped alpha.)

---

## Appendix — Command Quick Reference

| Command                    | Purpose                                  | Example                        |
| -------------------------- | ---------------------------------------- | ------------------------------ |
| `pnShowEffects`            | One-line per barn (Nut, ADG×, Cond, ADG) | `pnShowEffects`                |
| `pnShowEffects stages`     | Add per-stage breakdown under each barn  | `pnShowEffects stages`         |
| `pnDumpHusbandries`        | List PN-tracked barns with indices       | `pnDumpHusbandries`            |
| `pnBeat <idx>`             | Force a PN update & print per-stage      | `pnBeat 10`                    |
| `pnInspectTrough <idx>`    | Show feed units, levels, supported types | `pnInspectTrough 10`           |
| `pnStages <idx>`           | Stage table with age/weight              | `pnStages 10`                  |
| `pnStagesWhy <idx>`        | Explain stage per cluster                | `pnStagesWhy 10`               |
| `pnClearFeed <idx> [pct]`  | Reduce or clear trough levels            | `pnClearFeed 10 50`            |
| `pnCredit <idx> FT kg`     | Credit intake (simulate eating)          | `pnCredit 10 SILAGE 200`       |
| `pnNut <idx> <0..1 off>`   | Override/clear nutrition                 | `pnNut 10 1.0`                 |
| `pnAutoConsume on / off`   | Toggle auto trough consumption           | `pnAutoConsume on`             |
| `pnIntakeDebug on /off`    | Toggle intake logging                    | `pnIntakeDebug off`            |
| `pnOverlay` / `pnOverlay*` | Toggle overlay / navigate                | `pnOverlay`                    |
| `pnPNReload`               | Reload PN configs                        | `pnPNReload`                   |
| `pnHeartbeat <ms off>`     | Change PN tick rate                      | `pnHeartbeat 1000`             |
| `pnSetLogLevel <L>`        | Logger level                             | `pnSetLogLevel DEBUG`          |
| `pnDiag`                   | Module readiness                         | `pnDiag`                       |
| `pnFixEvents`              | Restore events methods                   | `pnFixEvents`                  |
| `pnFindFeeder <idx> [m]`   | Nearby feeder placeables                 | `pnFindFeeder 10 35`           |
| `pnInspectHusbandry <idx>` | Inspect entry internals                  | `pnInspectHusbandry 10`        |
| `pnInspectClusters <idx>`  | Dump cluster objects                     | `pnInspectClusters 10`         |
| `pnInspectFoodSpec <idx>`  | Dump husbandryFood levels                | `pnInspectFoodSpec 10`         |

---

## Changelog Highlights (Player-Facing)

* New **ADG multiplier** curve tied to Nut (feels rewarding but fair).
* Subtle **Condition** drift for long-term husbandry.
* **Effects summary** & **per-stage breakdown** commands.
* Cleaner console output (ASCII only).
* Safer load order & debug guards.

---

### Contributing / Feedback

If you hit a barn that “doesn’t move” or Nut looks wrong:

1. Run `pnInspectTrough <idx>` and `pnBeat <idx>`,
2. Paste both outputs in an issue with your map/mod list,
3. Tell us what feed was in the trough.

We’ll tune it fast. Enjoy! 🐄🌾
