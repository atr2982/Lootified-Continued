-- Lootified - design tokens: colors, per-context accent color, fonts, textures, glyphs and instance artwork.
-- Three looks ("skins"): "modern" (dark glass, everything bundled in Media/UI and Media/Fonts), "classic" (warm dark
-- leather with thin bronze lines, gold titles, red buttons and the client's Friz Quadrata font: Theme.HEARTH) and
-- "database" (the modern glass with one ice-blue accent, for the lookup pages of UI/Database/). Only dungeon art, item
-- icons and models always come from the client.
local _, LJ = ...

local Theme = {}
LJ.Theme = Theme

local Util = LJ.Util

Theme.UI = LJ.MEDIA .. "UI\\"
Theme.FONT_DIR = LJ.MEDIA .. "Fonts\\"

---------------------------------------------------------------------------
-- Colors (r, g, b[, a]) 0..1
---------------------------------------------------------------------------
local function hex(s, a)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1 }
end
Theme.hex = hex

Theme.COLORS = {
    text1 = hex("F3F1EC"),      -- titles, names
    text2 = hex("C3C8D0"),      -- body text
    text3 = hex("8B93A0"),      -- secondary
    text4 = hex("6F7885"),      -- labels, muted
    text5 = hex("4F5763"),      -- faint
    white = { 1, 1, 1, 1 },
    dark = hex("0D0F13"),       -- text on accent fills
    winTop = hex("151921", 0.955),
    winBottom = hex("0C0E13", 0.97),
    ok = hex("57E389"),
    okText = hex("6EE7A0"),
    blue = hex("6CB6FF"),
    blueText = hex("7CC0FF"),
    gold = hex("F6C744"),
    goldText = hex("F7CF5A"),
    red = hex("F87171"),
    redText = hex("FF8A8A"),
    bad = hex("E46A6A"),
    gray = hex("8E96A2"),
    chanceHi = hex("78E3A4"),
    chanceMid = hex("F5C469"),
    chanceLo = hex("FF8F8F"),
    set = hex("76D38A"),
    rare = hex("C7A3FF"),       -- the RARE tag of rare spawns
    defaultAccent = hex("E8B04B"),
    -- compatibility names used by core modules
    good = hex("57E389"),
    warn = hex("F5C469"),
    info = hex("6CB6FF"),
    dim = hex("6F7885"),
    soft = hex("8B93A0"),
    text = hex("C3C8D0"),
    title = hex("F3F1EC"),
}
local C = Theme.COLORS

-- The modern values, kept to switch back (Theme.SetSkin changes the tables of Theme.COLORS in place, so every
-- module that holds a color table sees the new values).
local MODERN_COLORS = {}
for key, c in pairs(C) do MODERN_COLORS[key] = { c[1], c[2], c[3], c[4] } end

-- Classic look: warm light text on dark leather brown; the gold of the titles is the accent.
local CLASSIC_COLORS = {
    text1 = hex("F4ECDC"), text2 = hex("DCCFB3"), text3 = hex("A99D85"), text4 = hex("8F8573"), text5 = hex("6B6252"),
    white = hex("FFF7E6"), dark = hex("1C1209"),
    winTop = hex("1E160F"), winBottom = hex("130D08"),
    ok = hex("7ED676"), okText = hex("86E57D"), blue = hex("6CB6FF"), blueText = hex("7CC0FF"),
    gold = hex("F0C24E"), goldText = hex("F3CC5E"), red = hex("E8675C"), redText = hex("F08074"), bad = hex("E46A6A"),
    gray = hex("9C9283"), chanceHi = hex("86E57D"), chanceMid = hex("F0C24E"), chanceLo = hex("F08074"),
    set = hex("86E57D"), rare = hex("B993F2"), defaultAccent = hex("F3C463"),
    good = hex("7ED676"), warn = hex("F0C24E"), info = hex("6CB6FF"), dim = hex("8F8573"), soft = hex("A99D85"),
    text = hex("DCCFB3"), title = hex("F4ECDC"),
}

-- Text on the game's own dark art (drop-down holders, the game's menu, the dungeon art of a banner): Blizzard's
-- gold, white and grey in every look.
Theme.ON_DARK = {
    gold = hex("FFD100"), white = hex("FFFFFF"), text = hex("EDEAE2"), dim = hex("B9B2A2"), faint = hex("80796B"),
}

Theme.SKINS = { "modern", "classic", "database" }
Theme.skin = "modern"
Theme.databaseClassic = false

function Theme.IsClassic()
    return Theme.skin == "classic" or (Theme.skin == "database" and Theme.databaseClassic)
end

function Theme.IsDatabase()
    return Theme.skin == "database"
end

-- The one accent of the database look (ice blue).
Theme.DATABASE_ACCENT = hex("5BC8FF")

-- Upper case in the glass looks (modern, database); the classic look keeps the normal spelling (Friz headings).
function Theme.Case(text)
    if Theme.IsClassic() then return text end
    return LJ.Util.Upper(text)
end

---------------------------------------------------------------------------
-- Classic look: the fills and lines of its window, panels, rows and buttons ("Hearth": dark leather brown, thin
-- bronze lines, crimson for the picked entry, lighter leather with a bronze edge for rows that stand out among others,
-- the red of Blizzard's panel buttons for the active one)
---------------------------------------------------------------------------
Theme.HEARTH = {
    windowTop = hex("1E160F"), windowBottom = hex("130D08"), windowBorder = hex("8A6A3C"), windowInner = hex("D6A05A", 0.2),
    line = hex("D6A05A"),                      -- hairlines (with an alpha)
    mainTop = hex("31231A"), mainBottom = hex("25190F"), mainBorder = hex("7A5E3A"),
    panelTop = hex("1D150D"), panelBottom = hex("160F09"), panelBorder = hex("5A4429"),
    rowTop = hex("2B2117"), rowBottom = hex("231A11"), rowBorder = hex("473824", 0.56),
    rowHoverTop = hex("3A2C1E"), rowHoverBottom = hex("2D2116"), rowHoverBorder = hex("6E5232", 0.8),
    pickTop = hex("7A1D14"), pickBottom = hex("4F100B"), pickBorder = hex("CF9C48"),
    buttonTop = hex("3B2A1B"), buttonBottom = hex("28190F"), buttonBorder = hex("6E5232"), buttonText = hex("E6D5B2"),
    buttonHoverTop = hex("4A3523"), buttonHoverBottom = hex("312015"), buttonHoverBorder = hex("8A6A3C"),
    redTop = hex("A3241A"), redBottom = hex("650F09"), redBorder = hex("D4A24A"), redText = hex("FFE08A"),
    redHoverTop = hex("B72C20"), redHoverBottom = hex("74130C"),
    inputFill = hex("0A0705", 0.9), inputBorder = hex("5E4529"),
    cardBorder = hex("5B4630"), ring = hex("8C6A3A"),
    title = hex("F3C463"), section = hex("ECBF5E"),
    fitGood = hex("3DA23A"), fitSoon = hex("C9A227"), fitLater = hex("CF6B22"),
    shade = hex("090705"),                     -- the dark over the pictures (their texts)
    pickText = hex("FFE08A"),                  -- the text on the picked row
    glyph = hex("C9B07A"),                     -- the symbols in place of a portrait (trash, quest rewards)
    badgeFill = hex("16110C"),                 -- the round level badges of the portraits
    radius = 4,
}

-- Modern look: the same parts as dark glass (the pages it shares with the classic look: For you, the journal, Open
-- World).
Theme.GLASS = {
    panelTop = { 1, 1, 1, 0.035 }, panelBottom = { 1, 1, 1, 0.02 }, panelBorder = { 1, 1, 1, 0.075 },
    rowTop = { 1, 1, 1, 0.035 }, rowBottom = { 1, 1, 1, 0.025 }, rowBorder = { 1, 1, 1, 0.06 },
    rowHoverTop = { 1, 1, 1, 0.07 }, rowHoverBottom = { 1, 1, 1, 0.05 }, rowHoverBorder = { 1, 1, 1, 0.14 },
    pickTop = { 1, 1, 1, 0.09 }, pickBottom = { 1, 1, 1, 0.07 }, pickBorder = { 1, 1, 1, 0.2 },
    windowBorder = { 1, 1, 1, 0.14 }, cardBorder = { 1, 1, 1, 0.1 }, ring = { 1, 1, 1, 0.22 },
    title = hex("F3F1EC"), section = hex("C3C8D0"), line = { 1, 1, 1, 0.18 },
    shade = hex("0A0C10"), badgeFill = hex("0D0F13"), pickText = hex("FFFFFF"), glyph = hex("8B93A0"),
    radius = 10,
}

-- The panels, rows and cards of the active look: the classic or the modern parts (filled in place by Theme.SetSkin,
-- so a module may keep the table).
Theme.PANE = {}

-- An item's name in its quality color for the window (Items.GetColoredName keeps the game's colors for chat).
function Theme.ItemName(itemID)
    local Items = LJ.Items
    local rec = Items.Get(itemID)
    local r, g, b = Util.QualityColor(rec.quality or 1)
    return Util.ColorText(Items.GetName(itemID), r, g, b)
end

-- Names in a list that are not selected: light grey on the glass, the classic look's text color there.
local LIST_NAME_GLASS = hex("D9DCE1")
function Theme.ListNameColor()
    return Theme.IsClassic() and C.text1 or LIST_NAME_GLASS
end

function Theme.ClassColorCode(class)
    local r, g, b = Util.ClassColor(class)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function Theme.Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

function Theme.ColorText(text, c)
    return Theme.Hex(c) .. tostring(text) .. "|r"
end

-- Per-instance accent colors, taken from each dungeon's artwork.
Theme.ACCENTS = {
    RFC = "FF6A3D", HOT = "F5A447", ROL = "58D6A7", DM = "F0A04B", WC = "5BD68A", SFK = "9D7BFF", BFD = "3FA7FF",
    STOCKS = "D98A4A", EXC = "C8B26B", DAL = "B58CFF", GNOMER = "5CE1E6", RFK = "B7C95A", SMGY = "FF5A5F",
    SMLIB = "FF5A5F", DROWNED = "39C6E6", SMARM = "FF5A5F", RFD = "B9A1E6", SMCATH = "FF5A5F", KROLDOK = "E2553F",
    ULDA = "E9C36A", ZF = "FFB547", MARA = "B77BFF", ALCAZ = "7FB0FF", ST = "3FD19A", BRD = "FF7A2E",
    DME = "58C7FF", LBRS = "FF5A36", BLACKMAW = "9BD35A", DMW = "58C7FF", DMN = "58C7FF", SCHOLO = "8BE35B",
    STRATLIVE = "FF6B4A", STRATUD = "E0567A", SHAPER = "6FA8FF", UBRS = "FF5A36", ONY = "FF6A3D",
    BARROW = "7EE0A8", HYJAL = "7BD8FF",
}

function Theme.InstanceAccent(inst)
    local h = inst and Theme.ACCENTS[inst.key]
    if h then return hex(h) end
    return C.defaultAccent
end

function Theme.ClassAccent(class)
    local r, g, b = Util.ClassColor(class)
    -- very dark class colors (shaman blue) get lifted so text on them stays readable
    local lum = 0.3 * r + 0.59 * g + 0.11 * b
    if lum < 0.45 then
        local k = 0.45 / math.max(lum, 0.05)
        r, g, b = math.min(1, r * k + 0.08), math.min(1, g * k + 0.08), math.min(1, b * k + 0.08)
    end
    return { r, g, b, 1 }
end

---------------------------------------------------------------------------
-- Accent color of the current page (smoothly animated when it changes)
---------------------------------------------------------------------------
Theme.accent = { C.defaultAccent[1], C.defaultAccent[2], C.defaultAccent[3] }
local accentListeners = setmetatable({}, { __mode = "k" })

-- visibleOnly: skip hidden frames (the in-between steps of the animation); the last step updates everything.
local function Broadcast(visibleOnly)
    local r, g, b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
    for obj, fn in pairs(accentListeners) do
        if not (visibleOnly and obj.IsVisible and not obj:IsVisible()) then
            LJ:SafeCall(fn, obj, r, g, b)
        end
    end
end

function Theme.CountAccentListeners()
    local n = 0
    for _ in pairs(accentListeners) do n = n + 1 end
    return n
end

-- fn(obj, r, g, b) is called now and whenever the accent changes (weak reference to obj).
function Theme.OnAccent(obj, fn)
    accentListeners[obj] = fn
    fn(obj, Theme.accent[1], Theme.accent[2], Theme.accent[3])
end

local accentFrom, accentTo, accentT
local accentDriver = CreateFrame("Frame")
accentDriver:Hide()
accentDriver:SetScript("OnUpdate", function(self, elapsed)
    accentT = accentT + elapsed / 0.3
    local p = math.min(1, accentT)
    p = 1 - (1 - p) * (1 - p)
    for i = 1, 3 do Theme.accent[i] = accentFrom[i] + (accentTo[i] - accentFrom[i]) * p end
    Broadcast(accentT < 1)
    if accentT >= 1 then self:Hide() end
end)

local function Close(x, y)
    return math.abs(x[1] - y[1]) + math.abs(x[2] - y[2]) + math.abs(x[3] - y[3]) < 0.004
end

-- Layout colors to choose from in the options (name, hex).
Theme.ACCENT_PRESETS = {
    { "Gold", "E8B04B" }, { "Amber", "F5A447" }, { "Ember", "FF6A3D" }, { "Crimson", "FF5A5F" },
    { "Rose", "E0567A" }, { "Violet", "9D7BFF" }, { "Blue", "3FA7FF" }, { "Ice", "7BD8FF" },
    { "Teal", "5CE1E6" }, { "Jade", "58D6A7" }, { "Lime", "8BE35B" }, { "Silver", "C3C8D0" },
}

local function ValidHex(h)
    return type(h) == "string" and h:match("^%x%x%x%x%x%x$") ~= nil
end

function Theme.ColorToHex(r, g, b)
    local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("%02X%02X%02X", c(r), c(g), c(b))
end

-- The layout color the user chose in the options, or nil for "automatic" (the page decides).
function Theme.UserAccent()
    local s = LJ.db and LJ.db.accent
    if not s or s.mode == "auto" then return nil end
    if s.mode == "class" then
        return Theme.ClassAccent(LJ.Player and LJ.Player.class or select(2, UnitClass("player")))
    end
    if s.mode == "fixed" and ValidHex(s.color) then return hex(s.color) end
    return nil
end

-- Name of the current layout color setting, for the options menu.
function Theme.UserAccentName()
    local s = LJ.db and LJ.db.accent or {}
    if s.mode == "class" then return "Class color" end
    if s.mode == "fixed" and ValidHex(s.color) then
        for _, p in ipairs(Theme.ACCENT_PRESETS) do
            if p[2] == s.color:upper() then return p[1] end
        end
        return "Custom"
    end
    return "Automatic"
end

Theme.pageAccent = C.defaultAccent   -- color the current page asks for (used in "automatic" mode)

-- The accent outside the window (pins on the game's world map).
function Theme.BrightAccent()
    return { Theme.accent[1], Theme.accent[2], Theme.accent[3], 1 }
end

-- c: the accent the page wants. A layout color chosen in the options wins over it. The classic and the database look
-- have one color everywhere (the classic look's gold, the database look's ice blue).
function Theme.SetAccent(c, instant)
    if not c then c = C.defaultAccent end
    Theme.pageAccent = c
    local user = Theme.UserAccent()
    if Theme.IsClassic() then
        c = user or C.defaultAccent
    elseif Theme.skin == "database" then
        c = user or Theme.DATABASE_ACCENT
    else
        c = user or c
    end
    local a = Theme.accent
    local animating = accentDriver:IsShown()
    -- already there, or already on the way there
    if Close(animating and accentTo or a, c) then return end
    if instant or Close(a, c) then
        a[1], a[2], a[3] = c[1], c[2], c[3]
        accentDriver:Hide()
        Broadcast()
        return
    end
    accentFrom = { a[1], a[2], a[3] }
    accentTo = { c[1], c[2], c[3] }
    accentT = 0
    accentDriver:Show()
end

-- Re-applies the accent after the layout color setting changed.
function Theme.RefreshAccent(instant)
    Theme.SetAccent(Theme.pageAccent, instant)
end
LJ:Listen("SETTINGS_CHANGED", function(_, what)
    if what == "accent" then Theme.RefreshAccent() end
end)
LJ:Listen("DB_READY", function()
    Theme.cyrillic = LJ.Locale.active == "ruRU" or GetLocale() == "ruRU"
    Theme.SetSkin(LJ.db.skin)
    Theme.RefreshAccent(true)
end)

---------------------------------------------------------------------------
-- Fonts (Barlow family, bundled; Blizzard fonts for non-Latin client languages; Friz Quadrata for Russian texts)
---------------------------------------------------------------------------
local FONT_FILES = {
    medium = "Barlow-Medium.ttf", semibold = "Barlow-SemiBold.ttf", bold = "Barlow-Bold.ttf",
    scBold = "BarlowSemiCondensed-Bold.ttf", scExtra = "BarlowSemiCondensed-ExtraBold.ttf",
    cExtra = "BarlowCondensed-ExtraBold.ttf", cBlack = "BarlowCondensed-Black.ttf",
}
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }

-- name = { file key, size }
local MODERN_FONT_DEFS = {
    hero = { "cBlack", 38 }, heroMid = { "cBlack", 32 }, heroSmall = { "cBlack", 27 },
    title = { "cExtra", 26 }, titleSmall = { "cExtra", 21 },
    wordmark = { "cBlack", 19 }, big = { "cExtra", 20 },
    h2 = { "bold", 14.5 }, h3 = { "bold", 13.5 }, nameBold = { "bold", 13 },
    item = { "semibold", 13.5 }, itemSmall = { "semibold", 12.5 },
    body = { "medium", 13 }, bodySemi = { "semibold", 13 }, bodySmall = { "medium", 12.5 },
    small = { "medium", 11.5 }, smallSemi = { "semibold", 12 }, tiny = { "semibold", 11 },
    label = { "scExtra", 11 }, pill = { "scBold", 11 }, pillTiny = { "scExtra", 9.5 },
    button = { "scBold", 12.5 }, chip = { "scBold", 12 }, tab = { "scBold", 14.5 }, nav = { "scBold", 14 },
    count = { "scExtra", 11 }, glyphText = { "cBlack", 17 }, toggle = { "scBold", 12 },
}
-- Classic look: Friz Quadrata (the Classic interface font) from the client, with Blizzard's black shadow. Friz is wider
-- than Barlow, so the sizes are a bit smaller.
local CLASSIC_FONT_DEFS = {
    hero = { "friz", 27 }, heroMid = { "friz", 24 }, heroSmall = { "friz", 21 },
    title = { "friz", 20 }, titleSmall = { "friz", 16.5 },
    wordmark = { "friz", 16.5 }, big = { "friz", 16 },
    h2 = { "friz", 13.5 }, h3 = { "friz", 13 }, nameBold = { "friz", 13 },
    item = { "friz", 13 }, itemSmall = { "friz", 12.5 },
    body = { "friz", 12.5 }, bodySemi = { "friz", 12.5 }, bodySmall = { "friz", 12 },
    small = { "friz", 11.5 }, smallSemi = { "friz", 11.5 }, tiny = { "friz", 10.5 },
    label = { "friz", 11.5 }, pill = { "friz", 10.5 }, pillTiny = { "friz", 9.5 },
    button = { "friz", 12 }, chip = { "friz", 11.5 }, tab = { "friz", 12 },
    nav = { "friz", 12 }, count = { "friz", 10.5 }, glyphText = { "friz", 14 }, toggle = { "friz", 12 },
}
local FONT_DEFS_BY_SKIN = { modern = MODERN_FONT_DEFS, classic = CLASSIC_FONT_DEFS, database = MODERN_FONT_DEFS }
Theme.FONT_DEFS = MODERN_FONT_DEFS

Theme.customFonts = LATIN[GetLocale()] == true
-- Russian texts (the addon in Russian or a Russian client): Barlow has no Cyrillic letters, so every look uses the
-- game's Friz Quadrata in its Cyrillic version (every client has it) at the sizes of the classic look (set at DB_READY)
Theme.cyrillic = false
local fontObjects = {}

local function FallbackFile(key)
    if key == "cBlack" or key == "cExtra" then
        return (_G.DAMAGE_TEXT_FONT or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    end
    return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- The file of a font key. Russian texts: the Cyrillic Friz Quadrata for every key. "friz": the client font of the
-- classic look (every WoW client has it; other alphabets use the client's own font).
function Theme.FontFile(key)
    if Theme.cyrillic then return "Fonts\\FRIZQT___CYR.TTF" end
    if key == "friz" then
        if Theme.customFonts then return "Fonts\\FRIZQT__.TTF" end
        return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    end
    if Theme.customFonts then return Theme.FONT_DIR .. FONT_FILES[key] end
    return FallbackFile(key)
end

-- The game's Cyrillic Friz Quadrata (every text when Russian names show) has no "·" (it draws a box): such texts
-- show an en dash, which it has.
function Theme.DotSafe(text)
    if Theme.cyrillic and type(text) == "string" then return (text:gsub("·", "–")) end
    return text
end

-- Every font string of the addon: its texts go through DotSafe.
function Theme.PrepareFontString(fs)
    if Theme.cyrillic then
        local set = fs.SetText
        fs.SetText = function(self, text) set(self, Theme.DotSafe(text)) end
    end
    return fs
end

-- Returns the font object for a design font name (created on first use).
function Theme.Font(name)
    local f = fontObjects[name]
    if f then return f end
    f = CreateFont("LootifiedFont_" .. name)
    Theme.ApplyFontDef(f, name)
    f:SetTextColor(1, 1, 1, 1)
    fontObjects[name] = f
    return f
end

-- Sets file, size and shadow of a font object for the current skin (every text using it follows at once).
function Theme.ApplyFontDef(f, name)
    local def = Theme.FONT_DEFS[name] or Theme.FONT_DEFS.body
    f:SetFont(Theme.FontFile(def[1]), def[2], "")
    if Theme.IsClassic() then
        f:SetShadowOffset(1, -1)
        f:SetShadowColor(0, 0, 0, 1)
    else
        f:SetShadowOffset(0, -1)
        f:SetShadowColor(0, 0, 0, 0.55)
    end
end

-- Creates every font object and draws a hidden line with each once, so the font files are loaded long before
-- the window measures its first labels.
function Theme.PreloadFonts()
    if Theme.fontHolder then return end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(10, 10)
    holder:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -200, 200)
    holder:SetAlpha(0)
    for name in pairs(Theme.FONT_DEFS) do
        local fs = Theme.PrepareFontString(holder:CreateFontString(nil, "OVERLAY"))
        fs:SetFontObject(Theme.Font(name))
        fs:SetPoint("TOPLEFT")
        fs:SetText("Lootified 0123456789")
    end
    Theme.fontHolder = holder
    C_Timer.After(2, function() holder:Hide() end)
end
LJ:Listen("LOGIN", function() Theme.PreloadFonts() end)

---------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------
Theme.TEX = {
    shadow = Theme.UI .. "Shadow",
    glow = Theme.UI .. "Glow",
    glowLine = Theme.UI .. "GlowLine",
    circle = Theme.UI .. "Circle",
    circleRing = Theme.UI .. "CircleRing",
    circleRingThin = Theme.UI .. "CircleRingThin",
    maskRound = Theme.UI .. "MaskRound",
    maskCircle = Theme.UI .. "MaskCircle",
    segment = Theme.UI .. "Segment",
    white = Util.WHITE,
    fallbackArt = LJ.MEDIA .. "InstanceFallback",
}

local MODERN_TEX = {}
for key, value in pairs(Theme.TEX) do MODERN_TEX[key] = value end

-- Blizzard Classic UI textures of the classic look (check boxes, menus, drop-downs, list headers, the close button).
-- The Forever client's own interface uses all of them except the close button's normal and pushed texture
-- (UI-Panel-MinimizeButton-Up/-Down): the classic close button checks those (Theme.HasClassic).
Theme.CLASSIC = {
    checkUp = "Interface\\Buttons\\UI-CheckBox-Up",
    checkHighlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    radio = "Interface\\Buttons\\UI-RadioButton",
    plus = "Interface\\Buttons\\UI-PlusButton-Up",
    minus = "Interface\\Buttons\\UI-MinusButton-Up",
    plusHighlight = "Interface\\Buttons\\UI-PlusButton-Hilight",
    dropdown = "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame",
    dropdownButton = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    dropdownButtonDown = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
    mouseHighlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    close = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHighlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
}

-- True when every named classic texture exists in the client.
function Theme.HasClassic(...)
    for i = 1, select("#", ...) do
        if not Util.FileExists(Theme.CLASSIC[(select(i, ...))]) then return false end
    end
    return true
end

-- Bundled texture of the classic look (Media/UI): the gold portrait ring.
Theme.TEX.classicRing = Theme.UI .. "ClassicRing"

-- The dungeon pictures of the game's Dungeon Journal (UI-EJ-DUNGEONBUTTON-<name>, 256 x 128 files): the classic look's
-- dungeon cards. The picture is the part from 4, 4 to 170, 92.
Theme.DUNGEON_ART = "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-"
local DUNGEON_PICTURE = { 4 / 256, 170 / 256, 4 / 128, 92 / 128 }

-- Corner radii that exist as textures (Media/UI/Round<r>.tga and Ring<r>.tga). The classic look has one small radius.
Theme.RADII = { 4, 6, 8, 10, 12 }
Theme.CLASSIC_RADIUS = 4

function Theme.SnapRadius(radius)
    if Theme.IsClassic() then return Theme.CLASSIC_RADIUS end
    local best = Theme.RADII[1]
    for _, r in ipairs(Theme.RADII) do
        if math.abs(r - (radius or 8)) < math.abs(best - (radius or 8)) then best = r end
    end
    return best
end

function Theme.RoundFile(radius, ring)
    return Theme.UI .. (ring and "Ring" or "Round") .. Theme.SnapRadius(radius)
end

---------------------------------------------------------------------------
-- Skin switch
---------------------------------------------------------------------------
local PALETTES = { modern = MODERN_COLORS, classic = CLASSIC_COLORS, database = MODERN_COLORS }

-- A look name as saved; anything unknown is the modern look.
function Theme.ValidSkin(skin)
    return PALETTES[skin] and skin or "modern"
end

-- Switches the design tokens (colors in place, font objects, texture set, accent). Widgets read the skin when they
-- are created, so the window is rebuilt afterwards (UI:ApplySkin).
function Theme.SetSkin(skin)
    skin = Theme.ValidSkin(skin)
    Theme.skin = skin
    local palette = (skin == "database" and Theme.databaseClassic) and CLASSIC_COLORS or PALETTES[skin]
    for key, value in pairs(palette) do
        local c = C[key]
        if c then c[1], c[2], c[3], c[4] = value[1], value[2], value[3], value[4] or 1 end
    end
    Theme.FONT_DEFS = Theme.cyrillic and CLASSIC_FONT_DEFS
        or ((skin == "database" and Theme.databaseClassic) and CLASSIC_FONT_DEFS or FONT_DEFS_BY_SKIN[skin])
    wipe(Theme.PANE)
    for key, value in pairs(Theme.IsClassic() and Theme.HEARTH or Theme.GLASS) do Theme.PANE[key] = value end
    for name, f in pairs(fontObjects) do Theme.ApplyFontDef(f, name) end
    for key, value in pairs(MODERN_TEX) do Theme.TEX[key] = value end
    -- glows only in the glass looks
    if Theme.IsClassic() then Theme.TEX.glow, Theme.TEX.glowLine = nil, nil end
    -- every accent listener belongs to a window of the old look (the main window and its
    -- tours), which a look switch builds again: none of their parts takes the new look's colors
    wipe(accentListeners)
    Theme.RefreshAccent(true)
end

---------------------------------------------------------------------------
-- Glyphs (Media/UI/Glyphs.tga, Phosphor icons) and boss emblems (game-icons.net)
---------------------------------------------------------------------------
local function SheetCoords(sheet, index)
    local col = index % sheet.columns
    local row = math.floor(index / sheet.columns)
    local s = sheet.cell / sheet.size
    return col * s, (col + 1) * s, row * s, (row + 1) * s
end

function Theme.GlyphCoords(name)
    local G = LJ.Glyphs
    local index = G.index[name] or G.index.circle
    return SheetCoords(G.sheet, index)
end

function Theme.SetGlyph(texture, name, color, alpha)
    texture:SetTexture(LJ.Glyphs.sheet.file)
    texture:SetTexCoord(Theme.GlyphCoords(name))
    if color then texture:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1) end
end

-- Inline glyph for FontStrings: |T...|t with vertex color.
function Theme.GlyphString(name, size, color, offsetY)
    local G = LJ.Glyphs
    local index = G.index[name] or G.index.circle
    local sheet = G.sheet
    local col = index % sheet.columns
    local row = math.floor(index / sheet.columns)
    local c = color or C.text2
    return string.format("|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", sheet.file, size or 12, size or 12, offsetY or 0,
        sheet.size, sheet.size, col * sheet.cell, (col + 1) * sheet.cell, row * sheet.cell, (row + 1) * sheet.cell,
        c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Named icons for the game's tooltips and the chat (dark in every look): fixed bright colors.
local ICON_GLYPH = { star = "star", gem = "crown", check = "check", upgrade = "upgrade", dot = "circle", cross = "close" }
local ICON_COLOR = { star = hex("F6C744"), gem = hex("F6C744"), check = hex("57E389"), upgrade = hex("57E389"),
    dot = hex("F6C744"), cross = hex("F87171") }
function Theme.IconString(name, size)
    return Theme.GlyphString(ICON_GLYPH[name] or "circle", size or 12, ICON_COLOR[name] or hex("C3C8D0"))
end

function Theme.SetEmblem(texture, name)
    local G = LJ.Glyphs
    local index = G.emblemIndex[name] or G.emblemIndex.skull
    texture:SetTexture(G.emblems.file)
    texture:SetTexCoord(SheetCoords(G.emblems, index))
end

-- Emblem for a boss without a portrait (by name keywords, then a default).
local EMBLEM_RULES = {
    { "chest", "chest" }, { "coffer", "chest" }, { "cache", "chest" }, { "tribute", "chest" }, { "strongbox", "chest" },
    { "spider", "spider" }, { "fang", "spider" }, { "widow", "spider" }, { "brood", "spider" },
    { "wolf", "wolf" }, { "worg", "wolf" }, { "hound", "wolf" }, { "dragon", "dragon" }, { "drake", "dragon" },
    { "onyxia", "dragon" }, { "whelp", "dragon" }, { "ghost", "ghost" }, { "spirit", "ghost" }, { "shade", "ghost" },
    { "abandoned", "ghost" }, { "captain", "visor" }, { "golem", "golem" }, { "plunder", "golem" },
    { "construct", "golem" }, { "magma", "fire" }, { "flame", "fire" }, { "fire", "fire" }, { "infern", "fire" },
    { "baron", "brute" }, { "abomination", "brute" }, { "ogre", "ogre" }, { "bjork", "ogre" },
    { "king", "crownedSkull" }, { "queen", "crownedSkull" }, { "lord", "crownedSkull" }, { "emperor", "crownedSkull" },
    { "vile", "cultist" }, { "cult", "cultist" }, { "necro", "cultist" }, { "rath", "cultist" }, { "priest", "hood" },
    { "anvilmar", "dwarf" }, { "dirgehammer", "dwarfHelm" }, { "thane", "dwarfHelm" }, { "dark iron", "dwarfHelm" },
    { "rat", "rat" }, { "bear", "bear" }, { "hydra", "hydra" }, { "naga", "kraken" }, { "tide", "kraken" },
    { "crystal", "crystal" }, { "bat", "bat" }, { "demon", "demon" }, { "felguard", "demon" }, { "gnome", "gnome" },
    { "troll", "troll" }, { "zombie", "zombie" }, { "ghoul", "zombie" },
}

function Theme.BossEmblem(boss)
    local name = (boss and boss.name or ""):lower()
    if boss and boss.chest then return "chest" end
    for _, rule in ipairs(EMBLEM_RULES) do
        if name:find(rule[1], 1, true) then return rule[2] end
    end
    return "skull"
end

-- Quest status: pill kind, short label, color (key: the palette entry), list icon (glyph or symbol text).
Theme.QUEST_STATUS = {
    READY = { pill = "ok", label = "TURN IN", long = "Ready to turn in", color = C.ok, key = "ok", symbol = "?" },
    ACTIVE = { pill = "blue", label = "IN LOG", long = "In your quest log", color = C.blue, key = "blue", symbol = "!" },
    AVAILABLE = { pill = "gold", label = "AVAILABLE", long = "Available", color = C.gold, key = "gold", symbol = "!" },
    LOCKED = { pill = "red", label = "LOCKED", long = "Earlier quests missing", color = C.red, key = "red", glyph = "lock" },
    LOW_LEVEL = { pill = "gray", label = "LEVEL %d", long = "Available from level %d", color = C.gray, key = "gray", symbol = "!" },
    COMPLETED = { pill = "gray", label = "DONE", long = "Completed", color = C.text4, key = "text4", glyph = "check" },
    OTHER = { pill = "gray", label = "OTHER", long = "Not for your character", color = C.text5, key = "text5", glyph = "xCircle" },
}

-- A palette color as the game's tooltips show it (the modern colors in every look: tooltips are dark).
function Theme.TooltipColor(key)
    return MODERN_COLORS[key] or MODERN_COLORS.text2
end

-- WoW quest difficulty colors (red, orange, yellow, green, grey) relative to the character level, per look.
-- onDark: for the game's tooltips (the modern colors in every look).
local LEVEL_COLORS = {
    modern = { hex("FF5A52"), hex("FF9A3C"), hex("F2CF4A"), hex("5FD068"), hex("8A929E") },
    classic = { hex("FF5A52"), hex("FF9A3C"), hex("F2CF4A"), hex("6CD266"), hex("9C9283") },
}
local function LevelPalette(onDark)
    return LEVEL_COLORS[onDark and "modern" or Theme.skin] or LEVEL_COLORS.modern
end

function Theme.LevelColor(level, onDark)
    if not level then return C.text3 end
    local me = LJ.Player and LJ.Player.level or 1
    local diff = level - me
    local p = LevelPalette(onDark)
    if diff >= 5 then return p[1] end
    if diff >= 3 then return p[2] end
    if diff >= -2 then return p[3] end
    local green = (me <= 9 and 4) or (me <= 19 and 5) or (me <= 29 and 6) or (me <= 39 and 7) or 8
    if -diff <= green then return p[4] end
    return p[5]
end

-- Color of an instance level range for the character.
function Theme.RangeColor(minLevel, maxLevel, onDark)
    local me = LJ.Player and LJ.Player.level or 1
    if not minLevel then return C.text3 end
    maxLevel = maxLevel or minLevel
    local p = LevelPalette(onDark)
    if maxLevel < me - 5 then return p[5] end
    if maxLevel < me - 1 then return p[4] end
    if minLevel <= me + 2 then return p[3] end
    if minLevel <= me + 4 then return p[2] end
    return p[1]
end

function Theme.ChanceColor(chance)
    if not chance then return C.text2 end
    if chance >= 20 then return C.chanceHi end
    if chance >= 5 then return C.chanceMid end
    return C.chanceLo
end

---------------------------------------------------------------------------
-- Instance artwork: candidates with their crop regions; crops keep the aspect ratio.
---------------------------------------------------------------------------
local function CropFor(region, targetAspect, sourceAspect, verticalBias)
    local l, r, t, b = region[1], region[2], region[3], region[4]
    local w, h = r - l, b - t
    verticalBias = verticalBias or 0.5
    local regionAspect = sourceAspect * (w / h)
    if regionAspect > targetAspect then
        local keep = targetAspect / regionAspect
        local cut = w * (1 - keep)
        return l + cut / 2, r - cut / 2, t, b
    else
        local keep = regionAspect / targetAspect
        local cut = h * (1 - keep)
        return l, r, t + cut * verticalBias, b - cut * (1 - verticalBias)
    end
end
Theme.CropFor = CropFor

local function Candidates(inst)
    local a = inst.art or {}
    local list = {}
    if a.loading then
        local isModern = a.loading:find("camelot160", 1, true) ~= nil
        -- classic loading screens carry the WoW logo in the upper third: keep to the lower part
        list[#list + 1] = { "Interface\\Glues\\LoadingScreens\\" .. a.loading, isModern and { 0.02, 0.98, 0.04, 0.96 } or { 0.02, 0.98, 0.24, 0.9 },
            isModern and (16 / 9) or (4 / 3), isModern and 0.5 or 0.55 }
    end
    if a.ej then
        list[#list + 1] = { "Interface\\EncounterJournal\\UI-EJ-LOREBG-" .. a.ej, { 0, 0.7617187, 0, 0.65625 }, 1024 / 1024, 0.35 }
    end
    if a.lfg then
        list[#list + 1] = { "Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. a.lfg, { 0, 0.66, 0, 0.66 }, 2, 0.5 }
    end
    list[#list + 1] = { Theme.TEX.fallbackArt, { 0, 1, 0, 1 }, 2.0, 0.5, true }
    return list
end

-- Returns path, left, right, top, bottom of the best artwork for a target aspect ratio, and whether it is
-- the bundled fallback.
function Theme.GetInstanceArt(inst, targetAspect)
    for _, c in ipairs(Candidates(inst)) do
        if c[5] or Util.FileExists(c[1]) then
            local l, r, t, b = CropFor(c[2], targetAspect, c[3], c[4])
            return c[1], l, r, t, b, c[5] and true or false
        end
    end
end

function Theme.SetInstanceArt(texture, inst, targetAspect)
    local path, l, r, t, b, fallback = Theme.GetInstanceArt(inst, targetAspect or 2)
    texture:SetTexture(path)
    texture:SetTexCoord(l, r, t, b)
    return path, fallback
end

-- A dungeon's picture for a card: the journal's picture of the dungeon when the client has it, else its other art
-- (the new Forever dungeons: their loading screen). Returns true when it is the bundled fallback art.
function Theme.SetDungeonPicture(texture, inst, targetAspect)
    local name = inst.art and inst.art.ej
    local file = name and (Theme.DUNGEON_ART .. name)
    if file and Util.FileExists(file) then
        texture:SetTexture(file)
        texture:SetTexCoord(CropFor(DUNGEON_PICTURE, targetAspect, 2, 0.45))
        return false
    end
    local _, fallback = Theme.SetInstanceArt(texture, inst, targetAspect)
    return fallback
end

-- Small round thumbnail of an instance (LFG icon when present, else a crop of its art).
function Theme.SetInstanceIcon(texture, inst)
    local a = inst.art or {}
    if a.lfg then
        local file = "Interface\\LFGFrame\\LFGIcon-" .. a.lfg
        if Util.FileExists(file) then
            texture:SetTexture(file)
            texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            return
        end
    end
    Theme.SetInstanceArt(texture, inst, 1)
end

function Theme.GetInstanceIconPath(inst)
    local a = inst.art or {}
    if a.lfg then
        local file = "Interface\\LFGFrame\\LFGIcon-" .. a.lfg
        if Util.FileExists(file) then return file end
    end
    return inst.kind == "raid" and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_14"
end
