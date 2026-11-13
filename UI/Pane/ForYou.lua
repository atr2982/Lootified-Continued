-- Lootified - For you in the classic and the modern look. On top the next step: the dungeon with the most upgrades for
-- the character (the journal's featured card). Below it on the left the character: portrait, level and experience (the
-- rested part after it) and its Best in Slot set as icons to collect; on the right the next three upgrades, one per
-- slot (the item, where it drops, the damage it adds) with the Best in Slot sim in their title (its progress, what it
-- found, run it again) and, at the bottom, more dungeons for its level as pictures. No Best in Slot sim yet (a spec the
-- simulator plays, with Sim): in the upgrades' place a card that runs it. Percent: in the upgrades' title All upgrades
-- and a Best in Slot sim button that offers the switch to Sim (UI/RatingPicker.lua). With the Best in Slot module off:
-- no set, no sim; in the upgrades' place a note that it is off and a button that switches it on.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local Lists = LJ.Lists
local C = Theme.COLORS
local P = Theme.PANE

local Page = {}

local GAP = 12
local LEFT_WIDTH = 350
local INNER = LEFT_WIDTH - 24           -- the left panel's inner width (Kit.Panel pads 12 on each side)
local SET_COLUMNS, SET_ICON, SET_GAP, SET_TOP = 7, 38, 8, 160
local UPGRADES, TILES = 3, 3
local XP_COLOR = { 0.58, 0.4, 0.95, 1 }             -- the game's experience bar
local RESTED_COLOR = { 0.32, 0.52, 0.96, 0.6 }

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function Page:Create(root)
    root = Kit.Page(root)
    -- the next step: the journal's featured card (the "feature" kind of UI/Pane/Journal.lua)
    local heroHeight = Kit.KINDS.feature.height
    self.hero = Kit.Sheet(root)
    self.hero.scroll:SetPoint("TOPLEFT")
    self.hero.scroll:SetPoint("TOPRIGHT")
    self.hero.scroll:SetHeight(heroHeight)
    local left = Kit.Panel(root)
    left:SetPoint("TOPLEFT", 0, -heroHeight)
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_WIDTH)
    self:CreateCharacter(left.inner)
    local right = Kit.Panel(root)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    -- more dungeons for the level at the bottom of the panel (one row of pictures), the next upgrades above them
    self.dungeons = Kit.Sheet(right.inner)
    self.dungeons.scroll:SetPoint("BOTTOMLEFT")
    self.dungeons.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    self.dungeons.scroll:SetHeight(Kit.M().section + Kit.KINDS.tile.height)
    self.upgrades = Kit.Sheet(right.inner)
    self.upgrades.scroll:SetPoint("TOPLEFT")
    self.upgrades.scroll:SetPoint("BOTTOMRIGHT", self.dungeons.scroll, "TOPRIGHT")
end

-- The character: portrait with the level, name, class, spec and zone, experience, the Best in Slot set.
function Page:CreateCharacter(pane)
    self.pane = pane
    local face = CreateFrame("Button", nil, pane)
    face:SetSize(56, 56)
    face:SetPoint("TOPLEFT", 6, -6)
    face.portrait = face:CreateTexture(nil, "ARTWORK")
    face.portrait:SetAllPoints()
    face.mask = face:CreateMaskTexture()
    face.mask:SetTexture(Theme.TEX.maskCircle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    face.mask:SetAllPoints(face.portrait)
    face.portrait:AddMaskTexture(face.mask)
    face.ring = face:CreateTexture(nil, "OVERLAY")
    face.ring:SetPoint("TOPLEFT", -4, 4)
    face.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    if Theme.IsClassic() then
        face.ring:SetTexture(Theme.TEX.classicRing)
    else
        face.ring:SetTexture(Theme.TEX.circleRing)
        Theme.OnAccent(face, function(x, r, g, b) x.ring:SetVertexColor(r, g, b, 0.95) end)
    end
    face.badge = Kit.Badge(face, 22)
    face.badge:SetPoint("CENTER", face, "BOTTOMLEFT", 6, 6)
    self.face = face
    self.name = Widgets.Text(pane, "title", P.title)
    self.name:SetPoint("TOPLEFT", face, "TOPRIGHT", 14, -6)
    self.sub = Widgets.Text(pane, "bodySmall", C.text3)
    self.sub:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -5)
    self.sub:SetWidth(INNER - 80)

    -- level and experience: the rested experience as a lighter part after it
    self.xpLabel = Widgets.Text(pane, "small", C.text2)
    self.xpLabel:SetPoint("TOPLEFT", 4, -80)
    self.xpText = Widgets.Text(pane, "small", C.text3, nil, "RIGHT")
    self.xpText:SetPoint("TOPRIGHT", -4, -80)
    self.xpBar = Widgets.CreateProgressBar(pane, 8)
    self.xpBar:SetPoint("TOPLEFT", 4, -98)
    self.xpBar:SetWidth(INNER - 8)
    self.rested = self.xpBar:CreateTexture(nil, "ARTWORK", nil, -1)
    self.rested:SetTexture(Theme.RoundFile(4))
    self.rested:SetPoint("TOPLEFT", self.xpBar.fill, "TOPRIGHT")
    self.rested:SetPoint("BOTTOMLEFT", self.xpBar.fill, "BOTTOMRIGHT")
    self.rested:SetVertexColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], RESTED_COLOR[4])
    local line = Kit.FadeLine(pane, 0.55)
    line:SetPoint("TOPLEFT", 0, -122)
    line:SetPoint("TOPRIGHT", 0, -122)

    -- the Best in Slot set: one icon per pick, the owned ones bright
    -- like the section titles: the classic heading, the modern label in capitals
    self.setTitle = Widgets.Text(pane, Theme.IsClassic() and "h2" or "label", Kit.SectionColor())
    self.setTitle:SetPoint("TOPLEFT", 4, -136)
    self.setTitle:SetText(Theme.Case(L("Your Best in Slot set")))
    self.setCount = Widgets.Text(pane, "small", C.text4)
    self.setCount:SetPoint("LEFT", self.setTitle, "RIGHT", 8, 0)
    self.setIcons = {}
    -- without a spec: a hint in place of the icons
    self.hint = Widgets.Text(pane, "small", C.text3)
    self.hint:SetPoint("TOPLEFT", 4, -SET_TOP)
    self.hint:SetWidth(INNER - 8)
    self.hint:SetText(L("Pick a spec on the Best in Slot page."))
end

-- An icon of the Best in Slot set (made on first use): tooltip, a click opens the item.
function Page:SetIcon(i)
    local icon = self.setIcons[i]
    if icon then return icon end
    icon = Widgets.CreateItemIcon(self.pane, SET_ICON)
    icon:SetScript("OnEnter", function(b) Widgets.ShowItemTooltip(b, b.itemID) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", function(b, button)
        if Items.HandleClick(b.itemID, button) then return end
        Util.PlaySound("IG_MAINMENU_OPTION")
        UI:Open("item", b.itemID)
    end)
    local col, row = (i - 1) % SET_COLUMNS, math.floor((i - 1) / SET_COLUMNS)
    icon:SetPoint("TOPLEFT", 4 + col * (SET_ICON + SET_GAP), -(SET_TOP + row * (SET_ICON + SET_GAP)))
    self.setIcons[i] = icon
    return icon
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function Page:RefreshCharacter()
    local spec, zone = self.spec, self.zone
    local level = Player.level or 1
    local face = self.face
    SetPortraitTexture(face.portrait, "player")
    face.badge.text:SetText(tostring(level))
    self.name:SetText(Theme.Case(UnitName("player") or ""))
    local parts = { Util.ClassName(Player.class or "WARRIOR") }
    if spec then parts[#parts + 1] = L(spec.name) end
    if zone then parts[#parts + 1] = zone.name end
    self.sub:SetText(table.concat(parts, " · "))

    -- experience (none at the highest level)
    local max = UnitXPMax("player") or 0
    self.xpLabel:SetText(F("Level %d", level))
    if level >= LJ.BiS.MAX_LEVEL or max <= 0 then
        self.xpText:SetText(L("Max level"))
        self.xpBar:SetProgress(1, XP_COLOR)
        self.rested:Hide()
    else
        local xp = UnitXP("player") or 0
        local rested = GetXPExhaustion() or 0
        local pct = math.floor(xp / max * 100)
        self.xpText:SetText(F(rested > 0 and "%d%% to level %d · rested" or "%d%% to level %d", pct, level + 1))
        self.xpBar:SetProgress(xp / max, XP_COLOR)
        local w = math.min(rested, max - xp) / max * self.xpBar:GetWidth()
        self.rested:SetShown(w >= 1)
        self.rested:SetWidth(math.max(1, w))
    end

    -- the set (none with the Best in Slot module off)
    local bis = LJ.Modules.On("bis")
    self.setTitle:SetShown(bis)
    self.setCount:SetShown(bis)
    local picks = bis and spec and LJ.BiS.GetPicks(spec) or {}
    local owned = 0
    for i, p in ipairs(picks) do
        local icon = self:SetIcon(i)
        local have = Items.IsOwned(p.id)
        if have then owned = owned + 1 end
        icon.itemID = p.id
        icon:SetItem(p.id)
        icon:SetOwned(have)
        icon.icon:SetDesaturated(not have)
        icon:SetAlpha(have and 1 or 0.55)
        icon:Show()
    end
    for i = #picks + 1, #self.setIcons do self.setIcons[i]:Hide() end
    self.setShown = #picks
    self.setCount:SetText(#picks > 0 and F("%d of %d", owned, #picks) or "")
    self.hint:SetShown(bis and not spec)
end

-- No sim Best in Slot (Sim/SimBiS.lua) of the spec yet and none running for it: a card in the upgrades' place (as the
-- note when Best in Slot is off) says the list is an estimate until then, with the button that runs it. Returns
-- whether it is there.
function Page:SimCard(spec)
    if LJ.NO_SIM then return false end
    local SimBiS = LJ.SimBiS
    local run = SimBiS.running
    if SimBiS.Get(spec) or (run and run.spec.key == spec.key) then return false end
        self.upgrades:Add("empty", { title = L("Best in Slot percent list"), glyph = "chartUp",
        text = L("Your Best in Slot list is calculated from your spec's stat weights, then your next upgrades show here."),
        button = "Refresh Best in Slot", buttonGlyph = "refresh", primary = true,
        onClick = function()
            Util.PlaySound("IG_MAINMENU_OPTION")
            UI.SimSpeed:Then(function() SimBiS.Start(spec) end)
        end })
    return true
end

-- Why the last sim stopped (an error in its fights; a press it refuses says why in a popup: UI/SimNotice.lua).
function Page:SimProblem()
    local problem = LJ.SimBiS.problem
    if problem then self.upgrades:Add("text", { text = problem, font = "bodySmall", color = C.bad, pad = 6 }) end
end

-- The sim Best in Slot of a spec the simulator plays (built or running: else SimCard), in the upgrades' section title
-- (d): its progress while it runs, else what it found, with "All upgrades" (the Best in Slot sheet); its button as on
-- the sheet (UI.BiSSimButton: Stop, "Up to date" or the sim).
function Page:SimSection(d, spec)
    local SimBiS = LJ.SimBiS
    local function Count(t) d.count = d.count and (d.count .. " · " .. t) or t end
    local run = SimBiS.running
    local mine = run and run.spec.key == spec.key
    local rec = SimBiS.Get(spec)
    if mine then
        Count(F(L("Percent %d%%"), math.floor(run.progress * 100)))
    elseif SimBiS.IsOutdated(rec) then
        Count(L("percent list outdated"))
    else
        Count(F(L("percent: +%.1f%%"), rec.gain))
    end
    local s = UI.BiSSimButton(spec)
    local sim = { text = s.text, glyph = s.glyph, onClick = function() UI.PressBiSSim(spec) end,
        tooltip = "Best in Slot sim", tooltipText = s.tip }
    d.actions = mine and { sim } or { { text = "All upgrades", glyph = "list", onClick = function() UI:Open("bis") end }, sim }
end

-- The sim Best in Slot moves on: its section follows.
function Page:OnSimProgress()
    self:RefreshUpgrades()
end

-- The next upgrades: per slot the item the sim found best (Lists.NextUpgrades), the biggest upgrade first (at most
-- three; the title counts all of them). A click opens the item.
function Page:RefreshUpgrades()
    local spec = self.spec
    local sheet = self.upgrades
    sheet:Reset(UI:ContentWidth() - LEFT_WIDTH - GAP - 32)
    if not LJ.Modules.On("bis") then
        sheet:Add("empty", { title = L("Best in Slot is off"),
            text = L("Switch it on for your Best in Slot set, the next upgrades and the percent upgrade check for loot. The settings have it too (Modules)."),
            glyph = "crown", button = "Switch on Best in Slot", buttonGlyph = "crown", onClick = function()
                Util.PlaySound("IG_MAINMENU_OPTION")
                LJ.Modules.Set("bis", true)
            end })
        sheet:Finish(4)
        return
    end
    -- (the Best in Slot sim builds the lists of Sim)
    local simmed = false
    if simmed and self:SimCard(spec) then
        self:SimProblem()
        sheet:Finish(4)
        return
    end
    local open = spec and Lists.NextUpgrades() or {}
    local section = { text = L("Next upgrades"), count = #open > 0 and #open or nil }
    if simmed then
        self:SimSection(section, spec)
    elseif spec then
        section.actions = { { text = "All upgrades", glyph = "list", onClick = function() UI:Open("bis") end } }
    end
    sheet:Add("section", section)
    if simmed then self:SimProblem() end
    for i = 1, math.min(UPGRADES, #open) do
        local p = open[i]
        local parts = {}
        local slot, where = Items.GetSlotText(p.id), LJ.BiS.SourceText(p.id)
        if slot ~= "" then parts[#parts + 1] = slot end
        if where then parts[#parts + 1] = (where:gsub(" %- ", " · ")) end
        sheet:Add("item", { id = p.id, upgrade = p.upgrade, chance = p.chance, sub = table.concat(parts, " · "),
            onClick = function(d) UI:Open("item", d.id) end })
    end
    if #open == 0 then
        sheet:Add("text", { text = L(spec and "No Best in Slot upgrades left for your level." or "Pick a spec on the Best in Slot page."),
            font = "bodySmall", color = C.text4, pad = 8 })
    end
    sheet:Finish(4)
end

-- More dungeons for the level (or the ones coming up) as pictures: one row, it ends at the bottom of the panel.
function Page:RefreshDungeons(instances, upcoming)
    local sheet = self.dungeons
    sheet:Reset(UI:ContentWidth() - LEFT_WIDTH - GAP - 32)
    local tiles = {}
    for i = 2, math.min(#instances, TILES + 1) do tiles[#tiles + 1] = instances[i] end
    if #tiles > 0 then
        sheet:Add("section", { text = L(upcoming and "Dungeons coming up" or "More dungeons for your level") })
        sheet:Grid("tile", tiles, TILES, Kit.KINDS.tile.height, GAP)
    end
    sheet:Finish(0)
end

function Page:Refresh()
    Theme.SetAccent(Theme.ClassAccent(Player.class or "WARRIOR"))
    local level = Player.level or 1
    self.spec = Player:GetActiveSpec()
    local instances, upcoming = Lists.InstancesFor(level)
    -- the zone the character stands in (when it has open world data)
    local map = Lists.CurrentZoneMap()
    self.zone = map and Items.GetWorldZone(map)
    local open = function(d) UI:Open("instance", d.inst.key) end
    for _, e in ipairs(instances) do e.onClick = open end
    -- the next step: the most upgrades (the list's first)
    local hero = self.hero
    hero:Reset(UI:ContentWidth())
    if instances[1] then hero:Add("feature", instances[1]) end
    hero:Finish(0)
    self:RefreshCharacter()
    self:RefreshUpgrades()
    self:RefreshDungeons(instances, upcoming)
end

function Page:Show()
    Player:Refresh()
    self:Refresh()
    -- the first show: the sizes of the new frames are only known after the first layout pass, the page is laid out
    -- again then (later shows have them; a look switch makes the page new)
    if self.laidOut then return end
    self.laidOut = true
    C_Timer.After(0, function()
        if self.root:IsShown() then self:Refresh() end
    end)
end

-- the experience bar follows kills and quests while the page is open
LJ:On("PLAYER_XP_UPDATE", function()
    if Page.root and Page.root:IsVisible() and Page.face then Page:RefreshCharacter() end
end)

UI:RegisterPage("foryou", Page, { "modern", "classic" })
