-- Lootified - the dungeon map: Blizzard's own map of the dungeon from the game client (the Forever client has the art
-- but shows none of it), or for the new Forever dungeons Santiago Reyes' maps shipped with the addon (Data/FanMaps.lua,
-- credited under the map), one floor at a time, with the bosses as their faces (a number badge gives the order; a boss
-- without a known face is a numbered disc) and the entrances marked. It opens in its own
-- window ("Dungeon map" on a dungeon's page) that can be moved and sized; a boss clicked on it unfolds its loot.
-- Data/DungeonMaps.lua names the art and where the bosses and entrances are on each floor.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local BiS = LJ.BiS
local C = Theme.COLORS

local DungeonMap = {}
LJ.DungeonMap = DungeonMap

-- the tiles of Blizzard's art: 4 x 3 tiles of 256, drawn 1002 x 668 { columns, rows, width, height, tile size }; a map
-- shipped with the addon names its own (data.grid)
local BLIZZARD_GRID = { 4, 3, 1002, 668, 256 }
local MAX_TILES = 12
local BAR = 32                   -- the row above the map of a dungeon with floors: floor buttons, floor name
local CAPTION = 22
local MARKER = 18                -- an entrance, a boss without a face
local FACE = 30                  -- a boss with a face
local BADGE = 14                 -- the number badge on a face
local FOCUS = 1.4                -- a highlighted or selected boss marker grows by this

-- Path of a tile (1-12) of a floor (0: a map without floors) of the art { folder, file prefix, addon = shipped with
-- the addon (Media\Maps) instead of the game client's Interface\WorldMap }.
local function TilePath(art, floor, tile)
    local root = art.addon and (LJ.MEDIA .. "Maps\\") or "Interface\\WorldMap\\"
    return root .. art[1] .. "\\" .. art[2] .. (floor > 0 and (floor .. "_") or "") .. tile
end
DungeonMap.TilePath = TilePath

local function Grid(data)
    return data.grid or BLIZZARD_GRID
end

-- The map's height for a width (the art keeps its proportions).
local function MapHeight(data, width)
    local grid = Grid(data)
    return width * grid[4] / grid[3]
end

-- The art of a map (the first of data.art the client has; the addon's own art is always there), false when there is
-- none. Checked once per session.
local function ResolveArt(data)
    if data.resolved == nil then
        data.resolved = false
        for _, art in ipairs(data.art) do
            if art.addon or Util.FileExists(TilePath(art, data.floors[1], 1)) then
                data.resolved = art
                break
            end
        end
    end
    return data.resolved
end

-- The map of an instance, nil for the ones without (the new Forever dungeons, or art the client lacks).
function DungeonMap.Get(inst)
    local data = inst and LJ.Data.DungeonMaps and LJ.Data.DungeonMaps[inst.key]
    if data and ResolveArt(data) then return data end
    return nil
end

-- Name of a floor: the map's own (data.names), the game's own (DUNGEON_FLOOR_...), "Floor n" where neither has one.
function DungeonMap.FloorName(data, floor)
    if data.names and data.names[floor] then return L(data.names[floor]) end
    local name = _G["DUNGEON_FLOOR_" .. data.key .. (floor > 0 and floor or "")]
    if type(name) == "string" and name ~= "" then return name end
    return F("Floor %d", floor)
end

-- Number of bosses with a marker on a floor.
local function BossesOn(data, floor)
    local n = 0
    for _, spots in pairs(data.s) do
        for i = 1, #spots, 3 do
            if spots[i] == floor then
                n = n + 1
                break
            end
        end
    end
    return n
end

local Map = {}

local function MarkerTooltip(marker, title, line)
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(L(line), 0.7, 0.72, 0.76, true) end
    GameTooltip:Show()
end

local function HideTooltip(marker)
    if GameTooltip:GetOwner() == marker then GameTooltip:Hide() end
end

function Map:BossMarker(i)
    local b = self.bossMarkers[i]
    if b then return b end
    b = CreateFrame("Button", nil, self.canvas)
    b.bg = b:CreateTexture(nil, "ARTWORK", nil, 0)
    b.bg:SetTexture(Theme.TEX.circle)
    b.bg:SetAllPoints()
    b.face = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.face:SetPoint("TOPLEFT", 2, -2)
    b.face:SetPoint("BOTTOMRIGHT", -2, 2)
    b.mask = b:CreateMaskTexture()
    b.mask:SetTexture(Theme.TEX.maskCircle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.mask:SetAllPoints(b.face)
    b.face:AddMaskTexture(b.mask)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture(Theme.TEX.circleRingThin)
    b.ring:SetAllPoints()
    b.num = Widgets.Text(b, "tiny", C.dark, nil, "CENTER")
    b.num:SetPoint("CENTER", 0, 0)
    -- the number badge at the bottom right of a face
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(BADGE, BADGE)
    b.badge:SetPoint("CENTER", b, "BOTTOMRIGHT", -3, 3)
    b.badge.bg = b.badge:CreateTexture(nil, "ARTWORK")
    b.badge.bg:SetTexture(Theme.TEX.circle)
    b.badge.bg:SetAllPoints()
    b.badge.ring = b.badge:CreateTexture(nil, "OVERLAY")
    b.badge.ring:SetTexture(Theme.TEX.circleRingThin)
    b.badge.ring:SetAllPoints()
    b.badge.ring:SetVertexColor(0, 0, 0, 0.8)
    b.badge.num = Widgets.Text(b.badge, "tiny", C.dark, nil, "CENTER")
    b.badge.num:SetPoint("CENTER", 0, 0)
    self:MarkerColors(b, Theme.accent[1], Theme.accent[2], Theme.accent[3])
    b:SetScript("OnEnter", function(m)
        self:HighlightBoss(m.index, true)
        if self.onHover then self.onHover(m.index) end
        -- markerHint(index): the tooltip line of a map that does something else with the click (the window)
        MarkerTooltip(m, m.boss and m.boss.name or "", self.markerHint and self.markerHint(m.index)
            or "Click to show the loot.")
    end)
    b:SetScript("OnLeave", function(m)
        self:HighlightBoss(nil)
        if self.onHover then self.onHover(nil) end
        HideTooltip(m)
    end)
    b:SetScript("OnClick", function(m)
        GameTooltip:Hide()
        if self.onBoss and m.index then self.onBoss(m.index) end
    end)
    self.bossMarkers[i] = b
    return b
end

-- The accent colors of a boss marker: the disc of a numbered one, the ring of a face and its badge.
function Map:MarkerColors(b, r, g, bl)
    b.badge.bg:SetVertexColor(r, g, bl, 1)
    if b.size == FACE then
        b.bg:SetVertexColor(0.05, 0.06, 0.08, 1)
        b.ring:SetVertexColor(r, g, bl, 1)
    else
        b.bg:SetVertexColor(r, g, bl, 1)
        b.ring:SetVertexColor(0, 0, 0, 0.7)
    end
end

-- Shows a boss on its marker: its face with the number in the badge, a numbered disc without a known face.
function Map:SetMarkerBoss(b, index, boss)
    b.index, b.boss = index, boss
    local display = boss.display
    b.num:SetText(tostring(index))
    b.badge.num:SetText(tostring(index))
    b.size = display and FACE or MARKER
    if display then SetPortraitTextureFromCreatureDisplayID(b.face, display) end
    b.face:SetShown(display ~= nil)
    b.badge:SetShown(display ~= nil)
    b.num:SetShown(display == nil)
    b:SetSize(b.size, b.size)
    self:MarkerColors(b, Theme.accent[1], Theme.accent[2], Theme.accent[3])
end

function Map:EntryMarker(i)
    local e = self.entryMarkers[i]
    if e then return e end
    e = CreateFrame("Frame", nil, self.canvas)
    e:SetSize(MARKER, MARKER)
    e.bg = e:CreateTexture(nil, "ARTWORK")
    e.bg:SetTexture(Theme.TEX.circle)
    e.bg:SetAllPoints()
    e.bg:SetVertexColor(0.05, 0.06, 0.08, 0.92)
    e.ring = e:CreateTexture(nil, "OVERLAY")
    e.ring:SetTexture(Theme.TEX.circleRingThin)
    e.ring:SetAllPoints()
    -- on the dark disc over the map art: the same bright green in every look
    local green = Theme.hex("6EE7A0")
    e.ring:SetVertexColor(green[1], green[2], green[3], 1)
    e.glyph = Widgets.Glyph(e, "flag", 10, green, "OVERLAY", 2)
    e.glyph:SetPoint("CENTER")
    e:EnableMouse(true)
    e:SetScript("OnEnter", function(m) MarkerTooltip(m, L("Entrance")) end)
    e:SetScript("OnLeave", HideTooltip)
    self.entryMarkers[i] = e
    return e
end

function Map:FloorButton(i)
    local b = self.floorButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, self.bar)
    b:SetSize(26, 22)
    b.panel = Widgets.CreatePanel(b, 6, "BACKGROUND", 0)
    b.text = Widgets.Text(b, "small", C.text2, nil, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b:SetScript("OnEnter", function(m)
        m.hovered = true
        self:FloorButtonVisual(m)
        local data = self.data
        GameTooltip:SetOwner(m, "ANCHOR_TOP")
        GameTooltip:SetText(DungeonMap.FloorName(data, m.floor), 1, 1, 1)
        local n = BossesOn(data, m.floor)
        if n > 0 then GameTooltip:AddLine(Util.Plural(n, "boss", "bosses"), 0.7, 0.72, 0.76) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(m)
        m.hovered = false
        self:FloorButtonVisual(m)
        HideTooltip(m)
    end)
    b:SetScript("OnClick", function(m)
        Util.PlaySound("IG_MAINMENU_OPTION")
        self:ShowFloor(m.floor)
    end)
    self.floorButtons[i] = b
    return b
end

function Map:FloorButtonVisual(b)
    local a = Theme.accent
    if b.floor == self.floor then
        b.panel:SetFill(a[1], a[2], a[3], 0.9)
        b.panel:SetBorder(a[1], a[2], a[3], 1)
        Widgets.SetTextColor(b.text, C.dark)
    else
        local hover = Widgets.Hover(b)
        b.panel:SetFill(1, 1, 1, hover and 0.1 or 0.04)
        b.panel:SetBorder(1, 1, 1, hover and 0.14 or 0.07)
        Widgets.SetTextColor(b.text, hover and C.text1 or C.text3)
    end
end

-- Places a marker at a spot of the map (x, y 0-1 from the top left), dx units to the right of it.
function Map:Place(region, x, y, dx)
    region:ClearAllPoints()
    region:SetPoint("CENTER", self.canvas, "TOPLEFT", x * self.mapW + (dx or 0), -y * self.mapH)
    region:Show()
end

-- Shows a floor: its art, its bosses and entrances, the floor buttons, the hint below the map.
function Map:ShowFloor(floor)
    local data, inst = self.data, self.inst
    self.floor = floor
    self.floorOf[inst.key] = floor
    local art = ResolveArt(data)
    local count = Grid(data)[1] * Grid(data)[2]
    for i = 1, count do self.tiles[i]:SetTexture(TilePath(art, floor, i)) end
    -- bosses on one spot (Sneed in his Shredder, rares that share their spots) stand in a row beside each other
    local n = 0
    local taken = {}                  -- ["x:y"] = markers on that spot so far
    local indices = {}
    for index in pairs(data.s) do indices[#indices + 1] = index end
    table.sort(indices)
    for _, index in ipairs(indices) do
        local spots = data.s[index]
        for i = 1, #spots, 3 do
            if spots[i] == floor then
                n = n + 1
                local b = self:BossMarker(n)
                self:SetMarkerBoss(b, index, inst.bosses[index])
                local key = spots[i + 1] .. ":" .. spots[i + 2]
                local before = taken[key] or 0
                taken[key] = before + 1
                self:Place(b, spots[i + 1], spots[i + 2], before * b.size * 0.85)
            end
        end
    end
    for i = n + 1, #self.bossMarkers do
        self.bossMarkers[i]:Hide()
        self.bossMarkers[i].index, self.bossMarkers[i].boss = nil, nil
    end
    -- the hint below the map only on a floor with bosses to click
    self.caption:SetText(n > 0 and L("Click a boss to see its loot.") or "")
    n = 0
    local e = data.e
    for i = 1, #e, 3 do
        if e[i] == floor then
            n = n + 1
            self:Place(self:EntryMarker(n), e[i + 1], e[i + 2])
        end
    end
    for i = n + 1, #self.entryMarkers do self.entryMarkers[i]:Hide() end
    for _, b in ipairs(self.floorButtons) do
        if b:IsShown() then self:FloorButtonVisual(b) end
    end
    self.floorName:SetText(#data.floors > 1 and DungeonMap.FloorName(data, floor) or "")
    self:HighlightBoss(self.highlighted, true)
end

-- Enlarges the markers of a boss (nil: none), e.g. while the boss is under the mouse in the loot list. A boss on
-- another floor brings its floor up first (stay = true: the floor stays). The selected boss (Map:FocusBoss) stays
-- large.
function Map:HighlightBoss(index, stay)
    self.highlighted = index
    local spots = index and self.data and self.data.s[index]
    if spots and not stay then
        local here = false
        for i = 1, #spots, 3 do
            if spots[i] == self.floor then here = true end
        end
        if not here then
            self:ShowFloor(spots[1])
            return
        end
    end
    local base = self.canvas:GetFrameLevel()
    for _, b in ipairs(self.bossMarkers) do
        local on = b.index ~= nil and (b.index == index or b.index == self.selected)
        local size = b.size * (on and FOCUS or 1)
        b:SetSize(size, size)
        b:SetFrameLevel(base + (on and 8 or 6))
    end
end

-- Selects a boss (nil: none): its markers stay large, and its floor comes up.
function Map:FocusBoss(index)
    self.selected = index
    local spots = index and self.data and self.data.s[index]
    if spots then
        local here = false
        for i = 1, #spots, 3 do
            if spots[i] == self.floor then here = true end
        end
        if not here then
            self:ShowFloor(spots[1])
            return
        end
    end
    self:HighlightBoss(self.highlighted, true)
end

-- Lays the map out for an instance at a width; returns the height it takes (0 when the instance has no map).
-- onBoss(index) is called when a boss marker is clicked, onHover(index or nil) when the mouse enters or leaves one.
function Map:SetMap(inst, width, onBoss, onHover)
    local data = DungeonMap.Get(inst)
    self.onBoss, self.onHover = onBoss, onHover
    if self.inst ~= inst then self.selected = nil end
    self.inst, self.data = inst, data
    if not data then
        self:Hide()
        return 0
    end
    local grid = Grid(data)
    local cols, count, artW, artH, tile = grid[1], grid[1] * grid[2], grid[3], grid[4], grid[5]
    local scale = width / artW
    self.mapW, self.mapH = width, MapHeight(data, width)
    local floors = #data.floors > 1
    local bar = floors and BAR or 0
    self.bar:SetShown(floors)
    self.box:ClearAllPoints()
    self.box:SetPoint("TOPLEFT", 0, -bar)
    self.box:SetSize(width, self.mapH)
    for i, t in ipairs(self.tiles) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local w, h = math.min(tile, artW - col * tile), math.min(tile, artH - row * tile)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", col * tile * scale, -row * tile * scale)
        t:SetSize(w * scale, h * scale)
        t:SetTexCoord(0, w / tile, 0, h / tile)
        t:SetShown(i <= count)
    end
    self.credit:SetText(data.credit and F("Map: %s", data.credit) or "")
    -- floor buttons in the order of the floors (maps with more than one), the name of the shown one beside them
    local x, shown = 0, floors and #data.floors or 0
    for i = 1, shown do
        local b = self:FloorButton(i)
        b.floor = data.floors[i]
        b.text:SetText(tostring(b.floor))
        b:ClearAllPoints()
        b:SetPoint("LEFT", self.bar, "LEFT", x, 0)
        b:Show()
        x = x + 30
    end
    for i = shown + 1, #self.floorButtons do self.floorButtons[i]:Hide() end
    self.floorName:ClearAllPoints()
    self.floorName:SetPoint("LEFT", self.bar, "LEFT", x + 6, 0)
    self.floorName:SetPoint("RIGHT", self.bar, "RIGHT", 0, 0)
    -- the floor last shown for this dungeon, else the one with the entrance
    local floor = self.floorOf[inst.key]
    local known = false
    for _, f in ipairs(data.floors) do
        if f == floor then known = true end
    end
    self.highlighted = nil
    self:ShowFloor(known and floor or data.first)
    self:SetSize(width, bar + self.mapH + CAPTION)
    self:Show()
    return bar + self.mapH + CAPTION
end

function DungeonMap.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    for k, v in pairs(Map) do f[k] = v end
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetPoint("TOPLEFT")
    f.bar:SetPoint("TOPRIGHT")
    f.bar:SetHeight(BAR - 6)
    f.floorName = Widgets.Text(f.bar, "nameBold", C.text1)
    f.box = CreateFrame("Frame", nil, f)
    f.box.panel = Widgets.CreatePanel(f.box, 4, "BACKGROUND", 0)
    f.box.panel:SetFill(0, 0, 0, 0.35)
    f.box.panel:SetBorder(1, 1, 1, 0.08)
    f.canvas = CreateFrame("Frame", nil, f.box)
    f.canvas:SetAllPoints()
    f.tiles = {}
    for i = 1, MAX_TILES do f.tiles[i] = f.canvas:CreateTexture(nil, "ARTWORK", nil, -1) end
    f.bossMarkers, f.entryMarkers, f.floorButtons, f.floorOf = {}, {}, {}, {}
    f.caption = Widgets.Text(f, "small", C.text4)
    -- the credit of a map shipped with the addon, at the right of the hint row
    f.credit = Widgets.Text(f, "small", C.text4, nil, "RIGHT")
    f.credit:SetPoint("TOPRIGHT", f.box, "BOTTOMRIGHT", -2, -6)
    f.caption:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 2, -6)
    f.caption:SetPoint("RIGHT", f.credit, "LEFT", -8, 0)
    Theme.OnAccent(f, function(m, r, g, b)
        for _, marker in ipairs(m.bossMarkers) do m:MarkerColors(marker, r, g, b) end
        for _, button in ipairs(m.floorButtons) do
            if button:IsShown() then m:FloorButtonVisual(button) end
        end
    end)
    return f
end


---------------------------------------------------------------------------
-- The window: the map in a window you can move (its title row) and size (the grip at the bottom right: the height
-- follows the width, the map keeps its proportions). A click on a boss unfolds its loot in a panel beside the window
-- (a second click, or the panel's close button, folds it away). Place and size are kept. The window follows the
-- dungeon picked in the journal and is built again after a switch of the window look.
---------------------------------------------------------------------------
local PAD = 16
local TOP = 46            -- the title row
local BOTTOM = 10         -- below the hint under the map
local MAP_W = 720         -- the map's width at first
local MIN_MAP = 420       -- the smallest map
local LOOT_W = 400        -- the loot panel beside the window
local LOOT_HEAD = 60      -- the panel's head: the boss and its drops
local window
local mapTour           -- the window's own tour (below), made the first time it runs

local function Bar(w)
    local data = DungeonMap.Get(w.inst)
    return data and #data.floors > 1 and BAR or 0
end

-- The window's height for a width: the map at that width with its proportions, the rows above and below it.
local function HeightFor(w, width)
    return math.floor(TOP + Bar(w) + MapHeight(DungeonMap.Get(w.inst), width - 2 * PAD) + CAPTION + BOTTOM + 0.5)
end

-- The widest window the screen has room for (in the window's own units).
local function MaxWidth(w)
    local s = w:GetScale() or 1
    local sw, sh = UIParent:GetWidth() / s, UIParent:GetHeight() / s
    local byHeight = (sh - TOP - Bar(w) - CAPTION - BOTTOM) / MapHeight(DungeonMap.Get(w.inst), 1) + 2 * PAD
    return math.floor(math.min(sw, byHeight))
end

-- Anchors the window by its top left corner (its height changes with the width: the top stays).
local function AnchorTopLeft(w)
    local left, top = w:GetLeft(), w:GetTop()
    if not (left and top) then return end
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function SaveWindow(w)
    local left, top = w:GetLeft(), w:GetTop()
    if not (left and top) then return end
    LJ.db.mapWindow = { left = left, top = top, width = w:GetWidth() }
end

-- The loot panel beside the window: right of it where the screen has room, else left of it, else over the map's right
-- part. unfold 0..1: slides out and fades in.
local function ChooseSide(w)
    local s = w:GetEffectiveScale()
    local screen = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    local need = (LOOT_W + 8) * s
    local right = screen - (w:GetRight() or 0) * s
    local left = (w:GetLeft() or 0) * s
    w.lootSide = (right >= need and "right") or (left >= need and "left") or "inside"
end

local function PlaceLoot(w, unfold)
    local loot = w.loot
    local slide = (1 - unfold) * 24
    loot:SetAlpha(unfold)
    loot:ClearAllPoints()
    if w.lootSide == "right" then
        loot:SetPoint("TOPLEFT", w, "TOPRIGHT", 8 - slide, -TOP)
    elseif w.lootSide == "left" then
        loot:SetPoint("TOPRIGHT", w, "TOPLEFT", -8 + slide, -TOP)
    else
        loot:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD + slide, -TOP)
    end
end

-- The selected boss's loot in the panel; the panel is as tall as its rows need (at most the window).
local function FillLoot(w)
    local loot, inst, index = w.loot, w.inst, w.selected
    local boss = index and inst.bosses[index]
    if not boss then return end
    local spec = LJ.Player:GetActiveSpec()
    loot.num.text:SetText(tostring(index))
    loot.title:SetText(boss.name)
    local n = #boss.loot
    local maxH = math.max(200, (w:GetHeight() or 0) - TOP - BOTTOM)
    loot:SetHeight(math.min(maxH, LOOT_HEAD + math.max(n * Widgets.ItemRowHeight(), 30) + 14))
    local width = LOOT_W - 16
    -- the chance column only where the boss has chances
    local anyChance = false
    for j = 1, n do
        if boss.chance and boss.chance[j] and boss.chance[j] > 0 then anyChance = true end
    end
    local content = loot.scroll.content
    local upgrades = 0
    for j, id in ipairs(boss.loot) do
        local row = loot.rows[j]
        if not row then
            row = Widgets.CreateItemRow(content)
            loot.rows[j] = row
        end
        local upgrade = BiS.Upgrade(id)
        if upgrade then upgrades = upgrades + 1 end
        local opts = { upgrade = upgrade, unusable = BiS.Unusable(Items.Get(id), spec),
            chance = boss.chance and boss.chance[j] or nil, noChance = not anyChance }
        -- the upgrade line of the item tooltip says the same when it is on (Options)
        local line = LJ.Lists.UpgradeTooltip(upgrade, id)
        if line then opts.extraTooltip = { line } end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(j - 1) * Widgets.ItemRowHeight())
        row:SetWidth(width)
        row:SetItem(id, opts)
        row:Show()
    end
    for j = n + 1, #loot.rows do loot.rows[j]:Hide() end
    local parts = {}
    if n > 0 then parts[#parts + 1] = n == 1 and L("1 drop") or F("%s drops", Theme.ColorText(n, C.text1)) end
    if upgrades > 0 then
        parts[#parts + 1] = F(upgrades == 1 and "%s upgrade for you" or "%s upgrades for you", Theme.ColorText(upgrades, C.okText))
    end
    loot.sub:SetText(table.concat(parts, " · "))
    loot.note:SetText(L("No drops recorded for this encounter."))
    loot.note:SetShown(n == 0)
    loot.scroll:SetContentHeight(n * Widgets.ItemRowHeight())
end

-- Unfolds the loot of a boss (the selected one again or nil: folds the panel away).
local function SelectBoss(w, index)
    if index ~= nil and w.selected == index then index = nil end
    local wasOpen = w.selected ~= nil
    w.selected = index
    w.map:FocusBoss(index)
    local open = index ~= nil
    if open then
        FillLoot(w)
        w.loot.scroll:ScrollToTop()   -- a new boss starts at its first drop; refreshes keep the place
    end
    if open == wasOpen then return end   -- another boss: the panel stays where it is
    local loot = w.loot
    if open then ChooseSide(w) end
    loot:Show()
    Widgets.Anim.Run(loot, 0.16, function(p) PlaceLoot(w, open and p or 1 - p) end, function()
        if not w.selected then loot:Hide() end
    end)
end

-- Fits the window to its width (within what the screen allows) and lays the map out in it.
local function LayoutWindow(w)
    if not w.inst then return end
    local minW = MIN_MAP + 2 * PAD
    local maxW = math.max(minW, MaxWidth(w))
    local width = math.max(minW, math.min(maxW, w:GetWidth() or MAP_W + 2 * PAD))
    local height = HeightFor(w, width)
    w.laying = true
    if math.abs((w:GetWidth() or 0) - width) > 0.5 then w:SetWidth(width) end
    if math.abs((w:GetHeight() or 0) - height) > 0.5 then w:SetHeight(height) end
    w.laying = false
    w:SetResizeBounds(minW, HeightFor(w, minW), maxW, HeightFor(w, maxW))
    w.mapW = width - 2 * PAD
    w.map:SetMap(w.inst, w.mapW, w.onBoss)
    w.map:FocusBoss(w.selected)
    w.map:ClearAllPoints()
    w.map:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -TOP)
    if w.selected then
        FillLoot(w)
        PlaceLoot(w, 1)
    end
end

local function CreateWindow()
    local w = CreateFrame("Frame", "LootifiedDungeonMapWindow", UIParent)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:SetResizable(true)
    w:EnableMouse(true)
    w:SetSize(MAP_W + 2 * PAD, 400)
    w:Hide()
    if not tContains(UISpecialFrames, "LootifiedDungeonMapWindow") then tinsert(UISpecialFrames, "LootifiedDungeonMapWindow") end
    Widgets.CreateShadow(w, 18, 0.75)
    w.panel = Widgets.CreatePopupPanel(w, 12, { fill = { 0.055, 0.063, 0.08, 0.97 }, border = { 1, 1, 1, 0.09 } })
    w.title = Widgets.Text(w, "titleSmall", C.white)
    w.title:SetPoint("TOPLEFT", PAD, -12)
    w.close = Widgets.CreateButton(w, nil, "icon", "close", 26, 26)
    w.close:SetPoint("TOPRIGHT", -8, -8)
    w.close:SetScript("OnClick", function() w:Hide() end)
    Widgets.SetTooltip(w.close, "Close", nil, "ANCHOR_BOTTOM")
    w.title:SetPoint("RIGHT", w.close, "LEFT", -8, 0)
    -- the title row moves the window
    w.drag = CreateFrame("Frame", nil, w)
    w.drag:SetPoint("TOPLEFT")
    w.drag:SetPoint("RIGHT", w.close, "LEFT", -4, 0)
    w.drag:SetHeight(TOP - 6)
    w.drag:EnableMouse(true)
    w.drag:RegisterForDrag("LeftButton")
    w.drag:SetScript("OnDragStart", function() w:StartMoving() end)
    w.drag:SetScript("OnDragStop", function()
        w:StopMovingOrSizing()
        AnchorTopLeft(w)
        SaveWindow(w)
        -- the loot panel goes to the side with room
        if w.selected then
            ChooseSide(w)
            PlaceLoot(w, 1)
        end
    end)
    -- the grip at the bottom right sizes the window (the height follows the width)
    w.grip = CreateFrame("Button", nil, w)
    w.grip:SetSize(16, 16)
    w.grip:SetPoint("BOTTOMRIGHT", -4, 4)
    w.grip:SetFrameLevel(w:GetFrameLevel() + 30)
    w.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    w.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    w.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    w.grip:SetScript("OnMouseDown", function()
        GameTooltip:Hide()
        w:StartSizing("RIGHT")
    end)
    w.grip:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
        AnchorTopLeft(w)
        LayoutWindow(w)
        SaveWindow(w)
    end)
    w.grip:SetScript("OnEnter", function(g)
        GameTooltip:SetOwner(g, "ANCHOR_TOP")
        GameTooltip:SetText(L("Drag to make the map bigger or smaller."), 1, 1, 1)
        GameTooltip:Show()
    end)
    w.grip:SetScript("OnLeave", function(g)
        if GameTooltip:GetOwner() == g then GameTooltip:Hide() end
    end)

    w.map = DungeonMap.Create(w)
    -- a boss marker unfolds its loot, a second click folds it away
    w.map.markerHint = function(index)
        return w.selected == index and "Click to hide the loot." or "Click to show the loot."
    end
    w.onBoss = function(index)
        Util.PlaySound("IG_MAINMENU_OPTION")
        SelectBoss(w, index)
    end

    -- the loot panel
    local loot = CreateFrame("Frame", nil, w)
    loot:SetWidth(LOOT_W)
    loot:SetHeight(200)
    loot:SetFrameLevel(w:GetFrameLevel() + 20)
    loot:EnableMouse(true)
    loot:Hide()
    Widgets.CreateShadow(loot, 14, 0.7)
    loot.panel = Widgets.CreatePopupPanel(loot, 10, { fill = { 0.055, 0.063, 0.08, 0.98 }, border = { 1, 1, 1, 0.1 } })
    -- the boss: its number (as on the map) and name
    loot.num = CreateFrame("Frame", nil, loot)
    loot.num:SetSize(22, 22)
    loot.num:SetPoint("TOPLEFT", 12, -12)
    loot.num.bg = loot.num:CreateTexture(nil, "ARTWORK")
    loot.num.bg:SetTexture(Theme.TEX.circle)
    loot.num.bg:SetAllPoints()
    local a = Theme.accent
    loot.num.bg:SetVertexColor(a[1], a[2], a[3], 1)
    loot.num.text = Widgets.Text(loot.num, "tiny", C.dark, nil, "CENTER")
    loot.num.text:SetPoint("CENTER", 0, 0)
    loot.close = Widgets.CreateButton(loot, nil, "icon", "close", 24, 24)
    loot.close:SetPoint("TOPRIGHT", -8, -8)
    loot.close:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        SelectBoss(w, nil)
    end)
    Widgets.SetTooltip(loot.close, "Close", nil, "ANCHOR_BOTTOM")
    loot.title = Widgets.Text(loot, "h2", C.white)
    loot.title:SetPoint("LEFT", loot.num, "RIGHT", 8, 0)
    loot.title:SetPoint("RIGHT", loot.close, "LEFT", -8, 0)
    loot.sub = Widgets.Text(loot, "small", C.text3)
    loot.sub:SetPoint("TOPLEFT", 12, -40)
    loot.sub:SetPoint("RIGHT", -12, 0)
    loot.scroll = Widgets.CreateScrollArea(loot, -4)
    loot.scroll:SetPoint("TOPLEFT", 8, -LOOT_HEAD)
    loot.scroll:SetPoint("BOTTOMRIGHT", -8, 10)
    -- a boss without known drops
    loot.note = Widgets.Text(loot, "body", C.text3)
    loot.note:SetPoint("TOPLEFT", 12, -(LOOT_HEAD + 4))
    loot.note:SetPoint("RIGHT", -12, 0)
    loot.note:Hide()
    loot.rows = {}
    w.loot = loot
    Theme.OnAccent(loot, function(l, r, g, b) l.num.bg:SetVertexColor(r, g, b, 1) end)

    -- a new size (the grip, the screen, the window scale): the map fits again
    w:SetScript("OnSizeChanged", function(f)
        if f:IsShown() and not f.laying then LayoutWindow(f) end
    end)
    -- closed: the next time it opens without a loot panel; its tour ends (and counts as seen)
    w:SetScript("OnHide", function(f)
        Widgets.Anim.Stop(f.loot)
        f.selected = nil
        f.loot:Hide()
        Widgets.Menu.Close()   -- a loot row's menu goes with the window
        if mapTour and mapTour.active then mapTour:Stop(true) end
    end)
    return w
end

-- The window explains itself the first time: its floors (on a map with floors), the bosses and their loot (on a floor
-- with bosses), its size.
-- Each part once (LJ.db.mapTour); starting the main tour again (options, /lf tour) resets it. It uses the spotlight
-- of the main tour (UI/Tour.lua).
local MAP_TOUR = {
    floors = {
        key = "floors", title = "Floors",
        text = "This dungeon has more than one floor: switch between them here. Next to the buttons is the name of the floor you see.",
        target = function() return window and window.map.bar end,
        interactive = true,
    },
    boss = {
        key = "boss", title = "Bosses",
        text = "These are the bosses, numbered in their order. Click one to see its loot next to the map; click it again to close it.",
        -- the boss with the lowest number on the floor shown
        target = function()
            local first
            for _, b in ipairs(window and window.map.bossMarkers or {}) do
                if b:IsShown() and b.index and (not first or b.index < first.index) then first = b end
            end
            return first
        end,
        interactive = true, pad = 8,
    },
    size = {
        key = "size", title = "Window size",
        text = "Drag the grip at the bottom right to make the map bigger or smaller, and the title to move the window. Size and place are kept.",
        target = function() return window and window.grip end,
        interactive = true, pad = 8,
    },
}

local function StartMapTour(w)
    local Tour = UI.Tour
    if Tour.active or not w:IsShown() or InCombatLockdown() then return end
    local seen = LJ.db.mapTour or {}
    local steps = {}
    if Bar(w) > 0 and not seen.floors then steps[#steps + 1] = MAP_TOUR.floors end
    -- the bosses only where the floor shown has some (else a later map explains them)
    if not seen.boss and BossesOn(DungeonMap.Get(w.inst), w.map.floor) > 0 then steps[#steps + 1] = MAP_TOUR.boss end
    if not seen.size then steps[#steps + 1] = MAP_TOUR.size end
    if #steps == 0 then return end
    mapTour = mapTour or Tour.New({
        host = function() return window end,
        -- the tour ended: its parts count as seen
        seen = function(t)
            LJ.db.mapTour = LJ.db.mapTour or {}
            for _, step in ipairs(t.steps) do LJ.db.mapTour[step.key] = true end
        end,
    })
    if mapTour.active then return end
    mapTour.steps = steps
    mapTour:Begin()
end

-- The window's tour (nil until it ran once), for the tests.
function DungeonMap.Tour() return mapTour end

-- Shows the map of an instance in the window; false (and nothing shown) when it has no map.
function DungeonMap.ShowWindow(inst)
    if not DungeonMap.Get(inst) then return false end
    window = window or CreateWindow()
    local w = window
    if w.inst ~= inst then
        w.selected = nil
        Widgets.Anim.Stop(w.loot)
        w.loot:Hide()
    end
    w.inst = inst
    w.title:SetText(Theme.Case(inst.name))
    w:SetScale(LJ.db.scale or 1)
    if not w:IsShown() then
        -- the place and size it had, else centred at the first width
        local p = LJ.db.mapWindow
        local width = (p and p.width) or (MAP_W + 2 * PAD)
        w:SetWidth(width)
        w:ClearAllPoints()
        if p and p.left and p.top then
            w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
        else
            local s = w:GetScale() or 1
            local sw, sh = UIParent:GetWidth() / s, UIParent:GetHeight() / s
            w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.floor((sw - width) / 2),
                math.floor((sh + HeightFor(w, width)) / 2))
        end
    end
    w:Show()
    w:Raise()
    LayoutWindow(w)
    -- the first time: the window explains itself (once its layout settled)
    C_Timer.After(0.3, function()
        if window == w and w:IsShown() then StartMapTour(w) end
    end)
    return true
end

function DungeonMap.HideWindow()
    if window then window:Hide() end
end

-- The instance the window shows, nil while it is closed.
function DungeonMap.WindowInstance()
    return window and window:IsShown() and window.inst or nil
end

-- the window is made again in the new look
LJ:Listen("SKIN_CHANGED", function()
    if not window then return end
    local inst = DungeonMap.WindowInstance()
    window:Hide()
    window = nil
    if inst then DungeonMap.ShowWindow(inst) end
end)
LJ:Listen("SETTINGS_CHANGED", function(_, what)
    if window and what == "scale" then
        window:SetScale(LJ.db.scale or 1)
        if window:IsShown() then LayoutWindow(window) end
    end
end)
-- item data, the wishlist, the spec, the gear, the filter (the list, the stat priority), the sim's numbers or Percent /
-- Sim changed: the open loot panel shows it
for _, message in ipairs({ "ITEMS_UPDATED", "WISHLIST_CHANGED", "SPEC_CHANGED", "EQUIPMENT_CHANGED", "LIST_CHANGED",
    "SIM_BIS_CHANGED" }) do
    LJ:Listen(message, function()
        if window and window:IsShown() and window.selected then FillLoot(window) end
    end)
end
