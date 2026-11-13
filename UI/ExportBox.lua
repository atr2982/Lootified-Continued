-- Lootified - the export box (/lf export, Sim/Export.lua): the text of the character for Lootified's web simulator in
-- a line to copy, selected with the keyboard on it (Ctrl+C copies it); typing does not change it. Escape or the close
-- button closes it.
local _, LJ = ...
local L = LJ.L

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local C = Theme.COLORS

local Box = {}
UI.ExportBox = Box

local WIDTH, PAD, LINE = 460, 16, 28
local NAME = "LootifiedExport"     -- Escape closes it (UISpecialFrames)

-- The box in the active look (Box.frame).
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
    f.glyph = Widgets.Glyph(f, "link", 18, Theme.accent)
    f.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    f.title = Widgets.Text(f, "titleSmall", Theme.PANE.title)
    f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
    f.title:SetText(Theme.Case(L("Export character")))
    f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetWidth(WIDTH - PAD * 2)
    f.text:SetWordWrap(true)
    f.text:SetText(L("Character export is disabled in this version of Lootified."))
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(WIDTH - PAD * 2, LINE)
    box:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -14)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject(Theme.Font("bodySmall"))
    box:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
    box:SetTextInsets(9, 9, 0, 0)
    Widgets.InputPanel(box)
    -- the text stays as it is, all of it selected
    box:SetScript("OnTextChanged", function(b, userInput)
        if userInput then b:SetText(f.export or "") end
        b:HighlightText()
    end)
    box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
    box:SetScript("OnMouseUp", function(b) b:HighlightText() end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.box = box
    f.foot = Widgets.Text(f, "small", C.text3)
    f.foot:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12)
    f.foot:SetWidth(WIDTH - PAD * 2)
    f.foot:SetWordWrap(true)
    f.foot:SetText(L("Your name and realm are not in it. Export again after you change your gear or talents."))
    f:SetHeight(math.floor(PAD + 34 + f.text:GetStringHeight() + 14 + LINE + 12 + f.foot:GetStringHeight() + PAD + 0.5))
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    -- closed: the text goes (it is long)
    f:SetScript("OnHide", function()
        f.export = nil
        box:ClearFocus()
        box:SetText("")
    end)
    f.skin = Theme.skin
    f:Hide()
    if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    return f
end

-- Shows the export text, selected, the keyboard on it.
function Box:Show(text)
    local f = self.frame
    if not (f and f.skin == Theme.skin) then
        if f then f:Hide() end
        f = Create()
        self.frame = f
    end
    f:Show()
    f:Raise()
    f.export = text
    f.box:SetText(text)
    f.box:SetFocus()
    f.box:HighlightText()
end
