-- Lootified - quest data access: per-instance lists, prerequisites, live status, item <-> quest links.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Quests = {}
LJ.Quests = Quests

local Player = LJ.Player

Quests.rewardOf = {}    -- [itemID] = { questID, ... }  quest rewards (choice or fixed)
Quests.neededFor = {}   -- [itemID] = { questID, ... }  items a quest asks for
Quests.startedBy = {}   -- [itemID] = questID           items that start a quest

-- Status values, ordered by how they are sorted in lists.
Quests.READY = "READY"            -- in the quest log, objectives done
Quests.ACTIVE = "ACTIVE"          -- in the quest log
Quests.AVAILABLE = "AVAILABLE"    -- can be picked up now
Quests.LOCKED = "LOCKED"          -- prerequisite quests missing
Quests.LOW_LEVEL = "LOW_LEVEL"    -- character level too low
Quests.COMPLETED = "COMPLETED"
Quests.OTHER = "OTHER"            -- other faction or class

local STATUS_ORDER = { READY = 1, ACTIVE = 2, AVAILABLE = 3, LOCKED = 4, LOW_LEVEL = 5, COMPLETED = 6, OTHER = 7 }
Quests.STATUS_ORDER = STATUS_ORDER

---------------------------------------------------------------------------
-- Indexes
---------------------------------------------------------------------------
local function Add(index, key, value)
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    for i = 1, #list do
        if list[i] == value then return end
    end
    list[#list + 1] = value
end

local function BuildIndexes()
    for qid, q in pairs(LJ.Data.Quests or {}) do
        q.id = qid
        for _, itemID in ipairs(q.choice or {}) do Add(Quests.rewardOf, itemID, qid) end
        for _, itemID in ipairs(q.reward or {}) do Add(Quests.rewardOf, itemID, qid) end
        for _, it in ipairs(q.items or {}) do Add(Quests.neededFor, it.id, qid) end
        if q.start and q.start.kind == "item" and q.start.id then
            Quests.startedBy[q.start.id] = qid
        end
    end
end

-- Each item's quests in quest order (Items.QuestOrder: the character's own quests first), whatever order pairs gave:
-- the tooltip, the item menu and a click on the item in the search show the first ones. Ordered once the quests have
-- their names in the addon's language (Core/Locale.lua, DB_READY).
local function OrderIndexes()
    local function Order(a, b) return LJ.Items.QuestOrder(Quests.Get(a), Quests.Get(b)) end
    for _, index in ipairs({ Quests.rewardOf, Quests.neededFor }) do
        for _, list in pairs(index) do table.sort(list, Order) end
    end
end

function Quests.Get(qid)
    return LJ.Data.Quests and LJ.Data.Quests[qid]
end

function Quests.GetName(qid)
    local q = Quests.Get(qid)
    return q and q.name or F("Quest #%s", tostring(qid))
end

---------------------------------------------------------------------------
-- Faction and class
---------------------------------------------------------------------------
local SIDE = { Alliance = "A", Horde = "H" }

function Quests.IsForSide(q, side)
    return q.side == "B" or q.side == nil or q.side == side
end

function Quests.IsForClass(q, class)
    if not q.classes or #q.classes == 0 then return true end
    for _, c in ipairs(q.classes) do
        if c:upper() == class then return true end
    end
    return false
end

-- q.races: the race mask of a quest only some races of its side can take (bit raceID - 1: 1 Human, 2 Orc, 4 Dwarf,
-- 8 Night Elf, 16 Undead, 32 Tauren, 64 Gnome, 128 Troll); nil when the side says it all.
function Quests.IsForRace(q, raceID)
    return not q.races or math.floor(q.races / 2 ^ (raceID - 1)) % 2 == 1
end

-- Can the current character ever take this quest?
function Quests.IsForPlayer(q)
    return Quests.IsForSide(q, SIDE[Player.faction] or "A") and Quests.IsForClass(q, Player.class)
        and Quests.IsForRace(q, Player.race)
end

---------------------------------------------------------------------------
-- Live quest state (C_QuestLog), cached until the quest log changes or the window closes
---------------------------------------------------------------------------
local completedCache = {}
local logCache = {}
local objectivesCache = {}
local liveQuestCache
local liveQuestNameCache
-- an instance's counts (Quests.CountForInstance), made from the states above: [instKey] = { total, open, done }
local countCache = {}

local function IsFlaggedCompleted(qid)
    local v = completedCache[qid]
    if v == nil then
        v = C_QuestLog.IsQuestFlaggedCompleted(qid)
        completedCache[qid] = v
    end
    return v
end
Quests.IsCompleted = IsFlaggedCompleted

-- The game's state of a quest in the log: "READY", "ACTIVE" or false (not in the log).
local function LiveQuestIDs()
    if liveQuestCache then return liveQuestCache end
    local ids = {}
    local names = {}
    local function AddName(title, level)
        if type(title) ~= "string" or title == "" then return end
        local key = title:lower() .. "|" .. tostring(tonumber(level) or 0)
        names[key] = true
        names[title:lower()] = true
    end
    local count
    if GetNumQuestLogEntries then
        count = GetNumQuestLogEntries()
    elseif C_QuestLog.GetNumQuestLogEntries then
        count = C_QuestLog.GetNumQuestLogEntries()
    elseif C_QuestLog.GetQuestLogCount then
        count = C_QuestLog.GetQuestLogCount()
    end
    if count then
        for index = 1, count do
            local questID
            local title, level, isHeader
            if C_QuestLog.GetQuestIDForLogIndex then
                questID = C_QuestLog.GetQuestIDForLogIndex(index)
            end
            if not questID and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(index)
                questID = info and (info.questID or info.questId)
                if info then title, level, isHeader = info.title, info.level, info.isHeader end
            end
            if GetQuestLogTitle then
                local classicTitle, classicLevel, _, classicHeader, _, _, _, classicQuestID = GetQuestLogTitle(index)
                title, level, isHeader = classicTitle or title, classicLevel or level, classicHeader
                if not isHeader then questID = classicQuestID end
            end
            if not isHeader then AddName(title, level) end
            if questID and questID > 0 then ids[questID] = true end
        end
    end
    liveQuestCache = ids
    liveQuestNameCache = names
    return ids
end

-- Forever can report a quest as complete before an instance objective has
-- actually been finished. Never show READY while the live objective list says
-- that one of the quest's objectives is still open.
local function ObjectivesAreFinished(qid)
    if not C_QuestLog.GetQuestObjectives then return true end
    local objectives = C_QuestLog.GetQuestObjectives(qid)
    if type(objectives) ~= "table" or #objectives == 0 then return true end
    for _, objective in ipairs(objectives) do
        if objective.finished == false then return false end
        if objective.numRequired and objective.numFulfilled
            and objective.numFulfilled < objective.numRequired then
            return false
        end
    end
    return true
end

local function ReadLogState(qid)
    local live = LiveQuestIDs()
    local q = Quests.Get(qid)
    if next(live) then
        if not live[qid] then
            local names = liveQuestNameCache or {}
            local title = q and q.name and q.name:lower()
            local byLevel = title and (title .. "|" .. tostring(tonumber(q.level) or 0))
            if not (title and (names[byLevel] or names[title])) then return false end
        end
    elseif not C_QuestLog.IsOnQuest(qid) then
        return false
    end
    if q and q.completeWithItem and GetItemCount
        and GetItemCount(q.completeWithItem, true) < 1 then
        return Quests.ACTIVE
    end
    local ready = C_QuestLog.ReadyForTurnIn(qid) or C_QuestLog.IsComplete(qid)
    return ready and ObjectivesAreFinished(qid) and Quests.READY or Quests.ACTIVE
end

-- Returns "READY", "ACTIVE" or nil.
local function LogState(qid)
    local v = logCache[qid]
    if v == nil then
        v = ReadLogState(qid)
        logCache[qid] = v
    end
    return v or nil
end
Quests.GetLogState = LogState

-- The objectives of a quest in the log as the game states them (C_QuestLog.GetQuestObjectives).
function Quests.GetObjectives(qid)
    local v = objectivesCache[qid]
    if v == nil then
        v = C_QuestLog.GetQuestObjectives(qid) or {}
        objectivesCache[qid] = v
    end
    return v
end

local function Progress(objectives)
    local parts = {}
    for i, o in ipairs(objectives) do parts[i] = (o.numFulfilled or 0) .. (o.finished and "+" or "") end
    return table.concat(parts, ",")
end

-- True when a quest state read since the last change is no longer the game's.
local function Stale()
    for qid, v in pairs(completedCache) do
        if C_QuestLog.IsQuestFlaggedCompleted(qid) ~= v then return true end
    end
    for qid, v in pairs(logCache) do
        if ReadLogState(qid) ~= v then return true end
    end
    for qid, v in pairs(objectivesCache) do
        if Progress(C_QuestLog.GetQuestObjectives(qid) or {}) ~= Progress(v) then return true end
    end
    return false
end

function Quests.InvalidateCache()
    wipe(completedCache)
    wipe(logCache)
    wipe(objectivesCache)
    wipe(countCache)
    liveQuestCache = nil
    liveQuestNameCache = nil
end

---------------------------------------------------------------------------
-- Prerequisites
---------------------------------------------------------------------------
-- Missing prerequisites of a quest: { missing all-of ids }, { missing one-of groups }.
function Quests.GetMissingPrerequisites(q)
    local missing, missingGroups = {}, {}
    for _, p in ipairs(q.pre or {}) do
        if not IsFlaggedCompleted(p) then missing[#missing + 1] = p end
    end
    for _, group in ipairs(q.preAny or {}) do
        local done = false
        for _, p in ipairs(group) do
            if IsFlaggedCompleted(p) then done = true break end
        end
        if not done then missingGroups[#missingGroups + 1] = group end
    end
    return missing, missingGroups
end

-- Status of a quest for the current character. Returns status, detail (level for LOW_LEVEL,
-- number of missing quests for LOCKED).
function Quests.GetStatus(q)
    if type(q) == "number" then q = Quests.Get(q) end
    if not q then return Quests.OTHER end
    if IsFlaggedCompleted(q.id) then return Quests.COMPLETED end
    local log = LogState(q.id)
    if log then return log end
    if not Quests.IsForPlayer(q) then return Quests.OTHER end
    local missing, groups = Quests.GetMissingPrerequisites(q)
    if #missing + #groups > 0 then return Quests.LOCKED, #missing + #groups end
    local minLevel = q.min or 1
    if (Player.level or 1) < minLevel then return Quests.LOW_LEVEL, minLevel end
    return Quests.AVAILABLE
end

-- Which versions of a quest a chain shows (Alliance, Horde, class versions): the ones this character can take, or for
-- a quest of another faction or class the versions of that quest's faction and class.
function Quests.ChainFilter(q)
    if Quests.IsForPlayer(q) then return Quests.IsForPlayer end
    return function(rec)
        if (q.side == "A" or q.side == "H") and not Quests.IsForSide(rec, q.side) then return false end
        if q.classes and #q.classes > 0 and rec.classes and #rec.classes > 0 then
            for _, c in ipairs(q.classes) do
                if Quests.IsForClass(rec, c:upper()) then return true end
            end
            return false
        end
        return true
    end
end

-- The quest of a "one of" group to follow (one of them is enough): the one that is done, else the one in the quest
-- log, else the first version that fits (fits: Quests.ChainFilter, default this character's versions), else the first.
function Quests.PickFromGroup(group, fits)
    fits = fits or Quests.IsForPlayer
    for _, p in ipairs(group) do
        if IsFlaggedCompleted(p) then return p end
    end
    for _, p in ipairs(group) do
        if LogState(p) then return p end
    end
    for _, p in ipairs(group) do
        local rec = Quests.Get(p)
        if rec and fits(rec) then return p end
    end
    return group[1]
end

-- What a quest needs within a set of quests: its pre quests and its version of each "one of" group.
local function Needs(rec, fits)
    local out = {}
    for _, p in ipairs(rec.pre or {}) do out[#out + 1] = p end
    for _, group in ipairs(rec.preAny or {}) do out[#out + 1] = Quests.PickFromGroup(group, fits) end
    return out
end

-- passed[id] = a quest that needs id (directly or through quests in between) is completed or in the quest log: the chain
-- went on past it (the game may not keep a skipped or optional quest as completed). neededBy[id] = { quests that need id }.
local function PassedMap(ids, neededBy)
    local passed = {}
    local function Passed(id)
        if passed[id] ~= nil then return passed[id] end
        passed[id] = false   -- a loop in the data ends here
        local v = false
        for _, later in ipairs(neededBy[id] or {}) do
            if IsFlaggedCompleted(later) or LogState(later) or Passed(later) then
                v = true
                break
            end
        end
        passed[id] = v
        return v
    end
    for _, id in ipairs(ids) do Passed(id) end
    return passed
end

local MAX_CHAIN = 60

-- The chain of a quest: every quest it needs (also indirectly; this character's version of each "one of" group), the
-- quest itself and everything that follows it (follow-ups of another faction or class left out), in play order. A
-- quest that only shares an earlier quest is not part of it: Red Silk Bandanas and the last Defias Brotherhood both
-- follow the sixth Defias Brotherhood, and neither is in the other's chain. Returns a list of { id, role, passed,
-- direct }: role = "before" (a quest this one needs), "current" or "after" (comes after this quest); direct = a
-- follow-up right after this quest.
function Quests.GetFullChain(q)
    local fits = Quests.ChainFilter(q)
    local role, ids = { [q.id] = "current" }, { q.id }
    local function Take(id, r)
        if role[id] or #ids >= MAX_CHAIN then return false end
        role[id] = r
        ids[#ids + 1] = id
        return true
    end
    local function Up(id, depth)
        if depth > 30 then return end
        for _, p in ipairs(Needs(Quests.Get(id), fits)) do
            if Quests.Get(p) and Take(p, "before") then Up(p, depth + 1) end
        end
    end
    Up(q.id, 0)
    local function Down(id, depth)
        if depth > 30 then return end
        for _, n in ipairs(Quests.Get(id).next or {}) do
            local rec = Quests.Get(n)
            if rec and fits(rec) and Take(n, "after") then Down(n, depth + 1) end
        end
    end
    Down(q.id, 0)
    -- links within the chain: what each quest needs, and what comes before it (needs and follow-up links)
    local neededBy, before = {}, {}
    for _, id in ipairs(ids) do
        neededBy[id], before[id] = {}, {}
    end
    for _, id in ipairs(ids) do
        local rec = Quests.Get(id)
        for _, p in ipairs(Needs(rec, fits)) do
            if role[p] then
                table.insert(neededBy[p], id)
                table.insert(before[id], p)
            end
        end
        for _, n in ipairs(rec.next or {}) do
            if role[n] then table.insert(before[n], id) end
        end
    end
    -- play order: the longest way from the chain's start, then the quest level
    local step = {}
    local function Step(id)
        if step[id] then return step[id] end
        step[id] = 0   -- a loop in the data ends here
        local v = 0
        for _, p in ipairs(before[id]) do v = math.max(v, Step(p) + 1) end
        step[id] = v
        return v
    end
    for _, id in ipairs(ids) do Step(id) end
    table.sort(ids, function(a, b)
        if step[a] ~= step[b] then return step[a] < step[b] end
        local la, lb = Quests.Get(a).level or 0, Quests.Get(b).level or 0
        if la ~= lb then return la < lb end
        return a < b
    end)
    local direct = {}
    for _, n in ipairs(q.next or {}) do direct[n] = true end
    local passed = PassedMap(ids, neededBy)
    local out = {}
    for _, id in ipairs(ids) do
        out[#out + 1] = { id = id, role = role[id], passed = passed[id] and id ~= q.id, direct = direct[id] or false }
    end
    return out
end

---------------------------------------------------------------------------
-- Instance lists
---------------------------------------------------------------------------
-- The quests before q: its prerequisites and theirs, as a set of IDs.
local function Earlier(q, out, depth)
    if depth > 30 then return out end
    local function AddEarlier(p)
        if out[p] then return end
        out[p] = true
        local rec = Quests.Get(p)
        if rec then Earlier(rec, out, depth + 1) end
    end
    for _, p in ipairs(q.pre or {}) do AddEarlier(p) end
    for _, group in ipairs(q.preAny or {}) do
        for _, p in ipairs(group) do AddEarlier(p) end
    end
    return out
end

-- faction filter: "MINE" (quests this character can take), "ALLIANCE", "HORDE", "ALL"
-- chainsOnce: one quest per chain, its last one in the list (the dungeon quest with the reward): a quest that comes
-- before another quest of the list is left out, done or not. Its steps are in that quest's chain.
function Quests.ForInstance(instKey, filter, chainsOnce)
    local list = Quests.ListForInstance(instKey, filter)
    if not chainsOnce then return list end
    local before = {}
    for _, q in ipairs(list) do Earlier(q, before, 0) end
    local shown = {}
    local active = {}
    -- The final reward quest is normally the best single representative of a
    -- chain.  While the player is on an earlier step, however, that final
    -- record is misleading: Forever can have a live dungeon quest whose
    -- classic follow-up is also present in the database.  Remember live
    -- steps so the list can prefer what is actually in the quest log.
    for _, q in ipairs(list) do
        local status = Quests.GetStatus(q)
        if status == Quests.ACTIVE or status == Quests.READY then
            active[q.id] = true
        end
    end
    for _, q in ipairs(list) do
        if not before[q.id] then
            local replaceWithLiveStep = false
            for p in pairs(Earlier(q, {}, 0)) do
                if active[p] then
                    replaceWithLiveStep = true
                    break
                end
            end
            if not replaceWithLiveStep then shown[#shown + 1] = q end
        end
    end
    -- Earlier live steps are not necessarily terminal records in the
    -- instance table. Add them after removing their chain's terminal row.
    for _, q in ipairs(list) do
        if active[q.id] then
            local present = false
            for _, existing in ipairs(shown) do
                if existing.id == q.id then present = true break end
            end
            if not present then shown[#shown + 1] = q end
        end
    end
    return shown
end

local function IsOpen(status)
    return status == Quests.AVAILABLE or status == Quests.ACTIVE or status == Quests.READY
end

-- A chain the character can work on now: its quest, or one of the quests before it, can be taken, is in the log or
-- ready to turn in.
local function ChainOpen(q)
    if IsOpen(Quests.GetStatus(q)) then return true end
    for p in pairs(Earlier(q, {}, 0)) do
        if IsOpen(Quests.GetStatus(p)) then return true end
    end
    return false
end

-- Every quest of the instance that passes the faction filter (finished ones too).
function Quests.ListForInstance(instKey, filter)
    local list = {}
    local ids = LJ.Data.InstanceQuests and LJ.Data.InstanceQuests[instKey]
    if not ids then return list end
    filter = filter or "MINE"
    for _, qid in ipairs(ids) do
        local q = Quests.Get(qid)
        if q then
            local ok
            if filter == "MINE" then
                ok = Quests.IsForPlayer(q)
            elseif filter == "ALLIANCE" then
                ok = Quests.IsForSide(q, "A")
            elseif filter == "HORDE" then
                ok = Quests.IsForSide(q, "H")
            else
                ok = true
            end
            if ok then list[#list + 1] = q end
        end
    end
    return list
end

-- Counts for an instance: quests this character can take, and how many of them can be worked on now. Counted like the
-- Quests tab lists them (one per chain; a chain whose earlier quest can be taken counts as open). Kept until the
-- quest states change (Quests.InvalidateCache: the quest log, the level, the window closed).
function Quests.CountForInstance(instKey)
    local kept = countCache[instKey]
    if kept then return kept[1], kept[2], kept[3] end
    local total, open, done = 0, 0, 0
    for _, q in ipairs(Quests.ForInstance(instKey, "MINE", true)) do
        total = total + 1
        if Quests.GetStatus(q) == Quests.COMPLETED then
            done = done + 1
        elseif ChainOpen(q) then
            open = open + 1
        end
    end
    countCache[instKey] = { total, open, done }
    return total, open, done
end

function Quests.IsAccessQuest(instKey, qid)
    local access = LJ.Data.InstanceAccess and LJ.Data.InstanceAccess[instKey]
    if not access then return false end
    for _, id in ipairs(access) do
        if id == qid then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
function Quests.FormatMoney(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return nil end
    return GetMoneyString(copper, true)
end

function Quests.SideText(side)
    -- the addon's own words: the game's FACTION_ALLIANCE is in the client's language, not the addon's
    if side == "A" then return L("Alliance") end
    if side == "H" then return L("Horde") end
    return L("Both factions")
end

---------------------------------------------------------------------------
-- XP and money as the game states them. The addon's data has them from the Classic data or public Forever sources;
-- the game's own quest window shows no XP, but the client knows both: they are read when a quest giver shows a
-- quest or its reward, saved per quest for the account (LootifiedData.questRewards) and win over the addon's data.
---------------------------------------------------------------------------
local MAX_LEVEL = 60
-- the full XP while the character is at most this many levels above the quest (above it the game gives less)
local FULL_XP_ABOVE = 5

local function ReadRewards()
    local qid = GetQuestID()
    if not qid or qid == 0 then return end
    local level = UnitLevel("player") or 0
    -- at the level cap a quest pays money instead of XP: readings there do not show the reward below the cap
    if level <= 0 or level >= MAX_LEVEL then return end
    -- the quest's level: a dungeon quest's or an open world quest's (Data/WorldQuests.lua)
    local q = Quests.Get(qid) or LJ.Items.GetWorldQuest(qid)
    local store = LJ.db.questRewards
    local e = store[qid] or {}
    local xp = tonumber(GetRewardXP()) or 0
    if xp > 0 and not (q and q.level and level > q.level + FULL_XP_ABOVE) then
        e.xp, e.xpLevel = xp, level
    end
    e.money = tonumber(GetRewardMoney()) or 0
    store[qid] = e
    LJ:Fire("QUEST_REWARDS_CHANGED", qid)
end
LJ:On("QUEST_DETAIL", ReadRewards)
LJ:On("QUEST_COMPLETE", ReadRewards)

-- XP and money of a quest (nil: not known): what the game stated to this account, else the addon's data.
function Quests.GetXPMoney(qid)
    local q = Quests.Get(qid)
    local seen = LJ.db.questRewards[qid]
    local xp = (seen and seen.xp) or (q and q.xp)
    local money = q and q.money
    if seen and seen.money ~= nil then money = seen.money end
    return xp, money
end

---------------------------------------------------------------------------
-- Events: refresh when the quest log changes
---------------------------------------------------------------------------
local function Changed()
    Quests.InvalidateCache()
    LJ:FireDebounced("QUESTS_CHANGED", 0.3)
end

LJ:On("QUEST_TURNED_IN", Changed)
LJ:On("QUEST_ACCEPTED", Changed)
LJ:On("QUEST_REMOVED", Changed)
-- the game fires QUEST_LOG_UPDATE far more often than a quest changes (also when it has loaded data:
-- Blizzard_PVPMatch/PVPMatchResults.lua): only a change of what was read refreshes
LJ:On("QUEST_LOG_UPDATE", function()
    if Stale() then Changed() end
end)
LJ:Listen("PLAYER_CHANGED", Changed)
-- with the window closed nothing shows a quest's state: the states read are dropped (a quest log update has none to
-- check), the window reads them again when it opens
LJ:Listen("WINDOW_CLOSED", Quests.InvalidateCache)

BuildIndexes()
LJ:Listen("DB_READY", OrderIndexes)
