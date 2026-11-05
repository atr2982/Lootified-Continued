# Lootified

**Loot journal & Best in Slot for WoW: Forever**: every boss and rare, every drop with its drop chance, every dungeon quest, a Best-in-Slot list the simulator builds for your level from every item you can wear, in three looks: Modern, Classic (dark leather with gold titles, every dungeon as a picture) or Database (look up every item, mob, quest and place with search and filters).

## Version 1.2.0

This upload collects the versions 1.6.3 to 1.6.9 below and more:

- **Ten languages:** besides English, German and Russian now French, Spanish (Spain and Latin America), Portuguese (Brazil), Korean and Chinese (traditional and simplified). The names of quests, NPCs, items, dungeons and zones come from the WoW: Forever game in that language. Korean and Chinese can be chosen in a client of that language (only its font has their letters). Searches find names without their accents ("defias" finds Défias).
- **City of Dalaran is open:** its 8 bosses with all 26 drops seen in the beta and their drop chances, its 8 quests (Alliance and Horde) and the quests that lead in (the Dalaran Sewer Key), and the dungeon map with every boss and the entrance on both floors (the Underbelly and the city).
- **Updated for the game build 1.60.1.70291:** the items, quests and names of the new client (58 items new, 256 changed: quality, stats, binding).
- **Zoom the window by its corner:** drag the grip at the bottom right and the whole window grows or shrinks, from 70 % to 150 %, text and pictures with it, in all three looks. Its top left stays where it is, and it keeps its size and place. The Window size buttons in the settings still work.
- **Smoother while gathering and crafting:** a profession skill-up no longer makes Lootified rank every item again. Only a skill-up that reaches a rank an item asks for (Engineering 245 for the Green Lens, for example) does; before, the next item tooltip after every skill-up took the extra time.
- **Checked for frame rate:** with the window closed Lootified runs nothing per frame; the game's events and item tooltips cost it a fraction of a millisecond.
- **Stat weights from Icy Veins for every spec** (Balance and Restoration Druid from foreverchanges.pro); tanks follow it too (threat first).
- **Stat priority only with Percent;** with Sim the simulator rates your items.
- **The filter explains itself:** a tour step shows its button, and the panel explains its parts the first time you open it.
- **The first start asks for Standard (Percent) or Advanced (Sim, Beta);** Percent shows no Best in Slot sim buttons.
- **Crafted items are no longer in the list at the start** (switch them on in the filter when you craft).
- **Set 1 and Set 2 always on the Best in Slot page,** empty until you put items in them. On a set, the list of a slot with an item starts with None: it takes the item out of the set.
- **The drop chance is a slider.** "Only good drops" in the filter (and at the first start) is now a slider from All drops to 50 % (10 % to start with, the mouse wheel moves it by 1 %). Had you switched Only good drops off, it starts at All drops. Drops without a known chance always count, trash drops too. A Best in Slot sim from before says it is outdated once: the list changed.
- **The minimap button switch moved** from General to Look & color in the settings.
- **The slot list is a bit wider:** its armor chips fit in one row (German and the classic look too).
- **Fix:** opening the simulator could end in an error ("stack overflow"). The dungeon map's loot follows a finished sim and the switch between Percent and Sim.
- **Fix:** in the classic look the filter's Done button stuck out below its panel in German, French, Portuguese and Russian. The buttons now stay inside it in every language.
- **Behind the scenes:** `/lf collect`, the data collect behind the translations, now asks the game about every item and every quest it knows (about 32,000 items and 6,700 quests), not only the ones Lootified lists.

## Version 1.6.9

- **Own sets stay empty until you fill them.** A click on an empty Set 1 or Set 2 shows it empty, with a line that says how it gets items: click a slot and pick an item. (1.6.8 filled it with your Best in Slot list.)

## Version 1.6.8

- **Your own sets on the Best in Slot page from the start.** Set 1 and Set 2 now always sit under What I wear and Best in Slot. A click on an empty set starts it as your Best in Slot list; click a slot to swap an item, and the set shows what it adds.
- **The first start's question: Standard or Advanced.** Standard (Percent) is the way for tanks, DPS and healers, with every upgrade in percent right away. Advanced (Sim) is for players who want to run sims themselves. The settings keep the names Percent and Sim; their texts no longer recommend Sim for DPS.

## Version 1.6.7

- **Percent shows no Best in Slot sim.** With Percent, the tour's welcome step and For you's next upgrades no longer show the Best in Slot sim button (it only offered the switch to Sim). With Sim they run the Best in Slot sim as before; Percent or Sim is set in the settings (General).
- **Crafted items are no longer in the list at the start.** Not everyone has the professions: the realistic list (first start, Back to realistic) takes quests, dungeons and rares; switch Crafted on in the filter when you craft. A list you already set keeps its choice.

## Version 1.6.6

- **Fix: opening the simulator could end in an error ("stack overflow").** When the Character tab needs a taller window, the window grows to fit it. The game can report the new height a hair lower than it was given, and the window then grew again and again. It now grows once, and the two cards under the Character tab show reliably too.

## Version 1.6.5

- **The filter explains itself.** The tour has a new Filter step on the Best in Slot page that shows the filter's button. The first time you open the filter it explains itself with the spotlight: the spec, the armor and sources (with Back to realistic) and, with Percent, the Stat priority tab. Each part once; starting the tour again (/lf tour) shows it again.

## Version 1.6.4

- **Stat priority only with Percent.** With Sim the simulator rates your items, so the filter has no Stat priority tab and your order counts nowhere: what the sim has no number for yet (the list before your first sim, tooltips of items not simmed) goes by your spec's own weights. Your order is kept: back on Percent it counts again.
- **Dungeon map:** its open loot follows a finished sim and the switch between Percent and Sim at once.

## Version 1.6.3

- **Stat weights from Icy Veins for every spec.** Every spec now takes its stat order from its Icy Veins WoW: Forever guide (Balance and Restoration Druid from foreverchanges.pro: Icy Veins ranks no stats for them). Per item budget the first stat counts most and each next one 0.8 of the one above; stats the guide does not name count very little. Weapon damage, attack power and spell school damage follow the stat they come from. Your list can change for every spec.
- **Tanks follow Icy Veins too:** its Protection Warrior and Feral lists rank threat first. Defense, dodge, parry and block now count very little for a Protection Warrior; the Bear takes the Feral list, so armor, Defense and dodge count very little for it.
- A stat priority saved before goes back to the default when it no longer fits the new weights.

## Version 1.6.2

- **Stat weights from the core sources.** Paladin (Holy, Protection, Retribution), Priest (Discipline, Holy, Shadow) and the Balance, Bear and Restoration Druid now take their stat order only from foreverchanges.pro's level-30 lists (before: a community scale made for another addon). What a list names first counts most, the next stats 3/4 and 1/2 of it per item budget; stats it does not name count a little. Your list for these specs can change.
- **The Stat priority tab compares by item budget.** Bars and order now weigh each stat by what an item gives of it for the same budget (from the game's item data), the way the specs' weights are made, so the tab shows the spec's own order.
- A stat priority saved in 1.6.1 for these specs goes back to the default when it no longer fits the new weights.

## Version 1.6.1

- **Stat priority: only what you drag changes.** Swapping two neighbours could change the other one in 1.6.0; now the stat you drag takes its new place's value and every other stat keeps its own. Put back in the spec's own order, everything is exactly the default again.
- **Stat priority with Sim:** the tab says it: Sim rates by the simulator's DPS; your order counts for the items not simmed yet (the list before your first Best in Slot sim, tooltips of items the sim has no number for).
- **Open boxes follow the filter.** The upgrade box (Alt+Click, loot rolls) and the dungeon map's loot update at once when you change the filter or the stat priority.

## Version 1.6.0

- **Your own stat priority.** The filter now has two tabs: Filter and Stat priority. Stat priority lists your spec's stats top down, each with a bar of what it is worth. Drag a stat up or down and your list, For you and the Percent numbers follow at once: only the stat you moved changes (it lands between its new neighbours), "Default order" brings your spec's own order back. Saved per character and spec; Sim keeps rating by real DPS.

## Version 1.5.0

- **Armor in the filter.** The filter (and the first start's question) now also picks the armor your list takes: Cloth, Leather, Mail, Plate, only the kinds your class wears. Switch off what you don't want (say everything but Plate) and the list, For you, the upgrade marks and the sims leave it out of head to feet; cloaks always count. The filter's button names the kinds you kept.

## Version 1.4.9

- **Filter in the middle.** On the Best in Slot page the filter's button sits in the middle above your character.
- **No "..." menu.** The Best in Slot header no longer has it: a right click on an item puts it on your wishlist (its menu also previews it in the Dressing Room).

## Version 1.4.8

- **Your list, your sources.** The first start now also asks what your Best in Slot list may use: quests, dungeons, rares, crafted items (every profession) and world drops, plus "Only good drops (10 %+)". It starts realistic (no random world drops, no drops under 10 %) and counts for the whole addon: the list, For you, the upgrade marks and the sims. A sim made with another list says it is outdated.
- **Filter on the Best in Slot page.** A button at the top shows your spec and your sources; a click opens a panel at the right: pick your spec, switch sources on and off, "Back to realistic". The class list on the left is gone: the page shows your own character.
- **Simpler slot list.** A click on a slot lists your list's items for it with a search that finds names and sources ("Blacksmithing", "Scarlet"), one row of armor chips (Cloth, Leather, Mail, Plate, each with its count) and "Higher levels" at the bottom.

## Version 1.4.7

- **Blacksmithing counts.** Blacksmithing items are on the Best in Slot list like quest rewards and good drops: WoW: Forever's professions make them easy to come by (the ones bound on pickup by learning Blacksmithing yourself).
- **Tanks: no empty slot for lack of heavy armor.** A tank's slot takes the heaviest armor it can really get there: a protection paladin without mail shoulders at its level gets Blacksmithing mail, without those leather, then cloth. A slot stays empty only when nothing at all is there for its level (like a level 20 paladin's head).

## Version 1.4.5

- **Percent shows its numbers everywhere.** With Percent, For you, the journal and every list show what an upgrade adds to your gear ("+2.4%") instead of "BiS"; the next upgrades come biggest first.
- **The planner rates sets in Percent.** A set shows what it adds by your stats and each of its items what it adds in its slot, right away, no sim needed. Sim my set still adds the DPS.
- **Tanks: lighter armor is no upgrade.** Upgrade marks, tooltips and the loot roll box follow the Best in Slot sheet: a protection paladin sees no upgrade on leather or cloth, the roll box says Greed or Pass. The upgrade marks only come from items the list takes (quest rewards you can take, good drops).

## Version 1.4.4

- **Tanks wear their heaviest armor.** Protection paladins and warriors get mail on the Best in Slot sheet, from level 40 plate; bears get leather. Lighter pieces with more Stamina are alternatives in the slot's list.
- **Quests count at most 10 levels below their own level.** A level 60 fishing quest you may take from level 1 now counts from level 50; Whirlwind Weapon (level 40, open from 30) still counts from 30.

## Version 1.4.3

- **Percent counts your whole gear.** The percent of an item is what it adds to everything you wear: an empty slot shows a number too (not only "Upgrade"), and a weak old item no longer turns a small upgrade into +1000 %. The items of a set add up to the set's total.

## Version 1.4.2

- **Best in Slot shows what you can really get.** Quest rewards you can take at your level (dungeon, open world and class quests, e.g. Whirlwind Weapon for warriors from level 30 or Verigan's Fist for paladins from level 20) and drops of 10 % or more (bosses, trash, rares and other mobs). Everything else (rarer drops, crafted, reputation and PvP items) is marked "Alternative" in the slot's list. A slot with nothing sure at your level stays empty and says so.
- A quest reward without a level of its own counts from the level its quest can be taken.

## Version 1.4.1

- **The sheet shows only what you can really get.** Every slot shows the best loot of dungeon and raid bosses or of dungeon and raid quests; boss drops below 1 % drop chance count as alternatives (nobody farms those). A slot without any stays empty and says so.
- **Alternatives in the slot's list.** A click on a slot lists every item you can wear there: trash and world drops, rares, other quests and crafted items are marked "Alternative".
- The Best in Slot sim fights only the dungeon items.

## Version 1.4

- **Best in Slot from dungeons and raids.** The list now takes the loot of dungeon and raid bosses and the rewards of dungeon and raid quests, as before only items you can wear at your level. Trash drops, world drops, rares, other quests and crafted items are the alternatives: a click on a slot lists them all, with where they drop and what they add. A slot without any dungeon item at your level shows its best alternative, marked "Alternative".
- The Best in Slot sim fights only the dungeon items in a slot that has them, so it is done sooner.

## Version 1.3.2

- **Percent or Sim per character.** Every character picks its own: the question comes once on each of them, and the settings change it for the character you play (General, "Rate items (this character)").
- **Healer talents played for damage.** The class list of the Best in Slot page has **Holy (Damage)** for the Paladin (Shockadin) and **Discipline (Damage)** and **Holy (Damage)** for the Priest. Pick it once and Lootified rates that character as a damage dealer: Sim plays your own talents (Holy Shock, Penance, Smite ...), Percent uses the stat weights of Retribution or Shadow. Lootified never picks these by itself, because healers take the same talents.

## Version 1.3.1

- **Percent: no "Simulate" in the item menu.** The simulator's upgrade check belongs to Sim; with Percent the menu of an item no longer offers it.

## Version 1.3

- **Choose how Lootified rates items: Percent or Sim.** After the look (and once after this update) Lootified asks you. **Percent** shows every upgrade in percent by your spec's stat weights, right away (highly recommended for Tanks and Healers). **Sim** shows every upgrade in DPS from the simulator (highly recommended for DPS). Every role can pick either; closing the question without a choice asks you to agree to Percent. Change it any time in the settings (General, "Rate items").
- **Percent:** your Best in Slot list, the upgrade marks, tooltips, loot rolls and For you follow your stat weights. The Best in Slot sim button on For you and in the tour offers the switch to Sim; the simulator still sims your damage when you open it.
- **Sim:** every spec of your class gets the Best in Slot sim and DPS numbers, tanks and healers by the damage they do.

## Version 1.2

- **Best in Slot: swap items on the sheet.** A click on a slot of your class lists every item you can put on there, each with what it adds: the DPS your Best in Slot sim found (damage specs) or the percent by your stat weights (healers and tanks). Pick one and it goes in your own set: on the Best in Slot list or What I wear a free set takes that view first and the sheet shows it (both sets have items: a popup says so). Under the set chips the set's total: healers and tanks the exact percent, damage specs an estimate from each item's own sim; "Sim this set" in the header sims it in the planner for its exact DPS. Healers and tanks also see the percent on the sheet itself. The click no longer opens the planner.

## Version 1.1

- **Healers and tanks:** item tooltips, the box beside loot rolls and Alt+Click judge an item by your spec's own stat weights again – the same as your Best in Slot list – with the share in percent it adds to what you wear. No damage numbers for these specs there any more. The simulator still sims their damage when you open it (a line on top says so), and its planner shows the same percent beside every item. The tour explains Alt+Click for them that way too, and its Best in Slot sim button tells them what their list is made of and what the sim is for, as does the new Best in Slot sim button on For you (beside All upgrades).

## Version 1.0

The first public release.

- **Loot journal**: every Classic dungeon plus the new Forever dungeons and raids, each boss with its loot and drop chances, dungeon quests with their chains, dungeon maps, entrances on the world map, open world rares and drops.
  - **The new Forever loot of the beta** (checked 2026-10-06 against the game's own data): Excavation Site: Wetlands, Razorfen Kraul, Gnomeregan and Scarlet Monastery with their new items and the drops seen in the beta; the quest items of Razorfen Downs and Uldaman.
  - **The beta's dungeon quests** as foreverchanges.pro shows them, matched by quest ID, the game's own levels, rewards and XP first: Excavation Site: Wetlands with its 14 quests, the new quests of Hall of Thanes, Ruins of Lordaeron, Ragefire Chasm and Scarlet Monastery and their chains, the givers with their map spots and the items that start a quest.
  - **Maps of the new Forever dungeons**: Santiago Reyes' maps of Hall of Thanes, Ruins of Lordaeron and Excavation Site: Wetlands with every boss and the entrance marked, and of City of Dalaran.
- **Best in Slot**: your list on your character, built by the in-game simulator from every item you can wear at your level, and the damage each upgrade adds in tooltips, loot rolls and For you. The item data of the current beta build (1.60.1.70235) ships with the addon.
- **Simulator** for every spec, the tanks and healers with their damage against the target dummy: your character's damage (Character), your own sets (Planner, with "Higher levels" also for later) and the sets side by side (Sets). The Best in Slot sim sits beside "Open simulator" on the Best in Slot sheet and on For you and says "Up to date" while your list fits your level and gear.
  - It follows the game's own spell data: the spell power share of every spell rank, damage over time that can crit, global cooldowns, procs and talents as the game applies them.
  - Where a spell may or may not pay (seals and Consecration, Holy Fire and Starshards, openers, Expose Armor and Rupture, Earth Shock or Frost Shock, a warlock's filler ...), it fights each way and keeps the one that does more.
  - The Character tab names what you have learned that it does not play, and why.
- **Upgrade check** for loot rolls, and Alt+Click sims any item: in your bags, the loot window, chat and every list of Lootified (the journal's loot too).
- **`/lf export`**: your character as a text to copy (gear, stats, spells, talents and pet; no name, no realm) for Lootified's web simulator.
- **Three looks** (Modern, Classic, Database), ten languages, modules you can switch off.
- **Help & links**: the ? in the top bar, the line under the pages and Tour & help in the settings open Lootified's homepage and Discord to copy, for bug reports and ideas.
- **Tour**: its first step starts the Best in Slot sim, which runs while you take the tour; it shows Alt+Click on the loot and in your bags; Done takes you to your start page; the simulator explains its Sim button and tabs the first time it opens.

## Content

- **26 Classic dungeons** (Ragefire Chasm to Upper Blackrock Spire, every Scarlet Monastery, Dire Maul and Stratholme wing on its own page).
- **The new Forever dungeons**: Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, The Drowned City, plus the four announced ones (Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace).
- **Forever raids**: Onyxia's Lair, Barrow Deeps, Hyjal Summit.
- **414 dungeon and raid quests** (690 including the earlier quests of their chains) with objectives, quest givers, chains and rewards, including 46 new Forever quests.
- **Open world loot**: about 3,000 items (uncommon and better) from open world mobs, including 77 rares with their own drops: mob, level, drop chance and camps on the map. Items that drop from almost any mob of a level range are shown as random world drops with that range.
- Every instance says in its tooltip (and on the Database's Places page) how far its data is known: loot confirmed in the Forever beta, the Classic loot table, no drops recorded yet, or announced and not revealed yet.

## Features

- **Three looks**, picked the first time you open Lootified and switched any time (Settings, Look & color, or `/lf look`). Modern and Classic have the pages For you, Journal, Open World, Best in Slot and Wishlist; the Database look has its own four.
  - *Modern*: dark glass with the dungeon art, 3D models and soft animations.
  - *Classic*: dark leather and gold titles, every dungeon as a picture.
  - *Database*: look up every item, mob, quest and place on four pages (Items, Mobs, Quests, Places), each with a search, filters, a sort and the details of the picked entry. The Items page sorted "For you" shows your Best in Slot items (crown) and your upgrades first.
- **For you** (the start page): the best dungeon for you on top (the most upgrades, then the most open quests, as in the Journal); your character with its level, experience and Best in Slot set (the items you own are bright); your next three upgrades, one per slot, with where they drop and the DPS they add (with Percent: the percent they add to your gear); more dungeons for your level. The Best in Slot sim starts here ("Run Best in Slot sim"); later its button says "Up to date" as on the Best in Slot sheet, or "Best in Slot sim" with a warning sign after a level-up or new gear; "All upgrades" opens the Best in Slot sheet. With Percent: All upgrades and a Best in Slot sim button that offers the switch to Sim.
- **Journal**: every dungeon and raid as a picture (Dungeons | Raids): the best one for you big on top, the others for your level below it, then the rest by level ("My level only": just the ones for your level and the next ones coming up). A dungeon has "Entrance" (on the world map) and "Dungeon map" at the top, Bosses | Quests on the left:
  - *Bosses*: every boss with its portrait, level and your upgrades, then trash & zone drops and quest rewards. The picked boss's loot shows on the right with drop chances, beside its animated 3D model (drag to turn it); "Usable by me" and "Upgrades only" filter it.
  - *Quests*: the dungeon's quests by status, one line per chain (your faction, Alliance, Horde or all), and the picked quest: XP and money, rewards, the whole chain, the objective, where it starts and ends with Map buttons.
  - *Dungeon map*: Blizzard's map of the dungeon in its own window (Santiago Reyes' maps for the new Forever dungeons), one floor at a time, the bosses with their faces, the entrance marked. Click a boss and its loot unfolds beside the map. Drag the title to move the window, the grip to size it.
- **Open World**: the zones for your level (or all of them) on the left, the picked zone as a hunt board: its rares as cards (face, level, best drops for you, a Map button for their camps), the other mobs as lines with their best drop. The page shows the zone you are in and follows you; a zone you pick stays until you move on. "Upgrades only" shows only your upgrades.
- **Best in Slot** for your character, every spec of its class (every talent tree, Feral as Cat and Bear, the Paladin's Holy and the Priest's Discipline and Holy also played for damage); your spec comes from your talent points, or pick it in the filter (the damage entries only there). Your list for your level as a character sheet, made of the armor and the sources you picked in the filter (every armor your class wears and, realistic to start with: quest rewards you can take, dungeon loot and rares, drops of 10 % or more (the drop chance: from every drop to 50 %); crafted items and world drops when you switch them on), for tanks the heaviest armor of these in each slot (none: the next lighter one; a slot without any item of your list stays empty and says so): your character in 3D wears it (drag to turn, mouse wheel to zoom), every slot shows its item and, in green, the DPS the sim found it adds; the item's tooltip says where it drops. Chips switch the sheet between "Best in Slot", "What I wear" (each slot with what its Best in Slot item would add) and your own sets Set 1 and Set 2 (an empty one shows empty: click a slot to put an item in it). A click on a slot lists your list's items for it, with a search (names and sources), armor chips and "Higher levels", each with what it adds (with Percent: the percent by your stat weights; a tank's lighter armor marked); pick one and it goes in your own set (None takes a set's item out again), whose total shows under the chips ("Sim this set" sims it exactly). The filter's Stat priority tab lets you drag your spec's stats into your own order (with Percent; Sim rates by real DPS). The filter sits in the middle at the top, "Best in Slot sim" and "Open simulator" at the right; a right click on an item puts it on your wishlist.
  - *Filter*: the button names your spec and your sources; its panel picks the spec (as cards), switches the sources (Quests, Dungeons, Rare, Crafted, World), sets the drop chance (a slider) and goes "Back to realistic". The same choice as at the first start; it counts for the whole addon at once.
  - *Best in Slot sim*: for the damage specs the simulator builds the list. Every item of it you can wear at your level fights in its slot against what you wear (a quick pass, then the best of each slot exactly, then the best set as a whole). It takes a few minutes, goes on while you play and only runs when you start it: on For you or with the "Best in Slot sim" button on the Best in Slot sheet. The button says "Up to date" while the list fits your level and gear (a click sims it again all the same, after new talents say); after a level-up, a gear change or a change of your list's sources it shows a warning sign and the sheet says the sim is outdated. When it cannot run (nothing to sim at your level yet, your pet not out, in combat ...), a popup says why.
  - Percent and every spec before its first sim get an estimate from stat weights built from the Forever class guides.
- **Simulator** (`/lf sim` or "Open simulator"): plays your character against a target dummy, for every spec (tanks and healers: their damage with their gear; with Percent a line on top says your upgrades follow your stat weights, and the planner shows the percent of every item and of the whole set, no sim needed). Pick the target (a mob of your level up to a boss 3 levels higher) and the fight's length (1, 3 or 5 minutes); the button at the bottom right sims the tab you see ("Sim my gear", "Sim my set", "Sim the sets"), Stop ends it. When it cannot sim (in combat, your pet not out, not in your form or stance, a set without its weapon ...), a popup says why; the Planner and Sets work all the same.
  - *Character*: your damage per second, the damage of each ability and what one more point of each stat is worth; with the room, what the sim read from you and from the target. Your last sim stays until you press Sim again.
  - *Planner*: two sets of your own that you can name. Click a slot to pick an item of your list your character can put on there (the search finds names and sources), or drop an item from your bags on it; "Higher levels" in the picker adds the items of later levels up to 60, each with its level (the sim counts them as if you could wear them now, the set says so); "Start from" copies what you wear or your Best in Slot sheet, "Empty" clears the set. Sim fights the set on its own.
  - *Sets*: what you wear against your Best in Slot sheet and your two sets (the ones you tick), all in the same fights, as bars side by side, with how the fights went and where the difference comes from.
  - The first Sim asks how fast it may calculate: Smooth, Fast or Turbo (Settings, General). While it calculates, a small window shows the progress, the time left and Stop; in combat the fights wait. Set bonuses, procs and on-use effects of items do not count.
- **Upgrade check for loot**: when an item is rolled for in a group, a box beside the roll says whether it is an upgrade for you: the DPS the sim found against what you wear (else an estimate from its stats), what it would replace and, for the damage specs, a tip (Need, or Greed or Pass); Sim lets the item fight in a few seconds. With Percent you get the verdict of your stat weights instead, with the share in percent the item adds to your whole gear (nothing fights). It also says when your class cannot use the item, your level is too low or, for a tank, it is lighter armor than tanks wear. Alt+Click an item in your bags, the loot window, a chat link, at a vendor or in any list of Lootified (a boss's loot, Open World, search, Best in Slot) for the same check in a small window: the item fights at once. On or off: Settings, Map & alerts.
- **Wishlist**: star any item (its star or the item menu). The list groups your items by where they drop, and "Where to go" names the dungeons, bosses and rares to run. One click adds the Best in Slot items you are missing. When a wishlist item drops or is rolled for, an alert shows on screen with a sound.
- **Search** (the box at the top right): every dungeon and raid, boss, dungeon quest, zone, mob and item, open world drops included, from 3 letters (dungeon shortcuts like `dm` or `zf` right away). An item opens its own page: every boss, mob and quest it comes from, with drop chance, level and zone, and a Map button that marks a mob's camps one after the other.
- **Item tooltips** everywhere in the game: beside the name the DPS the item adds for you (or "BiS"; with Percent: the percent it adds to your whole gear by your stat weights), below it where it drops and how often, the profession that makes it, the quests that give or need it and your wishlist mark. Gear the sim can fight that has no number yet says "Alt+Click: sim it against what you wear", in Lootified's lists too. Each line can be switched off (Settings, Tooltips, with a live preview).
- **World map**: a pin at every dungeon entrance; a click opens the dungeon in Lootified with its map (Settings, Map & alerts). Map buttons (quest givers, camps, entrances) mark the spot and set the game's waypoint.
- **Help & links** (the ? beside the gear, the line under the pages, "Website & Discord" in Settings, Tour & help): Lootified's homepage (https://foreverlootified.com/) and Discord (https://discord.gg/8pQheBvCB6) in lines to copy: click a line, press Ctrl+C and paste it into your browser. Bug reports and ideas are welcome there.
- **Settings** (the gear button or `/lf settings`): General (how items are rated, window size and position, sim speed), Modules, Look & color (the look, the layout color, the minimap button), Tooltips, Map & alerts, Language, Tour & help. Every change applies at once; "Reset this page" puts a page back to its defaults.
  - *Modules*: For you, Journal, Open World, Best in Slot and Wishlist can each be switched off; its tab goes away. Best in Slot off also takes the simulator, the upgrade marks, its tooltip line and the upgrade check with it, Wishlist off its stars, tooltip mark and alerts. One module always stays on; the first one that is on is the start page.
- **Tour**: a spotlight tour of the window the first time you open it. Its first step starts the Best in Slot sim, which runs while you take the tour; then come the pages of the modules that are on (the journal and the Best in Slot steps show Alt+Click), the Best in Slot sim and "Open simulator" (the damage specs) and the settings; Done takes you to your start page. The dungeon map and the simulator explain themselves the first time they open. Again from Settings (Tour & help) or with `/lf tour`.
- **Languages**: English, German, French, Spanish (Spain, Latin America), Portuguese (Brazil), Russian, Korean and Chinese (traditional, simplified) (Settings, Language: the game's language or one of them; Korean and Chinese in a client of that language; a new language shows after a reload).
- Minimap button (left-click opens or closes Lootified, right-click opens Best in Slot), addon compartment entry and key bindings (Options > Keybindings > AddOns).

## Commands

| Command | What it does |
|---|---|
| `/lf` | Open or close the window (inside a dungeon it opens that dungeon) |
| `/lf start` | The start page (For you) |
| `/lf settings` | The settings: modules, look, tooltips, language |
| `/lf bis` | Best in Slot for your character |
| `/lf sim` | The simulator: your damage, your own sets, the sets side by side |
| `/lf export` | Your character as a text to copy into Lootified's web simulator |
| `/lf wishlist` | Your wishlist |
| `/lf raids` | The raids in the journal |
| `/lf search <text>` | Search every dungeon, boss, quest, zone, mob and item |
| `/lf <dungeon>` | Open a dungeon or raid directly, e.g. `/lf dm`, `/lf wc`, `/lf sfk`, `/lf bfd`, `/lf hot`, `/lf rol`, `/lf brd`, `/lf strat` |
| `/lf tour` | The tour of Lootified |
| `/lf look` | Compare the three looks and pick one |
| `/lf modern`, `/lf classic`, `/lf database` | Switch the look directly |
| `/lf color` | Layout color back to automatic (pick one in the settings) |
| `/lf minimap` | Show or hide the minimap button |
| `/lf reset` | Reset the window position and scale (and the simulator window's size and place) |
| `/lf errors` | Show recent Lootified errors (for bug reports) |
| `/lf items` | Item data status: saved items, server requests, waiting items (for bug reports) |
| `/lf memory` | The memory Lootified uses, with and without the garbage the game has not cleaned up yet |
| `/lf debug` | Debug output on or off (also how long showing a page and making a ranking take) |
| `/lf help` | List every command in the chat |

In the Database look, `/lf start`, `/lf bis` and `/lf wishlist` open its Items page and `/lf raids` its Places page.

**Clicks on items** in Lootified: Alt+Click sims an item against what you wear (the upgrade check, as in your bags, the loot window, chat links and at vendors), Shift-click links it in chat, Ctrl-click opens the dressing room, right-click opens a menu (wishlist, Link in chat, Simulate, Preview in Dressing Room, its source and quests). The star puts an item on your wishlist or takes it off.

## Notes

- The data of the dungeon, raid and open world items and of all the gear Forever has opened ships with the addon (read from the Forever client: levels, stats, a weapon's damage and speed, professions), so Best in Slot and the simulator are ready at once, without asking the server for these items. What you wear is read from your game, and so is an item you check for an upgrade (a loot roll, Alt+Click), random suffixes like "of Strength" included. Items Forever still keeps secret come with a later update.
- Drop chances are the Classic loot table values; the real rates in Forever can differ. Items that are new in Forever have no known drop chance, so none shows.
- The stat weights of the specs are estimates built from the stat priorities of the Forever class guides.
- Map buttons mark the spot on the world map and set the game's waypoint (the marker on your screen). Click the button again to remove the mark. A dungeon entrance's Map button lights up its entrance pin instead (while the pins are on).
- The dungeon maps are Blizzard's own map art from your game client. They show each dungeon as Blizzard drew it for Cataclysm, so a room Forever changes can look different in the game. Wailing Caverns has Blizzard's earlier map (Wrath of the Lich King), shipped with the addon, with the eastern maze Forever still has. The new Forever dungeons have Santiago Reyes' maps (Atlas de Azeroth: Forever), shipped with the addon with his permission; where they don't show a boss yet, nobody has placed it.
- Errors are never hidden: they go to the normal Lua error display and are listed by `/lf errors`.
- The Modern and Database looks use the bundled fonts on English, German, French, Spanish, Italian and Portuguese clients and the game font on other client languages (Korean, Chinese), so every character shows; the Classic look uses the game's Friz Quadrata. Russian uses Friz Quadrata (Cyrillic) in every look.

## Credits and license

Data sources:

- **CMaNGOS classic-db** (GPL-3.0): quests, prerequisites, rewards, loot tables and drop chances, creatures and spawns, the class restrictions of items, where the bosses and entrances are on the dungeon maps.
- **CMaNGOS mangos-classic** (GPL-2.0+): the simulator's combat rules (attack table, armor, regeneration, spell hit, the spell power shares); the formulas are written anew, no code of it is part of the addon.
- **World of Warcraft 4.3.4 client tables** (DungeonMap, DungeonMapChunk, WorldMapArea) and collision models from a public server data pack: the floors of the dungeon maps and where they lie in the world.
- **Public guides** (WoW Handbook, Warcraft Tavern, Warcraft Wiki, Wowhead): dungeon entrance coordinates.
- **Public Forever sites** (wowforevertalent.com, Wowhead Forever, Zockify, Mobalytics, WoW Handbook and others): Forever beta quest facts (quest giver positions, rewards, levels, new quests).
- **foreverchanges.pro**: the quests of the dungeons open in the beta and their chains, the bosses and entrances on the maps of Hall of Thanes, Ruins of Lordaeron and Excavation Site: Wetlands.
- foreverchanges.pro, Wowhead (Forever and Classic), 60.tools: Forever loot. Icy Veins and Warcraft Tavern: BiS guides. Icy Veins, leprestore, Wowhead, wowforeverbuilds and Warcraft Tavern (Forever class guides): the stat priorities of the specs.

Maps:

- **Santiago Reyes, Atlas de Azeroth: Forever**: the maps of Hall of Thanes, Ruins of Lordaeron, City of Dalaran and Excavation Site: Wetlands, used with his permission (not under the GPL; see `THIRD_PARTY_NOTICES.md`). https://asguevara433.wixsite.com/srmaps
- **Blizzard Entertainment**: the earlier map of Wailing Caverns (Wrath of the Lich King), shipped with the addon. It is Blizzard's artwork and not under the GPL (see `THIRD_PARTY_NOTICES.md`).

Fonts and icons:

- **Barlow** fonts by Jeremy Tribby (SIL Open Font License 1.1).
- **Phosphor Icons** (MIT) for the interface icons.
- **game-icons.net** by Lorc, Delapouite, Skoll, Sbed, Carl Olsen and Kier Heyl (CC BY 3.0) for the boss emblems.

Details and license texts: `THIRD_PARTY_NOTICES.md`.

Lootified is released under the **GNU General Public License v3** (see `LICENSE`).

Author: Alen
