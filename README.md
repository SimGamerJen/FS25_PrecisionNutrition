# Precision Nutrition (FS25)

**Nutrition-aware growth for cattle in Farming Simulator 25.**

This gameplay mod links your barn’s feed supply directly to **Average Daily Gain (ADG)** and weight change. If animals run out of feed, growth halts and weight begins to decline. This alpha release is stable and usable, but not yet feature-complete.

---

## ✨ Features (v0.3.0-alpha)

* **Nutrition → Growth:** Barn-level nutrition ratio drives ADG.  
* **Safe trough behaviour:** Empty troughs force `Nut = 0 → ADG = 0 → avgWeight` declines.  
* **Stage-aware baseline:** Growth varies by stage (lact, gest, bull) with conservative defaults.  
* **Realistic Livestock integration:** Detected automatically; PN applies compatibility multipliers.  
* **Console command support** for testing (`pnClearFeed`).  

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

## 🎮 Console Commands

### `pnClearFeed <barnId> <percent>`
Reduce or clear feed from a barn’s troughs.

- **barnId**: Internal FS25 husbandry ID (see logs).  
- **percent**: Percent to remove (100 = clear all).  
- **Example:**  
```lua
pnClearFeed 9 100
````

→ Clears all feed from barn ID 9.

Effect: `Nut` immediately drops to 0, `ADG` goes to 0, and animals’ average weight trends downward.

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

* **0.3.0-alpha** — First stable pre-release; core nutrition → ADG pipeline working, RL multipliers applied, trough clearing safe.
* **0.2.x.x** — Experimental builds, not publicly released.
* **0.1.0.x** — Early prototypes, overlay testing, safer hooks.
