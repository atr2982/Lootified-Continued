-- Lootified - the database's Mobs page: every boss of the dungeons and raids and every open world mob with drops
-- (rares too). Filters: type, level, where; "With upgrades for me" keeps the mobs that drop an upgrade for the
-- character. The picked mob: its face, level and place, a map button (the dungeon's entrance, the mob's camps), and its
-- drops with their chances and the upgrades.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local DB = LJ.Database
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local Lists = LJ.Lists
local MapPin = LJ.MapPin
local BiS = LJ.BiS
local C = Theme.COLORS

local KINDS = {
    { key = "boss", text = "Boss" },
    { key = "rare", text = "Rare" },
    { key = "elite", text = "Elite" },
    { key = "normal", text = "Normal" },
}
local KIND_TEXT = {}
for _, k in ipairs(KINDS) do KIND_TEXT[k.key] = k.text end
-- the type tag of a row: its text and pill kind
local TAG = { boss = { "BOSS", "gold" }, rare = { "RARE", "rare" }, elite = { "ELITE", "neutral" }, normal = { "NORMAL", "gray" } }

local WHERE = {
    { key = "dungeon", text = "Dungeons", glyph = "castle" },
    { key = "raid", text = "Raids", glyph = "crown" },
    { key = "world", text = "Open world", glyph = "globe" },
}

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
-- "19", "19-20", "??": the level range of a boss (nil when it is not known).
local function BossLevels(boss)
    local lo, hi = tostring(boss.level or ""):match("^(%d+)%-?(%d*)$")
    lo = tonumber(lo)
    return lo, tonumber(hi) or lo
end

local function Records()
    local list = {}
    for _, inst in ipairs(LJ.Data.Instances) do
        for i, boss in ipairs(inst.bosses) do
            local lo, hi = BossLevels(boss)
            local drops = {}
            for j, id in ipairs(boss.loot) do drops[j] = { id = id, chance = boss.chance and boss.chance[j] or nil } end
            list[#list + 1] = { id = DB.BossID(inst.key, i), name = boss.name, kind = boss.rare and "rare" or "boss",
                where = inst.kind, inst = inst, boss = boss, index = i, minLevel = lo, maxLevel = hi, place = inst.name,
                placeID = DB.InstanceID(inst.key), drops = drops }
        end
    end
    for _, zone in ipairs(Items.GetWorldZones()) do
        for _, mob in ipairs(zone.mobs) do
            local kind = (mob.isRare and "rare") or (mob.rank == 3 and "boss") or (mob.rank == 1 and "elite") or "normal"
            list[#list + 1] = { id = DB.WorldMobID(mob.id), name = mob.name, kind = kind, where = "world", mob = mob,
                minLevel = mob.minLevel, maxLevel = mob.maxLevel, place = zone.name, placeID = DB.ZoneID(zone.map),
                drops = Items.GetMobDrops(mob.id) or {} }
        end
    end
    return list
end

-- The number of a mob's drops that are an upgrade for the character.
local function Upgrades(rec)
    local n = 0
    for _, d in ipairs(rec.drops) do
        if BiS.Upgrade(d.id) then n = n + 1 end
    end
    return n
end

local function Passes(rec, state)
    if not state.kinds[rec.kind] or not state.where[rec.where] then return false end
    if not DB.InLevels(state.level, rec.minLevel, rec.maxLevel) then return false end
    return not state.upgrades or Upgrades(rec) > 0
end

local function Prepare(list, _, sort)
    if sort.key ~= "foryou" then return end
    for _, rec in ipairs(list) do rec.up = Upgrades(rec) end
end

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function ByLevel(a, b)
    local la, lb = a.minLevel or 99, b.minLevel or 99
    if la ~= lb then return la < lb end
    return ByName(a, b)
end

local SORTS = {
    { key = "level", text = "Level", column = 3, compare = ByLevel },
    { key = "name", text = "Name", column = 1, compare = ByName },
    { key = "drops", text = "Drops", column = 4, compare = function(a, b)
        if #a.drops ~= #b.drops then return #a.drops > #b.drops end
        return ByLevel(a, b)
    end },
    { key = "foryou", text = "For you", column = 4, compare = function(a, b)
        if a.up ~= b.up then return a.up > b.up end
        return ByLevel(a, b)
    end },
}

---------------------------------------------------------------------------
-- The row: face, name and place, type, level, drops (with the upgrades)
---------------------------------------------------------------------------
local function SetFace(emblem, rec)
    if rec.boss then
        emblem:SetBoss(rec.boss)
    else
        emblem:SetRare(rec.mob.isRare)
        emblem:SetCreature(rec.mob.display, Theme.BossEmblem(rec.mob))
    end
end

Kit.KINDS.dbMob = {
    height = DB.ROW_HEIGHT,
    create = function(parent, sheet)
        local f = DB.CreateRow(parent)
        f.emblem = Widgets.CreateEmblem(f, DB.ICON)
        f.emblem:SetPoint("LEFT", sheet.page.cols.pos[1], 1)
        f.tag = Widgets.CreatePill(f, 18, "pillTiny")
        f.level = DB.Cell(f, "chip")
        f.drops = DB.Cell(f, "chip", "RIGHT")
        return f
    end,
    fill = function(f, rec)
        local page = f.sheet.page
        local cols = page.cols
        SetFace(f.emblem, rec)
        f.name:SetText(rec.name)
        f.name:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
        f.sub:SetText(rec.place)
        DB.PlaceName(f, DB.ICON)
        local tag = TAG[rec.kind]
        f.tag:Set(L(tag[1]), tag[2])
        f.tag:ClearAllPoints()
        f.tag:SetPoint("LEFT", f, "LEFT", cols.pos[2], 1)
        f.level:SetText(DB.LevelText(rec.minLevel, rec.maxLevel))
        DB.PlaceCell(f, f.level, 3)
        local up = Upgrades(rec)
        f.drops:SetText(tostring(#rec.drops) .. (up > 0 and ("  " .. Theme.GlyphString("upgrade", 10, C.okText) .. Theme.ColorText(up, C.okText)) or ""))
        DB.PlaceCell(f, f.drops, 4)
        f.selected = page.selected == rec.id
        f.hovered = f:IsMouseOver()
        DB.RowVisual(f)
    end,
}

---------------------------------------------------------------------------
-- The detail
---------------------------------------------------------------------------
local HERO = 104

-- The map spot of a mob: a boss's dungeon entrance; an open world mob: Lists.MarkNextCamp walks through its camps.
local function EntranceSpot(inst)
    local e = inst.entrance
    if e then return { map = e.map, x = e.x, y = e.y, title = inst.name, detail = L("Dungeon entrance") } end
end

local function CreateDetail(page, panel)
    local hero = DB.Hero(panel, HERO)
    hero.emblem = Widgets.CreateEmblem(hero, 58)
    hero.emblem:SetPoint("TOPLEFT", 18, -20)
    hero.name = Widgets.Text(hero, "titleSmall", C.white)
    hero.name:SetPoint("TOPLEFT", hero.emblem, "TOPRIGHT", 14, -2)
    hero.name:SetPoint("RIGHT", -16, 0)
    hero.name:SetWordWrap(true)
    hero.name:SetMaxLines(2)
    hero.line = Widgets.Text(hero, "bodySmall", DB.TEXT)
    hero.line:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -5)
    hero.line:SetPoint("RIGHT", -16, 0)
    hero.line:SetWordWrap(true)
    hero.line:SetMaxLines(2)
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
        sheet:Add("empty", { title = L("No mob picked"), text = L("Pick a mob in the list to see what it drops."), glyph = "skull" })
        sheet:Finish()
        return
    end
    SetFace(hero.emblem, rec)
    local tint = rec.kind == "rare" and C.rare or Theme.accent
    hero.glow:SetVertexColor(tint[1], tint[2], tint[3], 0.22)
    hero.name:SetText(Util.Upper(rec.name))
    local parts = { Theme.ColorText(L(KIND_TEXT[rec.kind]), rec.kind == "rare" and C.rare or (rec.kind == "boss" and C.goldText or DB.TEXT)) }
    if rec.minLevel then parts[#parts + 1] = F("Level %s", DB.LevelText(rec.minLevel, rec.maxLevel)) end
    parts[#parts + 1] = rec.place
    if rec.boss then
        parts[#parts + 1] = F("Boss %d of %d", rec.index, #rec.inst.bosses)
    elseif #rec.mob.locs > 0 then
        parts[#parts + 1] = Util.Plural(#rec.mob.locs, "camp")
    end
    hero.line:SetText(table.concat(parts, " · "))

    -- the drops: the upgrades first (the biggest first), then in the order of the loot list
    local spec = Player:GetActiveSpec()
    local cells = {}
    for i, d in ipairs(rec.drops) do
        cells[i] = Kit.ItemData(d.id, spec, { chance = d.chance, order = i,
            onClick = function(x) DB.Go("items", x.id) end })
    end
    table.sort(cells, function(a, b)
        local ua, ub = a.upgrade ~= nil, b.upgrade ~= nil
        if ua ~= ub then return ua end
        if ua and a.upgrade ~= b.upgrade then return a.upgrade > b.upgrade end
        return a.order < b.order
    end)
    sheet:Add("section", { text = L("Drops"), count = #cells })
    if #cells > 0 then
        sheet:Grid("item", cells, 1, Kit.M().item)
    else
        sheet:Add("text", { text = L("No drops are known for it yet."), font = "bodySmall", color = C.text3 })
    end
    if rec.mob then
        sheet:Add("section", { text = L("Good to know") })
        local notes = {}
        if rec.mob.isRare then notes[#notes + 1] = L("Rare spawn: it is not always up. The map button marks its camps.") end
        notes[#notes + 1] = L("Open world drop chances and spawn points are the Classic values and can differ in WoW: Forever.")
        sheet:Add("text", { text = table.concat(notes, " "), font = "bodySmall", color = C.text2, spacing = 3 })
    end
    sheet:Finish(8)

    -- the map: the dungeon's entrance or the mob's camps; the place
    local main
    if rec.boss then
        local spot = EntranceSpot(rec.inst)
        local marked = spot and MapPin.IsTarget(spot)
        main = { text = marked and "Marked" or "Show the entrance", glyph = marked and "check" or "mapPin", disabled = spot == nil,
            tooltip = marked and "Marked on your map" or "Show on the map",
            tooltipText = marked and "Click to remove the mark." or "Opens the world map and sets a marker at the dungeon's entrance.",
            onClick = function()
                if MapPin.IsTarget(spot) then MapPin.Clear() else MapPin.Show(spot) end
            end }
    else
        local label, glyph, title, tip, canMark = Lists.MapButtonState(rec.mob)
        main = { text = glyph == "mapPin" and "Show on map" or label, glyph = glyph, disabled = not canMark, tooltip = title,
            tooltipText = tip, onClick = function() Lists.MarkNextCamp(rec.mob) end }
    end
    DB.SetActions(page.actions, main, {
        { glyph = rec.boss and "castle" or "globe", tooltip = rec.place, tooltipText = "Opens it on the Places page.",
            onClick = function() DB.Go("places", rec.placeID) end },
    })
end

DB.Page({
    key = "mobs", scope = "Mobs", placeholder = "Search mobs, bosses, places",
    toggle = { key = "upgrades", label = "With upgrades for me", tooltip = "Only mobs that drop an upgrade for your character.",
        module = "bis" },
    sorts = SORTS,
    filters = {
        { key = "kinds", label = "Type", kind = "multi", options = KINDS },
        { key = "level", label = "Level", kind = "range" },
        { key = "where", label = "Where", kind = "multi", options = WHERE },
    },
    columns = { { title = "Mob" }, { title = "Type", width = 54, tags = { "BOSS", "RARE", "ELITE", "NORMAL" } },
        { title = "Lv", width = 40 },
        { title = "Drops", width = 56, justify = "RIGHT" } },
    rowKind = "dbMob", icon = DB.ICON,
    Records = Records, Passes = Passes, Prepare = Prepare,
    SearchKey = function(rec) return DB.SearchKey(rec.name, rec.place) end,
    CreateDetail = CreateDetail, FillDetail = FillDetail,
    Empty = function(state)
        return state.upgrades and "No mob drops an upgrade for you with these filters." or "Nothing matches the search and the filters."
    end,
})
