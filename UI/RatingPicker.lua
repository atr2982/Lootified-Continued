-- Lootified - how a character's items are rated (LJ.cdb.rating), the one switch of UI.Sim.RanksItems: "percent" (every
-- spec by its stat weights) or "sim" (every spec by the simulator's DPS, tanks and healers by their damage; the sim Best
-- in Slot counts only here: Sim/SimBiS.lua). The question: the first start asks it after the look
-- (UI/LayoutPicker.lua), every other character once a few seconds after its login; the settings (General) change it
-- later. Two ways side by side; a click on one (its card or its button) picks it. Below them what the Best in Slot list
-- may use (UI/ListFilter.lua: realistic to start with; a chip changes it at once). Closed without a pick (its close
-- button, Escape), a second popup asks to agree to Percent ("Go back" shows the choice again). Both lie above the
-- windows (the fullscreen dialog layer, as the sim notice).
local _, LJ = ...
local L = LJ.L

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local C = Theme.COLORS

local Picker = {}
UI.RatingPicker = Picker

-- the ways, left to right (tip: who it is for): Standard (Percent) for every role, Advanced (Sim, a Beta) for players
-- who want to run sims themselves; the titles name the ways as the settings do in brackets
Picker.WAYS = {
    { key = "percent", glyph = "chartUp", title = "Standard (Percent)", sub = "By your stat weights", button = "Use Standard",
      tip = "For tanks, DPS and healers",
      text = "Every upgrade in percent by your spec's stat weights, right away and with nothing to run." },
}

-- the settings' chips (UI/Settings.lua)
Picker.OPTIONS = { { key = "percent", text = "Percent" } }

local WIDTH, PAD, GAP, BUTTON = 600, 16, 12, 30
local CARD = (WIDTH - PAD * 2 - GAP) / 2
local NAME = "LootifiedRatingPicker"     -- Escape closes it (UISpecialFrames)
local ASK, ASK_WIDTH = "LootifiedRatingAsk", 400

local function WayVisual(b)
    Widgets.BoxFill(b.fill, b.ring, "row", b.hovered)
end

-- A way's card: its glyph, name (a Beta: its tag beside it) and what it rates by, who it is for, what it does, its
-- button.
local function CreateWay(f, way)
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(CARD)
    b.fill = Widgets.CreateBox(b, "BACKGROUND", 1, 8)
    b.ring = Widgets.CreateBox(b, "BACKGROUND", 2, 8, true)
    b.glyph = Widgets.Glyph(b, way.glyph, 22, Theme.accent)
    b.glyph:SetPoint("TOPLEFT", 14, -15)
    b.title = Widgets.Text(b, "h2", C.white)
    b.title:SetPoint("TOPLEFT", 46, -13)
    b.title:SetText(L(way.title))
    if way.beta then
        b.beta = Widgets.CreatePill(b, 18, "pillTiny")
        b.beta:Set("Beta", "blue")
        b.beta:SetPoint("LEFT", b.title, "RIGHT", 8, 0)
    end
    b.sub = Widgets.Text(b, "small", C.text3)
    b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -2)
    b.sub:SetText(L(way.sub))
    b.tip = Widgets.Text(b, "smallSemi", C.okText)
    b.tip:SetPoint("TOPLEFT", 14, -52)
    b.tip:SetWidth(CARD - 28)
    b.tip:SetWordWrap(true)
    b.tip:SetText(Theme.GlyphString("checkCircle", 12, C.okText) .. " " .. L(way.tip))
    b.text = Widgets.Text(b, "bodySmall", C.text2)
    b.text:SetPoint("TOPLEFT", b.tip, "BOTTOMLEFT", 0, -6)
    b.text:SetWidth(CARD - 28)
    b.text:SetWordWrap(true)
    b.text:SetText(L(way.text))
    b.button = Widgets.CreateButton(b, way.button, "accent", nil, CARD - 28, BUTTON)
    b.button:SetPoint("BOTTOM", 0, 14)
    local function Enter() b.hovered = true WayVisual(b) end
    local function Leave() b.hovered = false WayVisual(b) end
    local function Choose()
        Util.PlaySound("IG_MAINMENU_OPTION")
        Picker:Choose(way.key)
    end
    b:SetScript("OnEnter", Enter)
    b:SetScript("OnLeave", Leave)
    b:SetScript("OnClick", Choose)
    b.button:HookScript("OnEnter", Enter)
    b.button:HookScript("OnLeave", Leave)
    b.button:SetScript("OnClick", Choose)
    Theme.OnAccent(b, function(x, r, g, bl) x.glyph:SetVertexColor(r, g, bl, 1) end)
    WayVisual(b)
    return b
end

-- The popup in the active look (Picker.frame): the cards as tall as the taller text needs.
local function Create()
    local f = CreateFrame("Frame", NAME, UIParent)
    f:SetWidth(WIDTH)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Widgets.CreateShadow(f, 18, 0.75)
    f.panel = Widgets.CreatePopupPanel(f, 12)
    f.glyph = Widgets.Glyph(f, "chartUp", 18, Theme.accent)
    f.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    f.title = Widgets.Text(f, "titleSmall", Theme.PANE.title)
    f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
    f.title:SetText(Theme.Case(L("How should Lootified rate items?")))
    f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetWidth(WIDTH - PAD * 2)
    f.text:SetWordWrap(true)
    f.text:SetText(L("This decides how this character's upgrades show in tooltips, loot rolls, For you and its Best in Slot list."))
    local top = PAD + 34 + f.text:GetStringHeight() + 14
    f.ways = {}
    local tall = 0
    for i, way in ipairs(Picker.WAYS) do
        local b = CreateWay(f, way)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (CARD + GAP), -top)
        f.ways[i] = b
        tall = math.max(tall, b.tip:GetStringHeight() + 6 + b.text:GetStringHeight())
    end
    local height = math.floor(52 + tall + 16 + BUTTON + 14 + 0.5)
    for _, b in ipairs(f.ways) do b:SetHeight(height) end
    top = top + height + 12
    f.list = UI.ListFilter.CreateListBox(f, WIDTH - PAD * 2,
        "Picked for you: what you can really get at your level. Standard and Advanced both use it; the filter on the Best in Slot page changes it any time.")
    f.list:SetPoint("TOPLEFT", PAD, -top)
    top = top + f.list:GetHeight() + 12
    f.foot = Widgets.Text(f, "small", C.text3)
    f.foot:SetPoint("TOPLEFT", PAD, -top)
    f.foot:SetWidth(WIDTH - PAD * 2)
    f.foot:SetWordWrap(true)
    f.foot:SetText(L("You can change how items are rated any time in the settings (the sliders icon, General)."))
    f:SetHeight(math.floor(top + f.foot:GetStringHeight() + PAD + 0.5))
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    f.skin = Theme.skin
    f:Hide()
    -- closed (once shown): the way picked is kept, else the confirm popup asks
    f:SetScript("OnHide", function()
        -- the whole interface hidden (Alt+Z, a cinematic): it comes back with it, nothing is picked
        if not UIParent:IsShown() then return end
        local picked = Picker.picked
        Picker.picked = nil
        if picked then Picker:Done(picked) else Picker:Confirm() end
    end)
    if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    return f
end

-- A question with two answers (Picker.ask): q = { glyph, title, text, ok, back, onOk, onBack }; ok is the main button,
-- back (also its close by Escape) runs onBack.
local function CreateAsk()
    local c = CreateFrame("Frame", ASK, UIParent)
    c:SetWidth(ASK_WIDTH)
    c:SetPoint("CENTER", 0, 60)
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    c:SetToplevel(true)
    c:SetClampedToScreen(true)
    c:EnableMouse(true)
    Widgets.CreateShadow(c, 18, 0.75)
    c.panel = Widgets.CreatePopupPanel(c, 12)
    c.glyph = Widgets.Glyph(c, "chartUp", 18, Theme.accent)
    c.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    c.title = Widgets.Text(c, "titleSmall", Theme.PANE.title)
    c.title:SetPoint("LEFT", c.glyph, "RIGHT", 8, 0)
    c.text = Widgets.Text(c, "bodySmall", C.text2)
    c.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    c.text:SetWidth(ASK_WIDTH - PAD * 2)
    c.text:SetWordWrap(true)
    c.ok = Widgets.CreateButton(c, nil, "primary", nil, nil, BUTTON)
    c.ok:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -16)
    c.ok:SetScript("OnClick", function()
        c.agreed = true
        c:Hide()
    end)
    c.back = Widgets.CreateButton(c, nil, "ghost", nil, nil, BUTTON)
    c.back:SetPoint("LEFT", c.ok, "RIGHT", 8, 0)
    c.back:SetScript("OnClick", function() c:Hide() end)
    Theme.OnAccent(c, function(_, r, g, b) c.glyph:SetVertexColor(r, g, b, 1) end)
    c.skin = Theme.skin
    c:Hide()
    -- closed (once shown): its answer
    c:SetScript("OnHide", function()
        if not UIParent:IsShown() then return end
        local q, agreed = c.q, c.agreed
        c.q, c.agreed = nil, nil
        local answer = agreed and q.onOk or q.onBack
        if answer then answer() end
    end)
    if not tContains(UISpecialFrames, ASK) then tinsert(UISpecialFrames, ASK) end
    return c
end

-- Shows the question; after() runs once a way is set (picked, or Percent agreed to).
function Picker:Show(after)
    local f = self.frame
    if not (f and f.skin == Theme.skin) then
        if f then
            f:SetScript("OnHide", nil)
            f:Hide()
        end
        f = Create()
        self.frame = f
    end
    self.after = after
    f:Show()
    f:Raise()
end

function Picker:Choose(key)
    self.picked = key
    self.frame:Hide()
end

-- Asks a question with two answers (CreateAsk).
function Picker:Ask(q)
    local c = self.ask
    if not (c and c.skin == Theme.skin) then
        if c then
            c:SetScript("OnHide", nil)
            c:Hide()
        end
        c = CreateAsk()
        self.ask = c
    end
    c:Hide()
    c.q = q
    Theme.SetGlyph(c.glyph, q.glyph)
    c.title:SetText(Theme.Case(L(q.title)))
    c.text:SetText(L(q.text))
    c.ok:SetLabel(q.ok)
    c.back:SetLabel(q.back)
    c:SetHeight(math.floor(PAD + 34 + c.text:GetStringHeight() + 16 + BUTTON + PAD + 0.5))
    c:Show()
    c:Raise()
end

-- The question closed without a pick: agree to Percent, or the choice again.
function Picker:Confirm()
    self:Ask({ glyph = "chartUp", title = "Use Percent?",
        text = "Without a choice, Lootified rates your items in Percent. You can change it any time in the settings (the sliders icon, General).",
        ok = "Use Percent", back = "Go back",
        onOk = function() self:Done("percent") end,
        onBack = function() self.frame:Show() end })
end

-- A way is set by the question: kept, then what came after it.
function Picker:Done(key)
    self:Set(key)
    local after = self.after
    self.after = nil
    if after then after() end
end

-- How items are rated from now on (the question, the settings). Percent stops a running Best in Slot sim
-- and an item's fights (their numbers do not count there); what shows the sim's numbers follows (SIM_BIS_CHANGED: the
-- sheet, the marks, For you, the loot boxes, the tour, the simulator).
function Picker:Set(key)
    assert(key == "percent", "Lootified only supports percent scoring")
    LJ.cdb.rating = "percent"
    if key == "percent" then
        LJ.SimBiS.Cancel()
        LJ.ItemCheck.Stop()
    end
    LJ:Fire("SIM_BIS_CHANGED")
end

-- After the look (UI/LayoutPicker.lua): the question while nothing is picked, then after(); else after() at once.
function Picker:AskFirst(after)
    if LJ.cdb.rating then
        if after then after() end
        return
    end
    self:Show(after)
end

-- A character without a rating while the look is picked already (another character of the account, or one from before
-- the question): the question once, a few seconds after the login (after a fight, when it starts in one). A new player
-- gets it after the look.
local pending = false
function Picker:AskOnLogin()
    if LJ.cdb.rating or not LJ.db.layoutChosen or (self.frame and self.frame:IsShown()) then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    self:Show()
end
LJ:Listen("LOGIN", function() C_Timer.After(4, function() Picker:AskOnLogin() end) end)
LJ:On("PLAYER_REGEN_ENABLED", function()
    if pending then
        pending = false
        C_Timer.After(1, function() Picker:AskOnLogin() end)
    end
end)
