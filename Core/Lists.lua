-- Lootified - the lists the pages show, without frames: an instance's loot groups with the Loot filters, the number of
-- upgrades (the items of the Best in Slot list: Core/BiS.lua), the dungeons for the character's level, the rares of a
-- zone, the wishlist by source, the zone that follows the player and the map marks of mob camps. Every look's pages
-- read them, so a number is the same wherever it shows.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Lists = {}
LJ.Lists = Lists

local Items = LJ.Items
local Player = LJ.Player
local BiS = LJ.BiS
local Quests = LJ.Quests
local Util = LJ.Util

---------------------------------------------------------------------------
-- Loot filters (the Loot tab's slot and class filters; LJ.db.lootFilter)
---------------------------------------------------------------------------
Lists.SLOT_FILTERS = {
    { key = "ALL", text = "All slots" },
    { key = "HEAD", text = "Head", locs = { INVTYPE_HEAD = true } },
    { key = "NECK", text = "Neck", locs = { INVTYPE_NECK = true } },
    { key = "SHOULDER", text = "Shoulder", locs = { INVTYPE_SHOULDER = true } },
    { key = "BACK", text = "Back", locs = { INVTYPE_CLOAK = true } },
    { key = "CHEST", text = "Chest", locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { key = "WRIST", text = "Wrist", locs = { INVTYPE_WRIST = true } },
    { key = "HANDS", text = "Hands", locs = { INVTYPE_HAND = true } },
    { key = "WAIST", text = "Waist", locs = { INVTYPE_WAIST = true } },
    { key = "LEGS", text = "Legs", locs = { INVTYPE_LEGS = true } },
    { key = "FEET", text = "Feet", locs = { INVTYPE_FEET = true } },
    { key = "FINGER", text = "Finger", locs = { INVTYPE_FINGER = true } },
    { key = "TRINKET", text = "Trinket", locs = { INVTYPE_TRINKET = true } },
    { key = "WEAPON", text = "Weapons", locs = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONOFFHAND = true } },
    { key = "OFFHAND", text = "Shields & Off-hands", locs = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true } },
    { key = "RANGED", text = "Ranged & Relics", locs = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true } },
    { key = "OTHER", text = "Other (recipes, quest)" },
}

function Lists.PassesSlot(rec, key)
    if key == "ALL" then return true end
    local isEquip = rec.equipLoc and rec.equipLoc ~= "" and rec.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    if key == "OTHER" then return not isEquip or rec.equipLoc == "INVTYPE_BAG" end
    for _, f in ipairs(Lists.SLOT_FILTERS) do
        if f.key == key then return f.locs and f.locs[rec.equipLoc] or false end
    end
    return true
end

-- The Loot tab's filter (LJ.db.lootFilter.spec): "ALL", "MINE" (usable by me) or "UPGRADE" (the items of the Best in
-- Slot list: BiS.Upgrade). Only the player changes it: links from other pages open the loot with the filter as it is.
function Lists.PassesClass(rec, key, upgrade)
    if key == "UPGRADE" then return upgrade ~= nil end
    if key ~= "MINE" then return true end
    if not rec.equipLoc or rec.equipLoc == "" then return false end
    return Player:CanClassUse(rec, Player.class)
end

---------------------------------------------------------------------------
-- An instance's loot
---------------------------------------------------------------------------
-- { id, kind = "boss" | "trash" | "quests", index (boss index, 0 trash, -1 quest rewards), boss,
--   entries = { { id, chance, label (trash mob), questID, questName, isChoice } } }
function Lists.BuildGroups(inst)
    local groups = {}
    for i, boss in ipairs(inst.bosses) do
        local g = { id = inst.key .. ":" .. i, kind = "boss", index = i, boss = boss, entries = {} }
        for j, id in ipairs(boss.loot) do
            g.entries[#g.entries + 1] = { id = id, chance = boss.chance and boss.chance[j] or nil }
        end
        groups[#groups + 1] = g
    end
    if inst.trash and #inst.trash > 0 then
        local g = { id = inst.key .. ":trash", kind = "trash", index = 0, entries = {} }
        for j, id in ipairs(inst.trash) do
            local source = inst.trashSource and inst.trashSource[j]
            g.entries[#g.entries + 1] = { id = id, chance = inst.trashChance and inst.trashChance[j] or nil,
                label = (source and source ~= "") and source or nil }
        end
        groups[#groups + 1] = g
    end
    return groups
end

-- The upgrades of an instance for the character (the items of its Best in Slot list), counted like its boss and trash
-- loot without filters. Quest rewards are shown only on the Quests tab.
function Lists.CountFor(inst)
    local seen, upgrades = {}, 0
    for _, g in ipairs(Lists.BuildGroups(inst)) do
        for _, e in ipairs(g.entries) do
            if not seen[e.id] then
                seen[e.id] = true
                if BiS.Upgrade(e.id) then upgrades = upgrades + 1 end
            end
        end
    end
    return upgrades
end

-- The "Upgrade for you" line an item row adds to its tooltip, or nil: only while the upgrade line of the item tooltip is
-- off in the options (it says the same).
function Lists.UpgradeTooltip(upgrade, itemID)
    if upgrade and not LJ.db.tooltipUpgrade then
        return { F("Upgrade for you: %s", BiS.FormatUpgrade(itemID)), 0.34, 0.89, 0.54 }
    end
end

---------------------------------------------------------------------------
-- Dungeons for the character
---------------------------------------------------------------------------
-- "My level": instances whose level range touches 2 levels below to 3 levels above the character's level.
Lists.NEAR_BELOW, Lists.NEAR_ABOVE, Lists.MAX_LEVEL = 2, 3, 60
function Lists.NearRange()
    local level = Player.level or 1
    return level - Lists.NEAR_BELOW, level + Lists.NEAR_ABOVE
end

function Lists.IsNear(inst)
    local low, high = Lists.NearRange()
    return inst.minLevel <= high and inst.maxLevel >= low
end

-- The quests of an instance its card shows: the ones the character can take, work on or turn in now.
function Lists.OpenQuests(inst)
    local _, open = Quests.CountForInstance(inst.key)
    return open
end

-- The better of two instance cards ({ inst, upgrades, quests: Lists.OpenQuests }), the same on every page ("Best for
-- you right now", the order for the level): more upgrades, then more open quests, then the lower one, then by name.
function Lists.Better(a, b)
    if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
    if a.quests ~= b.quests then return a.quests > b.quests end
    if a.inst.minLevel ~= b.inst.minLevel then return a.inst.minLevel < b.inst.minLevel end
    return a.inst.name < b.inst.name
end

-- Dungeons and raids for the character's level ("My level"), the best first (Lists.Better); when none fits: the next
-- three coming up. Returns { { inst, upgrades, quests (open) } } and whether they are the coming ones.
function Lists.InstancesFor(level)
    local near, later = {}, {}
    for _, kind in ipairs({ "dungeon", "raid" }) do
        for _, inst in ipairs(LJ.instancesByKind[kind] or {}) do
            if inst.status ~= "announced" then
                if inst.minLevel <= level + 3 and inst.maxLevel >= level - 2 then
                    near[#near + 1] = inst
                elseif inst.minLevel > level + 3 then
                    later[#later + 1] = inst
                end
            end
        end
    end
    local upcoming = #near == 0
    local chosen = near
    if upcoming then
        table.sort(later, function(a, b)
            if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
            return a.name < b.name
        end)
        chosen = {}
        for i = 1, math.min(3, #later) do chosen[i] = later[i] end
    end
    local list = {}
    for _, inst in ipairs(chosen) do
        list[#list + 1] = { inst = inst, upgrades = Lists.CountFor(inst), quests = Lists.OpenQuests(inst) }
    end
    if not upcoming then table.sort(list, Lists.Better) end
    return list, upcoming
end

-- The next upgrades: per slot of the Best in Slot sheet the item the sim found best there (before the spec's first
-- sim the hidden ranking's) when the character does not own it yet; the biggest upgrade first:
-- { { id, upgrade, chance } }.
function Lists.NextUpgrades()
    local spec = Player:GetActiveSpec()
    if not spec then return {} end
    -- Saved simulator records are legacy data and must not drive the active
    -- percent-only upgrade list or bypass the current Best in Slot filters.
    local simmed = false
    local ranking = not simmed and BiS.Ranking(spec)
    local list, seen = {}, {}
    local mainHand
    for _, slot in ipairs(BiS.SLOTS) do
        local id
        if simmed then id = LJ.SimBiS.Winner(spec, slot) else id = BiS.RankedPick(spec, slot, ranking) end
        if slot == "MAINHAND" then mainHand = id end
        -- no off hand beside a two-handed main hand (as on the sheet: BiS.ResolveSlot)
        if slot == "OFFHAND" and BiS.IsTwoHand(mainHand) then id = nil end
        local t = id and not seen[id] and BiS.Target(id)
        if t then
            seen[id] = true
            list[#list + 1] = { id = id, upgrade = t.value, chance = Items.GetBestChance(id) }
        end
    end
    table.sort(list, function(a, b)
        if a.upgrade ~= b.upgrade then return a.upgrade > b.upgrade end
        return a.id < b.id
    end)
    return list
end

---------------------------------------------------------------------------
-- Open world
---------------------------------------------------------------------------
-- The map the player is on (with or without open world data).
function Lists.PlayerMap()
    return C_Map.GetBestMapForUnit("player")
end

-- The zone the player stands in, when it has open world data.
function Lists.CurrentZoneMap()
    local map = Lists.PlayerMap()
    if map and Items.GetWorldZone(map) then return map end
    return nil
end

-- Zone to open without a choice: where the player is, else the first zone around the player's level.
function Lists.DefaultZoneMap(zones)
    local here = Lists.CurrentZoneMap()
    if here then return here end
    local level = Player.level or 1
    for _, zone in ipairs(zones) do
        if level >= zone.minLevel and level <= zone.maxLevel + 2 then return zone.map end
    end
    return zones[1] and zones[1].map
end

-- Zones for the character's level: the level range reaches from 2 levels below to 3 above the character's level.
function Lists.ZoneIsNear(zone)
    local low, high = Lists.NearRange()
    return zone.minLevel <= high and zone.maxLevel >= low
end

-- The mobs of a zone with the drops to show: with upgradesOnly just the upgrades, and the mobs that have one.
-- Returns { { mob, drops, total } } (zone order: rares first) and the numbers of rares and other mobs listed.
function Lists.ZoneMobs(zone, upgradesOnly)
    local list, rares, others = {}, 0, 0
    for _, mob in ipairs(zone.mobs) do
        local all = Items.GetMobDrops(mob.id) or {}
        local drops = all
        if upgradesOnly then
            drops = {}
            for _, d in ipairs(all) do
                if BiS.WorldUpgrade(d.id) then drops[#drops + 1] = d end
            end
        end
        if not upgradesOnly or #drops > 0 then
            list[#list + 1] = { mob = mob, drops = drops, total = #all }
            if mob.isRare then rares = rares + 1 else others = others + 1 end
        end
    end
    return list, rares, others
end

-- Map marker of a mob's camp: the first click marks its main camp, further clicks walk through the other camps, a click
-- on the last marked camp removes the mark. itemName: the marker names the item the mob drops (the item page).
function Lists.MobSpot(mob, index, itemName)
    local loc = mob.locs[index]
    if not loc then return nil end
    LJ.MapPin.Resolve(loc)
    if not (loc.map and loc.x and loc.y) then return nil end
    local detail = itemName and F("Drops %s", itemName) or F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel))
    if #mob.locs > 1 then detail = F("%s (camp %d of %d)", detail, index, #mob.locs) end
    return { map = loc.map, x = loc.x, y = loc.y, title = mob.name, detail = detail }
end

-- The camp of a mob that is marked on the map, or nil.
function Lists.MarkedCamp(mob, itemName)
    for i = 1, #mob.locs do
        local spot = Lists.MobSpot(mob, i, itemName)
        if spot and LJ.MapPin.IsTarget(spot) then return i end
    end
    return nil
end

-- The next click on a mob's map button: marks the next camp, or clears the mark after the last one.
function Lists.MarkNextCamp(mob, itemName)
    local marked = Lists.MarkedCamp(mob, itemName)
    local spot = Lists.MobSpot(mob, marked and marked + 1 or 1, itemName)
    if spot then
        LJ.MapPin.Show(spot)
    else
        LJ.MapPin.Clear()
    end
end

-- Label, glyph, tooltip title and text of a mob's map button (the button is off without a map position).
function Lists.MapButtonState(mob, itemName)
    local marked = Lists.MarkedCamp(mob, itemName)
    local canMark = Lists.MobSpot(mob, 1, itemName) ~= nil
    local label
    if marked and #mob.locs > 1 then
        label = F("Camp %d/%d", marked, #mob.locs)
    else
        label = marked and "Marked" or "Map"
    end
    local tip
    if not canMark then
        tip = L("The game has no map position for this spot.")
    elseif marked and marked < #mob.locs then
        tip = L("Click for the next camp.")
    elseif marked then
        tip = L("Click to remove the mark.")
    else
        tip = L("Opens the world map and sets a marker you can follow.")
        if #mob.locs > 1 then tip = tip .. " " .. L("Click again for its other camps.") end
    end
    return label, marked and "check" or "mapPin", marked and "Marked on your map" or "Show on the map", tip, canMark
end

---------------------------------------------------------------------------
-- Wishlist
---------------------------------------------------------------------------
-- The wishlist by source: instance keys in list order, then "_WORLD" (rares, mobs and quests of the open world), then
-- "_OTHER". Returns groups ([key] = { { id, source } }, items by boss), the keys in order and the number of items.
function Lists.WishlistGroups()
    local groups, order, count = {}, {}, 0
    for itemID in pairs(LJ.cdb.wishlist) do
        count = count + 1
        local sources = Items.GetSources(itemID)
        local key = sources and sources[1] and sources[1].inst
            or ((Items.HasWorldDrop(itemID) or Items.GetWorldQuestSources(itemID)) and "_WORLD") or "_OTHER"
        if not groups[key] then
            groups[key] = {}
            order[#order + 1] = key
        end
        table.insert(groups[key], { id = itemID, source = sources and sources[1] })
    end
    table.sort(order, function(a, b)
        local ia, ib = LJ.instanceByKey[a], LJ.instanceByKey[b]
        if ia and ib then return ia.index < ib.index end
        if ia or ib then return ia ~= nil end
        return a == "_WORLD" and b ~= "_WORLD"    -- open world before the other sources
    end)
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            local ba = a.source and a.source.boss or 99
            local bb = b.source and b.source.boss or 99
            if ba ~= bb then return ba < bb end
            return a.id < b.id
        end)
    end
    return groups, order, count
end

-- Where to go for the wishlist: the instances (with the bosses to kill) and the open world mobs to hunt, busiest first.
-- { { inst, count, bosses = { names }, firstBoss } | { mob, count, bosses = {}, itemID } }
function Lists.WishlistPlan(groups, order)
    local plan = {}
    for _, key in ipairs(order) do
        local inst = LJ.instanceByKey[key]
        if inst then
            local bosses, seen, firstBoss = {}, {}, nil
            for _, entry in ipairs(groups[key]) do
                local s = entry.source
                local name = s and (s.boss == 0 and L("Trash") or (inst.bosses[s.boss] and inst.bosses[s.boss].name))
                if name and not seen[name] then
                    seen[name] = true
                    bosses[#bosses + 1] = name
                    firstBoss = firstBoss or s.boss
                end
            end
            plan[#plan + 1] = { inst = inst, count = #groups[key], bosses = bosses, firstBoss = firstBoss }
        elseif key == "_WORLD" then
            -- open world: one line per mob to hunt (the best source of each item); random world drops have none
            local byMob = {}
            for _, entry in ipairs(groups[key]) do
                local mobs = Items.GetWorldSources(entry.id)
                local mob = mobs and mobs[1] and mobs[1].mob
                if mob then
                    local p = byMob[mob.id]
                    if not p then
                        p = { mob = mob, count = 0, bosses = {}, itemID = entry.id }
                        byMob[mob.id] = p
                        plan[#plan + 1] = p
                    end
                    p.count = p.count + 1
                end
            end
        end
    end
    table.sort(plan, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.inst ~= nil) ~= (b.inst ~= nil) then return a.inst ~= nil end
        if a.inst then return a.inst.index < b.inst.index end
        return a.mob.name < b.mob.name
    end)
    return plan
end
