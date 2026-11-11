-- Lootified - player information: class, spec, level, proficiencies, equipped gear.
local _, LJ = ...

local Player = {}
LJ.Player = Player

Player.class = "WARRIOR"
Player.level = 1
Player.faction = "Alliance"
Player.race = 1         -- race ID (1 Human): the race masks of quests only some races can take (Core/Quests.lua)

function Player:Refresh()
    local _, classFile = UnitClass("player")
    if classFile then self.class = classFile end
    self.level = UnitLevel("player") or self.level
    self.faction = UnitFactionGroup("player") or self.faction
    self.race = select(3, UnitRace("player")) or self.race
end

---------------------------------------------------------------------------
-- Professions: [skill line] = rank, read with the game's GetProfessions / GetProfessionInfo as Forever's own
-- professions book does (Blizzard_ProfessionsBook/Camelot)
---------------------------------------------------------------------------
Player.professions = {}

local function ProfessionRanks(...)
    local ranks = {}
    for i = 1, select("#", ...) do
        local index = select(i, ...)
        if index then
            local _, _, rank, _, _, _, line = GetProfessionInfo(index)
            if line then ranks[line] = rank end
        end
    end
    return ranks
end

-- A rank change changes what the character can wear when a rank some item asks for (Items.SkillRanks) lies above the
-- lower and at most at the higher of the two ranks (0: the profession not learned).
local function Crosses(line, a, b)
    local lo, hi = math.min(a, b), math.max(a, b)
    for rank in pairs(LJ.Items.SkillRanks(line)) do
        if rank > lo and rank <= hi then return true end
    end
    return false
end

-- true when a rank change changes what the character can wear (Scoring.MissingSkill): a profession learned, unlearned
-- or skilled up past a rank an item asks for. Other skill-ups change nothing (gathering skills up all the time).
function Player:RefreshProfessions()
    local ranks, changed = ProfessionRanks(GetProfessions()), false
    for line, rank in pairs(ranks) do changed = changed or Crosses(line, self.professions[line] or 0, rank) end
    for line, rank in pairs(self.professions) do changed = changed or (ranks[line] == nil and Crosses(line, rank, 0)) end
    self.professions = ranks
    return changed
end

-- The character's rank in a profession by its skill line; nil without it.
function Player:ProfessionRank(line)
    return self.professions[line]
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------
function Player:GetSpecs(class)
    return LJ.Data.BiS[class or self.class] or {}
end

function Player:GetSpec(class, key)
    for _, spec in ipairs(self:GetSpecs(class)) do
        if spec.key == key then return spec end
    end
end

-- Maps the live spec (name / role) of the client onto one of our BiS specs.
local NAME_HINTS = {
    { "prot", "PROT" }, { "retri", "RET" }, { "holy", "HOLY" }, { "disc", "DISC" }, { "shadow", "SHADOW" },
    { "resto", "RESTO" }, { "enhance", "ENH" }, { "elemental", "ELE" }, { "balance", "BALANCE" },
    { "guardian", "BEAR" }, { "fury", "FURY" }, { "arms", "ARMS" }, { "beast", "BM" }, { "marks", "MM" },
    { "surviv", "SV" }, { "assass", "ASSA" }, { "combat", "COMBAT" }, { "outlaw", "COMBAT" }, { "subtle", "SUB" },
    { "arcane", "ARCANE" }, { "fire", "FIRE" }, { "frost", "FROST" }, { "afflic", "AFFLI" }, { "demon", "DEMO" },
    { "destru", "DESTRO" },
}

-- WoW: Forever has the Classic talent trees (the talent window shows them side by side with the points spent in
-- each); the spec is the tree with the most points. A tree is recognised by its Classic skill line, else by its name
-- (English or German), else by its place in the window (the Classic order). FERAL: cat, or bear for a tank role.
-- (Classic skill line IDs: Wowhead Classic skill pages, AzerothCore SkillLine table; both Holy lines, 56 and 594, are HOLY.)
local TREE_SKILL_LINES = {
    [26] = "ARMS", [256] = "FURY", [257] = "PROT",
    [594] = "HOLY", [267] = "PROT", [184] = "RET",
    [50] = "BM", [163] = "MM", [51] = "SV",
    [253] = "ASSA", [38] = "COMBAT", [39] = "SUB",
    [613] = "DISC", [56] = "HOLY", [78] = "SHADOW",
    [375] = "ELE", [373] = "ENH", [374] = "RESTO",
    [237] = "ARCANE", [8] = "FIRE", [6] = "FROST",
    [355] = "AFFLI", [354] = "DEMO", [593] = "DESTRO",
    [574] = "BALANCE", [134] = "FERAL", [573] = "RESTO",
}
-- (keys as string.lower returns them: it leaves the German capital Ü of "Überleben" as it is)
local TREE_NAMES = {
    ["arms"] = "ARMS", ["waffen"] = "ARMS", ["fury"] = "FURY", ["furor"] = "FURY",
    ["protection"] = "PROT", ["schutz"] = "PROT", ["holy"] = "HOLY", ["heilig"] = "HOLY",
    ["retribution"] = "RET", ["vergeltung"] = "RET",
    ["beast mastery"] = "BM", ["tierherrschaft"] = "BM", ["marksmanship"] = "MM", ["treffsicherheit"] = "MM",
    ["survival"] = "SV", ["Überleben"] = "SV",
    ["assassination"] = "ASSA", ["meucheln"] = "ASSA", ["combat"] = "COMBAT", ["kampf"] = "COMBAT",
    ["subtlety"] = "SUB", ["täuschung"] = "SUB",
    ["discipline"] = "DISC", ["disziplin"] = "DISC", ["shadow"] = "SHADOW", ["shadow magic"] = "SHADOW",
    ["schatten"] = "SHADOW", ["schattenmagie"] = "SHADOW",
    ["elemental"] = "ELE", ["elementar"] = "ELE", ["enhancement"] = "ENH", ["verstärkung"] = "ENH",
    ["restoration"] = "RESTO", ["wiederherstellung"] = "RESTO",
    ["arcane"] = "ARCANE", ["arkan"] = "ARCANE", ["fire"] = "FIRE", ["feuer"] = "FIRE", ["frost"] = "FROST",
    ["affliction"] = "AFFLI", ["gebrechen"] = "AFFLI", ["demonology"] = "DEMO", ["dämonologie"] = "DEMO",
    ["destruction"] = "DESTRO", ["zerstörung"] = "DESTRO",
    ["balance"] = "BALANCE", ["gleichgewicht"] = "BALANCE", ["feral combat"] = "FERAL", ["wilder kampf"] = "FERAL",
}
local TREE_ORDER = {
    WARRIOR = { "ARMS", "FURY", "PROT" }, PALADIN = { "HOLY", "PROT", "RET" }, HUNTER = { "BM", "MM", "SV" },
    ROGUE = { "ASSA", "COMBAT", "SUB" }, PRIEST = { "DISC", "HOLY", "SHADOW" }, SHAMAN = { "ELE", "ENH", "RESTO" },
    MAGE = { "ARCANE", "FIRE", "FROST" }, WARLOCK = { "AFFLI", "DEMO", "DESTRO" }, DRUID = { "BALANCE", "FERAL", "RESTO" },
}

-- The talent tree with the most points spent (nil: no talent trees, no points, or unknown trees), read the way the
-- game's own talent window reads them: active spec group -> trait config -> tree -> the groups (one per talent
-- tree) with the points spent in each.
function Player:GetTalentTreeSpec()
    local SI = C_SpecializationInfo
    local configID = SI.GetCombatConfigIDForSpecGroup(SI.GetActiveSpecGroup())
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if not groups or #groups == 0 then return nil end
    local groupIDs = {}
    for i, group in ipairs(groups) do groupIDs[i] = group.groupID end
    local spentByGroup = {}
    for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        local spent = currency and currency.spent
        if LJ.Util.IsSecret(spent) then return nil end
        spentByGroup[info.traitNodeGroupID] = spent
    end
    local order = TREE_ORDER[self.class]
    local best, bestSpent = nil, 0
    for i, group in ipairs(groups) do
        local spent = spentByGroup[group.groupID] or 0
        if spent > bestSpent then
            local name = group.displayName
            local key = TREE_SKILL_LINES[group.skillLineID]
                or (type(name) == "string" and not LJ.Util.IsSecret(name) and TREE_NAMES[name:lower()])
                or (order and order[i])
            best, bestSpent = key, spent
        end
    end
    return best
end

-- The damage entries of the healer trees (HOLY_DMG, DISC_DMG: listed after the trees' specs) are never detected: the
-- player picks them in the Best in Slot list (healers take their talents too).
function Player:DetectSpecKey()
    local specs = self:GetSpecs()
    if #specs == 0 then return nil end
    if #specs == 1 then return specs[1].key end

    local function Has(key)
        for _, spec in ipairs(specs) do
            if spec.key == key then return key end
        end
    end

    local name, role
    local SI = C_SpecializationInfo
    local index = SI.GetSpecialization()
    if index and index > 0 then
        local _, specName, _, _, specRole = SI.GetSpecializationInfo(index)
        -- Forever has one spec per class: its name and role only mean something where the game lets you pick a
        -- spec (the character window shows the spec name only then)
        if SI.IsSpecSelectionEnabled(select(3, UnitClass("player"))) then
            if not LJ.Util.IsSecret(specName) then name = specName end
            if not LJ.Util.IsSecret(specRole) then role = specRole end
        end
    end

    local tree = self:GetTalentTreeSpec()
    if tree == "FERAL" then
        return (role == "TANK") and Has("BEAR") or Has("CAT") or specs[1].key
    elseif tree and Has(tree) then
        return tree
    end

    if type(name) == "string" then
        local lower = name:lower()
        if lower:find("feral") then
            return (role == "TANK") and Has("BEAR") or Has("CAT")
        end
        for _, hint in ipairs(NAME_HINTS) do
            if lower:find(hint[1], 1, true) and Has(hint[2]) then
                return hint[2]
            end
        end
    end
    if role == "TANK" then
        return Has("PROT") or Has("BEAR") or specs[1].key
    elseif role == "HEALER" then
        return Has("HOLY") or Has("RESTO") or specs[1].key
    end
    for _, spec in ipairs(specs) do
        if spec.role == "DPS" then return spec.key end
    end
    return specs[1].key
end

-- The spec used by the journal: the player's choice, otherwise auto-detected. The detected spec is kept until the
-- talents or the spec change (item tooltips ask for it on every item).
local detectedKey
function Player:GetActiveSpecKey()
    local chosen = LJ.cdb.spec and LJ.cdb.spec[self.class]
    if chosen and self:GetSpec(self.class, chosen) then
        return chosen
    end
    detectedKey = detectedKey or self:DetectSpecKey()
    return detectedKey
end

function Player:GetActiveSpec()
    return self:GetSpec(self.class, self:GetActiveSpecKey())
end

function Player:SetChosenSpec(class, key)
    if class ~= self.class then return end
    LJ.cdb.spec[class] = key
    LJ:Fire("SPEC_CHANGED")
end

---------------------------------------------------------------------------
-- Proficiencies (Classic rules). Armor: subclass -> required level.
---------------------------------------------------------------------------
local ARMOR = {
    WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER  = { [0] = 1, [1] = 1, [2] = 1, [3] = 40 },
    ROGUE   = { [0] = 1, [1] = 1, [2] = 1 },
    PRIEST  = { [0] = 1, [1] = 1 },
    SHAMAN  = { [0] = 1, [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    MAGE    = { [0] = 1, [1] = 1 },
    WARLOCK = { [0] = 1, [1] = 1 },
    DRUID   = { [0] = 1, [1] = 1, [2] = 1, [8] = 1 },
}

local function Set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

-- Weapon subclasses (Enum.ItemWeaponSubclass)
local WEAPONS = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER  = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE   = Set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST  = Set(4, 10, 15, 19),
    SHAMAN  = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE    = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID   = Set(4, 5, 10, 13, 15),
}

-- The level a class learns Dual Wield at its trainer (CMaNGOS classic-db npc_trainer_template: the warrior, hunter and
-- rogue trainers teach spell 1424, which teaches Dual Wield 674); the other classes never learn it.
local DUAL_WIELD_LEVEL = { WARRIOR = 20, HUNTER = 20, ROGUE = 10 }

Player.ARMOR = ARMOR
Player.WEAPONS = WEAPONS

-- Can a character wield a weapon in the off hand? The player's own character when the game says so (CanDualWield: it
-- trained Dual Wield), a character of another class when its class learns it (with level: from that level on).
function Player:CanDualWield(class, level)
    class = class or self.class
    if class == self.class then return self.dualWield end
    local from = DUAL_WIELD_LEVEL[class]
    return from ~= nil and (level == nil or level >= from)
end

-- Dual Wield as the game says (CanDualWield); true when that changed (trained at a trainer)
function Player:RefreshDualWield()
    local known = CanDualWield()
    local changed = self.dualWield ~= known
    self.dualWield = known
    return changed
end

-- Can class wear/wield the item at all (ignoring level)? When atLevel is given,
-- armor proficiencies that unlock at 40 (mail / plate) are checked too. Off-hand weapons need Dual Wield
-- (Player:CanDualWield: the player's own character as the game says, another class at atLevel).
function Player:CanClassUse(rec, class, atLevel)
    class = class or self.class
    if not rec or not rec.equipLoc or rec.equipLoc == "" then return false end
    if rec.equipLoc == "INVTYPE_NON_EQUIP_IGNORE" or rec.equipLoc == "INVTYPE_BAG" or rec.equipLoc == "INVTYPE_TABARD"
        or rec.equipLoc == "INVTYPE_BODY" or rec.equipLoc == "INVTYPE_AMMO" or rec.equipLoc == "INVTYPE_QUIVER" then
        return false
    end
    if rec.classID == 4 then
        local req = ARMOR[class] and ARMOR[class][rec.subclassID or 0]
        if not req then return false end
        if atLevel and atLevel < req then return false end
    elseif rec.classID == 2 then
        -- off-hand weapons need dual wield
        if rec.equipLoc == "INVTYPE_WEAPONOFFHAND" and not self:CanDualWield(class, atLevel) then return false end
        if not (WEAPONS[class] and WEAPONS[class][rec.subclassID or -1]) then return false end
    end
    -- items only some classes can use ("Classes: Mage")
    if rec.id and not LJ.Items.IsClassAllowed(rec.id, class) then return false end
    return true
end

---------------------------------------------------------------------------
-- Equipped gear
---------------------------------------------------------------------------
Player.SLOT_IDS = {
    HEAD = { 1 }, NECK = { 2 }, SHOULDER = { 3 }, BACK = { 15 }, CHEST = { 5 }, WRIST = { 9 }, HANDS = { 10 },
    WAIST = { 6 }, LEGS = { 7 }, FEET = { 8 }, FINGER = { 11, 12 }, TRINKET = { 13, 14 },
    MAINHAND = { 16 }, OFFHAND = { 17 }, TWOHAND = { 16 }, RANGED = { 18 }, RELIC = { 18 },
}

function Player:GetEquippedItemID(slotID)
    return GetInventoryItemID("player", slotID)
end

function Player:GetEquippedLink(slotID)
    return GetInventoryItemLink("player", slotID)
end

LJ:Listen("LOGIN", function()
    Player:Refresh()
    Player:RefreshProfessions()
    Player:RefreshDualWield()
end)
-- a profession rank that changes what the character can wear: the upgrades are counted again (debounced: crafting
-- skills up often)
LJ:On("SKILL_LINES_CHANGED", function()
    if Player:RefreshProfessions() then LJ:FireDebounced("PLAYER_CHANGED", 1) end
end)
-- Dual Wield trained (a spell): the upgrades are counted again (the game's own Classic wardrobe counts what the
-- character can use again on SPELLS_CHANGED)
LJ:On("SPELLS_CHANGED", function()
    if Player:RefreshDualWield() then LJ:Fire("PLAYER_CHANGED") end
end)
LJ:On("PLAYER_LEVEL_UP", function(_, level)
    Player.level = level or UnitLevel("player")
    LJ:Fire("PLAYER_CHANGED")
end)

-- The talents with points, one text ("entry:rank" of the active talent config, in the trees' order): a change makes the
-- sims outdated (Sim/SimBiS.lua). Kept until the talents or the spec change.
local talentsText
function Player:TalentsText()
    if not talentsText then
        local parts = {}
        local configID = C_ClassTalents.GetActiveConfigID()
        local config = configID and C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(config and config.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node and node.activeRank > 0 and node.activeEntry then
                    parts[#parts + 1] = node.activeEntry.entryID .. ":" .. node.activeRank
                end
            end
        end
        talentsText = table.concat(parts, ",")
    end
    return talentsText
end

local function SpecMaybeChanged()
    detectedKey, talentsText = nil, nil
    LJ:FireDebounced("SPEC_CHANGED", 0.5)
end
-- (it names the unit whose spec changed: a party or raid member's change is not the player's)
LJ:On("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == "player" then SpecMaybeChanged() end
end)
LJ:On("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", SpecMaybeChanged)
LJ:On("PLAYER_TALENT_UPDATE", SpecMaybeChanged)
LJ:On("TRAIT_CONFIG_UPDATED", SpecMaybeChanged)
-- the talent configs arrive after login
LJ:On("TRAIT_CONFIG_LIST_UPDATED", SpecMaybeChanged)
LJ:On("PLAYER_ENTERING_WORLD", function() detectedKey, talentsText = nil, nil end)
LJ:On("PLAYER_EQUIPMENT_CHANGED", function()
    LJ:FireDebounced("EQUIPMENT_CHANGED", 0.3)
end)
LJ:On("BAG_UPDATE_DELAYED", function()
    LJ:FireDebounced("BAGS_CHANGED", 0.5)
end)

-- Class, level and faction are already known while addons load.
Player:Refresh()
