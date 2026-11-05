-- Lootified - the window that shows while the simulator calculates. A sim only runs when the player presses Sim (the
-- Best in Slot sheet, For you, the simulator window); its fights take a few milliseconds of every frame (Sim/Jobs.lua),
-- so this window says what goes on: the progress, the time left, that the game can run a little slower meanwhile (the
-- calculation, not an error), and Stop. It shows once a sim runs longer than a moment, at the top of the screen over
-- everything and also with the main window closed (the sim Best in Slot goes on while the player plays), until the
-- fights end. It can be dragged elsewhere (for the session). The item check's few seconds of fights (Sim/ItemCheck.lua)
-- show their progress in its own box instead.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Sim = LJ.Sim
local C = Theme.COLORS

local Progress = {}
UI.SimProgress = Progress

local WIDTH, HEIGHT, PAD = 400, 168, 16
local DELAY = 0.5                    -- seconds of a sim before the window shows (a short one ends before)

-- The window in the active look (Progress.frame).
local function Create()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("TOP", 0, -60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Widgets.CreateShadow(f, 18, 0.75)
    f.panel = Widgets.CreatePopupPanel(f, 12)
    f.glyph = Widgets.Glyph(f, "lightning", 18, Theme.accent)
    f.glyph:SetPoint("TOPLEFT", PAD, -PAD - 2)
    f.title = Widgets.Text(f, "titleSmall", Theme.PANE.title)
    f.title:SetPoint("LEFT", f.glyph, "RIGHT", 8, 0)
    f.title:SetText(Theme.Case(L("The simulator is calculating")))
    f.percent = Widgets.Text(f, "titleSmall", C.text1, nil, "RIGHT")
    f.percent:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -PAD - 11)
    f.text = Widgets.Text(f, "bodySmall", C.text2)
    f.text:SetWordWrap(true)
    f.text:SetJustifyV("TOP")
    f.text:SetPoint("TOPLEFT", PAD, -PAD - 34)
    f.text:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 50)
    f.text:SetText(L("It fights with your gear many times over. Until it is done the game can run a little slower: that is the calculation, not an error."))
    f.bar = Widgets.CreateProgressBar(f, 6)
    f.bar:SetPoint("BOTTOMLEFT", PAD, PAD + 38)
    f.bar:SetPoint("BOTTOMRIGHT", -PAD, PAD + 38)
    f.stop = Widgets.CreateButton(f, "Stop", "ghost", "xCircle", nil, 26)
    f.stop:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.stop:SetScript("OnClick", function() Sim.Jobs.Cancel() end)
    f.status = Widgets.Text(f, "small", C.text3)
    f.status:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + 13)
    f.status:SetPoint("RIGHT", f.stop, "LEFT", -12, 0)
    Theme.OnAccent(f, function(_, r, g, b) f.glyph:SetVertexColor(r, g, b, 1) end)
    f.skin = Theme.skin
    f:Hide()
    return f
end

local driver = CreateFrame("Frame")
local waited, active                 -- seconds since the sim started; seconds its fights ran (combat pauses them)

-- The time left from the pace so far, "" until it can tell.
local function TimeLeft(p)
    if p < 0.05 or active < 1 then return "" end
    local left = active * (1 - p) / p
    if left >= 90 then return F(L("About %d min left"), math.floor(left / 60 + 0.5)) end
    return F(L("About %d s left"), math.max(1, math.floor(left + 0.5)))
end

local function Update(_, elapsed)
    local p = Sim.Jobs.Progress()
    local fighting = InCombatLockdown()
    waited = waited + elapsed
    if not fighting then active = active + elapsed end
    if waited < DELAY then return end
    local f = Progress.frame
    if not (f and f.skin == Theme.skin) then
        if f then f:Hide() end
        f = Create()
        Progress.frame = f
    end
    f:Show()
    f.bar:SetProgress(p)
    f.percent:SetText(F("%d%%", math.floor(p * 100)))
    f.status:SetText(fighting and L("Paused while you are in combat.") or TimeLeft(p))
end

LJ:Listen("SIM_JOB_STARTED", function(_, job)
    if job.quiet then return end
    waited, active = 0, 0
    driver:SetScript("OnUpdate", Update)
end)
LJ:Listen("SIM_JOB_ENDED", function()
    driver:SetScript("OnUpdate", nil)
    if Progress.frame then Progress.frame:Hide() end
end)
