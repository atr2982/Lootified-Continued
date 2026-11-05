-- Lootified - item stats and the hidden ranking: reads the Forever item stats (shipped, or the client's for items
-- outside the shipped data) and scores items per spec with stat weights. The ranking is never shown as such: it fills
-- the Best in Slot list where the simulator does not decide it (Core/BiS.lua).
local _, LJ = ...

local Scoring = {}
LJ.Scoring = Scoring

local Items = LJ.Items
local Player = LJ.Player

---------------------------------------------------------------------------
-- Stat extraction
---------------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AttackPower",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RangedAttackPower",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FeralAttackPower",
    ITEM_MOD_HIT_RATING_SHORT = "HitRating",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "MeleeHitRating",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "RangedHitRating",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SpellHitRating",
    ITEM_MOD_CRIT_RATING_SHORT = "CritRating",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "MeleeCritRating",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "RangedCritRating",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SpellCritRating",
    ITEM_MOD_HASTE_RATING_SHORT = "HasteRating",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "ExpertiseRating",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense",
    ITEM_MOD_DODGE_RATING_SHORT = "DodgeRating",
    ITEM_MOD_PARRY_RATING_SHORT = "ParryRating",
    ITEM_MOD_BLOCK_RATING_SHORT = "BlockRating",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
    ITEM_MOD_SPELL_POWER_SHORT = "SpellPowerAll",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "ShadowPower",
    ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "FirePower",
    ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "FrostPower",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "NaturePower",
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "ArcanePower",
    ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "HolyPower",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "Armor",
    RESISTANCE0_NAME = "Armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
    ITEM_MOD_AXES_SHORT = "WeaponSkill", ITEM_MOD_BOWS_SHORT = "WeaponSkill", ITEM_MOD_CROSSBOWS_SHORT = "WeaponSkill",
    ITEM_MOD_DAGGERS_SHORT = "WeaponSkill", ITEM_MOD_FIST_WEAPONS_SHORT = "WeaponSkill", ITEM_MOD_GUNS_SHORT = "WeaponSkill",
    ITEM_MOD_MACES_SHORT = "WeaponSkill", ITEM_MOD_POLEARMS_SHORT = "WeaponSkill", ITEM_MOD_SWORDS_SHORT = "WeaponSkill",
    ITEM_MOD_STAVES_SHORT = "WeaponSkill",
}

Scoring.STAT_KEYS = STAT_KEYS

-- English "Equip:" lines that GetItemStats does not always expose (percentage
-- based Classic effects). Only used when the stat is missing from GetItemStats.
-- Attack power that only counts in Cat and Bear form is feral attack power (e.g. Mace of Unending Life: "+140 Attack
-- Power in Cat, Bear, and Dire Bear forms only.").
local EQUIP_PATTERNS = {
    { "%+(%d+) Attack Power in Cat", "FeralAttackPower" },
    { "attack power by (%d+) in Cat", "FeralAttackPower" },
    { "chance to hit with spells by (%d+)%%", "SpellHitPct" },
    { "chance to get a critical strike with spells by (%d+)%%", "SpellCritPct" },
    { "chance to hit by (%d+)%%", "HitPct" },
    { "chance to get a critical strike by (%d+)%%", "CritPct" },
    { "chance to dodge an attack by (%d+)%%", "DodgePct" },
    { "chance to parry an attack by (%d+)%%", "ParryPct" },
    { "chance to block attacks with a shield by (%d+)%%", "BlockPct" },
    { "damage and healing done by magical spells and effects by up to (%d+)", "SpellPowerAll" },
    { "healing done by spells and effects by up to (%d+)", "Healing" },
    { "healing done by magical spells and effects by up to (%d+)", "Healing" },
    { "damage done by Shadow spells and effects by up to (%d+)", "ShadowPower" },
    { "damage done by Fire spells and effects by up to (%d+)", "FirePower" },
    { "damage done by Frost spells and effects by up to (%d+)", "FrostPower" },
    { "damage done by Nature spells and effects by up to (%d+)", "NaturePower" },
    { "damage done by Arcane spells and effects by up to (%d+)", "ArcanePower" },
    { "damage done by Holy spells and effects by up to (%d+)", "HolyPower" },
    { "Restores (%d+) mana per 5 sec", "MP5" },
    { "%+(%d+) Attack Power", "AttackPower" },
    { "attack power by (%d+)", "AttackPower" },
    { "block value of your shield by (%d+)", "BlockValue" },
    { "defense skill by (%d+)", "Defense" },
    { "Increased Defense %+(%d+)", "Defense" },
    { "your hit by (%d+)", "HitRating" },
    { "your critical strike by (%d+)", "CritRating" },
}

local statCache = {}
local liveStats = {}   -- [itemID] = true when statCache holds stats read from the client this session

-- The "Equip:" lines are read with English patterns (EQUIP_PATTERNS). On a client in another language they do
-- not match, so stats read there can miss spell power, hit, crit, MP5 and the like. Such clients use the stats
-- shipped with the addon (read from an English client) for every item that has them (LJ.ENGLISH_CLIENT).
local ENGLISH_CLIENT = LJ.ENGLISH_CLIENT

-- Effects that only count against some enemies are not stats of the item (Mark of the Champion: "+150 Attack Power
-- when fighting Undead and Demons.").
local function ParseTooltipData(data, stats)
    if not data or not data.lines then return end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not LJ.Util.IsSecret(text) and text:find("Equip:", 1, true)
            and not text:find(" when fighting ", 1, true) then
            for _, p in ipairs(EQUIP_PATTERNS) do
                local value = text:match(p[1])
                if value and not stats[p[2]] then
                    stats[p[2]] = tonumber(value)
                    break
                end
            end
        end
    end
end

local function ParseTooltip(itemID, stats)
    ParseTooltipData(C_TooltipInfo.GetItemByID(itemID), stats)
end

-- Stats of one concrete item link (random suffixes like "of the Bear" included), for tooltips of any item in
-- the game (bags, bank, vendors, auction house, other players). Not written to the item cache.
-- nil while the client has no data for the item yet.
local linkStats, linkStatsCount = {}, 0
function Scoring.GetStatsForLink(link)
    if type(link) ~= "string" or LJ.Util.IsSecret(link) then return nil end
    local cached = linkStats[link]
    if cached then return cached end
    if not ENGLISH_CLIENT then
        -- items without a random suffix: the shipped stats (see ENGLISH_CLIENT)
        local id = tonumber(link:match("item:(%d+)"))
        local suffix = link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d*)")
        local shipped = id and (not suffix or suffix == "" or suffix == "0") and Items.GetShippedStats(id)
        if shipped then
            if linkStatsCount > 400 then linkStats, linkStatsCount = {}, 0 end
            linkStats[link] = shipped
            linkStatsCount = linkStatsCount + 1
            return shipped
        end
    end
    if not C_Item.GetItemInfo(link) then return nil end
    local raw = C_Item.GetItemStats(link)
    if not raw then return nil end
    local stats = {}
    for key, value in pairs(raw) do
        local stat = STAT_KEYS[key]
        if stat and type(value) == "number" then
            stats[stat] = (stats[stat] or 0) + value
        end
    end
    ParseTooltipData(C_TooltipInfo.GetHyperlink(link), stats)
    if linkStatsCount > 400 then linkStats, linkStatsCount = {}, 0 end
    linkStats[link] = stats
    linkStatsCount = linkStatsCount + 1
    return stats
end

-- Stats read or looked up earlier in this session (nil when there are none yet).
function Scoring.GetCachedStats(itemID)
    return statCache[itemID]
end

-- The stats the client itself gives for an item it has the data of: its stat table and the "Equip:" lines of its
-- tooltip; empty while the client has not all of the item's data. (/lf collect reads them; at run time they count only
-- for items outside the shipped data.)
function Scoring.ClientStats(itemID)
    local stats = {}
    local link = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
    local raw = C_Item.GetItemStats(link)
    if raw then
        for key, value in pairs(raw) do
            local stat = STAT_KEYS[key]
            if stat and type(value) == "number" then
                stats[stat] = (stats[stat] or 0) + value
            end
        end
    end
    ParseTooltip(itemID, stats)
    return stats
end

-- The stats of an item. An item of the shipped data (Data/ItemStats.lua): its shipped stats, nil when none are known
-- (never asked for). Other items: stats saved in an earlier session until the client has the item, then the client's;
-- nil while its data is not loaded (asked from the server).
function Scoring.GetStats(itemID)
    local cached = statCache[itemID]
    if Items.IsShipped(itemID) then
        if not cached then
            cached = Items.GetShippedStats(itemID)
            statCache[itemID] = cached
        end
        return cached
    end
    local rec = Items.Get(itemID)
    if not rec.loaded then return nil end
    if cached and (liveStats[itemID] or not rec.live) then return cached end
    if not rec.live then
        local saved = Items.GetSavedStats(itemID)
        if saved then
            statCache[itemID] = saved
            return saved
        end
        Items.Request(itemID)
        return nil
    end
    local stats = Scoring.ClientStats(itemID)
    -- no stats at all: the client does not have the item's full data yet (gear without any stat is ranked out
    -- anyway), so nothing is kept and the next call reads again
    if next(stats) == nil then return stats end
    statCache[itemID] = stats
    liveStats[itemID] = true
    Items.SaveStats(itemID, stats)
    return stats
end

---------------------------------------------------------------------------
-- Rating conversion
---------------------------------------------------------------------------
-- Combat rating indices (Forever uses the rating system: GetCombatRatingBonus).
local CR = { HIT_MELEE = 6, HIT_RANGED = 7, HIT_SPELL = 8, CRIT_MELEE = 9, CRIT_RANGED = 10, CRIT_SPELL = 11,
    DODGE = 3, PARRY = 4, BLOCK = 5, HASTE = 18, EXPERTISE = 24 }
Scoring.CR = CR

-- Approximate rating per 1% at level 60 (Forever tooltips: +20 hit ~ 2%, +14 crit ~ 1%).
local RATING_PER_PCT_60 = { HIT_MELEE = 10, HIT_RANGED = 10, HIT_SPELL = 8, CRIT_MELEE = 14, CRIT_RANGED = 14,
    CRIT_SPELL = 14, DODGE = 12, PARRY = 20, BLOCK = 5, HASTE = 10, EXPERTISE = 10 }
Scoring.RATING_PER_PCT_60 = RATING_PER_PCT_60

local function RatingToPct(which, rating, atCurrentLevel)
    if not rating or rating == 0 then return 0 end
    if atCurrentLevel then
        local pct = GetCombatRatingBonusForCombatRatingValue(CR[which], rating)
        if pct > 0 then return pct end
    end
    return rating / RATING_PER_PCT_60[which]
end
Scoring.RatingToPct = RatingToPct

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function W(w, key) return w[key] or 0 end

local SCHOOLS = { "ShadowPower", "FirePower", "FrostPower", "NaturePower", "ArcanePower", "HolyPower" }

-- slotKey decides how weapon DPS counts (MAINHAND/TWOHAND/OFFHAND/RANGED).
-- stats: optional stat table (Scoring.GetStatsForLink), otherwise the item's stats are used.
function Scoring.Score(itemID, spec, slotKey, atCurrentLevel, stats)
    local s = stats or Scoring.GetStats(itemID)
    if not s then return nil end
    local w = LJ.StatPrio.Weights(spec) or {}
    local score = 0

    score = score + (s.Strength or 0) * W(w, "Strength")
    score = score + (s.Agility or 0) * W(w, "Agility")
    score = score + (s.Stamina or 0) * W(w, "Stamina")
    score = score + (s.Intellect or 0) * W(w, "Intellect")
    score = score + (s.Spirit or 0) * W(w, "Spirit")
    score = score + (s.MP5 or 0) * W(w, "MP5")
    score = score + (s.Armor or 0) * W(w, "Armor")
    score = score + (s.Defense or 0) * W(w, "Defense")
    score = score + (s.BlockValue or 0) * W(w, "BlockValue")

    -- Attack power. Hunters value ranged AP; "+Attack Power" also raises ranged AP.
    local apWeight = W(w, "AttackPower")
    local rapWeight = W(w, "RangedAttackPower")
    score = score + (s.AttackPower or 0) * math.max(apWeight, rapWeight)
    score = score + (s.RangedAttackPower or 0) * rapWeight
    if spec.key == "CAT" or spec.key == "BEAR" then
        score = score + (s.FeralAttackPower or 0) * apWeight
    end

    -- Spell power: generic spell power counts for damage and healing. The client also reports the healing part of
    -- a "damage and healing" effect as Healing (equal values on all 335 shipped items that have both), so that
    -- healing is not counted a second time.
    local spWeight = W(w, "SpellPower")
    local healWeight = W(w, "Healing")
    local spellPower, healing = s.SpellPowerAll or 0, s.Healing or 0
    if spellPower > 0 and healing == spellPower then healing = 0 end
    score = score + spellPower * math.max(spWeight, healWeight)
    score = score + (s.SpellDamage or 0) * spWeight
    score = score + healing * healWeight
    for _, school in ipairs(SCHOOLS) do
        score = score + (s[school] or 0) * W(w, school)
    end

    -- Ratings -> percent -> weights (per 1%).
    local hitPct = RatingToPct("HIT_MELEE", (s.HitRating or 0) + (s.MeleeHitRating or 0), atCurrentLevel) + (s.HitPct or 0)
    local rangedHitPct = RatingToPct("HIT_RANGED", s.RangedHitRating, atCurrentLevel)
    local spellHitPct = RatingToPct("HIT_SPELL", (s.HitRating or 0) + (s.SpellHitRating or 0), atCurrentLevel) + (s.SpellHitPct or 0)
    local critPct = RatingToPct("CRIT_MELEE", (s.CritRating or 0) + (s.MeleeCritRating or 0), atCurrentLevel) + (s.CritPct or 0)
    local rangedCritPct = RatingToPct("CRIT_RANGED", s.RangedCritRating, atCurrentLevel)
    local spellCritPct = RatingToPct("CRIT_SPELL", (s.CritRating or 0) + (s.SpellCritRating or 0), atCurrentLevel) + (s.SpellCritPct or 0)
    local isHunter = spec.class == "HUNTER"
    score = score + (hitPct + (isHunter and rangedHitPct or 0)) * W(w, "Hit")
    score = score + (critPct + (isHunter and rangedCritPct or 0)) * W(w, "Crit")
    score = score + spellHitPct * W(w, "SpellHit")
    score = score + spellCritPct * W(w, "SpellCrit")
    score = score + (RatingToPct("DODGE", s.DodgeRating, atCurrentLevel) + (s.DodgePct or 0)) * W(w, "Dodge")
    score = score + (RatingToPct("PARRY", s.ParryRating, atCurrentLevel) + (s.ParryPct or 0)) * W(w, "Parry")
    score = score + (RatingToPct("BLOCK", s.BlockRating, atCurrentLevel) + (s.BlockPct or 0)) * W(w, "Block")

    -- Haste / expertise have no Classic weights: derive conservative values.
    local physicalCrit = math.max(W(w, "Crit"), 0)
    local spellCrit = math.max(W(w, "SpellCrit"), 0)
    local hasteWeight = w.Haste or (0.6 * math.max(physicalCrit, spellCrit))
    score = score + RatingToPct("HASTE", s.HasteRating, atCurrentLevel) * hasteWeight
    local expertiseWeight = w.Expertise or (0.8 * W(w, "Hit"))
    score = score + RatingToPct("EXPERTISE", s.ExpertiseRating, atCurrentLevel) * expertiseWeight
    score = score + (s.WeaponSkill or 0) * 0.2 * W(w, "Hit")

    -- Weapon damage.
    local dps = s.DPS or 0
    if dps > 0 then
        if slotKey == "RANGED" then
            score = score + dps * W(w, "RangedWeaponDPS")
        elseif slotKey == "OFFHAND" then
            score = score + dps * (w.OffHandWeaponDPS or 0.5 * W(w, "WeaponDPS"))
        else
            score = score + dps * W(w, "WeaponDPS")
        end
    end
    return score
end

---------------------------------------------------------------------------
-- Candidate pools and ranking
---------------------------------------------------------------------------
Scoring.SLOTS = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET",
    "FINGER", "TRINKET", "MAINHAND", "OFFHAND", "TWOHAND", "RANGED", "RELIC" }

local EQUIPLOC_SLOTS = {
    INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET", INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_WEAPONOFFHAND = "OFFHAND",
    INVTYPE_SHIELD = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND", INVTYPE_2HWEAPON = "TWOHAND",
    INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED", INVTYPE_RELIC = "RELIC",
}
Scoring.EQUIPLOC_SLOTS = EQUIPLOC_SLOTS

-- Returns the list of slot keys an item can fill for a class (shared lists: callers only read them); level: the level
-- of the character (another class: Dual Wield is learned at a level, Player:CanDualWield).
local SLOT_LIST, DUAL_WIELD, MAIN_HAND, NO_SLOTS = {}, { "MAINHAND", "OFFHAND" }, { "MAINHAND" }, {}
for _, slot in pairs(EQUIPLOC_SLOTS) do SLOT_LIST[slot] = SLOT_LIST[slot] or { slot } end
function Scoring.GetItemSlots(rec, class, level)
    local loc = rec.equipLoc
    if loc == "INVTYPE_WEAPON" then
        if Player:CanDualWield(class, level) then return DUAL_WIELD end
        return MAIN_HAND
    end
    -- off-hand weapons need dual wield
    if loc == "INVTYPE_WEAPONOFFHAND" and not Player:CanDualWield(class, level) then return NO_SLOTS end
    local slot = EQUIPLOC_SLOTS[loc]
    if slot then return SLOT_LIST[slot] end
    return NO_SLOTS
end

-- Every item the journal knows (dungeon + raid loot, trash, the shipped Best in Slot items of Data/BiS.lua).
-- Their data ships with the addon (Data/ItemStats.lua).
function Scoring.GetBaseCandidateIDs()
    if Scoring.baseIDs then return Scoring.baseIDs end
    local seen, list = {}, {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    for _, inst in ipairs(LJ.Data.Instances) do
        for _, boss in ipairs(inst.bosses) do
            for _, id in ipairs(boss.loot) do add(id) end
        end
        for _, id in ipairs(inst.trash or {}) do add(id) end
    end
    for _, specs in pairs(LJ.Data.BiS) do
        for _, spec in ipairs(specs) do
            for _, entries in pairs(spec.slots) do
                for _, e in ipairs(entries) do add(e.id) end
            end
        end
    end
    Scoring.baseIDs, Scoring.baseSet = list, seen
    return list
end

-- The open world's items (the drops of rares and other mobs, random world drops), open world quest rewards, the rewards
-- of the dungeon quests and what the professions make. Which of them a character's list takes, its filter decides
-- (Items.InList).
function Scoring.GetWorldCandidateIDs()
    if Scoring.worldIDs then return Scoring.worldIDs end
    Scoring.GetBaseCandidateIDs()
    local seen, list = {}, {}
    local function add(id)
        if not seen[id] and not Scoring.baseSet[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    for id in pairs(LJ.Data.WorldDrops or {}) do add(id) end
    for _, id in ipairs(Items.GetWorldQuestItemIDs()) do add(id) end
    for id in pairs(LJ.Quests and LJ.Quests.rewardOf or {}) do add(id) end
    for id in pairs(LJ.Data.Crafted) do add(id) end
    table.sort(list)
    Scoring.worldIDs = list
    return list
end

function Scoring.GetAllCandidateIDs()
    if Scoring.allIDs then return Scoring.allIDs end
    local list = {}
    for _, id in ipairs(Scoring.GetBaseCandidateIDs()) do list[#list + 1] = id end
    for _, id in ipairs(Scoring.GetWorldCandidateIDs()) do list[#list + 1] = id end
    Scoring.allIDs = list
    return list
end

-- Developer tool (/lf collect): asks the server once for every open world candidate, so the saved item cache
-- holds their Forever stats. That SavedVariables file is then baked into Data/ItemStats.lua (gen_itemstats.lua)
-- and the items rank from the start without any server request. Only runs when the command is typed.
-- Items new in WoW: Forever have IDs far above the Classic ones (Classic item IDs end below 26000).
local FOREVER_ITEM_MIN = 100000

-- Every new Forever item the addon knows: loot, open world drops, quest items and rewards, BiS entries.
function Scoring.GetForeverItemIDs()
    local seen, list = {}, {}
    local function add(id)
        if type(id) == "number" and id >= FOREVER_ITEM_MIN and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    local D = LJ.Data
    for id in pairs(D.Items or {}) do add(id) end
    for id in pairs(D.WorldDrops or {}) do add(id) end
    for id in pairs(D.WorldQuestItems or {}) do add(id) end
    for id in pairs(D.ItemStats and D.ItemStats.items or {}) do add(id) end
    for _, q in pairs(D.Quests or {}) do
        for _, id in ipairs(q.choice or {}) do add(id) end
        for _, id in ipairs(q.reward or {}) do add(id) end
        for _, it in ipairs(q.items or {}) do add(it.id) end
        if type(q.start) == "table" and q.start.kind == "item" then add(q.start.id) end
    end
    for _, specs in pairs(D.BiS or {}) do
        for _, spec in ipairs(specs) do
            for _, entries in pairs(spec.slots or {}) do
                for _, e in ipairs(entries) do add(e.id) end
            end
        end
    end
    table.sort(list)
    return list
end

-- Every item the addon knows (dungeon loot, Best in Slot lists, open world drops, quest items and rewards, the
-- shipped item data), for /lf collect (Core/Locale.lua).
function Scoring.GetAllItemIDs()
    local seen, list = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    for _, id in ipairs(Scoring.GetBaseCandidateIDs()) do add(id) end
    for _, id in ipairs(Scoring.GetWorldCandidateIDs()) do add(id) end
    for _, id in ipairs(Scoring.GetForeverItemIDs()) do add(id) end
    local D = LJ.Data
    for id in pairs(D.Items or {}) do add(id) end
    for id in pairs(D.WorldDrops or {}) do add(id) end
    for id in pairs(D.WorldQuestItems or {}) do add(id) end
    for id in pairs(D.ItemStats and D.ItemStats.items or {}) do add(id) end
    for _, q in pairs(D.Quests or {}) do
        for _, it in ipairs(q.items or {}) do add(it.id) end
        if type(q.start) == "table" and q.start.kind == "item" then add(q.start.id) end
    end
    table.sort(list)
    return list
end

-- Rankings are kept until something they come from changes: the spec or the character (Scoring.InvalidateCache), an
-- item's levels; one that waited for items without data yet (pending) until item data arrives (ITEMS_UPDATED).
local rankingCache, rankingCount = {}, 0
local RANKINGS_KEPT = 6     -- specs and level options switched between; older rankings are made again

function Scoring.InvalidateCache()
    rankingCache, rankingCount = {}, 0
end

local function ByScore(a, b) return a.score > b.score end

-- Ranks every known item for a spec, grouped by slot: the items its list takes (Items.InList: the sources the player
-- picked) that the character can wear (not the other faction's, on the own class's list none with a profession the
-- character lacks). Kept per list (Items.ListKey) and stat priority (Core/StatPrio.lua): another one is ranked anew.
-- opts.maxLevel limits the items to those usable at that level (Items.GetUseLevel), opts.current uses the
-- rating conversions of the current level.
-- Thousands of candidates are looked at without an item record each: slot and type come from the client
-- (C_Item.GetItemInfoInstant), levels and stats from the shipped or saved data. Only items neither knows (outside the
-- shipped data and not known as without server data) get a record, which asks the server for them.
local facts = {}            -- equipLoc, classID, subclassID of the candidate being ranked (Player:CanClassUse)
local scratchStats = {}     -- shipped stats of that candidate, parsed for its score only
function Scoring.RankAll(spec, opts)
    opts = opts or {}
    local cacheKey = table.concat({ spec.class, spec.key, tostring(opts.maxLevel or 0), tostring(opts.current and 1 or 0),
        Items.ListKey(), LJ.StatPrio.Key(spec) }, ":")
    if rankingCache[cacheKey] then return rankingCache[cacheKey] end
    local started = debugprofilestop()
    local bySlot = {}
    for _, slot in ipairs(Scoring.SLOTS) do bySlot[slot] = {} end
    -- the candidates whose data the game has not sent yet (asked for once: Items.Request)
    local waiting = {}
    local class, maxLevel = spec.class, opts.maxLevel
    local level, own = maxLevel or 60, class == Player.class
    local function Rank(id, world)
        -- an item without server data (the shipped list, or this game version's answers) is not in the game
        if Items.IsKnownMissing(id) then return end
        local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
        if not itemID or not equipLoc or equipLoc == "" then return end   -- not in this client, or not gear
        facts.id, facts.equipLoc, facts.classID, facts.subclassID = id, equipLoc, classID, subclassID
        if not Player:CanClassUse(facts, class, level) then return end
        if Items.IsOtherFaction(id) then return end
        -- the character's own list: not with a profession it lacks (Scoring.MissingSkill)
        if own and Scoring.MissingSkill(id) then return end
        -- only what the list takes (a quest of the other faction or another class gives none)
        if not Items.InList(id, class, level) then return end
        local minLevel, itemLevel = Items.GetKnownLevels(id)
        if not minLevel then
            -- open world items never ask the server: they rank when their data ships with the addon
            -- (Data/ItemStats.lua) or the client already has it; otherwise they are skipped, not pending
            local rec = world and Items.Peek(id) or Items.Get(id)
            if not rec.loaded then
                if not world then waiting[#waiting + 1] = id end
                return
            end
            minLevel, itemLevel = rec.minLevel or 0, rec.itemLevel or 0
        end
        -- ... and only with stats that are known without asking the server
        if world and not Items.HasKnownStats(id) then return end
        if maxLevel and Items.UseLevelFrom(id, minLevel, itemLevel) > maxLevel then return end
        -- stats read this session, then saved or shipped ones; unknown stats come from the client or the server
        local stats = Scoring.GetCachedStats(id) or Items.GetKnownStats(id, scratchStats) or Scoring.GetStats(id)
        if not stats then
            -- (a shipped item without stats has none: it does not rank)
            if not Items.IsShipped(id) then waiting[#waiting + 1] = id end
            return
        end
        for _, slot in ipairs(Scoring.GetItemSlots(facts, class, level)) do
            local score = Scoring.Score(id, spec, slot, opts.current, stats)
            if score and score > 0 then
                local list = bySlot[slot]
                list[#list + 1] = { id = id, score = score }
            end
        end
    end
    for _, id in ipairs(Scoring.GetBaseCandidateIDs()) do Rank(id, false) end
    for _, id in ipairs(Scoring.GetWorldCandidateIDs()) do Rank(id, true) end
    for _, list in pairs(bySlot) do
        table.sort(list, ByScore)
    end
    local result = { bySlot = bySlot, pending = #waiting }
    if rankingCount >= RANKINGS_KEPT then rankingCache, rankingCount = {}, 0 end
    rankingCache[cacheKey] = result
    rankingCount = rankingCount + 1
    -- (/lf debug: a ranking made, and the items it waits for)
    LJ:Debug("ranking %s: %.1f ms, %d items wait for data %s", cacheKey, debugprofilestop() - started, #waiting,
        table.concat(waiting, ", ", 1, math.min(#waiting, 8)))
    return result
end

-- New item data: the rankings that waited for items are made again with them.
LJ:Listen("ITEMS_UPDATED", function()
    for key, r in pairs(rankingCache) do
        if r.pending > 0 then
            rankingCache[key] = nil
            rankingCount = rankingCount - 1
        end
    end
end)

-- The score of the item worn in an equipment slot, from its link (random suffixes count): score, item ID, link; 0
-- for an empty slot. The score is nil while the game has no data for the worn item yet (no link, no stats of it): the
-- game is asked for it (ITEMS_UPDATED follows).
local function EquippedScore(slotID, spec, slotKey, current)
    local itemID = Player:GetEquippedItemID(slotID)
    if not itemID then return 0, nil end
    local link = Player:GetEquippedLink(slotID)
    local stats = link and Scoring.GetStatsForLink(link)
    if not stats then
        Items.Request(itemID)
        return nil, itemID, link
    end
    return Scoring.Score(itemID, spec, slotKey, current, stats), itemID, link
end
Scoring.EquippedScore = EquippedScore

-- The score of what is worn where an item of a slot goes (the lower one of two ring or trinket slots): score, item ID,
-- link; the score is nil while the game has no data for an item worn there yet (EquippedScore).
function Scoring.GetEquippedScore(spec, slot, current)
    if slot == "TWOHAND" then
        local mhScore, mh, mhLink = EquippedScore(16, spec, "MAINHAND", current)
        local ohScore, oh, ohLink = EquippedScore(17, spec, "OFFHAND", current)
        if not (mhScore and ohScore) then return nil, mh or oh, mhLink or ohLink end
        return mhScore + ohScore, mh or oh, mhLink or ohLink
    end
    local ids = Player.SLOT_IDS[slot]
    if not ids then return 0, nil end
    -- an off hand next to a worn two-hander replaces the two-hander (its own slot is empty, not free)
    if slot == "OFFHAND" and not Player:GetEquippedItemID(17) then
        local mainHand = Player:GetEquippedItemID(16)
        local mainLoc = mainHand and select(4, C_Item.GetItemInfoInstant(mainHand))
        if mainLoc == "INVTYPE_2HWEAPON" then return EquippedScore(16, spec, "TWOHAND", current) end
    end
    local lowest, lowestID, lowestLink
    for _, slotID in ipairs(ids) do
        local score, itemID, link = EquippedScore(slotID, spec, slot, current)
        if not score then return nil, itemID, link end
        if not lowest or score < lowest then
            lowest, lowestID, lowestLink = score, itemID, link
        end
    end
    return lowest or 0, lowestID, lowestLink
end

-- The profession an item asks for (Data/ItemStats.lua) when the character does not have it at that rank:
-- "Requires Engineering (245)" with the profession's name (Data.Professions, translated by the language data); nil
-- when it asks for none or the character has it.
function Scoring.MissingSkill(itemID)
    local line, rank = Items.GetSkill(itemID)
    if not line or (Player:ProfessionRank(line) or 0) >= rank then return nil end
    return LJ.F("Requires %s (%d)", assert(LJ.Data.Professions[line], "no name for profession " .. line), rank)
end

-- stats looked up for the items the window showed (the item records go at the same time, Items.lua)
LJ:Listen("WINDOW_CLOSED", function() statCache, liveStats = {}, {} end)

LJ:Listen("SPEC_CHANGED", Scoring.InvalidateCache)
LJ:Listen("PLAYER_CHANGED", Scoring.InvalidateCache)
