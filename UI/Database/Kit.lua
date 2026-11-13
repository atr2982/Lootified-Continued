-- Lootified - the database look (UI/Database/): pages to look things up - Items, Mobs and Places. Each
-- page searches every record the addon knows: the search bar on top (with the number of results, a switch and the
-- sort), the filters on the left, the results as a table in the middle (only the rows in view are built) and the picked
-- record's details on the right. This kit makes a page from its definition and holds what the four share: the search
-- bar, the filter widgets (chips, check boxes, a level range), the table rows, the detail panel parts, and the routes
-- from the other looks' addresses and between the pages (an item's mob and a mob's place).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local DB = {}
LJ.Database = DB

local UI = LJ.UI
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local C = Theme.COLORS

-- The pages as tabs of the top bar (UI/MainFrame.lua).
DB.TABS = {
    { key = "items", text = "Items", glyph = "package" },
    { key = "mobs", text = "Mobs", glyph = "skull" },
    { key = "places", text = "Places", glyph = "castle" },
}

-- The page area below the top bar: the search bar, then the filters, the table and the details side by side.
local MARGIN, GAP = 18, 12
local BAR_TOP, BAR_HEIGHT, SEARCH_WIDTH = 12, 40, 470
local PANEL_TOP = BAR_TOP + BAR_HEIGHT + GAP
local FILTER_WIDTH, TABLE_WIDTH = 196, 420
local HEAD_HEIGHT = 30
local ROW_PAD, COLUMN_GAP = 10, 11
DB.ROW_HEIGHT = 46                  -- a row: 44 and the 2 below it
DB.ICON = 30                        -- the icon or face at the start of a row
DB.LEVEL_MIN, DB.LEVEL_MAX = 1, 60
DB.TEXT = Theme.hex("AEB4BD")       -- the table's column texts

---------------------------------------------------------------------------
-- Search and level helpers
---------------------------------------------------------------------------
-- The words of a search text (the keys of Util.SearchKey, as the window's search uses them).
function DB.Tokens(text)
    local tokens = {}
    for word in Util.SearchKey(text or ""):gmatch("%S+") do tokens[#tokens + 1] = word end
    return tokens
end

local function Matches(key, tokens)
    for i = 1, #tokens do
        if not key:find(tokens[i], 1, true) then return false end
    end
    return true
end

-- The search key of a record: its words (name, place, slot, ...) as one key.
function DB.SearchKey(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if text and text ~= "" then parts[#parts + 1] = Util.SearchKey(text) end
    end
    return table.concat(parts, " ")
end

-- True when a level range (lo, hi) touches the filter's range; levels count as 1 to 60 (a quest of level 0 as 1, an
-- item of level 75 as 60), no level passes.
function DB.InLevels(range, lo, hi)
    if not lo then return true end
    lo = math.max(DB.LEVEL_MIN, math.min(lo, DB.LEVEL_MAX))
    hi = math.max(DB.LEVEL_MIN, math.min(hi or lo, DB.LEVEL_MAX))
    return lo <= range[2] and hi >= range[1]
end

-- The level of a record as the table shows it: "18" or "15–20".
function DB.LevelText(lo, hi)
    if not lo then return "" end
    return (Util.LevelRange(lo, hi):gsub("-", "–"))
end

---------------------------------------------------------------------------
-- Upgrades for the character (the "For you" of every page: the items of its Best in Slot list, BiS.Upgrade)
---------------------------------------------------------------------------
-- "+1.4 DPS" (the gain the sim found) or "BiS".
function DB.UpgradeText(itemID)
    return LJ.BiS.UpgradeText(itemID)
end

---------------------------------------------------------------------------
-- Routes: the addresses of the other looks (links of tooltips, the world map, the minimap, slash commands) and the
-- links between the pages lead to a page and a record
---------------------------------------------------------------------------
local PAGES = { items = true, mobs = true, quests = true, places = true }

-- Returns the page key and its Show arguments (record ID, search text).
function DB.Route(page, arg1, arg2)
    if PAGES[page] then return page, arg1, arg2 end
    if page == "item" then return "items", arg1 end
    if page == "search" then return "items", nil, arg1 or "" end
    if page == "quest" then return "quests", arg1 end
    if page == "instance" then
        if type(arg2) == "number" and arg2 > 0 then return "mobs", DB.BossID(arg1, arg2) end
        return "places", arg1 and DB.InstanceID(arg1)
    end
    if page == "world" then
        if arg2 then return "mobs", DB.WorldMobID(arg2) end
        return "places", arg1 and DB.ZoneID(arg1)
    end
    if page == "home" or page == "journal" then return "places" end
    return "items"    -- For you and Best in Slot
end

-- The IDs of the records that are no plain numbers (items and quests are their item and quest IDs).
function DB.BossID(instKey, index) return "b:" .. instKey .. ":" .. index end
function DB.WorldMobID(npcID) return "w:" .. npcID end
function DB.InstanceID(instKey) return "i:" .. instKey end
function DB.ZoneID(map) return "z:" .. map end

-- Opens a page on a record (id) or with a search (query).
function DB.Go(page, id, query)
    Util.PlaySound("IG_MAINMENU_OPTION")
    UI:Open(page, id, query)
end

---------------------------------------------------------------------------
-- Filter widgets
---------------------------------------------------------------------------
-- A filter's title with a line that fades out to the right. Returns the height it takes.
local function FilterHeader(parent, y, text)
    local t = Widgets.Text(parent, "label", C.text3)
    t:SetPoint("TOPLEFT", 0, -y)
    t:SetText(Util.Upper(L(text)))
    local line = Kit.FadeLine(parent, 0.45)
    line:SetPoint("LEFT", t, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    return 18
end

-- A check box row with a colored dot (the qualities).
local function CheckVisual(b)
    local a = Theme.accent
    if b.checked then
        b.box:SetColor(a[1], a[2], a[3], 1)
        b.boxRing:SetColor(a[1], a[2], a[3], 1)
    else
        b.box:SetColor(1, 1, 1, b.hovered and 0.08 or 0.03)
        b.boxRing:SetColor(1, 1, 1, b.hovered and 0.4 or 0.25)
    end
    b.mark:SetShown(b.checked)
    local c = (b.hovered or b.checked) and C.text1 or C.text2
    b.text:SetTextColor(c[1], c[2], c[3])
end

local function CreateCheck(parent, text, color)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    local holder = CreateFrame("Frame", nil, b)
    holder:SetSize(15, 15)
    holder:SetPoint("LEFT", 0, 0)
    b.box = Widgets.CreateBox(holder, "ARTWORK", 0, 4)
    b.boxRing = Widgets.CreateBox(holder, "ARTWORK", 1, 4, true)
    b.mark = Widgets.Glyph(holder, "check", 10, C.dark, "ARTWORK", 2)
    b.mark:SetPoint("CENTER")
    b.dotGlow = Widgets.CreateGlow(b, "ARTWORK", 0, color, 0.5, "ADD")
    b.dotGlow:SetSize(18, 18)
    b.dotGlow:SetPoint("CENTER", holder, "RIGHT", 12, 0)
    b.dot = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.dot:SetTexture(Theme.TEX.circle)
    b.dot:SetSize(8, 8)
    b.dot:SetVertexColor(color[1], color[2], color[3], 1)
    b.dot:SetPoint("CENTER", holder, "RIGHT", 12, 0)
    b.text = Widgets.Text(b, "itemSmall", C.text2)
    b.text:SetPoint("LEFT", holder, "RIGHT", 24, 0)
    b.text:SetText(L(text))
    b:SetScript("OnEnter", function(self) self.hovered = true CheckVisual(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = false CheckVisual(self) end)
    Theme.OnAccent(b, CheckVisual)
    return b
end

-- A level range: a track with two knobs (drag them), the two levels under the knobs. onChange(lo, hi) while dragging.
local KNOB = 14
local function CreateRange(parent, width, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 38)
    f.lo, f.hi = DB.LEVEL_MIN, DB.LEVEL_MAX
    local inset = KNOB / 2 + 2
    f.track = Widgets.Solid(f, "ARTWORK", 0, C.white, 0.08)
    f.track:SetHeight(4)
    f.track:SetPoint("TOPLEFT", inset, -9)
    f.track:SetPoint("TOPRIGHT", -inset, -9)
    f.fill = Widgets.Solid(f, "ARTWORK", 1, C.white, 1)
    f.fill:SetHeight(4)
    f.glow = Widgets.CreateGlow(f, "ARTWORK", 0, nil, 0.45, "ADD")
    f.glow:SetPoint("TOPLEFT", f.fill, "TOPLEFT", -6, 7)
    f.glow:SetPoint("BOTTOMRIGHT", f.fill, "BOTTOMRIGHT", 6, -7)
    local function X(v)
        return inset + (width - inset * 2) * (v - DB.LEVEL_MIN) / (DB.LEVEL_MAX - DB.LEVEL_MIN)
    end
    function f:Update()
        local x1, x2 = X(self.lo), X(self.hi)
        self.fill:ClearAllPoints()
        self.fill:SetPoint("TOPLEFT", x1, -9)
        self.fill:SetWidth(math.max(1, x2 - x1))
        for _, k in ipairs(self.knobs) do
            local v = k.which == 1 and self.lo or self.hi
            k:ClearAllPoints()
            k:SetPoint("CENTER", self, "TOPLEFT", X(v), -11)
            k.value:SetText(tostring(v))
        end
    end
    function f:Set(lo, hi)
        self.lo, self.hi = lo, hi
        self:Update()
    end
    f.knobs = {}
    for which = 1, 2 do
        local k = CreateFrame("Button", nil, f)
        k:SetSize(KNOB + 6, KNOB + 6)
        k.which = which
        k.halo = k:CreateTexture(nil, "ARTWORK", nil, 2)
        k.halo:SetTexture(Theme.TEX.circle)
        k.halo:SetSize(KNOB + 6, KNOB + 6)
        k.halo:SetPoint("CENTER")
        k.dot = k:CreateTexture(nil, "ARTWORK", nil, 3)
        k.dot:SetTexture(Theme.TEX.circle)
        k.dot:SetSize(KNOB, KNOB)
        k.dot:SetPoint("CENTER")
        k.value = Widgets.Text(f, "count", C.text2, nil, "CENTER")
        k.value:SetPoint("TOP", k, "BOTTOM", 0, -1)
        k:SetScript("OnMouseDown", function(self)
            self:SetScript("OnUpdate", function()
                local left = f:GetLeft()
                if not left then return end
                local x = GetCursorPosition() / f:GetEffectiveScale() - left
                local v = DB.LEVEL_MIN + (x - inset) / (width - inset * 2) * (DB.LEVEL_MAX - DB.LEVEL_MIN)
                v = math.max(DB.LEVEL_MIN, math.min(DB.LEVEL_MAX, math.floor(v + 0.5)))
                local lo, hi = f.lo, f.hi
                if self.which == 1 then lo = math.min(v, hi) else hi = math.max(v, lo) end
                if lo ~= f.lo or hi ~= f.hi then
                    f:Set(lo, hi)
                    onChange(lo, hi)
                end
            end)
        end)
        local function Stop(self) self:SetScript("OnUpdate", nil) end
        k:SetScript("OnMouseUp", Stop)
        k:SetScript("OnHide", Stop)
        f.knobs[which] = k
    end
    Theme.OnAccent(f, function(x, r, g, b)
        x.fill:SetVertexColor(r, g, b, 1)
        x.glow:SetVertexColor(r, g, b, 0.45)
        for _, k in ipairs(x.knobs) do k.halo:SetVertexColor(r, g, b, 0.35) end
    end)
    f:Update()
    return f
end

---------------------------------------------------------------------------
-- Table rows: the shared parts of every page's row kind
---------------------------------------------------------------------------
-- Hover: a faint light; the picked row: a wash and an outline in the layout color and a glowing bar at its left.
function DB.RowVisual(f)
    local a = Theme.accent
    if f.selected then
        f.fill:SetGradient("HORIZONTAL", { a[1], a[2], a[3], 0.13 }, { a[1], a[2], a[3], 0.04 })
        f.ring:SetColor(a[1], a[2], a[3], 0.35)
        f.bar:SetVertexColor(a[1], a[2], a[3], 1)
        f.barGlow:SetVertexColor(a[1], a[2], a[3], 0.8)
    else
        f.fill:SetColor(1, 1, 1, f.hovered and 0.04 or 0)
        f.ring:SetColor(1, 1, 1, f.hovered and 0.06 or 0)
    end
    f.bar:SetShown(f.selected and true or false)
    f.barGlow:SetShown(f.selected and true or false)
end

local function RowEnter(f)
    f.hovered = true
    DB.RowVisual(f)
    local rec = f.sheet.data[f.entry]
    local def = f.sheet.page.def
    if def.OnRowEnter then def.OnRowEnter(f, rec) end
end

local function RowLeave(f)
    f.hovered = false
    DB.RowVisual(f)
    if GameTooltip:GetOwner() == f then GameTooltip:Hide() end
end

local function RowClick(f, button)
    local rec = f.sheet.data[f.entry]
    local page = f.sheet.page
    if page.def.OnRowClick and page.def.OnRowClick(f, rec, button) then return end
    Util.PlaySound("IG_MAINMENU_OPTION")
    page:Select(rec.id)
end

-- A row of the table (a page's row kind adds its cells): f.name and f.sub are the name column's two lines, placed by
-- DB.PlaceName. Clicking picks the record (the page's OnRowClick can take the click first: modified clicks on items).
function DB.CreateRow(parent)
    local f = CreateFrame("Button", nil, parent)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.fill = Widgets.CreateLazyBox(f, "BACKGROUND", 1, 10)
    f.fill:SetAnchor(f, 0, 0, 0, 2)
    f.ring = Widgets.CreateLazyBox(f, "BACKGROUND", 2, 10, true)
    f.ring:SetAnchor(f, 0, 0, 0, 2)
    f.bar = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.bar:SetTexture(Theme.RoundFile(4))
    f.bar:SetWidth(3)
    f.bar:SetPoint("TOPLEFT", -1, -9)
    f.bar:SetPoint("BOTTOMLEFT", -1, 11)
    f.barGlow = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.barGlow:SetTexture(Theme.TEX.glow)
    f.barGlow:SetBlendMode("ADD")
    f.barGlow:SetPoint("TOPLEFT", f.bar, "TOPLEFT", -8, 6)
    f.barGlow:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 8, -6)
    f.name = Widgets.Text(f, "item", C.text1)
    f.sub = Widgets.Text(f, "small", C.text3)
    f:SetScript("OnEnter", RowEnter)
    f:SetScript("OnLeave", RowLeave)
    f:SetScript("OnClick", RowClick)
    return f
end

-- A column (not the name column) is at least as wide as its title, with room for the sort caret after a left-aligned
-- title, and as its widest type tag (pills of the rows: font pillTiny, height 18), as the words differ in length between
-- the languages. columns[i].tags = the tags' texts.
function DB.FitColumns(columns)
    for i = 2, #columns do
        local col = columns[i]
        local title = Kit.TextWidth(Util.Upper(L(col.title)), "label") + (col.justify == "RIGHT" and 0 or 13)
        col.width = math.max(col.width, math.ceil(title))
        for _, text in ipairs(col.tags or {}) do
            col.width = math.max(col.width, math.ceil(Kit.TextWidth(L(text), "pillTiny")) + 14)
        end
    end
end

-- The columns' places in a row of the page's table: x of each column (from the row's left edge), the name column's
-- width (what the other columns leave). columns = { { width }, ... }, the first one the name column.
function DB.Columns(columns, width)
    local x, pos = width - ROW_PAD, {}
    for i = #columns, 2, -1 do
        x = x - columns[i].width
        pos[i] = x
        x = x - COLUMN_GAP
    end
    pos[1] = ROW_PAD
    return pos, x - ROW_PAD
end

-- The name column: the two lines right of the icon (icon: its width, 0 without one), each cut off at the column's end.
function DB.PlaceName(f, icon)
    local cols = f.sheet.page.cols
    local x = cols.pos[1] + (icon > 0 and icon + 11 or 0)
    local w = cols.nameWidth - (x - cols.pos[1])
    f.name:ClearAllPoints()
    f.sub:ClearAllPoints()
    if f.sub:GetText() and f.sub:GetText() ~= "" then
        f.name:SetPoint("TOPLEFT", x, -6)
        f.sub:SetPoint("TOPLEFT", x, -24)
    else
        f.name:SetPoint("LEFT", x, 1)
    end
    f.name:SetWidth(w)
    f.sub:SetWidth(w)
end

-- A text cell of column i (its font, color and justification).
function DB.Cell(f, font, justify)
    local t = Widgets.Text(f, font or "bodySmall", DB.TEXT, nil, justify)
    return t
end

function DB.PlaceCell(f, cell, i, dy)
    local cols = f.sheet.page.cols
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", cols.pos[i], dy or 1)
    cell:SetWidth(f.sheet.page.def.columns[i].width)
end

---------------------------------------------------------------------------
-- Detail panel parts
---------------------------------------------------------------------------
-- The top of a detail panel: a soft glow at its left and a line under it. hero.glow is tinted by the page.
function DB.Hero(panel, height)
    local h = CreateFrame("Frame", nil, panel)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(height)
    h.glow = h:CreateTexture(nil, "BACKGROUND", nil, 1)
    h.glow:SetTexture(Theme.TEX.glow)
    h.glow:SetBlendMode("ADD")
    h.glow:SetSize(260, 190)
    h.glow:SetPoint("CENTER", h, "TOPLEFT", 52, -40)
    h.line = Widgets.Line(h, "BORDER", 0.06)
    h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT")
    h.line:SetPoint("BOTTOMRIGHT")
    return h
end

-- The buttons at the bottom of a detail panel: a main button (fills the width) and up to three icon buttons right of it.
-- actions.main, actions.icons[i]; DB.SetActions fills them.
function DB.Actions(panel)
    local a = CreateFrame("Frame", nil, panel)
    a:SetPoint("BOTTOMLEFT", 16, 16)
    a:SetPoint("BOTTOMRIGHT", -16, 16)
    a:SetHeight(32)
    a.main = Widgets.CreateButton(a, "", "primary", nil, 100, 32)
    a.main:SetMotionScriptsWhileDisabled(true)
    a.main:SetScript("OnClick", function(b) if b.handler then b.handler() end end)
    a.icons = {}
    for i = 1, 3 do
        local b = Widgets.CreateButton(a, nil, "ghost", "link", 36, 32)
        b:SetScript("OnClick", function(x) if x.handler then Util.PlaySound("IG_MAINMENU_OPTION") x.handler() end end)
        b:Hide()
        a.icons[i] = b
    end
    return a
end

-- main = { text, glyph, onClick, disabled, tryOn, tooltip, tooltipText }; icons = { { glyph, onClick, tryOn, tooltip,
-- tooltipText } } (tryOn: the action is Try on, off in combat: Widgets.SetTryOn)
function DB.SetActions(a, main, icons)
    local x = 0
    for i = #a.icons, 1, -1 do
        local def, b = icons[i], a.icons[i]
        if def then
            b.handler = def.onClick
            b:SetGlyph(def.glyph)
            Widgets.SetTryOn(b, def.tryOn)
            Widgets.SetTooltip(b, def.tooltip, def.tooltipText, "ANCHOR_TOP")
            b:ClearAllPoints()
            b:SetPoint("RIGHT", -x, 0)
            x = x + b:GetWidth() + 8
            b:Show()
        else
            b:Hide()
        end
    end
    a.main:ClearAllPoints()
    a.main:SetPoint("LEFT")
    a.main:SetPoint("RIGHT", -x, 0)
    a.main.handler = main.onClick
    a.main:SetGlyph(main.glyph)
    a.main:SetLabel(main.text)
    Widgets.SetTryOn(a.main, main.tryOn)
    if main.disabled then a.main:Disable() end
    Widgets.SetTooltip(a.main, main.tooltip, main.tooltipText, "ANCHOR_TOP")
end

-- A dark box of text lines (an item's stats, a place's facts): data = { lines = { text, ... } }. A line wider than the
-- box wraps (a place's status).
local BLOCK_LINE = 21
-- The height a line's wrapped lines after its first one take in a box of width w.
local function Wrapped(text, w)
    return Kit.TextHeight(text, "bodySemi", w - 24, 0) - Kit.TextHeight(text, "bodySemi", 2000, 0)
end
Kit.KINDS.dbBlock = {
    height = function(d, w)
        local h = 20 + #d.lines * BLOCK_LINE + 12
        for _, text in ipairs(d.lines) do h = h + Wrapped(text, w) end
        return h
    end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.fill = Widgets.CreateBox(f, "BACKGROUND", 1, 10)
        f.fill:SetAnchor(f, 0, 12, 0, 0)
        f.fill:SetColor(0, 0, 0, 0.28)
        f.ring = Widgets.CreateBox(f, "BACKGROUND", 2, 10, true)
        f.ring:SetAnchor(f, 0, 12, 0, 0)
        f.ring:SetColor(1, 1, 1, 0.06)
        f.lines = {}
        return f
    end,
    fill = function(f, d, w)
        local y = 12 + 10
        for i = 1, math.max(#d.lines, #f.lines) do
            local fs = f.lines[i]
            if not fs and d.lines[i] then
                fs = Widgets.Text(f, "bodySemi", C.text1)
                fs:SetWordWrap(true)
                f.lines[i] = fs
            end
            if d.lines[i] then
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", 12, -y)
                fs:SetWidth(w - 24)
                fs:SetText(d.lines[i])
                fs:Show()
                y = y + BLOCK_LINE + Wrapped(d.lines[i], w)
            elseif fs then
                fs:Hide()
            end
        end
    end,
}

-- A source of the detail (a mob that drops the item, a boss of a place): its face, name, a line below and a value at
-- the right (a drop chance). A click opens it. data = { text, sub, right, rightColor, onClick, and the face: boss + inst
-- (a boss), display + emblem + rare (a creature: its face, else the emblem), or glyph (a symbol: a random world drop) }
Kit.KINDS.dbSource = {
    height = 56,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        f.fill = Widgets.CreateBox(f, "BACKGROUND", 1, 10)
        f.fill:SetAnchor(f, 0, 0, 0, 6)
        f.ring = Widgets.CreateBox(f, "BACKGROUND", 2, 10, true)
        f.ring:SetAnchor(f, 0, 0, 0, 6)
        f.emblem = Widgets.CreateEmblem(f, 34)
        f.emblem:SetPoint("LEFT", 10, 3)
        f.glyph = Widgets.Glyph(f.emblem, "globe", 16, C.text2, "OVERLAY", 2)
        f.glyph:SetPoint("CENTER")
        f.name = Widgets.Text(f, "h3", C.text1)
        f.name:SetPoint("TOPLEFT", f.emblem, "TOPRIGHT", 10, 0)
        f.sub = Widgets.Text(f, "small", C.text3)
        f.sub:SetPoint("BOTTOMLEFT", f.emblem, "BOTTOMRIGHT", 10, 1)
        f.right = Widgets.CreatePill(f, 20, "count")
        f.right:SetPoint("RIGHT", -10, 3)
        local function Visual(self)
            self.fill:SetColor(1, 1, 1, self.hovered and 0.06 or 0.03)
            self.ring:SetColor(1, 1, 1, self.hovered and 0.12 or 0.06)
        end
        f.Visual = Visual
        f:SetScript("OnEnter", function(self) self.hovered = true Visual(self) end)
        f:SetScript("OnLeave", function(self) self.hovered = false Visual(self) end)
        f:SetScript("OnClick", function(self)
            local d = self.sheet.data[self.entry]
            if d.onClick then
                Util.PlaySound("IG_MAINMENU_OPTION")
                d.onClick(d)
            end
        end)
        return f
    end,
    fill = function(f, d, w)
        f.glyph:Hide()
        if d.boss then
            f.emblem:SetBoss(d.boss)
        elseif d.glyph then
            f.emblem:SetRare(false)
            f.emblem:SetGlyph("skull")
            f.emblem.glyph:Hide()
            Theme.SetGlyph(f.glyph, d.glyph, C.text2)
            f.glyph:Show()
        else
            f.emblem:SetRare(d.rare)
            f.emblem:SetCreature(d.display, d.emblem or "skull")
        end
        f.right:SetShown(d.right ~= nil)
        local rightW = 0
        if d.right then
            f.right:Set(d.right, "chance")
            f.right:SetTextColorOverride(d.rightColor or C.text2)
            rightW = f.right:GetWidth() + 10
        end
        f.name:SetText(d.text or "")
        f.sub:SetText(d.sub or "")
        f.name:SetWidth(w - 54 - 10 - rightW)
        f.sub:SetWidth(w - 54 - 10 - rightW)
        f:EnableMouse(d.onClick ~= nil)
        f.hovered = f:IsMouseOver()
        f:Visual()
    end,
}

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
-- def = {
--   key, scope (the chip in the search box), placeholder,
--   toggle = { key, label, tooltip, module } (a switch in the bar: state[key]; module: only while that module is on,
--     Core/Modules.lua),
--   sorts = { { key, text, column, compare(a, b) } } (column: the column the header marks),
--   filters = { { key, label, kind = "chips" (one choice) | "multi" (any choices, led by an "All" chip: every choice on;
--     with All on, a click on a choice leaves only that one on) | "checks" (check boxes with a colored
--     dot) | "range" (levels), options = { { key, text, glyph, color, module } } } } (module: a chip only while that
--     module is on; the group's first option stands for it while it is off),
--   columns = { { title, width, justify } } (the first: the name column, its width is what the others leave),
--   rowKind (a Kit kind: the row of a record; DB.CreateRow and the cells of the page), icon (the row icon's width),
--   Records() (every record: { id, ... }), SearchKey(rec) (the words the search finds a record by, DB.SearchKey; made
--   when a search first needs it), Passes(rec, state) (the filters), Prepare(list, state) (values for the sort before
--   it), Find(id) (a record by its ID, also one the filters hide),
--   CreateDetail(page, panel), FillDetail(page, rec) (the detail panel; nil: nothing picked),
--   OnRowEnter(f, rec), OnRowClick(f, rec, button) (true: handled), Empty(state) (the text of an empty table) }
-- The page's state (filters, sort, switch: DB.state[key], from LJ.DATABASE_DEFAULTS at the first use), the search text
-- and the picked record stay for the game session (not saved: every login and /reload starts fresh).
DB.state = {}

local function CopyDeep(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = type(v) == "table" and CopyDeep(v) or v end
    return copy
end

-- every choice of a "multi" filter group is on
local function AllOn(set, options)
    for _, opt in ipairs(options) do
        if not set[opt.key] then return false end
    end
    return true
end

function DB.Page(def)
    local page = { def = def }

    -- a record's search key, kept on the record (most opens of a page search nothing)
    local function SearchKey(rec)
        local key = rec.searchKey
        if not key then
            key = def.SearchKey(rec)
            rec.searchKey = key
        end
        return key
    end

    function page:State()
        DB.state[def.key] = DB.state[def.key] or CopyDeep(LJ.DATABASE_DEFAULTS[def.key])
        return DB.state[def.key]
    end

    function page:Create(root)
        self.records, self.byID = nil, nil
        self:CreateBar(root)
        self:CreateFilters(root)
        self:CreateTable(root)
        local panel = Kit.Panel(root, 0)
        panel:SetPoint("TOPLEFT", self.tablePanel, "TOPRIGHT", GAP, 0)
        panel:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        self.detail = panel
        def.CreateDetail(self, panel)
    end

    -- the search box with the page's scope, the number of results, the switch and the sort
    function page:CreateBar(root)
        local box = CreateFrame("EditBox", nil, root)
        box:SetSize(SEARCH_WIDTH, BAR_HEIGHT)
        box:SetPoint("TOPLEFT", MARGIN, -BAR_TOP)
        box:SetAutoFocus(false)
        box:SetFontObject(Theme.Font("bodySemi"))
        box:SetTextColor(C.white[1], C.white[2], C.white[3])
        box.panel = Widgets.CreatePanel(box, 12, "BACKGROUND", 1)
        box.panel:SetFill(0, 0, 0, 0.35)
        box.panel:SetBorder(1, 1, 1, 0.1)
        box.icon = Widgets.Glyph(box, "search", 15, C.text3)
        box.icon:SetPoint("LEFT", 12, 0)
        box.scope = Widgets.CreatePill(box, 22, "label")
        box.scope:SetPoint("LEFT", 37, 0)
        box.scope:Set(Util.Upper(L(def.scope)), "acc")
        box:SetTextInsets(37 + box.scope:GetWidth() + 10, 30, 0, 0)
        box.placeholder = Widgets.Text(box, "bodySmall", C.text4)
        box.placeholder:SetPoint("LEFT", box.scope, "RIGHT", 10, 0)
        box.placeholder:SetPoint("RIGHT", -30, 0)
        box.placeholder:SetText(L(def.placeholder))
        box.clear = Widgets.CreateButton(box, nil, "icon", "close", 22, 22)
        box.clear:SetPoint("RIGHT", -8, 0)
        box.clear:Hide()
        box.clear:SetScript("OnClick", function()
            box:SetText("")
            box:ClearFocus()
            self:Search("")
        end)
        box:SetScript("OnTextChanged", function(b, userInput)
            local text = b:GetText() or ""
            b.placeholder:SetShown(text == "")
            b.clear:SetShown(text ~= "")
            if userInput then
                LJ:Debounce("databaseSearch" .. def.key, 0.15, function() self:Search(b:GetText()) end)
            end
        end)
        box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
        box:SetScript("OnEditFocusGained", function(b)
            local a = Theme.accent
            b.panel:SetBorder(a[1], a[2], a[3], 0.55)
            b.icon:SetVertexColor(a[1], a[2], a[3], 1)
        end)
        box:SetScript("OnEditFocusLost", function(b)
            b.panel:SetBorder(1, 1, 1, 0.1)
            b.icon:SetVertexColor(C.text3[1], C.text3[2], C.text3[3], 1)
        end)
        self.search = box

        self.count = Widgets.Text(root, "bodySemi", C.text3)
        self.count:SetPoint("LEFT", box, "RIGHT", GAP, 0)

        self.sort = Widgets.CreateDropdown(root, nil, function(menu)
            for _, s in ipairs(def.sorts) do
                menu:CreateRadio(s.text, function() return self:State().sort == s.key end, function()
                    self:State().sort = s.key
                    self:Changed()
                end)
            end
        end, "", "list")
        self.sort:SetHeight(32)
        self.sort:SetPoint("RIGHT", root, "TOPRIGHT", -MARGIN, -(BAR_TOP + BAR_HEIGHT / 2))

        if def.toggle then
            self.toggle = Widgets.CreateToggle(root, def.toggle.label, def.toggle.tooltip)
            self.toggle:SetPoint("RIGHT", self.sort, "LEFT", -GAP, 0)
            self.toggle.onChange = function(_, on)
                self:State()[def.toggle.key] = on
                self:Changed()
            end
        end
    end

    -- the filters on the left (a scroll area: a long list of options still fits)
    function page:CreateFilters(root)
        local panel = Kit.Panel(root, 14)
        panel:SetPoint("TOPLEFT", MARGIN, -PANEL_TOP)
        panel:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        panel:SetWidth(FILTER_WIDTH)
        self.filterPanel = panel
        local scroll = Widgets.CreateScrollArea(panel.inner, 5)
        scroll:SetAllPoints()
        local content = scroll.content
        local width = FILTER_WIDTH - 28
        content:SetWidth(width)
        self.filterWidgets = {}
        local y = 0
        for gi, group in ipairs(def.filters) do
            if gi > 1 then y = y + 10 end
            y = y + FilterHeader(content, y, group.label)
            local widgets = {}
            self.filterWidgets[group.key] = widgets
            if group.kind == "chips" or group.kind == "multi" then
                local x, top = 0, y
                -- a multi group starts with its "All" chip (widgets.all, not in the list of choices)
                local chips = group.kind == "multi" and { { key = "ALL", text = "All" } } or {}
                for _, opt in ipairs(group.options) do chips[#chips + 1] = opt end
                for _, opt in ipairs(chips) do
                    local chip = Widgets.CreateChip(content, opt.text, opt.glyph, 22)
                    if x > 0 and x + chip:GetWidth() > width then
                        x, top = 0, top + 26
                    end
                    chip:SetPoint("TOPLEFT", x, -top)
                    x = x + chip:GetWidth() + 4
                    chip.key = opt.key
                    chip:SetScript("OnClick", function(c)
                        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
                        local state = self:State()
                        local set = state[group.key]
                        if group.kind == "chips" then
                            state[group.key] = c.key
                        elseif c.key == "ALL" then
                            for _, o in ipairs(group.options) do set[o.key] = true end
                        elseif AllOn(set, group.options) then
                            for _, o in ipairs(group.options) do set[o.key] = o.key == c.key end
                        else
                            set[c.key] = not set[c.key]
                        end
                        self:Changed()
                    end)
                    if opt.key == "ALL" and group.kind == "multi" then
                        widgets.all = chip
                    else
                        widgets[#widgets + 1] = chip
                    end
                end
                y = top + 22
            elseif group.kind == "checks" then
                for i, opt in ipairs(group.options) do
                    local check = CreateCheck(content, opt.text, opt.color)
                    check:SetPoint("TOPLEFT", 0, -y)
                    check:SetPoint("RIGHT", content, "RIGHT")
                    check.key = opt.key
                    check:SetScript("OnClick", function(c)
                        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
                        local list = self:State()[group.key]
                        list[c.key] = not list[c.key]
                        self:Changed()
                    end)
                    widgets[i] = check
                    y = y + 21
                end
            elseif group.kind == "range" then
                local range = CreateRange(content, width, function(lo, hi)
                    local r = self:State()[group.key]
                    r[1], r[2] = lo, hi
                    -- hidden by then (another page, the window closed): Show refreshes
                    LJ:Debounce("databaseRange" .. def.key, 0.12, function()
                        if self.root:IsVisible() then self:Changed() end
                    end)
                end)
                range:SetPoint("TOPLEFT", 0, -(y + 2))
                widgets[1] = range
                y = y + 40
            end
        end
        scroll:SetContentHeight(y + 4)
    end

    -- the table: the header with the column titles, the rows below it
    function page:CreateTable(root)
        local panel = Kit.Panel(root, 0)
        panel:SetPoint("TOPLEFT", self.filterPanel, "TOPRIGHT", GAP, 0)
        panel:SetPoint("BOTTOMLEFT", self.filterPanel, "BOTTOMRIGHT", GAP, 0)
        panel:SetWidth(TABLE_WIDTH)
        self.tablePanel = panel
        local inner = CreateFrame("Frame", nil, panel)
        inner:SetPoint("TOPLEFT", 8, -6)
        inner:SetPoint("BOTTOMRIGHT", -8, 6)
        local width = TABLE_WIDTH - 16
        DB.FitColumns(def.columns)
        local pos, nameWidth = DB.Columns(def.columns, width)
        self.cols = { pos = pos, nameWidth = nameWidth }
        local head = CreateFrame("Frame", nil, inner)
        head:SetPoint("TOPLEFT")
        head:SetPoint("TOPRIGHT")
        head:SetHeight(HEAD_HEIGHT)
        head.line = Widgets.Line(head, "BORDER", 0.06)
        head.line:SetHeight(1)
        head.line:SetPoint("BOTTOMLEFT")
        head.line:SetPoint("BOTTOMRIGHT")
        head.titles = {}
        for i, col in ipairs(def.columns) do
            local t = Widgets.Text(head, "label", C.text3, nil, col.justify)
            local x = pos[i] + (i == 1 and def.icon > 0 and def.icon + 11 or 0)
            t:SetPoint("LEFT", x, 0)
            t:SetWidth(i == 1 and (nameWidth - (x - pos[1])) or col.width)
            head.titles[i] = t
        end
        head.caret = Widgets.Glyph(head, "caretDown", 9, C.white)
        self.head = head
        local sheet = Kit.Sheet(inner, 3)
        sheet.page = self
        sheet.scroll:SetPoint("TOPLEFT", 0, -(HEAD_HEIGHT + 4))
        sheet.scroll:SetPoint("BOTTOMRIGHT")
        self.sheet = sheet
        self.empty = Widgets.CreateEmptyState(inner, "search", 300)
        self.empty:SetPoint("TOP", 0, -100)
        self.empty:Hide()
    end

    -- the column titles: the sorted column in the layout color with a caret
    function page:UpdateHead(sort)
        local a = Theme.accent
        local head = self.head
        head.caret:Hide()
        for i, col in ipairs(def.columns) do
            local t = head.titles[i]
            t:SetText(Util.Upper(L(col.title)))
            if sort.column == i then
                t:SetTextColor(a[1], a[2], a[3], 1)
                head.caret:SetVertexColor(a[1], a[2], a[3], 1)
                head.caret:ClearAllPoints()
                if col.justify == "RIGHT" then
                    t:SetPoint("LEFT", self.cols.pos[i] - 12, 0)
                    head.caret:SetPoint("RIGHT", t, "RIGHT", 12, 0)
                else
                    head.caret:SetPoint("LEFT", t, "LEFT", Widgets.TextWidth(t) + 4, 0)
                end
                head.caret:Show()
            else
                t:SetTextColor(C.text3[1], C.text3[2], C.text3[3], 1)
                if col.justify == "RIGHT" then t:SetPoint("LEFT", self.cols.pos[i], 0) end
            end
        end
    end

    function page:Records()
        if not self.records then
            self.records = def.Records()
            self.byID = {}
            for _, rec in ipairs(self.records) do self.byID[rec.id] = rec end
        end
        return self.records
    end

    function page:Find(id)
        self:Records()
        return self.byID[id] or (def.Find and def.Find(id)) or nil
    end

    -- the filters or the sort changed: from the top of the list
    function page:Changed()
        self.sheet:ScrollToTop()
        self:Refresh()
    end

    -- a search typed just before the page was hidden is kept for its next Show
    function page:Search(text)
        text = Util.Trim(text or "")
        if text == self.query then return end
        self.query = text
        if not self.root:IsVisible() then return end
        self.sheet:ScrollToTop()
        self:Refresh()
    end

    -- picks a record: its row is marked, its details show; nothing else moves
    function page:Select(id)
        self.selected, self.autoPicked = id, nil
        for _, f in ipairs(self.sheet:Frames(def.rowKind)) do
            f.selected = self.sheet.data[f.entry].id == id
            DB.RowVisual(f)
        end
        self:RefreshDetail()
    end

    function page:RefreshDetail()
        local rec = self.selected and self:Find(self.selected)
        def.FillDetail(self, rec)
    end

    function page:Refresh()
        local state = self:State()
        local sort
        for _, s in ipairs(def.sorts) do
            if s.key == state.sort then sort = s end
        end
        sort = sort or def.sorts[1]
        -- the widgets show the state; a switch or chip of a module that is off is gone and filters nothing
        if self.toggle then
            local on = not def.toggle.module or LJ.Modules.On(def.toggle.module)
            if not on then state[def.toggle.key] = false end
            self.toggle:SetShown(on)
            self.toggle:SetChecked(state[def.toggle.key] and true or false)
        end
        self.sort:SetLabel(F("Sort: %s", L(sort.text)))
        for _, group in ipairs(def.filters) do
            local widgets = self.filterWidgets[group.key]
            if group.kind == "chips" then
                for i, chip in ipairs(widgets) do
                    local module = group.options[i].module
                    local on = not module or LJ.Modules.On(module)
                    if not on and state[group.key] == chip.key then state[group.key] = group.options[1].key end
                    chip:SetShown(on)
                end
                for _, chip in ipairs(widgets) do chip:SetActive(state[group.key] == chip.key) end
            elseif group.kind == "multi" then
                local all = AllOn(state[group.key], group.options)
                widgets.all:SetActive(all)
                for _, chip in ipairs(widgets) do chip:SetActive(not all and state[group.key][chip.key]) end
            elseif group.kind == "checks" then
                for _, check in ipairs(widgets) do
                    check.checked = state[group.key][check.key] and true or false
                    CheckVisual(check)
                end
            elseif group.kind == "range" then
                local r = state[group.key]
                widgets[1]:Set(r[1], r[2])
            end
        end
        self:UpdateHead(sort)

        -- the records that match the search (every record without one) and pass the filters, sorted
        local tokens = DB.Tokens(self.query)
        local searching = #tokens > 0
        local list = {}
        for _, rec in ipairs(self:Records()) do
            if (not searching or Matches(SearchKey(rec), tokens)) and def.Passes(rec, state) then list[#list + 1] = rec end
        end
        if def.Prepare then def.Prepare(list, state, sort) end
        table.sort(list, sort.compare)
        self.list = list
        -- nothing picked yet: the first row, before the rows are made (they mark the picked one); it follows the list
        -- until a record is picked (an item whose data arrives later can sort above it)
        if (self.autoPicked or not self.selected) and list[1] then
            self.selected, self.autoPicked = list[1].id, true
        end
        self.count:SetText(Theme.ColorText(tostring(#list), C.white) .. " " .. Util.PluralWord(#list, "result"))

        local sheet = self.sheet
        sheet:Reset(TABLE_WIDTH - 16)
        local rowY
        for _, rec in ipairs(list) do
            if rec.id == self.selected then rowY = sheet.cursor end
            sheet:Add(def.rowKind, rec, DB.ROW_HEIGHT)
        end
        sheet:Finish(4)
        self.empty:SetShown(#list == 0)
        if #list == 0 then
            self.empty:Set(L("Nothing found"), L(def.Empty and def.Empty(state) or "Nothing matches the search and the filters."),
                "search", "Reset filters", function() self:ResetFilters() end, "reset")
        end
        -- a record shown from elsewhere (a link, the search) is scrolled into view once
        if self.reveal and rowY then
            local top, view = sheet.scroll:GetVerticalScroll(), sheet.scroll:GetHeight() or 0
            if rowY < top or rowY + DB.ROW_HEIGHT > top + view then sheet:Reveal(rowY, 60) end
        end
        self.reveal = nil
        self:RefreshDetail()
    end

    -- every filter and the switch back to their defaults (the sort and the search stay)
    function page:ResetFilters()
        local state, defaults = self:State(), LJ.DATABASE_DEFAULTS[def.key]
        for key, value in pairs(defaults) do
            if key ~= "sort" then
                if type(value) == "table" then
                    for k, v in pairs(value) do state[key][k] = v end
                else
                    state[key] = value
                end
            end
        end
        self:Changed()
    end

    -- id: the record to show (a link from another page or look; without a query its name is the search); query: a
    -- search text
    function page:Show(id, query)
        local rec = id ~= nil and self:Find(id) or nil
        if rec and query == nil then query = rec.name end
        -- a search from elsewhere without a record: its first result is picked, not an earlier pick
        if not rec and query ~= nil then self.selected, self.autoPicked = nil, nil end
        if query ~= nil then
            self.query = Util.Trim(query)
            self.search:SetText(self.query)
            self.sheet:ScrollToTop()
        end
        if rec then
            self.selected, self.autoPicked = id, nil
            self.reveal = true
        end
        self:Refresh()
    end

    -- nothing of the results is kept while the page is hidden
    function page:OnHide()
        self.sheet:Clear()
        self.list = nil
        self.search:ClearFocus()
    end

    UI:RegisterPage(def.key, page, { "database" })
    return page
end

-- The records are made again the next time the window opens.
LJ:Listen("WINDOW_CLOSED", function()
    for _, t in ipairs(DB.TABS) do
        local page = UI.pageSets.database[t.key]
        page.records, page.byID = nil, nil
    end
end)

-- The map buttons of the details (an entrance, a mob's camps, where a quest starts and ends) show whether their spot
-- is marked: the shown page's details are drawn again when the mark changes.
LJ:Listen("MAP_TARGET_CHANGED", function()
    for _, t in ipairs(DB.TABS) do
        local page = UI.pageSets.database[t.key]
        if page.root and page.root:IsVisible() then page:RefreshDetail() end
    end
end)

-- Forever item records arrive asynchronously. Refresh visible database rows so newly
-- available stats immediately produce their percentage comparison.
LJ:Listen("ITEMS_UPDATED", function()
    for _, t in ipairs(DB.TABS) do
        local page = UI.pageSets.database[t.key]
        if page.root and page.root:IsVisible() then page:Refresh() end
    end
end)
