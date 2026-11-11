-- Lootified - why a sim does not run: a press of a Sim button that cannot run opens this popup with the reason. The
-- Best in Slot sim's buttons (For you, the Best in Slot sheet, the tour: nothing to sim at the character's level, no
-- pet, not in its form ..., Sim/SimBiS.lua: SIM_BIS_REFUSED) and the simulator window's Sim (a character it cannot read,
-- a set that cannot fight, fights that stopped). It lies above the windows and the tour (the fullscreen dialog layer,
-- as the sim speed question); OK, its close button or Escape closes it.
local _, LJ = ...
local L = LJ.L

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local C = Theme.COLORS

local Notice = {}
UI.SimNotice = Notice

local WIDTH, PAD, BUTTON = 400, 16, 30
local NAME = "LootifiedSimNotice"     -- Escape closes it (UISpecialFrames)

-- The popup in the active look (Notice.frame).
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
    f.glyph = Widgets.Glyph(f, "lightning", 18, Theme.accent)
    f.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    f.title = Widgets.Text(f, "titleSmall", Theme.PANE.title)
    f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
    f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetWidth(WIDTH - PAD * 2)
    f.text:SetWordWrap(true)
    f.ok = Widgets.CreateButton(f, "OK", "primary", nil, nil, BUTTON)
    f.ok:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -16)
    f.ok:SetScript("OnClick", function() f:Hide() end)
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    f.skin = Theme.skin
    f:Hide()
    if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    return f
end

-- Shows the reason under a title (both in the client's language).
function Notice:Show(title, text)
    local f = self.frame
    if not (f and f.skin == Theme.skin) then
        if f then f:Hide() end
        f = Create()
        self.frame = f
    end
    f.title:SetText(Theme.Case(title))
    f.text:SetText(text)
    f:SetHeight(math.floor(PAD + 34 + f.text:GetStringHeight() + 16 + BUTTON + PAD + 0.5))
    f:Show()
    f:Raise()
end

LJ:Listen("SIM_BIS_REFUSED", function(_, text) Notice:Show(L("Best in Slot sim"), text) end)
