-- Lootified - widget toolkit: rounded 9-slice boxes, pills, buttons, toggles, custom menus, scroll areas with a
-- thin scroll bar, underline tabs, item rows, boss emblems, progress ring and a small tween engine for hover fades
-- and slides. Every widget reads the skin when it is created: the classic look builds the same widget from
-- Blizzard's art (red panel buttons, tabs, check boxes, drop-downs, the game's menu) in its brown leather colors; the
-- modern and the database look share the dark glass.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Widgets = {}
LJ.Widgets = Widgets

local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local C = Theme.COLORS
local TEX = Theme.TEX

---------------------------------------------------------------------------
-- Tweens: one driver frame runs every active animation (ease-out cubic)
---------------------------------------------------------------------------
local Anim = { active = {} }
Widgets.Anim = Anim
local animDriver = CreateFrame("Frame")
animDriver:Hide()

local function EaseOut(p) return 1 - (1 - p) * (1 - p) * (1 - p) end

-- scratch lists of the driver (no new tables every frame while something animates)
local animKeys, animFinished = {}, {}
animDriver:SetScript("OnUpdate", function(self, elapsed)
    local keys, finished = animKeys, animFinished
    wipe(keys)
    wipe(finished)
    for key in pairs(Anim.active) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local a = Anim.active[key]
        if a then
            a.t = a.t + elapsed
            local p = (a.d > 0) and math.min(1, a.t / a.d) or 1
            local ok = LJ:SafeCall(a.fn, EaseOut(p))
            if p >= 1 or not ok then
                Anim.active[key] = nil
                if a.done then finished[#finished + 1] = a.done end
            end
        end
    end
    for _, fn in ipairs(finished) do LJ:SafeCall(fn) end
    if not next(Anim.active) then self:Hide() end
end)

-- Runs fn(progress 0..1) over duration seconds. A new animation with the same key replaces the old one.
function Anim.Run(key, duration, fn, done)
    Anim.active[key] = { t = 0, d = duration or 0.15, fn = fn, done = done }
    fn(0)
    animDriver:Show()
end

function Anim.Stop(key)
    Anim.active[key] = nil
end

function Anim.Fade(region, to, duration, key)
    key = key or region
    local from = region:GetAlpha()
    if math.abs(from - to) < 0.01 then
        Anim.Stop(key)
        region:SetAlpha(to)
        return
    end
    Anim.Run(key, duration or 0.12, function(p) region:SetAlpha(from + (to - from) * p) end)
end

---------------------------------------------------------------------------
-- Text and glyph helpers
---------------------------------------------------------------------------
function Widgets.Text(parent, font, color, layer, justify)
    local fs = Theme.PrepareFontString(parent:CreateFontString(nil, layer or "OVERLAY"))
    fs:SetFontObject(Theme.Font(font or "body"))
    local c = color or C.text1
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function Widgets.SetTextColor(fs, c, alpha)
    fs:SetTextColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

-- True while the mouse is over a widget.
local function Hover(f)
    return f.hovered or false
end
Widgets.Hover = Hover

function Widgets.Glyph(parent, name, size, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    t:SetSize(size or 14, size or 14)
    Theme.SetGlyph(t, name, color or C.text2)
    return t
end

-- Width of a FontString's text without wrapping.
function Widgets.TextWidth(fs)
    return fs:GetUnboundedStringWidth()
end

---------------------------------------------------------------------------
-- Rounded 9-slice box (textures of a host frame; white texture tinted with vertex colors)
---------------------------------------------------------------------------
local Box = {}
Box.__index = Box
Widgets.BoxMeta = Box

local PIECE = {}
do
    -- 1 TL, 2 T, 3 TR, 4 L, 5 C, 6 R, 7 BL, 8 B, 9 BR
    PIECE.coords = function(c)
        return { { 0, c, 0, c }, { c, 1 - c, 0, c }, { 1 - c, 1, 0, c }, { 0, c, c, 1 - c }, { c, 1 - c, c, 1 - c },
            { 1 - c, 1, c, 1 - c }, { 0, c, 1 - c, 1 }, { c, 1 - c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 } }
    end
end

-- radius: 4, 6, 8, 10 or 12 (display units); ring: 1 unit outline instead of a fill.
function Widgets.CreateBox(host, layer, sublevel, radius, ring)
    radius = Theme.SnapRadius(radius or 8)
    local box = setmetatable({ host = host, parts = {}, radius = radius }, Box)
    local file = Theme.RoundFile(radius, ring)
    box.file = file
    local coords = PIECE.coords(radius / 32)
    for i = 1, 9 do
        local t = host:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
        t:SetTexture(file)
        t:SetTexCoord(unpack(coords[i]))
        box.parts[i] = t
    end
    box:SetAnchor(host)
    return box
end

-- Places the box on region with insets (positive = inwards).
function Box:SetAnchor(region, left, top, right, bottom)
    local R, p = self.radius, self.parts
    left, top, right, bottom = left or 0, top or 0, right or 0, bottom or 0
    for i = 1, 9 do p[i]:ClearAllPoints() end
    p[1]:SetPoint("TOPLEFT", region, "TOPLEFT", left, -top)
    p[3]:SetPoint("TOPRIGHT", region, "TOPRIGHT", -right, -top)
    p[7]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", left, bottom)
    p[9]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -right, bottom)
    for _, i in ipairs({ 1, 3, 7, 9 }) do p[i]:SetSize(R, R) end
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT")
    p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT")
    p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT")
    p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
    p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT")
    p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT")
    p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    return self
end

function Box:SetColor(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], g or r[4] end
    for i = 1, 9 do self.parts[i]:SetVertexColor(r, g, b, a or 1) end
    return self
end

-- orientation "HORIZONTAL" (c1 left -> c2 right) or "VERTICAL" (c1 top -> c2 bottom); colors {r, g, b, a}.
function Box:SetGradient(orientation, c1, c2)
    local p = self.parts
    local function col(c) return CreateColor(c[1], c[2], c[3], c[4] or 1) end
    if orientation == "HORIZONTAL" then
        for _, i in ipairs({ 1, 4, 7 }) do p[i]:SetVertexColor(c1[1], c1[2], c1[3], c1[4] or 1) end
        for _, i in ipairs({ 3, 6, 9 }) do p[i]:SetVertexColor(c2[1], c2[2], c2[3], c2[4] or 1) end
        for _, i in ipairs({ 2, 5, 8 }) do p[i]:SetGradient("HORIZONTAL", col(c1), col(c2)) end
    else
        for _, i in ipairs({ 1, 2, 3 }) do p[i]:SetVertexColor(c1[1], c1[2], c1[3], c1[4] or 1) end
        for _, i in ipairs({ 7, 8, 9 }) do p[i]:SetVertexColor(c2[1], c2[2], c2[3], c2[4] or 1) end
        -- WoW: VERTICAL gradients go from minColor (bottom) to maxColor (top)
        for _, i in ipairs({ 4, 5, 6 }) do p[i]:SetGradient("VERTICAL", col(c2), col(c1)) end
    end
    return self
end

-- Square corners (tl, tr, bl, br = true): those corner pieces become plain fills.
function Box:SetSquareCorners(tl, tr, bl, br)
    local coords = PIECE.coords(self.radius / 32)
    for i, square in pairs({ [1] = tl, [3] = tr, [7] = bl, [9] = br }) do
        local t = self.parts[i]
        if square then
            t:SetTexture(TEX.white)
            t:SetTexCoord(0, 1, 0, 1)
        else
            t:SetTexture(self.file)
            t:SetTexCoord(unpack(coords[i]))
        end
    end
    return self
end

function Box:SetAlpha(a) for i = 1, 9 do self.parts[i]:SetAlpha(a) end return self end
function Box:SetShown(v) for i = 1, 9 do self.parts[i]:SetShown(v) end return self end
function Box:Show() return self:SetShown(true) end
function Box:Hide() return self:SetShown(false) end
function Box:SetBlendMode(m) for i = 1, 9 do self.parts[i]:SetBlendMode(m) end return self end

---------------------------------------------------------------------------
-- Lazy box: the same box, but its 9 textures are only made once it shows something. Hover highlights, selection
-- rings and transparent pill outlines start transparent, and most of them never become visible (rows the mouse
-- never touches), so they cost no textures. Starts transparent (unlike a box, which starts white).
---------------------------------------------------------------------------
local LazyBox = {}
LazyBox.__index = LazyBox

function Widgets.CreateLazyBox(host, layer, sublevel, radius, ring)
    return setmetatable({ host = host, layer = layer, sublevel = sublevel, radius = radius, ring = ring,
        shown = true, alpha = 1 }, LazyBox)
end

-- The real box, made with every setting received so far.
local function RealBox(lb)
    local box = Widgets.CreateBox(lb.host, lb.layer, lb.sublevel, lb.radius, lb.ring)
    lb.box = box
    if lb.anchor then box:SetAnchor(lb.anchor, lb.left, lb.top, lb.right, lb.bottom) end
    if lb.square then box:SetSquareCorners(lb.square[1], lb.square[2], lb.square[3], lb.square[4]) end
    if lb.blend then box:SetBlendMode(lb.blend) end
    if lb.alpha ~= 1 then box:SetAlpha(lb.alpha) end
    if lb.gradient then
        box:SetGradient(lb.gradient[1], lb.gradient[2], lb.gradient[3])
    elseif lb.colorAlpha then
        box:SetColor(lb.cr, lb.cg, lb.cb, lb.ca)
    end
    if not lb.shown then box:Hide() end
    return box
end

-- visible = shown with a color that is not fully transparent
local function MakeRealIfVisible(lb)
    if lb.shown and lb.colorAlpha and lb.colorAlpha > 0 then RealBox(lb) end
end

function LazyBox:SetColor(r, g, b, a)
    if self.box then self.box:SetColor(r, g, b, a) return self end
    local alpha
    if type(r) == "table" then alpha = g or r[4] or 1 else alpha = a or 1 end
    self.gradient = nil
    if alpha > 0 then
        self.cr, self.cg, self.cb, self.ca, self.colorAlpha = r, g, b, a, alpha
        MakeRealIfVisible(self)
    else
        -- transparent: nothing to remember
        self.cr, self.cg, self.cb, self.ca, self.colorAlpha = nil, nil, nil, nil, nil
    end
    return self
end

function LazyBox:SetGradient(orientation, c1, c2)
    if self.box then self.box:SetGradient(orientation, c1, c2) return self end
    self.gradient = { orientation, c1, c2 }
    self.colorAlpha = math.max(c1[4] or 1, c2[4] or 1)
    MakeRealIfVisible(self)
    return self
end

function LazyBox:SetAnchor(region, left, top, right, bottom)
    if self.box then self.box:SetAnchor(region, left, top, right, bottom) return self end
    self.anchor, self.left, self.top, self.right, self.bottom = region, left, top, right, bottom
    return self
end

function LazyBox:SetSquareCorners(tl, tr, bl, br)
    if self.box then self.box:SetSquareCorners(tl, tr, bl, br) return self end
    self.square = { tl, tr, bl, br }
    return self
end

function LazyBox:SetAlpha(a)
    self.alpha = a
    if self.box then self.box:SetAlpha(a) end
    return self
end

function LazyBox:SetShown(v)
    self.shown = v and true or false
    if self.box then
        self.box:SetShown(v)
    else
        MakeRealIfVisible(self)
    end
    return self
end
function LazyBox:Show() return self:SetShown(true) end
function LazyBox:Hide() return self:SetShown(false) end

function LazyBox:SetBlendMode(m)
    self.blend = m
    if self.box then self.box:SetBlendMode(m) end
    return self
end

-- Horizontal 3-slice of a Blizzard texture (buttons, tabs, drop-downs): left cap, stretched middle, right cap.
-- coords = { l, ml, mr, r, t, b } in texture space; cap = display width of the caps.
function Widgets.CreateThreeSlice(host, file, coords, cap, layer, sublevel)
    local ts = { parts = {} }
    local l, ml, mr, r, t, b = unpack(coords)
    local uv = { { l, ml }, { ml, mr }, { mr, r } }
    for i = 1, 3 do
        local tex = host:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
        tex:SetTexture(file)
        tex:SetTexCoord(uv[i][1], uv[i][2], t, b)
        ts.parts[i] = tex
    end
    ts.cap = cap
    function ts:SetAnchor(region, left, top, right, bottom)
        left, top, right, bottom = left or 0, top or 0, right or 0, bottom or 0
        local Lp, M, R = self.parts[1], self.parts[2], self.parts[3]
        for _, x in ipairs(self.parts) do x:ClearAllPoints() end
        Lp:SetPoint("TOPLEFT", region, "TOPLEFT", left, -top)
        Lp:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", left, bottom)
        Lp:SetWidth(self.cap)
        R:SetPoint("TOPRIGHT", region, "TOPRIGHT", -right, -top)
        R:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -right, bottom)
        R:SetWidth(self.cap)
        M:SetPoint("TOPLEFT", Lp, "TOPRIGHT")
        M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
        return self
    end
    function ts:SetShown(v) for _, x in ipairs(self.parts) do x:SetShown(v) end return self end
    function ts:Show() return self:SetShown(true) end
    function ts:Hide() return self:SetShown(false) end
    function ts:SetVertexColor(...) for _, x in ipairs(self.parts) do x:SetVertexColor(...) end return self end
    function ts:SetDesaturated(v) for _, x in ipairs(self.parts) do x:SetDesaturated(v) end return self end
    function ts:SetBlendMode(m) for _, x in ipairs(self.parts) do x:SetBlendMode(m) end return self end
    ts:SetAnchor(host)
    return ts
end

-- Fill + 1 unit border.
function Widgets.CreatePanel(host, radius, layer, sublevel)
    local panel = {
        fill = Widgets.CreateBox(host, layer or "BACKGROUND", sublevel or 0, radius),
        ring = Widgets.CreateBox(host, layer or "BACKGROUND", (sublevel or 0) + 1, radius, true),
    }
    function panel:SetFill(...) self.fill:SetColor(...) return self end
    function panel:SetBorder(...) self.ring:SetColor(...) return self end
    function panel:SetGradient(...) self.fill:SetGradient(...) return self end
    function panel:SetShown(v) self.fill:SetShown(v) self.ring:SetShown(v) return self end
    function panel:SetAlpha(a) self.fill:SetAlpha(a) self.ring:SetAlpha(a) return self end
    function panel:SetAnchor(...) self.fill:SetAnchor(...) self.ring:SetAnchor(...) return self end
    return panel
end

-- The panel behind a text line (EditBox) in the active look: box.panel.
function Widgets.InputPanel(box)
    box.panel = Widgets.CreatePanel(box, 7, "BACKGROUND", 1)
    if Theme.IsClassic() then
        local H = Theme.HEARTH
        box.panel:SetFill(H.inputFill[1], H.inputFill[2], H.inputFill[3], H.inputFill[4] or 1)
        box.panel:SetBorder(H.inputBorder[1], H.inputBorder[2], H.inputBorder[3], H.inputBorder[4] or 1)
    else
        box.panel:SetFill(0, 0, 0, 0.3)
        box.panel:SetBorder(1, 1, 1, 0.1)
    end
    return box.panel
end

-- An item search line (the pickers of a slot's items): the search glyph, a placeholder while it is empty; Escape and
-- hiding clear it. onChange() on every change of its text.
local function SearchVisual(box)
    box.placeholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
end

function Widgets.CreateSearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 26)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    box:SetFontObject(Theme.Font("bodySmall"))
    box:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
    box:SetTextInsets(28, 9, 0, 0)
    Widgets.InputPanel(box)
    box.glyph = Widgets.Glyph(box, "search", 13, C.text3)
    box.glyph:SetPoint("LEFT", 9, 0)
    box.placeholder = Widgets.Text(box, "small", C.text4)
    box.placeholder:SetPoint("LEFT", 28, 0)
    box.placeholder:SetPoint("RIGHT", -9, 0)
    box.placeholder:SetText(LJ.L(placeholder))
    box:SetScript("OnEditFocusGained", SearchVisual)
    box:SetScript("OnEditFocusLost", SearchVisual)
    box:SetScript("OnTextChanged", function(b)
        SearchVisual(b)
        onChange()
    end)
    box:SetScript("OnEscapePressed", function(b)
        b:SetText("")
        b:ClearFocus()
    end)
    box:SetScript("OnHide", function(b) b:SetText("") end)
    return box
end

-- Soft drop shadow around a frame (textures below everything else of the frame).
function Widgets.CreateShadow(frame, spread, alpha)
    spread = spread or 16
    local corner = spread + 8
    local c = 0.375
    local coords = PIECE.coords(c)
    local parts = {}
    for i = 1, 9 do
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture(TEX.shadow)
        t:SetTexCoord(unpack(coords[i]))
        t:SetVertexColor(0, 0, 0, alpha or 0.75)
        parts[i] = t
    end
    local p = parts
    p[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -spread, spread)
    p[3]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", spread, spread)
    p[7]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -spread, -spread)
    p[9]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spread, -spread)
    for _, i in ipairs({ 1, 3, 7, 9 }) do p[i]:SetSize(corner, corner) end
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT")
    p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT")
    p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT")
    p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
    p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT")
    p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT")
    p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    return parts
end

-- Soft radial glow texture.
function Widgets.CreateGlow(parent, layer, sublevel, color, alpha, blend)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetTexture(TEX.glow)
    if blend then t:SetBlendMode(blend) end
    local c = color or Theme.accent
    t:SetVertexColor(c[1], c[2], c[3], alpha or 0.3)
    return t
end

-- Solid color texture (1x1 white tinted).
function Widgets.Solid(parent, layer, sublevel, color, alpha)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    t:SetTexture(TEX.white)
    local c = color or C.white
    t:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
    return t
end

-- 1 unit hairline (a bronze line in the classic look).
function Widgets.Line(parent, layer, alpha)
    if Theme.IsClassic() then
        return Widgets.Solid(parent, layer or "BORDER", 0, Theme.HEARTH.line, math.min(1, 0.06 + (alpha or 0.06) * 2))
    end
    return Widgets.Solid(parent, layer or "BORDER", 0, C.white, alpha or 0.06)
end

    -- Background of a panel over the window (menus, flyouts, notes and the tour's box): dark glass in the
-- glass looks, dark brown in a bronze line in the classic look. Its SetBorder tints the outline. modern = { fill =
-- {r, g, b, a}, border = {r, g, b, a} }: this panel's own glass (default: the popup glass).
local POPUP_GLASS = { fill = { 0.086, 0.102, 0.133, 0.98 }, border = { 1, 1, 1, 0.09 } }
function Widgets.CreatePopupPanel(frame, radius, modern)
    local panel = Widgets.CreatePanel(frame, radius or 10, "BACKGROUND", 0)
    if Theme.IsClassic() then
        local H = Theme.HEARTH
        panel:SetGradient("VERTICAL", { H.windowTop[1], H.windowTop[2], H.windowTop[3], 0.985 },
            { H.windowBottom[1], H.windowBottom[2], H.windowBottom[3], 0.985 })
        panel:SetBorder(H.windowBorder)
    else
        local glass = modern or POPUP_GLASS
        panel:SetFill(unpack(glass.fill))
        panel:SetBorder(unpack(glass.border))
    end
    return panel
end

-- Vertical rounded bar (3-slice of the segment texture), e.g. scroll bars.
function Widgets.CreateVBar(host, layer, sublevel)
    local bar = { parts = {} }
    local coords = { { 0, 1, 0, 0.25 }, { 0, 1, 0.25, 0.75 }, { 0, 1, 0.75, 1 } }
    for i = 1, 3 do
        local t = host:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
        t:SetTexture(TEX.segment)
        t:SetTexCoord(unpack(coords[i]))
        bar.parts[i] = t
    end
    local top, mid, bottom = bar.parts[1], bar.parts[2], bar.parts[3]
    function bar:SetAnchor(region)
        local w = region:GetWidth()
        if not w or w <= 0 then w = 4 end
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", region)
        top:SetPoint("TOPRIGHT", region)
        top:SetHeight(w)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", region)
        bottom:SetPoint("BOTTOMRIGHT", region)
        bottom:SetHeight(w)
        mid:ClearAllPoints()
        mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
        mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    end
    function bar:SetColor(r, g, b, a)
        if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], g or r[4] end
        for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, a or 1) end
    end
    bar:SetAnchor(host)
    return bar
end

---------------------------------------------------------------------------
-- Pills (small rounded labels)
---------------------------------------------------------------------------
local PILL_KINDS = {
    neutral = { fill = { 1, 1, 1, 0.08 }, ring = { 1, 1, 1, 0.08 }, text = Theme.hex("C9CED6") },
    gray = { fill = { 1, 1, 1, 0.06 }, ring = { 1, 1, 1, 0.07 }, text = C.gray },
    dark = { fill = { 1, 1, 1, 0.10 }, ring = { 1, 1, 1, 0 }, text = Theme.hex("C9CED6") },
    ok = { fill = { 0.29, 0.87, 0.5, 0.12 }, ring = { 0.29, 0.87, 0.5, 0.35 }, text = C.okText },
    blue = { fill = { 0.38, 0.65, 0.98, 0.13 }, ring = { 0.38, 0.65, 0.98, 0.40 }, text = C.blueText },
    gold = { fill = { 0.96, 0.78, 0.27, 0.13 }, ring = { 0.96, 0.78, 0.27, 0.42 }, text = C.goldText },
    red = { fill = { 0.97, 0.44, 0.44, 0.12 }, ring = { 0.97, 0.44, 0.44, 0.40 }, text = C.redText },
    chance = { fill = { 1, 1, 1, 0.06 }, ring = { 1, 1, 1, 0 }, text = C.text2 },
    rare = { fill = { 0.78, 0.64, 1, 0.1 }, ring = { 0.78, 0.64, 1, 0.45 }, text = C.rare },
    -- on pictures: a dark see-through fill
    art = { fill = { 0, 0, 0, 0.62 }, ring = { 1, 1, 1, 0.14 }, text = Theme.hex("EADFC6") },
    artOk = { fill = { 0, 0, 0, 0.62 }, ring = { 0.49, 0.88, 0.48, 0.35 }, text = C.okText },
    artGold = { fill = { 0, 0, 0, 0.62 }, ring = { 0.96, 0.78, 0.27, 0.4 }, text = C.goldText },
}
Widgets.PILL_KINDS = PILL_KINDS

local function ApplyPill(pill)
    local kind = pill.kind or "neutral"
    local a = Theme.accent
    local fill, ring, text
    if kind == "acc" then
        fill, ring, text = { a[1], a[2], a[3], 0.14 }, { a[1], a[2], a[3], 0.45 }, { a[1], a[2], a[3], 1 }
    elseif kind == "solid" then
        fill, ring, text = { a[1], a[2], a[3], 1 }, { 0, 0, 0, 0 }, C.dark
    elseif kind == "accSoft" then
        fill, ring, text = { a[1], a[2], a[3], 0.12 }, { a[1], a[2], a[3], 0 }, { a[1], a[2], a[3], 1 }
    else
        local k = PILL_KINDS[kind] or PILL_KINDS.neutral
        fill, ring, text = k.fill, k.ring, pill.textColor or k.text
    end
    pill.fill:SetColor(fill)
    pill.ring:SetColor(ring)
    pill.text:SetTextColor(text[1], text[2], text[3], text[4] or 1)
    pill.icon:SetVertexColor(text[1], text[2], text[3], text[4] or 1)
end

-- text, kind, glyph name, fixed width (nil = fit the text)
local function PillSet(self, text, kind, glyph, width)
    self.kind = kind or self.kind or "neutral"
    -- a text color of an earlier use (SetTextColorOverride after Set) does not carry over
    self.textColor = nil
    self.text:SetText(LJ.L(text) or "")
    local pad = (self:GetHeight() >= 18) and 7 or 5
    local w = Widgets.TextWidth(self.text)
    self.text:ClearAllPoints()
    if glyph then
        Theme.SetGlyph(self.icon, glyph)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("LEFT", pad - 1, 0)
        self.icon:Show()
        self.text:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)
        self:SetWidth(width or math.floor(w + pad * 2 + 14 + 0.5))
    else
        self.icon:Hide()
        self.text:SetPoint("CENTER", 0, 0)
        self:SetWidth(width or math.floor(w + pad * 2 + 0.5))
    end
    ApplyPill(self)
    return self
end

local function PillSetTextColorOverride(self, c)
    self.textColor = c
    ApplyPill(self)
end

local function PillOnAccent(p)
    if p.kind == "acc" or p.kind == "solid" or p.kind == "accSoft" then ApplyPill(p) end
end

function Widgets.CreatePill(parent, height, font)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 20)
    local radius = (height or 20) >= 18 and 6 or 4
    f.fill = Widgets.CreateBox(f, "BACKGROUND", 1, radius)
    f.ring = Widgets.CreateLazyBox(f, "BACKGROUND", 2, radius, true)   -- several pill kinds have no outline
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(11, 11)
    f.icon:Hide()
    f.text = Widgets.Text(f, font or "pill", C.text2)
    f.kind = "neutral"
    f.Set, f.SetTextColorOverride = PillSet, PillSetTextColorOverride
    Theme.OnAccent(f, PillOnAccent)
    return f
end

-- Formats a drop chance for display.
local FormatChance = Util.FormatChance
Widgets.FormatChance = FormatChance

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local BUTTON_STYLE = {
    ghost = { fill = { 1, 1, 1, 0.05 }, fillHover = { 1, 1, 1, 0.10 }, ring = { 1, 1, 1, 0.13 }, ringHover = { 1, 1, 1, 0.22 }, text = Theme.hex("E9EBEE") },
    glass = { fill = { 0.04, 0.05, 0.06, 0.55 }, fillHover = { 0.08, 0.09, 0.11, 0.7 }, ring = { 1, 1, 1, 0.14 }, ringHover = { 1, 1, 1, 0.24 }, text = Theme.hex("E9EBEE") },
    icon = { fill = { 1, 1, 1, 0 }, fillHover = { 1, 1, 1, 0.07 }, ring = { 1, 1, 1, 0 }, ringHover = { 1, 1, 1, 0 }, text = Theme.hex("9AA2AE"), textHover = C.white },
}

-- The fills of the boxed looks (Theme.PANE: the classic leather or the modern glass): "row", "pick" (the picked row:
-- crimson in the classic look) and "panel"; the classic buttons also "button" (brown) and "red" (the active or main
-- button). Rows and buttons are lighter on hover. fill, ring: a box pair (fill + outline).
local BOX_FILLS = {
    button = { "buttonTop", "buttonBottom", "buttonBorder", "buttonHoverTop", "buttonHoverBottom", "buttonHoverBorder" },
    red = { "redTop", "redBottom", "redBorder", "redHoverTop", "redHoverBottom", "redBorder" },
    row = { "rowTop", "rowBottom", "rowBorder", "rowHoverTop", "rowHoverBottom", "rowHoverBorder" },
    pick = { "pickTop", "pickBottom", "pickBorder", "pickTop", "pickBottom", "pickBorder" },
    panel = { "panelTop", "panelBottom", "panelBorder", "panelTop", "panelBottom", "panelBorder" },
}
function Widgets.BoxFill(fill, ring, kind, hover)
    local H, k = Theme.PANE, BOX_FILLS[kind]
    local o = hover and 3 or 0
    fill:SetGradient("VERTICAL", H[k[1 + o]], H[k[2 + o]])
    ring:SetColor(H[k[3 + o]])
end

local function ButtonVisual(b)
    local a = Theme.accent
    local hover = Hover(b) and b:IsEnabled()
    if b.hearth then
        -- classic: a brown button, red when active (and the main buttons), lighter on hover
        local H = Theme.HEARTH
        local red = b.active or b.kind == "primary" or b.kind == "solidAccent"
        Widgets.BoxFill(b.fill, b.ring, red and "red" or "button", hover)
        local c = (hover and C.white) or (red and H.redText) or (b.kind == "accent" and H.title) or H.buttonText
        b.text:SetTextColor(c[1], c[2], c[3])
        b.icon:SetVertexColor(c[1], c[2], c[3])
        return
    elseif b.classicIcon then
        -- classic icon button: a light glyph, white on hover or when active
        local c = (not b:IsEnabled()) and C.text5 or ((hover or b.active) and C.white or C.text3)
        b.text:SetTextColor(c[1], c[2], c[3])
        b.icon:SetVertexColor(c[1], c[2], c[3])
        return
    elseif b.kind == "primary" then
        b.fill:SetGradient("VERTICAL", { a[1], a[2], a[3], 1 }, { a[1] * 0.82, a[2] * 0.82, a[3] * 0.82, 1 })
        b.ring:SetColor(1, 1, 1, hover and 0.25 or 0.12)
        b.glow:SetVertexColor(a[1], a[2], a[3], hover and 0.55 or 0.35)
        b.text:SetTextColor(C.dark[1], C.dark[2], C.dark[3])
        b.icon:SetVertexColor(C.dark[1], C.dark[2], C.dark[3])
    elseif b.kind == "accent" then
        b.fill:SetColor(a[1], a[2], a[3], hover and 0.22 or 0.12)
        b.ring:SetColor(a[1], a[2], a[3], hover and 0.6 or 0.35)
        b.text:SetTextColor(a[1], a[2], a[3])
        b.icon:SetVertexColor(a[1], a[2], a[3])
    elseif b.kind == "solidAccent" then
        b.fill:SetGradient("VERTICAL", { a[1], a[2], a[3], 1 }, { a[1] * 0.8, a[2] * 0.8, a[3] * 0.8, 1 })
        b.ring:SetColor(0, 0, 0, 0)
        b.text:SetTextColor(C.dark[1], C.dark[2], C.dark[3])
        b.icon:SetVertexColor(C.dark[1], C.dark[2], C.dark[3])
        if b.glow then b.glow:SetVertexColor(a[1], a[2], a[3], hover and 0.5 or 0.3) end
    else
        local s = BUTTON_STYLE[b.kind] or BUTTON_STYLE.ghost
        b.fill:SetColor(hover and s.fillHover or s.fill)
        b.ring:SetColor(hover and s.ringHover or s.ring)
        local tc = (hover and s.textHover) or (b.active and C.white) or s.text
        b.text:SetTextColor(tc[1], tc[2], tc[3])
        b.icon:SetVertexColor(tc[1], tc[2], tc[3])
    end
end

local function LayoutButton(b)
    local hasText = b.text:GetText() and b.text:GetText() ~= ""
    local hasIcon = b.glyphName ~= nil
    b.icon:SetShown(hasIcon)
    b.icon:ClearAllPoints()
    b.text:ClearAllPoints()
    local dy = b.pressed and -1 or 0 -- content moves down 1 px while the button is held
    if hasIcon and hasText then
        local w = Widgets.TextWidth(b.text)
        local total = b.iconSize + 6 + w
        if b.autoWidth then b:SetWidth(math.floor(total + b.padding * 2 + 0.5)) end
        b.icon:SetPoint("CENTER", b, "CENTER", -total / 2 + b.iconSize / 2, dy)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    elseif hasIcon then
        b.icon:SetPoint("CENTER", 0, dy)
    else
        if b.autoWidth then b:SetWidth(math.floor(Widgets.TextWidth(b.text) + b.padding * 2 + 0.5)) end
        b.text:SetPoint("CENTER", 0, dy)
    end
end

-- kind: "ghost" (default), "glass" (on art), "primary" (accent fill + glow), "accent" (tinted),
-- "solidAccent", "icon" (square icon button). width nil = fit the content.
function Widgets.CreateButton(parent, text, kind, glyph, width, height)
    local b = CreateFrame("Button", nil, parent)
    b.kind = kind or "ghost"
    b.autoWidth = width == nil
    b.padding = 11
    b.iconSize = (b.kind == "icon") and 16 or 14
    b:SetSize(width or 80, height or 28)
    if b.kind == "primary" or b.kind == "solidAccent" then
        b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
        b.glow:SetTexture(TEX.glow)
        b.glow:SetBlendMode("ADD")
        b.glow:SetPoint("TOPLEFT", -18, 14)
        b.glow:SetPoint("BOTTOMRIGHT", 18, -14)
    end
    local radius = (height or 28) >= 26 and 8 or 6
    b.fill = Widgets.CreateBox(b, "BACKGROUND", 1, radius)
    b.ring = Widgets.CreateBox(b, "BACKGROUND", 2, radius, true)
    if Theme.IsClassic() then
        if b.glow then b.glow:Hide() end
        if b.kind == "icon" then
            b.classicIcon = true
            b.fill:Hide()
            b.ring:Hide()
        else
            b.hearth = true
        end
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(b.iconSize, b.iconSize)
    b.text = Widgets.Text(b, "button", C.text1)
    function b:SetLabel(label)
        self.text:SetText(LJ.L(label) or "")
        LayoutButton(self)
    end
    function b:SetGlyph(name)
        self.glyphName = name
        if name then
            Theme.SetGlyph(self.icon, name)
            self.icon:Show()
        else
            self.icon:Hide()
        end
        LayoutButton(self)
        ButtonVisual(self)
    end
    function b:SetActive(v)
        self.active = v and true or false
        ButtonVisual(self)
    end
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        ButtonVisual(self)
        if self.tooltipTitle then
            GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
            if self.tooltipText then GameTooltip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        ButtonVisual(self)
        if self.tooltipTitle then GameTooltip:Hide() end
    end)
    -- pressed look: darker and the content 1 px lower while the mouse button is down
    b.press = Widgets.CreateLazyBox(b, "BACKGROUND", 3, radius)
    b.press:Hide()
    b.press:SetColor(0, 0, 0, 0.28)
    b:HookScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        self.pressed = true
        if not self.classicIcon then self.press:Show() end
        LayoutButton(self)
    end)
    b:HookScript("OnMouseUp", function(self)
        self.pressed = false
        self.press:Hide()
        LayoutButton(self)
    end)
    b:HookScript("OnHide", function(self)
        if self.pressed then
            self.pressed = false
            self.press:Hide()
            LayoutButton(self)
        end
    end)
    b:HookScript("OnDisable", function(self) self:SetAlpha(0.45) ButtonVisual(self) end)
    b:HookScript("OnEnable", function(self) self:SetAlpha(1) ButtonVisual(self) end)
    Theme.OnAccent(b, function(btn) ButtonVisual(btn) end)
    b:SetGlyph(glyph)
    b:SetLabel(text)
    return b
end

function Widgets.SetTooltip(frame, title, text, anchor)
    frame.tooltipTitle, frame.tooltipText, frame.tooltipAnchor = LJ.L(title), LJ.L(text), anchor
end

---------------------------------------------------------------------------
-- Filter chips
---------------------------------------------------------------------------
local function ChipVisual(chip)
    local a = Theme.accent
    local hover = Hover(chip)
    if chip.hearth then
        -- classic: a small brown button, red while active
        local H = Theme.HEARTH
        Widgets.BoxFill(chip.fill, chip.ring, chip.active and "red" or "button", hover)
        local c = (hover and C.white) or (chip.active and H.redText) or H.buttonText
        chip.text:SetTextColor(c[1], c[2], c[3])
        chip.icon:SetVertexColor(c[1], c[2], c[3])
        return
    end
    if chip.active then
        chip.fill:SetGradient("VERTICAL", { a[1], a[2], a[3], 0.34 }, { a[1], a[2], a[3], 0.2 })
        chip.ring:SetColor(a[1], a[2], a[3], 0.55)
        chip.text:SetTextColor(1, 1, 1)
        chip.icon:SetVertexColor(1, 1, 1)
    else
        chip.fill:SetColor(1, 1, 1, hover and 0.08 or 0.045)
        chip.ring:SetColor(1, 1, 1, hover and 0.12 or 0.06)
        local c = hover and C.text1 or Theme.hex("AAB1BC")
        chip.text:SetTextColor(c[1], c[2], c[3])
        chip.icon:SetVertexColor(c[1], c[2], c[3])
    end
end

function Widgets.CreateChip(parent, text, glyph, height)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(height or 24)
    chip.fill = Widgets.CreateBox(chip, "BACKGROUND", 1, 6)
    chip.ring = Widgets.CreateBox(chip, "BACKGROUND", 2, 6, true)
    chip.hearth = Theme.IsClassic()
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(12, 12)
    chip.text = Widgets.Text(chip, "chip", C.text2)
    -- (raw: the label as it is, e.g. a name the player gave; else it is translated)
    function chip:SetLabel(label, glyphName, raw)
        if not raw then label = LJ.L(label) end
        self.glyphName = glyphName
        self.text:SetText(label or "")
        self.text:ClearAllPoints()
        self.icon:ClearAllPoints()
        local w = Widgets.TextWidth(self.text)
        if glyphName then
            Theme.SetGlyph(self.icon, glyphName)
            self.icon:Show()
            self.icon:SetPoint("LEFT", 8, 0)
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
            self:SetWidth(math.floor(w + 33 + 0.5))
        else
            self.icon:Hide()
            self.text:SetPoint("CENTER")
            self:SetWidth(math.floor(w + 16 + 0.5))
        end
        ChipVisual(self)
    end
    function chip:SetActive(v)
        self.active = v and true or false
        ChipVisual(self)
    end
    chip:SetScript("OnEnter", function(self) self.hovered = true ChipVisual(self) end)
    chip:SetScript("OnLeave", function(self) self.hovered = false ChipVisual(self) end)
    Theme.OnAccent(chip, function(c) ChipVisual(c) end)
    chip:SetLabel(text, glyph)
    return chip
end

---------------------------------------------------------------------------
-- Toggle switch with a label (a check box in the classic look)
---------------------------------------------------------------------------
local function ToggleVisual(t)
    local a = Theme.accent
    local hover = Hover(t)
    if t.classic then
        -- the game's check box: the label white on hover
        t.mark:SetShown(t.checked)
        t.boxHL:SetShown(hover)
        local c = hover and C.white or C.text2
        t.text:SetTextColor(c[1], c[2], c[3])
        return
    end
    t.fill:SetColor(1, 1, 1, hover and 0.07 or 0.04)
    t.ring:SetColor(1, 1, 1, hover and 0.12 or 0.07)
    if t.checked then
        t.track:SetColor(a[1], a[2], a[3], 1)
        t.trackGlow:SetVertexColor(a[1], a[2], a[3], 0.45)
        t.knob:SetVertexColor(1, 1, 1, 1)
        t.text:SetTextColor(C.white[1], C.white[2], C.white[3])
    else
        t.track:SetColor(1, 1, 1, 0.14)
        t.trackGlow:SetVertexColor(a[1], a[2], a[3], 0)
        t.knob:SetVertexColor(0.67, 0.69, 0.74, 1)
        local c = hover and C.text1 or (Theme.IsClassic() and C.text2 or Theme.hex("AEB5BF"))
        t.text:SetTextColor(c[1], c[2], c[3])
    end
end

function Widgets.CreateToggle(parent, label, tooltip)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(26)
    t.fill = Widgets.CreateBox(t, "BACKGROUND", 1, 6)
    t.ring = Widgets.CreateBox(t, "BACKGROUND", 2, 6, true)
    local sw = CreateFrame("Frame", nil, t)
    sw:SetSize(24, 14)
    sw:SetPoint("LEFT", 6, 0)
    t.sw = sw
    t.trackGlow = sw:CreateTexture(nil, "BACKGROUND", nil, 0)
    t.trackGlow:SetTexture(TEX.glow)
    t.trackGlow:SetBlendMode("ADD")
    t.trackGlow:SetPoint("TOPLEFT", -10, 8)
    t.trackGlow:SetPoint("BOTTOMRIGHT", 10, -8)
    t.track = Widgets.CreateBox(sw, "ARTWORK", 0, 6)
    t.knob = sw:CreateTexture(nil, "ARTWORK", nil, 2)
    t.knob:SetTexture(TEX.circle)
    t.knob:SetSize(10, 10)
    t.knob:SetPoint("LEFT", sw, "LEFT", 2, 0)
    t.text = Widgets.Text(t, "toggle", C.text2)
    t.text:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    t.checked = false
    if Theme.IsClassic() then
        t.classic = true
        t.fill:Hide()
        t.ring:Hide()
        sw:Hide()
        local function CheckTexture(file, sublevel)
            local x = t:CreateTexture(nil, "ARTWORK", nil, sublevel)
            x:SetTexture(file)
            x:SetSize(26, 26)
            x:SetPoint("LEFT", -2, 0)
            return x
        end
        t.box = CheckTexture(Theme.CLASSIC.checkUp, 0)
        t.boxHL = CheckTexture(Theme.CLASSIC.checkHighlight, 1)
        t.boxHL:SetBlendMode("ADD")
        t.mark = CheckTexture(Theme.CLASSIC.check, 2)
        t.text:ClearAllPoints()
        t.text:SetPoint("LEFT", t.box, "RIGHT", 0, 1)
    end
    function t:SetLabel(text)
        self.text:SetText(LJ.L(text) or "")
        self:SetWidth(math.floor(Widgets.TextWidth(self.text) + (self.classic and 30 or 45) + 0.5))
    end
    function t:SetChecked(v, animate)
        v = v and true or false
        if self.classic then
            self.checked = v
            ToggleVisual(self)
            return
        end
        local from = self.checked and 12 or 2
        self.checked = v
        local to = v and 12 or 2
        if animate then
            Anim.Run(self.knob, 0.14, function(p)
                self.knob:SetPoint("LEFT", self.sw, "LEFT", from + (to - from) * p, 0)
            end)
        else
            Anim.Stop(self.knob)
            self.knob:SetPoint("LEFT", self.sw, "LEFT", to, 0)
        end
        ToggleVisual(self)
    end
    t:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked, true)
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        if self.onChange then self.onChange(self, self.checked) end
    end)
    t:SetScript("OnEnter", function(self)
        self.hovered = true
        ToggleVisual(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(LJ.L(label), 1, 1, 1)
            GameTooltip:AddLine(LJ.L(tooltip), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    t:SetScript("OnLeave", function(self)
        self.hovered = false
        ToggleVisual(self)
        if tooltip then GameTooltip:Hide() end
    end)
    Theme.OnAccent(t, function(x) ToggleVisual(x) end)
    t:SetLabel(label)
    t:SetChecked(false)
    return t
end

---------------------------------------------------------------------------
-- Slider: a value from min to max in whole steps, a track with the accent up to the knob. A press on it takes the
-- value under the mouse and follows the mouse until it is let go; the mouse wheel moves it a step.
-- slider.onMove(slider, value) while it moves, slider.onChange(slider, value) when it is set (let go, a wheel step);
-- slider:SetValue(value) shows a value.
---------------------------------------------------------------------------
local function SliderPlace(s)
    local f = (s.value - s.min) / (s.max - s.min)
    local w = s:GetWidth()
    s.fill:SetWidth(math.max(1, w * f))
    s.fill:SetShown(f > 0)
    s.knob:SetPoint("CENTER", s, "LEFT", w * f, 0)
end

local function SliderMove(s, value)
    value = math.max(s.min, math.min(s.max, value))
    if value == s.value then return end
    s.value = value
    SliderPlace(s)
    if s.onMove then s.onMove(s, value) end
end

-- the value under the mouse
local function SliderAt(s)
    local x = GetCursorPosition() / s:GetEffectiveScale()
    local f = math.max(0, math.min(1, (x - s:GetLeft()) / s:GetWidth()))
    return math.floor(s.min + f * (s.max - s.min) + 0.5)
end

-- the press ends (let go, or the window closed during it): the value is set
local function SliderRelease(s)
    if not s.dragging then return end
    s.dragging = false
    s:SetScript("OnUpdate", nil)
    if s.value ~= s.pressValue and s.onChange then s.onChange(s, s.value) end
end

function Widgets.CreateSlider(parent, width, min, max)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(width, 16)
    -- the knob at the ends stands out half: it can be taken there too
    s:SetHitRectInsets(-8, -8, -4, -4)
    s.min, s.max, s.value = min, max, min
    local track = CreateFrame("Frame", nil, s)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    Widgets.CreateBox(track, "BACKGROUND", 1, 3):SetColor(1, 1, 1, 0.14)
    s.fill = CreateFrame("Frame", nil, track)
    s.fill:SetPoint("LEFT")
    s.fill:SetHeight(6)
    local fill = Widgets.CreateBox(s.fill, "ARTWORK", 1, 3)
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetTexture(TEX.circle)
    s.knob:SetSize(14, 14)
    s:SetScript("OnMouseDown", function(self)
        self.dragging, self.pressValue = true, self.value
        SliderMove(self, SliderAt(self))
        self:SetScript("OnUpdate", function(x) SliderMove(x, SliderAt(x)) end)
    end)
    s:SetScript("OnMouseUp", SliderRelease)
    s:SetScript("OnHide", SliderRelease)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local before = self.value
        SliderMove(self, before + delta)
        if self.value ~= before and self.onChange then self.onChange(self, self.value) end
    end)
    function s:SetValue(value)
        self.value = math.max(self.min, math.min(self.max, value))
        SliderPlace(self)
    end
    Theme.OnAccent(s, function(_, r, g, b) fill:SetColor(r, g, b, 1) end)
    SliderPlace(s)
    return s
end

---------------------------------------------------------------------------
-- Check box with a label: the accent box with a check mark (the game's check box in the classic look)
---------------------------------------------------------------------------
local function CheckVisual(b)
    local hover = Hover(b)
    b.mark:SetShown(b.checked)
    local c = hover and C.white or b.color
    b.text:SetTextColor(c[1], c[2], c[3])
    if b.classic then
        b.hl:SetShown(hover)
        return
    end
    local a = Theme.accent
    if b.checked then
        b.box:SetColor(a[1], a[2], a[3], 1)
        b.ring:SetColor(a[1], a[2], a[3], 1)
    else
        b.box:SetColor(1, 1, 1, hover and 0.08 or 0.03)
        b.ring:SetColor(1, 1, 1, hover and 0.4 or 0.25)
    end
end

-- font, color: the label's; onChange(checked) after a click. SetLabel(text) takes the text as shown.
function Widgets.CreateCheck(parent, font, color, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.color, b.checked = color, false
    if Theme.IsClassic() then
        b.classic = true
        local function CheckTexture(file, sublevel)
            local x = b:CreateTexture(nil, "ARTWORK", nil, sublevel)
            x:SetTexture(file)
            x:SetSize(24, 24)
            x:SetPoint("LEFT", -4, 0)
            return x
        end
        b.box = CheckTexture(Theme.CLASSIC.checkUp, 0)
        b.hl = CheckTexture(Theme.CLASSIC.checkHighlight, 1)
        b.hl:SetBlendMode("ADD")
        b.mark = CheckTexture(Theme.CLASSIC.check, 2)
    else
        local holder = CreateFrame("Frame", nil, b)
        holder:SetSize(14, 14)
        holder:SetPoint("LEFT")
        b.box = Widgets.CreateBox(holder, "ARTWORK", 0, 4)
        b.ring = Widgets.CreateBox(holder, "ARTWORK", 1, 4, true)
        b.mark = Widgets.Glyph(holder, "check", 10, C.dark, "ARTWORK", 2)
        b.mark:SetPoint("CENTER")
    end
    b.text = Widgets.Text(b, font, color)
    b.text:SetPoint("LEFT", 21, 0)
    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(math.floor(21 + Widgets.TextWidth(self.text) + 0.5))
    end
    function b:SetChecked(v)
        self.checked = v and true or false
        CheckVisual(self)
    end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        onChange(self.checked)
    end)
    b:SetScript("OnEnter", function(self) self.hovered = true CheckVisual(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = false CheckVisual(self) end)
    Theme.OnAccent(b, CheckVisual)
    CheckVisual(b)
    return b
end

---------------------------------------------------------------------------
-- Menus (dropdowns, context menus) in the addon's own style.
-- The description API mirrors Blizzard's menu system: root:CreateTitle / CreateButton / CreateRadio.
---------------------------------------------------------------------------
local Desc = {}
Desc.__index = Desc

local function NewDesc(kind, text)
    return setmetatable({ kind = kind, text = text, elements = {} }, Desc)
end
Widgets.NewMenuDescription = NewDesc

function Desc:add(kind, text, a, b, data)
    local el = NewDesc(kind, LJ.L(text))
    el.a, el.b, el.data = a, b, data
    self.elements[#self.elements + 1] = el
    return el
end
function Desc:CreateTitle(text) return self:add("title", text) end
function Desc:CreateButton(text, fn, data) return self:add("button", text, fn, nil, data) end
function Desc:CreateRadio(text, isSelected, setSelected, data) return self:add("radio", text, isSelected, setSelected, data) end
function Desc:SetTooltip(fn) self.tooltip = fn end

local Menu = { rows = {} }
Widgets.Menu = Menu

local MENU_ROW = 26

local RADIO_UV = { off = { 0, 0.25, 0, 1 }, on = { 0.25, 0.5, 0, 1 } }

local function MenuRowVisual(row)
    local a = Theme.accent
    local el = row.el
    if not el then return end
    local interactive = el.kind == "button" or el.kind == "radio"
    if row.classic then
        -- Classic drop-down list: quest-title highlight, Blizzard radio buttons
        row.hlTex:SetShown(row.hovered and interactive)
        row.dot:Hide()
        if el.kind == "radio" then
            row.selected = (el.a and el.a(el.data)) and true or false
            row.mark:SetTexture(Theme.CLASSIC.radio)
            row.mark:SetTexCoord(unpack(row.selected and RADIO_UV.on or RADIO_UV.off))
            row.mark:SetSize(16, 16)
            row.mark:Show()
        else
            row.mark:Hide()
        end
        return
    end
    row.hl:SetColor(a[1], a[2], a[3], (Hover(row) and interactive) and 0.16 or 0)
    if el.kind == "radio" then
        row.selected = (el.a and el.a(el.data)) and true or false
        row.mark:SetTexture(TEX.circleRing)
        row.dot:SetShown(row.selected)
        row.dot:SetVertexColor(a[1], a[2], a[3], 1)
        row.mark:SetVertexColor(row.selected and a[1] or 0.55, row.selected and a[2] or 0.58, row.selected and a[3] or 0.62, 1)
        row.mark:Show()
    else
        row.mark:Hide()
        row.dot:Hide()
    end
end

local function EnsureMenuFrame()
    if Menu.frame then return Menu.frame end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() Menu.Close() end)
    catcher:Hide()
    Menu.catcher = catcher

    local f = CreateFrame("Frame", "LootifiedMenu", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    f.shadow = Widgets.CreateShadow(f, 14, 0.7)
    if Theme.IsClassic() then
        -- the classic look's dark brown panel, with the game's gold and white texts
        f.dark = true
        f.panel = Widgets.CreatePopupPanel(f, 4)
    else
        f.panel = Widgets.CreatePopupPanel(f, 10)
    end
    f:SetScript("OnHide", function()
        catcher:Hide()
        Menu.owner = nil
    end)
    Menu.frame = f
    return f
end

local function MenuRow(i)
    local row = Menu.rows[i]
    if row then return row end
    local f = Menu.frame
    row = CreateFrame("Button", nil, f)
    row:SetHeight(MENU_ROW)
    row.hl = Widgets.CreateBox(row, "BACKGROUND", 3, 6)
    if Theme.IsClassic() then
        row.classic = true
        row.hl:Hide()
        row.hlTex = row:CreateTexture(nil, "BACKGROUND", nil, 3)
        row.hlTex:SetTexture(Theme.CLASSIC.highlight)
        row.hlTex:SetBlendMode("ADD")
        row.hlTex:SetAllPoints()
        row.hlTex:Hide()
    end
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(12, 12)
    row.mark:SetPoint("LEFT", 9, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.dot:SetTexture(TEX.circle)
    row.dot:SetSize(6, 6)
    row.dot:SetPoint("CENTER", row.mark, "CENTER")
    if row.classic then
        row.mark:ClearAllPoints()
        row.mark:SetPoint("CENTER", row, "LEFT", 15, 0)
    end
    row.text = Widgets.Text(row, "itemSmall", C.text1)
    row:SetScript("OnEnter", function(self)
        self.hovered = true
        MenuRowVisual(self)
        if self.el and self.el.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            LJ:SafeCall(self.el.tooltip, GameTooltip, self.el)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        MenuRowVisual(self)
        if self.el and self.el.tooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        local el = self.el
        if not el then return end
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        if el.kind == "button" then
            Menu.Close()
            if el.a then LJ:SafeCall(el.a, el.data) end
        elseif el.kind == "radio" then
            Menu.Close()
            if el.b then LJ:SafeCall(el.b, el.data) end
        end
    end)
    Menu.rows[i] = row
    return row
end

-- Opens a menu description. anchor: "below" (under owner), "belowRight" (under owner, right edges aligned) or "cursor".
function Menu.Open(owner, desc, anchor, minWidth)
    local f = EnsureMenuFrame()
    Widgets.lastMenu = desc
    if f:IsShown() and Menu.owner == owner and (anchor == "below" or anchor == "belowRight") then
        Menu.Close()
        return
    end
    for _, r in ipairs(Menu.rows) do r:Hide() r.el = nil end
    -- keep the rows inside the dark menu's border
    local pad = f.dark and 3 or 0
    -- the game's dark menu has the game's text colors
    local titleColor, rowColor = C.text4, C.text1
    if f.dark then titleColor, rowColor = Theme.ON_DARK.gold, Theme.ON_DARK.white end
    local y, width = 6 + pad, minWidth or 150
    for i, el in ipairs(desc.elements) do
        local row = MenuRow(i)
        row.el = el
        row:ClearAllPoints()
        local interactive = el.kind == "button" or el.kind == "radio"
        local h = MENU_ROW
        row.text:ClearAllPoints()
        if el.kind == "title" then
            h = 22
            row.text:SetFontObject(Theme.Font("label"))
            Widgets.SetTextColor(row.text, titleColor)
            row.text:SetText(Theme.Case(el.text or ""))
            row.text:SetPoint("LEFT", 10, -1)
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, -1)
        else
            row.text:SetFontObject(Theme.Font("itemSmall"))
            Widgets.SetTextColor(row.text, rowColor)
            row.text:SetText(el.text or "")
            row.text:SetPoint("LEFT", el.kind == "radio" and (row.classic and 30 or 28) or 10, 0)
            -- the menu is at most 360 wide: longer texts end with "..." inside it
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        row:SetHeight(h)
        row:EnableMouse(interactive)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + pad, -y)
        row:SetPoint("RIGHT", f, "RIGHT", -4 - pad, 0)
        row.hovered = false
        row:Show()
        MenuRowVisual(row)
        local tw = Widgets.TextWidth(row.text) + (el.kind == "radio" and 46 or 28)
        if tw > width then width = tw end
        y = y + h
    end
    width = math.min(360, math.floor(width + 0.5))
    f:SetSize(width + 8 + pad * 2, y + 6 + pad)
    -- same scale as the window it belongs to; anchor offsets are in the menu's own (scaled) units
    f:SetScale(owner and owner.GetEffectiveScale and (owner:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1)
    f:ClearAllPoints()
    if anchor == "cursor" then
        local x, cy = GetCursorPosition()
        local es = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / es + 2, cy / es - 2)
    elseif anchor == "belowRight" then
        -- below a button at the window's right edge: the menu ends where the button ends
        f:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    else
        f:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    end
    Menu.owner = owner
    Menu.catcher:Show()
    f:Show()
    f:SetAlpha(0)
    Anim.Fade(f, 1, 0.1)
end

function Menu.Close()
    if Menu.frame and Menu.frame:IsShown() then Menu.frame:Hide() end
    if Menu.catcher then Menu.catcher:Hide() end
end

-- After a skin switch: the menu is created again in the new look on its next use.
function Menu.Reset()
    Menu.Close()
    Menu.frame, Menu.catcher, Menu.owner = nil, nil, nil
    Menu.rows = {}
end

function Widgets.ShowContextMenu(owner, build)
    local root = NewDesc("root")
    build(root)
    Menu.Open(owner, root, "cursor")
    return root
end

---------------------------------------------------------------------------
-- Dropdown button (opens a menu below itself)
---------------------------------------------------------------------------
local function DropdownVisual(dd)
    if dd.classic then
        dd.buttonHL:SetShown(dd.hovered and true or false)
        return
    end
    local hover = Hover(dd)
    dd.fill:SetColor(1, 1, 1, hover and 0.09 or 0.05)
    dd.ring:SetColor(1, 1, 1, hover and 0.16 or 0.09)
end

-- width: number, or nil to fit the label.
function Widgets.CreateDropdown(parent, width, build, defaultText, glyph)
    local dd = CreateFrame("Button", nil, parent)
    dd:SetSize(width or 120, 26)
    dd.autoWidth = width == nil
    dd.fill = Widgets.CreateBox(dd, "BACKGROUND", 1, 6)
    dd.ring = Widgets.CreateBox(dd, "BACKGROUND", 2, 6, true)
    dd.caret = Widgets.Glyph(dd, "caretDown", 12, C.text4)
    dd.caret:SetPoint("RIGHT", -8, 0)
    dd.label = Widgets.Text(dd, "button", Theme.hex("D7DBE0"))
    if glyph then
        dd.icon = Widgets.Glyph(dd, glyph, 13, C.text4)
        dd.icon:SetPoint("LEFT", 9, 0)
        dd.label:SetPoint("LEFT", dd.icon, "RIGHT", 6, 0)
    else
        dd.label:SetPoint("LEFT", 10, 0)
    end
    dd.label:SetPoint("RIGHT", dd.caret, "LEFT", -4, 0)
    if Theme.IsClassic() then
        -- Classic drop-down: Blizzard's label frame and the round arrow button
        dd.classic = true
        dd.fill:Hide()
        dd.ring:Hide()
        dd.caret:Hide()
        local k = 26 / 30              -- the visible box of the label frame is 30 of its 64 px
        local frameArt = Widgets.CreateThreeSlice(dd, Theme.CLASSIC.dropdown, { 0, 0.1953125, 0.8046875, 1, 0, 1 },
            math.floor(25 * k + 0.5), "BACKGROUND", 1)
        local side, top = 16 * k, 17 * k
        frameArt:SetAnchor(dd, -side, -top, -side, -(64 * k - 26 - top))
        dd.frameArt = frameArt
        dd.button = dd:CreateTexture(nil, "ARTWORK", nil, 1)
        dd.button:SetTexture(Theme.CLASSIC.dropdownButton)
        dd.button:SetSize(22, 22)
        dd.button:SetPoint("RIGHT", 2, 0)
        dd.buttonHL = dd:CreateTexture(nil, "ARTWORK", nil, 2)
        dd.buttonHL:SetTexture(Theme.CLASSIC.mouseHighlight)
        dd.buttonHL:SetBlendMode("ADD")
        dd.buttonHL:SetAllPoints(dd.button)
        dd.buttonHL:Hide()
        dd:HookScript("OnMouseDown", function(self) self.button:SetTexture(Theme.CLASSIC.dropdownButtonDown) end)
        dd:HookScript("OnMouseUp", function(self) self.button:SetTexture(Theme.CLASSIC.dropdownButton) end)
        local D = Theme.ON_DARK
        dd.label:SetTextColor(D.white[1], D.white[2], D.white[3])
        dd.label:ClearAllPoints()
        if dd.icon then
            dd.icon:SetVertexColor(D.gold[1], D.gold[2], D.gold[3], 1)
            dd.label:SetPoint("LEFT", dd.icon, "RIGHT", 6, 0)
        else
            dd.label:SetPoint("LEFT", 8, 0)
        end
        dd.label:SetPoint("RIGHT", dd.button, "LEFT", -2, 0)
    end
    dd.build = build
    dd.menuDescription = NewDesc("root")
    function dd:GenerateMenu()
        local root = NewDesc("root")
        self.build(root)
        self.menuDescription = root
        return root
    end
    function dd:SetLabel(text)
        self.label:SetText(LJ.L(text) or "")
        if self.autoWidth then
            self.label:ClearAllPoints()
            if self.icon then self.label:SetPoint("LEFT", self.icon, "RIGHT", 6, 0) else self.label:SetPoint("LEFT", self.classic and 8 or 10, 0) end
            if self.classic then
                -- label insets: 8 (or 9 + icon 13 + 6) on the left, arrow button 22 - 2 + 2 on the right
                self:SetWidth(math.ceil(Widgets.TextWidth(self.label) + (self.icon and 50 or 32)))
                self.label:SetPoint("RIGHT", self.button, "LEFT", -2, 0)
            else
                -- label insets: 10 (or 9 + icon 13 + 6) on the left, caret 12 + 8 + 4 on the right
                self:SetWidth(math.ceil(Widgets.TextWidth(self.label) + (self.icon and 52 or 34)))
                self.label:SetPoint("RIGHT", self.caret, "LEFT", -4, 0)
            end
        end
    end
    function dd:Refresh() end
    dd:SetScript("OnClick", function(self)
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        Menu.Open(self, self:GenerateMenu(), "below", self:GetWidth() - 8)
    end)
    dd:SetScript("OnEnter", function(self)
        self.hovered = true
        DropdownVisual(self)
        -- a tooltip set with Widgets.SetTooltip, like the buttons
        if self.tooltipTitle and not (Menu.frame and Menu.frame:IsShown() and Menu.owner == self) then
            GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
            if self.tooltipText then GameTooltip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    end)
    dd:SetScript("OnLeave", function(self)
        self.hovered = false
        DropdownVisual(self)
        if self.tooltipTitle and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    DropdownVisual(dd)
    dd:SetLabel(defaultText or "")
    return dd
end

---------------------------------------------------------------------------
-- Scroll area with a thin scroll bar and smooth wheel scrolling
---------------------------------------------------------------------------
function Widgets.CreateScrollArea(parent, barOffset)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll:EnableMouseWheel(true)

    local barWidth = 4
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(barWidth)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", barOffset or 3, -2)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", barOffset or 3, 2)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 5)
    bar.track = Widgets.CreateVBar(bar, "BACKGROUND")
    bar.track:SetColor(1, 1, 1, 0.04)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(barWidth)
    thumb:SetHitRectInsets(-5, -5, 0, 0)
    thumb.tex = Widgets.CreateVBar(thumb, "ARTWORK")
    thumb.tex:SetColor(1, 1, 1, 0.2)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    thumb:SetHeight(40)
    bar.thumb = thumb
    bar:Hide()
    scroll.bar = bar

    local function Range()
        return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
    end
    scroll.GetMaxScroll = Range

    local function UpdateThumb()
        local range = Range()
        local h = scroll:GetHeight() or 0
        if range <= 0.5 or h <= 0 or not scroll:IsShown() then
            bar:Hide()
            return
        end
        bar:Show()
        local trackH = math.max(10, h - 4)
        local thumbH = math.max(24, trackH * h / (h + range))
        thumb:SetHeight(thumbH)
        local y = (trackH - thumbH) * (scroll:GetVerticalScroll() / range)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -y)
        thumb.tex:SetAnchor(thumb)
        bar.track:SetAnchor(bar)
    end
    scroll.UpdateThumb = UpdateThumb

    -- scroll.onScroll(scroll): optional, called whenever the offset or the size of the view changes (lists that
    -- only build their visible rows)
    local function SetScroll(y)
        y = math.max(0, math.min(Range(), y))
        scroll:SetVerticalScroll(y)
        UpdateThumb()
        if scroll.onScroll then scroll.onScroll(scroll) end
    end

    function scroll:ScrollTo(y, smooth)
        y = math.max(0, math.min(Range(), y))
        self.target = y
        if smooth then
            local from = self:GetVerticalScroll()
            Anim.Run(self, 0.2, function(p) SetScroll(from + (y - from) * p) end)
        else
            Anim.Stop(self)
            SetScroll(y)
        end
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local base = (Anim.active[self] and self.target) or self:GetVerticalScroll()
        self:ScrollTo(base - delta * 60, true)
    end)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
        -- a taller view has less to scroll: the offset stays inside the new range
        if self:GetVerticalScroll() > Range() then self:SetVerticalScroll(Range()) end
        UpdateThumb()
        if self.onScroll then self.onScroll(self) end
    end)

    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, cy = GetCursorPosition()
        self.startY = cy / self:GetEffectiveScale()
        self.startScroll = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(s)
            if not s.dragging then return end
            local _, y = GetCursorPosition()
            y = y / s:GetEffectiveScale()
            local h = scroll:GetHeight() or 1
            local trackH = math.max(10, h - 4)
            local free = math.max(1, trackH - s:GetHeight())
            SetScroll(s.startScroll + (s.startY - y) / free * Range())
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    -- the window closed during a drag: no mouse-up arrives, the drag ends here
    thumb:SetScript("OnHide", function(self)
        if self.dragging then
            self.dragging = false
            self:SetScript("OnUpdate", nil)
        end
    end)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColor(1, 1, 1, 0.35) end)
    thumb:SetScript("OnLeave", function(self) self.tex:SetColor(1, 1, 1, 0.2) end)

    function scroll:SetContentHeight(height)
        local width = self:GetWidth()
        if width and width > 0 then content:SetWidth(width) end
        content:SetHeight(math.max(1, height))
        if self:GetVerticalScroll() > Range() then SetScroll(Range()) end
        UpdateThumb()
    end
    function scroll:ScrollToTop()
        self:ScrollTo(0)
    end
    scroll:HookScript("OnShow", UpdateThumb)
    scroll:HookScript("OnHide", function() bar:Hide() end)
    return scroll, content
end

---------------------------------------------------------------------------
-- Tabs: underline tabs (hero tabs, top navigation); in the classic look a row of brown buttons, the picked one red
---------------------------------------------------------------------------
-- defs = { { key, text, glyph, count (false: no count pill) } }; opts = { font, height, pad, gap, tabHeight (classic:
-- the buttons' height), fill (a width: the bar gets it, its tabs share it equally with their content centered),
-- iconAccent (the picked tab's glyph in the layout color), onLayout(bar): after every layout (bar.width = the tabs'
-- width) }
function Widgets.CreateTabs(parent, defs, onSelect, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(opts.height or 38)
    bar.tabs, bar.byKey = {}, {}
    bar.hearth = Theme.IsClassic()
    local pad, gap = opts.pad or 12, opts.gap or (bar.hearth and 6 or 0)
    local tabHeight = opts.tabHeight or 26
    if opts.fill then bar:SetWidth(opts.fill) end

    bar.glow = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.glow:SetTexture(TEX.glowLine)
    bar.glow:SetBlendMode("ADD")
    bar.glow:SetHeight(14)
    bar.line = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.line:SetTexture(Theme.RoundFile(4))
    bar.line:SetHeight(2)
    bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, opts.lineOffset or 0)
    bar.glow:SetPoint("CENTER", bar.line, "CENTER", 0, 0)

    local function TabVisual(tab)
        local on = bar.selected == tab.key
        if bar.hearth then
            local H = Theme.HEARTH
            local hover = tab.hovered and not on
            Widgets.BoxFill(tab.fill, tab.ring, on and "red" or "button", hover)
            local c = (hover and C.white) or (on and H.redText) or H.buttonText
            tab.text:SetTextColor(c[1], c[2], c[3])
            if tab.icon then tab.icon:SetVertexColor(c[1], c[2], c[3]) end
            if tab.count then tab.count:Set(tab.count.text:GetText(), "dark") end
            return
        end
        local c = on and C.white or (Hover(tab) and C.text1 or Theme.hex("9AA2AE"))
        tab.text:SetTextColor(c[1], c[2], c[3])
        if tab.icon then
            local ic = (on and opts.iconAccent) and Theme.accent or c
            tab.icon:SetVertexColor(ic[1], ic[2], ic[3])
        end
        if tab.count then tab.count:Set(tab.count.text:GetText(), on and "solid" or "dark") end
    end

    local function Layout()
        local x = opts.startX or 0
        local shown = 0
        for _, tab in ipairs(bar.tabs) do
            if tab:IsShown() then shown = shown + 1 end
        end
        for _, tab in ipairs(bar.tabs) do
            if tab:IsShown() then
                local w = Widgets.TextWidth(tab.text) + pad * 2
                if tab.icon then w = w + 18 end
                if tab.count and tab.count:IsShown() then w = w + tab.count:GetWidth() + 7 end
                if opts.fill then
                    local share = math.floor((opts.fill - gap * (shown - 1)) / shown)
                    local first = tab.icon or tab.text
                    first:SetPoint("LEFT", math.floor((share - w) / 2) + pad, opts.textOffset or 0)
                    w = share
                end
                tab:SetWidth(math.floor(w + 0.5))
                tab:ClearAllPoints()
                if bar.hearth then
                    tab:SetHeight(tabHeight)
                    tab:SetPoint("LEFT", bar, "LEFT", x, 0)
                else
                    tab:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
                    tab:SetPoint("TOP", bar, "TOP")
                end
                tab.x = x   -- kept here: GetPoint(1) returns the points in anchor order (TOP before BOTTOMLEFT)
                x = x + tab:GetWidth() + gap
            end
        end
        bar.width = x
        if opts.onLayout then opts.onLayout(bar) end
    end
    bar.Layout = Layout

    local function PlaceLine(instant)
        local tab = bar.byKey[bar.selected]
        if bar.hearth or not tab or not tab:IsShown() then
            bar.line:Hide()
            bar.glow:Hide()
            return
        end
        bar.line:Show()
        bar.glow:Show()
        local tx = tab.x or 0
        local x1, w1 = tx + pad - 2, tab:GetWidth() - pad * 2 + 4
        local x0, w0 = bar.lineX or x1, bar.lineW or w1
        bar.lineX, bar.lineW = x1, w1
        if instant or not bar:IsVisible() then
            Anim.Stop(bar)
            bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x1, opts.lineOffset or 0)
            bar.line:SetWidth(w1)
            bar.glow:SetWidth(w1 + 30)
        else
            Anim.Run(bar, 0.22, function(p)
                bar.line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x0 + (x1 - x0) * p, opts.lineOffset or 0)
                bar.line:SetWidth(w0 + (w1 - w0) * p)
                bar.glow:SetWidth(w0 + (w1 - w0) * p + 30)
            end)
        end
    end

    for _, def in ipairs(defs) do
        local tab = CreateFrame("Button", nil, bar)
        tab.key = def.key
        tab.text = Widgets.Text(tab, opts.font or "tab", C.text3)
        local textY = opts.textOffset or 0
        if bar.hearth then
            tab.fill = Widgets.CreateBox(tab, "BACKGROUND", 1, 4)
            tab.ring = Widgets.CreateBox(tab, "BACKGROUND", 2, 4, true)
        end
        if def.glyph then
            tab.icon = Widgets.Glyph(tab, def.glyph, bar.hearth and 13 or 14, C.text3)
            tab.icon:SetPoint("LEFT", pad, textY)
            tab.text:SetPoint("LEFT", tab.icon, "RIGHT", bar.hearth and 6 or 4, 0)
        else
            tab.text:SetPoint("LEFT", pad, textY)
        end
        if def.count ~= false then
            tab.count = Widgets.CreatePill(tab, 16, "count")
            tab.count:SetPoint("LEFT", tab.text, "RIGHT", 7, 0)
            tab.count:Hide()
        end
        tab:SetScript("OnClick", function(t)
            Util.PlaySound("IG_CHARACTER_INFO_TAB")
            if onSelect then onSelect(t.key) end
        end)
        tab:SetScript("OnEnter", function(t) t.hovered = true TabVisual(t) end)
        tab:SetScript("OnLeave", function(t) t.hovered = false TabVisual(t) end)
        tab.text:SetText(LJ.L(def.text))
        bar.byKey[def.key] = tab
        bar.tabs[#bar.tabs + 1] = tab
        function tab:SetLabel(text)
            self.text:SetText(LJ.L(text))
            Layout()
            PlaceLine(true)
        end
        TabVisual(tab)
    end

    function bar:SetCount(key, n)
        local tab = self.byKey[key]
        if not tab or not tab.count then return end
        if n and n > 0 then
            tab.count:Set(tostring(n), (self.selected == key and not self.hearth) and "solid" or "dark")
            tab.count:Show()
        else
            tab.count:Hide()
        end
        Layout()
        PlaceLine(true)
    end

    -- a tab shown or hidden: the others close up
    function bar:ShowTab(key, shown)
        self.byKey[key]:SetShown(shown)
        Layout()
        PlaceLine(true)
    end

    function bar:Select(key, instant)
        self.selected = key
        for _, tab in ipairs(self.tabs) do TabVisual(tab) end
        PlaceLine(instant)
    end

    Theme.OnAccent(bar, function(b, r, g, bb)
        b.line:SetVertexColor(r, g, bb, 1)
        b.glow:SetVertexColor(r, g, bb, 0.9)
        if opts.iconAccent then
            for _, tab in ipairs(b.tabs) do TabVisual(tab) end
        end
    end)
    Layout()
    return bar
end

---------------------------------------------------------------------------
-- Section label with a hairline ("REWARDS ----------")
---------------------------------------------------------------------------
function Widgets.CreateSectionLabel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(14)
    f.text = Widgets.Text(f, "label", C.text4)
    f.text:SetPoint("LEFT", 0, 0)
    f.line = Widgets.Line(f, "ARTWORK", 0.06)
    f.line:SetHeight(1)
    f.line:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
    f.line:SetPoint("RIGHT", 0, 0)
    function f:SetLabel(text) self.text:SetText(Theme.Case(LJ.L(text) or "")) end
    return f
end

---------------------------------------------------------------------------
-- Item icon (real item icon, rounded mask, quality border, owned check)
---------------------------------------------------------------------------
-- Methods shared by every item icon (no closures per icon). The owned check and the count text are made the first
-- time an icon needs them.
local ItemIcon = {}

function ItemIcon.SetQualityColor(self, r, g, bl, a)
    self.border:SetColor(r, g, bl, a or 0.95)
    self.inner:SetColor(r, g, bl, (a or 1) * 0.28)
end

function ItemIcon.SetCount(self, count)
    local text = (count and count > 1) and tostring(count) or nil
    if text and not self.count then
        self.count = Theme.PrepareFontString(self:CreateFontString(nil, "OVERLAY"))
        self.count:SetFontObject(Theme.Font("tiny"))
        self.count:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if self.count then self.count:SetText(text or "") end
end

function ItemIcon.SetItem(self, itemID, count)
    self.itemID = itemID
    self:SetCount(count)
    if not itemID then
        self.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self.icon:SetDesaturated(false)
        self:SetQualityColor(1, 1, 1, 0.1)
        self:SetOwned(false)
        return
    end
    local rec = Items.Get(itemID)
    self.icon:SetTexture(rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon:SetDesaturated(rec.exists == false)
    local r, g, bl = Util.QualityColor(rec.quality or 1)
    if (rec.quality or 1) <= 1 then
        self:SetQualityColor(1, 1, 1, 0.22)
    else
        self:SetQualityColor(r, g, bl, 0.95)
    end
end

function ItemIcon.SetOwned(self, owned)
    if owned and not self.check then
        self.check = self:CreateTexture(nil, "OVERLAY", nil, 3)
        self.check:SetTexture(TEX.circle)
        self.check:SetSize(12, 12)
        self.check:SetPoint("BOTTOMRIGHT", 4, -4)
        self.check:SetVertexColor(C.ok[1], C.ok[2], C.ok[3], 1)
        self.checkMark = self:CreateTexture(nil, "OVERLAY", nil, 4)
        self.checkMark:SetSize(8, 8)
        self.checkMark:SetPoint("CENTER", self.check, "CENTER")
        Theme.SetGlyph(self.checkMark, "check", C.dark)
    end
    if self.check then
        self.check:SetShown(owned and true or false)
        self.checkMark:SetShown(owned and true or false)
    end
end

function Widgets.CreateItemIcon(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.shade = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.shade:SetTexture(Theme.RoundFile(4))
    b.shade:SetPoint("TOPLEFT", -1, 1)
    b.shade:SetPoint("BOTTOMRIGHT", 1, -1)
    b.shade:SetVertexColor(0, 0, 0, Theme.IsClassic() and 1 or 0.7)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not Theme.IsClassic() then
        -- rounded corners with an inner glow; the classic look keeps the game's square icons
        b.mask = b:CreateMaskTexture()
        b.mask:SetTexture(TEX.maskRound, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.mask:SetAllPoints(b.icon)
        b.icon:AddMaskTexture(b.mask)
        b.inner = Widgets.CreateBox(b, "OVERLAY", 0, 4, true)
        b.inner:SetAnchor(b, 1, 1, 1, 1)
    else
        -- no inner glow: a transparent stand-in that never makes textures
        b.inner = Widgets.CreateLazyBox(b, "OVERLAY", 0, 4, true)
        b.inner:Hide()
    end
    b.border = Widgets.CreateBox(b, "OVERLAY", 1, 4, true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.SetQualityColor, b.SetCount, b.SetItem, b.SetOwned = ItemIcon.SetQualityColor, ItemIcon.SetCount, ItemIcon.SetItem,
        ItemIcon.SetOwned
    return b
end

---------------------------------------------------------------------------
-- Item tooltip (Blizzard item tooltip + our extra lines from Tooltip.lua)
---------------------------------------------------------------------------
-- The side of a frame with more room on the screen: its tooltip opens there and the game's item comparison beside it,
-- toward the middle of the screen (like the game's bag items).
function Widgets.TooltipAnchor(owner)
    local scale = owner:GetEffectiveScale()
    local left = owner:GetLeft() * scale
    local right = UIParent:GetWidth() * UIParent:GetEffectiveScale() - owner:GetRight() * scale
    return right >= left and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
end

-- The owner whose item tooltip the game redoes (its UpdateTooltip); none once the tooltip is hidden.
local redoing
GameTooltip:HookScript("OnHide", function()
    if redoing then redoing.UpdateTooltip = nil end
    redoing = nil
end)

local function RedoItemTooltip(owner)
    Widgets.ShowItemTooltip(owner, owner.tooltipItemID, owner.tooltipExtraLines)
end

function Widgets.ShowItemTooltip(owner, itemID, extraLines)
    if not itemID then return end
    GameTooltip:SetOwner(owner, Widgets.TooltipAnchor(owner))
    local rec = Items.Get(itemID)
    LJ.Tooltip.SetExtraLines(owner, itemID, extraLines)
    if rec.exists == false then
        GameTooltip:SetText(rec.fallbackName or F("Item #%d", itemID), 1, 1, 1)
        GameTooltip:AddLine(L("This item is not in your game client yet (datamined / upcoming)."), 0.8, 0.8, 0.8, true)
        LJ.Tooltip.AddLines(GameTooltip, itemID, true)
        if extraLines then LJ.Tooltip.AddExtraLines(GameTooltip) end
    else
        -- the extra lines come in with the game's item lines (UI/Tooltip.lua); the game adds its comparison with what
        -- is worn (Shift or "Always compare items")
        GameTooltip:SetItemByID(itemID)
    end
    GameTooltip:Show()
    -- while it shows, the game redoes the tooltip of an owner with UpdateTooltip every 0.2 s (GameTooltip_OnUpdate),
    -- as for its bag items: the comparison is filled once, with "Retrieving item information" while the game has no
    -- data of the worn item, and gets the item on the next go
    owner.tooltipItemID, owner.tooltipExtraLines = itemID, extraLines
    owner.UpdateTooltip = RedoItemTooltip
    redoing = owner
end

-- Right-click menu for any item.
-- Names of the Best in Slot data slots
Widgets.SLOT_NAMES = {
    HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back", CHEST = "Chest", WRIST = "Wrist",
    HANDS = "Hands", WAIST = "Waist", LEGS = "Legs", FEET = "Feet", FINGER = "Finger", TRINKET = "Trinket",
    MAINHAND = "Main Hand", OFFHAND = "Off Hand", TWOHAND = "Two-hand weapon", RANGED = "Ranged", RELIC = "Relic",
}

-- Puts an item's link into the chat line.
function Widgets.LinkInChat(itemID)
    local link = Items.GetLink(itemID)
    -- opens the chat line when none is open (InsertLink only fills an open one)
    ChatFrameUtil.LinkItem(itemID, link:find("|H", 1, true) and link or nil)
end

-- Try on (the game's Dressing Room, DressUpItemLink): the Dressing Room is a UI panel, and in combat the game does not
-- show a UI panel for an addon (UIParentPanelManager.lua: ShowUIPanel only says "Interface action failed"). The Try on
-- buttons (Widgets.SetTryOn) are off while the player is in combat; the menus leave Try on out then.
local tryOnButtons = {}
-- on: b tries on (off in combat); false: b does something else now (a button the database look gives other actions)
function Widgets.SetTryOn(b, on)
    tryOnButtons[b] = on or nil
    b:SetEnabled(not (on and InCombatLockdown()))
end
LJ:On("PLAYER_REGEN_DISABLED", function()
    for b in pairs(tryOnButtons) do b:Disable() end
end)
LJ:On("PLAYER_REGEN_ENABLED", function()
    for b in pairs(tryOnButtons) do b:Enable() end
end)

function Widgets.ShowItemMenu(owner, itemID)
    return Widgets.ShowContextMenu(owner, function(root)
        root:CreateTitle(Items.GetName(itemID))
        if LJ.Modules.On("wishlist") then
            root:CreateButton(Items.IsWishlisted(itemID) and "Remove from Wishlist" or "Add to Wishlist", function()
                Items.ToggleWishlist(itemID)
            end)
        end
        root:CreateButton("Link in chat", function() Widgets.LinkInChat(itemID) end)
        -- the simulator: this item against what the player wears (the upgrade check's window)
        if not LJ.NO_SIM and LJ.UI.Sim.CanSim(itemID) then
            root:CreateButton("Simulate", function() LJ.UI.ItemCheckBox:Check(Items.GetLink(itemID)) end)
        end
        -- (no Try on in combat: Widgets.SetTryOn)
        if not InCombatLockdown() then
            root:CreateButton("Preview in Dressing Room", function() DressUpItemLink(Items.GetLink(itemID)) end)
        end
        -- links into the journal (the database look shows them on its own pages)
        local journal = Theme.IsDatabase() or LJ.Modules.On("journal")
        local sources = journal and Items.GetSources(itemID)
        if sources and sources[1] then
            local s = sources[1]
            local inst = LJ.instanceByKey[s.inst]
            if inst then
                root:CreateButton(F("Show source: %s", inst.name), function()
                    LJ:Open("instance", inst.key, s.boss)
                end)
            end
        end
        local Q = LJ.Quests
        local quests, seen = {}, {}
        local function AddQuest(qid)
            if qid and not seen[qid] then
                seen[qid] = true
                quests[#quests + 1] = qid
            end
        end
        if Q and journal then
            -- separate loops: a list of lists would stop at a missing first list
            for _, qid in ipairs(Q.rewardOf[itemID] or {}) do AddQuest(qid) end
            for _, qid in ipairs(Q.neededFor[itemID] or {}) do AddQuest(qid) end
            -- a quest item often starts the quest it is needed for: each quest once
            AddQuest(Q.startedBy[itemID])
        end
        for i, qid in ipairs(quests) do
            if i > 3 then break end
            root:CreateButton(F("Show quest: %s", Q.GetName(qid)), function()
                LJ:Open("quest", qid)
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- Compact item row (loot lists, rewards, wishlist, search)
---------------------------------------------------------------------------
-- Height of an item row (lists lay them out with it).
function Widgets.ItemRowHeight()
    return 32
end

-- Item rows share their scripts and methods (no closures per row). The wishlist star and the badges are made the
-- first time a row needs them, the hover boxes the first time the row is hovered.
-- the wishlist star's outline: light grey on the glass, the classic look's muted text color
local STAR_LINE_GLASS = Theme.hex("DFE3E8")
local function StarLine()
    if Theme.IsClassic() then return C.text4 end
    return STAR_LINE_GLASS
end
local BADGE_UPGRADE = { "upgrade", C.ok, { 0.29, 0.87, 0.5, 0.13 } }
local BADGE_QUEST = { "scroll", C.gold, { 0.96, 0.78, 0.27, 0.12 } }
local NO_OPTS = {}
local badgeDefs = {}        -- scratch list of ItemRow.SetItem
local GetStar

local function RowHover(row, on)
    row.hovered = on
    row.hoverFrom, row.hoverTo = row.hlAlpha or 0, on and 1 or 0
    local fn = row.hoverFn
    if not fn then
        fn = function(p)
            local a = row.hoverFrom + (row.hoverTo - row.hoverFrom) * p
            row.hlAlpha = a
            row.hl:SetColor(1, 1, 1, 0.06 * a)
            row.hlRing:SetColor(1, 1, 1, 0.06 * a)
        end
        row.hoverFn = fn
    end
    Anim.Run(row.hl, 0.1, fn)
    local wished = row.itemID and Items.IsWishlisted(row.itemID)
    if (on and LJ.Modules.On("wishlist")) or wished then
        GetStar(row):SetAlpha(1)
    elseif row.star then
        row.star:SetAlpha(0)
    end
end

local function StarOnClick(self)
    local r = self:GetParent()
    if r.itemID then Items.ToggleWishlist(r.itemID) end
end

local function StarOnEnter(self)
    local r = self:GetParent()
    RowHover(r, true)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local wished = r.itemID and Items.IsWishlisted(r.itemID)
    GameTooltip:SetText(wished and L("Remove from Wishlist") or L("Add to Wishlist"), 1, 1, 1)
    GameTooltip:Show()
end

local function StarOnLeave(self)
    RowHover(self:GetParent(), false)
    GameTooltip:Hide()
end

-- The wishlist star at the right end of a row.
function GetStar(row)
    local star = row.star
    if star then return star end
    star = CreateFrame("Button", nil, row)
    star:SetSize(20, 20)
    star:SetPoint("RIGHT", -6, 0)
    star.bg = Widgets.CreateBox(star, "BACKGROUND", 0, 6)
    star.bg:SetColor(1, 1, 1, 0.08)
    if Theme.IsClassic() then star.bg:Hide() end
    star.tex = Widgets.Glyph(star, "starLine", 14, StarLine())
    star.tex:SetPoint("CENTER")
    star:SetAlpha(0)
    star:SetScript("OnClick", StarOnClick)
    star:SetScript("OnEnter", StarOnEnter)
    star:SetScript("OnLeave", StarOnLeave)
    row.star = star
    return star
end

local function GetBadge(row, i)
    local b = row.badges[i]
    if b then return b end
    b = CreateFrame("Frame", nil, row)
    b:SetSize(18, 18)
    b.bg = Widgets.CreateBox(b, "BACKGROUND", 0, 4)
    b.icon = Widgets.Glyph(b, "star", 12)
    b.icon:SetPoint("CENTER")
    row.badges[i] = b
    return b
end

local function RowOnUpdate(s)
    if s.itemID and IsModifiedClick("DRESSUP") then
        ShowInspectCursor()
    else
        ResetCursor()
    end
end

local function RowOnEnter(self)
    RowHover(self, true)
    Widgets.ShowItemTooltip(self, self.itemID, self.extraTooltip)
    self:SetScript("OnUpdate", RowOnUpdate)
end

local function RowOnLeave(self)
    RowHover(self, false)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", nil)
    ResetCursor()
end

local function RowOnClick(self, button)
    if not self.itemID then return end
    if Items.HandleClick(self.itemID, button) then return end
    if button == "RightButton" then
        Widgets.ShowItemMenu(self, self.itemID)
    elseif self.onClick then
        self.onClick(self, button)
    end
end

-- opts: { chance, rightText (pill text instead of a chance), rightKind, right (type column text),
--         noChance (hide the pill), upgrade (BiS.Upgrade: an item of the Best in Slot list), unusable, count,
--         extraTooltip }
local function ItemRowSetItem(self, itemID, opts)
    opts = opts or NO_OPTS
    self.itemID = itemID
    local rec = Items.Get(itemID)
    self.iconButton:SetItem(itemID, opts.count)
    self.iconButton:SetOwned(Items.IsOwned(itemID))
    local q = rec.quality or 1
    local r, g, b = Util.QualityColor(q)
    if rec.isQuest and not rec.loaded then r, g, b = C.text1[1], C.text1[2], C.text1[3] end
    self.name:SetText(rec.name or rec.fallbackName or F("Item #%d", itemID))
    self.name:SetTextColor(r, g, b)

    -- right cluster
    -- the pill column keeps its width without a chance, so the type texts of a list line up
    local rightEdge = 32 -- star + gap
    if opts.rightText then
        self.chancePill:Set(opts.rightText, opts.rightKind or "gray", nil, 52)
        self.chancePill:Show()
        rightEdge = rightEdge + 58
    elseif opts.noChance then
        self.chancePill:Hide()
        self.chance:SetText("")
    else
        local text = FormatChance(opts.chance)
        if text then
            self.chancePill:Set(text, "chance", nil, 44)
            self.chancePill:SetTextColorOverride(Theme.ChanceColor(opts.chance))
            self.chancePill:Show()
        else
            self.chancePill:Hide()
            self.chance:SetText("")
        end
        rightEdge = rightEdge + 50
    end

    local n = 0
    if opts.upgrade then n = n + 1; badgeDefs[n] = BADGE_UPGRADE end
    local Q = LJ.Quests
    if Q and (Q.rewardOf[itemID] or Q.neededFor[itemID] or Q.startedBy[itemID]) and not opts.hideQuestBadge then
        n = n + 1; badgeDefs[n] = BADGE_QUEST
    end
    local x = -rightEdge
    for i = 1, math.max(n, #self.badges) do
        if i <= n then
            local def = badgeDefs[i]
            local badge = GetBadge(self, i)
            Theme.SetGlyph(badge.icon, def[1], def[2])
            badge.bg:SetColor(def[3])
            badge.bg:SetShown(not Theme.IsClassic())
            badge:ClearAllPoints()
            badge:SetPoint("RIGHT", self, "RIGHT", x, 0)
            badge:Show()
            x = x - 22
        else
            self.badges[i]:Hide()
        end
    end

    self.type:SetText(opts.right or Items.GetSlotText(itemID) or "")
    self.type:ClearAllPoints()
    self.type:SetPoint("RIGHT", self, "RIGHT", x - 4, 0)
    local unusable = opts.unusable
    Widgets.SetTextColor(self.type, unusable and C.bad or C.text3)
    self:SetAlpha(unusable and 0.5 or 1)

    -- name width: up to the type text, leaving room for the tag
    local tag = opts.tag or ((rec.setID and rec.setID > 0) and "SET") or nil
    self.tag:SetText(tag and L(tag) or "")
    Widgets.SetTextColor(self.tag, C.set)
    local width = self:GetWidth() or 300
    self.type:SetWidth(0) -- natural width first
    local typeW = Widgets.TextWidth(self.type)
    local tagW = tag and (Widgets.TextWidth(self.tag) + 6) or 0
    -- room for name + type text; when both do not fit, the type text is shortened (the name keeps at
    -- least half of the room) instead of running over the name
    local space = width - (self.iconButton:GetWidth() + 15) + x - 4 - 10 - tagW
    local nameW = Widgets.TextWidth(self.name) + 2
    local nameFit = math.min(nameW, math.max(space * 0.5, space - typeW))
    if typeW > space - nameFit then
        self.type:SetWidth(math.max(20, space - nameFit))
    end
    self.name:SetWidth(math.max(40, nameFit))

    local wished = Items.IsWishlisted(itemID)
    local star = self.star
    if wished or (self.hovered and LJ.Modules.On("wishlist")) then star = GetStar(self) end
    if star then
        Theme.SetGlyph(star.tex, wished and "star" or "starLine", wished and C.gold or StarLine())
        star.bg:SetColor(1, 1, 1, wished and 0 or 0.08)
        star:SetAlpha(((self.hovered and LJ.Modules.On("wishlist")) or wished) and 1 or 0)
    end
    self.extraTooltip = opts.extraTooltip
end

function Widgets.CreateItemRow(parent, height)
    height = height or Widgets.ItemRowHeight()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 6)
    row.hlRing = Widgets.CreateLazyBox(row, "BACKGROUND", 2, 6, true)

    row.iconButton = Widgets.CreateItemIcon(row, height - 6)
    row.iconButton:SetPoint("LEFT", 6, 0)
    row.iconButton:EnableMouse(false)

    row.name = Widgets.Text(row, "item", C.text1)
    row.name:SetPoint("LEFT", row.iconButton, "RIGHT", 9, 0)
    row.tag = Widgets.Text(row, "pill", C.set)
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 5, 0)

    -- right cluster (right to left): star (GetStar), chance pill, badges (GetBadge), type text
    row.chancePill = Widgets.CreatePill(row, 19, "count")
    row.chancePill:SetPoint("RIGHT", row, "RIGHT", -32, 0)   -- left of the star (20 wide, 6 from the edge) + 6
    row.chance = row.chancePill.text
    row.badges = {}
    row.type = Widgets.Text(row, "smallSemi", C.text3, nil, "RIGHT")

    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)
    row.SetItem = ItemRowSetItem
    return row
end

---------------------------------------------------------------------------
-- Boss emblem: round portrait (creature display) or an emblem glyph, accent ring and glow
---------------------------------------------------------------------------
function Widgets.CreateEmblem(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.glow:SetTexture(TEX.glow)
    f.glow:SetPoint("TOPLEFT", -size * 0.35, size * 0.35)
    f.glow:SetPoint("BOTTOMRIGHT", size * 0.35, -size * 0.35)
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.bg:SetTexture(TEX.circle)
    f.bg:SetAllPoints()
    f.bg:SetVertexColor(0.1, 0.12, 0.15, 1)
    f.bgLight = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.bgLight:SetTexture(TEX.glow)
    f.bgLight:SetPoint("TOPLEFT", size * 0.08, -size * 0.02)
    f.bgLight:SetPoint("BOTTOMRIGHT", -size * 0.08, size * 0.16)
    f.bgLight:SetVertexColor(1, 1, 1, 0.08)
    f.portrait = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.portrait:SetPoint("TOPLEFT", 2, -2)
    f.portrait:SetPoint("BOTTOMRIGHT", -2, 2)
    f.mask = f:CreateMaskTexture()
    f.mask:SetTexture(TEX.maskCircle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.mask:SetAllPoints(f.portrait)
    f.portrait:AddMaskTexture(f.mask)
    f.glyph = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.glyph:SetSize(size * 0.6, size * 0.6)
    f.glyph:SetPoint("CENTER", 0, 0)
    f.glyph:SetVertexColor(0.91, 0.89, 0.84, 1)
    f.ring = f:CreateTexture(nil, "OVERLAY", nil, 0)
    f.ring:SetTexture(size >= 34 and TEX.circleRing or TEX.circleRingThin)
    f.ring:SetAllPoints()
    f.rare = false
    if Theme.IsClassic() then
        -- gold portrait ring of the classic look
        f.classic = true
        f.ring:SetTexture(TEX.classicRing)
        f.ring:ClearAllPoints()
        f.ring:SetPoint("TOPLEFT", -1, 1)
        f.ring:SetPoint("BOTTOMRIGHT", 1, -1)
        f.bg:SetVertexColor(0.03, 0.03, 0.03, 1)
        f.glyph:SetVertexColor(0.9, 0.8, 0.55, 1)
    end

    local function Colors(self, r, g, b)
        if self.classic then
            self.ring:SetVertexColor(self.rare and 0.82 or 1, self.rare and 0.84 or 1, self.rare and 0.9 or 1, 1)
            return
        end
        if self.rare then
            self.ring:SetVertexColor(0.8, 0.82, 0.86, 1)
            self.glow:SetVertexColor(0.86, 0.88, 0.92, 0.22)
        else
            self.ring:SetVertexColor(r, g, b, 0.8)
            self.glow:SetVertexColor(r, g, b, 0.26)
        end
    end
    Theme.OnAccent(f, Colors)

    function f:SetGlyph(name)
        self.portrait:Hide()
        self.glyph:Show()
        Theme.SetEmblem(self.glyph, name)
    end
    function f:SetRare(v)
        self.rare = v and true or false
        Colors(self, Theme.accent[1], Theme.accent[2], Theme.accent[3])
    end
    -- a creature's face (its display ID); without one, the symbol
    function f:SetCreature(display, glyph)
        if display then
            self.glyph:Hide()
            self.portrait:Show()
            SetPortraitTextureFromCreatureDisplayID(self.portrait, display)
            return
        end
        self:SetGlyph(glyph)
    end
    function f:SetBoss(boss)
        self:SetRare(boss and boss.rare)
        self:SetCreature(boss and boss.display, Theme.BossEmblem(boss))
    end
    return f
end

---------------------------------------------------------------------------
-- Card: rounded panel with a soft horizontal gradient
---------------------------------------------------------------------------
function Widgets.StyleCard(frame, radius)
    frame.card = Widgets.CreatePanel(frame, radius or 10, "BACKGROUND", -4)
    frame.card:SetGradient("HORIZONTAL", { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.025 })
    frame.card:SetBorder(1, 1, 1, 0.06)
    return frame.card
end

---------------------------------------------------------------------------
-- Empty state: glyph in a glowing accent circle, headline, text and an optional button
---------------------------------------------------------------------------
function Widgets.CreateEmptyState(parent, glyph, width)
    width = width or 400
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 200)
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.glow:SetTexture(TEX.glow)
    f.glow:SetSize(220, 220)
    f.circle = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.circle:SetTexture(TEX.circle)
    f.circle:SetSize(64, 64)
    f.circle:SetPoint("TOP", 0, 0)
    f.glow:SetPoint("CENTER", f.circle, "CENTER")
    f.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.ring:SetTexture(TEX.circleRing)
    f.ring:SetAllPoints(f.circle)
    f.icon = Widgets.Glyph(f, glyph or "info", 28, C.white, "ARTWORK", 2)
    f.icon:SetPoint("CENTER", f.circle, "CENTER")
    f.title = Widgets.Text(f, "h2", C.text1, nil, "CENTER")
    f.title:SetPoint("TOP", f.circle, "BOTTOM", 0, -16)
    f.text = Widgets.Text(f, "bodySmall", C.text3, nil, "CENTER")
    f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -7)
    f.text:SetWidth(width)
    f.text:SetWordWrap(true)
    f.text:SetSpacing(3)
    f.button = Widgets.CreateButton(f, "", "primary", nil, nil, 30)
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -18)
    f.button:Hide()
    Theme.OnAccent(f, function(s, r, g, b)
        s.glow:SetVertexColor(r, g, b, 0.16)
        s.circle:SetVertexColor(r, g, b, 0.12)
        s.ring:SetVertexColor(r, g, b, 0.5)
        s.icon:SetVertexColor(r, g, b, 1)
    end)
    -- title, text, glyph (nil = keep), button label + onClick + glyph (nil label = no button)
    function f:Set(title, text, glyphName, buttonText, onClick, buttonGlyph)
        self.title:SetText(title or "")
        self.text:SetText(text or "")
        if glyphName then Theme.SetGlyph(self.icon, glyphName) end
        local a = Theme.accent
        self.icon:SetVertexColor(a[1], a[2], a[3], 1)
        if buttonText then
            self.button:SetGlyph(buttonGlyph)
            self.button:SetLabel(buttonText)
            self.button:SetScript("OnClick", onClick)
            self.button:Show()
        else
            self.button:Hide()
        end
    end
    return f
end

---------------------------------------------------------------------------
-- Progress: bar and segmented ring
---------------------------------------------------------------------------
function Widgets.CreateProgressBar(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 5)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture(Theme.RoundFile(4))
    f.bg:SetAllPoints()
    f.bg:SetVertexColor(1, 1, 1, 0.1)
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetTexture(Theme.RoundFile(4))
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.fill:SetWidth(1)
    f.color = nil
    function f:SetProgress(p, color)
        p = math.max(0, math.min(1, p or 0))
        self.value = p
        local w = (self:GetWidth() or 0) * p
        self.fill:SetShown(w >= 1)
        self.fill:SetWidth(math.max(1, w))
        self.color = color
        local c = color or Theme.accent
        self.fill:SetVertexColor(c[1], c[2], c[3], 1)
    end
    f:SetScript("OnSizeChanged", function(self) self:SetProgress(self.value or 0, self.color) end)
    Theme.OnAccent(f, function(self)
        if not self.color then self:SetProgress(self.value or 0) end
    end)
    return f
end

---------------------------------------------------------------------------
-- Character chip (bottom of a sidebar): class avatar, name, level, spec
---------------------------------------------------------------------------
function Widgets.CreateCharacterChip(parent, onSettings)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(46)
    f.bg = Widgets.Solid(f, "BACKGROUND", 0, { 0, 0, 0 }, 0.18)
    f.bg:SetAllPoints()
    f.line = Widgets.Line(f, "BORDER", 0.06)
    f.line:SetHeight(1)
    f.line:SetPoint("TOPLEFT")
    f.line:SetPoint("TOPRIGHT")
    f.avatar = f:CreateTexture(nil, "ARTWORK")
    f.avatar:SetSize(28, 28)
    f.avatar:SetPoint("LEFT", 12, 0)
    f.avatarMask = f:CreateMaskTexture()
    f.avatarMask:SetTexture(TEX.maskCircle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.avatarMask:SetAllPoints(f.avatar)
    f.avatar:AddMaskTexture(f.avatarMask)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(TEX.circleRingThin)
    f.ring:SetPoint("TOPLEFT", f.avatar, "TOPLEFT", -2, 2)
    f.ring:SetPoint("BOTTOMRIGHT", f.avatar, "BOTTOMRIGHT", 2, -2)
    if Theme.IsClassic() then
        f.classic = true
        f.ring:SetTexture(TEX.classicRing)
        f.ring:ClearAllPoints()
        f.ring:SetPoint("TOPLEFT", f.avatar, "TOPLEFT", -4, 4)
        f.ring:SetPoint("BOTTOMRIGHT", f.avatar, "BOTTOMRIGHT", 4, -4)
    end
    -- the name and below it the level and the spec (the avatar shows the class), on two lines where one is not wide
    -- enough (German, Russian): the name moves up with them, both stay centered beside the avatar
    f.name = Widgets.Text(f, "nameBold", C.text1)
    f.sub = Widgets.Text(f, "small", C.text3)
    f.sub:SetWordWrap(true)
    f.sub:SetMaxLines(2)
    f.sub:SetPoint("LEFT", f.avatar, "RIGHT", 9, -8)
    f.name:SetPoint("BOTTOMLEFT", f.sub, "TOPLEFT", 0, 4)
    f.gear = Widgets.CreateButton(f, nil, "ghost", "gear", 26, 22)
    f.gear:SetPoint("RIGHT", -10, 0)
    Widgets.SetTooltip(f.gear, "Settings", nil, "ANCHOR_TOP")
    f.gear:SetScript("OnClick", function(b) if onSettings then onSettings(b) end end)
    f.sub:SetPoint("RIGHT", f.gear, "LEFT", -6, -8)
    f.name:SetPoint("RIGHT", f.gear, "LEFT", -6, 0)
    function f:Update()
        local P = LJ.Player
        local class = P.class or "WARRIOR"
        Util.SetClassIcon(self.avatar, class)
        local r, g, b = Util.ClassColor(class)
        if self.classic then r, g, b = 1, 1, 1 end
        self.ring:SetVertexColor(r, g, b, 0.95)
        self.name:SetText(UnitName("player"))
        local spec = P:GetActiveSpec()
        self.sub:SetText(F("Level %d", P.level or 1) .. (spec and (" · " .. L(spec.name)) or ""))
    end
    return f
end

---------------------------------------------------------------------------
-- Sidebar pane (left column of every page): darker glass, rounded bottom-left corner, hairline
---------------------------------------------------------------------------
function Widgets.CreateSidebar(root, width)
    local side = CreateFrame("Frame", nil, root)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(width or 244)
    side.bg = Widgets.CreateBox(side, "BACKGROUND", -6, 12)
    side.bg:SetSquareCorners(true, true, false, true)
    side.bg:SetGradient("HORIZONTAL", { 0, 0, 0, 0.16 }, { 0, 0, 0, 0.08 })
    side.line = Widgets.Line(side, "BORDER", 0.06)
    side.line:SetWidth(1)
    side.line:SetPoint("TOPRIGHT")
    side.line:SetPoint("BOTTOMRIGHT")
    return side
end

-- Group header of a sidebar list: label, count, collapse caret.
function Widgets.CreateGroupHeader(parent)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(26)
    h.caret = Widgets.Glyph(h, "caretDown", 10, C.text5)
    h.caret:SetPoint("LEFT", 8, -2)
    h.text = Widgets.Text(h, "label", C.text4)
    h.text:SetPoint("LEFT", h.caret, "RIGHT", 4, 0)
    if Theme.IsClassic() then
        -- Classic quest-log header: plus / minus button and gold text
        h.classic = true
        h.caret:SetSize(14, 14)
        h.caret:SetTexCoord(0, 1, 0, 1)
        h.caret:ClearAllPoints()
        h.caret:SetPoint("LEFT", 6, -1)
        h.text:ClearAllPoints()
        h.text:SetPoint("LEFT", h.caret, "RIGHT", 5, 0)
        h.caretHL = h:CreateTexture(nil, "ARTWORK", nil, 1)
        h.caretHL:SetTexture(Theme.CLASSIC.plusHighlight)
        h.caretHL:SetBlendMode("ADD")
        h.caretHL:SetAllPoints(h.caret)
        h.caretHL:Hide()
    end
    h.count = Widgets.Text(h, "label", C.text5, nil, "RIGHT")
    h.count:SetPoint("RIGHT", -10, -2)
    h:SetScript("OnEnter", function(self)
        Widgets.SetTextColor(self.text, self.classic and C.white or C.text2)
        if self.caretHL then self.caretHL:Show() end
    end)
    h:SetScript("OnLeave", function(self)
        Widgets.SetTextColor(self.text, C.text4)
        if self.caretHL then self.caretHL:Hide() end
    end)
    function h:Set(text, count, collapsed)
        self.text:SetText(Theme.Case(text or ""))
        self.count:SetText(count and tostring(count) or "")
        self.collapsed = collapsed and true or false
        if self.classic then
            self.caret:SetTexture(collapsed and Theme.CLASSIC.plus or Theme.CLASSIC.minus)
            self.caret:SetTexCoord(0, 1, 0, 1)
            self.caret:SetVertexColor(1, 1, 1, 1)
        else
            Theme.SetGlyph(self.caret, collapsed and "caretRight" or "caretDown", C.text5)
        end
    end
    return h
end
