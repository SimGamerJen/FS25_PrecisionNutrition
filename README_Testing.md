# Precision Nutrition — Tester Guide (Console & Overlay)

> **Goal:** Quickly validate that PN detects barns, shows live animal stats, and applies nutrition-driven weight gain in a safe, observable way—*before* wiring real feed intake.

## Prereqs

* **Game:** Farming Simulator 25
* **Mod:** FS25\_PrecisionNutrition (this branch)
* **Developer console enabled** (Options → General → *Development Controls* ON; or `game.xml` set `developmentControls="true"`).
* **Load a save** with at least one animal barn you own.

---

## Quick Start (2 mins)

1. **Open your save** and press **Alt+N** → PN overlay appears.
2. (Optional) In console: `pnOverlay` toggles overlay on/off.
3. `pnDumpHusbandries` → see indexed list of all detected animal barns.
4. Pick a barn **you own** (e.g., index **9**).
5. `pnNut 9 1` → set nutrition to 100% (max gain).
6. `pnSim 9 6` → simulate 6 hours.
7. `pnBeat 9` → heartbeat shows **Nut=100%** and **ADG≈stage base**, and **avgW** has increased.

---

## Overlay (Alt+N)

* **Alt+N** toggles the on-screen overlay.
* Header shows **scope**:

  * `My Farm Only` (default) → only barns you own
  * `All Farms` → everything detected

**Console scope toggle:**

* `pnOverlayMine on` → only your barns
* `pnOverlayMine off` or `pnOverlayMine all` → all barns
* `pnOverlayMine` (no arg) → toggles
* You can also `pnOverlay` to toggle the overlay itself.

---

## Core Console Commands

| Command                      | Purpose                                 | Example                                                                | Expected Output                   |                                   |       |         |
| ---------------------------- | --------------------------------------- | ---------------------------------------------------------------------- | --------------------------------- | --------------------------------- | ----- | ------- |
| `pnDumpHusbandries`          | List all detected barns with index      | —                                                                      | Numbered list (22, etc.)          |                                   |       |         |
| `pnDumpHusbandriesCSV`       | Write a CSV to your mod settings folder | —                                                                      | Path + count written              |                                   |       |         |
| `pnInspect <index>`          | Inspect one entry’s placeable/specs     | `pnInspect 9`                                                          | Keys/values dump                  |                                   |       |         |
| `pnInspectClusters <index>`  | Peek at the animal clusters/fields      | `pnInspectClusters 9`                                                  | First \~20 keys for each cluster  |                                   |       |         |
| `pnOverlay`                  | Toggle overlay                          | —                                                                      | Overlay ON/OFF log                |                                   |       |         |
| `pnOverlayMine [on/off/all]` | Filter overlay scope                    | `pnOverlayMine on`                                                     | “Overlay ownership filter now: …” |                                   |       |         |
| `pnBeat <index>`             | One-shot PN heartbeat for that barn     | `pnBeat 9`                                                             | \`Barn \[SPECIES]                 | head=… avgW=…                     | Nut=… | ADG=…\` |
| \`pnHeartbeat \<ms           | off>\`                                  | Periodic heartbeat rate                                                | `pnHeartbeat 3000`                | “Heartbeat set to every 3000 ms.” |       |         |
| `pnNut <index> <0..1>`       | Set/view nutrition fulfillment          | `pnNut 9 0.5`                                                          | “nutrition ratio set to 50%”      |                                   |       |         |
| \`pnSim <index> \<hours      | Nd>\`                                   | Time-warp simulation (applies weight gain for the period, then prints) | `pnSim 9 6` or `pnSim 9 0.5d`     | “SIM … dT=6h … avgW=…”            |       |         |

> Tip: Use `pnSim` during testing to see weight changes **immediately** (e.g., 6–12h). The normal per-frame gain is tiny by design.

---

## What to Look For

* **Overlay rows** like:

  ```
  Timber Sage Cow Stall [COW] | head=15 (M:4/F:11, preg=1) avgW=403.02kg | Nut=100% | ADG=0.90 kg/d
  ```

* **`pnBeat <index>`** prints:

  * **Species** bracket (e.g., `[COW]`, `[SHEEP]`)
  * **Headcounts** with M/F/pregnant
  * **avgW** (average weight; we suggest `%.2f kg` in code)
  * **Nut=XX%** (your test ratio)
  * **ADG=X.XX kg/d** (effective daily gain per head = stage base × Nut)

* **`pnNut` effect:**

  * `pnNut 9 1` → ADG ≈ stage base (e.g., \~0.90 for heifers)
  * `pnNut 9 0.25` → ADG drops to \~¼
  * `pnSim 9 0.5d` then `pnBeat 9` → avgW increases accordingly

---

## How PN Is Calculating (Phase 1)

* PN infers **species** and **average age** per barn from cluster fields or by weight estimation.
* It selects a **stage** (Option A; from `PN_Settings.lua`) and reads **baseADG** for that stage.
* Your **Nut ratio** (0–1) scales baseADG → **effective ADG**.
* On the **server**, PN applies a **per-tick weight delta** to each live animal cluster:
  `∆kg/head = ADG * (dtMs / 86,400,000)`

*(In this phase, Nut is tester-controlled via `pnNut`. The feed-intake driven Nut% comes next.)*

---

## Suggested Test Scenarios

1. **Sanity**

   * `pnDumpHusbandries`
   * `pnOverlay` (Alt+N also)
   * `pnOverlayMine on`
   * `pnBeat <myIndex>`

2. **Full nutrition**

   * `pnNut <myIndex> 1`
   * `pnSim <myIndex> 6`
   * `pnBeat <myIndex>` → avgW should go up

3. **Low nutrition**

   * `pnNut <myIndex> 0.25`
   * `pnSim <myIndex> 12`
   * `pnBeat <myIndex>` → smaller avgW increase, ADG quartered

4. **Different species**

   * Add sheep/pigs/chickens; repeat the above with those indices.
   * Confirm species tag and plausible ADG for their stages.

---

## Troubleshooting

* **Overlay shows nothing (headers only):**

  * Press **Alt+N** again.
  * Run `pnDumpHusbandries` to confirm detection.
  * If you see barns listed but not on overlay, they might not be yours—use `pnOverlayMine all`.

* **Console says “command not found”:**

  * Ensure PN loaded with **no Lua errors** above the registration lines.
  * `PN_Debug.lua` must be sourced (it is in current build).

* **No weight change after `pnBeat`:**

  * `pnBeat` uses a tiny `dt` (frame-like); use `pnSim` to fast-forward hours.
  * Or wait for real time with overlay on; set Nut high and check later.

* **Font warning (`Character '916' not found`)**:

  * Ignore if you see it once; we’ve removed `Δ` from logs. If your local copy still prints it, update PN\_Debug’s sim log to use `dT=` (ASCII).

* **MP note:**

  * Weight changes apply **server-side only**; clients still see overlay, but weight writes only happen when `g_server` is true.

---

## Useful Config Tweaks (optional)

* **Heartbeat frequency:** `pnHeartbeat 3000` (ms) or `pnHeartbeat off`
* **Overlay scope default:** in `PN_UI.lua`, set `PN_UI.onlyMyFarm = true|false`
* **Decimal precision:** in `PN_Core.updateHusbandry` heartbeat log, change `avgW=%.2fkg` as preferred.

---

## Next Steps (for devs)

* Replace manual `pnNut` with a **calculated Nut%** from actual feed consumption.
* Map **fillTypes → nutrient buckets** per species/stage; compare to **targets** (see `PN_Settings.lua`).
* Feed-driven Nut% will automatically drive ADG without console intervention.

---

### Appendix: Sample Session

```
> pnDumpHusbandries
[PN] ---- PN Husbandries ---- count=22
[PN] 009 | farm=1 | type=ANIMAL | cluster=yes | Timber Sage Cow Stall
...

> pnOverlayMine on
[PN] Overlay ownership filter now: My Farm Only

> pnNut 9 1
[PN] Barn 'Timber Sage Cow Stall' nutrition ratio set to 100%

> pnSim 9 6
[PN] Timber Sage Cow Stall [COW] | head=15 (M:4 / F:11, preg=1) avgW=403.00kg | Nut=100% | ADG=0.90 kg/d
[PN] SIM 'Timber Sage Cow Stall' COW | dT=6h | Nut=100% | ADG=0.90 kg/d | head=15 avgW=403.228 kg

> pnBeat 9
[PN] Timber Sage Cow Stall [COW] | head=15 (M:4 / F:11, preg=1) avgW=403.23kg | Nut=100% | ADG=0.90 kg/d
```

