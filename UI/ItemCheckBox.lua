-- Lootified - the upgrade check's box (Sim/ItemCheck.lua): beside every loot roll of the game (GroupLootFrame1-4)
-- and, for an item clicked with Alt (bags, the loot window, chat links, vendors: the game's HandleModifiedItemClick; the
-- lists of Lootified: Items.HandleClick), as a small window of its own. It says whether the item is an upgrade for the active spec (what the sim found with what
-- is worn now, else the hidden ranking's estimate; Percent: the stat weights, with the share it adds in percent,
-- nothing fights), what it would replace, a tip for the roll (the game's own Need,
-- Greed and Pass) and Sim: the item fights against what is worn (a few seconds; again with a number too, e.g. after an
-- enchant or a talent: a number counts until the gear or the level changes; Alt+Click sims at once, the click is the
-- press, as do the item menu's "Simulate" and a click on the Best in Slot sheet: Box:Check). The boxes and Alt+Click
-- are on with the setting "Upgrade check" (LJ.db.upgradeCheck) and the Best in Slot module.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local ItemCheck = LJ.ItemCheck
local C = Theme.COLORS

local Box = {}
UI.ItemCheckBox = Box

local WIDTH, PAD = 300, 12
local HEAD = 28 + 9 + 10              -- the window's item line above the verdict (icon, gap, line, gap)
local ROLL_FRAMES = 4                 -- GroupLootFrame1-4 (Blizzard_UIPanels_Game GroupLootFrame.xml)
local NAME = "LootifiedItemCheck"     -- the Alt+Click window: Escape closes it (UISpecialFrames)
-- the art of the game's own roll buttons (GroupLootFrame.xml)
local NEED_ICON, GREED_ICON = "lootroll-toast-icon-need-up", "lootroll-toast-icon-greed-up"

-- The box in the active look; window: the Alt+Click window (the item's icon and name on top, a close button,
-- draggable), else the box beside a roll.
local function Create(window)
    local f = CreateFrame("Frame", window and NAME or nil, UIParent)
    f.window = window
    f:SetWidth(WIDTH)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Widgets.CreateShadow(f, 14, 0.7)
    f.panel = Widgets.CreatePopupPanel(f, 10)
    local top = PAD
    if window then
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.icon = Widgets.CreateItemIcon(f, 28)
        f.icon:SetPoint("TOPLEFT", PAD, -PAD)
        f.close = Widgets.CreateButton(f, nil, "icon", "close", 24, 24)
        f.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 2)
        f.close:SetScript("OnClick", function() f:Hide() end)
        Widgets.SetTooltip(f.close, "Close", nil, "ANCHOR_TOP")
        f.name = Widgets.Text(f, "item", C.text1)
        f.name:SetPoint("LEFT", f.icon, "RIGHT", 9, 0)
        f.name:SetWidth(WIDTH - PAD * 2 - 28 - 9 - 24 - 6)
        f.line = Widgets.Line(f)
        f.line:SetHeight(1)
        f.line:SetPoint("TOPLEFT", PAD, -(PAD + 28 + 9))
        f.line:SetPoint("TOPRIGHT", -PAD, -(PAD + 28 + 9))
        top = PAD + HEAD
        if not tContains(UISpecialFrames, NAME) then tinsert(UISpecialFrames, NAME) end
    end
    -- the verdict: its symbol and word, at the right the tags (Best in Slot, Wishlist)
    f.glyph = Widgets.Glyph(f, "upgrade", 13, C.ok)
    f.glyph:SetPoint("TOPLEFT", PAD, -top - 1)
    f.verdict = Widgets.Text(f, "label", C.ok)
    f.verdict:SetPoint("LEFT", f.glyph, "RIGHT", 6, 0)
    f.verdict:SetWidth(WIDTH - PAD * 2 - 19)
    f.bis = Widgets.CreatePill(f, 18)
    f.wish = Widgets.CreatePill(f, 18)
    -- the number with its unit and error; or a line of text (the estimate, why not, a problem, the fights going on)
    f.value = Widgets.Text(f, "heroSmall", C.okText)
    f.value:SetPoint("TOPLEFT", PAD, -(top + 19))
    f.unit = Widgets.Text(f, "h3", C.okText)
    f.unit:SetPoint("BOTTOMLEFT", f.value, "BOTTOMRIGHT", 4, 3)
    f.err = Widgets.Text(f, "small", C.text3)
    f.err:SetPoint("BOTTOMLEFT", f.unit, "BOTTOMRIGHT", 7, 0)
    f.note = Widgets.Text(f, "bodySmall", C.text2)
    f.note:SetWordWrap(true)
    f.note:SetJustifyV("TOP")
    f.note:SetMaxLines(3)
    f.bar = Widgets.CreateProgressBar(f, 5)
    -- Sim (Stop while it fights)
    f.sim = Widgets.CreateButton(f, "Sim", "primary", "lightning", nil, 24)
    f.sim:SetPoint("TOPRIGHT", -PAD, -(top + 21))
    f.sim:SetScript("OnClick", function()
        if ItemCheck.running and ItemCheck.running.link == f.link then
            ItemCheck.Stop()
            return
        end
        local link = f.link
        UI.SimSpeed:Then(function() ItemCheck.Start(link) end)
    end)
    -- what it would replace; the tip for the roll (their row and the box's height: Refresh)
    f.instead = Widgets.Text(f, "small", C.text3)
    f.tipIcon = f:CreateTexture(nil, "ARTWORK")
    f.tipIcon:SetSize(18, 18)
    f.tip = Widgets.Text(f, "pill", C.text2, nil, "RIGHT")
    f.tipIcon:SetPoint("RIGHT", f.tip, "LEFT", -4, 0)
    f.top = top
    f.skin = Theme.skin
    f:Hide()
    return f
end

-- A number as the box shows it: "+1.8", "-0.7".
local function Signed(v)
    return string.format("%+.1f", v)
end

-- The verdict's symbol, color and word, and the line of text under it (nil: the number shows).
local function Words(v)
    local level = LJ.Player.level
    if v.kind == "sim" then
        local dir = ItemCheck.Direction(v)
        if dir == "up" then return "upgrade", C.ok, L("Upgrade for you") end
        if dir == "down" then return "minus", C.red, L("Not an upgrade") end
        return "minus", C.text3, L("About the same")
    elseif v.kind == "stats" then
        local dir = ItemCheck.StatsDirection(v)
        local note = L("By your spec's stat weights.")
        if dir == "up" then return "upgrade", C.ok, L("Upgrade for you"), note end
        if dir == "down" then return "minus", C.red, L("Not an upgrade"), note end
        return "minus", C.text3, L("About the same"), note
    elseif v.kind == "estimate" then
        local note = L("Estimate from its stats.")
        if v.better then return "upgrade", C.warn, L("Probably an upgrade"), note end
        return "minus", C.text3, L("Probably not an upgrade"), note
    elseif v.kind == "unknown" then
        return "chart", C.text3, L("No percent data yet"), L("The game has not sent all of its data yet.")
    elseif v.kind == "cannot" then
        return "xCircle", C.text3, L("Not for you"), v.why
    elseif v.kind == "level" then
        return "hourglass", C.warn, F(L("From level %d"), v.level), F(L("You are level %d."), level)
    end
    return "checkCircle", C.ok, L("You wear it"), L("Nothing to compare.")
end

-- The item is on the Best in Slot sheet of the active spec (one of its picks).
local function IsPick(itemID)
    local spec = LJ.Player:GetActiveSpec()
    for _, p in ipairs(spec and LJ.BiS.GetPicks(spec) or {}) do
        if p.id == itemID then return true end
    end
    return false
end

-- The share of the fights done (the item fighting now is the box's).
local function ShowProgress(f, running)
    f.note:SetText(InCombatLockdown() and L("Paused while you are in combat.")
        or F(L("Simming: %d%%"), math.floor(running.progress * 100)))
    f.bar:SetProgress(running.progress)
end

-- Fills a box from its item (f.link) as it stands: the verdict, the number or a line of text, Sim, what it would
-- replace and (beside a roll) the tip.
local function Refresh(f)
    local v = ItemCheck.Get(f.link)
    if not v then
        f:Hide()
        return
    end
    local id, key = ItemCheck.Parse(f.link)
    -- no verdict while the game has no data of the item: asked through the addon's item loader, whose answer
    -- (ITEMS_UPDATED) fills the box again (the game's own answers to other requests are not followed)
    if v.kind == "unknown" and not C_Item.IsItemDataCachedByID(id) then LJ.Items.Request(id) end
    local top = f.top
    if f.window then
        -- the name as the link has it (a random suffix too), in the color of its quality
        f.icon:SetItem(id)
        local quality = select(3, C_Item.GetItemInfo(f.link)) or LJ.Items.Get(id).quality or 1
        f.name:SetText(Util.ColorText(f.link:match("%[(.-)%]") or LJ.Items.GetName(id), Util.QualityColor(quality)))
    end
    local glyph, color, word, note = Words(v)
    Theme.SetGlyph(f.glyph, glyph, color)
    Widgets.SetTextColor(f.verdict, color)
    f.verdict:SetText(Theme.Case(word))
    -- the tags at the right of the verdict, as many as fit beside its word: Best in Slot, then Wishlist
    local room = WIDTH - PAD * 2 - 19 - Widgets.TextWidth(f.verdict) - 8
    local last
    for _, t in ipairs({ { f.bis, IsPick(id), "Best in Slot", "gold", "crown" },
        { f.wish, LJ.Items.IsWishlisted(id), "Wishlist", "rare", "star" } }) do
        local pill = t[1]
        pill:Hide()
        if t[2] then
            pill:Set(Theme.Case(L(t[3])), t[4], t[5])
            if pill:GetWidth() <= room then
                pill:ClearAllPoints()
                if last then
                    pill:SetPoint("RIGHT", last, "LEFT", -5, 0)
                else
                    pill:SetPoint("TOPRIGHT", -PAD, -top + 3)
                end
                pill:Show()
                room, last = room - pill:GetWidth() - 5, pill
            end
        end
    end

    -- Sim, with a number too (Stop while this item fights)
    local running = ItemCheck.running and ItemCheck.running.key == key and ItemCheck.running
    local problem = ItemCheck.problems[key]
    f.sim:SetShown(false)
    if running then
        f.sim:SetLabel("Stop")
        f.sim:SetGlyph("xCircle")
    else
        f.sim:SetLabel("Percent")
        f.sim:SetGlyph("lightning")
    end
    -- the number: the damage the sim found, or (Percent) the share by the stat weights
    local share = v.kind == "stats" and v.pct ~= nil
    local numberShown = (v.kind == "sim" or share) and not running
    for _, part in ipairs({ f.value, f.unit, f.err }) do part:SetShown(numberShown) end
    f.note:SetShown(not numberShown)
    f.bar:SetShown(running and true or false)
    -- (the note's top is Sim's; its width ends 10 before Sim, set so that its lines can be counted before the box shows)
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", PAD, -(top + 21))
    f.note:SetWidth(WIDTH - PAD * 2 - (f.sim:IsShown() and f.sim:GetWidth() + 10 or 0))
    if numberShown then
        local dir = share and ItemCheck.StatsDirection(v) or ItemCheck.Direction(v)
        local c = dir == "up" and C.okText or dir == "down" and C.redText or C.text2
        f.value:SetText(Signed(share and v.pct or v.delta))
        Widgets.SetTextColor(f.value, c)
        Widgets.SetTextColor(f.unit, c)
        f.unit:SetText(share and "%" or "DPS")
        f.err:SetText(share and L("by your stats") or F("±%.1f", v.err))
    elseif running then
        Widgets.SetTextColor(f.note, C.text2)
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", PAD, -(top + 40))
        f.bar:SetPoint("TOPRIGHT", f.sim, "TOPLEFT", -10, -19)
        ShowProgress(f, running)
    elseif problem then
        f.note:SetText(problem)
        Widgets.SetTextColor(f.note, C.warn)
    else
        f.note:SetText(note or "")
        Widgets.SetTextColor(f.note, C.text2)
    end
    -- the row of what it would replace and the tip: a third line of the note (a long text in German or Russian beside
    -- Sim) moves it and the bottom of the box down by a line
    local row = top + 54
    local lines = f.note:IsShown() and f.note:GetNumLines() or 0
    if lines > 2 then row = row + math.ceil(f.note:GetStringHeight() / lines) end
    f.instead:SetPoint("TOPLEFT", PAD, -row)
    f.tip:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -(row + 6))
    f:SetHeight(row + 14 + PAD)

    -- what it would replace
    local replacing = v.kind == "sim" or v.kind == "estimate" or v.kind == "stats" or v.kind == "unknown"
    f.instead:SetShown(replacing)
    if replacing then
        if v.replaces then
            f.instead:SetText(F(L("instead of %s"), "|T" .. C_Item.GetItemIconByID(v.replaces) .. ":14:14|t "
                .. Theme.ItemName(v.replaces)))
        else
            f.instead:SetText(L("into an empty slot"))
        end
    end
    -- beside a roll: Need for an upgrade the game lets the player need, Greed or Pass for what is none; the damage the
    -- sim found decides with Sim only (Percent rates by the weights)
    local tip
    if f.rollID then
        local dir = v.kind == "sim" and UI.Sim.RanksItems(LJ.Player:GetActiveSpec()) and ItemCheck.Direction(v)
        if dir == "up" and f.canNeed then
            tip = { NEED_ICON, NEED }
        elseif (dir and dir ~= "up") or v.kind == "cannot" then
            tip = { GREED_ICON, F(L("%s or %s"), GREED, PASS) }
        end
    end
    f.tip:SetShown(tip ~= nil)
    f.tipIcon:SetShown(tip ~= nil)
    if tip then
        f.tipIcon:SetAtlas(tip[1])
        f.tip:SetText(Theme.Case(tip[2]))
    end
    -- (the icon of the tip is 3 higher than this line)
    if tip then
        f.instead:SetPoint("TOPRIGHT", f.tipIcon, "TOPLEFT", -8, -3)
    else
        f.instead:SetPoint("TOPRIGHT", -PAD, -row)
    end
end

-- Every box that shows (the rolls' and the window).
local function Shown()
    local list = {}
    for _, f in pairs(Box.rolls) do
        if f:IsShown() then list[#list + 1] = f end
    end
    if Box.window and Box.window:IsShown() then list[#list + 1] = Box.window end
    return list
end

local function On()
    return LJ.db.upgradeCheck and LJ.Modules.On("bis")
end

---------------------------------------------------------------------------
-- Beside the loot rolls
---------------------------------------------------------------------------
Box.rolls = {}   -- [roll frame] = its box

-- A roll frame showed: its box beside it (on the side with more room) for gear of the character's slots.
local function ShowRoll(frame)
    local f = Box.rolls[frame]
    if f then f:Hide() end
    -- (the game hides a roll frame whose item it cannot show during its own OnShow)
    if not (On() and frame:IsShown()) then return end
    local link = GetLootRollItemLink(frame.rollID)
    if not (link and ItemCheck.Get(link)) then return end
    if not (f and f.skin == Theme.skin) then
        f = Create(false)
        Box.rolls[frame] = f
    end
    f.link, f.rollID = link, frame.rollID
    f.canNeed = select(6, GetLootRollItemInfo(frame.rollID))
    f:ClearAllPoints()
    if Widgets.TooltipAnchor(frame) == "ANCHOR_RIGHT" then
        f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 5)
    else
        f:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 5)
    end
    Refresh(f)
    f:Show()
end

---------------------------------------------------------------------------
-- Alt+Click on an item
---------------------------------------------------------------------------
-- Opens the window on an item link (the middle of the screen the first time, then where it was dragged).
function Box:Open(link)
    local f = self.window
    if not (f and f.skin == Theme.skin) then
        local point = f and { f:GetPoint(1) }
        if f then f:Hide() end
        f = Create(true)
        if point then f:SetPoint(unpack(point)) else f:SetPoint("CENTER", 0, 140) end
        self.window = f
    end
    f.link = link
    Refresh(f)
    f:Show()
    f:Raise()
end

-- The window on an item (link) whose item fights at once (Alt+Click, the item menu's "Simulate", a click on the Best
-- in Slot sheet): again when it has a number (the gear or level it fought with is not all that counts, e.g. an
-- enchant). Nothing for an item that is no gear.
function Box:Check(link)
    local v = ItemCheck.Get(link)
    if not v then return end
    self:Open(link)
    local _, key = ItemCheck.Parse(link)
    if v.canSim and not (ItemCheck.running and ItemCheck.running.key == key) then
        UI.SimSpeed:Then(function() ItemCheck.Start(link) end)
    end
end

-- A click on an item with Alt alone: Box:Check. The game's modified clicks (bags, loot window, chat links, vendors ...)
-- and the lists of Lootified (Items.HandleClick) come here. true when it took the click.
function Box:AltClick(link)
    if not (On() and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then return false end
    if type(link) ~= "string" or Util.IsSecret(link) or not link:find("item:", 1, true) then return false end
    self:Check(link)
    return true
end

LJ:Listen("LOGIN", function()
    for i = 1, ROLL_FRAMES do
        local frame = assert(_G["GroupLootFrame" .. i], "no GroupLootFrame" .. i)
        frame:HookScript("OnShow", function(self) LJ:SafeCall(ShowRoll, self) end)
        frame:HookScript("OnHide", function(self)
            if Box.rolls[self] then Box.rolls[self]:Hide() end
        end)
    end
    hooksecurefunc("HandleModifiedItemClick", function(link) LJ:SafeCall(Box.AltClick, Box, link) end)
end)

-- New numbers, a fight's progress, other gear, level, spec, filter (the list, the stat priority) or item data: the
-- boxes that show say it again.
local function RefreshShown()
    for _, f in ipairs(Shown()) do Refresh(f) end
end
for _, message in ipairs({ "ITEM_CHECK_CHANGED", "SIM_BIS_CHANGED", "EQUIPMENT_CHANGED", "PLAYER_CHANGED",
    "SPEC_CHANGED", "ITEMS_UPDATED", "WISHLIST_CHANGED", "LIST_CHANGED" }) do
    LJ:Listen(message, RefreshShown)
end
-- the fights going on (paused in combat): only the share done of the boxes of that item
local function Progress()
    local running = ItemCheck.running
    for _, f in ipairs(Shown()) do
        if running and f.link == running.link then ShowProgress(f, running) end
    end
end
LJ:Listen("ITEM_CHECK_PROGRESS", Progress)
LJ:On("PLAYER_REGEN_DISABLED", Progress)
LJ:On("PLAYER_REGEN_ENABLED", Progress)
-- the setting or the Best in Slot module off: the boxes go
local function SettingsChanged()
    if On() then return end
    for _, f in ipairs(Shown()) do f:Hide() end
end
LJ:Listen("SETTINGS_CHANGED", SettingsChanged)
LJ:Listen("MODULES_CHANGED", SettingsChanged)
