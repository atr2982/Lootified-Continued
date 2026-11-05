-- Lootified - the kit of the pane pages (UI/Pane/): every page of the classic look, For you, the journal and Open
-- World of the modern look; the database pages (UI/Database/) fill their sheets with its kinds too. A page shows dark
-- panels with the rows as small boxes: the classic look in brown leather and bronze lines (the picked row crimson), the
-- glass looks as dark glass (the picked row lighter, with a bar in the layout color). The panes hold a sheet: a scroll
-- list that only builds the rows in view (a dungeon with hundreds of drops builds the same few rows), filled from the
-- row kinds below (section titles, texts, list rows, item cells, mob headers, buttons, quests).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Kit = {}
LJ.Kit = Kit

local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local BiS = LJ.BiS
local C = Theme.COLORS

-- The looks of most pane pages (For you, the journal and Open World draw the modern look too).
Kit.LOOKS = { "classic" }

-- Sizes: item cell and its icon, list row, mob header, section title, page header. The rows have a gap of ROW_GAP below
-- their boxes (part of their height).
local METRICS = { item = 48, icon = 34, row = 38, rowSub = 46, mob = 36, section = 34, header = 40 }
function Kit.M() return METRICS end
local ROW_GAP = 4

-- How far a row's content sits above the row's middle: half the gap under the boxes.
function Kit.RowDY() return ROW_GAP / 2 end

function Kit.SectionColor() return Theme.PANE.section end

-- A hairline: a bronze line in the classic look, a faint white on the dark panel otherwise.
function Kit.Line(parent, layer)
    if Theme.IsClassic() then return Widgets.Solid(parent, layer or "BORDER", 0, Theme.HEARTH.line, 0.18) end
    return Widgets.Solid(parent, layer or "BORDER", 0, { 1, 1, 1 }, 0.07)
end

-- A hairline that fades out to the right (section titles and headers of the boxed looks).
function Kit.FadeLine(parent, alpha)
    local c = Theme.PANE.line
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(Util.WHITE)
    t:SetHeight(1)
    t:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], (alpha or 0.5) * c[4]), CreateColor(c[1], c[2], c[3], 0))
    return t
end

-- A panel of the boxed looks: dark brown in a bronze line (classic), dark glass (modern). panel.inner is the area
-- inside its padding.
local PANEL_PAD = 12
function Kit.Panel(parent, pad)
    local p = CreateFrame("Frame", nil, parent)
    p.fill = Widgets.CreateBox(p, "BACKGROUND", -2, Theme.PANE.radius)
    p.ring = Widgets.CreateBox(p, "BACKGROUND", -1, Theme.PANE.radius, true)
    Widgets.BoxFill(p.fill, p.ring, "panel")
    p.inner = CreateFrame("Frame", nil, p)
    p.inner:SetPoint("TOPLEFT", pad or PANEL_PAD, -(pad or PANEL_PAD))
    p.inner:SetPoint("BOTTOMRIGHT", -(pad or PANEL_PAD), pad or PANEL_PAD)
    return p
end

-- A small link back to a start page ("< All dungeons") above a page's title (classic look). SetLabel(text) names it.
function Kit.BackLink(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(14)
    b.glyph = Widgets.Glyph(b, "caretLeft", 10, C.text3)
    b.glyph:SetPoint("LEFT")
    b.text = Widgets.Text(b, "small", C.text3)
    b.text:SetPoint("LEFT", b.glyph, "RIGHT", 3, 0)
    b:SetScript("OnEnter", function(self)
        Widgets.SetTextColor(self.text, C.white)
        self.glyph:SetVertexColor(C.white[1], C.white[2], C.white[3])
    end)
    b:SetScript("OnLeave", function(self)
        Widgets.SetTextColor(self.text, C.text3)
        self.glyph:SetVertexColor(C.text3[1], C.text3[2], C.text3[3])
    end)
    b:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        onClick()
    end)
    function b:SetLabel(text)
        self.text:SetText(L(text))
        self:SetWidth(13 + Widgets.TextWidth(self.text) + 2)
    end
    return b
end

-- A small round badge with a level, at the bottom left of a portrait (boxed looks): its ring bronze (classic) or in the
-- layout color (modern).
function Kit.Badge(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b:SetFrameLevel(parent:GetFrameLevel() + 3)
    b.bg = b:CreateTexture(nil, "ARTWORK", nil, 0)
    b.bg:SetTexture(Theme.TEX.circle)
    b.bg:SetAllPoints()
    local fill = Theme.PANE.badgeFill
    b.bg:SetVertexColor(fill[1], fill[2], fill[3], 1)
    b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.ring:SetTexture(Theme.TEX.circleRingThin)
    b.ring:SetAllPoints()
    if Theme.IsClassic() then
        b.ring:SetVertexColor(0.66, 0.54, 0.29, 1)
    else
        Theme.OnAccent(b, function(x, r, g, bl) x.ring:SetVertexColor(r, g, bl, 1) end)
    end
    b.text = Widgets.Text(b, size >= 22 and "tiny" or "pillTiny", C.white, "OVERLAY", "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    return b
end

---------------------------------------------------------------------------
-- Text measuring (wrapped texts get the height their lines need)
---------------------------------------------------------------------------
local measure
local function Measure(text, font, width, spacing)
    if not measure then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(10, 10)
        holder:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -400, 400)
        holder:SetAlpha(0)
        measure = Theme.PrepareFontString(holder:CreateFontString(nil, "OVERLAY"))
        measure:SetJustifyH("LEFT")
        measure:SetWordWrap(true)
    end
    measure:SetFontObject(Theme.Font(font or "body"))
    measure:SetSpacing(spacing or 2)
    measure:SetWidth(math.max(20, width))
    measure:SetText(text or "")
    return measure
end

function Kit.TextHeight(text, font, width, spacing)
    return math.max(12, Measure(text, font, width, spacing):GetStringHeight() or 12)
end

-- The width of a text on one line.
function Kit.TextWidth(text, font)
    return Widgets.TextWidth(Measure(text, font, 2000, 0))
end

---------------------------------------------------------------------------
-- The two panes
---------------------------------------------------------------------------
-- Two panels side by side, the left one SIDE_WIDTH wide (or the page's width), GAP apart.
local SIDE_WIDTH, GAP = 300, 12

-- Kit.Book(root, leftWidth) -> book: book.left and book.right are the panes (frames inside the panels' padding) the
-- page fills; book.leftPanel and book.rightPanel are the panels around them, book.frame the frame around both.
function Kit.Book(root, leftWidth)
    local left = Kit.Panel(root)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(leftWidth or SIDE_WIDTH)
    local right = Kit.Panel(root)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    return { left = left.inner, right = right.inner, leftPanel = left, rightPanel = right, frame = root }
end

-- The header of a pane: title, a text beside it and a line under it that fades out (the look's title color; the glass
-- title in capitals). header.title, header.sub, header.height. Controls go to its right end.
function Kit.PaneHeader(pane)
    local m = Kit.M()
    local h = CreateFrame("Frame", nil, pane)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(m.header)
    h.height = m.header
    h.title = Widgets.Text(h, "titleSmall", Theme.PANE.title)
    h.title:SetPoint("LEFT", 0, 3)
    h.sub = Widgets.Text(h, "bodySmall", C.text4)
    h.sub:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 10, 1)
    h.line = Kit.FadeLine(h, 0.55)
    h.line:SetPoint("BOTTOMLEFT", 0, 6)
    h.line:SetPoint("BOTTOMRIGHT", 0, 6)
    -- the title keeps room for the sub text and the controls on the right (width: what is left)
    function h:Set(title, sub, rightWidth)
        self.title:SetText(Theme.Case(title or ""))
        self.sub:SetText(sub or "")
        local w = self:GetWidth()
        if not w or w < 50 then w = 400 end
        local room = w - 12 - (rightWidth or 0)
        self.title:SetWidth(0)
        local tw = Widgets.TextWidth(self.title) + 2
        self.title:SetWidth(math.min(tw, room))
        self.sub:SetWidth(math.max(10, room - self.title:GetWidth() - 10))
    end
    return h
end

---------------------------------------------------------------------------
-- Sheet: a scroll list of placed entries; only the entries in view (and a margin) have a frame
---------------------------------------------------------------------------
local Sheet = {}
Sheet.__index = Sheet
local BUFFER = 120
Kit.KINDS = {}

function Kit.Sheet(parent, barOffset)
    local scroll = Widgets.CreateScrollArea(parent, barOffset or -8)
    local sheet = setmetatable({ scroll = scroll, content = scroll.content, pools = {}, bound = {},
        kind = {}, data = {}, x = {}, y = {}, w = {}, h = {}, n = 0, cursor = 0, maxH = 0, width = 300 }, Sheet)
    scroll.onScroll = function() if not sheet.building then sheet:Bind(false) end end
    return sheet
end

-- Starts a new layout: every entry is dropped, the width is read again.
function Sheet:Reset(defaultWidth)
    self.n, self.cursor, self.maxH = 0, 0, 0
    local w = self.scroll:GetWidth()
    if not w or w < 50 then w = defaultWidth or self.width end
    self.width = w
    return w
end

-- An entry of a kind at x, y (from the top left) with its size; does not move the cursor. Entries are placed top down
-- (y never smaller than the one before; side by side entries share a y).
function Sheet:Place(kind, data, x, y, w, h)
    if h > self.maxH then self.maxH = h end
    local n = self.n + 1
    self.n = n
    self.kind[n], self.data[n], self.x[n], self.y[n], self.w[n], self.h[n] = kind, data, x, y, w, h
    return n
end

-- An entry across the whole width at the cursor; the cursor moves below it. h: the height (nil: the kind's).
function Sheet:Add(kind, data, h, indent)
    local k = Kit.KINDS[kind]
    indent = indent or 0
    h = h or (type(k.height) == "function" and k.height(data, self.width - indent) or k.height)
    self:Place(kind, data, indent, self.cursor, self.width - indent, h)
    self.cursor = self.cursor + h
    return h
end

function Sheet:Space(h)
    self.cursor = self.cursor + (h or 6)
end

-- Entries in columns: list of datas, cols columns of equal width, rows of height h (each data gets .col and .cols).
function Sheet:Grid(kind, list, cols, h, gap, indent)
    gap, indent = gap or 0, indent or 0
    local w = (self.width - indent - gap * (cols - 1)) / cols
    for i, data in ipairs(list) do
        local col = (i - 1) % cols
        data.col, data.cols = col + 1, cols
        self:Place(kind, data, indent + col * (w + gap), self.cursor + math.floor((i - 1) / cols) * h, w, h)
    end
    self.cursor = self.cursor + math.ceil(#list / cols) * h
end

-- Ends the layout: the content gets its height, the entries in view their frames.
function Sheet:Finish(extra)
    for i = self.n + 1, #self.kind do
        self.kind[i], self.data[i], self.x[i], self.y[i], self.w[i], self.h[i] = nil, nil, nil, nil, nil, nil
    end
    self.building = true
    self.scroll:SetContentHeight(self.cursor + (extra or 8))
    self.building = false
    self:Bind(true)
end

function Sheet:Release(frame)
    self.bound[frame.entry] = nil
    frame.entry = nil
    frame:Hide()
end

-- Binds the entries in view: frames of entries that scrolled out are freed, entries that scrolled in get a free frame
-- of their kind. force: fill every frame again (a new layout).
function Sheet:Bind(force)
    local n = self.n
    local offset = self.scroll:GetVerticalScroll() or 0
    local top, bottom = offset - BUFFER, offset + (self.scroll:GetHeight() or 0) + BUFFER
    local ys, hs = self.y, self.h
    for _, pool in pairs(self.pools) do
        for _, f in ipairs(pool) do
            local i = f.entry
            if i and (force or i > n or ys[i] + hs[i] < top or ys[i] > bottom) then self:Release(f) end
        end
    end
    -- entries are placed top down: the first one that can reach into the view starts at most the tallest entry's
    -- height above it (side by side entries of different heights: columns, grids)
    local from = top - self.maxH
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if ys[mid] < from then lo = mid + 1 else hi = mid end
    end
    for i = lo, n do
        if ys[i] > bottom then break end
        if ys[i] + hs[i] >= top and not self.bound[i] then self:BindEntry(i) end
    end
end

function Sheet:BindEntry(i)
    local kind = self.kind[i]
    local pool = self.pools[kind]
    if not pool then
        pool = {}
        self.pools[kind] = pool
    end
    local f
    for _, x in ipairs(pool) do
        if not x.entry then
            f = x
            break
        end
    end
    if not f then
        f = Kit.KINDS[kind].create(self.content, self)
        f.sheet = self
        pool[#pool + 1] = f
    end
    f.entry = i
    self.bound[i] = f
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", self.content, "TOPLEFT", self.x[i], -self.y[i])
    f:SetSize(self.w[i], self.h[i])
    Kit.KINDS[kind].fill(f, self.data[i], self.w[i], self.h[i])
    f:Show()
end

-- Every bound frame of a kind (tests, the tour).
function Sheet:Frames(kind)
    local list = {}
    for _, f in ipairs(self.pools[kind] or {}) do
        if f.entry then list[#list + 1] = f end
    end
    table.sort(list, function(a, b) return a.entry < b.entry end)
    return list
end

-- Scrolls so that y (from the top of the content) is near the top of the view.
function Sheet:Reveal(y, margin)
    self.scroll:ScrollTo(math.max(0, y - (margin or 8)))
end

function Sheet:ScrollToTop() self.scroll:ScrollTo(0) end

-- Drops every frame's entry and the layout (the page was hidden: nothing of the layout is kept).
function Sheet:Clear()
    for _, pool in pairs(self.pools) do
        for _, f in ipairs(pool) do
            if f.entry then self:Release(f) end
        end
    end
    for i = #self.kind, 1, -1 do
        self.kind[i], self.data[i], self.x[i], self.y[i], self.w[i], self.h[i] = nil, nil, nil, nil, nil, nil
    end
    self.n = 0
end

---------------------------------------------------------------------------
-- Hover and selection marks
---------------------------------------------------------------------------
-- A row's background: a box, lighter on hover; selected: crimson (classic) or lighter (glass). The selected row of the
-- glass looks has a bar in the layout color.
local function MarkVisual(f)
    Widgets.BoxFill(f.box, f.ring, f.selected and "pick" or "row", f.hovered)
    if f.bar then
        local a = Theme.accent
        f.bar:SetVertexColor(a[1], a[2], a[3], 1)
        f.bar:SetShown(f.selected and true or false)
    end
end
Kit.MarkVisual = MarkVisual

-- Adds the hover / selection background to a button-like frame: the row's box, ROW_GAP shorter than the row; the glass
-- looks: the bar of the selected row too.
function Kit.AddMarks(f)
    f.box = Widgets.CreateBox(f, "BACKGROUND", 1, 4)
    f.box:SetAnchor(f, 0, 0, 0, ROW_GAP)
    f.ring = Widgets.CreateBox(f, "BACKGROUND", 2, 4, true)
    f.ring:SetAnchor(f, 0, 0, 0, ROW_GAP)
    if Theme.IsClassic() then return end
    f.bar = f:CreateTexture(nil, "ARTWORK", nil, -1)
    f.bar:SetTexture(Util.WHITE)
    f.bar:SetWidth(3)
    f.bar:SetPoint("TOPLEFT", 0, -1)
    f.bar:SetPoint("BOTTOMLEFT", 0, ROW_GAP + 1)
    f.bar:Hide()
    Theme.OnAccent(f, function(x) if x.selected then MarkVisual(x) end end)
end

---------------------------------------------------------------------------
-- Kinds. Each: height (number, or function(data, width)), create(parent, sheet) -> frame, fill(frame, data, w, h).
---------------------------------------------------------------------------
-- A section title: data = { text, count (small text after it), actions = { { text, glyph, onClick, tooltip,
-- tooltipText } } (small buttons at its right end) }
Kit.KINDS.section = {
    height = function() return Kit.M().section end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.text = Widgets.Text(f, Theme.IsClassic() and "h2" or "label", Kit.SectionColor())
        f.text:SetPoint("BOTTOMLEFT", 0, 10)
        f.count = Widgets.Text(f, "small", C.text4)
        f.count:SetJustifyH("LEFT")
        f.count:SetWordWrap(false)
        f.line = Kit.FadeLine(f, 0.5)
        f.line:SetPoint("LEFT", f.count, "RIGHT", 9, 0)
        f.line:SetPoint("RIGHT", 0, 0)
        f.actions = {}
        return f
    end,
    fill = function(f, d)
        f.text:SetText(Theme.IsClassic() and d.text or Util.Upper(d.text or ""))
        f.count:SetText(d.count and tostring(d.count) or "")
        local defs = d.actions or {}
        local left
        for i = math.max(#defs, #f.actions), 1, -1 do
            local def, b = defs[i], f.actions[i]
            if def and not b then
                b = Widgets.CreateButton(f, "", "ghost", nil, nil, 22)
                b:SetScript("OnClick", function(btn)
                    Util.PlaySound("IG_MAINMENU_OPTION")
                    btn.handler()
                end)
                f.actions[i] = b
            end
            if def then
                b.handler = def.onClick
                b:SetGlyph(def.glyph)
                b:SetLabel(def.text)
                Widgets.SetTooltip(b, def.tooltip, def.tooltipText, "ANCHOR_TOP")
                b:ClearAllPoints()
                if left then b:SetPoint("RIGHT", left, "LEFT", -6, 0) else b:SetPoint("BOTTOMRIGHT", 0, 6) end
                left = b
                b:Show()
            elseif b then
                b:Hide()
            end
        end
        -- with buttons the count ends before them (cut when too long) and there is no line
        f.count:ClearAllPoints()
        f.count:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 7, 1)
        if left then f.count:SetPoint("RIGHT", left, "LEFT", -8, 0) end
        f.line:SetShown(not left)
    end,
}

-- A wrapped text: data = { text, font, color, indent, spacing, justify }
Kit.KINDS.text = {
    height = function(d, w)
        return math.ceil(Kit.TextHeight(d.text, d.font or "body", w - (d.indent or 0) * 2, d.spacing or 2)) + (d.pad or 4)
    end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.text = Theme.PrepareFontString(f:CreateFontString(nil, "OVERLAY"))
        f.text:SetJustifyV("TOP")
        f.text:SetWordWrap(true)
        return f
    end,
    fill = function(f, d, w)
        f.text:SetFontObject(Theme.Font(d.font or "body"))
        f.text:SetSpacing(d.spacing or 2)
        f.text:SetJustifyH(d.justify or "LEFT")
        f.text:ClearAllPoints()
        f.text:SetPoint("TOPLEFT", d.indent or 0, -2)
        f.text:SetWidth(w - (d.indent or 0) * 2)
        f.text:SetText(d.text or "")
        local c = d.color or C.text2
        f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end,
}

-- List row (selectable): data = { text, sub (second line), right (text at the right), rightColor, num (number at the
-- left), glyph (glyph at the left), glyphColor, tag (small tag after the text, e.g. RARE), tagKind, color (text color),
-- selected, dim, onClick(data, button), onEnter(frame, data) }
local function RowOnEnter(f)
    f.hovered = true
    MarkVisual(f)
    local d = f.sheet.data[f.entry]
    if d and d.onEnter then d.onEnter(f, d) end
end

local function RowOnLeave(f)
    f.hovered = false
    MarkVisual(f)
    if GameTooltip:GetOwner() == f then GameTooltip:Hide() end
end

local function RowOnClick(f, button)
    local d = f.sheet.data[f.entry]
    if d and d.onClick then
        Util.PlaySound("IG_MAINMENU_OPTION")
        d.onClick(d, button)
    end
end

Kit.KINDS.row = {
    height = function(d) return d.sub and Kit.M().rowSub or Kit.M().row end,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Kit.AddMarks(f)
        f.num = Widgets.Text(f, "count", C.text4, nil, "RIGHT")
        f.num:SetWidth(18)
        f.glyph = f:CreateTexture(nil, "ARTWORK")
        f.glyph:SetSize(14, 14)
        f.text = Widgets.Text(f, "item", C.text1)
        f.sub = Widgets.Text(f, "small", C.text3)
        f.tag = Widgets.CreatePill(f, 15, "pillTiny")
        f.right = Widgets.Text(f, "smallSemi", C.text3, nil, "RIGHT")
        f:SetScript("OnEnter", RowOnEnter)
        f:SetScript("OnLeave", RowOnLeave)
        f:SetScript("OnClick", RowOnClick)
        return f
    end,
    fill = function(f, d, w)
        local pad = 10
        local dy = Kit.RowDY()
        local x = pad
        f.num:SetShown(d.num ~= nil)
        f.glyph:SetShown(d.glyph ~= nil)
        if d.num then
            f.num:SetText(tostring(d.num))
            f.num:ClearAllPoints()
            f.num:SetPoint("LEFT", x - 6, dy)
            x = x + 18
        elseif d.glyph then
            Theme.SetGlyph(f.glyph, d.glyph, d.glyphColor or C.text3)
            f.glyph:ClearAllPoints()
            f.glyph:SetPoint("LEFT", x, dy)
            x = x + 20
        end
        f.right:SetText(d.right or "")
        local rc = d.rightColor or C.text3
        f.right:SetTextColor(rc[1], rc[2], rc[3])
        f.right:ClearAllPoints()
        f.right:SetPoint("RIGHT", -pad, dy)
        local rightW = (d.right and d.right ~= "") and (Widgets.TextWidth(f.right) + 10) or 0
        f.text:SetFontObject(Theme.Font(d.font or "item"))
        f.text:SetText(d.text or "")
        local c = d.color or (d.selected and Theme.PANE.pickText) or (d.dim and C.text3) or Theme.ListNameColor()
        f.text:SetTextColor(c[1], c[2], c[3])
        local tagW = 0
        if d.tag then
            f.tag:Set(d.tag, d.tagKind or "neutral")
            tagW = f.tag:GetWidth() + 6
        end
        f.tag:SetShown(d.tag ~= nil)
        local room = w - x - pad - rightW - tagW
        f.text:SetWidth(0)
        f.text:SetWidth(math.max(30, math.min(Widgets.TextWidth(f.text) + 2, room)))
        f.text:ClearAllPoints()
        f.sub:ClearAllPoints()
        if d.sub then
            f.text:SetPoint("TOPLEFT", x, -6)
            f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -2)
            f.sub:SetWidth(math.max(30, w - x - pad - rightW))
            f.sub:SetText(d.sub)
            f.sub:Show()
        else
            f.text:SetPoint("LEFT", x, dy)
            f.sub:Hide()
        end
        f.tag:ClearAllPoints()
        f.tag:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
        f.selected = d.selected
        f.hovered = f:IsMouseOver()
        MarkVisual(f)
        f:SetAlpha(d.dim and 0.75 or 1)
    end,
}

-- Item cell: icon, name in its quality color, a second line (slot, or where it drops), the upgrade mark (an item of the
-- Best in Slot list) and the drop chance; the wishlist star shows on hover and on wished items. data = { id, chance,
-- upgrade (BiS.Upgrade), unusable, sub, tag (text instead of the chance, e.g. CHOICE), count, extraTooltip, onClick(data),
-- col, cols (grid) }
local function CellVisual(f)
    local wished = f.itemID and Items.IsWishlisted(f.itemID)
    f.star:SetShown(((f.hovered and LJ.Modules.On("wishlist")) or wished) and true or false)
    if f.star:IsShown() then
        Theme.SetGlyph(f.star.tex, wished and "star" or "starLine", wished and C.gold or C.text4)
    end
    Widgets.BoxFill(f.box, f.ring, "row", f.hovered)
end

local function CellOnUpdate(f)
    if f.itemID and IsModifiedClick("DRESSUP") then
        ShowInspectCursor()
    else
        ResetCursor()
    end
end

local function CellOnEnter(f)
    f.hovered = true
    CellVisual(f)
    local d = f.sheet.data[f.entry]
    Widgets.ShowItemTooltip(f, f.itemID, d and d.extraTooltip)
    f:SetScript("OnUpdate", CellOnUpdate)
end

local function CellOnLeave(f)
    f.hovered = false
    CellVisual(f)
    GameTooltip:Hide()
    f:SetScript("OnUpdate", nil)
    ResetCursor()
end

local function CellOnClick(f, button)
    if not f.itemID then return end
    if Items.HandleClick(f.itemID, button) then return end
    if button == "RightButton" then
        Widgets.ShowItemMenu(f, f.itemID)
        return
    end
    local d = f.sheet.data[f.entry]
    if d and d.onClick then d.onClick(d) end
end

local function StarOnClick(star)
    local f = star:GetParent()
    if f.itemID then Items.ToggleWishlist(f.itemID) end
end

Kit.KINDS.item = {
    height = function() return Kit.M().item end,
    create = function(parent)
        local m = Kit.M()
        local f = CreateFrame("Button", nil, parent)
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        Kit.AddMarks(f)
        f.icon = Widgets.CreateItemIcon(f, m.icon)
        f.icon:SetPoint("LEFT", 6, Kit.RowDY())
        f.icon:EnableMouse(false)
        f.name = Widgets.Text(f, "item", C.text1)
        f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
        f.sub = Widgets.Text(f, "small", C.text3)
        f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, 1)
        f.chance = Widgets.Text(f, "h3", C.text2, nil, "RIGHT")
        f.marks = Widgets.Text(f, "nameBold", C.okText, nil, "RIGHT")
        f.star = CreateFrame("Button", nil, f)
        f.star:SetSize(18, 18)
        f.star:SetPoint("RIGHT", -6, Kit.RowDY())
        f.star:SetFrameLevel(f:GetFrameLevel() + 3)
        f.star.tex = Widgets.Glyph(f.star, "starLine", 12, C.text4)
        f.star.tex:SetPoint("CENTER")
        f.star:SetScript("OnClick", StarOnClick)
        f.star:SetScript("OnEnter", function(s)
            local cell = s:GetParent()
            cell.hovered = true
            CellVisual(cell)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            local wished = cell.itemID and Items.IsWishlisted(cell.itemID)
            GameTooltip:SetText(L(wished and "Remove from Wishlist" or "Add to Wishlist"), 1, 1, 1)
            GameTooltip:Show()
        end)
        f.star:SetScript("OnLeave", function(s)
            local cell = s:GetParent()
            cell.hovered = cell:IsMouseOver()
            CellVisual(cell)
            GameTooltip:Hide()
        end)
        f:SetScript("OnEnter", CellOnEnter)
        f:SetScript("OnLeave", CellOnLeave)
        f:SetScript("OnClick", CellOnClick)
        return f
    end,
    fill = function(f, d, w)
        local id = d.id
        f.itemID = id
        local rec = Items.Get(id)
        f.icon:SetItem(id, d.count)
        f.icon:SetOwned(Items.IsOwned(id))
        local r, g, b = Util.QualityColor(rec.quality or 1)
        if rec.isQuest and not rec.loaded then r, g, b = C.text1[1], C.text1[2], C.text1[3] end
        f.name:SetText(rec.name or rec.fallbackName or F("Item #%d", id))
        f.name:SetTextColor(r, g, b)
        f.sub:SetText(d.sub or Items.GetSlotText(id) or "")
        Widgets.SetTextColor(f.sub, d.unusable and C.bad or C.text3)
        -- right: the wishlist star, the chance (or a tag) left of it, the marks left of that
        local dy = Kit.RowDY()
        local right = 28
        if d.tag then
            f.chance:SetText(L(d.tag))
            Widgets.SetTextColor(f.chance, C.goldText)
        elseif d.chance and d.chance > 0 then
            f.chance:SetText(Util.FormatChance(d.chance) or "")
            Widgets.SetTextColor(f.chance, Theme.IsClassic() and C.text2 or Theme.ChanceColor(d.chance))
        else
            f.chance:SetText("")
        end
        f.chance:ClearAllPoints()
        f.chance:SetPoint("RIGHT", -right, dy)
        local chanceW = (f.chance:GetText() ~= "") and math.max(Widgets.TextWidth(f.chance), 34) + 8 or 0
        local marks = {}
        local upText = d.upgrade and BiS.FormatUpgrade(id)
        if upText then marks[#marks + 1] = Theme.GlyphString("upgrade", 11, C.okText) .. " " .. upText end
        f.marks:SetText(table.concat(marks, "  "))
        f.marks:ClearAllPoints()
        f.marks:SetPoint("RIGHT", -(right + chanceW), dy)
        local marksW = #marks > 0 and (Widgets.TextWidth(f.marks) + 8) or 0
        local room = w - 6 - Kit.M().icon - 10 - right - chanceW - marksW - 4
        f.name:SetWidth(0)
        f.name:SetWidth(math.max(40, math.min(Widgets.TextWidth(f.name) + 2, room)))
        f.sub:SetWidth(math.max(40, room))
        f:SetAlpha(d.unusable and 0.55 or 1)
        f.hovered = f:IsMouseOver()
        CellVisual(f)
    end,
}

-- Mob or boss header in a loot list: name, a tag (RARE, elite), the level line and an optional map button.
-- data = { text, tag, tagKind, sub, mob (map button for its camps), itemName (map marker text), onClick(data) }
local function MapButtonClick(b)
    local d = b.cell and b.cell.sheet.data[b.cell.entry]
    if d and d.mob then LJ.Lists.MarkNextCamp(d.mob, d.itemName) end
end

Kit.KINDS.mob = {
    height = function() return Kit.M().mob end,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        f.name = Widgets.Text(f, Theme.IsClassic() and "h2" or "nameBold", C.white)
        f.name:SetPoint("BOTTOMLEFT", Theme.IsClassic() and 0 or 10, 7)
        f.tag = Widgets.CreatePill(f, 15, "pillTiny")
        f.tag:SetPoint("LEFT", f.name, "RIGHT", 7, 0)
        f.sub = Widgets.Text(f, "small", C.text3)
        f.line = Kit.Line(f)
        f.line:SetHeight(1)
        f.line:SetPoint("BOTTOMLEFT")
        f.line:SetPoint("BOTTOMRIGHT")
        f.map = Widgets.CreateButton(f, "Map", "ghost", "mapPin", nil, Theme.IsClassic() and 22 or 20)
        f.map:SetPoint("BOTTOMRIGHT", -2, 4)
        f.map:SetMotionScriptsWhileDisabled(true)
        f.map.cell = f
        f.map:SetScript("OnClick", MapButtonClick)
        f:SetScript("OnClick", function(self)
            local d = self.sheet.data[self.entry]
            if d and d.onClick then d.onClick(d) end
        end)
        f:SetScript("OnEnter", function(self)
            local d = self.sheet.data[self.entry]
            if d and d.onEnter then d.onEnter(self, d) end
        end)
        f:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
        return f
    end,
    fill = function(f, d, w)
        f.name:SetText(d.text or "")
        f.tag:SetShown(d.tag ~= nil)
        if d.tag then f.tag:Set(d.tag, d.tagKind or "neutral") end
        f.sub:SetText(d.sub or "")
        f.sub:ClearAllPoints()
        if d.tag then f.sub:SetPoint("LEFT", f.tag, "RIGHT", 7, 0) else f.sub:SetPoint("BOTTOMLEFT", f.name, "BOTTOMRIGHT", 8, 0) end
        local mapW = 0
        if d.mob then
            local label, glyph, title, tip, canMark = LJ.Lists.MapButtonState(d.mob, d.itemName)
            f.map:SetEnabled(canMark)
            f.map:SetGlyph(glyph)
            f.map:SetLabel(label)
            Widgets.SetTooltip(f.map, title, tip, "ANCHOR_TOP")
            f.map:Show()
            mapW = f.map:GetWidth() + 10
        else
            f.map:Hide()
        end
        local tagW = d.tag and (f.tag:GetWidth() + 7) or 0
        local room = w - 12 - mapW
        f.name:SetWidth(0)
        f.name:SetWidth(math.max(40, math.min(Widgets.TextWidth(f.name) + 2, room - tagW - 60)))
        f.sub:SetWidth(math.max(20, room - f.name:GetWidth() - tagW - 8))
        f:EnableMouse(d.onClick ~= nil or d.onEnter ~= nil)
    end,
}

-- A row of buttons: data = { buttons = { { text, glyph, onClick, tooltip, tooltipText, kind } }, align = "LEFT" }
Kit.KINDS.buttons = {
    height = function() return Theme.IsClassic() and 36 or 32 end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.buttons = {}
        return f
    end,
    fill = function(f, d)
        local x = 0
        for i = 1, math.max(#d.buttons, #f.buttons) do
            local def, b = d.buttons[i], f.buttons[i]
            if def and not b then
                b = Widgets.CreateButton(f, "", "ghost", nil, nil, Theme.IsClassic() and 26 or 24)
                b:SetScript("OnClick", function(btn)
                    if btn.handler then
                        Util.PlaySound("IG_MAINMENU_OPTION")
                        btn.handler()
                    end
                end)
                f.buttons[i] = b
            end
            if def then
                b.handler = def.onClick
                b.key = def.key
                b:SetGlyph(def.glyph)
                b:SetLabel(def.text)
                b:SetEnabled(def.disabled ~= true)
                b:SetMotionScriptsWhileDisabled(true)
                Widgets.SetTooltip(b, def.tooltip, def.tooltipText, "ANCHOR_TOP")
                b:ClearAllPoints()
                b:SetPoint("LEFT", x, 0)
                x = x + b:GetWidth() + 8
                b:Show()
            elseif b then
                b:Hide()
            end
        end
    end,
}

-- An empty state inside a pane: a glyph, a title, a text and an optional button (primary: the accent-filled one).
-- data = { title, text, glyph, button, onClick, buttonGlyph, primary }
local function EmptyButton(f, kind)
    local b = Widgets.CreateButton(f, "", kind, nil, nil, 26)
    b:SetPoint("TOP", f.text, "BOTTOM", 0, -14)
    b:SetScript("OnClick", function(self) if self.handler then self.handler() end end)
    return b
end
Kit.KINDS.empty = {
    height = function(d, w)
        return 70 + math.ceil(Kit.TextHeight(d.text, "bodySmall", math.min(w - 40, 340), 3)) + (d.button and 44 or 10)
    end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.icon = Widgets.Glyph(f, "info", 26, C.text4)
        f.icon:SetPoint("TOP", 0, -10)
        f.title = Widgets.Text(f, "h2", C.text1, nil, "CENTER")
        f.title:SetPoint("TOP", f.icon, "BOTTOM", 0, -10)
        f.text = Widgets.Text(f, "bodySmall", C.text3, nil, "CENTER")
        f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.text:SetWordWrap(true)
        f.text:SetSpacing(3)
        f.button = EmptyButton(f, "ghost")
        return f
    end,
    fill = function(f, d, w)
        Theme.SetGlyph(f.icon, d.glyph or "info", C.text4)
        f.title:SetText(d.title or "")
        f.title:SetWidth(w - 20)
        f.text:SetWidth(math.min(w - 40, 340))
        f.text:SetText(d.text or "")
        if d.primary and not f.primary then f.primary = EmptyButton(f, "primary") end
        local b = d.primary and f.primary or f.button
        f.button:SetShown(d.button ~= nil and b == f.button)
        if f.primary then f.primary:SetShown(d.button ~= nil and b == f.primary) end
        if d.button then
            b.handler = d.onClick
            b:SetGlyph(d.buttonGlyph)
            b:SetLabel(d.button)
        end
    end,
}

---------------------------------------------------------------------------
-- Page helpers
---------------------------------------------------------------------------
-- The area a page fills in its root: the glass keeps a margin to the window's edges (the classic look has the brown
-- panel around the pages).
local MODERN_MARGIN = 16
function Kit.Page(root)
    if Theme.IsClassic() then return root end
    local area = CreateFrame("Frame", nil, root)
    area:SetPoint("TOPLEFT", MODERN_MARGIN, -MODERN_MARGIN)
    area:SetPoint("BOTTOMRIGHT", -MODERN_MARGIN, MODERN_MARGIN)
    return area
end

-- The options of an item cell for the character: upgrade (an item of its Best in Slot list), unusable and the tooltip
-- line of the upgrade.
function Kit.ItemData(id, spec, extra)
    local d = extra or {}
    d.id = id
    d.upgrade = BiS.Upgrade(id)
    d.unusable = BiS.Unusable(Items.Get(id), spec)
    local up = LJ.Lists.UpgradeTooltip(d.upgrade, d.id)
    if up then
        d.extraTooltip = d.extraTooltip or {}
        d.extraTooltip[#d.extraTooltip + 1] = up
    end
    return d
end

-- The level range of an instance or zone as text with an en dash, in the colors of the character's level.
function Kit.RangeText(minLevel, maxLevel)
    return (Util.LevelRange(minLevel, maxLevel):gsub("-", "–"))
end

-- A checkbox in a header (Usable by me, Upgrades only): the look's own check box.
function Kit.Toggle(parent, label, tooltip, onChange)
    local t = Widgets.CreateToggle(parent, label, tooltip)
    t.onChange = function(_, on) onChange(on) end
    return t
end
