### ✅ What’s working in 0.3.2-alpha

* **Husbandry scan**: barns / pens are detected reliably, so commands like `pnDumpHusbandries` and `pnBeat` can pull info from them.
* **Feed → Nutrition mapping**: everything you dump into a trough gets translated into a nutrient vector (`energy`, `protein`, `fibre`, `starch`).
* **Nutrition ratio calculation**: the barn’s feed balance is compared against stage-specific targets (calf, grower, finisher, dry, gest, lact, bull). You’ll see a `Nut=…` % value in the console output.
* **ADG (Average Daily Gain)**: each animal group gets an **ADG (kg/day)** number computed from weight, stage, and nutrition ratio. This is stored per-barn and shown in console (e.g. `ADG=0.043 kg/d`).
* **Heartbeat / progression**: running `pnBeat` steps the model forward, so animals’ average weight increases (or drops if feed is poor/empty). This is how nutrition *actually* affects outcomes now.
* **Integration with Realistic Livestock**: PN scales against RL attributes (weight, fertility, metabolism, etc.) so they don’t conflict.

### 🚫 What’s *not* yet happening

* No in-game GUI/overlay beyond console output (nutrient ratios, ADG, weight shifts).
* No direct sale-price or condition multipliers yet — weight gain is happening, but value on sale is still vanilla.
* “Grass-fed” logic is coded, but not hooked into market prices yet.
* Enhanced Mixer Wagon (EMW) support is stubbed but buggy.

### 🤔 So, does it “make a difference”?

Yes — but right now the effect is visible **only if you look at console outputs or track weights over beats/days**.

* If you feed only hay → nutrition ratio low → ADG smaller.
* If you balance hay + silage + some protein grain → ratio closer to stage target → ADG bigger.
* If feed runs out (pnClearFeed test) → nutrition = 0 → ADG = 0 → weights begin dropping.

So while the animals in the pens look the same in-game, under the hood their **average weight and growth trajectory is being driven by nutrition quality**. Over time, this will be what drives sale value and condition.

---

👉 Next steps could be:

1. **Hook weight → sale price** so market value actually changes.
2. **Overlay / UI panel** to show ranchers nutrition, ADG, and grass-fed status without console diving.
3. **Finish EMW support** so custom rations mix down into proper nutrient balances.
4. **Add health/fertility feedbacks** (tie into Realistic Livestock deeper).
