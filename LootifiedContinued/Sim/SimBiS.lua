-- Lootified - the simulator's Best in Slot list ("sim Best in Slot"): every item of the addon the character can wear
-- at its level is simmed in its slot against what is worn, of them only what its list takes (Core/BiS.lua: the
-- sources the player picked): a quick pass for all of them, then the best few of each slot exactly, then the best of
-- every slot worn as one set (a paladin gets a set for each seal and the better one counts). Kept per character and
-- spec with the level, the gear and the list it was simmed with. With Sim (LJ.cdb.rating) it is the character's Best in Slot list
-- (Core/BiS.lua): the sheet shows its winners, the upgrade marks, tooltips and For you show its items. It only runs
-- when the player presses it (For you, the simulator's "Best in Slot sim" button); a changed level, gear or talents
-- make it outdated, and a run that no longer fits them ends. Its fights last a minute (SimBiS.LENGTH), whatever the
-- simulator window's length; the target is the window's. One fight job at a time (Sim/Jobs.lua; in combat the fights
-- wait).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Sim = LJ.Sim
local SimBiS = {}
LJ.SimBiS = SimBiS

SimBiS.QUICK = 40                    -- fights per item in the quick pass
SimBiS.BEST = 5                      -- items per slot simmed exactly after it
SimBiS.LENGTH = 60                   -- seconds of every fight: up to level 60 a fight lasts about a minute

-- Sheet slot -> equipment slot
local INV_SLOT = {
    HEAD = 1, NECK = 2, SHOULDER = 3, BACK = 15, CHEST = 5, WRIST = 9, HANDS = 10, WAIST = 6, LEGS = 7, FEET = 8,
    FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, MAINHAND = 16, OFFHAND = 17, RANGED = 18,
}
SimBiS.INV_SLOT = INV_SLOT

-- The sheet slots of an item's slots (a ring both ring slots, a two-hander the main hand ...).
local SHEET_SLOTS = { FINGER = { "FINGER1", "FINGER2" }, TRINKET = { "TRINKET1", "TRINKET2" }, TWOHAND = { "MAINHAND" },
    RELIC = { "RANGED" } }

-- The sheet slots an item goes in for the player's class; nil when the class cannot wear it (its armor or weapon type
-- and "Classes:"; level rules like mail at 40 do not count here).
function SimBiS.SheetSlots(itemID)
    local id, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not (id and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE") then return nil end
    local class = LJ.Player.class
    local facts = { id = itemID, equipLoc = equipLoc, classID = classID, subclassID = subclassID }
    local slots = LJ.Scoring.GetItemSlots(facts, class)
    if #slots == 0 or not LJ.Player:CanClassUse(facts, class) then return nil end
    local out = {}
    for _, s in ipairs(slots) do
        for _, sheet in ipairs(SHEET_SLOTS[s] or { s }) do out[#out + 1] = sheet end
    end
    return out
end

function SimBiS.Fits(itemID, slot)
    for _, s in ipairs(SimBiS.SheetSlots(itemID) or {}) do
        if s == slot then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- What is simmed
---------------------------------------------------------------------------
-- True when a character of a class and level can put an item on (facts: a scratch table it fills with the item's
-- facts): its class wears the item's kind at that level (Player:CanClassUse: "Classes:", armor learned later), the
-- item's level is reached and the character has the profession it asks for.
local function Wearable(id, facts, class, level)
    local Items = LJ.Items
    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if not itemID or not equipLoc or equipLoc == "" then return false end
    facts.id, facts.equipLoc, facts.classID, facts.subclassID = id, equipLoc, classID, subclassID
    if not LJ.Player:CanClassUse(facts, class, level) then return false end
    local minLevel, itemLevel = Items.GetKnownLevels(id)
    if not minLevel or Items.UseLevelFrom(id, minLevel, itemLevel) > level then return false end
    return LJ.Scoring.MissingSkill(id) == nil
end

local scratch = {}
-- True when the player can put an item on now (whatever the simulator makes of it: the planner offers it).
function SimBiS.CanWear(id)
    return Wearable(id, scratch, LJ.Player.class, LJ.Player.level or 1)
end

-- The level from which the player can put an item on: its use level, for armor the level its class learns the kind
-- (mail, plate: 40); nil when it cannot up to the top level. (The planner's "Higher levels".)
function SimBiS.WearLevel(id)
    local class = LJ.Player.class
    if not Wearable(id, scratch, class, LJ.BiS.MAX_LEVEL) then return nil end
    local minLevel, itemLevel = LJ.Items.GetKnownLevels(id)
    local level = LJ.Items.UseLevelFrom(id, minLevel, itemLevel)
    if scratch.classID == 4 then level = math.max(level, LJ.Player.ARMOR[class][scratch.subclassID]) end
    return level
end

-- Every item of the addon (Scoring's candidates: dungeon and raid loot, open world drops and quest rewards, the
-- shipped Best in Slot items) the character can get and wear in each sheet slot at its level, with stats the shipped
-- data knows and the simulator counts (or a weapon's damage): { [sheet slot] = { item IDs } }. Kept per spec and level
-- until the character changes (PLAYER_CHANGED: a profession, Dual Wield).
local pool, poolKey
function SimBiS.Pool(spec)
    local Items, Scoring, Player = LJ.Items, LJ.Scoring, LJ.Player
    local level = Player.level or 1
    local key = spec.key .. ":" .. level
    if pool and poolKey == key then return pool end
    local class = spec.class
    local out = {}
    for _, slot in ipairs(LJ.BiS.SLOTS) do out[slot] = {} end
    local facts = {}
    local function Consider(id, world)
        if not Wearable(id, facts, class, level) or Items.IsOtherFaction(id) then return end
        -- quest rewards of the other faction or another class's quests are not for this character
        if world and not Items.IsObtainable(id, class) then return end
        local stats = Items.IsShipped(id) and Scoring.GetStats(id)
        if not stats or not (Sim.Character.Counts(stats) or Items.GetWeapon(id)) then return end
        for _, dataSlot in ipairs(Scoring.GetItemSlots(facts, class, level)) do
            for _, sheet in ipairs(SHEET_SLOTS[dataSlot] or { dataSlot }) do
                local list = out[sheet]
                if list then list[#list + 1] = id end
            end
        end
    end
    for _, id in ipairs(Scoring.GetBaseCandidateIDs()) do Consider(id, false) end
    for _, id in ipairs(Scoring.GetWorldCandidateIDs()) do Consider(id, true) end
    pool, poolKey = out, key
    return out
end

-- What the fights of some sheet slots compare: the pool's items the Best in Slot list takes (BiS.OnSheet: the sources
-- the player picked, a tank's in its heaviest armor) and, simmed exactly anyway, extra (an item to look at);
-- never an item that is worn (in any slot: a worn ring is no pick for the other ring slot). The off hand is skipped beside a
-- two-hander. Returns the picks for Sim.Jobs.BestItems (key: the sheet slot) and bySlot = { [sheet slot] = { worn,
-- skipped, rows = {} } }.
function SimBiS.Picks(spec, char, slots, extra)
    local worn = {}
    for _, s in pairs(INV_SLOT) do
        local id = GetInventoryItemID("player", s)
        if id then worn[id] = true end
    end
    local all = SimBiS.Pool(spec)
    local picks, bySlot = {}, {}
    local twoHand = LJ.BiS.IsTwoHand(char.items[INV_SLOT.MAINHAND])
    for _, slot in ipairs(slots) do
        local skipped = slot == "OFFHAND" and twoHand and "Two-hander in the main hand" or nil
        bySlot[slot] = { rows = {}, worn = GetInventoryItemID("player", INV_SLOT[slot]), skipped = skipped }
        if not skipped then
            local keep, seen = {}, {}
            local function Keep(id)
                if not worn[id] and not seen[id] then
                    seen[id] = true
                    keep[#keep + 1] = id
                end
            end
            if extra and SimBiS.Fits(extra, slot) then Keep(extra) end
            local ids = {}
            for _, id in ipairs(all[slot]) do
                if not worn[id] and not seen[id] and LJ.BiS.OnSheet(spec, id, LJ.Player.level) then
                    ids[#ids + 1] = id
                end
            end
            if #ids + #keep > 0 then
                picks[#picks + 1] = { slot = INV_SLOT[slot], ids = ids, keep = keep, key = slot }
            end
        end
    end
    return picks, bySlot
end

-- The best pick of every slot: the first row with a gain that shows (more than twice its error); of two ring, trinket
-- or weapon slots with the same best item, the slot it helps less takes its next one. slots = { [sheet slot] = { rows } }.
function SimBiS.BestPicks(slots)
    local best = {}
    for slot, r in pairs(slots) do
        for _, row in ipairs(r.rows) do
            if not row.failed and row.delta > 2 * row.err and row.delta > 0.05 then
                best[slot] = best[slot] or {}
                best[slot][#best[slot] + 1] = row
            end
        end
    end
    for _, pair in ipairs({ { "FINGER1", "FINGER2" }, { "TRINKET1", "TRINKET2" }, { "MAINHAND", "OFFHAND" } }) do
        local a, b = best[pair[1]], best[pair[2]]
        if a and b and a[1].id == b[1].id then
            local loser = a[1].delta >= b[1].delta and pair[2] or pair[1]
            table.remove(best[loser], 1)
        end
    end
    local out = {}
    for slot, list in pairs(best) do out[slot] = list[1] end
    return out
end

-- The set of a pass of Sim.Jobs.BestItems (slots: its result's, in the order of picks): every slot's best pick
-- (SimBiS.BestPicks) as { { slot (equipment slot), id } } in sheet order; no off hand beside a two-hander.
function SimBiS.SetOf(slots, picks)
    local bySlot = {}
    for i, pick in ipairs(picks) do bySlot[pick.key] = { rows = slots[i].rows } end
    local best = SimBiS.BestPicks(bySlot)
    local twoHand = best.MAINHAND and select(4, C_Item.GetItemInfoInstant(best.MAINHAND.id)) == "INVTYPE_2HWEAPON"
    local items = {}
    for _, sheet in ipairs(LJ.BiS.SLOTS) do
        if best[sheet] and not (sheet == "OFFHAND" and twoHand) then
            items[#items + 1] = { slot = INV_SLOT[sheet], id = best[sheet].id }
        end
    end
    return items
end

---------------------------------------------------------------------------
-- What was simmed: per character (LootifiedCharData.simBiS) and spec
---------------------------------------------------------------------------
-- What the character fights with, one text: the worn items and the talents (Player:TalentsText). A change of either
-- makes the sims outdated: the sim Best in Slot, the Character tab's last numbers, the item checks.
function SimBiS.Setup()
    local ids = {}
    for _, slot in ipairs(LJ.BiS.SLOTS) do ids[#ids + 1] = tostring(GetInventoryItemID("player", INV_SLOT[slot]) or 0) end
    return table.concat(ids, ",") .. "|" .. LJ.Player:TalentsText()
end

-- The record of a spec of the character: { level, setup (the worn items and the talents when it started), list (its
-- key: Items.ListKey), time, base (DPS), tested (items of the quick pass), foot, slots = { [sheet slot] = { worn, skipped, rows = { { id, delta, err }
-- or { id, failed } } } }, best = { [sheet slot] = { id, delta, err } } }; nil when the spec was never simmed (another
-- class's spec: never) and while items are rated in Percent (LJ.cdb.rating: it is kept for Sim).
function SimBiS.Get(spec)
    if not spec or spec.class ~= LJ.Player.class or LJ.cdb.rating ~= "sim" then return nil end
    return LJ.cdb.simBiS[spec.key]
end

-- Simmed with the level, the gear and the talents of now: what single items did still counts (Sim/ItemCheck.lua).
function SimBiS.Fought(rec)
    return rec.level == LJ.Player.level and rec.setup == SimBiS.Setup()
end

-- Simmed at another level, with other gear, talents or list, or by a sim before the set's gain was simmed (gain).
function SimBiS.IsOutdated(rec)
    return not SimBiS.Fought(rec) or rec.list ~= LJ.Items.ListKey() or rec.gain == nil
end

-- Keeps the fights of every slot (result = { base = run, tested, gain, slots = { [sheet slot] = { worn, skipped, rows }
-- } }), with the level, the gear, the talents and the list the fights started with.
function SimBiS.Save(spec, result, run)
    local slots = {}
    for slot, r in pairs(result.slots) do
        local rows = {}
        for i, row in ipairs(r.rows) do
            rows[i] = row.failed and { id = row.id, failed = row.failed } or { id = row.id, delta = row.delta, err = row.err }
        end
        slots[slot] = { worn = r.worn, skipped = r.skipped, rows = rows }
    end
    local best = {}
    for slot, row in pairs(SimBiS.BestPicks(slots)) do best[slot] = { id = row.id, delta = row.delta, err = row.err } end
    LJ.cdb.simBiS[spec.key] = { level = run.level, setup = run.setup, list = run.list, time = time(), base = result.base.dps,
        tested = result.tested, gain = result.gain, foot = result.foot, slots = slots, best = best }
    LJ:Fire("SIM_BIS_CHANGED")
end

-- A sheet slot the sim decides: its record's slot when it had items to test, else nil (no picks, the off hand beside
-- a two-hander, the spec never simmed). Outdated records count (the sheet says so).
function SimBiS.Simmed(spec, slot)
    local rec = SimBiS.Get(spec)
    local r = rec and rec.slots[slot]
    return r and #r.rows > 0 and r or nil
end

-- The sim's winner of a sheet slot: its best pick, or what was worn when no pick does more; nil when the slot was not
-- simmed (SimBiS.Simmed).
function SimBiS.Winner(spec, slot)
    local r = SimBiS.Simmed(spec, slot)
    if not r then return nil end
    local best = SimBiS.Get(spec).best[slot]
    if best then return best.id, best end
    return r.worn
end

-- What the sim found for an item in a slot: { delta, err } (for what was worn: delta 0), nil when it was not simmed
-- there.
function SimBiS.SlotGain(spec, slot, itemID)
    local rec = SimBiS.Get(spec)
    local r = rec and rec.slots[slot]
    if not r then return nil end
    if itemID == r.worn and #r.rows > 0 then return { delta = 0, err = 0 } end
    for _, row in ipairs(r.rows) do
        if row.id == itemID and not row.failed then return row end
    end
    return nil
end

-- A gain that shows: more than twice its error and at least 0.05 DPS (else the fights cannot tell).
function SimBiS.Shows(delta, err)
    return delta > 2 * err and delta > 0.05
end

-- What an own set adds by the spec's current sim Best in Slot (the Best in Slot sheet): counted from the nearer of what
-- is worn (0) and the list's set (its own fights: gain), plus what each item it changes added alone in its slot (an
-- estimate: items count together). gain, exact (the set is one of the two); nil without current numbers, when an item
-- it changes was not simmed in its slot or a slot is empty where something is worn. pick(slot): its item of a sheet
-- slot.
function SimBiS.SetGain(spec, pick)
    local rec = SimBiS.Get(spec)
    if not rec or SimBiS.IsOutdated(rec) then return nil end
    local BiS = LJ.BiS
    -- a set's items by sheet slot, none beside a two-hander
    local function Of(f)
        local out = {}
        for _, slot in ipairs(BiS.SLOTS) do out[slot] = f(slot) end
        if BiS.IsTwoHand(out.MAINHAND) then out.OFFHAND = nil end
        return out
    end
    local ranking = BiS.Ranking(spec)
    local set, list = Of(pick), Of(function(slot) return BiS.ResolveSlot(spec, slot, ranking) end)
    local worn = Of(function(slot) return GetInventoryItemID("player", INV_SLOT[slot]) end)
    -- what an item of a set added alone: what is worn and the off hand beside a two-hander (in its gain) nothing
    local function Alone(items, slot)
        if items[slot] == worn[slot] or (slot == "OFFHAND" and BiS.IsTwoHand(items.MAINHAND)) then return 0 end
        local row = items[slot] and SimBiS.SlotGain(spec, slot, items[slot])
        return row and row.delta
    end
    local function Changes(from)
        local n = 0
        for _, slot in ipairs(BiS.SLOTS) do
            if set[slot] ~= from[slot] then n = n + 1 end
        end
        return n
    end
    local from, gain = worn, 0
    if Changes(list) < Changes(worn) then from, gain = list, rec.gain end
    local exact = true
    for _, slot in ipairs(BiS.SLOTS) do
        if set[slot] ~= from[slot] then
            local now, before = Alone(set, slot), Alone(from, slot)
            if not (now and before) then return nil end
            gain, exact = gain + now - before, false
        end
    end
    return gain, exact
end

---------------------------------------------------------------------------
-- Running it
---------------------------------------------------------------------------
-- The running sim Best in Slot: { spec, progress (0-1), level, gear } or nil.
SimBiS.running = nil
-- Why the last run stopped (an error in its fights; For you shows it), nil when it did not.
SimBiS.problem = nil

-- Stop (For you, the simulator window), or the run no longer fits: the running sim Best in Slot ends, nothing is kept.
function SimBiS.Cancel()
    if not SimBiS.running then return end
    SimBiS.running = nil
    Sim.Jobs.Cancel()
    LJ:Fire("SIM_BIS_CHANGED")
end

-- A press that cannot run says why, in a popup (UI/SimNotice.lua): the same for every button that starts the sim (For
-- you, the Best in Slot sheet, the tour).
local function Refuse(text)
    LJ:Fire("SIM_BIS_REFUSED", text)
end

-- Sims every slot of a character (read from the game: Sim.Character.Read) for a spec: the quick pass over every item of
-- its list it can wear, then the best of each slot exactly; keeps the result (SimBiS.Save). onProgress(0-1),
-- onDone(result, err): result = { base = run, tested, gain, slots = { [sheet slot] = { worn, skipped, rows (with their
-- runs) } } }. Without any pick (nothing of the list the character can wear yet) nothing runs: it says so and onDone
-- gets the slots at once.
function SimBiS.Run(spec, model, char, opts, onProgress, onDone)
    SimBiS.Cancel()
    local picks, bySlot = SimBiS.Picks(spec, char, LJ.BiS.SLOTS)
    if #picks == 0 then
        Refuse(L("Nothing to Sim yet - nothing of your list can be worn at your level. The filter on the Best in Slot page takes more sources."))
        onDone({ slots = bySlot })
        return
    end
    local run = { spec = spec, progress = 0, level = LJ.Player.level, setup = SimBiS.Setup(), list = LJ.Items.ListKey() }
    SimBiS.running = run
    SimBiS.problem = nil
    local n = Sim.Jobs.FIGHTS
    local started = debugprofilestop()
    local shown = -1
    onProgress(0)
    LJ:Fire("SIM_BIS_CHANGED")
    Sim.Jobs.Start(Sim.Jobs.BestItems(char, model, opts, SimBiS.QUICK, n, SimBiS.BEST, picks, SimBiS.SetOf), function(p)
        run.progress = p
        onProgress(p)
        local pct = math.floor(p * 100)
        if pct ~= shown then
            shown = pct
            LJ:Fire("SIM_BIS_PROGRESS")
        end
    end, function(result, err)
        if SimBiS.running ~= run then return end
        SimBiS.running = nil
        if err then
            SimBiS.problem = F(L("The simulator stopped: %s"), (tostring(err):gsub("^.-:%d+: ", "")))
            LJ:Fire("SIM_BIS_CHANGED")
            onDone(nil, err)
            return
        end
        for i, pick in ipairs(picks) do bySlot[pick.key].rows = result.slots[i].rows end
        local out = { base = result.base, tested = result.tested, gain = result.gain, slots = bySlot }
        out.foot = F(L("%d items tested · %.1f s"), result.tested, (debugprofilestop() - started) / 1000)
        -- the way the best set is played (a paladin's seal ...)
        if result.variant then
            out.foot = out.foot .. " · " .. F(L("Best set: %s"), LJ.UI.Sim.VariantText(model, result.variant))
        end
        SimBiS.Save(spec, out, run)
        onDone(out)
    end, function()
        -- another job took its place: nothing is kept
        if SimBiS.running == run then
            SimBiS.running = nil
            LJ:Fire("SIM_BIS_CHANGED")
        end
    end)
end

-- The press waiting for the data of what is worn (SimBiS.WhenGearRead), nil when none waits.
local gearWait

-- Calls onRead(gear) with the stats of everything worn, gear = { [equipment slot] = stats } (Scoring.GetStatsForLink:
-- the equipped item's link, random suffixes count). The game has an item's data only after it was asked for and can
-- drop it again right away (Blizzard_ObjectAPI ContinuableContainer checks again before it calls back; /lf collect
-- lost most item names it had loaded): what it lacks is asked for and read the moment it arrives. A slot the game
-- has no data for stays out (Character.AssertGear names it). A newer press takes the place of one still waiting.
function SimBiS.WhenGearRead(onRead)
    local wait = {}
    gearWait = wait
    local gear, missing, left = {}, {}, 0
    local function Read(slot)
        local link = GetInventoryItemLink("player", slot)
        gear[slot] = link and LJ.Scoring.GetStatsForLink(link) or nil
    end
    for _, slot in pairs(INV_SLOT) do
        local id = GetInventoryItemID("player", slot)
        if id then
            Read(slot)
            if not gear[slot] then
                missing[slot] = id
                left = left + 1
            end
        end
    end
    local function Done()
        if gearWait ~= wait then return end
        gearWait = nil
        onRead(gear)
    end
    if left == 0 then return Done() end
    for slot, id in pairs(missing) do
        LJ.Items.Request(id, function()
            Read(slot)
            left = left - 1
            if left == 0 then Done() end
        end, true)
    end
end

-- Reads the character for a spec once the game has the data of everything worn and sims every slot; a character that
-- cannot be read (in combat, no pet ...) says why (Refuse). onProgress and onDone as SimBiS.Run (optional).
function SimBiS.Start(spec, onProgress, onDone)
    assert(LJ.UI.Sim.RanksItems(spec), "the Best in Slot sim builds the lists of Sim")
    SimBiS.WhenGearRead(function(gear)
        local model = LJ.UI.Sim.Model(spec)
        local ok, char = pcall(Sim.Character.Read, model, spec.key)
        if not ok then
            Refuse(LJ.UI.Sim.ProblemText(char))
            return
        end
        char.slotStats = gear
        SimBiS.Run(spec, model, char, { length = SimBiS.LENGTH, levelOffset = LJ.db.sim.target },
            onProgress or function() end, onDone or function() end)
    end)
end

-- The level, the gear or the talents changed: a running sim no longer fits them and ends (as on another spec).
local function StateChanged()
    local run = SimBiS.running
    if run and (run.level ~= LJ.Player.level or run.setup ~= SimBiS.Setup()) then SimBiS.Cancel() end
end

LJ:Listen("EQUIPMENT_CHANGED", StateChanged)
LJ:Listen("PLAYER_CHANGED", StateChanged)
-- the level, a profession or Dual Wield changed what the character can wear: the item list is made again
LJ:Listen("PLAYER_CHANGED", function() pool = nil end)
LJ:Listen("SPEC_CHANGED", function()
    local run, spec = SimBiS.running, LJ.Player:GetActiveSpec()
    if run and not (spec and spec.key == run.spec.key) then SimBiS.Cancel() end
    StateChanged()
end)
