-- Lootified - the database's Items page: every item the addon knows (dungeon and raid loot, Best in Slot items, open
-- world drops, quest rewards). Filters: slot, quality, required level, where it comes from, usable by the character;
-- sorted by the upgrade for the character, the level, the name or the quality. The picked item shows as a card: its
-- icon in its quality's glow, its upgrade, its stats, where it drops (a click opens the mob or the place) and the
-- quests that give it; below it the wishlist, try on and a chat link.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local DB = LJ.Database
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local Quests = LJ.Quests
local Lists = LJ.Lists
local Scoring = LJ.Scoring
local BiS = LJ.BiS
local C = Theme.COLORS

local function QualityColor(q)
    local r, g, b = Util.QualityColor(q or 1)
    return { r, g, b, 1 }
end

-- the slot filter's options: the Loot tab's slots (Lists.SLOT_FILTERS) with short names for the chips
local SHORT = { ALL = "All", WEAPON = "Weapons", OFFHAND = "Off-hand", RANGED = "Ranged", OTHER = "Other" }
local SLOTS = {}
for _, f in ipairs(Lists.SLOT_FILTERS) do SLOTS[#SLOTS + 1] = { key = f.key, text = SHORT[f.key] or f.text } end

-- the qualities: common, uncommon, rare, epic (and better); poor items count as common
local QUALITIES = {}
for q, name in ipairs({ "Common", "Uncommon", "Rare", "Epic" }) do QUALITIES[q] = { key = q, text = name, color = QualityColor(q) } end

-- bit: the source in a record's kinds (one number per item, not a table)
local SOURCES = {
    { key = "dungeon", text = "Dungeon", glyph = "castle", bit = 1 },
    { key = "raid", text = "Raid", glyph = "crown", bit = 2 },
    { key = "rare", text = "Rare mob", glyph = "skull", bit = 4 },
    { key = "world", text = "World", glyph = "globe", bit = 8 },
    { key = "quest", text = "Quest", glyph = "scroll", bit = 16 },
    { key = "other", text = "Other", glyph = "package", bit = 32 },
}
local BIT = {}
for _, src in ipairs(SOURCES) do BIT[src.key] = src.bit end

local function HasBit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

---------------------------------------------------------------------------
-- Records: the items as the table needs them, read without asking the server
---------------------------------------------------------------------------
-- Where an item comes from, as the bits of the source filter's keys. The open world drop is read from the shipped
-- data (no mob lists are built for thousands of items).
local function SourceKinds(id)
    local kinds = {}
    for _, s in ipairs(Items.GetSources(id) or {}) do
        local inst = LJ.instanceByKey[s.inst]
        kinds[(inst and inst.kind == "raid") and "raid" or "dungeon"] = true
    end
    local drop = Items.GetWorldDrop(id)
    if drop then
        local mobs, worldMobs = drop[4], LJ.Data.WorldMobs or {}
        for i = 1, #mobs, 2 do
            local m = worldMobs[mobs[i]]
            if m then kinds[(m[4] == 2 or m[4] == 4) and "rare" or "world"] = true end
        end
        if drop[5] then kinds.world = true end   -- a random world drop
    end
    if Quests.rewardOf[id] or (LJ.Data.WorldQuestRewards and LJ.Data.WorldQuestRewards[id]) then kinds.quest = true end
    if not next(kinds) then kinds.other = true end
    local mask = 0
    for key in pairs(kinds) do mask = mask + BIT[key] end
    return mask
end

-- A record keeps only what the table, the filters and the sorts read: thousands of them stay while the page shows.
local slotFacts = {}   -- what Items.SlotTextOf reads, for the record being made
local function MakeRecord(id)
    local name, quality = Items.GetQuickInfo(id)
    if not name then return nil end
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    local _, metaSlot, flags = Items.GetMeta(id)
    local f = slotFacts
    f.equipLoc, f.classID, f.subclassID = equipLoc, classID, subclassID
    f.slotText = metaSlot ~= "" and metaSlot or nil
    f.isQuest = classID == 12 or (flags and flags:find("Q", 1, true) ~= nil)
    local minLevel, itemLevel = Items.GetKnownLevels(id)
    return { id = id, name = name, quality = math.max(1, quality or 1), equipLoc = equipLoc, classID = classID,
        subclassID = subclassID, level = math.max(1, Items.UseLevelFrom(id, minLevel, itemLevel) or 1),
        itemLevel = itemLevel, slot = Items.SlotTextOf(f), kinds = SourceKinds(id) }
end

-- Where an item comes from as one line ("Mr. Smite · The Deadmines"), made when a row or the search first needs it.
local function SourceText(rec)
    if not rec.source then rec.source = (LJ.BiS.SourceText(rec.id) or ""):gsub(" %- ", " · ") end
    return rec.source
end

-- the name order as a number (nameRank): the sorts compare numbers, not names (a sort of thousands of results); the
-- names' sort keys are only kept while the ranks are made
local nameKeys
local function ByNameKey(a, b)
    local ka, kb = nameKeys[a], nameKeys[b]
    if ka ~= kb then return ka < kb end
    return a.id < b.id
end

local function Records()
    local list = {}
    for _, id in ipairs(LJ.UI.SearchItemIDs()) do
        local rec = MakeRecord(id)
        if rec then list[#list + 1] = rec end
    end
    local byName = {}
    nameKeys = {}
    for i, rec in ipairs(list) do
        byName[i] = rec
        nameKeys[rec] = Util.SearchKey(rec.name)
    end
    table.sort(byName, ByNameKey)
    nameKeys = nil
    for i, rec in ipairs(byName) do rec.nameRank = i end
    return list
end

local function Passes(rec, state)
    if state.slot ~= "ALL" and not Lists.PassesSlot(rec, state.slot) then return false end
    if not state.quality[math.min(rec.quality, 4)] then return false end
    if not DB.InLevels(state.level, rec.level) then return false end
    local source = false
    for _, src in ipairs(SOURCES) do
        if state.sources[src.key] and HasBit(rec.kinds, src.bit) then
            source = true
            break
        end
    end
    if not source then return false end
    return not state.usable or Lists.PassesClass(rec, "MINE")
end

-- the Best in Slot picks of the character's spec at its level (the Best in Slot page's) get a crown; the sort
-- "For you" needs every listed item's upgrade
local function Prepare(list, _, sort)
    local picks = {}
    local spec = Player:GetActiveSpec()
    for _, p in ipairs(spec and LJ.Modules.On("bis") and LJ.BiS.GetPicks(spec) or {}) do picks[p.id] = true end
    local forYou = sort.key == "foryou"
    for _, rec in ipairs(list) do
        rec.bis = picks[rec.id]   -- true or nil (no field more on thousands of records)
        if forYou then rec.up = BiS.Upgrade(rec.id) end
    end
end

local function ByName(a, b)
    return a.nameRank < b.nameRank
end

local SORTS = {
    -- For you: the Best in Slot picks, then the upgrades (the biggest first), then the rest
    { key = "foryou", text = "For you", column = 4, compare = function(a, b)
        if a.bis ~= b.bis then return a.bis end
        local ua, ub = a.up or -1, b.up or -1
        if ua ~= ub then return ua > ub end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.level ~= b.level then return a.level > b.level end
        return ByName(a, b)
    end },
    { key = "level", text = "Level", column = 3, compare = function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return ByName(a, b)
    end },
    { key = "name", text = "Name", column = 1, compare = ByName },
    { key = "quality", text = "Quality", compare = function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.level ~= b.level then return a.level > b.level end
        return ByName(a, b)
    end },
}

---------------------------------------------------------------------------
-- The row: icon in its quality's glow, name and where it comes from, slot, level, the upgrade
---------------------------------------------------------------------------
Kit.KINDS.dbItem = {
    height = DB.ROW_HEIGHT,
    create = function(parent, sheet)
        local f = DB.CreateRow(parent)
        local cols = sheet.page.cols
        f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 3)
        f.glow:SetTexture(Theme.TEX.glow)
        f.glow:SetBlendMode("ADD")
        f.glow:SetSize(50, 50)
        f.icon = Widgets.CreateItemIcon(f, DB.ICON)
        f.icon:SetPoint("LEFT", cols.pos[1], 1)
        f.icon:EnableMouse(false)
        f.glow:SetPoint("CENTER", f.icon, "CENTER")
        f.star = Widgets.Glyph(f, "star", 11, C.gold)
        f.crown = Widgets.Glyph(f, "crown", 12, C.gold)
        f.slot = DB.Cell(f, "bodySmall")
        f.level = DB.Cell(f, "chip")
        f.up = Widgets.CreatePill(f, 20, "count")
        return f
    end,
    fill = function(f, rec)
        local page = f.sheet.page
        local cols = page.cols
        local item = Items.Get(rec.id)
        f.icon:SetItem(rec.id)
        local quality = item.quality or rec.quality
        local c = QualityColor(quality)
        f.glow:SetVertexColor(c[1], c[2], c[3], quality >= 2 and 0.4 or 0)
        f.name:SetText(item.name or rec.name)
        f.name:SetTextColor(c[1], c[2], c[3])
        f.sub:SetText(SourceText(rec))
        DB.PlaceName(f, DB.ICON)
        -- after the name: the Best in Slot crown, the wishlist star
        f.crown:SetShown(rec.bis)
        f.star:SetShown(Items.IsWishlisted(rec.id))
        local right = cols.pos[1] + cols.nameWidth
        for _, mark in ipairs({ f.star, f.crown }) do
            if mark:IsShown() then
                f.name:SetWidth(f.name:GetWidth() - 15)
                mark:ClearAllPoints()
                mark:SetPoint("TOPRIGHT", f, "TOPLEFT", right, -8)
                right = right - 15
            end
        end
        f.slot:SetText(rec.slot)
        DB.PlaceCell(f, f.slot, 2)
        f.level:SetText(rec.level > 1 and tostring(rec.level) or "")
        DB.PlaceCell(f, f.level, 3)
        local up = BiS.Upgrade(rec.id)
        f.up:SetShown(up and true or false)
        if up then
            f.up:Set(DB.UpgradeText(rec.id), "ok", "upgrade")
            f.up:ClearAllPoints()
            f.up:SetPoint("RIGHT", f, "LEFT", cols.pos[4] + page.def.columns[4].width, 1)
        end
        f.selected = page.selected == rec.id
        f.hovered = f:IsMouseOver()
        DB.RowVisual(f)
    end,
}

---------------------------------------------------------------------------
-- The detail: the card, the stats, the sources, the actions
---------------------------------------------------------------------------
local HERO = 150

-- Stat names (Core/Scoring.lua keys) in the order the stats block lists them.
local STATS = {
    { "Strength", "Strength" }, { "Agility", "Agility" }, { "Stamina", "Stamina" }, { "Intellect", "Intellect" },
    { "Spirit", "Spirit" }, { "AttackPower", "Attack Power" }, { "RangedAttackPower", "Ranged Attack Power" },
    { "SpellPowerAll", "Spell Power" }, { "SpellDamage", "Spell Damage" }, { "Healing", "Healing" },
    { "ShadowPower", "Shadow Spell Power" }, { "FirePower", "Fire Spell Power" }, { "FrostPower", "Frost Spell Power" },
    { "NaturePower", "Nature Spell Power" }, { "ArcanePower", "Arcane Spell Power" }, { "HolyPower", "Holy Spell Power" },
    { "HitRating", "Hit Rating" }, { "CritRating", "Critical Strike Rating" }, { "HasteRating", "Haste Rating" },
    { "ExpertiseRating", "Expertise Rating" }, { "Defense", "Defense" }, { "DodgeRating", "Dodge Rating" },
    { "ParryRating", "Parry Rating" }, { "BlockRating", "Block Rating" }, { "BlockValue", "Block Value" },
    { "MP5", "Mana per 5 sec." },
}

local BIND = { [1] = "Binds when picked up", [2] = "Binds when equipped", [3] = "Binds when used", [4] = "Quest Item" }

-- The lines of the stats block: damage, armor, stats (three to a line), the required level the game gives it.
local function StatLines(rec, item)
    local stats = Scoring.GetCachedStats(rec.id) or Items.GetKnownStats(rec.id, {})
    local lines = {}
    if stats then
        if stats.DPS and stats.DPS > 0 then lines[#lines + 1] = F("%.1f damage per second", stats.DPS) end
        if stats.Armor and stats.Armor > 0 then lines[#lines + 1] = F("%d Armor", stats.Armor) end
        local parts = {}
        for _, s in ipairs(STATS) do
            local v = stats[s[1]]
            if v and v ~= 0 then parts[#parts + 1] = string.format("%s%d %s", v > 0 and "+" or "", v, L(s[2])) end
        end
        for i = 1, #parts, 2 do
            lines[#lines + 1] = parts[i] .. (parts[i + 1] and ("  ·  " .. parts[i + 1]) or "")
        end
    end
    if item.minLevel and item.minLevel > 1 then
        lines[#lines + 1] = Theme.ColorText(F("Requires level %d", item.minLevel), C.text3)
    end
    return lines
end

-- What the upgrade line of the card says (the required level the game gives the item, as the ranking reads it).
local function UpgradeLine(rec, item, up, spec)
    if up then return nil, F("upgrade for you (%s)", L(spec.name)) end
    if not (rec.classID == 2 or rec.classID == 4) or not spec then return nil, "" end
    if not Player:CanClassUse(rec, spec.class) then return C.bad, L("Your class cannot use it") end
    local missing = spec.class == Player.class and Scoring.MissingSkill(rec.id)
    if missing then return C.bad, missing end
    local need = item.minLevel or 0
    if need > (Player.level or 1) + 5 then return C.text3, F("Usable from level %d", need) end
    return C.text3, L("No upgrade for you right now")
end

local function CreateDetail(page, panel)
    local hero = DB.Hero(panel, HERO)
    hero.icon = Widgets.CreateItemIcon(hero, 58)
    hero.icon:SetPoint("TOPLEFT", 18, -20)
    hero.icon:SetScript("OnEnter", function(b) Widgets.ShowItemTooltip(b, page.detailID) end)
    hero.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hero.icon:SetScript("OnClick", function(_, button) Items.HandleClick(page.detailID, button) end)
    hero.iconGlow = hero:CreateTexture(nil, "BACKGROUND", nil, 2)
    hero.iconGlow:SetTexture(Theme.TEX.glow)
    hero.iconGlow:SetBlendMode("ADD")
    hero.iconGlow:SetSize(110, 110)
    hero.iconGlow:SetPoint("CENTER", hero.icon, "CENTER")
    hero.name = Widgets.Text(hero, "titleSmall", C.white)
    hero.name:SetPoint("TOPLEFT", hero.icon, "TOPRIGHT", 14, 1)
    hero.name:SetPoint("RIGHT", -16, 0)
    hero.name:SetWordWrap(true)
    hero.name:SetMaxLines(2)
    hero.type = Widgets.Text(hero, "bodySmall", DB.TEXT)
    hero.type:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -4)
    hero.type:SetPoint("RIGHT", -16, 0)
    hero.type:SetWordWrap(true)
    -- (German and Russian need a third line for slot, bind and item level)
    hero.type:SetMaxLines(3)
    hero.up = Widgets.CreatePill(hero, 26, "tab")
    hero.up:SetPoint("BOTTOMLEFT", 18, 12)
    hero.upText = Widgets.Text(hero, "bodySmall", C.text3)
    hero.upText:SetPoint("RIGHT", -16, 0)
    page.hero = hero
    local sheet = Kit.Sheet(panel, 5)
    sheet.scroll:SetPoint("TOPLEFT", 16, -(HERO + 2))
    sheet.scroll:SetPoint("BOTTOMRIGHT", -16, 64)
    page.detailSheet = sheet
    page.actions = DB.Actions(panel)
end

local function FillDetail(page, rec)
    local hero, sheet = page.hero, page.detailSheet
    sheet:Reset(272)
    page.detailID = rec and rec.id
    hero:SetShown(rec ~= nil)
    page.actions:SetShown(rec ~= nil)
    if not rec then
        sheet:Add("empty", { title = L("No item picked"), text = L("Pick an item in the list to see where it drops."), glyph = "package" })
        sheet:Finish()
        return
    end
    local id = rec.id
    local item = Items.Get(id)
    local quality = item.quality or rec.quality
    local c = QualityColor(quality)

    -- the card
    hero.icon:SetItem(id)
    hero.icon:SetOwned(Items.IsOwned(id))
    hero.iconGlow:SetVertexColor(c[1], c[2], c[3], quality >= 2 and 0.55 or 0.15)
    hero.glow:SetVertexColor(c[1], c[2], c[3], quality >= 2 and 0.28 or 0.1)
    hero.name:SetText(Util.Upper(item.name or rec.name))
    hero.name:SetTextColor(math.min(1, c[1] * 0.75 + 0.3), math.min(1, c[2] * 0.75 + 0.3), math.min(1, c[3] * 0.75 + 0.3))
    local facts = {}
    if rec.slot ~= "" then facts[#facts + 1] = rec.slot end
    if BIND[item.bindType] then facts[#facts + 1] = L(BIND[item.bindType]) end
    if rec.itemLevel and rec.itemLevel > 0 then facts[#facts + 1] = F("Item level %d", rec.itemLevel) end
    hero.type:SetText(table.concat(facts, " · "))
    local spec = Player:GetActiveSpec()
    local up = BiS.Upgrade(id)
    local color, line = UpgradeLine(rec, item, up, spec)
    hero.up:SetShown(up and true or false)
    hero.upText:ClearAllPoints()
    if up then
        hero.up:Set(DB.UpgradeText(id), "ok", "upgrade")
        hero.upText:SetPoint("LEFT", hero.up, "RIGHT", 10, 0)
    else
        hero.upText:SetPoint("BOTTOMLEFT", 18, 18)
    end
    hero.upText:SetPoint("RIGHT", -16, 0)
    hero.upText:SetText(line)
    Widgets.SetTextColor(hero.upText, color or C.text3)

    -- stats
    local lines = StatLines(rec, item)
    if #lines > 0 then sheet:Add("dbBlock", { lines = lines }) end

    -- where it drops: dungeon bosses, open world mobs, random drops
    local sources = Items.GetSources(id) or {}
    local mobs, random = Items.GetWorldSources(id)
    mobs = mobs or {}
    local count = #sources + #mobs + (random and 1 or 0)
    if count > 0 then
        sheet:Add("section", { text = L("Drops from"), count = count })
        for _, s in ipairs(sources) do
            local inst = LJ.instanceByKey[s.inst]
            if inst then
                local boss = s.boss > 0 and inst.bosses[s.boss] or nil
                local chance = Util.FormatChance(s.chance)
                if boss then
                    sheet:Add("dbSource", { text = boss.name, sub = F("%s · boss %d", inst.name, s.boss), boss = boss, inst = inst,
                        right = chance, rightColor = Theme.ChanceColor(s.chance),
                        onClick = function() DB.Go("mobs", DB.BossID(inst.key, s.boss)) end })
                else
                    sheet:Add("dbSource", { text = L("Trash mobs"), sub = inst.name, emblem = "bag", right = chance,
                        rightColor = Theme.ChanceColor(s.chance), onClick = function() DB.Go("places", DB.InstanceID(inst.key)) end })
                end
            end
        end
        for _, m in ipairs(mobs) do
            local mob = m.mob
            local zone = Items.GetMobZone(mob)
            local chance = Util.FormatChance(m.chance)
            sheet:Add("dbSource", { text = mob.name, sub = (zone and (zone .. " · ") or "") .. F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel)),
                display = mob.display, emblem = Theme.BossEmblem(mob), rare = mob.isRare, right = chance,
                rightColor = Theme.ChanceColor(m.chance), onClick = function() DB.Go("mobs", DB.WorldMobID(mob.id)) end })
        end
        if random then
            sheet:Add("dbSource", { text = L("Random world drop"), glyph = "globe",
                sub = F("Almost any mob of level %s", Util.LevelRange(random.minLevel, random.maxLevel)) })
        end
    end

    -- the quests that give it
    local quests = {}
    for _, qid in ipairs(Quests.rewardOf[id] or {}) do
        local q = Quests.Get(qid)
        if q then quests[#quests + 1] = q end
    end
    for _, q in ipairs(Items.GetWorldQuestSources(id) or {}) do quests[#quests + 1] = q end
    if #quests > 0 then
        sheet:Add("section", { text = L("Quest reward"), count = #quests })
        for _, q in ipairs(quests) do
            local status = Quests.GetStatus(q)
            local glyph, gc = LJ.PaneQuests.StatusGlyph(status)
            sheet:Add("row", { text = q.name, sub = F("Level %s", q.level or "?") .. "  ·  " .. Quests.SideText(q.side),
                glyph = glyph, glyphColor = gc, onClick = function() DB.Go("quests", q.id) end })
        end
    end

    if count == 0 and #quests == 0 then
        sheet:Add("section", { text = L("Where it comes from") })
        local known = Items.GetCraftedText(id) or LJ.BiS.FindCuratedSource(id)
        sheet:Add("text", { text = known or L("This item is not in the loot data. It may be crafted, sold by a vendor or come from a source that is new in Forever."),
            font = "bodySmall", color = C.text2, spacing = 3 })
    end
    local note = LJ.Data.ItemNotes and LJ.Data.ItemNotes[id]
    if note then
        sheet:Add("section", { text = L("Note") })
        sheet:Add("text", { text = note, font = "bodySmall", color = C.text3, spacing = 3 })
    end
    sheet:Finish(8)

    -- the actions
    local wished = Items.IsWishlisted(id)
    local function TryOn() DressUpItemLink(Items.GetLink(id)) end
    local link = { glyph = "link", tooltip = "Link in chat", onClick = function() Widgets.LinkInChat(id) end }
    if LJ.Modules.On("wishlist") then
        DB.SetActions(page.actions,
            { text = wished and "On your wishlist" or "Add to wishlist", glyph = wished and "check" or "star",
                onClick = function() Items.ToggleWishlist(id) end,
                tooltip = wished and "Remove from Wishlist" or "Add to Wishlist", tooltipText = "You get an alert when it drops." },
            { { glyph = "shirt", tooltip = "Try on", tooltipText = "Shows the item on your character in the dressing room.", onClick = TryOn,
                tryOn = true }, link })
    else
        -- the Wishlist module off: Try on is the main action
        DB.SetActions(page.actions, { text = "Try on", glyph = "shirt", onClick = TryOn, tryOn = true, tooltip = "Try on",
            tooltipText = "Shows the item on your character in the dressing room." }, { link })
    end
end

DB.Page({
    key = "items", scope = "Items", placeholder = "Search items, slots, sources",
    toggle = { key = "usable", label = "Usable by me", tooltip = "Only gear your class can wear or wield." },
    sorts = SORTS,
    filters = {
        { key = "slot", label = "Slot", kind = "chips", options = SLOTS },
        { key = "quality", label = "Quality", kind = "checks", options = QUALITIES },
        { key = "level", label = "Required level", kind = "range" },
        { key = "sources", label = "Source", kind = "multi", options = SOURCES },
    },
    columns = { { title = "Item" }, { title = "Slot", width = 92 }, { title = "Lv", width = 26 },
        { title = "For you", width = 64, justify = "RIGHT" } },
    rowKind = "dbItem", icon = DB.ICON,
    Records = Records, Passes = Passes, Prepare = Prepare,
    SearchKey = function(rec) return DB.SearchKey(rec.name, rec.slot, SourceText(rec)) end,
    Find = function(id)
        return type(id) == "number" and MakeRecord(id) or nil
    end,
    CreateDetail = CreateDetail, FillDetail = FillDetail,
    OnRowEnter = function(f, rec) Widgets.ShowItemTooltip(f, rec.id) end,
    OnRowClick = function(f, rec, button)
        if Items.HandleClick(rec.id, button) then return true end
        if button == "RightButton" then
            Widgets.ShowItemMenu(f, rec.id)
            return true
        end
        return false
    end,
})
