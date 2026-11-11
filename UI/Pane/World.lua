-- Lootified - Open World in the classic and the modern look: the zone list on the left (the zones for the character's
-- level, or all), the picked zone on the right; it follows the zone the player is in until the player picks another
-- one. The zone is a hunt board: its rares as cards (face, level, camps, their best drops for the character and a
-- button for their camps), the other mobs as lines with their best drop (a click shows all).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local Lists = LJ.Lists
local C = Theme.COLORS
local P = Theme.PANE

local Page = {}

local GAP = 12
-- the hunt cards: three in a row, the face on top, then the name and the tag line, the drops, the button
local HUNT_COLUMNS, HUNT_PAD, HUNT_FACE = 3, 10, 56
local HUNT_TOP = 122                 -- where the drops start
local HUNT_DROPS = 2                 -- drops a card shows before "+N more"
local DROP_H, DROP_GAP = 40, 4
-- the mob lines: face, name column, the best drop, map button; their other drops indented below
local LINE_H, LINE_NAME, LINE_INDENT = 56, 160, 24
local CHIP_X = 9 + 34 + 12 + LINE_NAME + 10

local function MobTooltip(owner, mob, hint)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(mob.name, 1, 0.82, 0)
    GameTooltip:AddLine(F("Level %s%s", Util.LevelRange(mob.minLevel, mob.maxLevel), mob.rankText and (" " .. L(mob.rankText)) or ""), 1, 1, 1)
    if mob.isRare then GameTooltip:AddLine(L("Rare spawn: it is not always up, check its camps."), 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(F("%s in the Classic data.", Util.Plural(mob.spawns, "spawn point")), 0.8, 0.8, 0.8)
    if hint then GameTooltip:AddLine(L(hint), 0.6, 0.62, 0.66, true) end
    GameTooltip:Show()
end

-- A mob's map button: label, glyph, tooltip and whether it can mark (unmarked: label, else the camp it marks).
local function MapState(button, mob, label)
    local text, glyph, title, tip, canMark = Lists.MapButtonState(mob)
    button:SetLabel(glyph == "mapPin" and label or text)
    button:SetGlyph(glyph)
    button:SetEnabled(canMark)
    Widgets.SetTooltip(button, title, tip, "ANCHOR_TOP")
end

local function MapClick(button)
    Lists.MarkNextCamp(button.mob)
end

local function CreateMapButton(parent, width, height)
    local b = Widgets.CreateButton(parent, "Map", "ghost", "mapPin", width, height)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnClick", MapClick)
    return b
end

---------------------------------------------------------------------------
-- The drops of the hunt board: in a card (two lines) and on a mob's line (one line)
---------------------------------------------------------------------------
-- cell: Kit.ItemData of the drop with its chance. A click opens the item, the tooltip is the game's.
local function DropEnter(b)
    b.ring:SetColor(P.ring)
    Widgets.ShowItemTooltip(b, b.cell.id, b.cell.extraTooltip)
end

local function DropLeave(b)
    b.ring:SetColor(P.rowBorder)
    GameTooltip:Hide()
end

local function DropClick(b, button)
    local id = b.cell.id
    if Items.HandleClick(id, button) then return end
    if button == "RightButton" then
        Widgets.ShowItemMenu(b, id)
        return
    end
    Util.PlaySound("IG_MAINMENU_OPTION")
    UI:Open("item", id)
end

local function CreateDrop(parent, height, iconSize)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.fill = Widgets.CreateBox(b, "BACKGROUND", 1, 4)
    b.fill:SetColor(0, 0, 0, 0.28)
    b.ring = Widgets.CreateBox(b, "BACKGROUND", 2, 4, true)
    b.ring:SetColor(P.rowBorder)
    b.icon = Widgets.CreateItemIcon(b, iconSize)
    b.icon:EnableMouse(false)
    b.icon:SetPoint("LEFT", (height - iconSize) / 2, 0)
    b.name = Widgets.Text(b, "item", C.text1)
    b.chance = Widgets.Text(b, "small", C.text2, nil, "RIGHT")
    b:SetScript("OnEnter", DropEnter)
    b:SetScript("OnLeave", DropLeave)
    b:SetScript("OnClick", DropClick)
    return b
end

-- The chance with the upgrade mark (an item of the Best in Slot list) before it.
local function ChanceText(cell)
    local marks = cell.upgrade and (Theme.GlyphString("upgrade", 10, C.okText) .. " ") or ""
    return marks .. (Util.FormatChance(cell.chance) or "")
end

-- The name in its quality color, the chance; dimmed when the character cannot use the item.
local function FillDrop(b, cell)
    b.cell = cell
    local rec = Items.Get(cell.id)
    b.icon:SetItem(cell.id)
    b.icon:SetOwned(Items.IsOwned(cell.id))
    b.name:SetText(rec.name or rec.fallbackName or F("Item #%d", cell.id))
    b.name:SetTextColor(Util.QualityColor(rec.quality or 1))
    b.chance:SetText(ChanceText(cell))
    b:SetAlpha(cell.unusable and 0.6 or 1)
end

-- The name as wide as it needs, at most room.
local function FitName(b, room)
    b.name:SetWidth(0)
    b.name:SetWidth(math.max(30, math.min(Widgets.TextWidth(b.name) + 2, room)))
end

-- In a card, w wide: the name on top, below it the slot ("not for you" in red) and the chance.
local function CreateCardDrop(parent)
    local b = CreateDrop(parent, DROP_H, 28)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.sub = Widgets.Text(b, "small", C.text3)
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.chance:SetPoint("BOTTOMRIGHT", -7, 7)
    return b
end

local function SetCardDrop(b, cell, w)
    local room = w - 42 - 7
    FillDrop(b, cell)
    FitName(b, room)
    local slot = Items.GetSlotText(cell.id) or ""
    b.sub:SetText(cell.unusable and F("%s · not for you", slot) or slot)
    Widgets.SetTextColor(b.sub, cell.unusable and C.bad or C.text3)
    b.sub:SetWidth(math.max(30, room - Widgets.TextWidth(b.chance) - 6))
end

-- On a mob's line: icon, name, chance; as wide as its content, at most room.
local function CreateChip(parent)
    local b = CreateDrop(parent, 28, 20)
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.chance:SetPoint("LEFT", b.name, "RIGHT", 6, 0)
    return b
end

local function SetChip(b, cell, room)
    FillDrop(b, cell)
    local fixed = 4 + 20 + 6 + 6 + Widgets.TextWidth(b.chance) + 10
    FitName(b, room - fixed)
    b:SetWidth(math.floor(fixed + b.name:GetWidth()))
end

---------------------------------------------------------------------------
-- Kinds of the hunt board (classic, modern)
---------------------------------------------------------------------------
-- The height of a row of cards that show n drops (more: a card in the row has the "+N more" link).
local function HuntHeight(n, more)
    return HUNT_TOP + n * DROP_H + (n - 1) * DROP_GAP + (more and 22 or 0) + 10 + 26 + HUNT_PAD + GAP
end

local function ToggleClick(b)
    local d = b.cell.sheet.data[b.cell.entry]
    Util.PlaySound("IG_MAINMENU_OPTION")
    d.onToggle(d)
end

-- A rare as a card: its face with the level, the name, the tag with level and camps, its best drops for the character
-- (all of them when open), "+N more" and a button for its camps.
-- data = { mob, cells (best first), shown (drops to show), open, onToggle(data) }
Kit.KINDS.hunt = {
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f:EnableMouse(true)
        local card = CreateFrame("Frame", nil, f)
        card:SetPoint("TOPLEFT")
        card:SetPoint("BOTTOMRIGHT", 0, GAP)
        f.card = card
        f.fill = Widgets.CreateBox(card, "BACKGROUND", 0, P.radius)
        f.fill:SetGradient("VERTICAL", P.rowTop, P.panelTop)
        f.ring = Widgets.CreateBox(card, "BACKGROUND", 2, P.radius, true)
        f.ring:SetColor(P.cardBorder)
        if Theme.skin == "modern" then
            -- a soft glow of the rare color behind the face
            f.shine = card:CreateTexture(nil, "BACKGROUND", nil, 1)
            f.shine:SetTexture(Theme.TEX.glow)
            f.shine:SetPoint("TOPLEFT", 8, -2)
            f.shine:SetPoint("TOPRIGHT", -8, -2)
            f.shine:SetHeight(104)
            f.shine:SetVertexColor(C.rare[1], C.rare[2], C.rare[3], 0.14)
        end
        f.emblem = Widgets.CreateEmblem(card, HUNT_FACE)
        f.emblem:SetPoint("TOP", 0, -12)
        f.emblem:SetRare(true)
        f.badge = Kit.Badge(f.emblem, 22)
        f.badge:SetPoint("CENTER", f.emblem, "BOTTOMLEFT", 6, 6)
        f.name = Widgets.Text(card, "h2", C.text1, nil, "CENTER")
        f.name:SetPoint("TOP", f.emblem, "BOTTOM", 0, -8)
        f.tag = Widgets.CreatePill(card, 15, "pillTiny")
        f.sub = Widgets.Text(card, "small", C.text3)
        f.sub:SetPoint("LEFT", f.tag, "RIGHT", 6, 0)
        f.drops = {}
        f.map = CreateMapButton(card, 120, 26)
        f.map:SetPoint("BOTTOM", 0, HUNT_PAD)
        f.more = CreateFrame("Button", nil, card)
        f.more:SetHeight(18)
        f.more:SetPoint("BOTTOM", f.map, "TOP", 0, 4)
        f.more.cell = f
        f.more.text = Widgets.Text(f.more, "small", C.text3, nil, "CENTER")
        f.more.text:SetPoint("CENTER")
        f.more:SetScript("OnClick", ToggleClick)
        f.more:SetScript("OnEnter", function(self) Widgets.SetTextColor(self.text, C.white) end)
        f.more:SetScript("OnLeave", function(self) Widgets.SetTextColor(self.text, C.text3) end)
        f:SetScript("OnEnter", function(self) MobTooltip(self.card, self.sheet.data[self.entry].mob) end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return f
    end,
    fill = function(f, d, w)
        local mob = d.mob
        local inner = w - 2 * HUNT_PAD
        f.emblem:SetCreature(mob.display, Theme.BossEmblem(mob))
        f.badge.text:SetText(tostring(mob.maxLevel))
        f.name:SetText(mob.name)
        f.name:SetWidth(inner)
        -- the tag and the level with the camps, together in the middle
        f.tag:Set(Util.Upper(L(mob.rankText)), "rare")
        f.sub:SetText(F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel)) .. " · " .. Util.Plural(#mob.locs, "camp"))
        local tagW = f.tag:GetWidth()
        local subW = math.min(Widgets.TextWidth(f.sub) + 2, inner - tagW - 6)
        f.sub:SetWidth(subW)
        f.tag:ClearAllPoints()
        f.tag:SetPoint("TOPLEFT", math.floor((w - tagW - 6 - subW) / 2), -97)
        for i = 1, math.max(d.shown, #f.drops) do
            local b = f.drops[i]
            if i <= d.shown then
                if not b then
                    b = CreateCardDrop(f.card)
                    local y = -(HUNT_TOP + (i - 1) * (DROP_H + DROP_GAP))
                    b:SetPoint("TOPLEFT", HUNT_PAD, y)
                    b:SetPoint("TOPRIGHT", -HUNT_PAD, y)
                    f.drops[i] = b
                end
                SetCardDrop(b, d.cells[i], inner)
                b:Show()
            elseif b then
                b:Hide()
            end
        end
        local more = #d.cells - HUNT_DROPS
        f.more:SetShown(more > 0)
        f.more.text:SetText(d.open and L("Show fewer") or F("+%d more", more))
        f.more:SetWidth(Widgets.TextWidth(f.more.text) + 16)
        f.map.mob = mob
        f.map:SetWidth(inner)
        MapState(f.map, mob, "Show on map")
    end,
}

local function LineEnter(f)
    f.hovered = true
    Kit.MarkVisual(f)
    local d = f.sheet.data[f.entry]
    MobTooltip(f, d.mob, d.onClick and "Click: show all its drops.")
end

local function LineLeave(f)
    f.hovered = false
    Kit.MarkVisual(f)
    GameTooltip:Hide()
end

-- A mob as a line: its face with the level, name and level with its camps, its best drop, "+N more" (a click on the
-- line shows the other drops below it) and a button for its camps. data = { mob, cells (best first), open, onClick }
Kit.KINDS.mobLine = {
    height = LINE_H,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        Kit.AddMarks(f)
        local dy = Kit.RowDY()
        f.emblem = Widgets.CreateEmblem(f, 34)
        f.emblem:SetPoint("LEFT", 9, dy)
        f.badge = Kit.Badge(f.emblem, 17)
        f.badge:SetPoint("CENTER", f.emblem, "BOTTOMLEFT", 2, 3)
        f.name = Widgets.Text(f, "item", C.text1)
        f.name:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 12, 1)
        f.name:SetWidth(LINE_NAME)
        f.sub = Widgets.Text(f, "small", C.text3)
        f.sub:SetPoint("BOTTOMLEFT", f.emblem, "BOTTOMRIGHT", 12, -1)
        f.sub:SetWidth(LINE_NAME)
        f.drop = CreateChip(f)
        f.drop:SetPoint("LEFT", CHIP_X, dy)
        f.more = Widgets.Text(f, "small", C.text3)
        f.more:SetPoint("LEFT", f.drop, "RIGHT", 10, 0)
        f.map = CreateMapButton(f, nil, 24)
        f.map:SetPoint("RIGHT", -9, dy)
        f:SetScript("OnEnter", LineEnter)
        f:SetScript("OnLeave", LineLeave)
        f:SetScript("OnClick", function(self)
            local d = self.sheet.data[self.entry]
            if not d.onClick then return end
            Util.PlaySound("IG_MAINMENU_OPTION")
            d.onClick(d)
        end)
        return f
    end,
    fill = function(f, d, w)
        local mob = d.mob
        f.emblem:SetCreature(mob.display, Theme.BossEmblem(mob))
        f.badge.text:SetText(tostring(mob.maxLevel))
        f.name:SetText(mob.name)
        f.sub:SetText(F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel)) .. "  ·  " .. Util.Plural(#mob.locs, "camp"))
        f.map.mob = mob
        MapState(f.map, mob, "Map")
        local more = #d.cells - 1
        f.more:SetShown(more > 0)
        f.more:SetText(d.open and L("Show fewer") or F("+%d more", more))
        local moreW = more > 0 and (Widgets.TextWidth(f.more) + 10) or 0
        SetChip(f.drop, d.cells[1], w - CHIP_X - moreW - f.map:GetWidth() - 9 - 12)
        f.hovered = f:IsMouseOver()
        Kit.MarkVisual(f)
    end,
}

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
local ZONE_FILTERS = { { key = "NEAR", text = "Zones for your level" }, { key = "ALL", text = "All zones" } }

local function ZoneFilterText(key)
    return key == "ALL" and "All zones" or "Zones for your level"
end

function Page:Create(root)
    root = Kit.Page(root)
    self.expanded = {}
    local book = Kit.Book(root)
    self.book = book
    self.leftHeader = Kit.PaneHeader(book.left)
    local listTop = self.leftHeader.height + 38
    self.filter = Widgets.CreateDropdown(book.left, nil, function(menu)
        for _, f in ipairs(ZONE_FILTERS) do
            menu:CreateRadio(f.text, function() return (LJ.db.world.zones or "NEAR") == f.key end, function()
                LJ.db.world.zones = f.key
                self:Refresh()
            end)
        end
    end, ZoneFilterText(LJ.db.world.zones), "globe")
    self.filter:SetPoint("TOPLEFT", 4, -(self.leftHeader.height + 6))
    self.list = Kit.Sheet(book.left, 0)
    self.list.scroll:SetPoint("TOPLEFT", 0, -listTop)
    self.list.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
    self.header = Kit.PaneHeader(book.right)
    self.upgrades = Kit.Toggle(self.header, "Upgrades only", "Only items that are an upgrade for your character.", function(on)
        LJ.db.world.upgradesOnly = on and true or false
        self.sheet:ScrollToTop()
        self:Refresh()
    end)
    self.sheet = Kit.Sheet(book.right, 0)
    self.upgrades:SetPoint("RIGHT", 0, 3)
    self.sheet.scroll:SetPoint("TOPLEFT", 0, -(self.header.height + 4))
    self.sheet.scroll:SetPoint("BOTTOMRIGHT", -10, 0)
end

---------------------------------------------------------------------------
-- Following the player
---------------------------------------------------------------------------
-- The zone to show follows the player: the zone they stand in. A zone they picked (zone list, search, a link) stays
-- until they move to another map. Where the player's map has no open world data, the page keeps its zone.
function Page:FollowPlayer(zones)
    if self.pickedIn ~= nil then
        local now = Lists.PlayerMap()
        if now and now ~= self.pickedIn then self.pickedIn = nil end
    end
    local valid = self.map and Items.GetWorldZone(self.map)
    if self.pickedIn ~= nil and valid then return end
    local map = Lists.CurrentZoneMap() or (valid and self.map) or Lists.DefaultZoneMap(zones)
    if map ~= self.map then
        self.map = map
        self.sheet:ScrollToTop()
    end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function ZoneEnter(f, d)
    local zone = d.zone
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
    GameTooltip:SetText(zone.name, 1, 0.82, 0)
    GameTooltip:AddLine(F("Level %s", Util.LevelRange(zone.minLevel, zone.maxLevel)), 1, 1, 1)
    if d.here then GameTooltip:AddLine(L("You are here"), 0.97, 0.78, 0.27) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L("Rares"), zone.rares, 0.6, 0.64, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("Other mobs with drops"), #zone.mobs - zone.rares, 0.6, 0.64, 0.7, 1, 1, 1)
    GameTooltip:Show()
end

-- The zone list.
function Page:RefreshList(zones)
    local filter = LJ.db.world.zones or "NEAR"
    self.filter:SetLabel(ZoneFilterText(filter))
    local here = Lists.CurrentZoneMap()
    local sheet = self.list
    sheet:Reset(276)
    local pick = function(d) self:Show(d.zone.map) end
    local selectedY
    for _, zone in ipairs(zones) do
        if filter == "ALL" or Lists.ZoneIsNear(zone) or zone.map == self.map or zone.map == here then
            local isHere = zone.map == here
            local rares = zone.rares > 0 and (Theme.GlyphString("skull", 10, C.text4) .. " " .. zone.rares .. "   ") or ""
            local range = Theme.ColorText(Kit.RangeText(zone.minLevel, zone.maxLevel), Theme.RangeColor(zone.minLevel, zone.maxLevel))
            if zone.map == self.map then selectedY = sheet.cursor end
            sheet:Add("row", { text = zone.name .. (isHere and (" " .. Theme.GlyphString("mapPin", 11, C.gold)) or ""),
                right = rares .. range, zone = zone, here = isHere, selected = zone.map == self.map, onClick = pick, onEnter = ZoneEnter })
        end
    end
    sheet:Finish(8)
    -- a zone picked elsewhere (search, the player's zone) is in view: once per picked zone
    local view = sheet.scroll:GetHeight() or 0
    if selectedY and self.revealedMap ~= self.map and view > 0 then
        self.revealedMap = self.map
        local top = sheet.scroll:GetVerticalScroll()
        if selectedY < top or selectedY + Kit.M().row > top + view then
            sheet.scroll:ScrollTo(math.max(0, selectedY - math.floor(view / 3)))
        end
    end
end

-- The drops of a mob for the character, best first: the upgrades (the biggest first), then what it can use, then the
-- rest, each by chance.
local function BestDrops(drops, spec)
    local cells = {}
    local open = function(x) UI:Open("item", x.id) end
    for i, d in ipairs(drops) do
        local cell = Kit.ItemData(d.id, spec)
        cell.chance, cell.order, cell.onClick = d.chance, i, open
        cells[i] = cell
    end
    table.sort(cells, function(a, b)
        local ua, ub = a.upgrade ~= nil, b.upgrade ~= nil
        if ua ~= ub then return ua end
        if ua and a.upgrade ~= b.upgrade then return a.upgrade > b.upgrade end
        if a.unusable ~= b.unusable then return not a.unusable end
        return a.order < b.order
    end)
    return cells
end

-- The rares as cards in rows of three, the other mobs as lines (a click shows their other drops below).
function Page:AddHuntBoard(list, rares, others, spec)
    local sheet = self.sheet
    local toggle = function(d)
        self.expanded[d.mob.id] = not self.expanded[d.mob.id] or nil
        self:Refresh()
    end
    local cards, lines = {}, {}
    for _, entry in ipairs(list) do
        local mob = entry.mob
        local d = { mob = mob, cells = BestDrops(entry.drops, spec), open = self.expanded[mob.id] }
        if mob.isRare then cards[#cards + 1] = d else lines[#lines + 1] = d end
    end
    if #cards > 0 then
        sheet:Add("section", { text = L("Rares to hunt"), count = rares })
        for first = 1, #cards, HUNT_COLUMNS do
            local row, shown, more = {}, 1, false
            for i = first, math.min(first + HUNT_COLUMNS - 1, #cards) do
                local d = cards[i]
                d.shown = d.open and #d.cells or math.min(#d.cells, HUNT_DROPS)
                d.onToggle = toggle
                shown = math.max(shown, d.shown)
                more = more or #d.cells > HUNT_DROPS
                self.mobY[d.mob.id] = sheet.cursor
                row[#row + 1] = d
            end
            sheet:Grid("hunt", row, HUNT_COLUMNS, HuntHeight(shown, more), GAP)
        end
    end
    if #lines > 0 then
        sheet:Add("section", { text = L("Mobs"), count = others })
        for _, d in ipairs(lines) do
            self.mobY[d.mob.id] = sheet.cursor
            if #d.cells > 1 then d.onClick = toggle end
            sheet:Add("mobLine", d)
            if d.open and #d.cells > 1 then
                local rest = {}
                for i = 2, #d.cells do rest[#rest + 1] = d.cells[i] end
                sheet:Grid("item", rest, 1, Kit.M().item, 0, LINE_INDENT)
                sheet:Space(4)
            end
        end
    end
end

-- The picked zone: its rares and other mobs with their drops.
function Page:RefreshZone()
    local zone = Items.GetWorldZone(self.map)
    local sheet = self.sheet
    sheet:Reset(420)
    self.mobY = {}
    -- (the Best in Slot module off: no "Upgrades only")
    local bis = LJ.Modules.On("bis")
    local upgradesOnly = bis and LJ.db.world.upgradesOnly
    self.upgrades:SetChecked(upgradesOnly)
    self.upgrades:SetShown(zone ~= nil and bis)
    if not zone then
        self.header:Set(L("Open World"), "")
        sheet:Add("empty", { title = L("No open world data"), text = L("The game has no map data for the open world mobs yet."), glyph = "globe" })
        sheet:Finish()
        return
    end
    local spec = Player:GetActiveSpec()
    local list, rares, others = Lists.ZoneMobs(zone, upgradesOnly)
    local parts = { F("Level %s", Kit.RangeText(zone.minLevel, zone.maxLevel)) }
    if zone.rares > 0 then parts[#parts + 1] = Util.Plural(zone.rares, "rare") end
    local mobs = #zone.mobs - zone.rares
    if mobs > 0 then parts[#parts + 1] = Util.Plural(mobs, "mob") end
    if zone.map == Lists.CurrentZoneMap() then parts[#parts + 1] = Theme.GlyphString("mapPin", 11, C.gold) .. " " .. L("You are here") end
    self.header:Set(zone.name, table.concat(parts, "  ·  "), bis and self.upgrades:GetWidth() + 24 or 0)
    self:AddHuntBoard(list, rares, others, spec)
    if #list == 0 and upgradesOnly then
        sheet:Add("empty", { title = L("No upgrades here"), text = L("Nothing here is an upgrade for your character right now."),
            glyph = "funnel", button = "Reset filters", buttonGlyph = "reset", onClick = function()
                LJ.db.world.upgradesOnly = false
                self:Refresh()
            end })
    else
        sheet:Space(6)
        sheet:Add("text", { text = L("Open world drop chances and spawn points are the Classic values and can differ in WoW: Forever."),
            font = "small", color = C.text4 })
    end
    sheet:Finish(10)
end

function Page:Refresh()
    Theme.SetAccent(C.defaultAccent)
    local zones = Items.GetWorldZones()
    self:FollowPlayer(zones)
    self.leftHeader:Set(L("Open World"), L("Zones"))
    self:RefreshList(zones)
    self:RefreshZone()
end

-- map: zone to show, picked by the player or a link (nil: the zone the player is in, see FollowPlayer); npcID: open
-- this mob and scroll to it.
function Page:Show(map, npcID)
    if map then
        -- the pick stays until the player moves to another map (false: the player's map is not known)
        self.pickedIn = Lists.PlayerMap() or false
        if map ~= self.map then
            self.map = map
            self.sheet:ScrollToTop()
        end
    end
    if npcID then self.expanded[npcID] = true end
    self:Refresh()
    if npcID and self.mobY and self.mobY[npcID] then self.sheet:Reveal(self.mobY[npcID]) end
end

-- The player entered another zone: the page follows while it shows.
LJ:On("ZONE_CHANGED_NEW_AREA", function()
    if Page.root and Page.root:IsVisible() then Page:Refresh() end
end)

-- The map buttons show which camp is marked: redraw when the mark changes.
LJ:Listen("MAP_TARGET_CHANGED", function()
    if Page.root and Page.root:IsVisible() then Page:Refresh() end
end)

UI:RegisterPage("world", Page, { "modern", "classic" })
