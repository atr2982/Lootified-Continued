-- Lootified - the settings window: opens over the main window (the gear button, /lf settings) with the categories on
-- the left and their settings on the right: General, Modules (the pages can be switched off, Core/Modules.lua), Look &
-- color, Tooltips (with a live preview of an item tooltip), Map & alerts, Language, Tour & help. Every change applies
-- at once; "Reset this page" puts the shown category back to its defaults. The window is made for each main window (a
-- new look builds a new one) in the look's own style.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Kit = LJ.Kit
local Modules = LJ.Modules
local C = Theme.COLORS

local Settings = { category = "general" }
UI.Settings = Settings

local WIDTH, HEIGHT = 800, 560
local HEAD, FOOT, SIDE = 56, 52, 196
local PAD = 18
local ROW_GAP = 6
local PREVIEW_WIDTH = 280   -- the tooltip preview beside the tooltip settings

local function Fire(key) LJ:Fire("SETTINGS_CHANGED", key) end

---------------------------------------------------------------------------
-- A page of settings: its controls top down, each with a refresh that shows the current state
---------------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function NewPage(parent, width)
    -- rows: the switches by their title, chips: the chips by their key (the tests and the tour find them there)
    local p = setmetatable({ y = 0, width = width, refreshers = {}, rows = {}, chips = {} }, Page)
    p.frame = CreateFrame("Frame", nil, parent)
    p.frame:SetPoint("TOPLEFT")
    p.frame:SetWidth(width)
    p.frame:Hide()
    return p
end

function Page:OnRefresh(fn) self.refreshers[#self.refreshers + 1] = fn end

function Page:Refresh()
    for _, fn in ipairs(self.refreshers) do fn() end
end

function Page:Space(h) self.y = self.y + (h or 10) end

-- A text block at the cursor (wraps to the width).
function Page:Text(text, font, color, width, x)
    local fs = Widgets.Text(self.frame, font, color)
    fs:SetWordWrap(true)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(width or self.width)
    fs:SetPoint("TOPLEFT", x or 0, -self.y)
    fs:SetText(text)
    self.y = self.y + math.ceil(fs:GetStringHeight()) + 4
    return fs
end

-- The category's title and what it is about.
function Page:Heading(title, text)
    self:Text(Theme.Case(L(title)), "titleSmall", Theme.PANE.title)
    self.y = self.y + 2
    if text then self:Text(L(text), "bodySmall", C.text3) end
    self:Space(8)
end

-- A small section label.
function Page:Label(text)
    self:Space(4)
    self:Text(Util.Upper(L(text)), "label", Kit.SectionColor())
    self:Space(2)
end

-- A setting that is on or off: a row with its name, what it does and a switch at the right; a click anywhere on the
-- row switches it. def = { title, text, glyph, get(), set(on), enabled() (nil: always), why (shown while disabled) }
function Page:Switch(def, width)
    width = width or self.width
    local row = CreateFrame("Button", nil, self.frame)
    row:SetPoint("TOPLEFT", 0, -self.y)
    row:SetWidth(width)
    row.fill = Widgets.CreateBox(row, "BACKGROUND", 1, 8)
    row.ring = Widgets.CreateBox(row, "BACKGROUND", 2, 8, true)
    local x = 12
    if def.glyph then
        row.icon = Widgets.Glyph(row, def.glyph, 16, Theme.accent)
        row.icon:SetPoint("TOPLEFT", 14, -14)
        x = 42
    end
    row.title = Widgets.Text(row, "h3", C.white)
    row.title:SetPoint("TOPLEFT", x, -10)
    row.title:SetText(L(def.title))
    row.toggle = Widgets.CreateToggle(row, "", nil)
    row.toggle:SetLabel("")
    row.toggle:SetPoint("RIGHT", -8, 0)
    local textWidth = width - x - math.max(row.toggle:GetWidth(), 45) - 18   -- the classic check box is narrower
    row.text = Widgets.Text(row, "small", C.text3)
    row.text:SetWordWrap(true)
    row.text:SetJustifyH("LEFT")
    row.text:SetWidth(textWidth)
    row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.text:SetText(def.text and L(def.text) or "")
    local h = math.max(40, math.ceil(10 + 16 + 3 + (def.text and row.text:GetStringHeight() or 0) + 10))
    row:SetHeight(h)
    row.def = def
    self.rows[def.title] = row
    local function Visual()
        Widgets.BoxFill(row.fill, row.ring, "row", row.hovered and row.enabled)
    end
    row.toggle.onChange = function(_, on)
        def.set(on)
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
    end
    row:SetScript("OnClick", function()
        if row.enabled then row.toggle:Click() end
    end)
    row:SetScript("OnEnter", function()
        row.hovered = true
        Visual()
        if not row.enabled and def.why then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(L(def.title), 1, 1, 1)
            GameTooltip:AddLine(L(def.why), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        row.hovered = false
        Visual()
        GameTooltip:Hide()
    end)
    self:OnRefresh(function()
        row.enabled = not def.enabled or def.enabled()
        row.toggle:SetChecked(def.get())
        row.toggle:SetEnabled(row.enabled)
        row:SetAlpha(row.enabled and 1 or 0.45)
        if row.icon then
            local c = def.get() and Theme.accent or C.text4
            row.icon:SetVertexColor(c[1], c[2], c[3], 1)
        end
        Visual()
    end)
    self.y = self.y + h + ROW_GAP
    return row
end

-- A choice of one: chips in rows. def = { options = { { key, text } }, get() -> key, set(key) }
function Page:Chips(def)
    local x, top, chips = 0, self.y, {}
    for _, opt in ipairs(def.options) do
        local chip = Widgets.CreateChip(self.frame, opt.text, opt.glyph, 28)
        if x > 0 and x + chip:GetWidth() > self.width then
            x, top = 0, top + 34
        end
        chip:SetPoint("TOPLEFT", x, -top)
        x = x + chip:GetWidth() + 6
        chip.key = opt.key
        self.chips[opt.key] = chip
        chip:SetScript("OnClick", function(c)
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            def.set(c.key)
        end)
        chips[#chips + 1] = chip
    end
    self:OnRefresh(function()
        local current = def.get()
        for _, chip in ipairs(chips) do chip:SetActive(chip.key == current) end
    end)
    self.y = top + 28 + 12
    return chips
end

-- Buttons side by side: list = { { text, glyph, kind, onClick } }
function Page:Buttons(list)
    local x, buttons = 0, {}
    for _, def in ipairs(list) do
        local b = Widgets.CreateButton(self.frame, def.text, def.kind or "ghost", def.glyph, nil, 28)
        b:SetPoint("TOPLEFT", x, -self.y)
        b:SetScript("OnClick", def.onClick)
        x = x + b:GetWidth() + 8
        buttons[#buttons + 1] = b
    end
    self.y = self.y + 28 + 12
    return buttons
end

---------------------------------------------------------------------------
-- The categories
---------------------------------------------------------------------------
local function DbSwitch(page, key, title, text, extra)
    local def = { title = title, text = text,
        get = function() return LJ.db[key] and true or false end,
        set = function(on)
            LJ.db[key] = on
            Fire(key)
        end }
    for k, v in pairs(extra or {}) do def[k] = v end
    return page:Switch(def, extra and extra.width)
end

local function ResetKeys(keys)
    for _, key in ipairs(keys) do
        LJ.db[key] = LJ.defaults[key]
        Fire(key)
    end
end

local SCALES = { 0.8, 0.9, 1.0, 1.1, 1.2 }

local function BuildGeneral(page)
    page:Heading("General", "How items are rated and the window.")
    -- how this character's items are rated (UI/RatingPicker.lua); nothing marked before the first pick
    page:Label("Rate items (this character)")
    page:Chips({ options = UI.RatingPicker.OPTIONS,
        get = function() return LJ.cdb.rating end,
        set = function(v)
            UI.RatingPicker:Set(v)
            Fire("rating")
        end })
    page:Text(L("Percent: every upgrade in percent by your spec's stat weights, for tanks, DPS and healers."), "bodySmall", C.text2)
    page:Space(6)
    page:Label("Window size")
    local options = {}
    for i, v in ipairs(SCALES) do options[i] = { key = v, text = string.format("%d%%", v * 100) } end
    page:Chips({ options = options,
        get = function()
            for _, v in ipairs(SCALES) do
                if math.abs((LJ.db.scale or 1) - v) < 0.01 then return v end
            end
        end,
        set = function(v)
            LJ.db.scale = v
            Fire("scale")
        end })
    page:Label("Window position")
    page:Buttons({ { text = "Reset window position", glyph = "reset", onClick = function()
        LJ.db.position = nil
        Fire("position")
    end } })
end

local function ResetGeneral()
    LJ.db.scale = 1.0
    Fire("scale")
    LJ.db.position = nil
    Fire("position")
end

local function BuildModules(page)
    page:Heading("Modules", "Switch off what you do not use: its tab goes away, Best in Slot also takes its crowns and "
        .. "tooltip lines with it, Wishlist its stars, tooltip mark and alerts. One module always stays on. The "
        .. "database look has its own pages.")
    for _, m in ipairs(Modules.LIST) do
        page:Switch({ title = m.name, text = m.text, glyph = m.glyph,
            get = function() return Modules.On(m.key) end,
            set = function(on) Modules.Set(m.key, on) end,
            enabled = function() return Modules.CanSwitch(m.key) end,
            why = "At least one module stays on." })
    end
end

local function ResetModules()
    for _, m in ipairs(Modules.LIST) do Modules.Set(m.key, true) end
end

local function SetAccent(mode, color)
    local s = LJ.db.accent
    s.mode = mode
    if color then s.color = color end
    Fire("accent")
end

local function AccentKey()
    local s = LJ.db.accent
    if s.mode ~= "fixed" then return s.mode end
    local name = Theme.UserAccentName()
    return name == "Custom" and "custom" or s.color:upper()
end

local function BuildLook(page)
    page:Heading("Look & color", "How the Lootified window looks and whether the minimap button shows. The window is "
        .. "built again in the new look.")
    page:Label("Look")
    local looks = {}
    for i, look in ipairs(UI.LOOKS) do looks[i] = { key = look.key, text = look.name } end
    page:Chips({ options = looks,
        get = function() return Theme.skin end,
        set = function(key)
            if key == Theme.skin then return end
            -- the window (and this one with it) is built again: leave the click first
            C_Timer.After(0, function()
                UI:ApplySkin(key)
                Settings:Open("look")
            end)
        end })
    page:Buttons({ { text = "Compare the looks...", glyph = "eye", onClick = function()
        Settings:Close()
        UI.LayoutPicker:Show()
    end } })
    page:Label("Layout color")
    local colors = { { key = "auto", text = "Automatic" },
        { key = "class", text = Theme.ColorText(L("My class color"), Theme.ClassAccent(LJ.Player.class)) } }
    for _, p in ipairs(Theme.ACCENT_PRESETS) do colors[#colors + 1] = { key = p[2], text = Theme.ColorText(L(p[1]), Theme.hex(p[2])) } end
    colors[#colors + 1] = { key = "custom", text = "Custom..." }
    page:Chips({ options = colors, get = AccentKey,
        set = function(key)
            if key == "auto" or key == "class" then
                SetAccent(key)
            elseif key == "custom" then
                UI:PickCustomAccent()
            else
                SetAccent("fixed", key)
            end
        end })
    page:Text(L("Automatic follows the page: the dungeon's colors in the journal, your class color on Best in Slot."),
        "small", C.text4)
    page:Space(6)
    page:Switch({ title = "Minimap button", text = "A click opens or closes Lootified; drag it around the minimap.",
        get = function() return not LJ.db.minimap.hide end,
        set = function(on)
            LJ.db.minimap.hide = not on
            Fire("minimap")
        end })
end

local function ResetLook()
    SetAccent("auto")
    LJ.db.minimap.hide = false
    Fire("minimap")
end

-- The item of the tooltip preview: the first Best in Slot pick of the active spec that drops in a dungeon, else the
-- first boss drop the addon knows.
local function SampleItem()
    local spec = LJ.Player:GetActiveSpec()
    for _, p in ipairs(spec and LJ.BiS.GetPicks(spec) or {}) do
        if LJ.Items.GetSources(p.id) then return p.id end
    end
    return LJ.Data.Instances[1].bosses[1].loot[1]
end

local previews = 0
local function BuildTooltips(page)
    page:Heading("Tooltips", "Lines Lootified adds to every item tooltip in the game.")
    local width = page.width - PREVIEW_WIDTH - 16
    local top = page.y
    local bisOn = function() return Modules.On("bis") end
    DbSwitch(page, "tooltipUpgrade", "Upgrade for my spec", "The damage the sim found for the item against what you wear, or that it is on your Best in Slot list.",
        { width = width, enabled = bisOn, why = "The Best in Slot module is off (Modules)." })
    DbSwitch(page, "tooltipSource", "Where it drops", "The boss, rare or zone that drops it, with the chance.", { width = width })
    DbSwitch(page, "tooltipQuests", "Quests", "The quests that give the item or need it.", { width = width })
    DbSwitch(page, "tooltipWishlist", "Wishlist mark", "Says when the item is on your wishlist.",
        { width = width, enabled = function() return Modules.On("wishlist") end, why = "The Wishlist module is off (Modules)." })
    -- the preview: a real item tooltip with the lines as they are set
    local label = Widgets.Text(page.frame, "label", Kit.SectionColor())
    label:SetPoint("TOPLEFT", width + 16, -top)
    label:SetText(Util.Upper(L("Preview")))
    -- a named tooltip (its template names its lines after it); every window (look) makes its own
    previews = previews + 1
    local tip = CreateFrame("GameTooltip", "LootifiedSettingsPreview" .. previews, page.frame, "GameTooltipTemplate")
    page.preview = tip
    page:OnRefresh(function()
        if not page.frame:IsVisible() then return end
        tip:SetOwner(page.frame, "ANCHOR_NONE")
        tip:SetScale(1)
        tip:ClearAllPoints()
        tip:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        tip:SetFrameStrata(page.frame:GetFrameStrata())
        tip:SetFrameLevel(page.frame:GetFrameLevel() + 20)
        tip:SetItemByID(SampleItem())
        tip:Show()
        -- a tooltip is as wide as its longest line: a wider one is scaled down to its column (the list would cut it off)
        local w = tip:GetWidth() or 0
        if w > PREVIEW_WIDTH then tip:SetScale(PREVIEW_WIDTH / w) end
    end)
    page.frame:HookScript("OnHide", function() tip:Hide() end)
end

local TOOLTIP_KEYS = { "tooltipUpgrade", "tooltipSource", "tooltipQuests", "tooltipWishlist" }

local function BuildMap(page)
    page:Heading("Map & alerts", "Dungeon entrances on the world map and what Lootified does by itself.")
    DbSwitch(page, "worldMapEntrances", "Dungeon entrances on the world map", "A pin at every entrance; a click opens the dungeon.")
    DbSwitch(page, "wishlistAlerts", "Alert when a wishlist item drops", "A message and a sound when an item you starred drops or is rolled for.",
        { enabled = function() return Modules.On("wishlist") end, why = "The Wishlist module is off (Modules)." })
    DbSwitch(page, "upgradeCheck", "Upgrade check for loot", "Beside every loot roll, and in a window on Alt+Click on any item: is it an upgrade for you? Sim lets it fight against what you wear.",
        { enabled = function() return Modules.On("bis") end, why = "The Best in Slot module is off (Modules)." })
    DbSwitch(page, "autoOpenInstance", "Open the current dungeon", "Inside a dungeon, Lootified opens on it.",
        { enabled = function() return Modules.On("journal") end, why = "The Journal module is off (Modules)." })
end

local MAP_KEYS = { "worldMapEntrances", "wishlistAlerts", "upgradeCheck", "autoOpenInstance" }

local function SetLanguage(value)
    LJ.db.language = value
    Fire("language")
end

local function BuildLanguage(page)
    page:Heading("Language", "The language of the interface and of the game's names in Lootified.")
    -- each language under its own name; Russian in the addon's language (the looks' own font has no Cyrillic
    -- letters); Korean and Chinese only in a client of that language (LJ.Locale.Available)
    local names = { enUS = "English", deDE = "Deutsch", frFR = "Français", esES = "Español (EU)", esMX = "Español (AL)",
        ptBR = "Português", ruRU = L("Russian"), koKR = "한국어", zhTW = "繁體中文", zhCN = "简体中文" }
    local options = { { key = "auto", text = F("Game language (%s)", names[LJ.Locale.Resolve("auto")]) },
        { key = "enUS", text = names.enUS } }
    for _, lang in ipairs(LJ.Locale.LANGUAGES) do
        if LJ.Locale.Available(lang) then options[#options + 1] = { key = lang, text = names[lang] } end
    end
    page:Chips({ options = options, get = function() return LJ.db.language or "auto" end, set = SetLanguage })
    local note = page:Text(L("A new language shows after the interface reloads."), "small", C.text4)
    local reload = page:Buttons({ { text = "Reload now", glyph = "reset", kind = "primary", onClick = function() ReloadUI() end } })[1]
    page:OnRefresh(function()
        local pending = LJ.Locale.Resolve(LJ.db.language) ~= LJ.Locale.active
        note:SetShown(pending)
        reload:SetShown(pending)
    end)
end

local function ResetLanguage() SetLanguage("auto") end

local function BuildHelp(page)
    page:Heading("Tour & help", "A short tour shows every part of Lootified, with these settings at the end.")
    page.startTour = page:Buttons({ { text = "Start the tour", glyph = "book", kind = "primary", onClick = function()
        Settings:Close()
        UI.Tour:Start()
    end } })[1]
    -- bugs and ideas: the homepage and Discord to copy (UI/HelpBox.lua)
    page:Label("Bugs & ideas")
    page:Text("Found a bug or have an idea? Visit the Lootified GitHub project.", "bodySmall", C.text2)
    page.links = page:Buttons({ { text = "Project on GitHub", glyph = "link", onClick = function() UI.HelpBox:Show() end } })[1]
    page:Label("Chat commands")
    page:Text(L("/lf opens and closes the window, /lf settings opens these settings, /lf tour starts the tour. /lf help lists every command."),
        "bodySmall", C.text2)
    page:Space(6)
    page:Text(F("Lootified %s", LJ.VERSION), "small", C.text4)
end

Settings.CATEGORIES = {
    { key = "general", name = "General", glyph = "sliders", build = BuildGeneral, reset = ResetGeneral },
    { key = "modules", name = "Modules", glyph = "grid", build = BuildModules, reset = ResetModules },
    { key = "look", name = "Look & color", glyph = "eye", build = BuildLook, reset = ResetLook },
    { key = "tooltips", name = "Tooltips", glyph = "info", build = BuildTooltips, reset = function() ResetKeys(TOOLTIP_KEYS) end },
    { key = "map", name = "Map & alerts", glyph = "mapPin", build = BuildMap, reset = function() ResetKeys(MAP_KEYS) end },
    { key = "language", name = "Language", glyph = "globe", build = BuildLanguage, reset = ResetLanguage },
    { key = "help", name = "Tour & help", glyph = "book", build = BuildHelp },
}
local byKey = {}
for _, c in ipairs(Settings.CATEGORIES) do byKey[c.key] = c end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function CategoryButton(parent, cat)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(36)
    Kit.AddMarks(b)
    b.icon = Widgets.Glyph(b, cat.glyph, 15, C.text3)
    b.icon:SetPoint("LEFT", 12, 0)
    b.text = Widgets.Text(b, "h3", C.text1)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.text:SetText(L(cat.name))
    b.count = Widgets.Text(b, "tiny", C.text4, nil, "RIGHT")
    b.count:SetPoint("RIGHT", -10, 0)
    b.key = cat.key
    b:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        Settings:Show(cat.key)
    end)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        Kit.MarkVisual(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        Kit.MarkVisual(self)
    end)
    return b
end

local function Create(host)
    local shade = CreateFrame("Frame", nil, host)
    shade:SetAllPoints()
    -- a layer above the window (frame levels inside one layer move when the game raises the window): nothing of the
    -- window takes a click while the settings show
    shade:SetFrameStrata("DIALOG")
    shade:SetFrameLevel(host:GetFrameLevel() + 100)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    shade.dim = Widgets.Solid(shade, "BACKGROUND", 0, C.black or { 0, 0, 0 }, 0.55)
    shade.dim:SetAllPoints()
    -- a click beside the window closes it
    shade:SetScript("OnMouseDown", function() Settings:Close() end)
    shade:Hide()
    shade.host = host

    local win = CreateFrame("Frame", nil, shade)
    win:SetSize(WIDTH, HEIGHT)
    win:EnableMouse(true)
    Widgets.CreateShadow(win, 22, 0.8)
    win.panel = Widgets.CreatePopupPanel(win, 14)
    shade.win = win

    -- the head: title, version, close
    win.gear = Widgets.Glyph(win, "gear", 20, Theme.accent)
    win.gear:SetPoint("TOPLEFT", PAD, -(HEAD - 20) / 2)
    win.title = Widgets.Text(win, "titleSmall", Theme.PANE.title)
    win.title:SetPoint("LEFT", win.gear, "RIGHT", 10, 1)
    win.title:SetText(Theme.Case(L("Settings")))
    win.version = Widgets.Text(win, "small", C.text4)
    win.version:SetPoint("BOTTOMLEFT", win.title, "BOTTOMRIGHT", 10, 2)
    win.version:SetText(F("Lootified %s", LJ.VERSION))
    win.close = Widgets.CreateButton(win, "Close", "ghost", "close", nil, 26)
    win.close:SetPoint("TOPRIGHT", -PAD + 4, -(HEAD - 26) / 2)
    win.close:SetScript("OnClick", function() Settings:Close() end)
    local headLine = Kit.Line(win)
    headLine:SetHeight(1)
    headLine:SetPoint("TOPLEFT", 0, -HEAD)
    headLine:SetPoint("TOPRIGHT", 0, -HEAD)
    Theme.OnAccent(win, function(_, r, g, b) win.gear:SetVertexColor(r, g, b, 1) end)

    -- the categories
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 0, -HEAD)
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(SIDE)
    local sideLine = Kit.Line(win)
    sideLine:SetWidth(1)
    sideLine:SetPoint("TOPLEFT", side, "TOPRIGHT")
    sideLine:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT")
    shade.buttons = {}
    for i, cat in ipairs(Settings.CATEGORIES) do
        local b = CategoryButton(side, cat)
        b:SetPoint("TOPLEFT", 10, -12 - (i - 1) * 38)
        b:SetPoint("RIGHT", -10, 0)
        shade.buttons[cat.key] = b
    end
    shade.side = side

    -- the settings of the picked category
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", SIDE + PAD, -(HEAD + 14))
    body:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 8)
    local scroll = Widgets.CreateScrollArea(body, 6)
    scroll:SetAllPoints()
    shade.body, shade.scroll = body, scroll
    shade.pages = {}

    -- the foot: reset and done
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", SIDE, 0)
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT)
    local footLine = Kit.Line(foot)
    footLine:SetHeight(1)
    footLine:SetPoint("TOPLEFT")
    footLine:SetPoint("TOPRIGHT")
    win.done = Widgets.CreateButton(foot, "Done", "primary", nil, nil, 30)
    win.done:SetPoint("RIGHT", -PAD, 0)
    win.done:SetScript("OnClick", function() Settings:Close() end)
    win.reset = Widgets.CreateButton(foot, "Reset this page", "ghost", "reset", nil, 28)
    win.reset:SetPoint("RIGHT", win.done, "LEFT", -8, 0)
    win.reset:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        byKey[Settings.category].reset()
        Settings:Refresh()
    end)
    win.note = Widgets.Text(foot, "small", C.text4)
    win.note:SetPoint("LEFT", PAD, 0)
    win.note:SetText(L("Changes apply at once."))
    return shade
end

-- The window of the current main window (made on first use).
function Settings:Frame()
    local host = UI:CreateMainFrame()
    if not (self.frame and self.frame.host == host) then self.frame = Create(host) end
    return self.frame
end

-- The page of a category (built on first use).
function Settings:Page(key)
    local f = self:Frame()
    local page = f.pages[key]
    if not page then
        page = NewPage(f.scroll.content, f.body:GetWidth() - 12)
        byKey[key].build(page)
        page.frame:SetHeight(page.y)
        f.pages[key] = page
    end
    return page
end

-- Shows a category.
function Settings:Show(key)
    assert(byKey[key], "unknown settings category " .. tostring(key))
    local f = self:Frame()
    self.category = key
    for k, page in pairs(f.pages) do
        if k ~= key then page.frame:Hide() end
    end
    local page = self:Page(key)
    page.frame:Show()
    f.scroll:SetContentHeight(page.y + 8)
    f.scroll:ScrollToTop()
    for k, b in pairs(f.buttons) do
        b.selected = k == key
        local c = b.selected and Theme.accent or C.text3
        b.icon:SetVertexColor(c[1], c[2], c[3], 1)
        Kit.MarkVisual(b)
    end
    f.win.reset:SetShown(byKey[key].reset ~= nil)
    self:Refresh()
end

-- The shown page and the counts follow the settings.
function Settings:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    f.buttons.modules.count:SetText(F("%d of %d", Modules.Count(), #Modules.LIST))
    f.pages[self.category]:Refresh()
end

-- aside: at the right edge of the main window (the tour's text box goes left of it)
function Settings:Open(key, aside)
    if not (UI.frame and UI.frame:IsShown()) then UI:Toggle() end
    local f = self:Frame()
    UI:ClosePopups()
    f.win:ClearAllPoints()
    if aside then
        f.win:SetPoint("RIGHT", f.host, "RIGHT", -12, -10)
    else
        f.win:SetPoint("CENTER", f.host, "CENTER", 0, -10)
    end
    f:Show()
    self:Show(key or self.category)
end

function Settings:Close()
    if self.frame then self.frame:Hide() end
end

function Settings:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

function Settings:Toggle()
    if self:IsShown() then self:Close() else self:Open() end
end

LJ:Listen("SETTINGS_CHANGED", function() Settings:Refresh() end)
LJ:Listen("MODULES_CHANGED", function() Settings:Refresh() end)
