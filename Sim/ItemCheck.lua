-- Lootified - is an item an upgrade for the character's active spec? One answer per item (its link: a random suffix
-- like "of the Bear" counts) for the box beside a loot roll, the box Alt+Click opens and the item tooltips
-- (UI/ItemCheckBox.lua, UI/Tooltip.lua). Sim (LJ.cdb.rating): what the sim found with what is worn now (this module's
-- own fights of the item, or those of the sim Best in Slot while the level and what is worn are the ones it fought
-- with), else the hidden ranking's estimate (Core/Scoring.lua). Percent: the spec's stat weights, as its Best in Slot
-- list, with the share the item adds to the whole gear (no item fights); the same share per sheet slot and for
-- whole sets (the pickers, the Best in Slot sheet). And what keeps the character from wearing it (its class, a
-- profession, its level). An item fights only on a press (the box's Sim, Alt+Click): against what is worn, in each
-- slot it goes in; the slot where it does more counts. Its numbers are kept per character and spec (LootifiedCharData.itemSims) with
-- the level and the gear they were fought with. No frames here.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Sim = LJ.Sim
local SimBiS = LJ.SimBiS
local Items = LJ.Items
local Player = LJ.Player
local Scoring = LJ.Scoring

local ItemCheck = {}
LJ.ItemCheck = ItemCheck

-- The item of a link: its ID, the key of its numbers (the ID; with a random suffix "ID:suffix") and whether it has a
-- random suffix (the item string's seventh field, as Scoring.GetStatsForLink reads it).
local function Parse(link)
    local id = tonumber(link:match("item:(%d+)"))
    assert(id, "no item link: " .. link)
    local suffix = link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d*)")
    if suffix and suffix ~= "" and suffix ~= "0" then return id, id .. ":" .. suffix, true end
    return id, tostring(id), false
end
ItemCheck.Parse = Parse

-- The sheet slots the simulator can fight an item in now: those of SimBiS.SheetSlots without the off hand beside a
-- two-hander in the main hand.
local function FightSlots(itemID)
    local mainHand = GetInventoryItemID("player", SimBiS.INV_SLOT.MAINHAND)
    local twoHand = mainHand and LJ.BiS.IsTwoHand(mainHand)
    local slots = {}
    for _, slot in ipairs(SimBiS.SheetSlots(itemID) or {}) do
        if not (slot == "OFFHAND" and twoHand) then slots[#slots + 1] = slot end
    end
    return slots
end

-- What the sim says about an item with what is worn now: { delta, err, slot (sheet slot) }; nil when it never fought
-- with what is worn now (its own fights first, then the sim Best in Slot's for an item without a random suffix: the
-- slot where it does more).
function ItemCheck.Number(link)
    local spec = Player:GetActiveSpec()
    if not (spec and LJ.UI.Sim.RanksItems(spec)) then return nil end
    local id, key, suffixed = Parse(link)
    local setup = SimBiS.Setup()
    local own = LJ.cdb.itemSims[spec.key]
    local e = own and own[key]
    if e and e.setup == setup and e.level == Player.level then return e end
    if suffixed then return nil end
    local rec = SimBiS.Get(spec)
    if not (rec and SimBiS.Fought(rec)) then return nil end
    local best
    for _, slot in ipairs(FightSlots(id)) do
        local row = SimBiS.SlotGain(spec, slot, id)
        if row and (not best or row.delta > best.delta) then
            best = { delta = row.delta, err = row.err, slot = slot }
        end
    end
    return best
end

-- The direction of a number: "up" (an upgrade: more than twice its error, SimBiS.Shows), "down" or "same".
function ItemCheck.Direction(n)
    if SimBiS.Shows(n.delta, n.err) then return "up" end
    if SimBiS.Shows(-n.delta, n.err) then return "down" end
    return "same"
end

-- The direction of a verdict by the stat weights (kind "stats"): "up", "down" or "same" (the share shown as +0.0 %);
-- without a share (an empty slot) up when it scores at all.
function ItemCheck.StatsDirection(v)
    if not v.pct then return v.better and "up" or "same" end
    if v.pct >= 0.05 then return "up" end
    if v.pct <= -0.05 then return "down" end
    return "same"
end

-- Gear for a slot of the sheet (Scoring's slots: weapons, armor, rings ...); bags, shirts, tabards, ammo are none.
local function IsGear(equipLoc)
    return equipLoc == "INVTYPE_WEAPON" or Scoring.EQUIPLOC_SLOTS[equipLoc] ~= nil
end

-- The score by a spec's stat weights of what is worn in a sheet slot (its link's stats: a random suffix counts); 0 for
-- an empty slot, nil while the game has no data of it yet.
local function WornScore(spec, slot)
    return (Scoring.EquippedScore(SimBiS.INV_SLOT[slot], spec, slot, true))
end

-- The score of everything worn (every sheet slot): the base of the shares in percent, so a share is what an item adds
-- to the whole gear (also in an empty slot; a slot's weak item does not make it thousands of percent); nil while the
-- game has no data of a worn item yet.
local function WornTotal(spec)
    local total = 0
    for _, slot in ipairs(LJ.BiS.SLOTS) do
        local base = WornScore(spec, slot)
        if not base then return nil end
        total = total + base
    end
    return total
end
ItemCheck.WornTotal = WornTotal

-- The hidden ranking's estimate for an item (its stats from the link) against what is worn where it goes: better
-- (true when it scores above what is worn in one of its slots), the item worn there (the slot where it scores the
-- most above it) and what it adds to the whole gear in percent (WornTotal; nil when nothing worn scores); nil while
-- the stats of the item or of what is worn there are not known yet.
local function Estimate(spec, id, link, facts)
    local stats = Scoring.GetStatsForLink(link)
    if not stats then return nil end
    local best, replaces
    for _, dataSlot in ipairs(Scoring.GetItemSlots(facts, spec.class)) do
        local worn, wornID = Scoring.GetEquippedScore(spec, dataSlot, true)
        if worn == nil then return nil end
        local margin = Scoring.Score(id, spec, dataSlot, true, stats) - worn
        if not best or margin > best then best, replaces = margin, wornID end
    end
    if not best then return nil end
    local total = WornTotal(spec)
    return best > 0, replaces, total and total > 0 and best / total * 100 or nil
end

-- An item by the stat weights of a spec (Percent: the tooltips and the boxes):
-- { better, pct, replaces } as Estimate gives them; nil while its stats or those of what is worn there are not known.
function ItemCheck.Share(spec, link)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    local id = Parse(link)
    local better, replaces, pct = Estimate(spec, id, link,
        { id = id, equipLoc = equipLoc, classID = classID, subclassID = subclassID })
    if better == nil then return nil end
    return { better = better, pct = pct, replaces = replaces }
end

-- An item in a sheet slot by a spec's stat weights against what is worn in that slot (a two-hander in the main hand:
-- against both hands): what it adds to the whole gear in percent (WornTotal; Percent: the pickers, the Best in Slot
-- sheet); 0 for what is worn there, nil when nothing worn scores or the stats of an item are not known yet.
function ItemCheck.SlotShare(spec, slot, id)
    if id == GetInventoryItemID("player", SimBiS.INV_SLOT[slot]) then return 0 end
    local base = WornScore(spec, slot)
    if base and slot == "MAINHAND" and LJ.BiS.IsTwoHand(id) then
        local off = WornScore(spec, "OFFHAND")
        base = off and base + off
    end
    local score = Scoring.Score(id, spec, slot, true)
    local total = WornTotal(spec)
    if not (base and score and total and total > 0) then return nil end
    return (score - base) / total * 100
end

-- A set by a spec's stat weights against what is worn, in percent (Percent: the Best in Slot sheet; the
-- weights add up, so it is the set's own share, no estimate): pick(slot) gives its item of a sheet slot (none beside a
-- two-hander in its main hand); nil while the stats of an item are not known yet or nothing worn scores.
function ItemCheck.SetShare(spec, pick)
    local twoHand = LJ.BiS.IsTwoHand(pick("MAINHAND"))
    local worn, set = 0, 0
    for _, slot in ipairs(LJ.BiS.SLOTS) do
        local base = WornScore(spec, slot)
        if not base then return nil end
        worn = worn + base
        local id = pick(slot)
        if slot == "OFFHAND" and twoHand then id = nil end
        if id == GetInventoryItemID("player", SimBiS.INV_SLOT[slot]) then
            set = set + base
        elseif id then
            local score = Scoring.Score(id, spec, slot, true)
            if not score then return nil end
            set = set + score
        end
    end
    if worn <= 0 then return nil end
    return (set - worn) / worn * 100
end

-- The verdict on an item for the active spec; nil without a spec or for things that are not gear. { kind, ... }:
--   "worn": the character wears it;
--   "cannot": why (its class cannot use it, an off-hand weapon without Dual Wield, a profession it lacks, armor lighter
--     than a tank wears: LJ.BiS.ArmorFits);
--   "level": level (the level it can be worn from);
--   "sim": delta, err, slot (what the sim found, ItemCheck.Number);
--   "estimate": better (the hidden ranking's estimate, not simmed yet);
--   "stats": better, pct (Percent: the stat weights decide; pct: what it adds to the whole gear, nil while nothing worn
--     scores);
--   "unknown": not simmed and no estimate yet (the game has not all data of the item or of what is worn there).
-- sim, estimate, stats and unknown also have replaces (the item worn where it goes, nil: that slot is empty); all but
-- stats canSim (the simulator plays the spec and has a slot to fight it in; never with Percent).
function ItemCheck.Get(link)
    local spec = Player:GetActiveSpec()
    if not spec then return nil end
    local id = Parse(link)
    local _, _, subType, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not IsGear(equipLoc) then return nil end
    if C_Item.IsEquippedItem(id) then return { kind = "worn" } end
    local facts = { id = id, equipLoc = equipLoc, classID = classID, subclassID = subclassID }
    if not Player:CanClassUse(facts, spec.class) then
        if not Items.IsClassAllowed(id, spec.class) then return { kind = "cannot", why = L("Only other classes can use it.") } end
        if equipLoc == "INVTYPE_WEAPONOFFHAND" and not Player:CanDualWield(spec.class) then
            return { kind = "cannot", why = L("You cannot dual wield.") }
        end
        return { kind = "cannot", why = F(L("%s: your class cannot use it."), subType) }
    end
    local skill = Scoring.MissingSkill(id)
    if skill then return { kind = "cannot", why = skill } end
    -- the level: the item's own, and for armor the level the class learns its kind (mail, plate)
    local level = select(5, C_Item.GetItemInfo(link)) or Items.GetKnownLevels(id) or 0
    if classID == 4 then level = math.max(level, Player.ARMOR[spec.class][subclassID]) end
    if level > Player.level then return { kind = "level", level = level } end
    if not LJ.BiS.ArmorFits(spec, id, Player.level) then
        return { kind = "cannot", why = L("Tanks wear their heaviest armor.") }
    end

    local slots = FightSlots(id)
    if not LJ.UI.Sim.RanksItems(spec) then
        local share = ItemCheck.Share(spec, link)
        if not share then
            return { kind = "unknown", canSim = false,
                replaces = slots[1] and GetInventoryItemID("player", SimBiS.INV_SLOT[slots[1]]) }
        end
        return { kind = "stats", better = share.better, pct = share.pct, replaces = share.replaces }
    end
    local canSim = LJ.UI.Sim.Model(spec) ~= nil and #slots > 0
    local n = ItemCheck.Number(link)
    if n then
        return { kind = "sim", delta = n.delta, err = n.err, slot = n.slot, canSim = canSim,
            replaces = GetInventoryItemID("player", SimBiS.INV_SLOT[n.slot]) }
    end
    local better, replaces = Estimate(spec, id, link, facts)
    if better ~= nil then return { kind = "estimate", better = better, replaces = replaces, canSim = canSim } end
    return { kind = "unknown", canSim = canSim,
        replaces = slots[1] and GetInventoryItemID("player", SimBiS.INV_SLOT[slots[1]]) }
end

---------------------------------------------------------------------------
-- Fighting an item
---------------------------------------------------------------------------
-- The item fighting now (one at a time): { key, link, progress (0-1), gear, level }; nil when none fights.
ItemCheck.running = nil
-- Why the last press of an item did not fight: [key] = text for the player.
ItemCheck.problems = {}

-- Keeps what an item did in the slot where it did more, with the gear and level it fought with; the spec's numbers of
-- other gear or another level go (they no longer count).
local function Save(spec, key, row, slot, run)
    local list = LJ.cdb.itemSims[spec.key] or {}
    for k, e in pairs(list) do
        if e.setup ~= run.setup or e.level ~= run.level then list[k] = nil end
    end
    list[key] = { delta = row.delta, err = row.err, slot = slot, setup = run.setup, level = run.level }
    LJ.cdb.itemSims[spec.key] = list
end

local function Problem(key, text)
    ItemCheck.problems[key] = text
    LJ:Fire("ITEM_CHECK_CHANGED")
end

-- Fights an item (link) against what is worn: Sim.Jobs.FIGHTS fights in each slot it goes in (Sim.Jobs.ItemGain),
-- once the game has the data of the item and of everything worn; keeps the slot where it does more (ItemCheck.Number
-- has it). The press of a box's Sim or Alt+Click (the sim speed is picked: UI.SimSpeed); another item's press or
-- another sim takes its place. A character that cannot be read (in combat, no weapon ...) or an item the game has no
-- data of leaves its text in ItemCheck.problems.
function ItemCheck.Start(link)
    local spec = Player:GetActiveSpec()
    local model = assert(LJ.UI.Sim.Model(spec), "the simulator does not play the active spec")
    local id, key = Parse(link)
    ItemCheck.problems[key] = nil
    local slots = FightSlots(id)
    assert(#slots > 0, "no slot to fight item " .. id .. " in")
    local function Fight(gear)
        local stats = Scoring.GetStatsForLink(link)
        if not stats then
            Problem(key, L("The game has no data of this item yet: press Sim again in a moment."))
            return
        end
        local ok, char = pcall(Sim.Character.Read, model, spec.key)
        if not ok then
            Problem(key, LJ.UI.Sim.ProblemText(char))
            return
        end
        char.slotStats = gear
        local inv = {}
        for i, slot in ipairs(slots) do inv[i] = SimBiS.INV_SLOT[slot] end
        local run = { key = key, link = link, progress = 0, setup = SimBiS.Setup(), level = Player.level }
        ItemCheck.running = run
        local db = LJ.db.sim
        Sim.Jobs.Start(Sim.Jobs.ItemGain(char, model, { length = db.length, levelOffset = db.target }, Sim.Jobs.FIGHTS,
            id, stats, inv), function(p)
            run.progress = p
            -- a message per percent (the boxes show it)
            local pct = math.floor(p * 100)
            if pct ~= run.shown then
                run.shown = pct
                LJ:Fire("ITEM_CHECK_PROGRESS")
            end
        end, function(result, err)
            if ItemCheck.running ~= run then return end
            ItemCheck.running = nil
            if err then
                Problem(key, F(L("The simulator stopped: %s"), (tostring(err):gsub("^.-:%d+: ", ""))))
                return
            end
            local best, slot
            for i, row in ipairs(result.rows) do
                if not row.failed and (not best or row.delta > best.delta) then best, slot = row, slots[i] end
            end
            if best then
                Save(spec, key, best, slot, run)
            else
                ItemCheck.problems[key] = F(L("The simulator stopped: %s"), result.rows[1].failed)
            end
            LJ:Fire("ITEM_CHECK_CHANGED")
        end, function()
            if ItemCheck.running == run then
                ItemCheck.running = nil
                LJ:Fire("ITEM_CHECK_CHANGED")
            end
        end, true)
        LJ:Fire("ITEM_CHECK_CHANGED")
    end
    -- the item's own data first (its stats), then what is worn
    if Scoring.GetStatsForLink(link) then
        SimBiS.WhenGearRead(Fight)
    else
        Items.Request(id, function() SimBiS.WhenGearRead(Fight) end, true)
    end
end

-- Stops the item fighting now (its numbers are not kept).
function ItemCheck.Stop()
    if ItemCheck.running then Sim.Jobs.Cancel() end
end
