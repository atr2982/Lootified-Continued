local _, LJ = ...

-- Language of the addon: interface texts (LJ.uiText, read by LJ.L) and data texts (quest, boss, mob and item
-- names, quest objectives, dungeon names).
-- LJ.db.language: "auto" (the game client's language when the addon has it, else English) | "enUS" | one of
-- Locale.LANGUAGES.
-- The texts of a language (Data/Locale_enUS.lua: the English game's texts where they differ from the data;
-- Data/Locale_<locale>.lua) are built only when it is used and written into the data tables once; otherwise the
-- loaders are dropped and nothing of them stays in memory. A change needs /reload.

local Locale = {}
LJ.Locale = Locale
Locale.active = "enUS"

-- The languages the addon has besides English, in the order of the settings.
-- Forever Lite ships English only.
Locale.LANGUAGES = {}
local LANGUAGES = {}
for _, lang in ipairs(Locale.LANGUAGES) do LANGUAGES[lang] = true end
-- Korean and Chinese only in a client of that language: only its font has their letters
Locale.OWN_CLIENT_ONLY = {}

-- Whether a language can be chosen in this client.
function Locale.Available(lang)
    return lang == "enUS" or (LANGUAGES[lang] == true and (not Locale.OWN_CLIENT_ONLY[lang] or lang == GetLocale()))
end

function Locale.Resolve(setting)
    if Locale.Available(setting) then return setting end
    local client = GetLocale()
    return LANGUAGES[client] and client or "enUS"
end

-- Item names by item ID in the language used (read by Core/Items.lua), empty in English (the client's and the shipped
-- names are English).
Locale.itemNames = nil

-- Translated name of a quest giver / turn-in (NPC, object or item) by its ID; returns the English name it replaced.
local function Rename(loc, L)
    if type(loc) ~= "table" or not loc.id then return nil end
    local de
    if loc.kind == "object" then
        de = L.object[loc.id]
    elseif loc.kind == "item" then
        de = L.item[loc.id]
    else
        de = L.npc[loc.id]
    end
    if not de or loc.name == de then return nil end
    local old = loc.name
    loc.name = de
    return old
end

-- "Old Name, rest" -> "rest" (the quest details strip the giver's name from the location line by the shown name).
local function StripName(text, old)
    if not text or not old then return text end
    local prefix = old .. ", "
    if text:sub(1, #prefix) == prefix then return text:sub(#prefix + 1) end
    return text
end

-- Replaces the text before the first "|" of every string in a data table ("name|..."), for the IDs given.
local function RenameStrings(list, names)
    if not list then return end
    for id, text in pairs(list) do
        local de = names[id]
        if de then
            local rest = text:match("^.-(|.*)$")
            if rest then list[id] = de .. rest end
        end
    end
end

local ROLES = { "start", "finish" }

local function Apply(L)
    local D = LJ.Data
    local Util = LJ.Util
    local oldNames = {}

    -- "inside <dungeon>" locations of quest givers and kills: the translated dungeon name
    local instDE = {}
    for _, inst in ipairs(D.Instances or {}) do
        local de = L.instance[inst.key]
        if de then instDE[inst.name] = de end
    end
    local function Zone(loc)
        if type(loc) ~= "table" or not loc.zone then return end
        local en = loc.zone:match("^inside (.+)$")
        -- the quest view offers the dungeon entrance on the map for spots inside a dungeon
        if en then loc.inside = true end
        if en and instDE[en] then
            loc.zone = string.format(L.ui["inside %s"] or "inside %s", instDE[en])
        else
            -- zone names of the game in that language (by the zone's map)
            loc.zone = L.zone[loc.zone] or loc.zone
        end
    end
    -- "Old Ironforge, Dun Morogh": each zone part
    local function ZoneList(text)
        if not text then return nil end
        return (text:gsub("[^,]+", function(part)
            local lead, name, trail = part:match("^(%s*)(.-)(%s*)$")
            return lead .. (L.zone[name] or name) .. trail
        end))
    end
    local reps = {}   -- reputation lists are shared between quests: each is renamed once

    for qid, q in pairs(D.Quests or {}) do
        q.name = L.questName[qid] or q.name
        q.obj = L.questObj[qid] or q.obj
        -- start / finish tables are shared between quests: each is renamed once (its English name kept in
        -- oldNames), the location texts per quest
        local st = q.start
        if type(st) == "table" and st.kind == "item" and st.text and L.startText[st.id] then
            st.text = L.startText[st.id]
        end
        for _, key in ipairs(ROLES) do
            local loc = q[key]
            if type(loc) == "table" and oldNames[loc] == nil then oldNames[loc] = Rename(loc, L) or false end
            local old = type(loc) == "table" and oldNames[loc]
            local text = q[key .. "Text"]
            if text then
                -- the addon's own location line translated (it starts with the translated name, which the quest
                -- view strips); spots inside a dungeon keep their map button
                if text:lower():find("inside") then q[key .. "Inside"] = true end
                local de = L.location[text]
                if de then
                    q[key .. "Text"] = de
                elseif old then
                    q[key .. "Text"] = StripName(text, old)
                end
            end
        end
        for _, k in ipairs(q.kills or {}) do
            local de = (k.id and L.npc[k.id]) or L.name[k.name]
            if de then k.name = de end
        end
        for _, it in ipairs(q.items or {}) do
            if it.name and L.item[it.id] then it.name = L.item[it.id] end
            if it.src and L.itemSrc[it.src] then it.src = L.itemSrc[it.src] end
        end
        Zone(q.start)
        Zone(q.finish)
        if type(q.rep) == "table" and not reps[q.rep] then
            reps[q.rep] = true
            for _, r in ipairs(q.rep) do r[1] = L.rep[r[1]] or r[1] end
        end
    end

    for _, inst in ipairs(D.Instances or {}) do
        local de = L.instance[inst.key]
        if de and de ~= inst.name then
            -- the search finds the dungeon by its translated and its English name
            inst.searchKey = Util.SearchKey(de .. " " .. inst.name)
            inst.englishName = inst.name
            inst.name = de
        end
        for _, boss in ipairs(inst.bosses or {}) do
            -- bosses without an NPC ID (chests, groups) by their English name
            local name = (boss.npc and L.npc[boss.npc]) or L.name[boss.name]
            if name then boss.name = name end
        end
        -- where trash items drop (mob names)
        for i, source in ipairs(inst.trashSource or {}) do
            if L.name[source] then inst.trashSource[i] = L.name[source] end
        end
        inst.desc = L.desc[inst.key] or inst.desc
        inst.statusText = inst.statusText and L.status[inst.statusText] or inst.statusText
        inst.zone = ZoneList(inst.zone)
        if inst.entrance then inst.entrance.zone = ZoneList(inst.entrance.zone) end
    end

    -- Best in Slot: the source text shown for items the addon has no source of its own for (crafted, PvP, ...)
    for _, specs in pairs(D.BiS or {}) do
        for _, spec in ipairs(specs) do
            for _, entries in pairs(spec.slots or {}) do
                for _, e in ipairs(entries) do
                    if e.src and L.bisSrc[e.src] then e.src = L.bisSrc[e.src] end
                end
            end
        end
    end
    -- zones the game finds for a spot (Core/MapPin.lua): translated names also on an English game client
    Locale.zoneById = L.zoneId

    for id, d in pairs(D.WorldMobs or {}) do
        if L.npc[id] then d[1] = L.npc[id] end
    end

    for qid, text in pairs(D.WorldQuests or {}) do
        local name, mid, giver, tail = text:match("^(.-)(|%d+|%d+|%a|[^|]*|)(.-)(|.*)$")
        if name then
            D.WorldQuests[qid] = (L.worldQuest[qid] or name) .. mid .. (L.giver[giver] or giver) .. tail
        end
    end

    RenameStrings(D.Items, L.item)
    RenameStrings(D.WorldDrops, L.item)
    RenameStrings(D.WorldQuestItems, L.item)
    -- Data/ItemStats stays English: Core/Items.lua compares the client's answers with it; the translated name is
    -- shown through Locale.itemNames
    Locale.itemNames = L.item
    LJ.uiText = L.ui
    -- Russian counts have a third word form (2-4, 22-24 ...: Util.PluralWord)
    LJ.uiFew = L.few

    D.ItemNotes = D.ItemNotes or {}
    for id, note in pairs(L.itemNote) do D.ItemNotes[id] = note end
    -- the professions of the crafted items (Data/Crafted.lua), by skill line
    for id, name in pairs(L.profession) do D.Professions[id] = name end
end

-- Before Core/Items.lua reads the saved item cache (this file loads first, so its listener runs first).
LJ:Listen("DB_READY", function()
    local loaders = LJ.Locales
    LJ.Locales = nil
    local lang = Locale.Resolve(LJ.db.language)
    local loader = loaders and loaders[lang]
    if not loader then error("Lootified: no data for language " .. tostring(lang)) end
    Apply(loader())
    Locale.active = lang
end)

---------------------------------------------------------------------------
-- /lf collect: what only the game's server can tell about the addon's data, in the client's language, slowly and with
-- a progress window: items (names and the classes of their tooltips; in an English client also their data with stats,
-- and the items the server has no data for), quests (titles, the game's facts, rewards, texts and objectives) and NPCs
-- (names, the other lines of their tooltips and their looks), also the creatures the game's achievements count
-- (LootifiedData.gameTexts[client language]). The names the game has in its own tables (factions, zones, achievements,
-- recipes ...) and the simulator's talents and spells come from those tables (pipeline/import_game_tables.py), not from
-- here. Nothing gets lost on the way (Ask): every ID is asked again until the game answers, a read counts once the
-- same read comes twice, the server's "no data" once it comes twice; what the game never answers is kept apart (open),
-- never as without data. The running collect is in the saved variables from its start: a /reload or a logout keeps
-- what it has read. Everything is kept per client language, and collects in the same language and game build add up
-- (AddCollect). /lf collect clear removes all of it again.
-- Read by pipeline/import_client_names.lua and pipeline/gen_itemstats.lua; the addon does not use it at run time.
-- Game functions (from the client's API documentation and its own interface code): C_Item.RequestLoadItemDataByID +
-- ITEM_DATA_LOAD_RESULT, C_Item.IsItemDataCachedByID, C_Item.GetItemInfo, C_TooltipInfo.GetItemByID,
-- C_QuestLog.RequestLoadQuestByID + QUEST_DATA_LOAD_RESULT, C_QuestLog.GetTitleForQuestID, GetQuestObjectives,
-- GetQuestDifficultyLevel, GetQuestTagInfo, GetSuggestedGroupSize, GetQuestFactionGroup, GetQuestLogRewardXP /
-- GetQuestLogRewardMoney / GetQuestLogRewardInfo / GetQuestLogChoiceInfo, C_TooltipInfo.GetHyperlink (quest and
-- creature links), PlayerModel:SetCreature / GetDisplayInfo.
---------------------------------------------------------------------------
local Collect = { running = false, steps = 3 }
Locale.Collect = Collect

local L, F = LJ.L, LJ.F
-- requests to the server per second (slow: the server drops requests that come too fast); what the client has already
-- is read without a request, as much as fits in READ_MS milliseconds of a tick
local ITEM_RATE, QUEST_RATE, NPC_RATE, READ_MS = 50, 10, 10, 8
-- a read counts when the same read comes again CONFIRM_WAIT seconds later or more; a round asks again for what is left
-- ROUND_WAIT seconds after the last one; a step ends STALL seconds after its last new answer
local CONFIRM_WAIT, ROUND_WAIT, STALL, TICK = 2, 3, 180, 0.1

local function GameText(s)
    if type(s) ~= "string" or s == "" or LJ.Util.IsSecret(s) then return nil end
    return s
end

local function Count(list)
    local n = 0
    for _ in pairs(list or {}) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Progress window
---------------------------------------------------------------------------
-- the progress bar's width: the window is wide enough for the step line ("Step 1 of 5: ...") beside the count
-- ("258000 of 258000") in every language
local BAR_WIDTH = 432

local function Frame()
    if Collect.frame then return Collect.frame end
    local Widgets, Theme = LJ.Widgets, LJ.Theme
    local C = Theme.COLORS
    local f = CreateFrame("Frame", "LootifiedCollectFrame", UIParent)
    f:SetSize(BAR_WIDTH + 28, 96)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.055, 0.07, 0.94)
    f.title = Widgets.Text(f, "h3", C.text1)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(L("Lootified: collecting game data"))
    f.step = Widgets.Text(f, "body", C.text2)
    f.step:SetPoint("TOPLEFT", 14, -34)
    f.count = Widgets.Text(f, "body", C.text2, nil, "RIGHT")
    f.count:SetPoint("TOPRIGHT", -14, -34)
    f.track = f:CreateTexture(nil, "ARTWORK")
    f.track:SetPoint("TOPLEFT", 14, -56)
    f.track:SetSize(BAR_WIDTH, 10)
    f.track:SetColorTexture(1, 1, 1, 0.08)
    f.bar = f:CreateTexture(nil, "OVERLAY")
    f.bar:SetPoint("TOPLEFT", f.track, "TOPLEFT")
    f.bar:SetSize(1, 10)
    f.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    f.note = Widgets.Text(f, "bodySmall", C.text3)
    f.note:SetPoint("TOPLEFT", 14, -76)
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(20, 20)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    f.close.text = Widgets.Text(f.close, "h3", C.text3, nil, "CENTER")
    f.close.text:SetPoint("CENTER")
    f.close.text:SetText("x")
    f.close:SetScript("OnClick", function() f:Hide() end)
    Collect.frame = f
    return f
end

local function SetStep(n, label)
    local f = Frame()
    Collect.step = n
    f.step:SetText(F("Step %d of %d: %s", n, Collect.steps, L(label)))
    f.count:SetText("")
    f.bar:SetWidth(1)
    f:Show()
end

-- text: what the count beside the step line shows instead of "done of total"
local function SetProgress(done, total, text)
    local f = Frame()
    f.count:SetText(text or F("%d of %d", done, total))
    local part = total > 0 and math.min(1, done / total) or 1
    -- the whole run: each step is an equal part of the bar
    f.bar:SetWidth(math.max(1, BAR_WIDTH * (((Collect.step or 1) - 1) + part) / Collect.steps))
end

---------------------------------------------------------------------------
-- IDs the addon knows
---------------------------------------------------------------------------
local function SortedKeys(set)
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return list
end

-- IDs the data names without keeping them (Data/CollectIDs.lua: "1,2,3")
local function AddListed(set, kind)
    local list = LJ.Data.CollectIDs and LJ.Data.CollectIDs[kind]
    for id in (list or ""):gmatch("%d+") do set[tonumber(id)] = true end
end

local function QuestIDs()
    local set = {}
    for qid in pairs(LJ.Data.Quests or {}) do set[qid] = true end
    for qid in pairs(LJ.Data.WorldQuests or {}) do set[qid] = true end
    AddListed(set, "quests")
    return SortedKeys(set)
end

local function NpcIDs()
    local set = {}
    AddListed(set, "npcs")
    local function add(loc) if type(loc) == "table" and loc.kind ~= "item" and loc.kind ~= "object" and loc.id then set[loc.id] = true end end
    for _, q in pairs(LJ.Data.Quests or {}) do
        add(q.start)
        add(q.finish)
        for _, k in ipairs(q.kills or {}) do if k.id then set[k.id] = true end end
    end
    for _, inst in ipairs(LJ.Data.Instances or {}) do
        for _, boss in ipairs(inst.bosses or {}) do if boss.npc then set[boss.npc] = true end end
    end
    for id in pairs(LJ.Data.WorldMobs or {}) do set[id] = true end
    return SortedKeys(set)
end

---------------------------------------------------------------------------
-- Asking until the game answers
---------------------------------------------------------------------------
-- A read as text: two reads are the same when their texts are; the longer text has more data.
local function ReadText(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = tostring(k) .. "=" .. ReadText(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Asks the game for every ID of a kind until it has answered for all of them. kind = { rate (IDs per second),
-- Has(id): the client has the data now, Ask(id): asks the server for it, Read(id): what the client has of it now (nil:
-- nothing yet), Keep(id, read): puts a read into the running collect, Refuse(id): keeps the server's "no data",
-- askFirst: every ID is asked for before it is read, what the client has already too }; the
-- kind's answer event calls kind.Answer(id, success). A read counts once the same read comes again at least
-- CONFIRM_WAIT seconds later; until then the read with the most data is kept. "No data" counts once it comes twice and
-- no read came. What is left is asked again round after round; the step ends when nothing is left or STALL seconds
-- after the last new answer. done(result): result = { read, refused, unconfirmed = { IDs read but never twice the
-- same }, open = { IDs the game never answered for }, and how long it took: seconds, rounds, asked (requests to the
-- server), reads (what the client had already), lastAnswer (seconds from the start to the last new answer), answers =
-- { first answers per round }, stalled (true: ended STALL seconds after the last new answer, IDs left) }.
local function Ask(kind, ids, done)
    local wanted, text, readAt, noData, finished = {}, {}, {}, {}, {}
    for _, id in ipairs(ids) do wanted[id] = true end
    local left, lastNew, round = #ids, GetTime(), 1
    local started, asked, reads, answers, heard = GetTime(), 0, 0, {}, {}
    -- the first answer for an ID (a read or "no data"), counted per round
    local function Answered(id)
        if heard[id] then return end
        heard[id] = true
        answers[round] = (answers[round] or 0) + 1
    end
    local function Finish(id)
        finished[id] = true
        left = left - 1
        lastNew = GetTime()
    end
    -- reads what the client has of an ID now; true when it had something
    local function Take(id)
        if finished[id] then return true end
        local r = kind.Read(id)
        if r == nil then return false end
        local t = ReadText(r)
        if t == text[id] then
            if GetTime() - readAt[id] >= CONFIRM_WAIT then Finish(id) end
        elseif not text[id] or #t > #text[id] then
            Answered(id)
            text[id], readAt[id], lastNew = t, GetTime(), GetTime()
            kind.Keep(id, r)
            C_Timer.After(CONFIRM_WAIT, function()
                if Collect.asking == kind and not finished[id] and kind.Has(id) then Take(id) end
            end)
        end
        return true
    end
    function kind.Answer(id, success)
        if not wanted[id] or finished[id] then return end
        if success ~= false then
            Take(id)
            return
        end
        -- (a "no data" after a read changes nothing: the ID is asked again)
        if text[id] then return end
        Answered(id)
        noData[id] = (noData[id] or 0) + 1
        if noData[id] >= 2 then
            kind.Refuse(id)
            Finish(id)
        end
    end
    local function Result()
        Collect.asking = nil
        local now = GetTime()
        local r = { read = 0, refused = 0, unconfirmed = {}, open = {}, seconds = math.floor(now - started + 0.5),
            rounds = round, asked = asked, reads = reads, lastAnswer = math.floor(lastNew - started + 0.5),
            answers = answers, stalled = left > 0 }
        for _, id in ipairs(ids) do
            if finished[id] then
                if text[id] then r.read = r.read + 1 else r.refused = r.refused + 1 end
            elseif text[id] then
                r.unconfirmed[#r.unconfirmed + 1] = id
            else
                r.open[#r.open + 1] = id
            end
        end
        return r
    end
    local queue, pos = ids, 0
    local perTick = math.max(1, math.floor(kind.rate * TICK + 0.5))
    local function Pass()
        if Collect.asking ~= kind then return end
        -- up to perTick requests to the server; what the client has already is read without one (no limit but READ_MS)
        local requests, tickStart = 0, debugprofilestop()
        while pos < #queue and requests < perTick and debugprofilestop() - tickStart < READ_MS do
            pos = pos + 1
            local id = queue[pos]
            if not finished[id] then
                if not kind.askFirst and kind.Has(id) and Take(id) then
                    reads = reads + 1
                else
                    kind.Ask(id)
                    requests = requests + 1
                end
            end
        end
        asked = asked + requests
        SetProgress(#ids - left, #ids, round > 1 and F("Round %d: %d left", round, left) or nil)
        if left == 0 then return done(Result()) end
        if pos < #queue then return C_Timer.After(TICK, Pass) end
        if GetTime() - lastNew >= STALL then return done(Result()) end
        -- the round is through: the next one asks again for what is left
        local rest = {}
        for _, id in ipairs(ids) do
            if not finished[id] then rest[#rest + 1] = id end
        end
        queue, pos, round = rest, 0, round + 1
        C_Timer.After(ROUND_WAIT, Pass)
    end
    Collect.asking = kind
    Pass()
end

-- What a step's result says in the collect: the counts (the lists of open and unconfirmed IDs are kept beside them)
-- and how long it took.
local function Summary(result)
    return { read = result.read, refused = result.refused, unconfirmed = #result.unconfirmed, open = #result.open,
        seconds = result.seconds, rounds = result.rounds, asked = result.asked, reads = result.reads,
        lastAnswer = result.lastAnswer, answers = result.answers, stalled = result.stalled }
end

---------------------------------------------------------------------------
-- Step 1: items
---------------------------------------------------------------------------
-- The client's tooltip data of an item; nil while it has only part of the item's data ("Retrieving item
-- information", RETRIEVING_ITEM_INFO).
local function FullTooltip(id)
    local data = C_TooltipInfo.GetItemByID(id)
    local first = data and data.lines and data.lines[1]
    if not first or first.leftText == RETRIEVING_ITEM_INFO then return nil end
    return data
end

-- The classes an item's tooltip (data) allows ("Classes: Mage, Warlock", ITEM_CLASSES_ALLOWED) as the class bits of
-- Data/ItemClasses.lua ("128"), "0" for a tooltip without the line (every class), "?<list>" for a class name the
-- game's class names do not have.
local function ItemClassBits(data)
    local pattern = LJ.Util.FormatPattern(ITEM_CLASSES_ALLOWED)
    local tokens = {}
    for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do tokens[name] = token end
    for _, line in ipairs(data.lines) do
        local list = type(line.leftText) == "string" and line.leftText:match(pattern)
        if list then
            local bits = 0
            for name in list:gmatch("[^,]+") do
                local bit = LJ.Items.CLASS_BITS[tokens[name:match("^%s*(.-)%s*$")]]
                if not bit then return "?" .. list end
                bits = bits + bit
            end
            return tostring(bits)
        end
    end
    return "0"
end

-- The profession an item's tooltip (data) asks for ("Requires Engineering (245)", ITEM_MIN_SKILL): { name, rank },
-- nil without one.
local function ItemSkill(data)
    local pattern = LJ.Util.FormatPattern(ITEM_MIN_SKILL)
    for _, line in ipairs(data.lines) do
        if type(line.leftText) == "string" then
            local name, rank = line.leftText:match(pattern)
            if name then return { name, tonumber(rank) } end
        end
    end
    return nil
end

-- Every item the client's own data has (C_Item.GetItemInfoInstant: no server), and of them the gear: every weapon and
-- armor item with an equipment slot, without shirts and tabards (no stats). ITEM_SCAN_LAST is well above the highest
-- item ID of the client's item table (287505 in build 1.60.1.70205). done(list of IDs, list of the gear's IDs).
local ITEM_SCAN_LAST, ITEM_SCAN_STEP = 400000, 10000
local NO_STATS_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
local function ScanItems(done)
    local found, gear, last = {}, {}, 0
    local function Tick()
        if Collect.stopped then return end
        local to = math.min(last + ITEM_SCAN_STEP, ITEM_SCAN_LAST)
        for id = last + 1, to do
            local known, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(id)
            if known then
                found[#found + 1] = id
                if (classID == 2 or classID == 4) and equipLoc ~= "" and not NO_STATS_SLOTS[equipLoc] then
                    gear[#gear + 1] = id
                end
            end
        end
        last = to
        SetProgress(last, ITEM_SCAN_LAST, F("Items in the game: %d", #found))
        if last < ITEM_SCAN_LAST then C_Timer.After(0, Tick) else done(found, gear) end
    end
    Tick()
end

-- What the client has of an item now (nil until it has the item's data and its full tooltip; a language collect: its
-- name, no tooltip): its name and the classes
-- its tooltip allows; in an English client its data with the stats of its tooltip, in the saved item cache's form (s:
-- {} for an item without stats), a weapon's damage and speed ({ min, max, speed }, as the simulator reads them) and the
-- profession it asks for: pipeline/gen_itemstats.lua builds Data/ItemStats.lua from it (the addon reads stats from
-- English tooltips only).
local function ReadItem(id)
    if not C_Item.IsItemDataCachedByID(id) then return nil end
    local name, _, quality, itemLevel, minLevel, _, _, _, _, _, _, _, _, bindType, _, setID = C_Item.GetItemInfo(id)
    -- a language collect reads the name only: the classes are the English collect's, and building the tooltip of some
    -- items crashes clients of other languages (Spanish, item 867: the game's own format error in its tooltip text)
    if Collect.texts.language then return GameText(name) and { name = name } or nil end
    local data = FullTooltip(id)
    if not GameText(name) or not data then return nil end
    local r = { name = name, classes = ItemClassBits(data) }
    if LJ.ENGLISH_CLIENT then
        local lo, hi, speed = LJ.Sim.Character.WeaponFromTooltip(data)
        r.data = { name, quality, itemLevel, minLevel, bindType or 0, setID or 0, s = LJ.Scoring.ClientStats(id),
            w = lo and { lo, hi, speed } or nil, skill = ItemSkill(data) }
    end
    return r
end

local ITEMS = { rate = ITEM_RATE, Read = ReadItem }
function ITEMS.Has(id) return C_Item.IsItemDataCachedByID(id) end
function ITEMS.Ask(id) C_Item.RequestLoadItemDataByID(id) end
function ITEMS.Keep(id, r)
    local t = Collect.texts
    t.items[id], t.itemClasses[id] = r.name, r.classes
    if r.data then t.itemData[id] = r.data end
end
-- the items the server has no data for in this game build
function ITEMS.Refuse(id)
    local list = Collect.texts.itemMissing
    list[#list + 1] = id
end
LJ:On("ITEM_DATA_LOAD_RESULT", function(_, id, success)
    if Collect.asking == ITEMS then ITEMS.Answer(id, success) end
end)

-- the addon's items and every item the client knows (ScanItems); addonItems: the addon's own items and the client's
-- gear, the items pipeline/gen_itemstats.lua bakes the data of (the others it reads only for their names)
-- The IDs without those in skip (a set; nil: all of them).
local function Skipped(ids, skip)
    if not skip then return ids end
    local left = {}
    for _, id in ipairs(ids) do
        if not skip[id] then left[#left + 1] = id end
    end
    return left
end

local function StepItems(nextStep)
    SetStep(1, "Items")
    ScanItems(function(all, gear)
        -- addonItems: the addon's own items and the client's gear; ids: those and every other item of the client
        local addonItems, ids, seen = {}, {}, {}
        local function Add(list, id)
            if not seen[id] then
                seen[id] = true
                list[#list + 1] = id
            end
        end
        for _, id in ipairs(LJ.Scoring.GetAllItemIDs()) do Add(addonItems, id) end
        for _, id in ipairs(gear) do Add(addonItems, id) end
        for _, id in ipairs(addonItems) do ids[#ids + 1] = id end
        for _, id in ipairs(all) do Add(ids, id) end
        table.sort(addonItems)
        table.sort(ids)
        ids = Skipped(ids, Collect.skip and Collect.skip.items)
        local t = Collect.texts
        t.itemIDs, t.addonItems = #ids, addonItems
        Ask(ITEMS, ids, function(result)
            table.sort(t.itemMissing)
            t.itemOpen, t.itemUnconfirmed, t.itemResult = result.open, result.unconfirmed, Summary(result)
            nextStep()
        end)
    end)
end

---------------------------------------------------------------------------
-- Step 2: quests
---------------------------------------------------------------------------
-- "itemID:count,..." of a quest's reward or choice items (GetQuestLogRewardInfo / GetQuestLogChoiceInfo by quest ID)
local function RewardList(count, info, qid)
    local list = {}
    for i = 1, count do
        local _, _, amount, _, _, itemID = info(i, qid)
        if itemID then list[#list + 1] = itemID .. ":" .. (amount or 1) end
    end
    return table.concat(list, ",")
end

-- What the client has of a quest now (nil without its title): the title and the game's facts of it: "level|tag
-- ID|tag|group size|side" (its level, the tag the game shows: dungeon, raid, elite ...; the group size it suggests; A or
-- H for a quest of one side); what it gives: "XP|money|items|choice items", read by quest ID as the game's own quest
-- tooltips do (QuestUtils.lua), the XP and money for the collecting character's level; the lines of the game's quest
-- tooltip (title first) and the objectives.
local function ReadQuest(qid)
    local Q = C_QuestLog
    local title = GameText(Q.GetTitleForQuestID(qid))
    if not title then return nil end
    local tag = Q.GetQuestTagInfo(qid)
    local side = GetQuestFactionGroup(qid)
    side = side and (side == LE_QUEST_FACTION_HORDE and "H" or "A") or ""
    local r = { title = title,
        facts = string.format("%d|%s|%s|%d|%s", Q.GetQuestDifficultyLevel(qid) or 0, tag and tag.tagID or "",
            tag and GameText(tag.tagName) or "", Q.GetSuggestedGroupSize(qid) or 0, side),
        rewards = string.format("%d|%d|%s|%s", (GetQuestLogRewardXP(qid)) or 0, GetQuestLogRewardMoney(qid) or 0,
            RewardList(GetNumQuestLogRewards(qid), GetQuestLogRewardInfo, qid),
            RewardList(GetNumQuestLogChoices(qid), GetQuestLogChoiceInfo, qid)) }
    local data = C_TooltipInfo.GetHyperlink("quest:" .. qid)
    local lines = {}
    for _, line in ipairs(data and data.lines or {}) do lines[#lines + 1] = GameText(line.leftText) or "" end
    if #lines > 1 then r.lines = lines end
    local objectives = {}
    for _, o in ipairs(Q.GetQuestObjectives(qid) or {}) do objectives[#objectives + 1] = GameText(o.text) end
    if #objectives > 0 then r.objectives = objectives end
    return r
end

-- askFirst: every quest is asked for before it is read. Its title stays in the client, its rewards do not: a collect
-- that read the quests the client still had from an earlier one got 205 of them without their choice items (2026-10-06).
local QUESTS = { rate = QUEST_RATE, Read = ReadQuest, askFirst = true }
function QUESTS.Has(qid) return C_QuestLog.GetTitleForQuestID(qid) ~= nil end
function QUESTS.Ask(qid) C_QuestLog.RequestLoadQuestByID(qid) end
function QUESTS.Keep(qid, r)
    local t = Collect.texts
    t.quests[qid], t.questFacts[qid], t.questRewards[qid] = r.title, r.facts, r.rewards
    if r.lines then t.questLines[qid] = r.lines end
    if r.objectives then t.questObjectives[qid] = r.objectives end
end
-- the quests the server refuses (it gives the data of fewer quests than the game has: which ones)
function QUESTS.Refuse(qid) Collect.texts.questRefused[qid] = true end
LJ:On("QUEST_DATA_LOAD_RESULT", function(_, qid, success)
    if Collect.asking == QUESTS then QUESTS.Answer(qid, success) end
end)

local function StepQuests(nextStep)
    SetStep(2, "Quests")
    local t = Collect.texts
    local ids = Skipped(QuestIDs(), Collect.skip and Collect.skip.quests)
    t.questIDs = #ids
    Ask(QUESTS, ids, function(result)
        t.questOpen, t.questUnconfirmed, t.questResult = result.open, result.unconfirmed, Summary(result)
        nextStep()
    end)
end

---------------------------------------------------------------------------
-- Step 3: NPCs
---------------------------------------------------------------------------
-- a model frame for the creatures' looks (off screen)
local function CollectModel()
    if not Collect.model then
        Collect.model = CreateFrame("PlayerModel", nil, UIParent)
        Collect.model:SetSize(1, 1)
        Collect.model:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT")
    end
    return Collect.model
end

-- What the client has of a creature now (nil without its name): its name, the other lines of its tooltip (level, rank
-- ...) and its look, the display ID the game gives its model (faces and 3D models).
local function ReadCreature(id)
    local data = C_TooltipInfo.GetHyperlink(string.format("unit:Creature-0-0-0-0-%d-0000000000", id))
    local lines = data and data.lines or {}
    local name = lines[1] and GameText(lines[1].leftText)
    if not name then return nil end
    local r = { name = name }
    if #lines > 1 then
        r.lines = {}
        for i = 2, #lines do r.lines[i - 1] = GameText(lines[i].leftText) or "" end
    end
    local model = CollectModel()
    model:SetCreature(id)
    local display = model:GetDisplayInfo()
    if type(display) == "number" and display > 0 then r.display = display end
    return r
end

-- The tooltip of a creature the game does not know yet asks the server for it (the name comes with a later call): the
-- read is the request, there is no answer event and no "no data".
local NPCS = { rate = NPC_RATE, Read = ReadCreature }
function NPCS.Has() return true end
function NPCS.Ask() end
function NPCS.Keep(id, r)
    local t = Collect.texts
    t.npcs[id] = r.name
    if r.lines then t.npcLines[id] = r.lines end
    if r.display then t.npcDisplays[id] = r.display end
end

local function StepNpcs(nextStep)
    SetStep(3, "NPC names")
    local ids = NpcIDs()
    local t = Collect.texts
    t.npcIDs = #ids
    Ask(NPCS, ids, function(result)
        t.npcOpen, t.npcUnconfirmed, t.npcResult = result.open, result.unconfirmed, Summary(result)
        nextStep()
    end)
end

---------------------------------------------------------------------------
-- Keeping it
---------------------------------------------------------------------------
-- The form of a collect (LootifiedData.gameTexts[locale]): collects add up only with collects of the same form
local COLLECT_FORMAT = 7
-- the lists of a collect that add up by ID
local TEXT_LISTS = { "quests", "questFacts", "questRewards", "questLines", "questObjectives", "npcs", "npcLines",
    "npcDisplays", "items", "itemClasses", "itemData" }

-- The IDs of two lists (nil: none), sorted, without the ones settled(id) says the collects have settled.
local function Unsettled(a, b, settled)
    local set = {}
    for _, list in ipairs({ a or {}, b or {} }) do
        for _, id in ipairs(list) do
            if not settled(id) then set[id] = true end
        end
    end
    return SortedKeys(set)
end

-- Keeps a collect in LootifiedData.gameTexts[locale]: added to the earlier collects in that language of the same game
-- build (every list by ID, the newer answer wins; a quest counts as refused only while no collect has its title, an
-- item as without server data only while none has its name; open: what no collect has an answer for), so any number of
-- collects (other characters, a second run) end up in one file. A collect in another game build (or of an earlier
-- form) starts the language afresh. The step results and unconfirmed IDs are the last collect's. Returns what is kept
-- for the language.
local function AddCollect(locale, texts)
    local all = type(LJ.db.gameTexts) == "table" and LJ.db.gameTexts or {}
    -- (the collect of a version before the languages were kept apart: one language, kept under its key)
    if type(all.locale) == "string" then all = { [all.locale] = all } end
    LJ.db.gameTexts = all
    local kept = all[locale]
    if type(kept) ~= "table" or kept.format ~= COLLECT_FORMAT or kept.build ~= texts.build then
        all[locale] = texts
        return texts
    end
    for _, kind in ipairs(TEXT_LISTS) do
        for id, value in pairs(texts[kind]) do kept[kind][id] = value end
    end
    for id in pairs(texts.questRefused) do kept.questRefused[id] = true end
    for id in pairs(kept.questRefused) do
        if kept.quests[id] then kept.questRefused[id] = nil end
    end
    kept.itemMissing = Unsettled(kept.itemMissing, texts.itemMissing, function(id) return kept.items[id] end)
    local missing = {}
    for _, id in ipairs(kept.itemMissing) do missing[id] = true end
    kept.itemOpen = Unsettled(kept.itemOpen, texts.itemOpen, function(id) return kept.items[id] or missing[id] end)
    kept.questOpen = Unsettled(kept.questOpen, texts.questOpen,
        function(id) return kept.quests[id] or kept.questRefused[id] end)
    kept.npcOpen = Unsettled(kept.npcOpen, texts.npcOpen, function(id) return kept.npcs[id] end)
    for _, character in ipairs(texts.characters) do kept.characters[#kept.characters + 1] = character end
    kept.itemResult, kept.questResult, kept.npcResult = texts.itemResult, texts.questResult, texts.npcResult
    kept.addonItems = texts.addonItems
    kept.itemUnconfirmed, kept.questUnconfirmed = texts.itemUnconfirmed, texts.questUnconfirmed
    kept.npcUnconfirmed = texts.npcUnconfirmed
    return kept
end

local function Finish(locale)
    local t = Collect.texts
    Collect.running, Collect.texts = false, nil
    LJ.db.collectRunning = nil
    local f = Frame()
    f.step:SetText(L("Done."))
    f.count:SetText("")
    f.bar:SetWidth(BAR_WIDTH)
    f.note:SetText(L("Type /reload, then send the file WTF\\Account\\<account>\\SavedVariables\\LootifiedContinued.lua."))
    local i, q, n = t.itemResult, t.questResult, t.npcResult
    LJ:Print("Items: %d of %d read, %d not in this game version, %d read only once, %d never answered.", i.read,
        t.itemIDs, i.refused, i.unconfirmed, i.open)
    LJ:Print("Quests: %d of %d read, %d refused by the server, %d read only once, %d never answered.", q.read,
        t.questIDs, q.refused, q.unconfirmed, q.open)
    LJ:Print("NPCs: %d of %d read, %d read only once, %d never answered.", n.read, t.npcIDs, n.unconfirmed, n.open)
    if t.language then
        LJ:Print("Taken from the English collect, not asked: %d items without data, %d refused quests.",
            #t.itemMissing - i.refused, Count(t.questRefused) - q.refused)
    end
    local kept = AddCollect(locale, t)
    LJ:Print("Collects in this language: %d. In all: %d quest titles, %d NPC names, %d item names.",
        #kept.characters, Count(kept.quests), Count(kept.npcs), Count(kept.items))
    LJ:Print("Type /reload, then send the file WTF\\Account\\<account>\\SavedVariables\\LootifiedContinued.lua.")
end

-- Collects everything, in every client language (English too). language (/lf collect language): in another client
-- language, after a full English collect of the same game build: what that one got no data for (items the server has
-- none of, quests it refuses) is not asked again, it is taken over as it is; the names and texts of the rest are read.
function Collect.Start(language)
    if Collect.running then
        LJ:Print("Still collecting, please wait for the result line.")
        Frame():Show()
        return
    end
    local locale = GetLocale()
    local version, build = GetBuildInfo()
    local gameBuild = version .. "." .. build
    local english = type(LJ.db.gameTexts) == "table" and LJ.db.gameTexts.enUS or nil
    if language then
        if LJ.ENGLISH_CLIENT then
            LJ:Print("/lf collect language is for the other client languages; the English client takes /lf collect.")
            return
        end
        if type(english) ~= "table" or english.format ~= COLLECT_FORMAT or english.build ~= gameBuild then
            LJ:Print("First a full /lf collect in the English client of this game build (%s).", gameBuild)
            return
        end
        Collect.skip = { items = {}, quests = english.questRefused }
        for _, id in ipairs(english.itemMissing) do Collect.skip.items[id] = true end
    else
        Collect.skip = nil
    end
    Collect.running, Collect.stopped, Collect.locale = true, false, locale
    local f = Frame()
    f.note:SetText(L("Type /lf collect stop to cancel. Please stay logged in."))
    -- the running collect; the collecting character's level, class and side with it: the server's answers may depend
    -- on them. A language collect starts with what the English one got no data for.
    local missing, refused = {}, {}
    if language then
        for i, id in ipairs(english.itemMissing) do missing[i] = id end
        for id in pairs(english.questRefused) do refused[id] = true end
    end
    -- (itemIDs is set by the item step, questIDs by the quest step, npcIDs by the NPC step)
    local texts = { format = COLLECT_FORMAT, build = gameBuild, quests = {}, questFacts = {},
        questRewards = {}, questRefused = refused, questLines = {}, questObjectives = {}, npcs = {},
        npcLines = {}, npcDisplays = {}, items = {}, itemClasses = {}, itemData = {}, itemMissing = missing,
        itemIDs = #LJ.Scoring.GetAllItemIDs(), questIDs = #QuestIDs(), language = language or nil,
        characters = { { level = UnitLevel("player"), class = select(2, UnitClass("player")),
            faction = UnitFactionGroup("player") } } }
    Collect.texts = texts
    -- in the saved variables from the start: a /reload or a logout keeps what it has read (KeepCutOff)
    LJ.db.collectRunning = { locale = locale, texts = texts }
    LJ:Print(language and "Collecting the names of this language: what the English collect got no data for is skipped."
        or "Collecting game data. This takes a while, the window shows the progress.")
    StepItems(function()
        StepQuests(function()
            StepNpcs(function() Finish(locale) end)
        end)
    end)
end

-- A collect a /reload or a logout cut off (its reads are in the saved variables): kept with the earlier collects in its
-- language.
function Collect.KeepCutOff()
    local cut = LJ.db.collectRunning
    LJ.db.collectRunning = nil
    if type(cut) ~= "table" or type(cut.texts) ~= "table" or cut.texts.format ~= COLLECT_FORMAT then return end
    AddCollect(cut.locale, cut.texts)
    LJ:Print("The last collect was cut off: what it had read is kept. /lf collect again reads the rest.")
end
LJ:Listen("DB_READY", function() Collect.KeepCutOff() end)

-- Removes everything /lf collect saved (after the file was sent: it keeps the saved variables small).
function Collect.Clear()
    if Collect.running then
        LJ:Print("Still collecting, please wait for the result line.")
        return
    end
    LJ.db.gameTexts = nil
    LJ:Print("Collected game data removed. Type /reload to save.")
end

function Collect.Stop()
    if not Collect.running then return end
    Collect.stopped, Collect.running, Collect.asking = true, false, nil
    if Collect.texts then
        AddCollect(Collect.locale, Collect.texts)
        Collect.texts = nil
    end
    LJ.db.collectRunning = nil
    local f = Frame()
    f.step:SetText(L("Stopped."))
    f.note:SetText(L("What is collected so far is saved with the next /reload."))
    LJ:Print("Collecting stopped. What is collected so far is saved with the next /reload.")
end
