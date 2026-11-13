-- Lootified - main window: frame, top bar (logo, navigation, search, help, options) and page host. The classic look is
-- a dark leather window with a title bar (character, name, help, options, close), a row of buttons for the pages and
-- the search box, and the pages on a brown panel; the database look has its four tabs (Items, Mobs, Quests, Places) in
-- the top bar and a search on each page (UI/Database/). Each look has its own pages (UI/Pane/ for the classic look);
-- switching the look rebuilds the window with them (UI:ApplySkin).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local C = Theme.COLORS
local Anim = Widgets.Anim

-- The pages of each look; UI.pages is the set of the active look.
UI.pageSets = { modern = {}, classic = {}, database = {} }
UI.pages = UI.pageSets.modern
UI.state = { page = nil }

local FRAME_WIDTH, FRAME_HEIGHT = 980, 620
local TOP_HEIGHT = 48
local FOOT_HEIGHT = 26      -- the footer under the pages: the version, the homepage and Discord (every look)
local DATABASE_TOP = 52     -- the database look's top bar: the logo, DATABASE and the three tabs
local SEARCH_WIDTH = 250
-- Classic look: title bar (34) and the row of page buttons (38) above the brown panel that holds the pages (12 from
-- the window's sides, the footer below it, 12 inside). The window is taller by what the second row needs; the page
-- area is 932 x 536.
local CLASSIC_TITLE, CLASSIC_TOP, CLASSIC_EXTRA = 34, 72, 24
local CLASSIC_MARGIN, CLASSIC_PAD = 12, 12
local CLASSIC_SEARCH = 240
UI.FRAME_WIDTH, UI.FRAME_HEIGHT = FRAME_WIDTH, FRAME_HEIGHT

-- The width of the pages' area: in the classic look the pages lie inside the brown panel.
function UI:ContentWidth()
    return FRAME_WIDTH - (LJ.Theme.IsClassic() and 2 * (CLASSIC_MARGIN + CLASSIC_PAD) or 0)
end
UI.TOP_HEIGHT = TOP_HEIGHT
UI.SIDEBAR_WIDTH = 244

-- The looks to choose from (options, the layout picker on the first start; UI/LayoutPicker.lua).
UI.LOOKS = {
    { key = "modern", name = "Modern", text = "Dark glass with the dungeon art, 3D models and soft animations." },
    { key = "classic", name = "Classic", text = "Dark leather and gold titles, every dungeon as a picture." },
}

-- The English name of a look (translate it where it is shown).
function UI.LookName(key)
    if key == "database" then return "Database" end
    for _, look in ipairs(UI.LOOKS) do
        if look.key == key then return look.name end
    end
    error("Lootified: unknown look " .. tostring(key))
end

-- Pages register themselves for the looks they draw: page = { Create(self, root), Show(self, ...), Refresh(self),
-- OnHide(self) }. looks: { "classic" }, { "database" } ... for the pages of those looks, nil for the modern look.
-- The page table as registered (methods and constants) is kept, so a skin switch can start the page from scratch.
UI.pristine = {}
function UI:RegisterPage(key, page, looks)
    page.key = key
    for _, look in ipairs(looks or { "modern" }) do self.pageSets[look][key] = page end
    local pristine = {}
    for k, v in pairs(page) do pristine[k] = v end
    self.pristine[page] = pristine
end

-- Forgets everything a page created (its frames belong to the window that is being replaced).
function UI:ResetPage(page)
    if page.root then page.root:Hide() end
    local pristine = self.pristine[page]
    for k in pairs(page) do page[k] = nil end
    for k, v in pairs(pristine) do page[k] = v end
end

-- The look's pages become the active set (at login with the saved look, and on a look switch).
LJ:Listen("DB_READY", function() UI.pages = UI.pageSets[Theme.skin] end)

---------------------------------------------------------------------------
-- Search box with instant results
---------------------------------------------------------------------------
local MAX_QUICK_RESULTS = 8
local QUICK_ROW = 38

local function CreateQuickResults(frame, box)
    local results = CreateFrame("Frame", nil, frame)
    results:SetFrameStrata("DIALOG")
    results:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
    results:SetWidth(330)
    results:EnableMouse(true)
    Widgets.CreateShadow(results, 14, 0.7)
    results.panel = Widgets.CreatePopupPanel(results, 10)
    results:Hide()
    results.rows = {}

    local function GetRow(i)
        local row = results.rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, results)
        row:SetHeight(QUICK_ROW)
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * QUICK_ROW)
        row:SetPoint("RIGHT", -5, 0)
        row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 3, 6)
        row.item = Widgets.CreateItemIcon(row, 26)
        row.item:SetPoint("LEFT", 6, 0)
        row.item:EnableMouse(false)
        row.emblem = Widgets.CreateEmblem(row, 26)
        row.emblem:SetPoint("LEFT", 6, 0)
        row.glyph = Widgets.Glyph(row.emblem, "scroll", 14, C.gold, "OVERLAY", 2)
        row.glyph:SetPoint("CENTER", row.emblem, "CENTER")
        row.text = Widgets.Text(row, "itemSmall", C.text1)
        row.text:SetPoint("TOPLEFT", 42, -5)
        row.text:SetPoint("RIGHT", -6, 0)
        row.sub = Widgets.Text(row, "small", C.text3)
        row.sub:SetPoint("BOTTOMLEFT", 42, 6)
        row.sub:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnEnter", function(self)
            local a = Theme.accent
            self.hl:SetColor(a[1], a[2], a[3], 0.14)
            if self.result and self.result.itemID then
                Widgets.ShowItemTooltip(self, self.result.itemID)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:SetColor(1, 1, 1, 0)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            local r = self.result
            if not r then return end
            if r.itemID and Items.HandleClick(r.itemID) then return end
            results:Hide()
            box:ClearFocus()
            UI:OpenSearchResult(r)
        end)
        results.rows[i] = row
        return row
    end

    local allButton = CreateFrame("Button", nil, results)
    allButton:SetHeight(30)
    allButton.hl = Widgets.CreateLazyBox(allButton, "BACKGROUND", 3, 6)
    allButton.text = Widgets.Text(allButton, "button", C.text2, nil, "CENTER")
    allButton.text:SetPoint("CENTER")
    allButton:SetScript("OnEnter", function(self)
        local a = Theme.accent
        self.hl:SetColor(a[1], a[2], a[3], 0.14)
    end)
    allButton:SetScript("OnLeave", function(self) self.hl:SetColor(1, 1, 1, 0) end)
    allButton:SetScript("OnClick", function()
        results:Hide()
        box:ClearFocus()
        UI:Open("search", box:GetText())
    end)
    results.allButton = allButton

    function results:Update(text)
        text = Util.Trim(text)
        -- from 3 letters on (or a dungeon shortcut like "dm")
        local list, _, tooShort = UI.Search(text, MAX_QUICK_RESULTS + 1)
        if tooShort and #list == 0 then
            self:Hide()
            return
        end
        for _, row in ipairs(self.rows) do row:Hide() end
        local shown = math.min(#list, MAX_QUICK_RESULTS)
        for i = 1, shown do
            local row = GetRow(i)
            local r = list[i]
            row.result = r
            row.item:Hide()
            row.emblem:Hide()
            row.glyph:Hide()
            if r.kind == "item" then
                row.item:SetItem(r.itemID)
                row.item:Show()
            elseif r.kind == "boss" then
                local inst = LJ.instanceByKey[r.instKey]
                row.emblem:SetBoss(inst and inst.bosses[r.bossIndex])
                row.emblem:Show()
            elseif r.kind == "quest" then
                row.emblem:SetRare(false)
                row.emblem:SetGlyph("scroll")
                row.emblem.glyph:Hide()
                row.emblem:Show()
                Theme.SetGlyph(row.glyph, "scroll", C.gold)
                row.glyph:Show()
            elseif r.kind == "world" then
                -- a mob: its emblem; a zone: the globe
                row.emblem:SetRare(r.rare)
                row.emblem:SetGlyph(Theme.BossEmblem({ name = r.text }))
                if not r.npcID then
                    row.emblem.glyph:Hide()
                    Theme.SetGlyph(row.glyph, "globe", C.gold)
                    row.glyph:Show()
                end
                row.emblem:Show()
            else
                row.emblem:SetRare(false)
                row.emblem:SetGlyph("visor")
                local inst = LJ.instanceByKey[r.instKey]
                if inst then
                    row.emblem.glyph:Hide()
                    row.emblem.portrait:Show()
                    Theme.SetInstanceIcon(row.emblem.portrait, inst)
                end
                row.emblem:Show()
            end
            row.text:SetText(r.text)
            row.sub:SetText(r.sub or "")
            row.hl:SetColor(1, 1, 1, 0)
            row:Show()
        end
        allButton:ClearAllPoints()
        allButton:SetPoint("TOPLEFT", 5, -7 - shown * QUICK_ROW)
        allButton:SetPoint("RIGHT", -5, 0)
        allButton.text:SetText(#list == 0 and L("No results") or L("Show all results"))
        self:SetHeight(shown * QUICK_ROW + 44)
        self:Show()
    end
    return results
end

local function CreateSearch(frame, parent)
    local box = CreateFrame("EditBox", "LootifiedSearchBox", parent)
    box:SetSize(SEARCH_WIDTH, 30)
    box:SetAutoFocus(false)
    box:SetFontObject(Theme.Font("bodySmall"))
    box:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
    box:SetTextInsets(30, 26, 0, 0)
    box.panel = Widgets.CreatePanel(box, 8, "BACKGROUND", 1)
    -- the idle border: a faint line, a bronze one in the classic look
    box.idleBorder = Theme.IsClassic() and Theme.HEARTH.inputBorder or { 1, 1, 1, 0.08 }
    box.panel:SetFill(Theme.IsClassic() and Theme.HEARTH.inputFill or { 0, 0, 0, 0.28 })
    box.panel:SetBorder(box.idleBorder)
    box.icon = Widgets.Glyph(box, "search", 14, C.text4)
    box.icon:SetPoint("LEFT", 10, 0)
    box.placeholder = Widgets.Text(box, "bodySmall", C.text4)
    box.placeholder:SetPoint("LEFT", 30, 0)
    box.placeholder:SetPoint("RIGHT", -10, 0)   -- a narrower box cuts it off with "..."
    box.placeholder:SetText(L("Search items, bosses, quests"))
    box.clear = Widgets.CreateButton(box, nil, "icon", "close", 20, 20)
    box.clear:SetPoint("RIGHT", -5, 0)
    box.clear:Hide()
    box.clear:SetScript("OnClick", function()
        box:SetText("")
        box.placeholder:Show()
        box.clear:Hide()
        frame.searchResults:Hide()
        box:ClearFocus()
    end)

    local results = CreateQuickResults(frame, box)
    frame.searchResults = results

    local function FocusVisual(focused)
        local a = Theme.accent
        if focused then
            box.panel:SetBorder(a[1], a[2], a[3], 0.55)
            box.icon:SetVertexColor(a[1], a[2], a[3], 1)
        else
            box.panel:SetBorder(box.idleBorder)
            box.icon:SetVertexColor(C.text4[1], C.text4[2], C.text4[3], 1)
        end
    end
    box:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        self.placeholder:SetShown(text == "")
        self.clear:SetShown(text ~= "")
        if userInput then results:Update(text) end
    end)
    box:SetScript("OnEnterPressed", function(self)
        results:Hide()
        self:ClearFocus()
        UI:Open("search", self:GetText())
    end)
    box:SetScript("OnEscapePressed", function(self)
        results:Hide()
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function() FocusVisual(true) end)
    box:SetScript("OnEditFocusLost", function()
        FocusVisual(false)
        -- a moment later (a click on a result goes first); typing again in the meantime keeps them
        C_Timer.After(0.2, function()
            if not box:HasFocus() and not results:IsMouseOver() then results:Hide() end
        end)
    end)
    Theme.OnAccent(box, function(b) if b:HasFocus() then FocusVisual(true) end end)
    return box
end

-- Blizzard color picker with live preview; Cancel restores the previous setting.
function UI:PickCustomAccent()
    local s = LJ.db.accent
    Widgets.Menu.Close()
    local oldMode, oldColor = s.mode, s.color
    local a = Theme.accent
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        s.mode, s.color = "fixed", Theme.ColorToHex(r, g, b)
        Theme.RefreshAccent(true)
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = a[1], g = a[2], b = a[3],
        hasOpacity = false,
        swatchFunc = Apply,
        cancelFunc = function()
            s.mode, s.color = oldMode, oldColor
            Theme.RefreshAccent(true)
        end,
    })
end

-- Closes what opens over the window (menus, the search results, the Best in Slot slot list): they lie in a higher
-- strata than the window and would cover the settings.
function UI:ClosePopups()
    Widgets.Menu.Close()
    if self.frame and self.frame.searchResults then self.frame.searchResults:Hide() end
    local bis = self.pages.bis
    if bis and bis.flyout then bis.flyout:Hide() end
end

-- The gear button (and the character chip of the classic pages): the settings window.
function UI:ShowOptions()
    UI.Settings:Toggle()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function ApplyPosition(frame)
    frame:ClearAllPoints()
    local p = LJ.db.position
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
    frame:SetScale(LJ.db.scale or 1)
end


-- Navigation labels in the look's spelling (upper case in the glass looks); the classic look's buttons carry glyphs,
-- the database look's tabs too (no counts).
local function NavDefs()
    local defs = {}
    if Theme.IsDatabase() then
        defs[1] = { key = "mainview", text = Theme.Case(L("Main View")), glyph = "home", count = false }
        for i, t in ipairs(LJ.Database.TABS) do
            defs[i + 1] = { key = t.key, text = Theme.Case(L(t.text)), glyph = t.glyph, count = false }
        end
        return defs
    end
    -- every module has its tab; the tabs of modules that are off are hidden (UI:ApplyModules)
    for i, m in ipairs(LJ.Modules.LIST) do
        defs[i] = { key = m.key, text = Theme.Case(L(m.name)), glyph = Theme.IsClassic() and m.glyph or nil }
    end
    -- Keep the database discoverable without requiring a trip through Settings.
    defs[#defs + 1] = { key = "database", text = Theme.Case(L("Database")), glyph = Theme.IsClassic() and "grid" or nil }
    return defs
end

-- Classic close button (the round red button of Classic windows); the client's standard close button when the art is
-- missing.
local function CreateClassicClose(frame, parent)
    local close
    if Theme.HasClassic("close", "closeDown") then
        close = CreateFrame("Button", nil, parent)
        close:SetSize(30, 30)
        close:SetNormalTexture(Theme.CLASSIC.close)
        close:SetPushedTexture(Theme.CLASSIC.closeDown)
        close:SetHighlightTexture(Theme.CLASSIC.closeHighlight, "ADD")
    else
        close = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
        close:SetSize(28, 28)
    end
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    return close
end

-- The classic title bar: the character on the left, the name in the middle, a bronze line under it.
local function CreateClassicTitle(frame, top)
    local who = CreateFrame("Frame", nil, top)
    who:SetPoint("TOPLEFT", 16, 0)
    who:SetSize(360, CLASSIC_TITLE)
    who.icon = Widgets.Glyph(who, "user", 12, C.text4)
    who.icon:SetPoint("LEFT", 0, 0)
    who.text = Widgets.Text(who, "bodySmall", C.text4)
    who.text:SetPoint("LEFT", who.icon, "RIGHT", 7, 0)
    who.text:SetPoint("RIGHT")
    function who:Update()
        local P = LJ.Player
        local spec = P:GetActiveSpec()
        local line = F("Level %d %s%s", P.level or 1, Util.ClassName(P.class or "WARRIOR"), spec and (" · " .. L(spec.name)) or "")
        self.text:SetText(Theme.ColorText(UnitName("player"), C.text2) .. "  ·  " .. line)
    end
    frame.who = who
    local title = Widgets.Text(top, "wordmark", Theme.HEARTH.title, "OVERLAY", "CENTER")
    title:SetPoint("CENTER", top, "TOP", 0, -CLASSIC_TITLE / 2)
    title:SetText(LJ.TITLE)
    frame.title = title
    local line = Widgets.Solid(top, "BORDER", 0, Theme.HEARTH.line, 0.16)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -CLASSIC_TITLE)
    line:SetPoint("TOPRIGHT", -1, -CLASSIC_TITLE)
end

local function CreateTopBar(frame)
    local classic, database = Theme.IsClassic(), Theme.IsDatabase()
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight((classic and CLASSIC_TOP) or (database and DATABASE_TOP) or TOP_HEIGHT)
    top:SetFrameLevel(frame:GetFrameLevel() + 20)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() frame:StartMoving() end)
    top:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        LJ.db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    top.shade = Widgets.Solid(top, "BACKGROUND", 0, C.white)
    top.shade:SetPoint("TOPLEFT", 12, 0)
    top.shade:SetPoint("BOTTOMRIGHT", -12, 0)
    top.shade:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.03))
    top.line = Widgets.Line(top, "BORDER", 0.06)
    top.line:SetHeight(1)
    top.line:SetPoint("BOTTOMLEFT")
    top.line:SetPoint("BOTTOMRIGHT")
    if classic then
        -- the title bar draws its own line; the brown panel below frames the pages
        top.shade:Hide()
        top.line:Hide()
    end

    -- logo tile + wordmark; the glow behind the tile follows the layout color
    local logo = CreateFrame("Frame", nil, top)
    logo:SetSize(28, 28)
    logo:SetPoint("LEFT", 14, 0)
    logo.glow = logo:CreateTexture(nil, "BACKGROUND", nil, -1)
    logo.glow:SetTexture(Theme.TEX.glow)
    logo.glow:SetBlendMode("ADD")
    logo.glow:SetPoint("TOPLEFT", -16, 16)
    logo.glow:SetPoint("BOTTOMRIGHT", 16, -16)
    logo.icon = logo:CreateTexture(nil, "ARTWORK")
    logo.icon:SetTexture(LJ.MEDIA .. "Logo64")
    logo.icon:SetAllPoints()
    top.logo = logo

    local word = Widgets.Text(top, "wordmark", C.white)
    word:SetPoint("LEFT", logo, "RIGHT", 9, 0)
    top.word = word
    if database then
        -- the wordmark in white, DATABASE beside it in the accent
        top.label = Widgets.Text(top, "label", C.white)
        top.label:SetPoint("LEFT", word, "RIGHT", 10, 0)
        top.label:SetText(Util.Upper(L("Database")))
    end
    Theme.OnAccent(logo, function(l, r, g, b)
        l.glow:SetVertexColor(r, g, b, 0.5)
        if top.label then
            word:SetText("LOOTIFIED")
            top.label:SetTextColor(r, g, b, 1)
        else
            word:SetText(string.format("LOOT|cff%02x%02x%02xIFIED|r", r * 255, g * 255, b * 255))
        end
    end)

    local function Fit() if frame:IsShown() then frame.FitSearch() end end
    local nav, close
    if database then
        -- the database pages as tabs; every page has its own search, so the bar has none
        nav = Widgets.CreateTabs(top, NavDefs(), function(key)
            if key == "mainview" then
                UI:ApplySkin(UI.previousSkin ~= "database" and UI.previousSkin or "modern")
            else
                UI:Open(key)
            end
        end,
            { font = "nav", height = top:GetHeight(), pad = 14, iconAccent = true })
        nav:SetPoint("LEFT", top.label, "RIGHT", 26, 0)
        close = Widgets.CreateButton(top, nil, "icon", "close", 30, 30)
        close:SetPoint("RIGHT", -10, 0)
        close:SetScript("OnClick", function() frame:Hide() end)
    elseif classic then
        logo:Hide()
        word:Hide()
        CreateClassicTitle(frame, top)
        -- the page buttons in the second row
        nav = Widgets.CreateTabs(top, NavDefs(), function(key)
            if key == "database" then
                UI:ApplySkin("database")
            else
                UI:Open(key)
            end
        end, { font = "nav", height = CLASSIC_TOP - CLASSIC_TITLE, onLayout = Fit })
        nav:SetPoint("TOPLEFT", top, "TOPLEFT", CLASSIC_MARGIN, -CLASSIC_TITLE)
        close = CreateClassicClose(frame, top)
    else
        nav = Widgets.CreateTabs(top, NavDefs(), function(key)
            if key == "database" then
                UI:ApplySkin("database")
            else
                UI:Open(key)
            end
        end,
            { font = "nav", height = top:GetHeight(), pad = 10, onLayout = Fit })
        nav:SetPoint("LEFT", word, "RIGHT", 18, 0)
        close = Widgets.CreateButton(top, nil, "icon", "close", 30, 30)
        close:SetPoint("RIGHT", -10, 0)
        close:SetScript("OnClick", function() frame:Hide() end)
    end
    nav:SetWidth(database and 560 or (classic and 650) or 470)
    frame.nav = nav
    UI:ApplyModules()
    Widgets.SetTooltip(close, "Close", nil, "ANCHOR_BOTTOM")
    -- the icon buttons side by side (the search box keeps its room beside them in German and Russian)
    local gear = Widgets.CreateButton(top, nil, "icon", "sliders", 30, 30)
    gear:SetPoint("RIGHT", close, "LEFT", classic and -2 or 0, 0)
    gear:SetScript("OnClick", function(b) UI:ShowOptions(b) end)
    Widgets.SetTooltip(gear, "Settings", nil, "ANCHOR_BOTTOM")
    -- the ? beside it: Lootified's homepage and Discord (UI/HelpBox.lua)
    local help = Widgets.CreateButton(top, nil, "icon", "question", 30, 30)
    help:SetPoint("RIGHT", gear, "LEFT", classic and -2 or 0, 0)
    help:SetScript("OnClick", function() UI.HelpBox:Show() end)
    Widgets.SetTooltip(help, "Help & links", nil, "ANCHOR_BOTTOM")
    frame.gear = gear
    frame.help = help
    frame.closeButton = close
    if database then return top end

    frame.search = CreateSearch(frame, top)
    local maxSearch = SEARCH_WIDTH
    if classic then
        maxSearch = CLASSIC_SEARCH
        frame.search:SetHeight(26)
        frame.search:SetPoint("RIGHT", top, "TOPRIGHT", -CLASSIC_MARGIN, -(CLASSIC_TITLE + (CLASSIC_TOP - CLASSIC_TITLE) / 2))
    else
        frame.search:SetPoint("RIGHT", help, "LEFT", -8, 0)
    end
    -- the box leaves the tabs the room they need: the game's own font of other alphabets (Russian, Korean and Chinese
    -- clients) is wider than Barlow, and the last tab ran under the box (when the window shows and when the tabs change)
    function frame.FitSearch()
        local tabsEnd = nav:GetLeft() + nav.width + 12
        frame.search:SetWidth(math.max(120, math.min(maxSearch, frame.search:GetRight() - tabsEnd)))
    end
    return top
end

-- The footer under the pages: Lootified's version on the left, the homepage and Discord on the right; a click on them
-- opens them to copy (UI/HelpBox.lua). A hairline above it; in the classic look the brown panel ends above it.
local function CreateFoot(frame)
    local classic = Theme.IsClassic()
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetPoint("BOTTOMLEFT", classic and CLASSIC_MARGIN or 0, 0)
    foot:SetPoint("BOTTOMRIGHT", classic and -CLASSIC_MARGIN or 0, 0)
    foot:SetHeight(FOOT_HEIGHT)
    if not classic then
        foot.line = Widgets.Line(foot, "BORDER", 0.06)
        foot.line:SetHeight(1)
        foot.line:SetPoint("TOPLEFT")
        foot.line:SetPoint("TOPRIGHT")
    end
    foot.version = Widgets.Text(foot, "label", C.text4)
    foot.version:SetPoint("LEFT", classic and 4 or 16, 0)
    foot.version:SetText(Util.Upper(F("Lootified %s", LJ.VERSION)))
    local links = CreateFrame("Button", nil, foot)
    -- left of the size grip (CreateGrip)
    links:SetPoint("RIGHT", classic and -14 or -26, 0)
    links:SetHeight(FOOT_HEIGHT)
    -- as the version, white under the mouse
    links.text = Widgets.Text(links, "label", C.text4)
    links.text:SetPoint("RIGHT")
    links.text:SetText(Util.Upper("Lootified on GitHub"))
    links:SetWidth(math.ceil(Widgets.TextWidth(links.text)))
    links:SetScript("OnEnter", function(b) Widgets.SetTextColor(b.text, C.white) end)
    links:SetScript("OnLeave", function(b) Widgets.SetTextColor(b.text, C.text4) end)
    links:SetScript("OnClick", function() UI.HelpBox:Show() end)
    foot.links = links
    frame.foot = foot
end

-- The grip at the bottom right: dragged, the whole window zooms (as Window size in the settings), its top left stays
-- and its corner goes as near the cursor as the scale range and the screen's edges let it; the scale and the place
-- are kept.
local MIN_SCALE, MAX_SCALE = 0.7, 1.5
local function CreateGrip(frame)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 70)   -- above the border
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local left, top   -- the window's top left in UIParent's units while it is dragged
    local function Drag()
        local ui = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local w, h = frame:GetWidth(), frame:GetHeight()
        -- the scale that puts the corner nearest the cursor
        local s = ((x / ui - left) * w + (top - y / ui) * h) / (w * w + h * h)
        s = math.max(MIN_SCALE, math.min(MAX_SCALE, (UIParent:GetWidth() - left) / w, top / h, s))
        s = math.floor(s * 100 + 1e-6) / 100
        frame:SetScale(s)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
    end
    grip:SetScript("OnMouseDown", function(g)
        GameTooltip:Hide()
        local s = frame:GetScale()
        left, top = frame:GetLeft() * s, frame:GetTop() * s
        g:SetScript("OnUpdate", Drag)
    end)
    grip:SetScript("OnMouseUp", function(g)
        g:SetScript("OnUpdate", nil)
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        LJ.db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
        LJ.db.scale = frame:GetScale()
        LJ:Fire("SETTINGS_CHANGED", "scale")
    end)
    Widgets.SetTooltip(grip, "Window size", "Drag to make the window bigger or smaller. It keeps its size.", "ANCHOR_TOP")
    frame.grip = grip
end

function UI:CreateMainFrame()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "LootifiedMainFrame", UIParent)
    self.frame = frame
    local classic = Theme.IsClassic()
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT + FOOT_HEIGHT + (classic and CLASSIC_EXTRA - CLASSIC_MARGIN or 0))
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    if not tContains(UISpecialFrames, "LootifiedMainFrame") then tinsert(UISpecialFrames, "LootifiedMainFrame") end

    -- glass body
    Widgets.CreateShadow(frame, 22, 0.8)
    frame.bg = Widgets.CreateBox(frame, "BACKGROUND", -7, 12)
    frame.bg:SetGradient("VERTICAL", C.winTop, C.winBottom)
    frame.glowTL = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    frame.glowTL:SetTexture(Theme.TEX.glow)
    frame.glowTL:SetSize(560, 400)
    frame.glowTL:SetPoint("CENTER", frame, "TOPLEFT", 100, -10)

    -- border above everything
    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints()
    border:SetFrameLevel(frame:GetFrameLevel() + 60)
    border:EnableMouse(false)
    border.ring = Widgets.CreateBox(border, "OVERLAY", 0, 12, true)
    border.ring:SetColor(1, 1, 1, 0.075)
    border.outer = Widgets.CreateBox(border, "OVERLAY", -1, 12, true)
    border.outer:SetAnchor(frame, -1, -1, -1, -1)
    border.outer:SetColor(0, 0, 0, 0.6)
    border.topLeft = Widgets.Solid(border, "OVERLAY", 2, C.white)
    border.topLeft:SetHeight(1)
    border.topLeft:SetPoint("TOPLEFT", 40, 0)
    border.topLeft:SetPoint("TOPRIGHT", frame, "TOP", 0, 0)
    border.topRight = Widgets.Solid(border, "OVERLAY", 2, C.white)
    border.topRight:SetHeight(1)
    border.topRight:SetPoint("TOPLEFT", frame, "TOP", 0, 0)
    border.topRight:SetPoint("TOPRIGHT", -40, 0)
    frame.border = border
    Theme.OnAccent(frame, function(f, r, g, b)
        f.glowTL:SetVertexColor(r, g, b, 0.16)
        border.topLeft:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.75))
        border.topRight:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.75), CreateColor(r, g, b, 0))
    end)
    if classic then
        -- dark leather in a bronze line with a faint gold line inside it; the pages lie on a brown panel
        local H = Theme.HEARTH
        frame.glowTL:Hide()
        border.topLeft:Hide()
        border.topRight:Hide()
        border.ring:SetColor(H.windowBorder)
        border.inner = Widgets.CreateBox(border, "OVERLAY", 0, 4, true)
        border.inner:SetAnchor(frame, 3, 3, 3, 3)
        border.inner:SetColor(H.windowInner)
        frame.main = CreateFrame("Frame", nil, frame)
        frame.main:SetPoint("TOPLEFT", CLASSIC_MARGIN, -CLASSIC_TOP)
        frame.main:SetPoint("BOTTOMRIGHT", -CLASSIC_MARGIN, FOOT_HEIGHT)
        frame.main.fill = Widgets.CreateBox(frame.main, "BACKGROUND", -4, 4)
        frame.main.fill:SetGradient("VERTICAL", H.mainTop, H.mainBottom)
        frame.main.ring = Widgets.CreateBox(frame.main, "BACKGROUND", -3, 4, true)
        frame.main.ring:SetColor(H.mainBorder)
    elseif Theme.IsDatabase() then
        -- a second, violet glow at the bottom right
        frame.glowBR = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
        frame.glowBR:SetTexture(Theme.TEX.glow)
        frame.glowBR:SetSize(560, 420)
        frame.glowBR:SetPoint("CENTER", frame, "BOTTOMRIGHT", -100, 10)
        frame.glowBR:SetVertexColor(0.59, 0.43, 1, 0.09)
    end

    frame.top = CreateTopBar(frame)

    local content = CreateFrame("Frame", nil, frame)
    if classic then
        content:SetPoint("TOPLEFT", frame.main, "TOPLEFT", CLASSIC_PAD, -CLASSIC_PAD)
        content:SetPoint("BOTTOMRIGHT", frame.main, "BOTTOMRIGHT", -CLASSIC_PAD, CLASSIC_PAD)
    else
        content:SetPoint("TOPLEFT", 0, -frame.top:GetHeight())
        content:SetPoint("BOTTOMRIGHT", 0, FOOT_HEIGHT)
    end
    frame.content = content
    CreateFoot(frame)
    CreateGrip(frame)

    -- the whole interface hidden (Alt+Z, a cinematic): the window only goes with it, nothing of it is closed
    frame:SetScript("OnShow", function(f)
        if f.hiddenWithUI then
            f.hiddenWithUI = nil
            return
        end
        if f.search then f.FitSearch() end
        if f.who then f.who:Update() end
        if not UI.switchingSkin then Util.PlaySound("IG_SPELLBOOK_OPEN") end
        f:SetAlpha(0)
        Anim.Fade(f, 1, 0.16, "mainFrameFade")
        -- the first time: the tour (UI/Tour.lua)
        if UI.Tour then UI.Tour:OnWindowShown() end
    end)
    frame:SetScript("OnHide", function(f)
        if not UIParent:IsShown() then
            f.hiddenWithUI = true
            return
        end
        if not UI.switchingSkin then Util.PlaySound("IG_SPELLBOOK_CLOSE") end
        Widgets.Menu.Close()
        UI.Settings:Close()
        if frame.searchResults then frame.searchResults:Hide() end
        local page = UI.pages[UI.state.page]
        if page and page.OnHide then LJ:SafeCall(page.OnHide, page) end
        if UI.Tour then UI.Tour:OnWindowHidden(frame) end
        -- search caches are only kept while the window is open
        LJ:Fire("WINDOW_CLOSED")
    end)

    ApplyPosition(frame)
    return frame
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function EnsurePage(key)
    local page = UI.pages[key]
    if not page then return nil end
    if not page.root then
        page.root = CreateFrame("Frame", nil, UI.frame.content)
        page.root:SetAllPoints()
        page.root:Hide()
        page:Create(page.root)
    end
    return page
end

function UI:UpdateNav()
    if not self.frame then return end
    local active = self.state.page
    if active == "search" or active == "item" then active = nil end
    self.frame.nav:Select(active)
end

function UI:ShowPage(key, ...)
    local started = debugprofilestop()
    self:CreateMainFrame()
    local page = EnsurePage(key)
    if not page then return end
    local changed = self.state.page ~= key
    for otherKey, other in pairs(self.pages) do
        if other.root and otherKey ~= key and other.root:IsShown() then
            other.root:Hide()
            if other.OnHide then LJ:SafeCall(other.OnHide, other) end
        end
    end
    self.state.page = key
    page.root:Show()
    if changed then
        page.root:SetAlpha(0)
        Anim.Fade(page.root, 1, 0.14, "pageFade")
    end
    page:Show(...)
    self:UpdateNav()
    -- (/lf debug: what showing it cost)
    LJ:Debug("page %s: %.1f ms", key, debugprofilestop() - started)
end

-- The module of each page of the Modern and Classic looks (the item and search pages belong to none).
local PAGE_MODULE = { foryou = "foryou", home = "journal", instance = "journal", quest = "journal", journal = "journal",
    world = "world", bis = "bis" }

-- The tabs of the modules that are off are hidden (the database look has its own tabs).
function UI:ApplyModules()
    if Theme.IsDatabase() then return end
    for _, m in ipairs(LJ.Modules.LIST) do self.frame.nav:ShowTab(m.key, LJ.Modules.On(m.key)) end
end

-- A module switched on or off: the tabs follow; the page of a module that went off gives way to the start page, a page
-- that stays shows what the module changed (For you: the Best in Slot set and the next upgrades, the filters).
LJ:Listen("MODULES_CHANGED", function()
    if not UI.frame then return end
    if not Theme.IsDatabase() then
        UI:ApplyModules()
        local module = PAGE_MODULE[UI.state.page]
        if UI.frame:IsShown() and module and not LJ.Modules.On(module) then
            UI:Open("start")
            return
        end
    end
    UI:RefreshCurrent()
end)

-- Public: open the journal on a page.
-- home(kind) | instance(key, bossIndex) | quest(questID) | item(itemID) | foryou | journal | bis | world(map, npcID)
-- | search(text)
function UI:Open(page, arg1, arg2)
    if self.LayoutPicker:AskFirst(function() self:Open(page, arg1, arg2) end) then return end
    local frame = self:CreateMainFrame()
    if Theme.IsDatabase() then
        -- the database look has its own pages: every address of the other looks leads to one of them
        frame:Show()
        self:ShowPage(LJ.Database.Route(page or self.state.page, arg1, arg2))
        return
    end
    if page == "start" then page = LJ.Modules.Start() end
    -- a page of a module that is off: the start page
    local module = PAGE_MODULE[page or self.state.page]
    if module and not LJ.Modules.On(module) then
        page, arg1, arg2 = LJ.Modules.Start(), nil, nil
    end
    if page == "instance" and not LJ.instanceByKey[arg1] then
        page = "home"
        arg1 = nil
    end
    if page == "quest" and not (LJ.Quests and LJ.Quests.Get(arg1)) then
        page = "home"
        arg1 = nil
    end
    if not page then
        page = self.state.page or "home"
    end
    frame:Show()
    if page == "home" then
        self:ShowPage("journal", "home", arg1)
    elseif page == "instance" then
        self:ShowPage("journal", "instance", arg1, arg2)
    elseif page == "quest" then
        self:ShowPage("journal", "quest", arg1)
    elseif page == "journal" then
        self:ShowPage("journal", "home")
    elseif page == "search" then
        self:ShowPage("search", arg1)
    elseif page == "item" then
        if not arg1 then return self:Open("home") end
        self:ShowPage("item", arg1)
    elseif page == "world" then
        self:ShowPage("world", arg1, arg2)
    else
        self:ShowPage(page)
    end
end

-- The instance the player is currently in (if we know it; none in a dungeon whose wings share one map, see
-- LJ:GetInstanceByMapID: the window opens as it does elsewhere).
function UI:GetCurrentInstance()
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return nil end
    return LJ:GetInstanceByMapID(instanceID) or LJ:GetInstanceByName(name)
end

function UI:Toggle()
    if self.LayoutPicker:AskFirst(function() self:Toggle() end) then return end
    local frame = self:CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    if LJ.db.autoOpenInstance and LJ.Modules.On("journal") then
        local inst = self:GetCurrentInstance()
        if inst then
            self:Open("instance", inst.key)
            return
        end
    end
    if self.state.page then
        frame:Show()
        local page = self.pages[self.state.page]
        if page and page.root then
            page.root:Show()
            if page.Refresh then page:Refresh() end
            self:UpdateNav()
            return
        end
    end
    -- the first open of a session starts on the start page
    self:Open("start")
end

-- Switches the look (modern, classic, database). Widgets read the look when they are created, so the window is built
-- again: the old one is hidden and forgotten, pages start fresh and the new look opens on its start page (the first
-- module that is on; the database look: Items).
function UI:ApplySkin(skin)
    skin = Theme.ValidSkin(skin)
    if skin == "database" and Theme.skin ~= "database" then
        self.previousSkin = Theme.skin
        Theme.databaseClassic = self.previousSkin == "classic"
    elseif skin ~= "database" then
        Theme.databaseClassic = false
    end
    -- Database is a view, not a saved look; keep Modern or Classic as the next-login style.
    if skin ~= "database" then LJ.db.skin = skin end
    if Theme.skin == skin then return end
    local old = self.frame
    local wasShown = old and old:IsShown()
    self.switchingSkin = true
    Widgets.Menu.Close()
    if old then
        old:Hide()
        old:ClearAllPoints()
    end
    for _, page in pairs(self.pages) do self:ResetPage(page) end
    Theme.SetSkin(skin)
    Widgets.Menu.Reset()
    -- the new look's pages, from scratch
    self.pages = self.pageSets[skin]
    for _, page in pairs(self.pages) do self:ResetPage(page) end
    self.frame = nil
    self.state.page = nil
    if wasShown then self:Open("start") end
    self.switchingSkin = false
    LJ:Fire("SKIN_CHANGED", skin)
end

function UI:RefreshCurrent()
    if not self.frame or not self.frame:IsShown() then return end
    local page = self.pages[self.state.page]
    if page and page.root and page.root:IsShown() and page.Refresh then
        page:Refresh()
    end
    self:UpdateNav()
end

---------------------------------------------------------------------------
-- Global refresh triggers
---------------------------------------------------------------------------
-- (/lf debug names what refreshed the page)
local function RefreshFor(message)
    if UI.frame and UI.frame:IsShown() then LJ:Debug("refresh: %s", message) end
    UI:RefreshCurrent()
end
LJ:Listen("ITEMS_UPDATED", RefreshFor)
LJ:Listen("PLANS_CHANGED", RefreshFor)
LJ:Listen("SPEC_CHANGED", RefreshFor)
-- the classic title bar names the character, its level and spec
local function UpdateWho() if UI.frame and UI.frame.who then UI.frame.who:Update() end end
LJ:Listen("SPEC_CHANGED", UpdateWho)
LJ:Listen("PLAYER_CHANGED", UpdateWho)
LJ:Listen("EQUIPMENT_CHANGED", RefreshFor)
-- the sim Best in Slot changed what the sheet, the marks and For you show (Sim/SimBiS.lua), or the list's sources did
-- (UI/ListFilter.lua)
LJ:Listen("SIM_BIS_CHANGED", RefreshFor)
LJ:Listen("LIST_CHANGED", RefreshFor)
-- its progress: only the page's own progress text (Page:OnSimProgress) follows it
LJ:Listen("SIM_BIS_PROGRESS", function()
    if not (UI.frame and UI.frame:IsShown()) then return end
    local page = UI.pages[UI.state.page]
    if page and page.OnSimProgress and page.root and page.root:IsShown() then page:OnSimProgress() end
end)
LJ:Listen("BAGS_CHANGED", RefreshFor)
LJ:Listen("QUESTS_CHANGED", RefreshFor)
LJ:Listen("QUEST_REWARDS_CHANGED", RefreshFor)
LJ:Listen("PLAYER_CHANGED", RefreshFor)
LJ:Listen("SETTINGS_CHANGED", function(_, what)
    if not UI.frame then return end
    if what == "scale" or what == "position" then
        ApplyPosition(UI.frame)
    else
        UI:RefreshCurrent()
    end
end)
