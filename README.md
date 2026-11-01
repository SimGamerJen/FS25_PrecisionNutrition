# Precision Nutrition 0.5.0.4-alpha

Precision Nutrition makes ration quality matter to individually tracked animals in Farming Simulator 25. This alpha is a focused integration for **FS25_RealisticLivestockRM 1.4.0.0**.

## What this build does

- Calculates energy and protein density from the feed currently stored in each husbandry.
- Selects a target for each RLRM animal from its real age, gender, lactation, pregnancy, and castration state.
- Multiplies RLRM's existing food factor by the resulting ration-quality factor.
- Leaves RLRM responsible for health, weight, reproduction, production, and animal synchronization.
- Shows a read-only native FS25 screen with ration quality, nutrient ratios, the original/effective RLRM food factors, dry matter, and herd stages.
- Populates the interface immediately from the live husbandry; it does not wait for the next RLRM hourly health update.
- Restores read-only individual development rows showing each animal's age, life stage, current/target weight, development percentage, health, ration quality, and effective food response.
- Presents those details in a native `ScreenElement` with a summary band, grouped columns, alternating rows, threshold colours, and a scrollable `SmoothList`.
- Synchronizes summary metrics from the server to multiplayer clients.

Precision Nutrition does not contain a second growth clock and does not directly edit animal weight, health, reproduction, sales, trough levels, or grazing state.

## Requirements and compatibility

- Farming Simulator 25
- FS25_RealisticLivestockRM 1.4.0.0

The dependency is intentional: PN disables itself if RLRM is unavailable. Legacy Realistic Livestock and Enhanced Livestock are not supported. Integrations with other SimGamerJen mods are future work and are not enabled in this alpha.

## Installation

1. Place `FS25_PrecisionNutrition.zip` in the Farming Simulator 25 `mods` folder.
2. Enable both Precision Nutrition and Realistic Livestock RM for the save.
3. Fully restart the game after replacing an earlier PN alpha so the native GUI XML is reloaded.

## Controls

- `Alt+N`: open the Precision Nutrition screen
- **Previous Husbandry** / **Next Husbandry**: use the native button-bar keys or controller buttons shown by FS25
- Mouse wheel, scrollbar, keyboard, or controller: scroll and navigate the animal table
- `Esc` or **Exit**: close the screen and return control to gameplay

## External configuration

Optional overrides are read from:

`modSettings/FS25_PrecisionNutrition/`

Only these files are loaded:

- `feeds.xml`: feed nutrient values and aliases
- `targets.xml`: daily energy, protein, and dry-matter targets by species/stage
- `stages.xml`: optional age/gender stage bands

Settings are authoritative on the server. Unknown feeds contribute dry matter but no energy or protein and are reported in the log and interface. `SOYBEANSTRAW` is intentionally not included in the built-in feed matrix.

Use `pnReload` after editing configuration and `pnStatus` to print the current integration and husbandry summaries to the log.

## Experimental mixer ingredient diagnostics (draft feature branch)

**Optional:** enable FS25_CustomAnimalFoodRecipes 1.0.0.0 alongside PN and RLRM. No map XML edits are required for custom recipes. PN does **not** install recipes, alter mixer fill levels, alter husbandry feeds, or use this ledger in its nutrition calculations yet.

On the authoritative server, PN observes each mixer wagon's actual accepted fill-unit volume changes and associates positive additions with the incoming fill type when that type is a recognised mixer recipe ingredient. On discharge/removal it reduces known constituents proportionally. The ledger is persisted separately in the wagon's vehicles.xml save data under mixerWagon.precisionNutrition. It is independent of the other mod's recipe snapshot.

Console commands:

- pnMixerDump — print every loaded mixer, recipe output, measured total, ingredient volumes and source quality.
- pnMixerTrace — toggle verbose event-by-event logs of accepted additions and removals (off by default; can be noisy while filling).
- pnStatus and pnReload — unchanged.

Ledger source labels:

- observed: recorded from real accepted input events, including across a save/load.
- reconstructed: recovered from wagon recipe rows when each filled row maps to exactly one fill type; this is **not** direct evidence of the original ingredients.
- incomplete: ambiguous recipe rows or volume changes outside the observed fill method; the unknown amount is shown as __UNTRACKED__.

The source label remains conservative: adding observed material to a reconstructed or incomplete batch does not retroactively establish all original ingredients. No attempt is made to infer a precise ingredient from the recipe's target ratios.

**Required in-game verification before nutrient integration:**

1. On a *copy* of a save, install the optional recipe mod, apply a recipe to an empty wagon, run pnMixerDump and confirm the wagon starts empty.
2. Run pnMixerTrace; add distinct materials (including a small amount, bales if supported and a custom recipe ingredient). Confirm recorded increases reflect **accepted** volume, not intended volume.
3. Mix and drive: verify the ledger is unchanged while the recipe is internally converted to FORAGE or a custom output type.
4. Unload half the wagon, run pnMixerDump, confirm all constituents fall proportionally and the sum matches the actual fill level. Repeat until empty, then add a new mixture.
5. Save and reload with a **partially filled** wagon. Verify the exact ingredient ledger, quality label and total survive. Check the saved vehicles.xml under the wagon's mixerWagon.precisionNutrition.
6. Load an existing wagon containing ingredients **before** the tracker was installed. Verify ambiguous rows show incomplete rather than fabricated precision.
7. Test switching recipes with an empty wagon, a full wagon, and a forced recipe change; any unobserved ingredients must remain marked as such.
8. Repeat with a multiplayer host/dedicated server; diagnostics are server-only. Confirm no game log errors, no impact on normal wagon filling/discharging, and no RLRM growth regression.

**Known limitations:** when a different mod directly changes a wagon fill level without calling the observed instance method, PN can reconcile the total but cannot know the missing ingredient; it marks that volume untracked. Multiple ingredients sharing one mixer recipe row may not be recoverable after the fact unless their inputs were observed. This branch does not yet track which husbandry receives discharged feed, nor expose ingredient nutrition in Alt+N.

## Multiplayer model

The RLRM health-update hook runs only where `g_server` exists. Clients receive read-only summaries approximately every five seconds. A client never changes animal or husbandry state through PN.

## Alpha testing focus

- Start a clean save and an existing RLRM save in single player.
- Compare TMR, hay, silage, and deliberately poor or unknown rations over several in-game hours.
- Verify lactating/dry females and intact/castrated males appear under the correct stages.
- Check `Alt+N`, husbandry cycling, `pnStatus`, and `pnReload`.
- Test a host/client session and a dedicated server, including a late-joining client.
- Save, reload, and review `log.txt` for `[Precision Nutrition]` errors or repeated hook messages.

The native screen, mouse focus, scrolling, husbandry navigation, Esc/Exit handling, final column layout, RLRM 1.4 callback integration, and uninterrupted monthly crop growth have been confirmed in game. Nutrition behaviour and multiplayer remain alpha testing areas.

## Copyright and permissions

Copyright © SimGamerJen. All rights reserved.

You may download and use this mod for personal use. You may not modify, redistribute, re-upload, or publish this mod, in whole or in part, or any derivative version without prior written permission from SimGamerJen.
