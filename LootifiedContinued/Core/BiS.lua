-- Lootified - the Best in Slot list: the sheet's slots and their picks (the simulator's winners of Sim/SimBiS.lua,
-- else the hidden ranking of Core/Scoring.lua), and the items the character's active spec should get, the one source
-- of every upgrade mark, count and tooltip line.
-- The list takes only the items of the sources the player picked (Items.InList: quests, dungeons, rares, crafted, world
-- drops, the least drop chance; realistic until the filter changes it: UI/ListFilter.lua); a tank in each armor slot the
-- heaviest armor it gets one of there (BiS.ArmorFits: its lighter armor the slot's list marks). A slot with nothing
-- of the list at its level stays empty and says so.
-- The hidden ranking (stat weights) is never shown as such: it fills the list with Percent (LJ.cdb.rating), until the
-- first sim of a spec, and in the slots where nothing adds damage (the item with the best other stats). No frames here:
-- the pages draw it.
local _, LJ = ...
local L = LJ.L

local BiS = {}
LJ.BiS = BiS

local Items = LJ.Items
local Player = LJ.Player
local Scoring = LJ.Scoring

BiS.LEFT_SLOTS = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS" }
BiS.RIGHT_SLOTS = { "WAIST", "LEGS", "FEET", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2" }
BiS.WEAPON_SLOTS = { "MAINHAND", "OFFHAND", "RANGED" }
BiS.SLOT_LABELS = {
    HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back", CHEST = "Chest", WRIST = "Wrist",
    HANDS = "Hands", WAIST = "Waist", LEGS = "Legs", FEET = "Feet", FINGER1 = "Finger", FINGER2 = "Finger",
    TRINKET1 = "Trinket", TRINKET2 = "Trinket", MAINHAND = "Main Hand", OFFHAND = "Off Hand", RANGED = "Ranged",
    RELIC = "Relic",
}
BiS.SLOT_EMPTY_ICON = {
    HEAD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", NECK = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck",
    SHOULDER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder", BACK = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    CHEST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", WRIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
    HANDS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands", WAIST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    LEGS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs", FEET = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    FINGER1 = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger", FINGER2 = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    TRINKET1 = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket", TRINKET2 = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    MAINHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand", OFFHAND = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
    RANGED = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged", RELIC = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Relic",
}
BiS.RELIC_CLASSES = { PALADIN = true, DRUID = true, SHAMAN = true }
BiS.MAX_LEVEL = 60

-- Every sheet slot in sheet order (left column, right column, weapons).
BiS.SLOTS = {}
for _, list in ipairs({ BiS.LEFT_SLOTS, BiS.RIGHT_SLOTS, BiS.WEAPON_SLOTS }) do
    for _, slot in ipairs(list) do BiS.SLOTS[#BiS.SLOTS + 1] = slot end
end

local function DataSlot(slot)
    if slot == "FINGER1" or slot == "FINGER2" then return "FINGER" end
    if slot == "TRINKET1" or slot == "TRINKET2" then return "TRINKET" end
    return slot
end

-- The weapon setup of a spec: "TWOHAND", nil or "MAINHAND", "OFFHAND".
function BiS.WeaponSlots(spec)
    local hasMH = spec.slots.MAINHAND and #spec.slots.MAINHAND > 0
    local hasTH = spec.slots.TWOHAND and #spec.slots.TWOHAND > 0
    if (spec.weapon == "2H" and hasTH) or (not hasMH and hasTH) then
        return "TWOHAND", nil
    end
    return "MAINHAND", "OFFHAND"
end

-- The data slot (hidden ranking) of a sheet slot: FINGER for both rings, the weapon slot of the setup,
-- RELIC for the classes that carry one.
function BiS.ResolveDataSlot(spec, slot)
    if slot == "MAINHAND" or slot == "OFFHAND" then
        local mh, oh = BiS.WeaponSlots(spec)
        return (slot == "MAINHAND") and mh or oh
    elseif slot == "RANGED" then
        return BiS.RELIC_CLASSES[spec.class] and "RELIC" or "RANGED"
    end
    return DataSlot(slot)
end

-- The hidden ranking of a spec at a level (Scoring caches it).
local function RankingAt(spec, level)
    return Scoring.RankAll(spec, level < BiS.MAX_LEVEL and { maxLevel = level, current = true } or {})
end

-- The armor a tank's list takes in an armor slot at a level: the heaviest kind of the slot's ranked items (the list's,
-- its armor kinds too: paladins and warriors mail, from level 40 plate, druids leather), so a slot without a piece of it
-- takes the next lighter kind (quest leather shoulders before any mail ones); none: the heaviest its class wears. Kept
-- with the ranking.
local function TankKind(spec, equipLoc, level)
    local ranking = RankingAt(spec, level)
    local dataSlot = Scoring.EQUIPLOC_SLOTS[equipLoc]
    ranking.tankKind = ranking.tankKind or {}
    local kind = ranking.tankKind[dataSlot]
    if kind then return kind end
    kind = 0
    for _, e in ipairs(ranking.bySlot[dataSlot] or {}) do
        local sub = select(7, C_Item.GetItemInfoInstant(e.id))
        if sub > kind and sub <= 4 then kind = sub end
    end
    if kind == 0 then
        for k = 1, 4 do
            local from = Player.ARMOR[spec.class][k]
            if from and from <= level then kind = k end
        end
    end
    ranking.tankKind[dataSlot] = kind
    return kind
end

-- A tank wears the heaviest armor its list takes in the slot (TankKind): a lighter piece with more Stamina is no
-- upgrade for it (the upgrade check: Sim/ItemCheck.lua; the slot's list marks it as lighter armor). Every other item
-- and spec fits.
function BiS.ArmorFits(spec, itemID, level)
    if spec.role ~= "TANK" then return true end
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= 4 or not Items.ARMOR_SLOTS[equipLoc] or subclassID < 1 or subclassID > 4 then return true end
    return subclassID >= TankKind(spec, equipLoc, level)
end

-- An item the Best in Slot list takes for a spec at a level: one of its sources (Items.InList), for a tank in the
-- heaviest armor it gets there (BiS.ArmorFits).
function BiS.OnSheet(spec, itemID, level)
    return Items.InList(itemID, spec.class, level) and BiS.ArmorFits(spec, itemID, level)
end

-- The part of a data slot's ranked list the sheet picks from (BiS.OnSheet; none: the slot stays empty). Kept with the
-- ranking (one per spec and level).
local function SheetList(spec, ranking, dataSlot)
    ranking.sheet = ranking.sheet or {}
    local kept = ranking.sheet[dataSlot]
    if kept then return kept end
    kept = {}
    local level = BiS.ListLevel(spec)
    for _, x in ipairs(ranking.bySlot[dataSlot] or {}) do
        if BiS.OnSheet(spec, x.id, level) then kept[#kept + 1] = x end
    end
    ranking.sheet[dataSlot] = kept
    return kept
end

-- The hidden ranking's pick of a sheet slot: itemID, its ranking entry, the data slot and the slot's list the sheet
-- picks from (SheetList).
function BiS.RankedPick(spec, slot, ranking)
    local dataSlot = BiS.ResolveDataSlot(spec, slot)
    if not dataSlot then return nil end
    local list = SheetList(spec, ranking, dataSlot)
    if slot == "FINGER2" or slot == "TRINKET2" then
        local first = list[1] and list[1].id
        for i = 2, #list do
            if list[i].id ~= first then return list[i].id, list[i], dataSlot, list end
        end
        return nil, nil, dataSlot, list
    end
    if slot == "OFFHAND" then
        local main = BiS.RankedPick(spec, "MAINHAND", ranking)
        for i = 1, #list do
            if list[i].id ~= main then return list[i].id, list[i], dataSlot, list end
        end
        return nil, nil, dataSlot, list
    end
    return list[1] and list[1].id, list[1], dataSlot, list
end

-- The other slot of a pair: the second ring or trinket and the off hand never show the item of the first slot, the
-- first ring or trinket never the sim's winner of the second.
local FIRST_OF = { FINGER2 = "FINGER1", TRINKET2 = "TRINKET1", OFFHAND = "MAINHAND" }
local SECOND_OF = { FINGER1 = "FINGER2", TRINKET1 = "TRINKET2" }

-- The item of a sheet slot. Once the spec was simmed (Sim/SimBiS.lua): the sim's winner of the slot, its best pick or
-- what was worn when nothing does more. Without one (nothing adds damage and nothing was worn, nothing to sim there, or
-- no sim yet): what is worn once simmed, then the hidden ranking (ranking: BiS.Ranking), so a slot where nothing adds
-- damage gets the item with the best other stats. Nothing in the off hand beside a two-hander in the main hand.
function BiS.ResolveSlot(spec, slot, ranking)
    if slot == "OFFHAND" and BiS.IsTwoHand(BiS.ResolveSlot(spec, "MAINHAND", ranking)) then return nil end
    local id = LJ.SimBiS.Winner(spec, slot)
    if id then return id end
    local taken
    if FIRST_OF[slot] then
        taken = BiS.ResolveSlot(spec, FIRST_OF[slot], ranking)
    elseif SECOND_OF[slot] then
        taken = LJ.SimBiS.Winner(spec, SECOND_OF[slot])
    end
    if LJ.SimBiS.Get(spec) then
        local worn = GetInventoryItemID("player", LJ.SimBiS.INV_SLOT[slot])
        if worn and worn ~= taken then return worn end
    end
    local _, _, _, list = BiS.RankedPick(spec, slot, ranking)
    for _, x in ipairs(list or {}) do
        if x.id ~= taken then return x.id end
    end
    return nil
end

-- A two-hand weapon: nothing goes in the off hand beside it.
function BiS.IsTwoHand(itemID)
    return itemID ~= nil and select(4, C_Item.GetItemInfoInstant(itemID)) == "INVTYPE_2HWEAPON"
end

-- The label of a sheet slot for a class (the ranged slot of paladins, druids and shamans is the relic) and its empty
-- slot icon.
function BiS.SlotLabel(slot, class)
    if slot == "RANGED" and BiS.RELIC_CLASSES[class] then return BiS.SLOT_LABELS.RELIC, BiS.SLOT_EMPTY_ICON.RELIC end
    return BiS.SLOT_LABELS[slot] or slot, BiS.SLOT_EMPTY_ICON[slot]
end

-- The level a spec's list is for: the character's own class its level (items it can wear now), other classes 60.
function BiS.ListLevel(spec)
    return spec.class == Player.class and (Player.level or BiS.MAX_LEVEL) or BiS.MAX_LEVEL
end

-- The hidden ranking of a spec at the level of its list (Scoring caches it).
function BiS.Ranking(spec)
    return RankingAt(spec, BiS.ListLevel(spec))
end

-- The picks of a spec as the Best in Slot page shows them (BiS.ResolveSlot). { { slot = sheet slot, id = itemID },
-- ... } in sheet order, every item once.
function BiS.GetPicks(spec)
    local ranking = BiS.Ranking(spec)
    local picks, seen = {}, {}
    for _, slot in ipairs(BiS.SLOTS) do
        local id = BiS.ResolveSlot(spec, slot, ranking)
        if id and not seen[id] then
            seen[id] = true
            picks[#picks + 1] = { slot = slot, id = id }
        end
    end
    return picks
end

-- Where a curated Best in Slot item comes from (crafted, a quest ...), when the loot data has no source for it.
function BiS.FindCuratedSource(itemID)
    local list = Items.GetBiSEntries(itemID)
    if not list then return nil end
    local specs = LJ.Data.BiS[list[1].class]
    for _, spec in ipairs(specs or {}) do
        for _, entries in pairs(spec.slots) do
            for _, e in ipairs(entries) do
                if e.id == itemID and e.src and e.src ~= "" then return e.src end
            end
        end
    end
end

-- Where an item comes from, for a Best in Slot row: the loot source, else the curated source.
function BiS.SourceText(itemID)
    return Items.GetSourceText(itemID) or BiS.FindCuratedSource(itemID)
end

-- The items of a list that are not owned and not on the wishlist yet (and exist in the game).
function BiS.Missing(ids)
    local list = {}
    for _, id in ipairs(ids) do
        if not Items.IsOwned(id) and not Items.IsWishlisted(id) and Items.Get(id).exists ~= false then list[#list + 1] = id end
    end
    return list
end

-- The picks of the character's active spec (see GetPicks) that are not owned yet go on the wishlist.
function BiS.AddMyBiSToWishlist()
    local spec = Player:GetActiveSpec()
    if not spec then return 0 end
    local ids = {}
    for _, p in ipairs(BiS.GetPicks(spec)) do ids[#ids + 1] = p.id end
    local added = Items.AddToWishlist(BiS.Missing(ids))
    if added == 0 then
        LJ:Print("Your Best in Slot items are already owned or on your wishlist.")
    end
    return added
end

-- The item on the cursor (dragged from the bags, a loot window, ...), or nil.
function BiS.CursorItem()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return nil end
    return id
end

-- The weapon setup as text ("Two-hand weapon", "Dual wield", "One-hand + off-hand").
function BiS.WeaponText(spec)
    if BiS.WeaponSlots(spec) == "TWOHAND" then return L("Two-hand weapon") end
    if Player:CanDualWield(spec.class, BiS.ListLevel(spec)) and spec.weapon == "DW" then return L("Dual wield") end
    return L("One-hand + off-hand")
end

---------------------------------------------------------------------------
-- The items to get: the Best in Slot list of the character's active spec
---------------------------------------------------------------------------
-- Every upgrade mark, count and tooltip line of the addon comes from here. Per item: { id, slot (sheet slot), value
-- (the sort key: the damage the sim found, else the hidden ranking's gain), delta, err (the sim's numbers, nil when it
-- did not sim the item), pct (Percent: what it adds to the whole gear by the stat weights, as the upgrade check says
-- it) }. The items: the sim's (Sim/SimBiS.lua: the items of each slot whose gain shows), else (Percent, before a spec's
-- first sim) the best of the list's own items (BiS.OnSheet) that beat what is worn. Items the character owns are none.
BiS.RANKED = 5         -- ranked items per slot (like the sim's exact ones: SimBiS.BEST)

local targets          -- [itemID] = entry, for targetsSpec; nil: made again when asked
local targetsSpec
local wornUnknown      -- an item worn was not known when they were made: made again when item data comes

local function AddTarget(list, id, slot, value, delta, err, pct)
    local old = list[id]
    if old and old.value >= value then return end
    list[id] = { id = id, slot = slot, value = value, delta = delta, err = err, pct = pct }
end

-- The best items of the list's own items (SheetList) of every slot that beat what is worn there (its scores:
-- GetEquippedScore); with Percent only those whose share shows (ItemCheck.StatsDirection: +0.1 % and more).
local function AddRanked(list, spec)
    local ranking, done = BiS.Ranking(spec), {}
    local total
    if not LJ.UI.Sim.RanksItems(spec) then
        total = LJ.ItemCheck.WornTotal(spec)
        if total == nil then wornUnknown = true end
        if total == 0 then total = nil end
    end
    for _, slot in ipairs(BiS.SLOTS) do
        local dataSlot = BiS.ResolveDataSlot(spec, slot)
        if dataSlot and not done[dataSlot] then
            done[dataSlot] = true
            local worn = Scoring.GetEquippedScore(spec, dataSlot, true)
            if worn == nil then
                wornUnknown = true
            else
                local taken = 0
                for _, e in ipairs(SheetList(spec, ranking, dataSlot)) do
                    local gain = e.score - worn
                    local pct = total and gain / total * 100
                    if taken >= BiS.RANKED or gain <= 0 or (pct and pct < 0.05) then break end
                    if not C_Item.IsEquippedItem(e.id) then
                        taken = taken + 1
                        AddTarget(list, e.id, slot, gain, nil, nil, pct)
                    end
                end
            end
        end
    end
end

local function MakeTargets(spec)
    local list = {}
    wornUnknown = false
    local rec = LJ.SimBiS.Get(spec)
    if rec then
        for slot, r in pairs(rec.slots) do
            for _, row in ipairs(r.rows) do
                if not row.failed and LJ.SimBiS.Shows(row.delta, row.err) then
                    AddTarget(list, row.id, slot, row.delta, row.delta, row.err)
                end
            end
        end
    else
        AddRanked(list, spec)
    end
    return list
end

-- The list of the active spec, owned items included ([itemID] = entry); nil without a spec or with the Best in Slot
-- module off.
local function Current()
    if not LJ.Modules.On("bis") then return nil end
    local spec = Player:GetActiveSpec()
    if not spec then return nil end
    if not targets or targetsSpec ~= spec then
        targets, targetsSpec = MakeTargets(spec), spec
    end
    return targets
end

-- The entry of an item on the active spec's list, nil when it is not on it or owned.
function BiS.Target(itemID)
    local list = Current()
    local t = list and list[itemID]
    if t and Items.IsOwned(itemID) then return nil end
    return t
end

-- The sort value of an item on the list (bigger: better), nil when it is not on it.
function BiS.Upgrade(itemID)
    local t = BiS.Target(itemID)
    return t and t.value
end

-- Open-world rows need a live answer even when the cached target sheet was built before
-- an item or an equipped link finished loading. Compare the drop directly with current gear.
function BiS.WorldUpgrade(itemID)
    local value = BiS.Upgrade(itemID)
    if value then return value end
    local spec = Player:GetActiveSpec()
    if not spec or Items.IsOwned(itemID) or Items.IsOtherFaction(itemID) then return nil end
    local level = Player.level or 1
    if not Items.InList(itemID, spec.class, level) then return nil end
    local minLevel, itemLevel = Items.GetKnownLevels(itemID)
    if not minLevel or Items.UseLevelFrom(itemID, minLevel, itemLevel) > level then return nil end
    local itemID2, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not itemID2 or not equipLoc or equipLoc == "" then return nil end
    local facts = { id = itemID, equipLoc = equipLoc, classID = classID, subclassID = subclassID }
    if not Player:CanClassUse(facts, spec.class, level) or Scoring.MissingSkill(itemID) then return nil end
    local stats = Scoring.GetStats(itemID)
    if not stats then return nil end
    local best
    for _, slot in ipairs(Scoring.GetItemSlots(facts, spec.class, level)) do
        local worn = Scoring.GetEquippedScore(spec, slot, true)
        local score = Scoring.Score(itemID, spec, slot, true, stats)
        if worn and score then
            local gain = score - worn
            if gain > 0 and (not best or gain > best) then best = gain end
        end
    end
    return best
end

-- Every item of the list the character does not own yet, the best first.
function BiS.Targets()
    local list = {}
    for id, t in pairs(Current() or {}) do
        if not Items.IsOwned(id) then list[#list + 1] = t end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.id < b.id
    end)
    return list
end

-- The mark of an item on the list: "+3.1 DPS" (the gain the sim found), "+2.4%" (Percent: what it adds to the whole
-- gear), else "BiS"; nil when it is not on it.
function BiS.UpgradeText(itemID)
    local t = BiS.Target(itemID)
    if not t then return nil end
    if t.delta and LJ.SimBiS.Shows(t.delta, t.err) then return string.format("+%.1f DPS", t.delta) end
    if t.pct then return string.format("+%.1f%%", t.pct) end
    return L("BiS")
end

-- The mark in green, nil when the item is not on the list.
function BiS.FormatUpgrade(itemID)
    local text = BiS.UpgradeText(itemID)
    return text and ("|cff55ee55" .. text .. "|r")
end

-- True when the character's class can never use the item, or it asks for a profession the character lacks.
function BiS.Unusable(rec, spec)
    if not (spec and rec.loaded and (rec.classID == 2 or rec.classID == 4)) then return false end
    if not Player:CanClassUse(rec, spec.class) then return true end
    return spec.class == Player.class and Scoring.MissingSkill(rec.id) ~= nil
end

local function Forget() targets = nil end
for _, message in ipairs({ "DB_READY", "SIM_BIS_CHANGED", "EQUIPMENT_CHANGED", "SPEC_CHANGED", "PLAYER_CHANGED",
    "MODULES_CHANGED", "LIST_CHANGED" }) do
    LJ:Listen(message, Forget)
end
LJ:Listen("ITEMS_UPDATED", function()
    if wornUnknown then targets = nil end
end)
