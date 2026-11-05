-- Lootified - item database access: indexes, async item info, sources, wishlist.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Items = {}
LJ.Items = Items

local Util = LJ.Util

---------------------------------------------------------------------------
-- Indexes (built once at load)
---------------------------------------------------------------------------
LJ.instanceByKey = {}
LJ.instancesByKind = { dungeon = {}, raid = {} }
Items.sources = {}      -- [itemID] = { { inst = key, boss = index (0 = trash), chance = percent or nil }, ... }
Items.bisIndex = {}     -- [itemID] = { { class, spec, slot, rank, specName }, ... }
-- Both are filled for an item the first time it is looked up. At load only one packed number per drop source or
-- BiS entry is kept: a table for each of the thousands of them would stay in memory all session.
local sourceRefs = {}   -- [itemID] = packed source (instance, boss, position in its loot list), or a list of them
local bisRefs = {}      -- [itemID] = packed BiS entry (class, spec, slot, rank), or a list of them
local bisClasses, bisSlots, bisSlotIndex = {}, {}, {}
local bisFaction = {}   -- [itemID] = "Alliance" | "Horde": the faction a BiS entry names for its item

local function AddRef(refs, itemID, packed)
    local ref = refs[itemID]
    if not ref then
        refs[itemID] = packed
    elseif type(ref) == "number" then
        refs[itemID] = { ref, packed }
    else
        ref[#ref + 1] = packed
    end
end

-- One source per instance and boss (bossIndex 0 = trash); j = position in the loot list (for the drop chance).
local function AddSource(itemID, instIndex, bossIndex, j)
    local key = instIndex * 64 + bossIndex
    local ref = sourceRefs[itemID]
    if type(ref) == "number" then
        if math.floor(ref / 1024) == key then return end
    elseif ref then
        for i = 1, #ref do
            if math.floor(ref[i] / 1024) == key then return end
        end
    end
    AddRef(sourceRefs, itemID, key * 1024 + j)
end

local function SourceOf(packed)
    local j = packed % 1024
    local key = (packed - j) / 1024
    local bossIndex = key % 64
    local inst = LJ.Data.Instances[(key - bossIndex) / 64]
    local chance
    if bossIndex == 0 then
        chance = inst.trashChance and inst.trashChance[j]
    else
        local boss = inst.bosses[bossIndex]
        chance = boss.chance and boss.chance[j]
    end
    return { inst = inst.key, boss = bossIndex, chance = (chance and chance > 0) and chance or nil }
end

local function BiSEntryOf(packed)
    local rank = packed % 64
    packed = (packed - rank) / 64
    local slot = packed % 64
    packed = (packed - slot) / 64
    local specIndex = packed % 8
    local class = bisClasses[(packed - specIndex) / 8]
    local spec = LJ.Data.BiS[class][specIndex]
    return { class = class, spec = spec.key, slot = bisSlots[slot], rank = rank, specName = spec.name }
end

local function Lazy(refs, build)
    return function(t, itemID)
        local ref = refs[itemID]
        if not ref then return nil end
        local list = {}
        if type(ref) == "number" then
            list[1] = build(ref)
        else
            for i = 1, #ref do list[i] = build(ref[i]) end
        end
        refs[itemID] = nil
        rawset(t, itemID, list)
        return list
    end
end
setmetatable(Items.sources, { __index = Lazy(sourceRefs, SourceOf) })
setmetatable(Items.bisIndex, { __index = Lazy(bisRefs, BiSEntryOf) })

-- Item facts from Data/Items.lua ("fallbackName|slotText|flags"): name, slot text, flags (N new in Forever,
-- S seen in the beta, Q quest item); nil for unknown items.
function Items.GetMeta(itemID)
    local text = LJ.Data.Items and LJ.Data.Items[itemID]
    if not text then return nil end
    local name, slot, flags = text:match("^(.-)|(.-)|(.*)$")
    return name, slot, flags
end

local function BuildIndexes()
    for index, inst in ipairs(LJ.Data.Instances or {}) do
        inst.index = index
        LJ.instanceByKey[inst.key] = inst
        local kindList = LJ.instancesByKind[inst.kind]
        if kindList then kindList[#kindList + 1] = inst end

        local unique, newCount = {}, 0
        for bossIndex, boss in ipairs(inst.bosses) do
            boss.index = bossIndex
            for j, itemID in ipairs(boss.loot) do
                AddSource(itemID, index, bossIndex, j)
                if not unique[itemID] then
                    unique[itemID] = true
                    local _, _, flags = Items.GetMeta(itemID)
                    if flags and flags:find("N", 1, true) then newCount = newCount + 1 end
                end
            end
        end
        for j, itemID in ipairs(inst.trash or {}) do
            AddSource(itemID, index, 0, j)
            unique[itemID] = true
        end
        local total = 0
        for _ in pairs(unique) do total = total + 1 end
        inst.itemCount = total
        inst.newCount = newCount
        inst.searchKey = Util.SearchKey(inst.name)
    end

    for class, specs in pairs(LJ.Data.BiS or {}) do
        bisClasses[#bisClasses + 1] = class
        local classIndex = #bisClasses
        for specIndex, spec in ipairs(specs) do
            spec.class = class
            for slot, entries in pairs(spec.slots) do
                local slotIndex = bisSlotIndex[slot]
                if not slotIndex then
                    bisSlots[#bisSlots + 1] = slot
                    slotIndex = #bisSlots
                    bisSlotIndex[slot] = slotIndex
                end
                for rank, entry in ipairs(entries) do
                    entry.rank = rank
                    AddRef(bisRefs, entry.id, ((classIndex * 8 + specIndex) * 64 + slotIndex) * 64 + rank)
                    if entry.faction then bisFaction[entry.id] = entry.faction end
                end
            end
        end
    end
end

function LJ:GetInstanceBySlash(word)
    word = (word or ""):lower()
    if word == "" then return nil end
    for _, inst in ipairs(LJ.Data.Instances) do
        if inst.key:lower() == word then return inst end
        for _, alias in ipairs(inst.slash or {}) do
            if alias == word then return inst end
        end
    end
end

-- The instance on an instance map (GetInstanceInfo's instanceID); nil for a map that several instances share: the
-- wings of Scarlet Monastery, Dire Maul, Stratholme and Blackrock Spire are one map each, and the client knows no map
-- of a dungeon (C_Map) that could tell which wing the player is in.
function LJ:GetInstanceByMapID(mapID)
    if not mapID then return nil end
    local found
    for _, inst in ipairs(LJ.Data.Instances) do
        for _, id in ipairs(inst.instanceIDs or {}) do
            if id == mapID then
                if found then return nil end
                found = inst
                break
            end
        end
    end
    return found
end

-- The instance with this name (the game's name of an instance), in the addon's language or in English.
function LJ:GetInstanceByName(name)
    if type(name) ~= "string" or Util.IsSecret(name) then return nil end
    local key = Util.SearchKey(name)
    for _, inst in ipairs(LJ.Data.Instances) do
        if Util.SearchKey(inst.name) == key or (inst.englishName and Util.SearchKey(inst.englishName) == key) then
            return inst
        end
    end
end

---------------------------------------------------------------------------
-- Item info (asynchronous)
---------------------------------------------------------------------------
local cache = {}
local searchKeys = {}       -- [itemID] = search key of the item name (Items.GetSearchKey)
local requested = {}
local waiting = {}
-- server traffic of this session (/lf items)
Items.netStats = { requests = 0, repeats = 0, answers = 0, noData = 0, noDataIDs = {}, noDataSeen = {} }

-- Saved item cache (SavedVariables, account wide): name, quality, levels and the stats Scoring reads, for every
-- item the addon has seen. WoW only hands out full item data after asking the server, so without it every
-- login starts with empty item info. Rebuilt when the game build or the client language changes.
local CACHE_FORMAT = 3      -- bump when the saved fields or the stat parsing change (3: "when fighting" lines)
local saved                 -- [itemID] = { name, quality, itemLevel, minLevel, bindType, setID, s = stats }
local missing               -- [itemID] = true: the server did not answer for this item (not revealed yet)
local bakedItems, bakedMissing   -- the same, shipped in Data/ItemStats.lua as one string per item
local bakedWeapons, bakedSkills  -- a weapon's damage and speed, the profession an item asks for (Data/ItemStats.lua)
local skillRanks                 -- the ranks the shipped items ask for, by profession (Items.SkillRanks)

-- Shipped entry "name|quality|itemLevel|minLevel|bind|set|Stat=value,..." -> name, quality, itemLevel,
-- minLevel, bind, set, statText ("-" = stats not read). Read on demand: a table per item would cost far more
-- memory.
local function BakedFields(itemID)
    local text = bakedItems and bakedItems[itemID]
    if not text then return nil end
    local name, q, il, ml, bind, set, st = text:match("^(.-)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not name then return nil end
    return name, tonumber(q), tonumber(il), tonumber(ml), tonumber(bind), tonumber(set), st
end

local function ParseStats(st)
    if not st or st == "-" then return nil end
    local stats = {}
    for k, v in st:gmatch("(%w+)=([-%d.]+)") do stats[k] = tonumber(v) end
    return stats
end

-- Number in field n ("|"-separated, 1 = first) of a shipped string, read without creating strings.
local function NumField(text, n)
    local p = 0
    for _ = 1, n - 1 do
        p = text:find("|", p + 1, true)
        if not p then return nil end
    end
    local v, i = 0, p + 1
    local b = text:byte(i)
    if not b or b < 48 or b > 57 then return nil end
    while b and b >= 48 and b <= 57 do
        v = v * 10 + b - 48
        i = i + 1
        b = text:byte(i)
    end
    return v
end

-- Fills t (emptied first) from a shipped stat text ("Stat=value,...", starting at position i of st). The values
-- are read digit by digit, so ranking thousands of items leaves no strings behind; the result equals ParseStats.
local POW10 = { 10, 100, 1000, 10000, 100000, 1000000 }
local function ParseStatsInto(st, t, i)
    for k in pairs(t) do t[k] = nil end
    i = i or 1
    local n = #st
    while i <= n do
        local eq = st:find("=", i, true)
        if not eq then break end
        local key = st:sub(i, eq - 1)
        local j = eq + 1
        local negative = st:byte(j) == 45     -- "-"
        if negative then j = j + 1 end
        local mantissa, decimals, inFraction = 0, 0, false
        while j <= n do
            local b = st:byte(j)
            if b == 44 then break end         -- ","
            if b == 46 then                   -- "."
                inFraction = true
            else
                mantissa = mantissa * 10 + b - 48
                if inFraction then decimals = decimals + 1 end
            end
            j = j + 1
        end
        local v = decimals > 0 and mantissa / POW10[decimals] or mantissa
        t[key] = negative and -v or v
        i = j + 1
    end
    return t
end
Items.ParseStatsInto = ParseStatsInto
Items.ParseStats = ParseStats

-- Keeps the client's data of an item the shipped data does not have (the saved item cache) for the next login.
local function Persist(rec)
    if not saved or not rec.name or (bakedItems and bakedItems[rec.id]) then return end
    local old = saved[rec.id]
    if missing then missing[rec.id] = nil end
    local name, q, il, ml = rec.name, rec.quality or 1, rec.itemLevel or 0, rec.minLevel or 0
    -- the levels the rankings used so far
    local usedIL, usedML
    if old then
        usedIL, usedML = old[3], old[4]
        old[1], old[2], old[3], old[4], old[5], old[6] = name, q, il, ml, rec.bindType or 0, rec.setID or 0
    else
        saved[rec.id] = { name, q, il, ml, rec.bindType or 0, rec.setID or 0 }
    end
    -- the client knows the item with other levels (or it is new): rankings made from the old data are made again
    -- (a name in the client's language alone changes nothing)
    if usedIL ~= il or usedML ~= ml then
        LJ:Debug("item %d: levels %s/%s -> %s/%s", rec.id, tostring(usedIL), tostring(usedML), il, ml)
        if LJ.Scoring then LJ.Scoring.InvalidateCache() end
        LJ:FireDebounced("ITEMS_UPDATED", 0.2)
    end
end

-- Name and quality of an open world drop or quest reward from the shipped strings.
function Items.GetWorldName(itemID)
    local text = (LJ.Data.WorldDrops and LJ.Data.WorldDrops[itemID])
        or (LJ.Data.WorldQuestItems and LJ.Data.WorldQuestItems[itemID])
    if not text then return nil end
    local name, q = text:match("^(.-)|(%d+)")
    return name, tonumber(q)
end

-- Name in the addon language chosen in the options (Core/Locale.lua): the translated name when German or Russian is
-- used, even if the game client names the item in English.
local function ShownName(id, name)
    local names = LJ.Locale and LJ.Locale.itemNames
    return names and names[id] or name
end

-- A record starts with the saved or shipped data of the item (filled on first use, not at login).
local function Seed(rec)
    local id = rec.id
    local e = saved and saved[id]
    local name, q, il, ml, bind, set
    if e then
        name, q, il, ml, bind, set = e[1], e[2], e[3], e[4], e[5], e[6]
    else
        name, q, il, ml, bind, set = BakedFields(id)
    end
    if not name then return end
    name = ShownName(id, name)
    rec.name, rec.quality, rec.itemLevel, rec.minLevel, rec.bindType = name, q, il, ml, bind
    rec.setID = (set or 0) > 0 and set or nil
    rec.loaded = true
    rec.fromCache = true
end

local function FillInstant(rec)
    local id = rec.id
    local itemID, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(id)
    rec.exists = itemID ~= nil
    rec.equipLoc = equipLoc
    rec.icon = icon
    rec.classID = classID
    rec.subclassID = subclassID
    local metaName, metaSlot, flags = Items.GetMeta(id)
    if metaName then
        rec.fallbackName = metaName ~= "" and metaName or nil
        rec.slotText = metaSlot ~= "" and metaSlot or nil
        -- flags only when set: every field more makes each of the thousands of records bigger
        rec.isNew = flags:find("N", 1, true) and true or nil
        rec.isSeen = flags:find("S", 1, true) and true or nil
        rec.isQuest = flags:find("Q", 1, true) and true or nil
    end
    local worldName, worldQuality = Items.GetWorldName(id)
    if worldName then
        -- open world drops and quest rewards that are not in the dungeon data: name and quality until the
        -- client answers
        rec.isWorld = true
        rec.fallbackName = rec.fallbackName or worldName
        rec.quality = rec.quality or worldQuality
    end
    if classID == 12 then rec.isQuest = true end
end

local function FillFull(rec)
    -- an item the shipped data names as without server data is not revealed yet: the client's data of it is never
    -- taken (the items Forever reveals since come with a new /lf collect and an update of the addon)
    if bakedMissing and bakedMissing[rec.id] then return false end
    local name, link, quality, itemLevel, minLevel, _, _, _, _, _, _, _, _, bindType, _, setID = C_Item.GetItemInfo(rec.id)
    if name then
        rec.setID = setID
        rec.name = name
        rec.link = link
        rec.quality = quality
        rec.itemLevel = itemLevel
        rec.minLevel = minLevel
        rec.bindType = bindType
        rec.loaded = true
        rec.live = true         -- data from the client in this session (not only from the saved cache)
        rec.fromCache = nil
        Persist(rec)    -- saved with the client's name
        rec.name = ShownName(rec.id, name)
        searchKeys[rec.id] = nil   -- made again from this name when a search needs it
        return true
    end
    return false
end

function Items.LoadSavedCache()
    local version, build = GetBuildInfo()
    local key = string.format("%s.%s:%s:%d", version, build, GetLocale(), CACHE_FORMAT)
    local c = LJ.db.itemCache
    if type(c) ~= "table" or c.key ~= key or type(c.items) ~= "table" then
        c = { key = key, items = {} }
        LJ.db.itemCache = c
    end
    -- Forever item data shipped with the addon (Data/ItemStats.lua): the one source of its items, ready even on the
    -- very first login; its items are never asked from the server, nor are the items it names as without server data
    -- (a new /lf collect finds the ones Forever has opened since).
    local shipped = LJ.Data.ItemStats
    bakedItems, bakedMissing, bakedWeapons, bakedSkills = nil, nil, nil, nil
    skillRanks = nil
    Items.bakedCount = 0
    if shipped and type(shipped.items) == "table" then
        bakedItems, bakedWeapons, bakedSkills = shipped.items, shipped.weapons, shipped.skills
        for _ in pairs(bakedItems) do Items.bakedCount = Items.bakedCount + 1 end
        bakedMissing = {}
        for _, id in ipairs(shipped.missing or {}) do bakedMissing[id] = true end
    end
    saved = c.items
    if type(c.missing) ~= "table" then c.missing = {} end
    missing = c.missing
    -- the saved cache keeps only what the shipped data does not have (or has differently); records are
    -- filled from it on first use
    local n = 0
    for id, e in pairs(saved) do
        -- a client in another language cannot read every stat (LJ.ENGLISH_CLIENT): stats it saved for items
        -- that ship with stats are dropped, the shipped ones count
        if not LJ.ENGLISH_CLIENT and type(e) == "table" and e.s and type(id) == "number" then
            local _, _, _, _, _, _, st = BakedFields(id)
            if st and st ~= "-" then e.s = nil end
        end
        if type(id) ~= "number" or type(e) ~= "table" or type(e[1]) ~= "string" then
            saved[id] = nil
        elseif (bakedItems and bakedItems[id]) or (bakedMissing and bakedMissing[id]) then
            saved[id] = nil   -- the shipped data is the item's one source (also for an item it has as without data)
        else
            n = n + 1
        end
    end
    Items.savedCount = n
    for id in pairs(missing) do
        if bakedItems and bakedItems[id] then missing[id] = nil end
    end
end
LJ:Listen("DB_READY", function() Items.LoadSavedCache() end)

-- Items the server never answered for (asked again only when the game version changes).
function Items.MarkMissing(itemID)
    local rec = cache[itemID]
    if missing and not (rec and rec.loaded) then missing[itemID] = true end
end

function Items.IsKnownMissing(itemID)
    return (missing and missing[itemID]) or (bakedMissing and bakedMissing[itemID]) or false
end

-- True for an item of the shipped data (Data/ItemStats.lua): everything about it comes from there.
function Items.IsShipped(itemID)
    return bakedItems ~= nil and bakedItems[itemID] ~= nil
end

-- A weapon's damage and speed from the shipped data: min, max, speed; nil for other items.
function Items.GetWeapon(itemID)
    local text = bakedWeapons and bakedWeapons[itemID]
    if not text then return nil end
    local lo, hi, speed = text:match("^(%d+)|(%d+)|([%d.]+)$")
    return tonumber(lo), tonumber(hi), tonumber(speed)
end

-- The profession an item asks for, from the shipped data: skill line, rank; nil for other items.
function Items.GetSkill(itemID)
    local text = bakedSkills and bakedSkills[itemID]
    if not text then return nil end
    local line, rank = text:match("^(%d+)|(%d+)$")
    return tonumber(line), tonumber(rank)
end

-- The ranks the shipped items ask for in a profession (skill line): { [rank] = true }, empty for a profession no item
-- asks for. Made once from the shipped data (again when it is loaded again: Items.LoadSavedCache).
local NO_RANKS = {}
function Items.SkillRanks(line)
    if not skillRanks then
        skillRanks = {}
        if bakedSkills then
            for _, text in pairs(bakedSkills) do
                local l, rank = text:match("^(%d+)|(%d+)$")
                l = tonumber(l)
                skillRanks[l] = skillRanks[l] or {}
                skillRanks[l][tonumber(rank)] = true
            end
        end
    end
    return skillRanks[line] or NO_RANKS
end

-- Items only some classes can use ("Classes: Mage" in the tooltip; Data/ItemClasses.lua, class bits of the
-- Classic data). True for every item without such a restriction.
local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, DRUID = 1024 }
Items.CLASS_BITS = CLASS_BITS   -- /lf collect reads the classes of the item tooltips into these bits
function Items.IsClassAllowed(itemID, class)
    local mask = itemID and LJ.Data.ItemClasses and LJ.Data.ItemClasses[itemID]
    local classBit = mask and CLASS_BITS[class]
    if not classBit then return true end
    return math.floor(mask / classBit) % 2 == 1
end

-- Stats of an item saved by Scoring in an earlier session.
-- Stats shipped with the addon (Data/ItemStats.lua, read from an English client), nil when there are none.
function Items.GetShippedStats(itemID)
    local _, _, _, _, _, _, st = BakedFields(itemID)
    return ParseStats(st)
end

function Items.GetSavedStats(itemID)
    local e = saved and saved[itemID]
    if e and e.s then return e.s end
    local _, _, _, _, _, _, st = BakedFields(itemID)
    return ParseStats(st)
end

function Items.SaveStats(itemID, stats)
    local e = saved and saved[itemID]
    if e and next(stats) ~= nil then e.s = stats end
end

-- For the ranking, which looks at thousands of items without creating a record for each: stats saved in an
-- earlier session, or the shipped ones parsed into the caller's scratch table (nothing is kept). nil when
-- neither knows the item's stats. (Items the window shows are read from the client; when the client knows one
-- differently, Persist makes the rankings again.)
function Items.GetKnownStats(itemID, scratch)
    local e = saved and saved[itemID]
    if e and e.s then return e.s end
    local text = bakedItems and bakedItems[itemID]
    if not text then return nil end
    local p = 0
    for _ = 1, 6 do
        p = text:find("|", p + 1, true)
        if not p then return nil end
    end
    if text:byte(p + 1) == 45 and p + 1 == #text then return nil end   -- "-": stats not read
    return ParseStatsInto(text, scratch, p + 1)
end

-- Required level and item level without creating a record: from the item's record (when one exists and has
-- data), the saved cache or the shipped data. nil when none of them knows the item.
function Items.GetKnownLevels(itemID)
    local rec = cache[itemID]
    if rec and rec.loaded then return rec.minLevel or 0, rec.itemLevel or 0 end
    local e = saved and saved[itemID]
    if e then return e[4] or 0, e[3] or 0 end
    local text = bakedItems and bakedItems[itemID]
    if text then
        local il, ml = NumField(text, 3), NumField(text, 4)
        if il and ml then return ml, il end
    end
    return nil
end

-- A new record: the client's instant facts, then the saved or shipped data.
local function NewRecord(itemID)
    local rec = { id = itemID }
    cache[itemID] = rec
    FillInstant(rec)
    Seed(rec)
    return rec
end

-- Returns the cached record for an item and requests missing data.
function Items.Get(itemID)
    local rec = cache[itemID] or NewRecord(itemID)
    if not rec.loaded then
        -- an item known as without server data is never asked for (not even the client: that would ask the server)
        if not Items.IsKnownMissing(itemID) and not FillFull(rec) and not rec.failed then Items.Request(itemID) end
    elseif rec.fromCache and not rec.liveChecked and not Items.IsShipped(itemID) then
        rec.liveChecked = true
        if C_Item.IsItemDataCachedByID(itemID) then FillFull(rec) end
    end
    if not rec.quality then
        rec.quality = C_Item.GetItemQualityByID(itemID)
    end
    return rec
end

-- Search key of an item's name without creating its record: the search scans thousands of items per key
-- press, a record for each would stay in memory.
function Items.GetSearchKey(itemID)
    local key = searchKeys[itemID]
    if key then return key end
    local rec = cache[itemID]
    local name = rec and rec.loaded and rec.name
    local names = LJ.Locale and LJ.Locale.itemNames
    name = name or (names and names[itemID])
    if not name then
        local e = saved and saved[itemID]
        name = e and e[1] or BakedFields(itemID)
    end
    if not name then
        local metaName = Items.GetMeta(itemID)
        name = (metaName and metaName ~= "" and metaName) or Items.GetWorldName(itemID)
    end
    key = Util.SearchKey(name or "")
    if name then searchKeys[itemID] = key end
    return key
end

-- Search keys and item records are made while the window shows items and dropped when it closes, so they do not
-- pile up over a long session (both are made again in an instant from the shipped and saved data).
LJ:Listen("WINDOW_CLOSED", function()
    searchKeys = {}
    cache = {}
end)

-- Like Items.Get, but never asks the server for data. Used where thousands of
-- items are scanned at once (search), so typing does not flood item requests.
function Items.Peek(itemID)
    local rec = cache[itemID] or NewRecord(itemID)
    if not rec.loaded and C_Item.IsItemDataCachedByID(itemID) then
        FillFull(rec)
    end
    return rec
end

-- force: ask the server again even if a request is still open (it may have been dropped).
-- The client's own data of an item when the client has it already (the name in the client's language), also for
-- records filled from the saved or shipped data. rec.live is true when the client's data is in the record.
function Items.GetLive(itemID)
    local rec = Items.Get(itemID)
    if not rec.live and C_Item.IsItemDataCachedByID(itemID) then FillFull(rec) end
    return rec
end

function Items.Request(itemID, callback, force)
    if callback then
        waiting[itemID] = waiting[itemID] or {}
        table.insert(waiting[itemID], callback)
    end
    if requested[itemID] and not force then return end
    local repeated = requested[itemID]
    requested[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
    local st = Items.netStats
    st.requests = st.requests + 1
    if repeated then st.repeats = st.repeats + 1 end
end

-- Calls callback(rec) once the item data is available (immediately if cached, or for an item known as without server
-- data: never asked for).
function Items.WhenLoaded(itemID, callback)
    local rec = Items.Get(itemID)
    if rec.loaded or not rec.exists or Items.IsKnownMissing(itemID) then
        callback(rec)
    else
        Items.Request(itemID, callback)
    end
end

local function OnItemData(_, itemID, success)
    if not itemID or not requested[itemID] then return end
    requested[itemID] = nil
    local rec = cache[itemID]
    local st = Items.netStats
    st.answers = st.answers + 1
    local changed = success ~= false
    if rec and not Items.IsShipped(itemID) then
        local ok = FillFull(rec)
        if success == false or not ok then
            -- the server answered, but has no data for this item
            rec.failed = true
            changed = false
            st.noData = st.noData + 1
            if not st.noDataSeen[itemID] then
                st.noDataSeen[itemID] = true
                st.noDataIDs[#st.noDataIDs + 1] = itemID
            end
            Items.MarkMissing(itemID)
        end
    end
    local cbs = waiting[itemID]
    if cbs then
        waiting[itemID] = nil
        for i = 1, #cbs do
            LJ:SafeCall(cbs[i], rec or Items.Get(itemID))
        end
    end
    -- the pages show the new data; an answer without data changes nothing they show
    if changed then
        LJ:Debug("item data: %d", itemID)
        LJ:FireDebounced("ITEMS_UPDATED", 0.2)
    end
end

LJ:On("GET_ITEM_INFO_RECEIVED", OnItemData)
LJ:On("ITEM_DATA_LOAD_RESULT", OnItemData)

---------------------------------------------------------------------------
-- Presentation helpers
---------------------------------------------------------------------------
function Items.GetName(itemID)
    local rec = Items.Get(itemID)
    return rec.name or rec.fallbackName or F("Item #%s", tostring(itemID))
end

function Items.GetColoredName(itemID)
    local rec = Items.Get(itemID)
    local r, g, b = Util.QualityColor(rec.quality or 1)
    return Util.ColorText(rec.name or rec.fallbackName or F("Item #%s", tostring(itemID)), r, g, b)
end

function Items.GetLink(itemID)
    local rec = Items.Get(itemID)
    if not rec.link then
        rec.link = (select(2, C_Item.GetItemInfo(itemID)))
    end
    return rec.link or ("item:" .. itemID)
end

local SUBCLASS_ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield",
    [7] = "Libram", [8] = "Idol", [9] = "Totem" }
local SUBCLASS_WEAPON = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm",
    [7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow",
    [19] = "Wand", [20] = "Fishing Pole" }

-- Weapon types that already say which hand they are for.
local WEAPON_IMPLIES_SLOT = { Staff = true, Polearm = true, Dagger = true, ["Fist Weapon"] = true, Bow = true, Gun = true,
    Crossbow = true, Wand = true, Thrown = true, ["Fishing Pole"] = true }

-- Localized armor type name (Cloth, Leather, Mail, Plate) from the client.
local function ArmorTypeName(subclassID)
    return C_Item.GetItemSubClassInfo(4, subclassID)
end

-- Slot text in the interface language: the whole text when it is known ("Quest Item"), otherwise each
-- ", "-separated part, split once at a space into two known words ("One-Hand Dagger", "Chest, Cloth").
-- Unknown texts (and everything when English is used) stay as they are.
local function SlotTextL(s)
    if not LJ.uiText or not s or s == "" then return s end
    local whole = L(s)
    if whole ~= s then return whole end
    local parts = {}
    for part in (s .. ", "):gmatch("(.-), ") do
        local text = L(part)
        if text == part then
            local pos = 1
            while true do
                local sp = part:find(" ", pos, true)
                if not sp then break end
                local a, b = part:sub(1, sp - 1), part:sub(sp + 1)
                local ta, tb = L(a), L(b)
                if ta ~= a and tb ~= b then
                    text = ta .. " " .. tb
                    break
                end
                pos = sp + 1
            end
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, ", ")
end

-- "Leather Waist", "Two-Hand Axe", "Staff", "Finger" style text (slot names from the client).
function Items.GetSlotText(itemID)
    return Items.SlotTextOf(Items.Get(itemID))
end

-- The same from a record (Items.Peek: lists of thousands of items that must not ask the server).
function Items.SlotTextOf(rec)
    if rec.equipLoc and rec.equipLoc ~= "" then
        local slot = _G[rec.equipLoc] or ""
        local sub = rec.subclassID
        if rec.classID == 4 and sub then
            if sub >= 1 and sub <= 4 and rec.equipLoc ~= "INVTYPE_CLOAK" then
                if slot ~= "" then return L(ArmorTypeName(sub)) .. " " .. SlotTextL(slot) end
            elseif sub >= 6 and SUBCLASS_ARMOR[sub] then
                return L(SUBCLASS_ARMOR[sub])
            end
        elseif rec.classID == 2 and sub and SUBCLASS_WEAPON[sub] then
            local weapon = SUBCLASS_WEAPON[sub]
            if WEAPON_IMPLIES_SLOT[weapon] or slot == "" then return L(weapon) end
            return SlotTextL(slot) .. " " .. L(weapon)
        end
        if slot ~= "" then return SlotTextL(slot) end
    end
    if rec.isQuest then return L("Quest Item") end
    return SlotTextL(rec.slotText) or ""
end

-- Level from which an item can be used: its required level. Items without one (many quest rewards) count
-- from the level of the quest that gives them, otherwise from their item level (Classic: roughly item level - 5, at
-- most the highest character level).
local NO_QUESTS = {}
local MAX_LEVEL = 60

-- How far below its own level a quest counts at the earliest (Items.QuestFrom): a level 60 fishing quest anyone may
-- take from level 1 is no reward for a level 20 character.
Items.QUEST_REACH = 10

-- The level from which a quest counts: the lowest level it can be taken at, but at most QUEST_REACH levels below its
-- own (Whirlwind Weapon: level 40, taken from 30, counts from 30).
function Items.QuestFrom(minLevel, questLevel)
    return math.max(minLevel or 0, (questLevel or 0) - Items.QUEST_REACH)
end

-- The same from known levels (the ranking reads them without a record). A quest reward without a level of its own:
-- the lowest level one of its quests counts from (Items.QuestFrom; dungeon and open world quests: Data/WorldQuests,
-- "name|level|min|...").
function Items.UseLevelFrom(itemID, minLevel, itemLevel)
    local level = minLevel or 0
    if level > 1 then return level end
    local Q = LJ.Quests
    local best
    for _, qid in ipairs(Q and Q.rewardOf and Q.rewardOf[itemID] or NO_QUESTS) do
        local q = Q.Get(qid)
        local l = q and Items.QuestFrom(q.min, q.level)
        if l and (not best or l < best) then best = l end
    end
    local world = LJ.Data.WorldQuestRewards and LJ.Data.WorldQuestRewards[itemID]
    for qid in tostring(world or ""):gmatch("%d+") do
        local text = LJ.Data.WorldQuests[tonumber(qid)]
        local questLevel, min
        if text then questLevel, min = text:match("^[^|]*|(%d+)|(%d+)|") end
        local l = min and Items.QuestFrom(tonumber(min), tonumber(questLevel))
        if l and (not best or l < best) then best = l end
    end
    if best then return best end
    if itemLevel and itemLevel > 6 then return math.min(itemLevel - 5, MAX_LEVEL) end
    return level
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
function Items.GetSources(itemID)
    return Items.sources[itemID]
end


-- "Crafted: Blacksmithing" for an item the game's recipes make (Data/Crafted.lua: the professions by skill line, their
-- names in Data.Professions, translated by the language data); nil for other items
function Items.GetCraftedText(itemID)
    local by = Items.GetCraftedBy(itemID)
    return by and F("Crafted: %s", by)
end

-- The professions that make an item ("Blacksmithing", "Leatherworking, Tailoring"), nil for an item no recipe makes.
function Items.GetCraftedBy(itemID)
    local professions = LJ.Data.Crafted[itemID]
    if not professions then return nil end
    local names = {}
    for id in professions:gmatch("%d+") do names[#names + 1] = LJ.Data.Professions[tonumber(id)] end
    return table.concat(names, ", ")
end

-- "Edwin VanCleef - The Deadmines"; items without a dungeon source: "Quest: The People's Militia - Westfall",
-- "Vultros (Rare) - Westfall", "World drop - level 30-35" or "Crafted: Blacksmithing"
function Items.GetSourceText(itemID, maxEntries, withChance)
    local list = Items.sources[itemID]
    if not list then
        return Items.GetQuestSourceText(itemID) or Items.GetWorldSourceText(itemID, withChance)
            or Items.GetCraftedText(itemID)
    end
    local parts = {}
    for i = 1, math.min(#list, maxEntries or 1) do
        local s = list[i]
        local inst = LJ.instanceByKey[s.inst]
        if inst then
            local bossName = (s.boss == 0) and L("Trash") or (inst.bosses[s.boss] and inst.bosses[s.boss].name) or "?"
            local text = bossName .. " - " .. inst.name
            if withChance and s.chance then
                text = text .. " (" .. Util.FormatChance(s.chance) .. ")"
            end
            parts[#parts + 1] = text
        end
    end
    local text = table.concat(parts, ", ")
    if #list > (maxEntries or 1) then
        text = text .. string.format(" (+%d)", #list - (maxEntries or 1))
    end
    return text
end

-- Best known drop chance: the first dungeon source, otherwise the first open world mob.
function Items.GetBestChance(itemID)
    local list = Items.sources[itemID]
    if list then return list[1] and list[1].chance end
    local world = Items.GetWorldSources(itemID)
    return world and world[1] and world[1].chance
end

---------------------------------------------------------------------------
-- Open world drops (Data/WorldDrops.lua): mobs outside instances, rares included
---------------------------------------------------------------------------
local RANK_TEXT = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local mobCache = {}

-- Open world drop of an item: { name, quality, requiredLevel, { npcID, chance, ... }, minLevel, maxLevel, mobs }
-- (the last three for random world drops). Read from the shipped string on first use.
local worldDrops = {}
function Items.GetWorldDrop(itemID)
    local d = worldDrops[itemID]
    if d ~= nil then return d or nil end
    local text = LJ.Data.WorldDrops and LJ.Data.WorldDrops[itemID]
    if not text then
        worldDrops[itemID] = false
        return nil
    end
    local name, q, req, mobText, rest = text:match("^(.-)|(%d+)|(%d+)|([^|]*)(.*)$")
    local mobs = {}
    for npc, chance in (mobText or ""):gmatch("(%d+):([%d.]+)") do
        mobs[#mobs + 1] = tonumber(npc)
        mobs[#mobs + 1] = tonumber(chance)
    end
    local lo, hi, n = (rest or ""):match("^|(%d+)|(%d+)|(%d+)$")
    d = { name, tonumber(q), tonumber(req), mobs, tonumber(lo), tonumber(hi), tonumber(n) }
    worldDrops[itemID] = d
    return d
end

function Items.HasWorldDrop(itemID)
    return LJ.Data.WorldDrops ~= nil and LJ.Data.WorldDrops[itemID] ~= nil
end

-- { id, name, minLevel, maxLevel, rank, rankText, isRare, spawns, display (its face), locs = { { w = { continent, x, y } }, ... } }
function Items.GetWorldMob(npcID)
    local mob = mobCache[npcID]
    if mob then return mob end
    local d = LJ.Data.WorldMobs and LJ.Data.WorldMobs[npcID]
    if not d then return nil end
    mob = { id = npcID, name = d[1], minLevel = d[2], maxLevel = d[3], rank = d[4], spawns = d[5], display = d[6], locs = {} }
    mob.rankText = L(RANK_TEXT[d[4]])
    mob.isRare = d[4] == 2 or d[4] == 4
    for i = 7, #d do
        mob.locs[#mob.locs + 1] = { w = d[i], name = d[1] }
    end
    mobCache[npcID] = mob
    return mob
end

-- Returns { { mob, chance }, ... } (highest chance first) and, for random world drops,
-- { minLevel, maxLevel, mobs } of the mobs that can drop it.
-- Built once per item and kept with its drop entry (callers only read the lists).
function Items.GetWorldSources(itemID)
    local d = Items.GetWorldDrop(itemID)
    if not d then return nil end
    if not d.sources then
        local list, mobs = {}, d[4]
        for i = 1, #mobs, 2 do
            local mob = Items.GetWorldMob(mobs[i])
            if mob then list[#list + 1] = { mob = mob, chance = mobs[i + 1] } end
        end
        d.sources = list
        d.random = d[5] and { minLevel = d[5], maxLevel = d[6], mobs = d[7] } or false
    end
    return d.sources, d.random or nil
end

-- Zone of the mob's main camp (from the game's map data).
function Items.GetMobZone(mob)
    local loc = mob and mob.locs[1]
    if not loc then return nil end
    LJ.MapPin.Resolve(loc)
    return loc.zone
end

-- " (0.03%)": the chance as the loot lists show it, "" without a chance
local function ChanceText(chance)
    local text = Util.FormatChance(chance)
    return text and (" (" .. text .. ")") or ""
end

function Items.GetWorldSourceText(itemID, withChance)
    local list, random = Items.GetWorldSources(itemID)
    if list and list[1] then
        local s = list[1]
        local text = s.mob.name
        if s.mob.rankText then text = text .. " (" .. s.mob.rankText .. ")" end
        local zone = Items.GetMobZone(s.mob)
        if zone then text = text .. " - " .. zone end
        if withChance then text = text .. ChanceText(s.chance) end
        if #list > 1 then text = text .. string.format(" (+%d)", #list - 1) end
        return text
    elseif random then
        return F("World drop - level %s", Util.LevelRange(random.minLevel, random.maxLevel))
    end
    return nil
end

---------------------------------------------------------------------------
-- Open world by zone and mob (the Open World page and the search). Built on first use and dropped when the
-- window closes, like the search data.
---------------------------------------------------------------------------
local mobDrops, worldZones, zoneByMap

local function ByChance(a, b)
    if a.chance ~= b.chance then return a.chance > b.chance end
    return a.id < b.id
end

-- Drops of an open world mob: { { id = itemID, chance = percent }, ... }, highest chance first; nil when the data
-- lists no drop for it. Random world drops (almost any mob of a level range) are not listed per mob.
function Items.GetMobDrops(npcID)
    if not mobDrops then
        mobDrops = {}
        for itemID, text in pairs(LJ.Data.WorldDrops or {}) do
            local mobText = text:match("^[^|]*|%d+|%d+|([^|]*)")
            for npc, chance in (mobText or ""):gmatch("(%d+):([%d.]+)") do
                npc = tonumber(npc)
                local list = mobDrops[npc]
                if not list then
                    list = {}
                    mobDrops[npc] = list
                end
                list[#list + 1] = { id = itemID, chance = tonumber(chance) }
            end
        end
        for _, list in pairs(mobDrops) do table.sort(list, ByChance) end
    end
    return mobDrops[npcID]
end

-- Zone map of a mob's main camp (the game's map data), or nil.
function Items.GetMobZoneMap(mob)
    local loc = mob and mob.locs[1]
    if not loc then return nil end
    LJ.MapPin.Resolve(loc)
    return loc.map
end

local function ByMobOrder(a, b)
    if a.isRare ~= b.isRare then return a.isRare end
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    return a.name < b.name
end

-- Zones with open world mobs that drop something: { { map, name, minLevel, maxLevel, rares, mobs = { mob, ... } },
-- ... }, sorted by level (the zone's level range from the game's map data). A mob belongs to the zone of its main
-- camp; rares come first in a zone.
function Items.GetWorldZones()
    if worldZones then return worldZones end
    local list = {}
    zoneByMap = {}
    for npcID in pairs(LJ.Data.WorldMobs or {}) do
        local mob = Items.GetWorldMob(npcID)
        local map = mob and Items.GetMobDrops(npcID) and Items.GetMobZoneMap(mob)
        if map then
            local zone = zoneByMap[map]
            if not zone then
                zone = { map = map, name = mob.locs[1].zone or F("Map %d", map), minLevel = mob.minLevel,
                    maxLevel = mob.maxLevel, rares = 0, mobs = {} }
                zoneByMap[map] = zone
                list[#list + 1] = zone
            end
            zone.mobs[#zone.mobs + 1] = mob
            zone.minLevel = math.min(zone.minLevel, mob.minLevel)
            zone.maxLevel = math.max(zone.maxLevel, mob.maxLevel)
            if mob.isRare then zone.rares = zone.rares + 1 end
        end
    end
    for _, zone in ipairs(list) do
        table.sort(zone.mobs, ByMobOrder)
        -- the zone's level range as the game's world map shows it; the range of its mobs when the game has none
        local lo, hi = C_Map.GetMapLevels(zone.map)
        if lo and hi and lo > 0 and hi > 0 then zone.minLevel, zone.maxLevel = lo, hi end
    end
    table.sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.name < b.name
    end)
    worldZones = list
    return list
end

function Items.GetWorldZone(map)
    Items.GetWorldZones()
    return map and zoneByMap[map] or nil
end

-- made again when needed: the database reads the open world drop of thousands of items
LJ:Listen("WINDOW_CLOSED", function() mobDrops, worldZones, zoneByMap, worldDrops, mobCache = nil, nil, nil, {}, {} end)

---------------------------------------------------------------------------
-- Open world quest rewards (Data/WorldQuests.lua) and the dungeon quests' rewards (Data/Quests.lua)
---------------------------------------------------------------------------
local questCache = {}

-- { id, name, level, min, side, classes, races, giver, loc = { w, name } or nil, choice, reward, world = true }
-- Read from the shipped string on first use (races: Data/WorldQuestRaces).
local function Numbers(text)
    local list = {}
    for n in (text or ""):gmatch("[-%d]+") do list[#list + 1] = tonumber(n) end
    return list
end

function Items.GetWorldQuest(qid)
    local q = questCache[qid]
    if q then return q end
    local text = LJ.Data.WorldQuests and LJ.Data.WorldQuests[qid]
    if not text then return nil end
    local name, level, min, side, classes, giver, pos, choice, reward =
        text:match("^(.-)|(%d+)|(%d+)|(%a)|([^|]*)|(.-)|([^|]*)|([^|]*)|([^|]*)$")
    if not name then return nil end
    local classList
    if classes ~= "" then
        classList = {}
        for c in classes:gmatch("[^,]+") do classList[#classList + 1] = c end
    end
    local w = pos ~= "" and Numbers(pos) or nil
    q = { id = qid, name = name, level = tonumber(level), min = tonumber(min), side = side, classes = classList,
        races = LJ.Data.WorldQuestRaces[qid], giver = giver, loc = w and { w = w, name = giver } or nil,
        choice = Numbers(choice), reward = Numbers(reward), world = true }
    questCache[qid] = q
    return q
end

-- Quest IDs that reward an item (Data/WorldQuestRewards: one ID, or "id,id").
local function RewardQuestIDs(itemID)
    local v = LJ.Data.WorldQuestRewards and LJ.Data.WorldQuestRewards[itemID]
    if not v then return nil end
    if type(v) == "number" then return { v } end
    return Numbers(v)
end

function Items.GetWorldQuestItemIDs()
    local list = {}
    for itemID in pairs(LJ.Data.WorldQuestRewards or {}) do list[#list + 1] = itemID end
    table.sort(list)
    return list
end

-- The order of an item's quests (open world and dungeon quests, Core/Quests.lua): the character's own quests first, then
-- by level, name and ID.
function Items.QuestOrder(a, b)
    local Q = LJ.Quests
    local ma, mb = Q.IsForPlayer(a), Q.IsForPlayer(b)
    if ma ~= mb then return ma end
    if a.level ~= b.level then return a.level < b.level end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end
local QuestOrder = Items.QuestOrder

-- Open world quests that reward the item, in quest order. Built once per item (callers only read the list).
local worldQuestSources = {}
function Items.GetWorldQuestSources(itemID)
    local list = worldQuestSources[itemID]
    if list ~= nil then return list or nil end
    local ids = RewardQuestIDs(itemID)
    if not ids then
        worldQuestSources[itemID] = false
        return nil
    end
    list = {}
    for _, qid in ipairs(ids) do
        local q = Items.GetWorldQuest(qid)
        if q then list[#list + 1] = q end
    end
    table.sort(list, QuestOrder)
    worldQuestSources[itemID] = list
    return list
end

-- Zone of the quest giver (open world quests) or of the quest start (dungeon quests).
function Items.GetQuestZone(q)
    local loc = q and (q.loc or q.start)
    if not loc then return nil end
    LJ.MapPin.Resolve(loc)
    return loc.zone
end

-- Quest for the character's faction and a class (default: the character's class).
local function QuestFor(q, class)
    local Q = LJ.Quests
    local side = (LJ.Player and LJ.Player.faction == "Horde") and "H" or "A"
    return Q.IsForSide(q, side) and Q.IsForClass(q, class or (LJ.Player and LJ.Player.class))
end

-- The quest to take for this item: an open world or a dungeon quest of the character's faction and the class.
function Items.GetBestQuest(itemID, class)
    local Q = LJ.Quests
    for _, q in ipairs(Items.GetWorldQuestSources(itemID) or {}) do
        if QuestFor(q, class) then return q end
    end
    for _, qid in ipairs(Q and Q.rewardOf[itemID] or {}) do
        local q = Q.Get(qid)
        if q and QuestFor(q, class) then return q end
    end
    return nil
end

function Items.GetQuestSourceText(itemID)
    local q = Items.GetBestQuest(itemID)
    if not q then return nil end
    local zone = Items.GetQuestZone(q)
    return F("Quest: %s", q.name) .. (zone and (" - " .. zone) or "")
end

-- Faction and class check of an open world quest, read straight from its shipped string
-- ("name|level|min|side|CLASSES|..."): the ranking checks thousands of rewards, a quest table for each would stay
-- in memory. sideByte: byte of "A" or "H"; level (optional): the quest counts by then (Items.QuestFrom).
local function WorldQuestFits(qid, sideByte, class, level)
    local text = LJ.Data.WorldQuests and LJ.Data.WorldQuests[qid]
    if not text then return false end
    local p, afterName, afterLevel = 0, 0, 0
    for i = 1, 3 do
        p = text:find("|", p + 1, true)
        if not p then return false end
        if i == 1 then afterName = p elseif i == 2 then afterLevel = p end
    end
    if level and Items.QuestFrom(tonumber(text:sub(afterLevel + 1, p - 1)),
        tonumber(text:sub(afterName + 1, afterLevel - 1))) > level then
        return false
    end
    local side = text:byte(p + 1)
    if side ~= 66 and side ~= sideByte then return false end     -- 66 = "B" (both factions)
    local first = p + 3
    local bar = text:find("|", first, true)
    if not bar then return false end
    local last = bar - 1
    if last < first then return true end                         -- no class restriction
    local start = first
    while true do
        local s, e = text:find(class, start, true)
        if not s or e > last then return false end
        if (s == first or text:byte(s - 1) == 44) and (e == last or text:byte(e + 1) == 44) then return true end
        start = e + 1
    end
end

-- Can a character of this faction and class get the item: any drop source, a quest it can take (same answer as
-- Items.GetBestQuest, without building quest tables) or a recipe (Data/Crafted.lua).
function Items.IsObtainable(itemID, class)
    if Items.sources[itemID] or Items.HasWorldDrop(itemID) or LJ.Data.Crafted[itemID] then return true end
    class = class or (LJ.Player and LJ.Player.class) or "?"
    local horde = LJ.Player and LJ.Player.faction == "Horde"
    local v = LJ.Data.WorldQuestRewards and LJ.Data.WorldQuestRewards[itemID]
    if type(v) == "number" then
        if WorldQuestFits(v, horde and 72 or 65, class) then return true end
    elseif type(v) == "string" then
        -- "id,id": read digit by digit
        local qid = 0
        for i = 1, #v + 1 do
            local b = v:byte(i)
            if b and b >= 48 and b <= 57 then
                qid = qid * 10 + b - 48
            else
                if qid > 0 and WorldQuestFits(qid, horde and 72 or 65, class) then return true end
                qid = 0
            end
        end
    end
    local Q = LJ.Quests
    local side = horde and "H" or "A"
    for _, qid in ipairs(Q and Q.rewardOf[itemID] or NO_QUESTS) do
        local q = Q.Get(qid)
        if q and Q.IsForSide(q, side) and Q.IsForClass(q, class) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- The list: where the Best in Slot list's items may come from and the armor it takes (LJ.cdb.list: picked at the first
-- start, changed in the Best in Slot page's filter, UI/ListFilter.lua). The list, For you, the upgrade marks and the
-- sims take only these (Core/BiS.lua); the hard limits (the level, the class, the faction, a profession the item asks
-- for, items not in the game) the ranking checks on its own (Core/Scoring.lua).
---------------------------------------------------------------------------
-- The sources in the filter's order: quests the character can take, dungeon loot (bosses and trash), the loot of the
-- open world's rares and other mobs that carry the item, what the professions make, random world drops. chance: the
-- least drop chance in % of dungeon and mob drops (0: every drop; a drop without a known chance always counts).
Items.LIST_SOURCES = { "quests", "dungeons", "rare", "crafted", "world" }
-- The armor kinds by item subclass (1 cloth ... 4 plate): the list takes the picked ones in the armor slots (cloaks are
-- cloth for everyone and always count).
Items.LIST_ARMOR = { "cloth", "leather", "mail", "plate" }
Items.ARMOR_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true }

-- The list's armor kind of an item ("cloth" ... "plate"); nil outside the armor slots and their four kinds.
local function ArmorChoice(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == 4 and Items.ARMOR_SLOTS[equipLoc] and Items.LIST_ARMOR[subclassID] or nil
end

-- A dungeon drop the list takes: one of at least min % (a boss's or trash drop without a known chance too).
local function DungeonDrop(itemID, min)
    for _, s in ipairs(Items.sources[itemID] or NO_QUESTS) do
        if not s.chance or s.chance >= min then return true end
    end
    return false
end

-- An open world drop (Data/WorldDrops: "name|quality|requiredLevel|npc:chance;npc:chance|minLevel|maxLevel|mobs"),
-- read from its string without a table (the ranking checks thousands): the best chance of the mobs that carry it (nil:
-- none does) and true for a random world drop (any mob of a level range: the last three fields).
local function WorldDropOf(itemID)
    local text = LJ.Data.WorldDrops and LJ.Data.WorldDrops[itemID]
    if not text then return nil, false end
    local mobs, rest = text:match("^.-|%d+|%d+|([^|]*)(.*)$")
    local best
    for chance in mobs:gmatch(":([%d.]+)") do
        chance = tonumber(chance)
        if not best or chance > best then best = chance end
    end
    return best, rest ~= ""
end

-- A quest the character can take by the level gives the item: its faction and class (the player's own class: its race
-- too), the quest counting by then (Items.QuestFrom); dungeon and open world quests (class quests among them).
local function QuestReward(itemID, class, level)
    local Q, P = LJ.Quests, LJ.Player
    local horde = P.faction == "Horde"
    local own = class == P.class
    for _, qid in ipairs(Q.rewardOf[itemID] or NO_QUESTS) do
        local q = Q.Get(qid)
        if q and Items.QuestFrom(q.min, q.level) <= level and Q.IsForSide(q, horde and "H" or "A")
            and Q.IsForClass(q, class) and (not own or Q.IsForRace(q, P.race)) then
            return true
        end
    end
    for _, qid in ipairs(RewardQuestIDs(itemID) or NO_QUESTS) do
        local races = own and LJ.Data.WorldQuestRaces[qid]
        if WorldQuestFits(qid, horde and 72 or 65, class, level)
            and (not races or math.floor(races / 2 ^ (P.race - 1)) % 2 == 1) then
            return true
        end
    end
    return false
end

-- Does the list take the item for a class at a level: its armor kind is picked (the armor slots) and one of its
-- sources is (a drop: at least the list's drop chance). Kept per class and level until the list changes.
local inList = {}
function Items.InList(itemID, class, level)
    local key = class .. level
    local known = inList[key]
    if not known then
        known = {}
        inList[key] = known
    end
    local yes = known[itemID]
    if yes == nil then
        local list = LJ.cdb.list
        local armor = ArmorChoice(itemID)
        if armor and not list[armor] then
            yes = false
        else
            local chance, random = WorldDropOf(itemID)
            yes = (list.quests and QuestReward(itemID, class, level))
                or (list.dungeons and DungeonDrop(itemID, list.chance))
                or (list.rare and chance ~= nil and chance >= list.chance)
                or (list.crafted and LJ.Data.Crafted[itemID] ~= nil)
                or (list.world and random)
        end
        known[itemID] = yes
    end
    return yes
end

-- The list as one text ("111001111:10": the sources in order, the armor kinds in order, the drop chance): rankings
-- and sims are kept per list.
function Items.ListKey()
    local list, key = LJ.cdb.list, ""
    for _, source in ipairs(Items.LIST_SOURCES) do key = key .. (list[source] and "1" or "0") end
    for _, kind in ipairs(Items.LIST_ARMOR) do key = key .. (list[kind] and "1" or "0") end
    return key .. ":" .. list.chance
end

-- A choice of the list changed (a source or an armor kind on or off, the drop chance); everything that shows its items
-- follows (LIST_CHANGED).
function Items.SetListChoice(key, value)
    assert(type(LJ.charDefaults.list[key]) == type(value), "no list choice " .. tostring(key) .. " " .. tostring(value))
    LJ.cdb.list[key] = value
    LJ:Fire("LIST_CHANGED")
end

-- Back to realistic: the list of the first start (LJ.charDefaults.list).
function Items.ResetList()
    for key, on in pairs(LJ.charDefaults.list) do LJ.cdb.list[key] = on end
    LJ:Fire("LIST_CHANGED")
end

LJ:Listen("LIST_CHANGED", function() inList = {} end)
-- (the character's saved list replaces the defaults)
LJ:Listen("DB_READY", function() inList = {} end)

-- True when the stats of an item are known without asking the server: read this session, saved in an earlier
-- one, or shipped with the addon (checked without reading them).
function Items.HasKnownStats(itemID)
    if Items.IsShipped(itemID) then return true end
    local rec = cache[itemID]
    if rec and rec.live then return true end
    local e = saved and saved[itemID]
    if e and e.s then return true end
    local text = bakedItems and bakedItems[itemID]
    if not text then return false end
    local n = #text
    return not (text:byte(n) == 45 and text:byte(n - 1) == 124)   -- ends in "|-": stats not read
end

-- Name (in the addon's language) and quality of an item without creating its record (search sorts thousands of
-- names, the database lists them).
function Items.GetQuickInfo(itemID)
    local rec = cache[itemID]
    if rec and rec.loaded then return rec.name, rec.quality end
    local e = saved and saved[itemID]
    if e then return ShownName(itemID, e[1]), e[2] end
    local name, q = BakedFields(itemID)
    if name then return ShownName(itemID, name), q end
    local worldName, worldQuality = Items.GetWorldName(itemID)
    if worldName then return ShownName(itemID, worldName), worldQuality end
    local metaName = Items.GetMeta(itemID)
    return metaName ~= "" and ShownName(itemID, metaName) or nil, nil
end

---------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------
function Items.GetOwnedCount(itemID)
    return C_Item.GetItemCount(itemID, true)
end

function Items.IsOwned(itemID)
    if C_Item.IsEquippedItem(itemID) then return true end
    return Items.GetOwnedCount(itemID) > 0
end

---------------------------------------------------------------------------
-- The shipped Best in Slot items (Data/BiS.lua: where an item without loot source comes from)
---------------------------------------------------------------------------
function Items.GetBiSEntries(itemID)
    return Items.bisIndex[itemID]
end

-- True for a shipped Best in Slot item that only the other faction can get (an entry of Data/BiS.lua names its
-- faction: PvP and reputation rewards, one faction's quest rewards).
function Items.IsOtherFaction(itemID)
    local faction = bisFaction[itemID]
    return faction ~= nil and faction ~= LJ.Player.faction
end

---------------------------------------------------------------------------
-- Wishlist
---------------------------------------------------------------------------
-- False while the Wishlist module is off (no stars, tooltip mark or alerts; the list itself is kept).
function Items.IsWishlisted(itemID)
    return LJ.Modules.On("wishlist") and LJ.cdb.wishlist[itemID] ~= nil
end

function Items.ToggleWishlist(itemID)
    assert(LJ.Modules.On("wishlist"), "the Wishlist module is off")
    if LJ.cdb.wishlist[itemID] then
        LJ.cdb.wishlist[itemID] = nil
        LJ:Print("Removed %s from your wishlist.", Items.GetColoredName(itemID))
    else
        local src = Items.sources[itemID]
        LJ.cdb.wishlist[itemID] = { t = time(), inst = src and src[1] and src[1].inst or nil }
        LJ:Print("Added %s to your wishlist.", Items.GetColoredName(itemID))
    end
    LJ:Fire("WISHLIST_CHANGED", itemID)
end

-- Adds several items at once (one chat line, one refresh). Returns the number of items added.
function Items.AddToWishlist(ids)
    local added = 0
    for _, itemID in ipairs(ids) do
        if not LJ.cdb.wishlist[itemID] then
            local src = Items.sources[itemID]
            LJ.cdb.wishlist[itemID] = { t = time(), inst = src and src[1] and src[1].inst or nil }
            added = added + 1
        end
    end
    if added > 0 then
        LJ:Print("%s added to your wishlist.", Util.Plural(added, "item", "items"))
        LJ:Fire("WISHLIST_CHANGED")
    end
    return added
end

---------------------------------------------------------------------------
-- Modified clicks (shift = link, ctrl = dress up, alt = sim)
---------------------------------------------------------------------------
function Items.HandleClick(itemID, button)
    local link = Items.GetLink(itemID)
    -- Alt alone sims the item, as on the game's items (the upgrade check's window)
    if LJ.UI.ItemCheckBox:AltClick(link) then return true end
    -- a chat link needs the game's own link; before the item has loaded there is only the bare item string
    if IsModifiedClick("CHATLINK") and not link:find("|H", 1, true) then return true end
    if HandleModifiedItemClick(link) then
        return true
    end
    return false
end

BuildIndexes()
