# Precision Nutrition (FS25) — Usage Guide

This document explains **how Precision Nutrition works**, how to **use the console commands** for testing, and what to **look out for in a live scenario**.

---

## 🔍 How it Works (v0.3.0-alpha)

Precision Nutrition hooks into the animal feeding logic in FS25. Instead of all feed being equal, it tracks the **nutrition ratio** at the barn level and scales **Average Daily Gain (ADG)** accordingly.

- **Nutrition Ratio (`Nut`)**
  - Value between `0.0` and `1.0`.
  - Represents how close current feed intake is to stage needs.
  - In this alpha, all forage is treated equally.

- **Average Daily Gain (`ADG`)**
  - Expressed in `kg/day`.
  - Higher when nutrition ratio is good.
  - Falls to `0` if troughs empty.

- **Average Weight (`avgW`)**
  - Mean body weight of animals in the barn.
  - Rises steadily with positive ADG.
  - Falls gradually if ADG = 0 for extended periods.

- **Realistic Livestock (RL) Integration**
  - If RL is active, PN applies multipliers so growth isn’t double-counted.
  - RL’s extended attributes (health, fertility, metabolism, etc.) remain in play.

---

<img width="1927" height="729" alt="image" src="https://github.com/user-attachments/assets/b9d61656-5395-4738-a63c-69469fbdb850" />

---
## 🎮 Console Commands

Precision Nutrition ships with console commands for **debugging and testing**.  
Enable the developer console in FS25 to use them.

---

### `pnClearFeed <barnId> <percent>`

**Purpose:** Reduce or clear feed from a barn’s troughs.  
Useful for testing starvation and recovery scenarios.

- **Parameters:**
  - `barnId` → Internal FS25 husbandry ID. Find it in the log on load:
    ```
    Info: [PN] Found cowHusbandryBarnMilk id=9
    ```
  - `percent` → % of feed to remove (e.g. `100` = clear completely, `50` = remove half).

- **Examples:**
  ```lua
  pnClearFeed 9 100
````

→ Clears all feed from barn ID 9.

```lua
pnClearFeed 12 50
```

→ Removes half of feed from barn ID 12.

* **Immediate Effects:**

  * `Nut` instantly drops (to 0 if cleared).
  * `ADG` falls to 0.000 when troughs empty.
  * Over time, `avgW` trends downward.

---

## 🧪 What to Look Out For

When running a live save with PN enabled:

1. **On Load**

   * Log shows:

     ```
     [PN] Precision Nutrition ready.
     [PN] Realistic Livestock detected: applying compatibility multipliers.   (if RL installed)
     ```

2. **Feeding Animals**

   * Adding hay/silage/forage → `Nut` increases above 0.
   * `ADG` rises above 0.000.
   * `avgW` gradually ticks upward.

3. **Starvation Scenario**

   * Use `pnClearFeed` to empty troughs.
   * Watch `Nut` and `ADG` instantly fall to 0.
   * After a short time, `avgW` begins to decline.

4. **Persistence Across Saves**

   * Save the game, reload, and check values.
   * Nutrition ratio, ADG, and avgWeight should remain consistent.

5. **With Realistic Livestock**

   * PN applies RL multipliers.
   * Weight gains/losses should appear more conservative than vanilla FS25.

---

## ✅ Signs It’s Working

* Feeding → `Nut > 0` and **positive ADG**.
* Clearing troughs → `Nut = 0`, **ADG = 0**, weight falls over time.
* Log confirms PN ready and RL multipliers (if applicable).
* No crashes, stalls, or runaway values.

---

## ⚠️ Known Limitations (Alpha)

* All feed types are lumped into one group (`FORAGE`).
* Ingredient-level distinctions (energy vs. protein grains) not yet implemented.
* Overlay is minimal — rely on logs and console for now.
* Sheep, pigs, and goats not tuned/tested in this build.

---

## 🔮 Coming Soon

* Specialised food groups: energy grains, protein grains, fibre, starch.
* Ingredient tracking for barns that only accept forage.
* Expanded overlay (showing diet quality and intake/head/day).
* Broader species support (sheep, pigs, goats).

---
