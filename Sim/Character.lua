-- Lootified - the character the simulator fights with, read from the game right now: the weapons (damage and speed
-- from their tooltips; a druid in Cat Form fights with its paws), attack power, crit, hit, spell power and spell crit
-- of every school, mana, rage or energy and the character sheet's damage modifiers; the best rank of every ability
-- the class model uses, with the numbers of the spell's own description, its cost, cast time and cooldown as the game
-- states them; the talents, found by their spell; the poisons and imbues on the weapons; the pet that is out.
-- Character.WithItem puts on another item: its stats change the numbers the way the game converts them (Strength
-- and Agility to attack power, Agility and Intellect to crit, ratings to percent ...; the talents that raise a stat by
-- a percent raise the item's too). The buffs on the character count.
local _, LJ = ...

local Sim = LJ.Sim
local Character = {}
Sim.Character = Character

local max = math.max

local STR, AGI, INT = 1, 2, 4   -- LE_UNIT_STAT_*
local MANA_PER_INT = 15
-- the shield's block value per point of Strength (the Forever client's character sheet,
-- Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua)
local BLOCK_VALUE_PER_STRENGTH = 20
local SHIELD_CLASS, SHIELD_SUBCLASS = 4, 6   -- Enum.ItemClass.Armor, Enum.ItemArmorSubclass.Shield
local CAT_FORM = 1              -- GetShapeshiftFormID() in Cat Form
-- the druid's forms with paws (GetShapeshiftFormID(): Cat Form, Bear Form, Dire Bear Form; CMaNGOS spell_template 768,
-- 5487, 9634)
local PAWS = { [CAT_FORM] = true, [5] = true, [8] = true }
-- combat ratings (CR_HIT_* of Blizzard's paper doll, which may not be loaded yet)
local CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL = 6, 7, 8
-- the spell schools by their index in GetSpellBonusDamage / GetSpellCritChance, and their item stat
local SCHOOLS = {
    { "holy", 2, "HolyPower" }, { "fire", 3, "FirePower" }, { "nature", 4, "NaturePower" },
    { "frost", 5, "FrostPower" }, { "shadow", 6, "ShadowPower" }, { "arcane", 7, "ArcanePower" },
}

local SLOT_MH, SLOT_OH, SLOT_RANGED = 16, 17, 18
local HAND_OF_SLOT = { [SLOT_MH] = "mh", [SLOT_OH] = "oh", [SLOT_RANGED] = "ranged" }
local HANDS = { "mh", "oh", "ranged" }
Character.HAND_OF_SLOT = HAND_OF_SLOT
-- The equipment slots whose items count (shirt and tabard have no stats).
Character.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, SLOT_MH, SLOT_OH, SLOT_RANGED }

-- Weapon subclass -> weapon skill line (Forever's skills panel, Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua)
local SKILL_LINE = {
    [0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229, [7] = 43, [8] = 55, [10] = 136,
    [13] = 162, [15] = 173, [16] = 176, [18] = 226, [19] = 228,
}
-- Normalized weapon speeds (abilities with "normalized weapon damage"): daggers 1.7, other one-handers 2.4,
-- two-handers 3.3, ranged 2.8.
local function NormSpeed(subclass, twoHand, ranged)
    if ranged then return 2.8 end
    if subclass == 15 then return 1.7 end
    return twoHand and 3.3 or 2.4
end

---------------------------------------------------------------------------
-- The numbers of a game text by kind: percentages ("25%", "20 %"), times in seconds ("9 sec", "9 Sek.", "9 сек.",
-- minutes too: "2 min" is 120) and the plain ones, each in their order. Languages order a sentence differently ("bleed for 15 damage over 9 sec" /
-- "im Verlauf von 9 Sek. 15 Schaden"); the kinds stay. Decimal points and commas both count ("2,5" in German); "1,234"
-- or "1.234" (three digits after it) are thousands.
---------------------------------------------------------------------------
local function TimeUnit(format)
    return ((format:gsub("%%d", "")):match("^%s*(.-)%s*$"):gsub("%.$", ""))
end
local SEC = TimeUnit(INT_SPELL_DURATION_SEC)
local MIN = TimeUnit(INT_SPELL_DURATION_MIN)

function Character.Parse(text)
    assert(type(text) == "string", "game text expected")
    -- color codes out; a grammar escape ("2 |4hour:hrs;") its plural word
    text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|4[^:;]*:([^;]*);", "%1")
    local p = { all = {}, pct = {}, time = {}, plain = {} }
    local pos = 1
    while true do
        local s, e = text:find("%d[%d%.,]*", pos)
        if not s then break end
        local token = text:sub(s, e):gsub("[%.,]+$", "")
        local whole, frac = token:match("^(%d+)[%.,](%d+)$")
        local value
        if whole and #frac == 3 then
            value = tonumber(whole .. frac)
        elseif whole then
            value = tonumber(whole .. "." .. frac)
        else
            value = tonumber((token:gsub("[%.,]", "")))
        end
        local after = text:sub(e + 1, e + 12):match("^%s*(.*)")
        local kind = "plain"
        if after:sub(1, 1) == "%" then
            kind = "pct"
        elseif after:find(SEC, 1, true) == 1 then
            kind = "time"
        elseif after:find(MIN, 1, true) == 1 then
            kind, value = "time", value * 60
        end
        p.all[#p.all + 1] = value
        p[kind][#p[kind] + 1] = value
        pos = e + 1
    end
    return p
end

-- A number of a talent's description: kind "pct", "time" or "plain" (Character.Parse), the i-th of that kind; 0
-- without the talent.
function Sim.Talent(c, key, kind, i)
    local t = c.talents[key]
    return t and t.p[kind][i or 1] or 0
end

-- The middle of a damage range in a description: the i-th plain number and the next ("397 to 505").
function Sim.Average(p, i)
    return (p.plain[i] + (p.plain[i + 1] or p.plain[i])) / 2
end

-- The per-combo-point lines of a finisher ("1 point : 93-137 damage", "1 point : 159 damage over 8 secs", "1 point :
-- 9 seconds"): [cp] = { numbers of that line }, from the last lines of the description (every line starts with its
-- number of points; kind "time": the line's time).
function Sim.PerPoint(spell, kind, count)
    local p = spell.p
    local per = {}
    if kind == "time" then
        assert(#p.time >= 5, spell.name .. ": unexpected description")
        for cp = 1, 5 do per[cp] = { p.time[#p.time - 5 + cp] } end
        return per
    end
    local step = count + 1
    local first = #p.plain - 5 * step + 1
    for cp = 1, 5 do
        local at = first + (cp - 1) * step
        assert(at >= 1 and p.plain[at] == cp, spell.name .. ": unexpected description")
        per[cp] = { unpack(p.plain, at + 1, at + count) }
    end
    return per
end
-- The share of spell power a spell learned before level 20 gets (CMaNGOS: 3.75 % less per level below 20).
function Sim.LevelPenalty(spell)
    local level = spell.level or 0
    if level <= 0 or level >= 20 then return 1 end
    return 1 - (20 - level) * 0.0375
end

-- The shares of spell power a spell's damage gets in the game's own tables, the rank the character has
-- (Data/SpellPower.lua): direct, per tick; each with Sim.LevelPenalty. Errors for a spell the tables give no damage.
function Sim.SpellPower(spell)
    local share = LJ.Data.SpellPower[spell.id]
    assert(share, spell.name .. ": no spell power share in the game's tables")
    local penalty = Sim.LevelPenalty(spell)
    return share[1] * penalty, share[2] * penalty
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------
-- Damage range and speed from a weapon's tooltip lines: the line with "min - max" on the left and the speed on the
-- right ("13 - 25 Damage" / "Speed 2.60", "Tempo 2,60", "Скорость 2,60").
function Character.WeaponFromTooltip(data)
    for _, line in ipairs(data and data.lines or {}) do
        local left, right = line.leftText, line.rightText
        if type(left) == "string" and type(right) == "string" then
            local lo, hi = left:match("(%d+)%s*%-%s*(%d+)")
            local speed = right:match("(%d+[%.,]%d+)")
            if lo and speed then
                return tonumber(lo), tonumber(hi), tonumber((speed:gsub(",", ".")))
            end
        end
    end
    return nil
end

-- The skill lines of the character: [skill line] = { rank, modifier } (the skill panel's numbers).
function Character.WeaponSkills()
    local skills = {}
    for i = 1, C_SkillInfo.GetNumSkillLines() do
        local info = C_SkillInfo.GetSkillLineInfo(i)
        if info and not info.isHeader and info.skillID then
            skills[info.skillID] = { rank = info.rank, modifier = info.modifier }
        end
    end
    return skills
end

-- The character's skill with weapons of a subclass: its rank (0: not learned), the level's maximum (5 x level) and
-- the skill the simulator counts: as if trained to that maximum (plus the skill panel's bonus, e.g. a race's), so that
-- it compares items, not how far a weapon skill is trained (a rank of 0 played as 0 missed almost every swing).
-- skills: Character.WeaponSkills(). A subclass without a skill line counts as trained.
function Character.WeaponSkill(subclass, skills, level)
    local top = level * 5
    local line = SKILL_LINE[subclass]
    if not line then return top, top, top end
    local own = skills[line]
    local rank = own and own.rank or 0
    return rank, top, max(rank, top) + (own and own.modifier or 0)
end

-- A weapon: { id, min, max, speed (its own), swing (seconds between swings), normSpeed, subclass, twoHand, skill (the
-- one the simulator counts: Character.WeaponSkill) }. lo, hi, speed: its damage and speed (an equipped weapon's
-- tooltip, the shipped data of another), haste: the character's attack speed factor.
function Character.Weapon(itemID, lo, hi, speed, skills, level, haste, ranged)
    local _, _, _, equipLoc, _, _, subclass = C_Item.GetItemInfoInstant(itemID)
    local twoHand = equipLoc == "INVTYPE_2HWEAPON"
    local _, _, skill = Character.WeaponSkill(subclass, skills, level)
    return {
        id = itemID, min = lo, max = hi, speed = speed, swing = speed / haste,
        normSpeed = NormSpeed(subclass, twoHand, ranged), subclass = subclass, twoHand = twoHand, skill = skill,
    }
end

-- A druid's paws in Cat or Bear Form (the weapon does not count there): the character sheet's damage without attack
-- power and its flat bonus, the attack speed of the form, the skill of the level.
local function Paws(c)
    local lo, hi, _, _, bonusPos, bonusNeg, percent = UnitDamage("player")
    local speed = UnitAttackSpeed("player")
    local bonus = (bonusPos or 0) + (bonusNeg or 0)
    local fromAp = c.ap / 14 * speed
    return { min = lo / percent - fromAp - bonus, max = hi / percent - fromAp - bonus, speed = speed, swing = speed,
        normSpeed = speed, skill = c.level * 5, basePct = percent, bonus = bonus, paws = true }
end

---------------------------------------------------------------------------
-- Spells and talents
---------------------------------------------------------------------------
-- A spell book: [spell name] = { id, level, passive, line } of the best rank (the entry that is not a lower rank). The
-- character's (bank Player) has only learned spells: the book also lists the spells the character learns later and
-- those of other specs (learned = a spell, not of another spec: Blizzard_PlayerSpellsFrame.lua); line: its skill line
-- (Enum.SpellBookSkillLineIndex: General first); the pet's (bank Pet) its abilities.
function Character.SpellBook(bank)
    local book = {}
    local function Add(slot, line)
        local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if info and info.itemType == Enum.SpellBookItemType.Spell and not info.isOffSpec and info.spellID
            and not C_SpellBook.IsSpellBookItemLowRank(slot, bank) then
            book[info.name] = { id = info.spellID, level = C_SpellBook.GetSpellBookItemLevelLearned(slot, bank),
                passive = info.isPassive, line = line }
        end
    end
    if bank == Enum.SpellBookSpellBank.Pet then
        for slot = 1, C_SpellBook.HasPetSpells() or 0 do Add(slot) end
        return book
    end
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do Add(slot, i) end
    end
    return book
end

-- The number of a tooltip text written with a game format ("%.2g sec cooldown"), nil when it is not that text.
local function FormatPattern(format)
    local before, after = format:match("^(.-)%%[%d%.]*g(.*)$")
    assert(before, "unexpected number format: " .. format)
    local function Esc(s) return (s:gsub("[%%%(%)%.%[%]%*%+%-%?%^%$]", "%%%0")) end
    return "^" .. Esc(before) .. "([%d%.,]+)" .. Esc(after) .. "$"
end
local COOLDOWN_SEC, COOLDOWN_MIN = FormatPattern(SPELL_RECAST_TIME_SEC), FormatPattern(SPELL_RECAST_TIME_MIN)

-- The cooldown (s) and whether it is channeled, from a spell's tooltip ("8 sec cooldown", "Channeled").
local function TooltipTimes(id)
    local cooldown, channel = 0, false
    local data = C_TooltipInfo.GetSpellByID(id)
    for _, line in ipairs(data and data.lines or {}) do
        for _, text in ipairs({ line.leftText, line.rightText }) do
            if type(text) == "string" then
                local sec, min = text:match(COOLDOWN_SEC), text:match(COOLDOWN_MIN)
                if sec then cooldown = tonumber((sec:gsub(",", "."))) end
                if min then cooldown = tonumber((min:gsub(",", "."))) * 60 end
                if text == SPELL_CAST_CHANNELED then channel = true end
            end
        end
    end
    return cooldown, channel
end

local POWERS = { [Enum.PowerType.Mana] = "mana", [Enum.PowerType.Rage] = "rage", [Enum.PowerType.Energy] = "energy",
    [Enum.PowerType.Focus] = "focus" }

-- An ability of the character (or its pet): { id, key, name, level (learned at), passive, p (the numbers of its
-- description, Character.Parse), text, power ("mana", "rage", "energy", "focus"), cost, cast (s), cooldown (s), channel }, nil when
-- the book does not have it. anyRank: a spell ID of any rank (the name decides, the spell book the rank). Cost, cast
-- time and cooldown are the game's, with the talents that change them.
function Character.Spell(book, anyRank, key)
    local name = C_Spell.GetSpellName(anyRank)
    local entry = name and book[name]
    if not entry then return nil end
    local id = entry.id
    local text = C_Spell.GetSpellDescription(id)
    if text == "" then
        -- the game has not loaded the spell's text yet: asked for, the next try has it
        C_Spell.RequestLoadSpellData(id)
        error("spell texts loading", 0)
    end
    local cost, power = 0, nil
    for _, c in ipairs(C_Spell.GetSpellPowerCost(id) or {}) do
        -- combo points are no cost
        if POWERS[c.type] then cost, power = c.cost, POWERS[c.type] end
    end
    local info = C_Spell.GetSpellInfo(id)
    local cooldown, channel = TooltipTimes(id)
    return { id = id, key = key, name = name, level = entry.level, passive = entry.passive, p = Character.Parse(text),
        text = text, power = power, cost = cost, cast = max(0, info.castTime / 1000), cooldown = cooldown, channel = channel }
end

-- A spell's description (a poison's, an imbue's ...): { id, name, text, p (Character.Parse) }; errors while the game
-- loads it.
function Character.Describe(id)
    local text = C_Spell.GetSpellDescription(id)
    if text == "" then
        C_Spell.RequestLoadSpellData(id)
        error("spell texts loading", 0)
    end
    return { id = id, name = C_Spell.GetSpellName(id), text = text, p = Character.Parse(text) }
end

-- The talents of the character: the ones the model knows, [key] = { rank, max, p (the numbers of the description at
-- that rank, Character.Parse) }, and every talent with points, { { name, rank, max, key (the model's, nil when the
-- model does not play it), id (its spell) } } (no talent tree: none). known = { [key] = spell ID }: a talent is found
-- by its spell, or by that spell's name (the game names both alike).
function Character.Talents(known)
    local talents, list = {}, {}
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    if not config then return talents, list end
    local byID, byName = {}, {}
    for key, id in pairs(known) do
        byID[id] = key
        local name = C_Spell.GetSpellName(id)
        if name then byName[name] = key end
    end
    for _, treeID in ipairs(config.treeIDs or {}) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            local rank = node and node.activeRank or 0
            if rank > 0 and node.activeEntry then
                local entryID = node.activeEntry.entryID
                local entry = C_Traits.GetEntryInfo(configID, entryID)
                local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                local spellID = def and def.spellID
                local name = spellID and C_Spell.GetSpellName(spellID)
                local key = spellID and (byID[spellID] or byName[name or ""])
                if name then list[#list + 1] = { name = name, rank = rank, max = node.maxRanks, key = key, id = spellID } end
                if key then
                    -- the entry's own rank, as the game's talent tooltip reads it (a tiered node's ranks are spread
                    -- over several entries: Blizzard_TalentDisplay.lua)
                    local text = C_Traits.GetTraitDescription(entryID, node.activeEntry.rank)
                    assert(type(text) == "string" and text ~= "", "no description for talent " .. key)
                    talents[key] = { rank = rank, max = node.maxRanks, p = Character.Parse(text) }
                end
            end
        end
    end
    return talents, list
end

-- What the simulator does with a class spell or talent no class model plays (Data/SimInventory.lua; the kinds:
-- pipeline/sim_inventory.py), nil when the inventory does not know it.
function Character.InventoryKind(class, id)
    return LJ.Data.SimInventory[class][id]
end

-- The kinds the window names as not simmed (the game's own numbers carry the others, or they do no damage), "new": a
-- class spell or talent the inventory does not know, and "tank": one only the class's tank spec plays.
Character.NOT_SIMMED = { aoe = true, type = true, chance = true, attacked = true, kill = true, later = true, new = true,
    tank = true }

-- What the character playing a spec (specKey) has learned that the simulator does not play, each once: { { name, kind }
-- } by name. book: the player's Character.SpellBook, talents: Character.Talents' list. A spell of the General line the
-- inventory does not know (racials, languages ...) is left out; the spells and talents only the model's tank spec plays
-- (model.tankSpells, model.tankSpec) are "tank" for its other specs.
function Character.NotSimmed(model, class, book, talents, specKey)
    -- the model's spells and talents (a talent's spell is in the book too: Shadowform)
    local tankOnly = model.tankSpec and specKey ~= model.tankSpec and model.tankSpells or {}
    local played, tank = {}, {}
    for _, ids in ipairs({ model.spells, model.talents }) do
        for key, id in pairs(ids) do
            local name = C_Spell.GetSpellName(id)
            if name then
                if tankOnly[key] then tank[name] = true else played[name] = true end
            end
        end
    end
    local list, seen = {}, {}
    local function Add(name, kind)
        if Character.NOT_SIMMED[kind] and not seen[name] then
            seen[name] = true
            list[#list + 1] = { name = name, kind = kind }
        end
    end
    for name, entry in pairs(book) do
        if not played[name] then
            local new = entry.line ~= Enum.SpellBookSkillLineIndex.General and "new" or nil
            Add(name, tank[name] and "tank" or Character.InventoryKind(class, entry.id) or new)
        end
    end
    for _, t in ipairs(talents) do
        if (not t.key or tankOnly[t.key]) and not played[t.name] then
            Add(t.name, tank[t.name] and "tank" or Character.InventoryKind(class, t.id) or "new")
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------------
-- The character
---------------------------------------------------------------------------
-- True for a shield (an item ID; nil: none).
function Character.IsShield(itemID)
    if not itemID then return false end
    local classID, subclassID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == SHIELD_CLASS and subclassID == SHIELD_SUBCLASS
end

local function Effective(unit, stat)
    local _, value = UnitStat(unit, stat)
    return value
end

local function Sum3(a, b, c) return (a or 0) + (b or 0) + (c or 0) end

local NO_MODS = { pct = 1, crit = 0, armorIgnore = 0 }
local function WeaponMods(model, c, w, hand)
    return model.WeaponMods and model.WeaponMods(c, w, hand) or NO_MODS
end

-- Reads the character for a class model (model.spells, model.talents, model.WeaponMods, model.Setup) playing the
-- spec specKey (a key of model.specs): what the game gives (Character.ReadRaw), then Character.Finish. Errors when the
-- game does not give what the simulator needs.
function Character.Read(model, specKey)
    return Character.Finish(Character.ReadRaw(model, specKey), model)
end

-- The last steps of Character.Read: the weapon-type talents of the weapons in hand and the model's Setup (its
-- abilities: c.ab). Lootified's web simulator runs them on the character of /lf export.
function Character.Finish(c, model)
    Character.ApplyWeaponMods(c, model)
    model.Setup(c)
    return c
end

-- The character as the game gives it, before Character.Finish (what /lf export carries: Sim/Export.lua).
function Character.ReadRaw(model, specKey)
    assert(model.specs[specKey], "unknown spec")
    assert(not UnitAffectingCombat("player"), "in combat")
    local level = UnitLevel("player")
    local power = UnitPowerType("player")
    local rage, energy = power == Enum.PowerType.Rage, power == Enum.PowerType.Energy
    local c = {
        class = select(2, UnitClass("player")), spec = specKey, level = level, items = {},
        str = Effective("player", STR), agi = Effective("player", AGI), int = Effective("player", INT),
        ap = Sum3(UnitAttackPower("player")), rap = Sum3(UnitRangedAttackPower("player")),
        crit = GetCritChance(), rangedCrit = GetRangedCritChance(),
        hit = GetCombatRatingBonus(CR_HIT_MELEE) + GetHitModifier(),
        rangedHit = GetCombatRatingBonus(CR_HIT_RANGED) + GetRangedHitModifier(),
        spellHit = GetCombatRatingBonus(CR_HIT_SPELL) + GetSpellHitModifier(),
        sp = {}, spellCrit = {},
        -- a druid in a form keeps its mana (Shifting Power spends it)
        manaMax = UnitPowerMax("player", Enum.PowerType.Mana),
        rageMax = rage and UnitPowerMax("player", Enum.PowerType.Rage) or 0,
        energyMax = energy and UnitPowerMax("player", Enum.PowerType.Energy) or 0,
        form = GetShapeshiftFormID(),
    }
    for _, s in ipairs(SCHOOLS) do
        c.sp[s[1]], c.spellCrit[s[1]] = GetSpellBonusDamage(s[2]), GetSpellCritChance(s[2])
    end
    c.mana = c.manaMax
    c.manaRegen, c.manaRegenCasting = GetManaRegen()
    for _, slot in ipairs(Character.SLOTS) do c.items[slot] = GetInventoryItemID("player", slot) end
    -- the shield and its block value (Shield Slam's damage grows with it)
    c.shield = Character.IsShield(c.items[SLOT_OH])
    c.blockValue = GetShieldBlock()

    local skills = Character.WeaponSkills()
    local mhSpeed, ohSpeed = UnitAttackSpeed("player")
    local _, _, _, _, bonusPos, bonusNeg, percent = UnitDamage("player")
    local function Melee(slot, speedNow)
        local lo, hi, speed = Character.WeaponFromTooltip(C_TooltipInfo.GetInventoryItem("player", slot))
        if not speed then return nil end
        local w = Character.Weapon(c.items[slot], lo, hi, speed, skills, level, speed / speedNow)
        w.basePct, w.bonus = percent, (bonusPos or 0) + (bonusNeg or 0)
        return w
    end
    if PAWS[c.form] then
        c.mh = Paws(c)
    else
        c.mh = c.items[SLOT_MH] and Melee(SLOT_MH, mhSpeed)
        c.oh = c.items[SLOT_OH] and ohSpeed and Melee(SLOT_OH, ohSpeed) or nil
    end
    c.ammoDps = 0
    if c.items[SLOT_RANGED] then
        local lo, hi, speed = Character.WeaponFromTooltip(C_TooltipInfo.GetInventoryItem("player", SLOT_RANGED))
        if speed then
            local rSpeed, rMin, _, rPos, rNeg, rPercent = UnitRangedDamage("player")
            local w = Character.Weapon(c.items[SLOT_RANGED], lo, hi, speed, skills, level, speed / rSpeed, true)
            w.basePct, w.bonus = rPercent, (rPos or 0) + (rNeg or 0)
            -- the ammunition: what the character sheet's damage has beyond weapon and attack power, per second
            local ammo = rMin / rPercent - w.bonus - w.min - c.rap / 14 * w.speed
            assert(ammo > -1, "the ranged damage of the character sheet is lower than the weapon's")
            c.ammoDps = max(0, ammo) / w.speed
            w.bonus = w.bonus + c.ammoDps * w.speed
            c.ranged = w
        end
    end
    -- poisons and imbues: the enchantments on each weapon ({ SpellItemEnchantment IDs })
    c.enchants = {}
    for hand, slot in pairs({ mh = Enum.WeaponSlot.MainHand, oh = Enum.WeaponSlot.OffHand }) do
        local list = {}
        for _, e in ipairs(C_Item.GetWeaponEnchantInfo(slot)) do
            if e.hasEnchant then list[#list + 1] = e.enchantID end
        end
        c.enchants[hand] = list
    end

    local book = Character.SpellBook(Enum.SpellBookSpellBank.Player)
    c.spells = {}
    for key, id in pairs(model.spells) do c.spells[key] = Character.Spell(book, id, key) end
    c.talents, c.talentList = Character.Talents(model.talents)
    c.notSimmed = Character.NotSimmed(model, c.class, book, c.talentList, specKey)
    c.petOut = UnitExists("pet")
    if model.petSpells and c.petOut then c.pet = Sim.Pet.Read(model) end
    -- the weapon-type talents (two-hand specialization, Weaponmaster ...) are in the character sheet's numbers for the
    -- equipped weapons: taken out once, so that every weapon gets its own
    for _, hand in ipairs(HANDS) do
        local w = c[hand]
        if w and not w.paws then
            local mods = WeaponMods(model, c, w, hand)
            w.basePct = w.basePct / mods.pct
            if hand == "mh" then c.crit = c.crit - mods.crit end
            if hand == "ranged" then c.rangedCrit = c.rangedCrit - mods.crit end
        end
    end
    return c
end

-- The weapon hand a character fights with ("mh" | "ranged"; nil: none, as casters and a druid in Cat Form with its
-- paws): the model's Setup needs it.
function Character.FightingHand(char, model)
    local hand = (char.hands or model.hands)[1]
    if hand == "mh" and char.mh and char.mh.paws then return nil end
    return hand
end

-- The weapon-type talents of the weapons in hand: model.WeaponMods(c, weapon, hand) = { pct, crit, armorIgnore, hit }
-- (none without). The weapons are copied (a character made from another one shares its tables).
function Character.ApplyWeaponMods(c, model)
    c.armorIgnore = 0
    for _, hand in ipairs(HANDS) do
        if c[hand] then
            local w = {}
            for k, v in pairs(c[hand]) do w[k] = v end
            local mods = w.paws and NO_MODS or WeaponMods(model, c, w, hand)
            w.pct, w.critBonus, w.hitBonus = w.basePct * mods.pct, mods.crit, mods.hit
            if hand == "mh" then c.armorIgnore = mods.armorIgnore end
            c[hand] = w
        end
    end
end

---------------------------------------------------------------------------
-- Other gear and more stats
---------------------------------------------------------------------------
local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function RatingToPct(which, rating) return LJ.Scoring.RatingToPct(which, rating, true) end

-- The item stats Character.WithStats reads: an item with none of them (and no weapon damage) cannot change the damage.
local COUNTED = {
    Strength = true, Agility = true, Intellect = true, AttackPower = true, FeralAttackPower = true,
    RangedAttackPower = true, CritPct = true, CritRating = true, MeleeCritRating = true, RangedCritRating = true,
    HitPct = true, HitRating = true, MeleeHitRating = true, RangedHitRating = true, SpellHitPct = true,
    SpellHitRating = true, SpellCritPct = true, SpellCritRating = true, SpellPowerAll = true, SpellDamage = true,
    MP5 = true,
}
for _, s in ipairs(SCHOOLS) do COUNTED[s[3]] = true end

-- True when an item's stats have one the simulator counts.
function Character.Counts(stats)
    for key, value in pairs(stats) do
        if COUNTED[key] and value ~= 0 then return true end
    end
    return false
end

-- A model without talents that raise a stat by a percent (model.StatMods).
local NO_STAT_MODS = { str = 1, agi = 1, int = 1 }

-- The character with more (or less) stats: delta = item stats (Scoring.GetStats keys). The item's Strength, Agility and
-- Intellect count with the talents that raise a stat by a percent (aura 137 MOD_TOTAL_STAT_PERCENTAGE: the character
-- sheet's stats have them; model.StatMods(c) = { str, agi, int } factors), and so do the attack power, crit and mana
-- from them; the buffs that do it (Blessing of Kings) are not read.
function Character.WithStats(char, delta, model)
    local c = Copy(char)
    c.sp, c.spellCrit = Copy(char.sp), Copy(char.spellCrit)
    local function D(key) return delta[key] or 0 end
    local mods = model.StatMods and model.StatMods(char) or NO_STAT_MODS
    local str, agi, int = D("Strength") * mods.str, D("Agility") * mods.agi, D("Intellect") * mods.int
    c.str, c.agi, c.int = c.str + str, c.agi + agi, c.int + int
    local apStats = (GetAttackPowerForStat(STR, c.str) - GetAttackPowerForStat(STR, char.str))
        + (GetAttackPowerForStat(AGI, c.agi) - GetAttackPowerForStat(AGI, char.agi))
    c.ap = c.ap + D("AttackPower") + apStats + (PAWS[c.form] and D("FeralAttackPower") or 0)
    c.rap = c.rap + D("AttackPower") + D("RangedAttackPower")
        + (GetRangedAttackPowerForStat(AGI, c.agi) - GetRangedAttackPowerForStat(AGI, char.agi))
    local agiCrit = (GetCritChanceFromStat(AGI, c.agi) - GetCritChanceFromStat(AGI, char.agi)) * 100
    c.crit = c.crit + D("CritPct") + agiCrit + RatingToPct("CRIT_MELEE", D("CritRating") + D("MeleeCritRating"))
    c.rangedCrit = c.rangedCrit + D("CritPct") + agiCrit
        + RatingToPct("CRIT_RANGED", D("CritRating") + D("RangedCritRating"))
    c.hit = c.hit + D("HitPct") + RatingToPct("HIT_MELEE", D("HitRating") + D("MeleeHitRating"))
    c.rangedHit = c.rangedHit + D("HitPct") + RatingToPct("HIT_RANGED", D("HitRating") + D("RangedHitRating"))
    c.spellHit = c.spellHit + D("SpellHitPct") + RatingToPct("HIT_SPELL", D("HitRating") + D("SpellHitRating"))
    local spellCrit = D("SpellCritPct") + RatingToPct("CRIT_SPELL", D("CritRating") + D("SpellCritRating"))
        + (GetSpellCritChanceFromStat(INT, c.int) - GetSpellCritChanceFromStat(INT, char.int)) * 100
    for _, s in ipairs(SCHOOLS) do
        c.sp[s[1]] = c.sp[s[1]] + D("SpellPowerAll") + D("SpellDamage") + D(s[3])
        c.spellCrit[s[1]] = c.spellCrit[s[1]] + spellCrit
    end
    -- the shield's block value: its own, and Strength's
    if c.shield then
        c.blockValue = c.blockValue + D("BlockValue")
            + math.floor(c.str / BLOCK_VALUE_PER_STRENGTH) - math.floor(char.str / BLOCK_VALUE_PER_STRENGTH)
    end
    if c.manaMax > 0 then
        c.manaMax = c.manaMax + int * MANA_PER_INT
        c.mana = c.manaMax
        -- mana per 5 seconds counts while casting too
        c.manaRegen, c.manaRegenCasting = c.manaRegen + D("MP5") / 5, c.manaRegenCasting + D("MP5") / 5
    end
    if model.WithIntellect then model.WithIntellect(c, int) end
    return c
end

-- What Character.WithStats asks the game, for /lf export (the web has no game to ask): each conversion of Strength,
-- Agility and Intellect as { at the character's stat, at 100 more } (the web takes the slope), and the percent that
-- 100 rating of each kind gives at the character's level (ratings; 0: the game has none, Scoring.RatingToPct then
-- counts Scoring.RATING_PER_PCT_60).
function Character.Conversions(c)
    local function At(fn, stat, value) return { fn(stat, value), fn(stat, value + 100) } end
    local ratings = {}
    for _, kind in ipairs({ "CRIT_MELEE", "CRIT_RANGED", "HIT_MELEE", "HIT_RANGED", "HIT_SPELL", "CRIT_SPELL" }) do
        ratings[kind] = GetCombatRatingBonusForCombatRatingValue(LJ.Scoring.CR[kind], 100)
    end
    return {
        apStr = At(GetAttackPowerForStat, STR, c.str), apAgi = At(GetAttackPowerForStat, AGI, c.agi),
        rapAgi = At(GetRangedAttackPowerForStat, AGI, c.agi), critAgi = At(GetCritChanceFromStat, AGI, c.agi),
        spellCritInt = At(GetSpellCritChanceFromStat, INT, c.int), ratings = ratings,
    }
end

-- Stops a sim that swaps items without the stats of everything worn (c.slotStats = { [equipment slot] = stats } of
-- what is worn, from SimBiS.WhenGearRead: a swap takes the old item's stats off).
function Character.AssertGear(c)
    for slot, id in pairs(c.items) do
        if not (c.slotStats and c.slotStats[slot]) then
            error("the game has no data for " .. (GetInventoryItemLink("player", slot) or ("item " .. id)) .. " yet", 0)
        end
    end
end

-- The character with another item in an equipment slot (1-18): its stats instead of the old item's, and in a weapon
-- slot the new weapon (a druid in Cat Form keeps its paws), from the shipped item data; stats: the item's own (from its
-- link: a random suffix counts). A shipped item without stats has none; errors for an item whose stats are unknown.
function Character.WithItem(char, slot, itemID, model, stats)
    local new = stats or LJ.Scoring.GetStats(itemID) or (LJ.Items.IsShipped(itemID) and {} or nil)
    assert(new, "no stats for item " .. itemID)
    local hand = HAND_OF_SLOT[slot]
    local lo, hi, speed = LJ.Items.GetWeapon(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    assert(not (slot == SLOT_OH and LJ.BiS.IsTwoHand(char.items[SLOT_MH])), "two-hander in the main hand")
    -- a two-hander in the main hand takes the off hand's place too
    local freed = { slot }
    if slot == SLOT_MH and equipLoc == "INVTYPE_2HWEAPON" and char.items[SLOT_OH] then freed[2] = SLOT_OH end
    local delta = {}
    for k, v in pairs(new) do delta[k] = (delta[k] or 0) + v end
    for _, s in ipairs(freed) do
        for k, v in pairs(char.slotStats[s] or {}) do delta[k] = (delta[k] or 0) - v end
    end
    local c = Character.WithStats(char, delta, model)
    c.items, c.slotStats = Copy(char.items), Copy(char.slotStats)
    for _, s in ipairs(freed) do c.items[s], c.slotStats[s] = nil, nil end
    c.items[slot], c.slotStats[slot] = itemID, new
    if slot == SLOT_OH or freed[2] then Character.ShieldChanged(c) end
    if hand and not (char.mh and char.mh.paws and hand ~= "ranged") then
        -- the attack speed factor and the sheet's modifiers of the weapon replaced (any weapon in hand without one)
        local old = char[hand] or char.mh or char.oh or char.ranged
        if lo then
            local w = Character.Weapon(itemID, lo, hi, speed, Character.WeaponSkills(), c.level,
                old and old.speed / old.swing or 1, hand == "ranged")
            w.basePct, w.bonus = old and old.basePct or 1, old and old.bonus or 0
            if hand == "ranged" then w.bonus = w.bonus - c.ammoDps * (old and old.speed or 0) + c.ammoDps * w.speed end
            c[hand] = w
            if freed[2] then c.oh = nil end
        else
            assert(hand ~= "mh", "item " .. itemID .. " is no weapon")
            c[hand] = nil
        end
        Character.ApplyWeaponMods(c, model)
    end
    return c
end

-- After a change in the off hand: without a shield no block value (a shield put on where none was worn has the block
-- value the character sheet said: none).
function Character.ShieldChanged(c)
    c.shield = Character.IsShield(c.items[SLOT_OH])
    if not c.shield then c.blockValue = 0 end
end

-- The character without the item of an equipment slot (1-18): its stats gone, in a weapon slot its weapon too (a druid
-- in Cat Form keeps its paws). The weapon the character fights with cannot go (Character.FightingHand).
function Character.WithoutItem(char, slot, model)
    local stats = assert(char.slotStats[slot], "nothing worn in slot " .. slot)
    local hand = HAND_OF_SLOT[slot]
    local paws = char.mh and char.mh.paws and hand ~= "ranged"
    assert(not hand or paws or hand ~= Character.FightingHand(char, model), "no weapon")
    local delta = {}
    for k, v in pairs(stats) do delta[k] = -v end
    local c = Character.WithStats(char, delta, model)
    c.items, c.slotStats = Copy(char.items), Copy(char.slotStats)
    c.items[slot], c.slotStats[slot] = nil, nil
    if slot == SLOT_OH then Character.ShieldChanged(c) end
    if hand and not paws then
        c[hand] = nil
        Character.ApplyWeaponMods(c, model)
    end
    return c
end
