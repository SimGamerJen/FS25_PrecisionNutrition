# Precision Nutrition (FS25)

**Nutrition-aware growth for beef cattle in Farming Simulator 25.**
This gameplay mod turns your cow feed mix into actual growth, condition, and sale-value outcomes—so **forage vs. grain choices matter**. Safe patching only: **no base game files are edited.**

---

## ✨ Features

* **Diet → Growth maths:** Every feed (grass, hay, silage, peas, barley, etc.) maps to a nutrient vector *(energy / protein / fibre / starch)*. Daily intake and balance against stage targets yield **Average Daily Gain (ADG)**.
* **Stage-aware:** Targets for **calf / grower / finisher / dry** with tunable intake ranges.
* **Grass-fed logic:** Maintain ≥80% forage for ≥120 game-days to earn a **grass-fed bonus** on sale; a short grain finish boosts gain but may forfeit the badge.
* **Grain nuance:** Distinguishes **protein grains** (e.g., peas, lentils, chickpeas, *fodder peas* / DRYPEAS, pinto beans / BEANS) from **energy grains** (e.g., barley, wheat, triticale, maize).
* **Overlay (Alt+N):** In-game debug HUD showing **Stage, ADG, Intake/head/day, Diet Balance, Forage %** per barn.
* **Map-agnostic & safe:** Wraps husbandry feeding update; respects your existing **animalFood.xml** and recipes (incl. custom groups like `proteinGrain`, `energyGrain`, `basicGrain`).
* **Compatibility mode:** Detects **Realistic Livestock** and scales baselines to avoid double-counting growth.

---

## 🧩 How it works (short version)

1. PN samples what your barn actually consumed since the last tick.
2. It mixes nutrient vectors for those **fillTypes** (e.g., `FORAGE`, `SILAGE`, `TRITICALE`, `PEA`, `DRYPEAS`…).
3. It compares the mixed diet to stage targets → **Balance score (0–1)**.
4. It evaluates **Intake/head/day** vs stage min–max.
5. **ADG = baseADG(stage) × IntakeScore × BalanceScore × starch penalty**, capped.
6. Weight and a simple BCS proxy update over time; sale price can be adjusted by band/label.

---

## 📦 Installation

1. Download the latest release ZIP and place it in:

   ```
   Documents/My Games/Farming Simulator 25/mods
   ```
2. Enable **Precision Nutrition** on your save.
3. Optional: keep **Realistic Livestock** enabled; PN will auto-adapt.
4. Load the save—look for:

   ```
   [PN] Precision Nutrition ready.
   [PN] Realistic Livestock detected: applying compatibility multipliers.   (if applicable)
   ```

---

## 🎛 In-game overlay

* **Toggle:** `Alt + N`
* **Shows:** `Stage | Cows | ADG (kg/day) | Intake (/hd/day) | Balance | Forage %`
* Purely informational; no gameplay side-effects.

---

## 🔧 Configuration

The mod ships with sensible defaults you can tune.

### `config/feedTargets.xml`

Defines stages, target macro ratios, intake ranges, and parameters.

```xml
<precisionNutrition>
  <stages animalType="COW">
    <stage name="calf"     minAgeM="0"  maxAgeM="6"  baseADG="0.7"/>
    <stage name="grower"   minAgeM="6"  maxAgeM="18" baseADG="0.9"/>
    <stage name="finisher" minAgeM="18" maxAgeM="36" baseADG="1.2"/>
    <stage name="dry"      minAgeM="36" maxAgeM="120" baseADG="0.4"/>
  </stages>

  <targets animalType="COW">
    <target stage="calf"     energy="0.35" protein="0.22" fibre="0.28" starch="0.15"/>
    <target stage="grower"   energy="0.37" protein="0.20" fibre="0.28" starch="0.15"/>
    <target stage="finisher" energy="0.42" protein="0.17" fibre="0.21" starch="0.20"/>
    <target stage="dry"      energy="0.30" protein="0.16" fibre="0.44" starch="0.10"/>
  </targets>

  <intakes animalType="COW">
    <intake stage="calf"     min="6"  max="10"/>
    <intake stage="grower"   min="10" max="16"/>
    <intake stage="finisher" min="12" max="20"/>
    <intake stage="dry"      min="8"  max="12"/>
  </intakes>

  <params>
    <dietPenaltyK value="0.85"/>
    <starchUpper  value="0.25"/>
    <adgCap       value="1.6"/>
    <grassFedFlag minGrassShare="0.80" minDays="120"/>
  </params>
</precisionNutrition>
```

### `scripts/PN_FeedMatrix.lua`

Maps **fillTypes** to nutrient vectors. Includes **PEA** (base peas), **DRYPEAS** (fodder peas), **BEANS** (pinto beans), etc.
Add or tweak entries to match your map’s crops.

```lua
PN_FeedMatrix = {
  -- forages
  GRASS_WINDROW      = {energy=0.30, protein=0.12, fibre=0.48, starch=0.10},
  SILAGE             = {energy=0.38, protein=0.15, fibre=0.40, starch=0.07},
  -- energy grains
  BARLEY             = {energy=0.49, protein=0.11, fibre=0.11, starch=0.29},
  TRITICALE          = {energy=0.49, protein=0.13, fibre=0.10, starch=0.28},
  MAIZE              = {energy=0.55, protein=0.09, fibre=0.06, starch=0.30},
  -- protein grains / pulses
  PEA                = {energy=0.41, protein=0.24, fibre=0.21, starch=0.14},
  DRYPEAS            = {energy=0.42, protein=0.25, fibre=0.20, starch=0.13},
  BEANS              = {energy=0.41, protein=0.26, fibre=0.20, starch=0.13},
  LENTILS            = {energy=0.40, protein=0.24, fibre=0.21, starch=0.15},
  CHICKPEAS          = {energy=0.41, protein=0.23, fibre=0.21, starch=0.15},
  -- fallback for TMR recipe
  FORAGE             = {energy=0.36, protein=0.17, fibre=0.36, starch=0.11},
}
```

### Optional user overrides

`modSettings/FS25_PrecisionNutrition/userOverrides.xml` – keep personal tweaks per save.

---

## 📁 Mod layout

```
Precision Nutrition/
├─ modDesc.xml
├─ scripts/
│  ├─ PN_Load.lua              # bootstraps, sets PN_MODDIR, hooks overlay
│  ├─ PN_Core.lua              # maths & stage logic
│  ├─ PN_Settings.lua          # loads XML config & RL compat
│  ├─ PN_FeedMatrix.lua        # nutrient vectors per fillType
│  ├─ PN_HusbandryPatch.lua    # safe wrapper over feeding update
│  ├─ PN_Compat_RL.lua         # Realistic Livestock adapter
│  ├─ PN_UI.lua                # Alt+N overlay
│  └─ PN_Events.lua            # (stub) MP sync hook points
├─ config/
│  ├─ feedTargets.xml          # stages, targets, intakes, params
│  └─ priceCurves.xml          # optional sale bands/labels
└─ modSettings/FS25_PrecisionNutrition/
   └─ userOverrides.xml
```

---

## ✅ Compatibility

* **FS25 PC/Mac** (SP & MP; MP events currently stubbed but safe).
* **Realistic Livestock**: detected automatically; PN lowers base ADG and caps accordingly.
* **Animal Food Overview**: fully compatible (read-only UI in that mod).

> PN inspects active *fillTypes* at runtime, so disabled crops (e.g., `GREENBEANS`) are ignored cleanly.

---

## 🧪 Verifying it works

* On load, check the log for:

  ```
  [PN] Precision Nutrition ready.
  ```
* Toggle **Alt+N** to watch barn stats as you feed.
* Run a quick A/B:

  * **Forage-only** a few in-game days → steady ADG, high Forage%.
  * **Short grain finish** (e.g., barley/maize via FORAGE) → ADG jumps; Balance and Forage% reflect the change.

---

## 🛠 Troubleshooting

* **No overlay / nothing appears:** ensure the mod is enabled and try **Alt+N**; if rebinding is needed, open an issue and we’ll switch to an action-binding approach.
* **Spam about XML functions:** usually a missing `config/feedTargets.xml` path; PN now guards this, but if you still see it, confirm the file exists and the mod is not unpacked incorrectly.
* **“Husbandry module not found”:** FS25 builds differ—PN searches for `HusbandryModuleFeeding` and cousins. If a custom map moves things further, open an issue with your log.

---

## 🧭 Roadmap

* Sheep & pigs nutrition (lighter model).
* Proper sale-time grading UI hook (using `priceCurves.xml`).
* MP state sync events (weight/BCS) finalisation.
* Per-barn config overrides in-game.

---

## 🤝 Contributing

PRs and issues welcome!
Helpful contributions include:

* Nutrient vector refinements for mod crops
* Map-specific feeding accessors
* Balance & parameter presets for different beef systems

---

## 📜 Licence

MIT (or project’s chosen licence). Include a `LICENCE` file in the repo if you prefer different terms.

---

## 🙌 Credits

* **Design & testing:** SimGamerJen (Buffalo Ridge Ranch, Judith Plains)
* **Implementation support:** GPT-5 Thinking
* Thanks to the FS modding community and authors of Realistic Livestock for inspiration.

---

## 🧾 Changelog

* **0.2.0.1** - Resolved inability to find husbandries, animal sheds, and placeables
* **0.1.0.3** — Added Alt+N debug overlay; safer hooks & guards.
* **0.1.0.2** — Robust file paths, XML nil-safety, broader husbandry hook.
* **0.1.0.1** — Fixed Lua `require` usage; global feed matrix; small patch syntax fix.
* **0.1.0.0** — Initial working prototype.
