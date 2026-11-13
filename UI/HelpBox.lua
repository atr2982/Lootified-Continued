-- Lootified - help and links: the ? in the top bar of the main window (UI/MainFrame.lua) opens it. Lootified's
-- homepage and Discord in lines to copy (an addon cannot open a browser): a click on a line selects it, Ctrl+C copies
-- it; typing does not change it. OK, the close button or Escape closes it. It lies above the windows (the fullscreen
-- dialog layer, as the sim notice).
local _, LJ = ...
local L = LJ.L

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local C = Theme.COLORS

local Help = {}
UI.HelpBox = Help

Help.LINKS = {
    { label = "Project on GitHub", url = "https://github.com/atr2982/LootifiedContinued" },
    { label = "Data from ForeverDB.net", url = "https://foreverdb.net" },
}

local WIDTH, PAD, LINE, BUTTON = 400, 16, 28, 30
local NAME = "LootifiedHelp"     -- Escape closes it (UISpecialFrames)

-- A line to copy: the link stays as it is, all of it selected on a click.
local function CreateLine(f, url)
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(WIDTH - PAD * 2, LINE)
    box:SetAutoFocus(false)
    box:SetFontObject(Theme.Font("bodySmall"))
    box:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
    box:SetTextInsets(9, 9, 0, 0)
    Widgets.InputPanel(box)
    box:SetText(url)
    box:SetScript("OnTextChanged", function(b, userInput)
        if userInput then
            b:SetText(url)
            b:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
    box:SetScript("OnMouseUp", function(b) b:HighlightText() end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    box.url = url
    return box
end

-- The popup in the active look (Help.frame).
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
    f.glyph = Widgets.Glyph(f, "question", 18, Theme.accent)
    f.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    f.title = Widgets.Text(f, "titleSmall", Theme.PANE.title)
    f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
    f.title:SetText(Theme.Case(L("Help & links")))
    f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetWidth(WIDTH - PAD * 2)
    f.text:SetWordWrap(true)
    f.text:SetText("Found a bug or have an idea? Visit the Lootified project on GitHub.")
    local height = PAD + 34 + f.text:GetStringHeight()
    local above = f.text
    f.lines = {}
    for i, link in ipairs(Help.LINKS) do
        local label = Widgets.Text(f, "label", Theme.PANE.section)
        label:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -14)
        label:SetText(Util.Upper(L(link.label)))
        local box = CreateLine(f, link.url)
        box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        f.lines[i] = box
        above = box
        height = height + 14 + label:GetStringHeight() + 6 + LINE
    end
    f.foot = Widgets.Text(f, "small", C.text3)
    f.foot:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -12)
    f.foot:SetWidth(WIDTH - PAD * 2)
    f.foot:SetWordWrap(true)
    f.foot:SetText(L("Click a link, press Ctrl+C to copy it, then paste it into your browser."))
    f.ok = Widgets.CreateButton(f, "OK", "primary", nil, nil, BUTTON)
    f.ok:SetPoint("TOPLEFT", f.foot, "BOTTOMLEFT", 0, -16)
    f.ok:SetScript("OnClick", function() f:Hide() end)
    f:SetHeight(math.floor(height + 12 + f.foot:GetStringHeight() + 16 + BUTTON + PAD + 0.5))
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    -- closed: the keyboard goes back to the game
    f:SetScript("OnHide", function()
        for _, box in ipairs(f.lines) do box:ClearFocus() end
    end)
    f.skin = Theme.skin
    f:Hide()
    if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    return f
end

function Help:Show()
    local f = self.frame
    if not (f and f.skin == Theme.skin) then
        if f then f:Hide() end
        f = Create()
        self.frame = f
    end
    f:Show()
    f:Raise()
end
