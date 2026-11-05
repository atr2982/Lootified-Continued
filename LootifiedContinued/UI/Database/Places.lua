-- Lootified - the database's Places page: every dungeon and raid and every zone with open world mobs. Filters: type,
-- level; "Near my level" keeps the places around the character's level. The picked place:
-- its picture (a dungeon) or the globe (a zone), its facts, its bosses or its rares and mobs (a click opens them on the
-- Mobs page), the best upgrades for the character there, and buttons for the map (a dungeon's entrance, a zone's map),
-- the dungeon map and its quests and mobs on the other pages.
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
local MapPin = LJ.MapPin
local BiS = LJ.BiS
local C = Theme.COLORS

local KINDS = {
    { key = "dungeon", text = "Dungeon", glyph = "castle" },
    { key = "raid", text = "Raid", glyph = "crown" },
    { key = "zone", text = "Zone", glyph = "globe" },
}
local KIND_TEXT = { dungeon = "Dungeon", raid = "Raid", zone = "Zone" }
-- the type tag of a row: its text and pill kind
local TAG = { dungeon = { "DUNGEON", "neutral" }, raid = { "RAID", "gold" }, zone = { "ZONE", "blue" } }

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
-- Every item of a place once: an instance's loot and quest rewards (as its loot lists them), a zone's mob drops.
local function InstanceItems(inst)
    local ids, seen = {}, {}
    for _, g in ipairs(Lists.BuildGroups(inst)) do
        for _, e in ipairs(g.entries) do
            if not seen[e.id] then
                seen[e.id] = true
                ids[#ids + 1] = e.id
            end
        end
    end
    return ids
end

local function ZoneItems(zone)
    local ids, seen = {}, {}
    for _, mob in ipairs(zone.mobs) do
        for _, d in ipairs(Items.GetMobDrops(mob.id) or {}) do
            if not seen[d.id] then
                seen[d.id] = true
                ids[#ids + 1] = d.id
            end
        end
    end
    return ids
end

local function Records()
    local list = {}
    for _, inst in ipairs(LJ.Data.Instances) do
        list[#list + 1] = { id = DB.InstanceID(inst.key), name = inst.name, kind = inst.kind, inst = inst,
            minLevel = inst.minLevel, maxLevel = inst.maxLevel, sub = inst.zone or "", items = InstanceItems(inst) }
    end
    for _, zone in ipairs(Items.GetWorldZones()) do
        list[#list + 1] = { id = DB.ZoneID(zone.map), name = zone.name, kind = "zone", zone = zone,
            minLevel = zone.minLevel, maxLevel = zone.maxLevel,
            sub = Util.Plural(zone.rares, "rare") .. " · " .. Util.Plural(#zone.mobs - zone.rares, "mob"),
            items = ZoneItems(zone) }
    end
    return list
end

-- The items of a place that are an upgrade for the character, the biggest first.
local function Upgrades(rec)
    local list = {}
    for _, id in ipairs(rec.items) do
        local up = BiS.Upgrade(id)
        if up then list[#list + 1] = { id = id, upgrade = up } end
    end
    table.sort(list, function(a, b)
        if a.upgrade ~= b.upgrade then return a.upgrade > b.upgrade end
        return a.id < b.id
    end)
    return list
end

local function Near(rec)
    if rec.inst then return Lists.IsNear(rec.inst) end
    return Lists.ZoneIsNear(rec.zone)
end

local function Passes(rec, state)
    if not state.kinds[rec.kind] then return false end
    if not DB.InLevels(state.level, rec.minLevel, rec.maxLevel) then return false end
    return not state.near or Near(rec)
end

local function Prepare(list, _, sort)
    if sort.key ~= "foryou" then return end
    for _, rec in ipairs(list) do rec.up = #Upgrades(rec) end
end

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function ByLevel(a, b)
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    if a.maxLevel ~= b.maxLevel then return a.maxLevel < b.maxLevel end
    return ByName(a, b)
end

local SORTS = {
    { key = "level", text = "Level", column = 3, compare = ByLevel },
    { key = "name", text = "Name", column = 1, compare = ByName },
    { key = "foryou", text = "For you", column = 4, compare = function(a, b)
        if a.up ~= b.up then return a.up > b.up end
        return ByLevel(a, b)
    end },
}

---------------------------------------------------------------------------
-- The row: the dungeon's icon or the globe, name and zone, type, level, upgrades
---------------------------------------------------------------------------
local function SetIcon(emblem, globe, rec)
    emblem:SetRare(false)
    emblem:SetGlyph("visor")
    emblem.glyph:Hide()
    globe:SetShown(rec.inst == nil)
    if rec.inst then
        emblem.portrait:Show()
        Theme.SetInstanceIcon(emblem.portrait, rec.inst)
    end
end

Kit.KINDS.dbPlace = {
    height = DB.ROW_HEIGHT,
    create = function(parent, sheet)
        local f = DB.CreateRow(parent)
        f.emblem = Widgets.CreateEmblem(f, DB.ICON)
        f.emblem:SetPoint("LEFT", sheet.page.cols.pos[1], 1)
        f.globe = Widgets.Glyph(f.emblem, "globe", 16, C.blueText, "OVERLAY", 2)
        f.globe:SetPoint("CENTER")
        f.tag = Widgets.CreatePill(f, 18, "pillTiny")
        f.level = DB.Cell(f, "chip")
        f.up = DB.Cell(f, "chip", "RIGHT")
        return f
    end,
    fill = function(f, rec)
        local page = f.sheet.page
        SetIcon(f.emblem, f.globe, rec)
        f.name:SetText(rec.name)
        f.name:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
        f.sub:SetText(rec.sub)
        DB.PlaceName(f, DB.ICON)
        local tag = TAG[rec.kind]
        f.tag:Set(tag[1], tag[2])
        f.tag:ClearAllPoints()
        f.tag:SetPoint("LEFT", f, "LEFT", page.cols.pos[2], 1)
        f.level:SetText(DB.LevelText(rec.minLevel, rec.maxLevel))
        Widgets.SetTextColor(f.level, Theme.RangeColor(rec.minLevel, rec.maxLevel))
        DB.PlaceCell(f, f.level, 3)
        local up = #Upgrades(rec)
        f.up:SetText(up > 0 and (Theme.GlyphString("upgrade", 10, C.okText) .. Theme.ColorText(up, C.okText)) or "")
        DB.PlaceCell(f, f.up, 4)
        f.selected = page.selected == rec.id
        f.hovered = f:IsMouseOver()
        DB.RowVisual(f)
    end,
}

---------------------------------------------------------------------------
-- The detail
---------------------------------------------------------------------------
local HERO = 126
local BEST = 5                      -- the best upgrades the detail lists

local function CreateDetail(page, panel)
    local hero = DB.Hero(panel, HERO)
    hero.art = hero:CreateTexture(nil, "BACKGROUND", nil, 2)
    hero.art:SetPoint("TOPLEFT", 1, -1)
    hero.art:SetPoint("BOTTOMRIGHT", -1, 1)
    hero.shade = Widgets.Solid(hero, "BACKGROUND", 3, { 0, 0, 0 }, 1)
    hero.shade:SetAllPoints(hero.art)
    hero.shade:SetGradient("VERTICAL", CreateColor(0.04, 0.05, 0.07, 0.95), CreateColor(0.04, 0.05, 0.07, 0.1))
    hero.emblem = Widgets.CreateEmblem(hero, 48)
    hero.emblem:SetPoint("TOPLEFT", 18, -14)
    hero.globe = Widgets.Glyph(hero.emblem, "globe", 26, C.blueText, "OVERLAY", 2)
    hero.globe:SetPoint("CENTER")
    hero.name = Widgets.Text(hero, "titleSmall", C.white)
    hero.name:SetPoint("BOTTOMLEFT", 18, 34)
    hero.name:SetPoint("RIGHT", -16, 0)
    hero.line = Widgets.Text(hero, "bodySmall", Theme.hex("D5DAE1"))
    hero.line:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -5)
    hero.line:SetPoint("RIGHT", -16, 0)
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
    hero:SetShown(rec ~= nil)
    page.actions:SetShown(rec ~= nil)
    if not rec then
        sheet:Add("empty", { title = L("No place picked"), text = L("Pick a dungeon, raid or zone in the list."), glyph = "castle" })
        sheet:Finish()
        return
    end
    local inst, zone = rec.inst, rec.zone
    -- the picture of a dungeon; a zone: the globe on the glass
    if inst then
        Theme.SetDungeonPicture(hero.art, inst, 302 / (HERO - 2))
        hero.art:Show()
        hero.shade:Show()
        hero.emblem:Hide()
        hero.glow:SetVertexColor(0, 0, 0, 0)
    else
        hero.art:Hide()
        hero.shade:Hide()
        hero.emblem:Show()
        SetIcon(hero.emblem, hero.globe, rec)
        hero.glow:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.22)
    end
    hero.name:SetText(Util.Upper(rec.name))
    local parts = { L(KIND_TEXT[rec.kind]), F("Level %s", DB.LevelText(rec.minLevel, rec.maxLevel)) }
    if inst and inst.zone then parts[#parts + 1] = inst.zone end
    hero.line:SetText(table.concat(parts, " · "))

    local spec = Player:GetActiveSpec()
    if inst then
        local lines = {}
        if inst.size then lines[#lines + 1] = F("%d players", inst.size) end
        lines[#lines + 1] = Util.Plural(#inst.bosses, "boss", "bosses") .. "  ·  " .. Util.Plural(inst.itemCount or 0, "item")
        local total, open = Quests.CountForInstance(inst.key)
        if total > 0 then lines[#lines + 1] = F("%d quests (%d open)", total, open) end
        if inst.statusText and inst.statusText ~= "" then lines[#lines + 1] = Theme.ColorText(inst.statusText, C.text3) end
        sheet:Add("dbBlock", { lines = lines })
        if #inst.bosses > 0 then
            sheet:Add("section", { text = L("Bosses"), count = #inst.bosses })
            for i, boss in ipairs(inst.bosses) do
                sheet:Add("dbSource", { text = boss.name, boss = boss, inst = inst,
                    sub = (boss.level and (F("Level %s", boss.level) .. " · ") or "") .. Util.Plural(#boss.loot, "item"),
                    onClick = function() DB.Go("mobs", DB.BossID(inst.key, i)) end })
            end
        end
    else
        local rares, others = {}, {}
        for _, mob in ipairs(zone.mobs) do
            if mob.isRare then rares[#rares + 1] = mob else others[#others + 1] = mob end
        end
        for _, group in ipairs({ { "Rares", rares }, { "Mobs", others } }) do
            if #group[2] > 0 then
                sheet:Add("section", { text = L(group[1]), count = #group[2] })
                for _, mob in ipairs(group[2]) do
                    sheet:Add("dbSource", { text = mob.name, display = mob.display, emblem = Theme.BossEmblem(mob), rare = mob.isRare,
                        sub = F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel)) .. " · "
                            .. Util.Plural(#(Items.GetMobDrops(mob.id) or {}), "drop"),
                        onClick = function() DB.Go("mobs", DB.WorldMobID(mob.id)) end })
                end
            end
        end
    end

    -- the best upgrades for the character there
    local best = Upgrades(rec)
    if #best > 0 then
        sheet:Add("section", { text = L("Best for you"), count = #best })
        local cells = {}
        for i = 1, math.min(BEST, #best) do
            cells[i] = Kit.ItemData(best[i].id, spec, { onClick = function(x) DB.Go("items", x.id) end })
        end
        sheet:Grid("item", cells, 1, Kit.M().item)
    end
    sheet:Finish(8)

    -- the map: a dungeon's entrance, a zone's map; the quests and mobs of the place
    local main
    if inst then
        local e = inst.entrance
        local spot = e and { map = e.map, x = e.x, y = e.y, title = inst.name, detail = L("Dungeon entrance") }
        local marked = spot and MapPin.IsTarget(spot)
        main = { text = marked and "Marked" or "Show the entrance", glyph = marked and "check" or "mapPin", disabled = spot == nil,
            tooltip = marked and "Marked on your map" or "Show on the map",
            tooltipText = marked and "Click to remove the mark." or "Opens the world map and sets a marker at the dungeon's entrance.",
            onClick = function()
                if MapPin.IsTarget(spot) then MapPin.Clear() else MapPin.Show(spot) end
            end }
    else
        main = { text = "Open the map", glyph = "map", tooltip = "Open the map", tooltipText = "Opens the world map on this zone.",
            onClick = function() MapPin.OpenZone(zone.map) end }
    end
    local icons = {}
    if inst and LJ.DungeonMap.Get(inst) then
        icons[#icons + 1] = { glyph = "map", tooltip = "Dungeon map", tooltipText = "Opens the dungeon's map with its bosses.",
            onClick = function() LJ.DungeonMap.ShowWindow(inst) end }
    end
    icons[#icons + 1] = { glyph = "scroll", tooltip = "Quests", tooltipText = "Its quests on the Quests page.",
        onClick = function() DB.Go("quests", nil, rec.name) end }
    icons[#icons + 1] = { glyph = "skull", tooltip = "Mobs", tooltipText = "Its bosses and mobs on the Mobs page.",
        onClick = function() DB.Go("mobs", nil, rec.name) end }
    DB.SetActions(page.actions, main, icons)
end

DB.Page({
    key = "places", scope = "Places", placeholder = "Search dungeons, raids, zones",
    toggle = { key = "near", label = "Near my level", tooltip = "Only places around your character's level." },
    sorts = SORTS,
    filters = {
        { key = "kinds", label = "Type", kind = "multi", options = KINDS },
        { key = "level", label = "Level", kind = "range" },
    },
    -- (the level column's title is a text of its own: a language can write it shorter than the filter's "Level")
    columns = { { title = "Place" }, { title = "Type", width = 64, tags = { "DUNGEON", "RAID", "ZONE" } },
        { title = "LEVEL", width = 50 }, { title = "For you", width = 50, justify = "RIGHT" } },
    rowKind = "dbPlace", icon = DB.ICON,
    Records = Records, Passes = Passes, Prepare = Prepare,
    -- a dungeon by its names (German and English), its zone and its slash command words
    SearchKey = function(rec)
        local inst = rec.inst
        if not inst then return DB.SearchKey(rec.name) end
        return inst.searchKey .. " " .. DB.SearchKey(inst.zone, table.concat(inst.slash or {}, " "))
    end,
    CreateDetail = CreateDetail, FillDetail = FillDetail,
})
