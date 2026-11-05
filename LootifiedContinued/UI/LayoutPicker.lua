-- Lootified - the layout picker: on the first start the player picks one of the three looks (Modern, Classic,
-- Database) from cards with a small preview of each, then how items are rated (UI/RatingPicker.lua); later it opens
-- from the options or with /lf look. It draws the previews with fixed colors and its own fonts, so it looks the same
-- whatever look is active.
local _, LJ = ...
local L = LJ.L

local UI = LJ.UI
local Theme = LJ.Theme
local Util = LJ.Util

local Picker = {}
UI.LayoutPicker = Picker

local CARD_W, CARD_H = 240, 290
local PREVIEW_W, PREVIEW_H = 220, 138
local GAP, PAD = 14, 24
local WHITE = Util.WHITE
local hex = Theme.hex

---------------------------------------------------------------------------
-- Drawing helpers (fixed colors: the previews show every look at once)
---------------------------------------------------------------------------
local fonts = {}
local function Font(file, size)
    local key = file .. size
    if not fonts[key] then
        local f = CreateFont("LootifiedPickerFont" .. (#fonts + 1) .. "_" .. math.floor(size * 10))
        f:SetFont(Theme.FontFile(file), size, "")
        f:SetShadowOffset(0, 0)
        fonts[key] = f
        fonts[#fonts + 1] = f
    end
    return fonts[key]
end

-- a flat rectangle at x, y (from the top left of parent)
local function Rect(parent, x, y, w, h, c, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    t:SetPoint("TOPLEFT", x, -y)
    t:SetSize(w, h)
    return t
end

local function Text(parent, x, y, text, file, size, c, justify)
    local fs = Theme.PrepareFontString(parent:CreateFontString(nil, "OVERLAY"))
    fs:SetFontObject(Font(file, size))
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", x, -y)
    fs:SetText(text)
    return fs
end

-- the art of the Deadmines in a rectangle (the game's journal or loading screen art)
local function Art(parent, x, y, w, h, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetPoint("TOPLEFT", x, -y)
    t:SetSize(w, h)
    Theme.SetInstanceArt(t, LJ.instanceByKey.DM, w / h)
    return t
end

-- icons of the preview rows (Deadmines drops: Miner's Cape, Cruel Barb, Blackened Defias Armor)
local ICON_ITEMS = { 5444, 5191, 10399 }

local function Icon(parent, x, y, size, quality)
    local q = { hex("1EFF00"), hex("0070DD"), hex("A335EE") }
    Rect(parent, x - 1, y - 1, size + 2, size + 2, q[quality])
    local t = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    t:SetTexture(select(5, C_Item.GetItemInfoInstant(ICON_ITEMS[quality])))
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t:SetPoint("TOPLEFT", x, -y)
    t:SetSize(size, size)
    return t
end

---------------------------------------------------------------------------
-- The three previews: a small window of each look with the Deadmines open
---------------------------------------------------------------------------
local PREVIEWS = {}

function PREVIEWS.modern(f, w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetGradient("VERTICAL", CreateColor(0.047, 0.055, 0.075, 1), CreateColor(0.082, 0.098, 0.13, 1))
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetTexture(Theme.UI .. "Glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.91, 0.69, 0.29, 0.18)
    glow:SetSize(200, 140)
    glow:SetPoint("CENTER", f, "TOPLEFT", 30, 0)
    local accent = hex("E8B04B")
    -- top bar
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LJ.MEDIA .. "Logo64")
    logo:SetSize(10, 10)
    logo:SetPoint("TOPLEFT", 6, -5)
    Text(f, 19, 5, "LOOT|cffe8b04bIFIED|r", "cBlack", 8.5, { 1, 1, 1 })
    for i, wd in ipairs({ 20, 26, 30, 24 }) do
        Rect(f, 60 + (i - 1) * 36, 8, wd, 3, i == 2 and { 1, 1, 1, 0.9 } or { 0.6, 0.64, 0.68, 0.7 })
    end
    Rect(f, 96, 13, 26, 1.5, accent)
    Rect(f, 0, 20, w, 1, { 1, 1, 1, 0.07 })
    -- list
    Rect(f, 0, 21, 52, h - 21, { 0, 0, 0, 0.18 }, "BACKGROUND", 2)
    for i = 1, 6 do
        local y = 27 + (i - 1) * 17
        if i == 2 then
            local sel = Rect(f, 3, y - 3, 46, 13, accent, "BACKGROUND", 3)
            sel:SetGradient("HORIZONTAL", CreateColor(accent[1], accent[2], accent[3], 0.3), CreateColor(accent[1], accent[2], accent[3], 0))
            Rect(f, 3, y - 1, 1.5, 9, accent)
        end
        Rect(f, 8, y + 2, 26 + (i % 3) * 4, 3, { 0.85, 0.86, 0.88, i == 2 and 1 or 0.55 })
    end
    -- banner with the dungeon art
    Art(f, 53, 21, w - 53, 46, "BACKGROUND")
    local fade = Rect(f, 53, 21, w - 53, 46, { 0.05, 0.06, 0.08 }, "BACKGROUND", 3)
    fade:SetGradient("HORIZONTAL", CreateColor(0.05, 0.06, 0.08, 0.95), CreateColor(0.05, 0.06, 0.08, 0.1))
    Text(f, 60, 30, Util.Upper(LJ.instanceByKey.DM.name), "cBlack", 13, { 1, 1, 1 })
    Text(f, 60, 46, LJ.instanceByKey.DM.zone, "medium", 7.5, { 0.76, 0.78, 0.82 })
    -- loot rows
    local names = { { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } }
    for i = 1, 3 do
        local y = 76 + (i - 1) * 19
        local row = Rect(f, 58, y - 2, w - 64, 16, { 1, 1, 1, 0.035 })
        row:SetDrawLayer("BACKGROUND", 4)
        Icon(f, 61, y, 12, i)
        Rect(f, 78, y + 4, 52 + i * 6, 3.5, names[i])
        Rect(f, w - 32, y + 2, 22, 8, { 1, 1, 1, 0.08 })
    end
end

-- Classic: the dark leather window with its title bar and the row of page buttons (Journal red), the brown panel with
-- the dungeon's header (its picture fading in), the bosses on the left (the picked one crimson) and their loot.
function PREVIEWS.classic(f, w, h)
    local dm = LJ.instanceByKey.DM
    local Hh = Theme.HEARTH
    local function Box(x, y, bw, bh, top, bottom, border, layer, sublevel)
        local fill = Rect(f, x, y, bw, bh, top, layer or "BACKGROUND", sublevel or 1)
        fill:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
        if border then
            for _, e in ipairs({ { x, y, bw, 1 }, { x, y + bh - 1, bw, 1 }, { x, y, 1, bh }, { x + bw - 1, y, 1, bh } }) do
                Rect(f, e[1], e[2], e[3], e[4], border, layer or "BACKGROUND", (sublevel or 1) + 1)
            end
        end
        return fill
    end
    Box(0, 0, w, h, Hh.windowTop, Hh.windowBottom, Hh.windowBorder, "BACKGROUND", 0)
    -- title bar: the character, the name, options and close
    local title = Text(f, 0, 3, LJ.TITLE, "friz", 7.5, Hh.title, "CENTER")
    title:SetWidth(w)
    Rect(f, 6, 5, 34, 2.5, { 0.56, 0.52, 0.45, 0.8 })
    local close = f:CreateTexture(nil, "ARTWORK")
    close:SetTexture(Theme.TEX.circle)
    close:SetVertexColor(0.62, 0.12, 0.08, 1)
    close:SetSize(7, 7)
    close:SetPoint("TOPRIGHT", -4, -3)
    Rect(f, 1, 12, w - 2, 1, { Hh.line[1], Hh.line[2], Hh.line[3], 0.18 })
    -- the page buttons (Journal picked) and the search box
    local x = 5
    for i, bw in ipairs({ 22, 24, 28, 26, 23 }) do
        if i == 2 then
            Box(x, 16, bw, 8, Hh.redTop, Hh.redBottom, Hh.redBorder, "ARTWORK", 0)
        else
            Box(x, 16, bw, 8, Hh.buttonTop, Hh.buttonBottom, Hh.buttonBorder, "ARTWORK", 0)
        end
        x = x + bw + 2
    end
    Box(w - 52, 16, 47, 8, { 0.04, 0.03, 0.02 }, { 0.04, 0.03, 0.02 }, Hh.inputBorder, "ARTWORK", 0)
    -- the brown panel
    local mx, my, mw, mh = 4, 28, w - 8, h - 32
    Box(mx, my, mw, mh, Hh.mainTop, Hh.mainBottom, Hh.mainBorder, "BACKGROUND", 2)
    -- the dungeon's header: its picture fading in from the left, the name, the buttons
    Box(mx + 4, my + 4, mw - 8, 22, Hh.panelTop, Hh.panelBottom, Hh.panelBorder, "BACKGROUND", 5)
    local art = Art(f, mx + 4 + math.floor((mw - 8) * 0.4), my + 5, math.floor((mw - 8) * 0.6) - 1, 20, "BORDER")
    art:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.95))
    Text(f, mx + 9, my + 8, dm.name, "friz", 8, Hh.title)
    Rect(f, mx + 9, my + 19, 44, 2, { 0.66, 0.62, 0.52, 0.8 })
    for i = 1, 3 do
        local bx = mx + mw - 58 + (i - 1) * 17
        if i == 1 then
            Box(bx, my + 11, 15, 7, Hh.redTop, Hh.redBottom, Hh.redBorder, "ARTWORK", 3)
        else
            Box(bx, my + 11, 15, 7, Hh.buttonTop, Hh.buttonBottom, Hh.buttonBorder, "ARTWORK", 3)
        end
    end
    -- left: the bosses, the second one picked
    local lx, ly, lw = mx + 4, my + 30, 62
    Box(lx, ly, lw, mh - 34, Hh.panelTop, Hh.panelBottom, Hh.panelBorder, "BACKGROUND", 5)
    for i = 1, 5 do
        local y = ly + 4 + (i - 1) * 13
        if i == 2 then
            Box(lx + 3, y, lw - 6, 11, Hh.pickTop, Hh.pickBottom, Hh.pickBorder, "BORDER", 0)
        else
            Box(lx + 3, y, lw - 6, 11, Hh.rowTop, Hh.rowBottom, Hh.rowBorder, "BORDER", 0)
        end
        local dot = f:CreateTexture(nil, "ARTWORK", nil, 3)
        dot:SetTexture(Theme.TEX.circle)
        dot:SetVertexColor(0.32, 0.22, 0.14, 1)
        dot:SetSize(7, 7)
        dot:SetPoint("TOPLEFT", lx + 5, -(y + 2))
        local ring = f:CreateTexture(nil, "ARTWORK", nil, 4)
        ring:SetTexture(Theme.TEX.classicRing)
        ring:SetSize(9, 9)
        ring:SetPoint("CENTER", dot, "CENTER")
        local c = i == 2 and Hh.redText or { 0.86, 0.81, 0.7 }
        Rect(f, lx + 15, y + 4, 22 + (i % 3) * 5, 2.5, c, "ARTWORK", 3)
    end
    -- right: the boss and its loot
    local rx, rw = lx + lw + 4, mx + mw - 4 - (lx + lw + 4)
    Box(rx, ly, rw, mh - 34, Hh.panelTop, Hh.panelBottom, Hh.panelBorder, "BACKGROUND", 5)
    local boss = f:CreateTexture(nil, "ARTWORK", nil, 1)
    boss:SetTexture(Theme.TEX.circle)
    boss:SetVertexColor(0.32, 0.22, 0.14, 1)
    boss:SetSize(11, 11)
    boss:SetPoint("TOPLEFT", rx + 5, -(ly + 4))
    Rect(f, rx + 20, ly + 6, 40, 3, { 0.95, 0.92, 0.86 }, "ARTWORK", 1)
    Rect(f, rx + 20, ly + 11, 30, 2, { 0.5, 0.48, 0.42 }, "ARTWORK", 1)
    local names = { hex("1EFF00"), hex("2A8CFF"), hex("B55CFF") }
    for i = 1, 3 do
        local y = ly + 19 + (i - 1) * 14
        Box(rx + 4, y, rw - 8, 12, Hh.rowTop, Hh.rowBottom, Hh.rowBorder, "BORDER", 0)
        Icon(f, rx + 6, y + 2, 8, i)
        Rect(f, rx + 18, y + 3, 26 + i * 6, 2.5, names[i], "ARTWORK", 3)
        Rect(f, rx + 18, y + 7, 18, 1.5, { 0.6, 0.56, 0.48 }, "ARTWORK", 3)
        Rect(f, rx + rw - 18, y + 5, 9, 2, { 0.86, 0.81, 0.7 }, "ARTWORK", 3)
    end
end

-- Database: the glass window with the four tabs (Items picked, ice blue), the search bar, the filters on the left, the
-- table of items in the middle and the picked item's card on the right.
function PREVIEWS.database(f, w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetGradient("VERTICAL", CreateColor(0.043, 0.051, 0.071, 1), CreateColor(0.086, 0.106, 0.141, 1))
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetTexture(Theme.UI .. "Glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.36, 0.78, 1, 0.16)
    glow:SetSize(200, 140)
    glow:SetPoint("CENTER", f, "TOPLEFT", 30, 0)
    local accent = hex("5BC8FF")
    local panel = { 1, 1, 1, 0.035 }
    -- top bar: logo, LOOTIFIED DATABASE, the tabs (Items picked)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LJ.MEDIA .. "Logo64")
    logo:SetSize(10, 10)
    logo:SetPoint("TOPLEFT", 6, -5)
    Text(f, 19, 5, "LOOTIFIED", "cBlack", 8.5, { 1, 1, 1 })
    Rect(f, 62, 8.5, 22, 2.5, accent)
    for i, wd in ipairs({ 18, 18, 22, 22 }) do
        Rect(f, 96 + (i - 1) * 28, 8, wd, 3, i == 1 and { 1, 1, 1, 0.95 } or { 0.6, 0.64, 0.68, 0.7 })
    end
    Rect(f, 94, 14, 22, 1.5, accent)
    Rect(f, 0, 20, w, 1, { 1, 1, 1, 0.07 })
    -- the search bar with its scope chip, the sort at the right
    Rect(f, 5, 25, 108, 10, { 0, 0, 0, 0.4 })
    Rect(f, 15, 27.5, 16, 5, { accent[1], accent[2], accent[3], 0.35 })
    Rect(f, 35, 29, 30, 2, { 1, 1, 1, 0.7 })
    Rect(f, w - 36, 26, 31, 8, { 1, 1, 1, 0.06 })
    -- filters: chips and check boxes
    Rect(f, 5, 40, 44, h - 45, panel)
    for r = 1, 3 do
        for c = 1, 2 do
            local on = r == 2 and c == 2
            Rect(f, 8 + (c - 1) * 19, 44 + (r - 1) * 9, 16, 6, on and { accent[1], accent[2], accent[3], 0.45 } or { 1, 1, 1, 0.1 })
        end
    end
    local q = { { 0.9, 0.9, 0.88 }, { 0.12, 1, 0 }, { 0.29, 0.61, 1 }, { 0.71, 0.36, 1 } }
    for i = 1, 4 do
        local y = 76 + (i - 1) * 8
        Rect(f, 8, y, 5, 5, (i == 2 or i == 3) and accent or { 1, 1, 1, 0.2 })
        Rect(f, 16, y + 1.5, 3, 3, q[i])
        Rect(f, 22, y + 2, 16, 2, { 0.76, 0.78, 0.82, 0.8 })
    end
    Rect(f, 8, 112, 36, 2, { 1, 1, 1, 0.1 })
    Rect(f, 16, 112, 18, 2, accent)
    -- the table: item rows, the first one picked, the upgrades in green
    local tx, tw = 53, 98
    Rect(f, tx, 40, tw, h - 45, panel)
    for i = 1, 6 do
        local y = 46 + (i - 1) * 14.5
        if i == 1 then
            local sel = Rect(f, tx + 2, y - 2, tw - 4, 13, accent, "BACKGROUND", 3)
            sel:SetGradient("HORIZONTAL", CreateColor(accent[1], accent[2], accent[3], 0.28), CreateColor(accent[1], accent[2], accent[3], 0.05))
            Rect(f, tx + 1, y, 1.5, 9, accent)
        end
        Icon(f, tx + 5, y, 9, (i % 3) + 1)
        Rect(f, tx + 18, y + 1, 30 + (i % 3) * 5, 2.5, q[(i % 3) + 2])
        Rect(f, tx + 18, y + 6, 22, 1.5, { 0.55, 0.58, 0.63, 0.8 })
        if i <= 4 then Rect(f, tx + tw - 18, y + 2, 14, 5, { 0.34, 0.89, 0.54, 0.5 }) end
    end
    -- the picked item's card: icon in its glow, name, stats, the wishlist button
    local dx = tx + tw + 4
    local dw = w - dx - 5
    Rect(f, dx, 40, dw, h - 45, panel)
    local cardGlow = f:CreateTexture(nil, "BORDER")
    cardGlow:SetTexture(Theme.UI .. "Glow")
    cardGlow:SetBlendMode("ADD")
    cardGlow:SetVertexColor(0.29, 0.61, 1, 0.45)
    cardGlow:SetSize(44, 44)
    cardGlow:SetPoint("CENTER", f, "TOPLEFT", dx + 13, -54)
    Icon(f, dx + 6, 47, 14, 2)
    Rect(f, dx + 24, 49, dw - 30, 3, hex("7DB8FF"))
    Rect(f, dx + 24, 55, dw - 38, 2, { 0.68, 0.71, 0.74, 0.8 })
    Rect(f, dx + 4, 68, dw - 8, 24, { 0, 0, 0, 0.3 })
    for i = 1, 3 do Rect(f, dx + 8, 72 + (i - 1) * 6, dw - 22 - i * 3, 2, { 0.9, 0.91, 0.93, 0.75 }) end
    Rect(f, dx + 4, h - 17, dw - 8, 9, accent)
end

---------------------------------------------------------------------------
-- The dialog
---------------------------------------------------------------------------
-- the first start marks no card; opened again, the card of the active look is marked
local function CardVisual(card)
    local current = Picker.reopened and card.look.key == Theme.skin
    local a = hex("E8B04B")
    if card.hovered or current then
        card.ring:SetVertexColor(a[1], a[2], a[3], card.hovered and 1 or 0.7)
    else
        card.ring:SetVertexColor(1, 1, 1, 0.12)
    end
    card.current:SetShown(current)
end

local function Border(parent, c, inset)
    -- 1 unit outline from four textures
    local parts = {}
    inset = inset or 0
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE)
        parts[i] = t
    end
    parts[1]:SetPoint("TOPLEFT", inset, -inset) parts[1]:SetPoint("TOPRIGHT", -inset, -inset) parts[1]:SetHeight(1)
    parts[2]:SetPoint("BOTTOMLEFT", inset, inset) parts[2]:SetPoint("BOTTOMRIGHT", -inset, inset) parts[2]:SetHeight(1)
    parts[3]:SetPoint("TOPLEFT", inset, -inset) parts[3]:SetPoint("BOTTOMLEFT", inset, inset) parts[3]:SetWidth(1)
    parts[4]:SetPoint("TOPRIGHT", -inset, -inset) parts[4]:SetPoint("BOTTOMRIGHT", -inset, inset) parts[4]:SetWidth(1)
    local border = { parts = parts }
    function border:SetVertexColor(r, g, b, alpha)
        for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, alpha) end
    end
    border:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return border
end

local function CreateCard(dialog, look, index)
    local card = CreateFrame("Button", nil, dialog)
    card.look = look
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", PAD + (index - 1) * (CARD_W + GAP), -78)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetVertexColor(1, 1, 1, 0.035)
    card.ring = Border(card, { 1, 1, 1, 0.12 })

    local preview = CreateFrame("Frame", nil, card)
    preview:SetSize(PREVIEW_W, PREVIEW_H)
    preview:SetPoint("TOP", 0, -10)
    preview:SetClipsChildren(true)
    PREVIEWS[look.key](preview, PREVIEW_W, PREVIEW_H)
    Border(preview, { 0, 0, 0, 0.8 })

    card.name = Text(card, 12, PREVIEW_H + 22, L(look.name), "bold", 17, { 1, 1, 1 })
    card.current = Text(card, 0, 0, L("Current look"), "semibold", 11, hex("E8B04B"), "RIGHT")
    card.current:ClearAllPoints()
    card.current:SetPoint("RIGHT", card, "TOPRIGHT", -12, -(PREVIEW_H + 32))
    card.text = Text(card, 12, PREVIEW_H + 48, L(look.text), "medium", 13, { 0.76, 0.78, 0.82 })
    card.text:SetWidth(CARD_W - 24)
    card.text:SetWordWrap(true)
    card.text:SetSpacing(2)
    card.text:SetJustifyV("TOP")

    -- the choose button
    local button = CreateFrame("Button", nil, card)
    button:SetSize(CARD_W - 24, 32)
    button:SetPoint("BOTTOM", 0, 12)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture(WHITE)
    fill:SetAllPoints()
    local a = hex("E8B04B")
    fill:SetVertexColor(a[1], a[2], a[3], 1)
    local label = Theme.PrepareFontString(button:CreateFontString(nil, "OVERLAY"))
    label:SetFontObject(Font("semibold", 14))
    label:SetTextColor(0.05, 0.05, 0.06, 1)
    label:SetPoint("CENTER")
    label:SetText(L("Use this look"))
    button.fill = fill
    card.button = button

    local function Choose()
        Util.PlaySound("IG_MAINMENU_OPTION")
        Picker:Choose(look.key)
    end
    card:SetScript("OnClick", Choose)
    button:SetScript("OnClick", Choose)
    local function Enter() card.hovered = true CardVisual(card) end
    local function Leave() card.hovered = false CardVisual(card) end
    card:SetScript("OnEnter", Enter)
    card:SetScript("OnLeave", Leave)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    return card
end

local function CreateDialog()
    local d = CreateFrame("Frame", "LootifiedLayoutPicker", UIParent)
    d:SetSize(PAD * 2 + 3 * CARD_W + 2 * GAP, 78 + CARD_H + 58)
    d:SetPoint("CENTER", 0, 40)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()
    if not tContains(UISpecialFrames, "LootifiedLayoutPicker") then tinsert(UISpecialFrames, "LootifiedLayoutPicker") end

    -- soft shadow and a dark, neutral panel
    local shadow = LJ.Widgets.CreateShadow(d, 22, 0.8)
    for _, t in ipairs(shadow) do t:SetTexture(Theme.UI .. "Shadow") end
    local bg = d:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetTexture(WHITE)
    bg:SetAllPoints()
    bg:SetVertexColor(0.067, 0.075, 0.094, 0.98)
    Border(d, { 1, 1, 1, 0.12 })

    local logo = d:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LJ.MEDIA .. "Logo64")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", PAD, -20)
    d.title = Text(d, PAD + 40, 18, L("Choose your look"), "bold", 22, { 1, 1, 1 })
    d.sub = Text(d, PAD + 40, 46, "", "medium", 13, { 0.76, 0.78, 0.82 })
    d.footer = Text(d, PAD, 78 + CARD_H + 20, L("You can change it any time in the options (the sliders icon) or with /lf look."),
        "medium", 12, { 0.55, 0.58, 0.63 })

    local close = CreateFrame("Button", nil, d)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.icon = close:CreateTexture(nil, "ARTWORK")
    close.icon:SetSize(16, 16)
    close.icon:SetPoint("CENTER")
    Theme.SetGlyph(close.icon, "close", { 0.62, 0.65, 0.7, 1 })
    close:SetScript("OnEnter", function(b) b.icon:SetVertexColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(b) b.icon:SetVertexColor(0.62, 0.65, 0.7, 1) end)
    close:SetScript("OnClick", function() d:Hide() end)

    d.cards = {}
    for i, look in ipairs(UI.LOOKS) do d.cards[i] = CreateCard(d, look, i) end
    -- closed without a pick: the look stays as it is and the picker does not ask again; how items are rated comes
    -- next while nothing is picked there, then what the player asked for (the window, a page, the tour) opens all the
    -- same
    d:SetScript("OnHide", function()
        -- the whole interface hidden (Alt+Z, a cinematic): the picker comes back with it, nothing is chosen
        if not UIParent:IsShown() then return end
        if Picker.picked then
            Picker.picked = nil
            return
        end
        LJ.db.layoutChosen = true
        local after = Picker.asked and Picker.after
        Picker.after, Picker.asked = nil, nil
        UI.RatingPicker:AskFirst(after)
    end)
    return d
end

-- Shows the picker. after(): runs once the player picked a look (the login ask opens the window with it).
function Picker:Show(after)
    self.dialog = self.dialog or CreateDialog()
    self.after = after
    self.asked = nil
    self.reopened = LJ.db.layoutChosen
    self.dialog.sub:SetText(self.reopened and L("How should the window look?")
        or L("Welcome to Lootified! How should the window look?"))
    for _, card in ipairs(self.dialog.cards) do CardVisual(card) end
    self.dialog:Show()
    self.dialog:Raise()
end

-- The first start: the player picks a look before the window opens. Returns true when the picker showed; open()
-- runs once the picker closes, with a pick or without one.
function Picker:AskFirst(open)
    if LJ.db.layoutChosen then return false end
    self:Show(open)
    self.asked = true
    return true
end

-- A look picked: how items are rated comes next while nothing is picked there (UI/RatingPicker.lua), then after().
function Picker:Choose(key)
    local after = self.after
    self.after, self.asked = nil, nil
    self.picked = true
    LJ.db.layoutChosen = true
    self.dialog:Hide()
    UI:ApplySkin(key)
    UI.RatingPicker:AskFirst(after)
end

function Picker:IsShown()
    return self.dialog and self.dialog:IsShown() or false
end

-- The first login: the picker asks once, a few seconds after the game has loaded (after a fight, when it starts in
-- one). Picking a look opens the window.
local pending = false
function Picker:AskOnLogin()
    if LJ.db.layoutChosen or self:IsShown() then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    self:Show(function() UI:Open("start") end)
end
LJ:Listen("LOGIN", function() C_Timer.After(4, function() Picker:AskOnLogin() end) end)
LJ:On("PLAYER_REGEN_ENABLED", function()
    if pending then
        pending = false
        C_Timer.After(1, function() Picker:AskOnLogin() end)
    end
end)
