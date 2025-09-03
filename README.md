# Precision Nutrition (FS25)

**Nutrition-aware growth for cattle in Farming Simulator 25.**

This gameplay mod links your barn’s feed supply directly to **Average Daily Gain (ADG)** and weight change. If animals run out of feed, growth halts and weight begins to decline. This alpha release is stable and usable, but not yet feature-complete.

---

## ✨ Features (v0.3.2-alpha)

* **Nutrition → Growth:** Barn-level nutrition ratio drives ADG.  
* **Safe trough behaviour:** Empty troughs force `Nut = 0 → ADG = 0 → avgWeight` declines.  
* **Stage-aware baseline:** Growth varies by stage (lact, gest, bull) with conservative defaults.  
* **Realistic Livestock integration:** Detected automatically; PN applies compatibility multipliers.  
* **Console command support** for testing (`pnClearFeed`, `pnDumpHusbandries`, `pnInspectTrough`, `pnFindFeeder`, `pnBeat`, `pnHeartBeat`).  

⚠️ **Limitations in this build:**  
- All feed is treated as generic “forage.” Specialised food groups (energy grains, protein grains, fibre, starch) will arrive in later builds.  
- Barns that only accept `FORAGE` cannot yet display which ingredients were used.  
- Overlay is minimal, primarily for debugging.  

---

## 📦 Installation

1. Download the latest release ZIP and place it in:

```

Documents/My Games/Farming Simulator 25/mods

```

2. Enable **Precision Nutrition** in the mod list.  
3. Optional: also enable **Realistic Livestock** — PN will adapt automatically.  
4. On save load, look for:

```

\[PN] Precision Nutrition ready.
\[PN] Realistic Livestock detected: applying compatibility multipliers.   (if applicable)

````

---

## 🎮 Console Commands (0.3.2-alpha)

> **Tip on `<index>`:** Run `pnDumpHusbandries` first to list PN entries and their indices. Most commands take that index.

## Discover & export

* **`pnDumpHusbandries`**
  List PN-scanned husbandries with index, farmId, type, and cluster presence.

* **`pnDumpHusbandriesCSV`**
  Export the list to `PN_Husbandries.csv` in your **modSettings** folder.

## Inspectors

* **`pnInspect <index>`** *(alias of `pnInspectHusbandry`)*
  Inspect a PN entry: basic info, state, and wiring.

* **`pnInspectHusbandry <index>`**
  Same as above; explicit name.

* **`pnInspectClusters <index>`**
  Dump cluster membership/details for the entry.

* **`pnInspectTrough <index>`**
  Show fillUnits and current trough levels; prints accepted fillTypes if available.

* **`pnInspectFoodSpec <index>`**
  Dump `spec_husbandryFood` levels the barn exposes.

* **`pnFindFeeder <index> [radiusMeters]`**
  Locate the nearest feeder (fillUnit) placeable for the entry. Optional search radius.

## Simulation & beats

* **`pnBeat <index>`**
  One-shot PN update tick for that entry (refreshes nutrition snapshot and prints a line if formatter is present).

* **`pnSim <index> <hours|e.g. 6 or 0.5d>`**
  Simulate PN over a span (hours or fractional days like `0.5d`) for the entry.

* **`pnHeartbeat <ms|'off'>`**
  Set global heartbeat period in **milliseconds** (minimum 100). Use `off` to disable.
  Examples: `pnHeartbeat 1000`, `pnHeartbeat off`.

## Feed & nutrition control

* **`pnClearFeed <index> [percent 0..100]`**
  Reduce/clear trough feed. `100` clears all.
  Example: `pnClearFeed 9 100`.

* **`pnNut <index>`**
  Show the barn’s current nutrition ratio (0..1).
  *(This command can also set/view in some builds; in 0.3.2 it reports.)*

* **`pnCredit <index> <FILLTYPE_NAME> <kg>`**
  Credit one-off intake to a barn and run a heartbeat.
  Example: `pnCredit 10 WHEAT 250`.

* **`pnAutoConsume <on|off>`**
  Toggle PN’s auto consumption shim on/off.

* **`pnIntakeDebug <on|off>`**
  Toggle verbose intake logging.

> *Note:* There are internal helpers in the file (`pnSetMix`, `pnClearMix`, `pnShowMix`) but they are **not registered as console commands** in this release.

## Overlay & UI

* **`pnOverlay`**
  Toggle the PN overlay on/off.

* **`pnOverlayMine <on|off|all>`**
  Filter overlay to your farm only (`on`) or show all farms (`off`/`all`).

## Reload & logging

* **`pnPNReload`**
  Reload PN settings/XML packs and re-init core.

* **`pnSetLogLevel <TRACE|DEBUG|INFO|WARN|ERROR>`**
  Switch PN\_Logger verbosity at runtime.

## Diagnostics & repair

* **`pnDiag`**
  Print PN module readiness (what’s loaded, counts, etc.).

* **`pnFixEvents`**
  Restore `PN_Events` methods if something clobbered them.

---

# Optional: Conflict-Probe commands (disabled by default)

> Enable by uncommenting the `PN_ConflictProbe.lua` `<sourceFile>` line in `modDesc.xml`.

* **`pnProbeOn` / `pnProbeOff`** — Enable/disable probe logging.
* **`pnProbeReport <index> [seconds]`** — Report recent events for a barn.
* **`pnProbeBarns`** — List barns with no consumption over the last N hours.
* **`pnProbeTrace <index> [seconds]`** — Start a 1 Hz trace for a barn.
* **`pnProbeTraceStop <index>`** — Stop the trace and print a summary.
* **`pnProbeTraceRpt <index>`** — Print the current trace summary.
* **`pnProbeHooks`** — Show which engine hooks are currently installed.

---

⚠️ **Note:** Some commands are primarily debugging tools. Normal gameplay will run PN updates automatically — you don’t need to use these unless testing or troubleshooting.

---

## 🧪 Evaluating in a Live Save

1. **Check load messages** in `game.log.txt` (“Precision Nutrition ready”).
2. **Feed cattle** (hay/silage): `Nut > 0`, ADG becomes positive.
3. **Starvation test:** Run `pnClearFeed <barnId> 100`.

   * Nutrition ratio drops to 0.
   * ADG drops to 0.000.
   * Average weight begins to decline.
4. **Persistence:** Save and reload → verify values remain consistent.
5. **With Realistic Livestock:** Compare growth/weight trends vs. vanilla FS25.

---

## ✅ Compatibility

* **FS25 PC/Mac** (tested SP; MP safe but sync not yet finalised).
* **Realistic Livestock:** detected and integrated.
* Compatible with custom maps and fillTypes — unsupported crops are ignored gracefully.

---

## 🧭 Roadmap

* Specialised food groups (energy/protein grains, fibre, starch).
* Ingredient mix tracking even for `FORAGE`-only barns.
* Expanded overlay for diet quality and intake/head/day.
* Species beyond cattle (sheep, pigs, goats).
* UI hooks for sale-time grading.

---

## 🙌 Credits

* **Design & testing:** SimGamerJen (Buffalo Ridge Ranch, Judith Plains)
* **Implementation support:** GPT-5
* Thanks to the FS modding community and the authors of Realistic Livestock for inspiration.

---

## 🧾 Changelog

* **0.3.2-alpha** — Stable baseline; farmhouse deletion fixed; husbandry scan stable; all console commands documented.
* **0.3.0-alpha** — First stable pre-release; core nutrition → ADG pipeline working, RL multipliers applied, trough clearing safe.
* **0.2.x.x** — Experimental builds, not publicly released.
* **0.1.0.x** — Early prototypes, overlay testing, safer hooks.
