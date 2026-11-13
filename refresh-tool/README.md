# Lootified Refresh Tool

This tool stages verified Forever data for review. It does not scrape arbitrary websites and does not overwrite the live addon automatically.

## The data flow

`/lf collect` is still useful. It asks the live Forever client/server for facts the addon cannot reliably get from a website: item tooltip data, quest facts and rewards, NPC names/lines, and current build-specific answers. After the collection finishes:

1. Type `/reload` in WoW.
2. Copy `WTF\Account\<account>\SavedVariables\LootifiedContinued.lua` to a work folder.
3. Supply a reviewed Forever JSON export from the web sources.
4. Run the tool to create a staged Lua file.
5. Review the diff and only then merge it into the addon data files.

## Example

```powershell
node refresh_tool.js `
  --collect-file .\LootifiedContinued.lua `
  --web-data .\forever-verified.json `
  --output .\staged\RefreshOverrides.lua
```

The web JSON schema is intentionally explicit. Use numeric ID keys for `items`, `item_stats`, `quests`, and `world_drops`; include the current Forever build; and include provenance fields for every imported record when possible.

The current addon ships generated static data from its earlier pipeline. The override file lets us update reviewed records without hand-editing those generated files. For a major rebuild, we can later replace the override with a full regeneration of `Items.lua`, `ItemStats.lua`, `Quests.lua`, `Instances.lua`, `WorldDrops.lua`, and `BiS.lua`.

## Rebuild the client collected layer

Run `node build_collected.js SAVED_VARIABLES OUTPUT_LUA` using the completed account SavedVariables file. This generates `Data/CollectedOverrides.lua` with the answered items, weapons, item names, and quest facts. Keep its TOC entry after the base data files and before `Data/RefreshOverrides.lua`. The client refused thousands of quest IDs; those remain in the curated base rather than being invented. Dungeon drops, map geometry, prerequisites, and BiS weights need separate verified data because this collection does not provide them.

After a refresh, the live addon reports the verified data build through `LJ.DATA_BUILD`, `LJ.DATA_CHECKED`, and `LJ.DATA_STATUS`. The tool does not treat a search result or arbitrary web scrape as truth: imported records must be reviewed, carry a Forever build, and should include provenance URLs. Client collection remains the authoritative source for build-specific tooltip and quest facts; public databases are reviewed cross-checks and cover server-side content the client cannot expose.

## ForeverDB snapshot

`fetch_foreverdb.js` reads `FOREVERDB_API_KEY` from the local environment and writes a packaged `Data/ForeverDB.lua` snapshot. The key is never written to the repository or addon. ForeverDB data is credited in the addon and supplies current item metadata, quest records, and dungeon catalog data; the client collection remains the source for tooltip stats.

```powershell
$env:FOREVERDB_API_KEY = "your-local-key"
node refresh-tool/fetch_foreverdb.js LootifiedContinued/Data/ForeverDB.lua
node refresh-tool/fetch_dungeon_details.js LootifiedContinued/Data/ForeverDBDungeons.lua
node refresh-tool/fetch_web_bis.js LootifiedContinued/Data/WebBiS.lua
```

The BiS refresh reads the current Forever-specific gear pages from [WoW Forever Forge](https://wowforeverforge.com/bis/), preserves the addon’s existing alternatives, and prepends current guide picks when they are not already present. Dungeon detail refreshes add current ForeverDB status, ranges, bosses and notable loot without replacing detailed boss tables that still need item-by-item confirmation.

## Static dungeon loot tables

Dungeon loot does not require personally running every dungeon. The refresh
workflow uses the published Forever Atlas tables as the primary static loot
cross-check, then compares them with ForeverDB, the client collection, and
other Forever-specific references. The current addon tables already include
the verified Forever Atlas boss drops; entries that Forever Atlas marks as
unknown or source-pending are not guessed into a boss table.

Forever Atlas is GPL-2.0. Keep the attribution and license notice in
`THIRD_PARTY_NOTICES.md` if its data or code is redistributed.
