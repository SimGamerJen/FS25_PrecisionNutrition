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
