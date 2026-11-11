-- Lootified - the sim speed, asked once: the first press of Sim (For you, the simulator window) asks how fast the
-- simulator calculates, Smooth, Fast or Turbo (Sim/Jobs.lua), and says that the settings (General) change it later;
-- the pick sims at once. Closed without a pick, nothing is simmed and the next press asks again.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local C = Theme.COLORS

local Speed = {}
UI.SimSpeed = Speed

local WIDTH, PAD = 420, 16
local NAME = "LootifiedSimSpeed"     -- Escape closes it (UISpecialFrames)

-- The speeds in their order (their milliseconds per frame: Sim.Jobs.BUDGET): the dialog's buttons, the settings' chips.
Speed.OPTIONS = { { key = "smooth", text = "Smooth" }, { key = "fast", text = "Fast" }, { key = "turbo", text = "Turbo" } }

-- What each speed does, a line each.
function Speed.Explain()
    local ms = LJ.Sim.Jobs.BUDGET
    return F(L("Smooth: %d ms per frame, the game stays the smoothest."), ms.smooth) .. "\n"
        .. F(L("Fast: %d ms per frame, the sim is done sooner, the game can run a little slower meanwhile."), ms.fast) .. "\n"
        .. F(L("Turbo: %d ms per frame, the sim is done soonest, the game can run slower meanwhile."), ms.turbo)
end

-- The dialog in the active look (Speed.frame).
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
    f.title:SetText(Theme.Case(L("Sim speed")))
    f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetWidth(WIDTH - PAD * 2)
    f.text:SetWordWrap(true)
    f.text:SetText(L("How fast should the sim calculate?") .. "\n\n" .. Speed.Explain())
    -- a button per speed, the first one stands out
    f.buttons = {}
    local last
    for i, opt in ipairs(Speed.OPTIONS) do
        local b = Widgets.CreateButton(f, opt.text, i == 1 and "primary" or "ghost", nil, nil, 30)
        if last then
            b:SetPoint("LEFT", last, "RIGHT", 8, 0)
        else
            b:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -16)
        end
        b:SetScript("OnClick", function() Speed:Choose(opt.key) end)
        f.buttons[opt.key] = b
        last = b
    end
    f.foot = Widgets.Text(f, "small", C.text3)
    f.foot:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -16 - 30 - 14)
    f.foot:SetWidth(WIDTH - PAD * 2)
    f.foot:SetWordWrap(true)
    f.foot:SetText(L("You can change it any time in the settings (the sliders icon, General)."))
    f:SetHeight(math.floor(PAD + 34 + f.text:GetStringHeight() + 16 + 30 + 14 + f.foot:GetStringHeight() + PAD + 0.5))
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    -- closed (its button, Escape) without a pick: nothing is simmed
    f:SetScript("OnHide", function() f.run = nil end)
    f.skin = Theme.skin
    f:Hide()
    if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    return f
end

-- run() starts the sim: at once when a sim speed is chosen, else once the player picks one.
function Speed:Then(run)
    if LJ.db.sim.speed then
        run()
        return
    end
    local f = self.frame
    if not (f and f.skin == Theme.skin) then
        if f then f:Hide() end
        f = Create()
        self.frame = f
    end
    f.run = run
    f:Show()
    f:Raise()
end

function Speed:Choose(speed)
    Util.PlaySound("IG_MAINMENU_OPTION")
    local f = self.frame
    local run = f.run
    LJ.db.sim.speed = speed
    LJ:Fire("SETTINGS_CHANGED", "simSpeed")
    f:Hide()
    run()
end
