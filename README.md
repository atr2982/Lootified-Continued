# Lootified Continued

A community maintained continuation of Lootified for World of Warcraft: Forever. It brings dungeon bosses and loot, dungeon quests and their chains, maps, open world drops, and level aware gear recommendations into one addon. This continuation uses English text and percent based stat weights; the simulator is disabled.

Maintained by atr2982. Based on the original Lootified addon by Alen, under GPL-3.0. This repository preserves the original license and notices and marks the continuation as modified. It is independent of the original author's website and Discord support channel.

This repository contains the code and data for the private personal fork. The artist-made dungeon map assets are kept only in the local installed addon and are excluded from this GitHub repository. If they are ever distributed, permission and attribution terms should be reviewed first.

## Data status

The local installation was refreshed against Forever client build 1.60.1.70790 using `/lf collect`. The personal collection is excluded from this public repository. Dungeon drops, maps, quest prerequisites, and BiS lists still contain curated data from earlier builds and are being checked against current Forever sources. A source's Classic data must be distinguished from observations in Forever.

## Refresh workflow

The `refresh-tool/` directory contains the client collection converter and a reviewed data importer. Run the collection in game, exit or reload so SavedVariables are written, then generate the collected Lua layer locally. Public repository copies do not include account data or generated collection files.

Issues and source contributions can be tracked through this repository once published. ForeverDB sourced records will be visibly credited if its API is used.
