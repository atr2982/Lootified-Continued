# Lootified

Lootified is an English-only, lightweight loot and progression journal for WoW: Forever. It brings dungeon quests, quest chains, boss loot, open-world drops, and level-aware gear upgrades together so you can see what is worth doing next without juggling several database addons.

## What it does

- **Dungeon journal:** Browse dungeons by level, faction, and role with bosses, loot tables, quest rewards, and quest chains in one place.
- **Quest-chain guidance:** See which dungeon quests are available, in your quest log, ready to turn in, or blocked by earlier prerequisites. Forever-specific quest data is kept separate from unverified records.
- **Loot and reward comparison:** Review boss drops, quest choices, world drops, and crafted items against your current character and see percentage-based upgrade values.
- **Best in Slot:** View level-aware recommendations for your class and specialization, with sources such as dungeons, quests, open-world drops, and professions identified where available.
- **Open World:** Browse zone-based rare and world-drop opportunities, with upgrade filtering for your current character.
- **Quest and world-map pins:** Keep useful quest and location markers available while avoiding unnecessary dungeon-map artwork and map UI.
- **Forever client data:** Uses the WoW: Forever client’s collected data and reviewed Forever-specific sources so the addon can track server changes as the game develops.

## Designed to stay lightweight

Lootified focuses on lookup, planning, and upgrade comparison. It uses English text, avoids language packs and dungeon-map assets, and keeps the main journal, Open World, and Best in Slot pages focused on the information you need while leveling.

## Maintained data

The data layer is refreshed for WoW: Forever builds and checked for duplicate quest rewards, duplicate dungeon entries, quest-chain mistakes, and mismatches between client observations and Forever-specific sources. The addon’s code and UI are kept stable during data refreshes so updates do not unnecessarily change how the journal works.

The original license, notices, and attribution remain in the repository files.

## Current data

The local installation and repository data are refreshed against Forever client build 1.60.1.70862 using `/lf collect`. The packaged snapshot combines client-collected facts with refreshed ForeverDB catalog and dungeon-detail data, verified Forever Atlas dungeon tables, and the latest accessible Forever-specific BiS guide snapshot. Personal account collection data is excluded from this public repository.
