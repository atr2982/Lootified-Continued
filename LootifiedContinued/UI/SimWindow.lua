-- Lootified - the simulator's window ("Open simulator" and "Sim this set" on the Best in Slot sheet, /lf sim). Three
-- tabs: "Character" sims the character as it is (the damage per second, the damage by ability and what one more point
-- of each stat is worth; with the room, what the fights start from: the character as the sim read it and the target),
-- "Planner" puts items in one of two own sets the player names (a slot's picker, or an item dragged onto the slot;
-- the Best in Slot sheet's own class swaps items into them too) and sims the set on its own, "Sets" sims the Best in
-- Slot sheet and the own sets as wholes against what is worn (bars side by side). The sim Best in Slot (Sim/SimBiS.lua) starts from For you and from the Best in
-- Slot sheet's "Best in Slot sim" button; one item against what is worn: the upgrade check's window (UI/ItemCheckBox.lua). Above the tabs the fight: the target's
-- level and the length (the sim Best in Slot takes the target only: its fights last a minute). The Sim button reads the character again and sims the view shown (Stop while it runs); a tab
-- only shows, a changed setting, gear or set clears the numbers (Character keeps its last ones until the next Sim,
-- over reloads too, and says when they were made with other gear, talents, level or fight settings). A sim Best in Slot goes on in the background when the
-- window closes (the foot shows one that runs). The window opens over the main window in the look's own style, its
-- texts as big as the main window's; its title row moves it, the grip at its bottom right makes it bigger or smaller
-- (the pages get the room: wider rows and cards, the slots spread out); place and size are kept. While fights run, UI/SimProgress.lua shows its own small window. The first time it opens
-- it explains itself (SimUI:StartTour).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Kit = LJ.Kit
local Sim = LJ.Sim
local BiS = LJ.BiS
local Player = LJ.Player
local Items = LJ.Items
local C = Theme.COLORS

-- results: the numbers of each view's last fights ({ [view] = result }) until a change clears them (the Best in Slot
-- page changes the own sets too, before the window was ever open)
local SimUI = { results = {} }
UI.Sim = SimUI

local WIDTH, HEIGHT = 900, 600
local HEAD, BAR, FOOT, PAD = 60, 48, 40, 18
local CARD_HEIGHT = 262
local SOURCE_ROWS = 8
local READ_ROWS, READ_STEP = 7, 30    -- the rows of the cards of what the fights start from (Character)
local MAX_SHARE = 0.95                -- the window covers at most 95 % of the screen
-- the pages between the tab bar and the foot; their room at the smallest size (other sizes: SimUI:Layout)
local BODY_TOP, BODY_BOTTOM = HEAD + BAR + 14, FOOT + 6
local BODY_WIDTH = WIDTH - 2 * PAD
-- the planner: the slots as a doll (two columns, the weapons below), its item picker
local PLANS = #LJ.charDefaults.plans   -- own sets (Core/Init.lua)
local TILE_WIDTH, TILE_HEIGHT, TILE_STEP = 250, 44, 48
local PLAN_TOP = 40                  -- the slots under the toolbar
local PICK_WIDTH, PICK_ROWS, PICK_ROW_HEIGHT = 316, 12, 36   -- the picker: at most PICK_ROWS rows (as many as fit)
local PICK_TOP = 98                  -- its rows under the title, the search line and the "Higher levels" switch
-- the sets tab: four cards side by side, a set's items in two rows below its numbers, as big as the card allows
-- (SET_ICON_MIN..SET_ICON_MAX; a narrow card: more rows); "Edit in Planner" with its text where it fits beside the
-- set's DPS (SET_DPS_WIDTH: what "123.4 DPS" takes), else the button's icon
local SET_HEIGHT = 232
local SET_ICONS_PER_ROW, SET_ICON_MIN, SET_ICON_MAX = 9, 20, 36
local SET_DPS_WIDTH = 140

local SimBiS = LJ.SimBiS
local INV_SLOT = SimBiS.INV_SLOT
SimUI.INV_SLOT = INV_SLOT

local TARGETS = {
    { 0, "Mob of your level" }, { 1, "1 level higher" }, { 2, "2 levels higher" }, { 3, "Boss (3 levels higher)" },
}
local LENGTHS = { { 60, "1 min" }, { 180, "3 min" }, { 300, "5 min" } }
-- The label of a target (TARGETS) by its level offset.
local function TargetLabel(offset)
    for _, t in ipairs(TARGETS) do
        if t[1] == offset then return t[2] end
    end
    error("unknown target " .. tostring(offset))
end
-- The tabs (each one view).
local TAB_TEXT = { own = "Character", plan = "Planner", sets = "Sets" }
-- the Sim button of each view (it sims what the tab shows)
local SIM_TEXT = { own = "Sim my gear", plan = "Sim my set", sets = "Sim the sets" }
-- the foot of a view before its first fights
local IDLE = {
    own = "Press Sim: your character fights as you wear it.",
    plan = "Press Sim: your set fights on its own.",
    sets = "Press Sim: each ticked set is worn as a whole and fights against what you wear.",
}

local function DB() return LJ.db.sim end

-- The view shown: the tab's.
function SimUI:View()
    return DB().tab
end

-- The class model of the player and the spec it plays: the spec given (the Best in Slot sheet's) or the player's own;
-- nil for another class's spec (every spec of the player's class plays: the tanks and the healers their damage).
function SimUI.Model(spec)
    local model = Sim.models[Player.class]
    spec = spec or Player:GetActiveSpec()
    if not (model and spec and spec.class == Player.class and model.specs[spec.key]) then return nil end
    return model, spec
end

-- The Best in Slot sheet shows the button for the specs the simulator plays.
function SimUI.Supports(spec)
    return spec ~= nil and SimUI.Model(spec) ~= nil
end

-- Items rated by the simulator: Sim picked (LJ.cdb.rating, UI/RatingPicker.lua) and a spec it plays (every spec of the
-- player's class: tanks and healers by their damage). The sim Best in Slot builds their list, the boxes and tooltips
-- show DPS; else (Percent) every spec keeps the list of its stat weights with the share in percent.
function SimUI.RanksItems(spec)
    return SimUI.Supports(spec) and LJ.cdb.rating == "sim"
end

---------------------------------------------------------------------------
-- Names and icons
---------------------------------------------------------------------------
local AUTO_SHOT, AUTO_ATTACK = 75, 6603

-- The name of a damage source in the client's language and its icon: the class model's spell of the ability, talent,
-- poison or imbue, the pet's abilities under "Pet" (numbers kept with a pet, a poison or an imbue the character no
-- longer has show them too).
function SimUI:Source(key)
    local char, model = self.char, self.model
    local mh, ranged = char and char.mh, char and char.ranged
    if key == "MELEE" then
        return L("Melee"), mh and mh.id and C_Item.GetItemIconByID(mh.id) or C_Spell.GetSpellTexture(AUTO_ATTACK)
    elseif key == "AUTO_SHOT" then
        return C_Spell.GetSpellName(AUTO_SHOT), ranged and C_Item.GetItemIconByID(ranged.id)
    elseif key == "PET_MELEE" then
        return F("%s: %s", L("Pet"), L("Melee")), C_Spell.GetSpellTexture(AUTO_ATTACK)
    end
    local petKey = key:match("^PET_(.+)$")
    if petKey then
        local id = model.petSpells[petKey]
        return F("%s: %s", L("Pet"), C_Spell.GetSpellName(id)), C_Spell.GetSpellTexture(id)
    end
    -- the damage over time of a spell that hits too (Immolate, Fireball ...)
    local base = key:match("^(.+)_DOT$")
    if base then
        local name, icon = self:Source(base)
        return F("%s (%s)", name, L("over time")), icon
    end
    local id = model.spells[key] or model.talents[key] or model.weaponSpells and model.weaponSpells[key]
    return id and C_Spell.GetSpellName(id) or key, id and C_Spell.GetSpellTexture(id)
end

-- The name of a way to play a character (Sim.VariantKeys): its spells' names in the client's language, joined by " + ".
function SimUI.VariantText(model, variant)
    local names = {}
    for _, key in ipairs(Sim.VariantKeys(variant)) do names[#names + 1] = C_Spell.GetSpellName(model.spells[key]) end
    return table.concat(names, " + ")
end

local function StatName(key)
    if key == "CritPct" then return L("1% Crit") end
    if key == "HitPct" then return L("1% Hit") end
    if key == "SpellCritPct" then return L("1% Spell crit") end
    if key == "SpellHitPct" then return L("1% Spell hit") end
    -- (the addon's stat names, as the Database look's)
    local names = {
        Strength = "Strength", Agility = "Agility", Intellect = "Intellect", AttackPower = "Attack Power",
        RangedAttackPower = "Ranged Attack Power", SpellPowerAll = "Spell Power", BlockValue = "Block Value",
    }
    return F("1 %s", L(names[key] or key))
end

local function Signed(v, decimals)
    local text = string.format("%." .. (decimals or 1) .. "f", math.abs(v))
    if tonumber(text) == 0 then return "±" .. text end
    return (v > 0 and "+" or "-") .. text
end

local function DeltaColor(delta, err)
    if delta > 2 * err and delta > 0.05 then return C.ok end
    if delta < -2 * err and delta < -0.05 then return C.bad end
    return C.text3
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- The note on a weapon whose skill the character has not trained to the level's maximum yet (the sim counts it as
-- trained: Sim.Character.WeaponSkill): "One-Handed Swords 0/100: counted as trained."; nil for other items.
local function SkillNote(itemID)
    local _, _, kind, _, _, classID, subclass = C_Item.GetItemInfoInstant(itemID)
    if classID ~= 2 then return nil end   -- not a weapon
    local rank, max = Sim.Character.WeaponSkill(subclass, Sim.Character.WeaponSkills(), UnitLevel("player"))
    if rank >= max then return nil end
    return F(L("%s %d/%d: counted as trained."), kind, rank, max)
end

-- The hand of a weapon -> its slot of the sheet (SlotName).
local HAND_SLOT = { mh = "MAINHAND", oh = "OFFHAND", ranged = "RANGED" }

-- The hands whose weapons the fights swing (the spec's, as Sim.Character.FightingHand: none for a caster, nor for a
-- cat, whose paws fight).
local function SwingHands(char, model)
    if char and char.mh and char.mh.paws then return {} end
    return char and char.hands or model.hands
end

-- What the fights of a run show (Character: what is worn; Sets: each simmed set): the share of the swings missed or
-- dodged and of the hits that crit (not the damage over time, nor the damage that rides on a hit: model.procs),
-- attacks per minute, the mana left at the end (a character with mana). better: which way is better (Sets colors the
-- sets' numbers against what is worn).
local FIGHT_LINES = {
    { text = "Missed or dodged", key = "missed", format = "%.1f%%", better = -1 },
    { text = "Critical hits", key = "crits", format = "%.1f%%", better = 1 },
    { text = "Attacks per minute", key = "perMinute", format = "%.0f", better = 1 },
    { text = "Mana left at the end", key = "mana", format = "%.0f%%", better = 1 },
}
local function FightNumbers(run, length, model)
    local swings, misses, crits = 0, 0, 0
    for _, s in ipairs(run.sources) do
        if not (s.periodic or model.procs and model.procs[s.key]) then
            swings, misses, crits = swings + s.count, misses + s.misses, crits + s.crits
        end
    end
    return {
        missed = swings > 0 and misses / swings * 100 or nil,
        crits = swings > misses and crits / (swings - misses) * 100 or nil,
        perMinute = swings * 60 / length,
        mana = run.manaLeft and run.manaLeft * 100 or nil,
    }
end

-- The name of a sheet slot ("Finger 1", "Main Hand" ...) and the icon of the empty slot.
local function SlotName(slot)
    local label, emptyIcon = BiS.SlotLabel(slot, Player.class)
    local n = slot:match("%u(%d)$")
    return n and (L(label) .. " " .. n) or L(label), emptyIcon
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Card(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.fill = Widgets.CreateBox(f, "BACKGROUND", 1, 10)
    f.ring = Widgets.CreateBox(f, "BACKGROUND", 2, 10, true)
    Widgets.BoxFill(f.fill, f.ring, "row")
    f.label = Widgets.Text(f, "label", Kit.SectionColor())
    f.label:SetPoint("TOPLEFT", 16, -14)
    return f
end

local function Chip(parent, text, onClick)
    local chip = Widgets.CreateChip(parent, text, nil, 26)
    chip:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        onClick()
    end)
    return chip
end

function SimUI:CreateControls(win)
    local controls = CreateFrame("Frame", nil, win)
    controls:SetPoint("TOPRIGHT", -PAD, -HEAD - 10)
    controls:SetSize(10, 28)
    self.target = Widgets.CreateDropdown(win, nil, function(menu)
        for _, t in ipairs(TARGETS) do
            menu:CreateRadio(t[2], function() return DB().target == t[1] end, function()
                DB().target = t[1]
                self:Reset()
            end)
        end
    end, "", "target")
    Widgets.SetTooltip(self.target, "Target", "The level of the target dummy. It stands still, never hits back and is hit from behind.", "ANCHOR_BOTTOM")
    self.lengthChips = {}
    local right = nil
    for i = #LENGTHS, 1, -1 do
        local len = LENGTHS[i]
        local chip = Chip(win, len[2], function()
            DB().length = len[1]
            self:Reset()
        end)
        chip.length = len[1]
        if right then chip:SetPoint("RIGHT", right, "LEFT", -4, 0) else chip:SetPoint("TOPRIGHT", controls, "TOPRIGHT") end
        right = chip
        self.lengthChips[i] = chip
    end
    self.target:SetPoint("RIGHT", right, "LEFT", -14, 0)
end

function SimUI:RefreshControls()
    local db = DB()
    self.target:SetLabel(TargetLabel(db.target))
    for _, chip in ipairs(self.lengthChips) do chip:SetActive(chip.length == db.length) end
    self.tabs:Select(db.tab, true)
end

-- The size the window can have: at least WIDTH x HEIGHT (its texts keep the main window's size), at most MAX_SHARE of
-- the screen.
local function ClampSize(win, w, h)
    local ratio = UIParent:GetEffectiveScale() / win:GetEffectiveScale()
    local mw, mh = UIParent:GetWidth() * ratio * MAX_SHARE, UIParent:GetHeight() * ratio * MAX_SHARE
    return math.floor(math.max(WIDTH, math.min(mw, w))), math.floor(math.max(HEIGHT, math.min(mh, h)))
end

-- The window's center on the screen in pixels: where it was moved to (kept), else the screen's middle.
local function CenterPixels()
    local pos = DB().pos
    if pos then return pos[1], pos[2] end
    local cx, cy = UIParent:GetCenter()
    local ui = UIParent:GetEffectiveScale()
    return cx * ui, cy * ui
end

-- Puts the window's center where it belongs at its scale.
function SimUI:Place()
    local win = self.frame.win
    local x, y = CenterPixels()
    local eff = win:GetEffectiveScale()
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / eff, y / eff)
end

-- The window's size, within what fits on the screen; its place kept, the pages take the room. SimUI.height: the
-- height it was given (the game can report it back a hair lower: its sizes are floats on the screen).
function SimUI:Resize(w, h)
    local win = self.frame.win
    local width, height = ClampSize(win, w, h)
    win:SetSize(width, height)
    self.height = height
    self:Place()
    self:Layout()
end

-- The size kept (the first time: WIDTH x HEIGHT).
function SimUI:ApplySize()
    local size = DB().size or { WIDTH, HEIGHT }
    self:Resize(size[1], size[2])
end

-- The title row moves the window (its center stays on the screen); the place is kept.
function SimUI:CreateMover(win)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT", -130, 0)   -- not over the Close button
    bar:SetHeight(HEAD)
    bar:EnableMouse(true)
    local startX, startY, fromX, fromY
    local function Move()
        local x, y = GetCursorPosition()
        local ui = UIParent:GetEffectiveScale()
        local w, h = UIParent:GetWidth() * ui, UIParent:GetHeight() * ui
        DB().pos = { math.max(0, math.min(w, fromX + x - startX)), math.max(0, math.min(h, fromY + y - startY)) }
        self:Place()
    end
    bar:SetScript("OnMouseDown", function(b)
        GameTooltip:Hide()
        startX, startY = GetCursorPosition()
        fromX, fromY = CenterPixels()
        b:SetScript("OnUpdate", Move)
    end)
    bar:SetScript("OnMouseUp", function(b) b:SetScript("OnUpdate", nil) end)
    Widgets.SetTooltip(bar, "Move window", "Drag the title to move the window. It keeps its place.", "ANCHOR_TOP")
    win.mover = bar
end

-- The grip at the bottom right: dragged, the window's corner follows the cursor (its center stays, the pages get the
-- room); the size is kept.
function SimUI:CreateGrip(win)
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(win:GetFrameLevel() + 30)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function Drag()
        -- in screen pixels: the cursor and the window's center (it stays where it is)
        local x, y = GetCursorPosition()
        local cx, cy = CenterPixels()
        local eff = win:GetEffectiveScale()
        self:Resize(2 * (x - cx) / eff, 2 * (cy - y) / eff)
    end
    grip:SetScript("OnMouseDown", function(g)
        GameTooltip:Hide()
        -- the player sizes it: no longer grown to the Character tab's cards (SimUI:ShowRead) until it opens again
        self.autoFit = false
        g:SetScript("OnUpdate", Drag)
    end)
    grip:SetScript("OnMouseUp", function(g)
        g:SetScript("OnUpdate", nil)
        DB().size = { win:GetWidth(), win:GetHeight() }
        self:Refresh()   -- texts that flow by the width (the stat chips) follow
    end)
    Widgets.SetTooltip(grip, "Window size", "Drag to make the window bigger or smaller. It keeps its size.", "ANCHOR_TOP")
    win.grip = grip
end

local function Create(host)
    local shade = CreateFrame("Frame", nil, host)
    -- over the whole screen: the window can be bigger than the main window
    shade:SetAllPoints(UIParent)
    shade:SetFrameStrata("DIALOG")
    shade:SetFrameLevel(host:GetFrameLevel() + 100)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    shade.dim = Widgets.Solid(shade, "BACKGROUND", 0, C.black or { 0, 0, 0 }, 0.55)
    shade.dim:SetAllPoints()
    shade:SetScript("OnMouseDown", function() SimUI:Close() end)
    -- hidden with the main window too: the fights stop, its tour ends
    shade:SetScript("OnHide", function()
        SimUI:Cancel()
        SimUI:StopTour()
    end)
    shade:Hide()
    shade.host = host

    local win = CreateFrame("Frame", nil, shade)
    win:SetSize(WIDTH, HEIGHT)
    win:EnableMouse(true)
    Widgets.CreateShadow(win, 22, 0.8)
    win.panel = Widgets.CreatePopupPanel(win, 14)
    shade.win = win
    SimUI:CreateGrip(win)
    SimUI:CreateMover(win)

    win.glyph = Widgets.Glyph(win, "chart", 22, Theme.accent)
    win.glyph:SetPoint("TOPLEFT", PAD, -(HEAD - 22) / 2)
    win.title = Widgets.Text(win, "titleSmall", Theme.PANE.title)
    win.title:SetPoint("TOPLEFT", win.glyph, "TOPRIGHT", 10, 4)
    win.title:SetText(Theme.Case(L("Sim")))
    win.sub = Widgets.Text(win, "small", C.text3)
    win.sub:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -2)
    win.close = Widgets.CreateButton(win, "Close", "ghost", "close", nil, 26)
    win.close:SetPoint("TOPRIGHT", -PAD + 4, -(HEAD - 26) / 2)
    win.close:SetScript("OnClick", function() SimUI:Close() end)
    -- Percent: what the simulator rates and what the upgrades follow (SimUI:Refresh)
    win.role = Widgets.Text(win, "small", C.text3, nil, "RIGHT")
    win.role:SetPoint("RIGHT", win.close, "LEFT", -18, 0)
    win.role:SetWidth(440)
    win.role:SetWordWrap(true)
    Theme.OnAccent(win, function(_, r, g, b) win.glyph:SetVertexColor(r, g, b, 1) end)
    local line = Kit.Line(win)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -HEAD)
    line:SetPoint("TOPRIGHT", 0, -HEAD)

    SimUI.tabs = Widgets.CreateTabs(win, {
        { key = "own", text = TAB_TEXT.own, glyph = "user", count = false },
        { key = "plan", text = TAB_TEXT.plan, glyph = "shirt", count = false },
        { key = "sets", text = TAB_TEXT.sets, glyph = "package", count = false },
    }, function(key) SimUI:ShowTab(key) end,
        -- the bar as wide as its tabs: a frame without a width is not drawn in the game, nor are the tabs on it
        { height = BAR - 6, onLayout = function(bar) bar:SetWidth(bar.width) end })
    SimUI.tabs:SetPoint("TOPLEFT", PAD - 6, -HEAD - 4)
    SimUI:CreateControls(win)
    local barLine = Kit.Line(win)
    barLine:SetHeight(1)
    barLine:SetPoint("TOPLEFT", 0, -HEAD - BAR)
    barLine:SetPoint("TOPRIGHT", 0, -HEAD - BAR)

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", PAD, -BODY_TOP)
    body:SetPoint("BOTTOMRIGHT", -PAD, BODY_BOTTOM)
    shade.body = body

    -- the foot: the sim Best in Slot's button on the left; what Sim does, the fights' progress or what they were; the
    -- Sim button of the tab on the right
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT)
    local footLine = Kit.Line(foot)
    footLine:SetHeight(1)
    footLine:SetPoint("TOPLEFT")
    footLine:SetPoint("TOPRIGHT")
    win.sim = Widgets.CreateButton(foot, SIM_TEXT.own, "primary", "lightning", nil, 30)
    win.sim:SetPoint("RIGHT", -PAD - 12, 0)   -- the size grip in the corner
    win.sim:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        SimUI:Press()
    end)
    Widgets.SetTooltip(win.sim, "Sim", "Reads your character again (gear, talents, buffs) and sims what this tab shows. While it sims: stops it.", "ANCHOR_TOP")
    win.progress = Widgets.CreateProgressBar(foot, 5)
    win.progress:SetPoint("RIGHT", win.sim, "LEFT", -12, 0)
    win.progress:SetWidth(200)
    -- (two lines where a note needs them)
    win.status = Widgets.Text(foot, "small", C.text4)
    win.status:SetPoint("LEFT", PAD, 0)
    win.status:SetWordWrap(true)
    win.status:SetMaxLines(2)
    win.status:SetPoint("RIGHT", win.progress, "LEFT", -12, 0)
    win.status:SetJustifyH("LEFT")

    shade.pages = { own = SimUI:CreateOwn(body), plan = SimUI:CreatePlan(body), sets = SimUI:CreateSets(body) }
    return shade
end

-- The pages take the window's room: Sets its cards, the planner its columns, weapons and the middle, Character what
-- the fights start from when it fits (SimUI:ShowRead).
function SimUI:Layout()
    local f = self.frame
    local w, h = f.win:GetWidth() - 2 * PAD, f.win:GetHeight() - BODY_TOP - BODY_BOTTOM
    f.pages.sets:Layout(w)
    f.pages.plan:Layout(w, h)
    if f.pages.own:IsVisible() then self:ShowRead() end
end

---------------------------------------------------------------------------
-- Rows and search lines (the planner's picker)
---------------------------------------------------------------------------
-- selected: the one picked row
local function RowVisual(row)
    Widgets.BoxFill(row.fill, row.ring, row.selected and "pick" or "row", row.hovered)
end

local function InputVisual(box)
    box.placeholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
end

---------------------------------------------------------------------------
-- Sets: what is worn, the Best in Slot sheet and the own sets (LJ.cdb.plans[n] = { [sheet slot] = itemID }: only the
-- items the player put in with the planner, empty until then; they fight with exactly these items)
---------------------------------------------------------------------------
local function Worn(slot) return GetInventoryItemID("player", INV_SLOT[slot]) end
local IsTwoHand = BiS.IsTwoHand

-- An item the planner can put in a set: its data ships with the addon (its stats, or none).
local function Simmable(id)
    return Items.IsShipped(id)
end

-- A set as Sim.Jobs.CompareSets takes it: { key, label, bySlot = { [sheet slot] = itemID } (the set's item, else what
-- is worn; exact: only the set's items; the off hand empty beside a two-hander), items = { { slot = equipment slot,
-- id } } (what differs from what is worn, in sheet order: the main hand before the off hand; id nil: an exact set's
-- empty slot where something is worn) }. pick(slot): the set's item of a slot, or nil.
local function MakeSet(key, label, pick, exact)
    local set = { key = key, label = label, bySlot = {}, items = {} }
    for _, slot in ipairs(BiS.SLOTS) do
        local worn = Worn(slot)
        local id = pick(slot)
        if not exact then id = id or worn end
        -- beside a two-hander: no off hand (the two-hander takes its place in the sim)
        local beside = slot == "OFFHAND" and IsTwoHand(set.bySlot.MAINHAND)
        if beside then id = nil end
        set.bySlot[slot] = id
        if id ~= worn and not beside then set.items[#set.items + 1] = { slot = INV_SLOT[slot], id = id } end
    end
    return set
end

-- The name of an own set: the player's, else "Set n".
function SimUI.PlanName(n)
    return LJ.cdb.planNames[n] or F(L("Set %d"), n)
end

-- An own set: it shows and fights with only its items (an empty slot: no item there). empty: none yet; missing: the
-- weapon slot it lacks to fight (the weapon the spec fights with, Sim.Character.FightingHand).
function SimUI:PlanSet(n)
    local plan = LJ.cdb.plans[n]
    local set = MakeSet("set" .. n, SimUI.PlanName(n), function(slot) return plan[slot] end, true)
    set.empty = next(plan) == nil
    local hand = self.char and Sim.Character.FightingHand(self.char, self.model)
    local need = (hand == "mh" and "MAINHAND") or (hand == "ranged" and "RANGED") or nil
    if not set.empty and need and not plan[need] then set.missing = need end
    return set
end

-- The sets the "Sets" tab compares with what is worn: the Best in Slot sheet's (BiS.ResolveSlot) and the own sets.
function SimUI:Sets()
    local ranking = BiS.Ranking(self.spec)
    local sets = { MakeSet("sheet", L("Best in Slot"), function(slot) return BiS.ResolveSlot(self.spec, slot, ranking) end) }
    for n = 1, PLANS do sets[#sets + 1] = self:PlanSet(n) end
    return sets
end

-- What a set's card and bar show: { dps, delta, err } once simmed (a set without changes: what is worn), { failed }
-- when it could not be simmed, nil before Sim and for an own set that cannot fight (empty, its weapon missing).
local function SetNumbers(result, set)
    if not result or set.empty or set.missing then return nil end
    if #set.items == 0 then return { dps = result.base.dps } end
    local r = result.sets[set.key]
    if not r then return nil end
    if r.failed then return { failed = r.failed:gsub("^.-:%d+: ", "") } end
    return { dps = r.run.dps, delta = r.delta, err = r.err, sources = r.sources, run = r.run }
end

-- What an own set without the weapon its spec fights with needs.
local NEED_TEXT = { MAINHAND = "Needs a main-hand weapon.", RANGED = "Needs a ranged weapon." }

-- The note under a set's numbers.
local function SetNote(set)
    if set.empty then return L("Empty: fill it in the Planner.") end
    if set.missing then return L(NEED_TEXT[set.missing]) end
    if #set.items == 0 then return L("Same as what you wear.") end
    return F(L("%d items different from now."), #set.items)
end

-- The planner's note on its set (on its own): how many items it has; its empty slots fight without an item; a weapon
-- the fights swing (hands: SwingHands) whose skill is not trained yet counts as trained.
local function PlanNote(set, hands)
    if set.empty then return L("Empty: click a slot to pick an item.") end
    if set.missing then return SetNote(set) end
    local items, empty = 0, false
    for _, slot in ipairs(BiS.SLOTS) do
        if set.bySlot[slot] then
            items = items + 1
        elseif not (slot == "OFFHAND" and IsTwoHand(set.bySlot.MAINHAND)) then
            empty = true
        end
    end
    local text = F(L("%d items in the set."), items) .. (empty and (" " .. L("Empty slots fight without an item.")) or "")
    -- items of a higher level: the sim counts them as if they could be worn now
    for _, slot in ipairs(BiS.SLOTS) do
        local from = set.bySlot[slot] and SimBiS.WearLevel(set.bySlot[slot])
        if from and from > (Player.level or 1) then
            text = text .. " " .. L("Items above your level count as if you could wear them now.")
            break
        end
    end
    for _, hand in ipairs(hands) do
        local id = set.bySlot[HAND_SLOT[hand]]
        local skill = id and SkillNote(id)
        if skill then text = text .. " " .. skill end
    end
    return text
end

local SET_ORDER = { "worn", "sheet", "set1", "set2" }
-- under the bars: a line of the fights' numbers, an ability of the best set (at most GAIN_ROWS)
local FIGHT_LINE, GAIN_LINE, GAIN_ROWS = 24, 25, 8

-- Four cards (what is worn, the sheet's set, the own sets: their numbers and items; the own sets with a button to the
-- planner), the bars of their numbers below. A tick on every set but what is worn: Sim sims the ticked ones (what is
-- worn always: they fight against it); the sets left out are kept per character (cdb.setsOff).
function SimUI:CreateSets(body)
    local ui = self
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    page.cards = {}
    for _, key in ipairs(SET_ORDER) do
        local card = Card(page)
        card:SetHeight(SET_HEIGHT)
        card.best = Widgets.CreatePill(card, 18)
        card.best:SetPoint("TOPRIGHT", -12, -11)
        card.best:Set("BEST", "acc", "trophy")
        if key ~= "worn" then
            card.label:Hide()
            card.pick = Widgets.CreateCheck(card, "label", Kit.SectionColor(), function(on)
                LJ.cdb.setsOff[key] = (not on) or nil
                self:ShowSets()
            end)
            card.pick:SetPoint("TOPLEFT", 14, -10)
        end
        card.big = Widgets.Text(card, "hero", C.white)
        card.big:SetPoint("TOPLEFT", 16, -40)
        card.unit = Widgets.Text(card, "big", Theme.accent)
        card.unit:SetPoint("BOTTOMLEFT", card.big, "BOTTOMRIGHT", 6, 4)
        card.unit:SetText(L("DPS"))
        card.delta = Widgets.Text(card, "nameBold", C.text3)
        card.delta:SetPoint("TOPLEFT", card.big, "BOTTOMLEFT", 0, -8)
        card.note = Widgets.Text(card, "small", C.text3)
        card.note:SetPoint("TOPLEFT", card.delta, "BOTTOMLEFT", 0, -6)
        card.note:SetPoint("RIGHT", -16, 0)
        card.note:SetJustifyH("LEFT")
        card.note:SetWordWrap(true)
        -- the set's items below the note
        card.grid = CreateFrame("Frame", nil, card)
        card.grid:SetSize(1, 1)
        card.grid:SetPoint("TOPLEFT", card.note, "BOTTOMLEFT", 0, -10)
        card.icons = {}
        for j = 1, #BiS.SLOTS do
            local icon = Widgets.CreateItemIcon(card, SET_ICON_MIN)
            icon:SetScript("OnEnter", function(b)
                if b.itemID then Widgets.ShowItemTooltip(b, b.itemID) end
            end)
            icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card.icons[j] = icon
        end
        -- an own set: to the planner, beside its numbers
        local n = tonumber(key:match("^set(%d)$"))
        if n then
            card.edit = Widgets.CreateButton(card, "Edit in Planner", "ghost", "shirt", nil, 24)
            card.edit:SetPoint("TOPRIGHT", -12, -45)
            Widgets.SetTooltip(card.edit, "Edit in Planner")
            card.edit:SetScript("OnClick", function()
                Util.PlaySound("U_CHAT_SCROLL_BUTTON")
                DB().set = n
                self:ShowTab("plan")
            end)
        end
        page.cards[key] = card
    end
    -- the cards share the width; their icons fill it
    function page:Layout(w)
        local width = math.floor((w - (#SET_ORDER - 1) * 12) / #SET_ORDER)
        local room = width - 28
        local step = math.max(SET_ICON_MIN + 3, math.min(SET_ICON_MAX + 3, math.floor(room / SET_ICONS_PER_ROW)))
        local perRow = math.min(SET_ICONS_PER_ROW, math.floor(room / step))
        for i, key in ipairs(SET_ORDER) do
            local card = self.cards[key]
            card:SetWidth(width)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", (i - 1) * (width + 12), 0)
            for j, icon in ipairs(card.icons) do
                icon:SetSize(step - 3, step - 3)
                icon:SetPoint("TOPLEFT", card.grid, "TOPLEFT", ((j - 1) % perRow) * step, -math.floor((j - 1) / perRow) * step)
            end
            if card.edit then
                card.edit:SetLabel("Edit in Planner")
                if card.edit:GetWidth() > width - 28 - SET_DPS_WIDTH then
                    card.edit:SetLabel("")
                    card.edit:SetWidth(28)
                end
            end
        end
        -- (the details under the bars fit the room)
        if self:IsVisible() then ui:ShowSets() end
    end
    -- the bars: every set's damage side by side (the hint before Sim)
    local bars = Card(page)
    bars:SetPoint("TOPLEFT", 0, -(SET_HEIGHT + 12))
    bars:SetPoint("BOTTOMRIGHT")
    bars.label:SetText(Util.Upper(L("One fight, all sets")))
    bars.rows = {}
    for i = 1, #SET_ORDER do
        local r = CreateFrame("Frame", nil, bars)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 16, -34 - (i - 1) * 21)
        r:SetPoint("RIGHT", -16, 0)
        r.name = Widgets.Text(r, "smallSemi", C.text2, nil, "RIGHT")
        r.name:SetPoint("LEFT")
        r.name:SetWidth(110)
        r.name:SetWordWrap(false)
        r.value = Widgets.Text(r, "smallSemi", C.text1)
        r.value:SetPoint("RIGHT")
        r.value:SetWidth(150)
        r.value:SetJustifyH("LEFT")
        r.bar = Widgets.CreateProgressBar(r, 10)
        r.bar:SetPoint("LEFT", r.name, "RIGHT", 12, 0)
        r.bar:SetPoint("RIGHT", r.value, "LEFT", -12, 0)
        bars.rows[i] = r
    end
    bars.hint = Widgets.Text(bars, "small", C.text4)
    bars.hint:SetPoint("TOPLEFT", 16, -36)
    bars.hint:SetPoint("RIGHT", -16, 0)
    bars.hint:SetJustifyH("LEFT")
    bars.hint:SetWordWrap(true)
    bars.hint:SetText(L("After Sim: the damage of every ticked set side by side, the same fights for all. Dim icons are worn already. Set bonuses, procs and on-use effects do not count."))
    -- under the bars, when the window has the room: how the fights of each simmed set went, and what each ability of
    -- the best set does more or less than with what is worn
    bars.line = Kit.Line(bars)
    bars.line:SetHeight(1)
    bars.fights = Widgets.Text(bars, "label", Kit.SectionColor())
    bars.fights:SetText(Util.Upper(L("How the fights went")))
    bars.columns = {}
    for i = 1, #SET_ORDER do
        local t = Widgets.Text(bars, "label", C.text4)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        bars.columns[i] = t
    end
    bars.lines = {}
    for k = 1, #FIGHT_LINES + 1 do
        local l = { name = Widgets.Text(bars, "bodySmall", C.text2), values = {} }
        l.name:SetJustifyH("LEFT")
        l.name:SetWordWrap(false)
        for i = 1, #SET_ORDER do
            l.values[i] = Widgets.Text(bars, "bodySemi", C.text1)
            l.values[i]:SetJustifyH("LEFT")
            l.values[i]:SetWordWrap(false)
        end
        bars.lines[k] = l
    end
    bars.divider = Kit.Line(bars)
    bars.divider:SetWidth(1)
    bars.gain = Widgets.Text(bars, "label", Kit.SectionColor())
    bars.gain:SetJustifyH("LEFT")
    bars.gain:SetWordWrap(false)
    bars.gainRows = {}
    for k = 1, GAIN_ROWS do
        local r = CreateFrame("Frame", nil, bars)
        r:SetHeight(22)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = Widgets.Text(r, "bodySmall", C.text1)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetWidth(150)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.value = Widgets.Text(r, "smallSemi", C.ok, nil, "RIGHT")
        r.value:SetPoint("RIGHT")
        r.value:SetWidth(70)
        r.value:SetJustifyH("RIGHT")
        r.bar = Widgets.CreateProgressBar(r, 7)
        r.bar:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
        r.bar:SetPoint("RIGHT", r.value, "LEFT", -10, 0)
        bars.gainRows[k] = r
    end
    page.bars = bars
    return page
end

function SimUI:ShowSets()
    local page = self.frame.pages.sets
    local result = self.results.sets
    local off = LJ.cdb.setsOff
    local run = self.running and self.running.view == "sets" and self.running
    local sets = { MakeSet("worn", L("What you wear"), function() return nil end) }
    for _, set in ipairs(self:Sets()) do sets[#sets + 1] = set end
    -- (a set left out of Sim: no numbers)
    local numbers, top, best = {}, 0, nil
    for i, set in ipairs(sets) do
        if not off[set.key] then
            numbers[i] = i == 1 and (result and { dps = result.base.dps }) or SetNumbers(result, set)
        end
        local d = numbers[i] and numbers[i].dps
        if d then
            top = math.max(top, d)
            if i > 1 and numbers[i].delta and SimBiS.Shows(numbers[i].delta, numbers[i].err)
                and (not best or numbers[i].dps > numbers[best].dps) then best = i end
        end
    end
    for i, set in ipairs(sets) do
        local card, num = page.cards[SET_ORDER[i]], numbers[i]
        local on = not off[set.key]
        if card.pick then
            card.pick:SetLabel(Util.Upper(set.label))
            card.pick:SetChecked(on)
        else
            card.label:SetText(Util.Upper(set.label))
        end
        card.best:SetShown(i == best)
        -- a set left out of Sim: dim
        local alpha = on and 1 or 0.4
        for _, region in ipairs({ card.big, card.unit, card.delta, card.note }) do region:SetAlpha(alpha) end
        for j, slot in ipairs(BiS.SLOTS) do
            local icon = card.icons[j]
            local id = set.bySlot[slot]
            icon:SetItem(id)
            -- dim: worn already
            icon:SetAlpha(((i == 1 or id == nil or id ~= sets[1].bySlot[slot]) and 1 or 0.35) * alpha)
        end
        if num and num.failed then
            card.big:SetText("-")
            card.delta:SetText("")
            card.note:SetText(F(L("Could not sim this set: %s"), num.failed))
        else
            card.big:SetText(num and string.format("%.1f", num.dps) or "-")
            if num and num.delta then
                card.delta:SetText(F(L("%s DPS (±%.1f)"), Signed(num.delta), num.err))
                SetColor(card.delta, DeltaColor(num.delta, num.err))
            elseif num then
                card.delta:SetText(i == 1 and F(L("±%.1f DPS"), result.base.error) or "")
                SetColor(card.delta, C.text3)
            else
                card.delta:SetText((set.empty or set.missing or not on) and ""
                    or L(run and run.keys[set.key] and "Simming ..." or "Not simmed yet"))
                SetColor(card.delta, C.text3)
            end
            card.note:SetText(i == 1 and L("Your gear right now.")
                or (not on and not set.empty and L("Not in the sim: tick the box to add it.")) or SetNote(set))
        end
    end
    -- the bars of what is worn and the ticked sets, one below the other
    local bars = page.bars
    bars.hint:SetShown(result == nil)
    local shown = 0
    for i, r in ipairs(bars.rows) do
        local num = numbers[i]
        r:SetShown(result ~= nil and not off[sets[i].key])
        if r:IsShown() then
            r:SetPoint("TOPLEFT", 16, -34 - shown * 21)
            shown = shown + 1
            r.name:SetText(sets[i].label)
            if num and num.dps then
                r.value:SetText(num.delta and F("%.1f DPS  %s", num.dps, Signed(num.delta)) or F("%.1f DPS", num.dps))
                r.bar:SetProgress(top > 0 and num.dps / top or 0, i == 1 and C.text4 or (i == best and Theme.accent or C.blue))
            else
                r.value:SetText("-")
                r.bar:SetProgress(0)
            end
        end
    end
    self:ShowSetDetails(bars, sets, numbers, best, result, shown)
end

-- Under the bars of the Sets tab, when they fit: how the fights of what is worn and of each simmed set went (a set's
-- number better than what is worn: green, worse: red; a paladin also the seal its fights played), and what each ability
-- of the best set (none beats what is worn: the one with the most damage) does more or less.
function SimUI:ShowSetDetails(bars, sets, numbers, best, result, shownBars)
    local parts = { bars.line, bars.fights, bars.divider, bars.gain }
    for _, t in ipairs(bars.columns) do parts[#parts + 1] = t end
    for _, l in ipairs(bars.lines) do
        parts[#parts + 1] = l.name
        for _, v in ipairs(l.values) do parts[#parts + 1] = v end
    end
    for _, r in ipairs(bars.gainRows) do parts[#parts + 1] = r end
    for _, part in ipairs(parts) do part:Hide() end
    if not result then return end
    -- the columns: what is worn and the sets with fights of their own
    local columns = { { label = sets[1].label, run = result.base } }
    for i = 2, #sets do
        local n = numbers[i]
        if n and n.run then columns[#columns + 1] = { label = sets[i].label, run = n.run } end
    end
    local lines = {}
    for _, f in ipairs(FIGHT_LINES) do
        if f.key ~= "mana" or result.base.manaLeft then lines[#lines + 1] = f end
    end
    if result.base.variant then lines[#lines + 1] = { text = "Rotation", variant = true } end
    local y = 34 + shownBars * 21 + 12
    local need = 14 + 22 + 20 + #lines * FIGHT_LINE
    if bars:GetHeight() - y - need < 8 then return end

    local width = bars:GetWidth() - 32
    local leftWidth = math.floor(width * 0.56)
    bars.line:SetPoint("TOPLEFT", 16, -y)
    bars.line:SetPoint("RIGHT", -16, 0)
    bars.line:Show()
    y = y + 14
    bars.fights:SetPoint("TOPLEFT", 16, -y)
    bars.fights:Show()
    local nameWidth = 170
    local columnWidth = math.floor((leftWidth - nameWidth) / #columns)
    local fights = {}
    for i, c in ipairs(columns) do
        fights[i] = FightNumbers(c.run, DB().length, self.model)
        local t = bars.columns[i]
        t:SetPoint("TOPLEFT", 16 + nameWidth + (i - 1) * columnWidth, -(y + 22))
        t:SetWidth(columnWidth - 8)
        t:SetText(Util.Upper(c.label))
        t:Show()
    end
    for k, f in ipairs(lines) do
        local l = bars.lines[k]
        local ly = y + 22 + 20 + (k - 1) * FIGHT_LINE
        l.name:SetPoint("TOPLEFT", 16, -ly)
        l.name:SetWidth(nameWidth - 10)
        l.name:SetText(L(f.text))
        l.name:Show()
        for i, c in ipairs(columns) do
            local v = l.values[i]
            v:SetPoint("TOPLEFT", 16 + nameWidth + (i - 1) * columnWidth, -ly)
            v:SetWidth(columnWidth - 8)
            local color = C.text1
            if f.variant then
                v:SetText(c.run.variant and SimUI.VariantText(self.model, c.run.variant) or "-")
                if i > 1 and c.run.variant == result.base.variant then color = C.text3 end
            else
                local n, worn = fights[i][f.key], fights[1][f.key]
                local text = n and string.format(f.format, n) or "-"
                v:SetText(text)
                if i > 1 and n and worn and text ~= string.format(f.format, worn) then
                    color = (n - worn) * f.better > 0 and C.ok or C.bad
                end
            end
            SetColor(v, color)
            v:Show()
        end
    end

    -- the abilities of the best set
    local top = best
    if not top then
        for i = 2, #sets do
            local n = numbers[i]
            if n and n.sources and (not top or n.dps > numbers[top].dps) then top = i end
        end
    end
    if not top then return end
    local gains = {}
    for key, v in pairs(numbers[top].sources) do
        if math.abs(v) >= 0.05 then gains[#gains + 1] = { key = key, v = v } end
    end
    table.sort(gains, function(a, b)
        if math.abs(a.v) ~= math.abs(b.v) then return math.abs(a.v) > math.abs(b.v) end
        return a.key < b.key
    end)
    local x = 16 + leftWidth + 34
    bars.divider:SetPoint("TOPLEFT", 16 + leftWidth + 17, -y)
    bars.divider:SetHeight(need - 14)
    bars.divider:Show()
    bars.gain:SetPoint("TOPLEFT", x, -y)
    bars.gain:SetPoint("RIGHT", -16, 0)
    bars.gain:SetText(Util.Upper(F("%s: %s", sets[top].label, L("Where the difference comes from"))))
    bars.gain:Show()
    local room = math.floor((bars:GetHeight() - y - 22 - 8) / GAIN_LINE)
    local most = gains[1] and math.abs(gains[1].v) or 0
    for k, r in ipairs(bars.gainRows) do
        local e = k <= room and gains[k]
        if e then
            r:SetPoint("TOPLEFT", x, -(y + 22 + (k - 1) * GAIN_LINE))
            r:SetPoint("RIGHT", -16, 0)
            local name, icon = self:Source(e.key)
            r.icon:SetTexture(icon)
            r.name:SetText(name)
            r.value:SetText(F("%s DPS", Signed(e.v)))
            SetColor(r.value, e.v > 0 and C.ok or C.bad)
            r.bar:SetProgress(most > 0 and math.abs(e.v) / most or 0, e.v > 0 and C.ok or C.bad)
            r:Show()
        end
    end
end

---------------------------------------------------------------------------
-- Planner: the slots of an own set as a doll; a click on a slot opens its picker (what is worn, the set's item, the
-- sheet's, the sim's picks, the bag items, or a search), an item dragged onto a slot goes in
---------------------------------------------------------------------------
-- The slot whose picker is open is marked.
local function TileVisual(t)
    Widgets.BoxFill(t.fill, t.ring, t.picked and "pick" or "row", t.hovered)
end

function SimUI:CreatePlanTile(page, slot, x, y, width, right)
    local t = CreateFrame("Button", nil, page)
    t:SetSize(width, TILE_HEIGHT)
    t:SetPoint("TOPLEFT", x, -y)
    t.slot, t.x, t.y, t.right = slot, x, y, right
    t.fill = Widgets.CreateBox(t, "BACKGROUND", 1, 8)
    t.ring = Widgets.CreateBox(t, "BACKGROUND", 2, 8, true)
    t.icon = Widgets.CreateItemIcon(t, 32)
    t.icon:EnableMouse(false)
    t.empty = t:CreateTexture(nil, "ARTWORK")
    t.empty:SetSize(32, 32)
    t.empty:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.name = Widgets.Text(t, "item", C.text1)
    t.sub = Widgets.Text(t, "small", C.text3)
    -- a slot with an item: empty again
    t.reset = Widgets.CreateButton(t, nil, "icon", "close", 20, 20)
    t.reset:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:SetPlanItem(slot, nil)
    end)
    Widgets.SetTooltip(t.reset, "Remove from this set", nil, "ANCHOR_TOP")
    local side, toward = right and "RIGHT" or "LEFT", right and "LEFT" or "RIGHT"
    local dx = right and -1 or 1
    t.icon:SetPoint(side, 6 * dx, 0)
    t.empty:SetPoint(side, 6 * dx, 0)
    t.reset:SetPoint(toward, -6 * dx, 0)
    t.name:SetPoint("TOP" .. side, t.icon, "TOP" .. toward, 9 * dx, -1)
    t.sub:SetPoint("BOTTOM" .. side, t.icon, "BOTTOM" .. toward, 9 * dx, 1)
    for _, fs in ipairs({ t.name, t.sub }) do
        fs:SetWidth(width - 6 - 32 - 9 - 30)
        fs:SetJustifyH(side)
        fs:SetWordWrap(false)
    end
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    t:SetScript("OnClick", function(b, button) self:PlanTileClick(b, button) end)
    t:SetScript("OnReceiveDrag", function(b) self:DropOnTile(b) end)
    t:SetScript("OnEnter", function(b)
        b.hovered = true
        TileVisual(b)
        if b.off then return end
        local hint = { LJ.Tooltip.Hint("Click to pick another item, or drop one here.") }
        if b.itemID then
            Widgets.ShowItemTooltip(b, b.itemID, hint)
        else
            GameTooltip:SetOwner(b, Widgets.TooltipAnchor(b))
            GameTooltip:SetText(SlotName(slot), 1, 1, 1)
            GameTooltip:AddLine(hint[1][1], hint[1][2], hint[1][3], hint[1][4])
            GameTooltip:Show()
        end
    end)
    t:SetScript("OnLeave", function(b)
        b.hovered = false
        TileVisual(b)
        GameTooltip:Hide()
    end)
    Theme.OnAccent(t, TileVisual)
    return t
end

-- The name line of the set the planner shows: Enter or leaving the line keeps the name, Escape takes it back; an empty
-- line gives the set its "Set n" again.
local NAME_MAX = 16
function SimUI:CreateNameBox(page)
    local box = CreateFrame("EditBox", nil, page)
    box:SetSize(150, 26)
    box:SetAutoFocus(false)
    box:SetMaxLetters(NAME_MAX)
    box:SetFontObject(Theme.Font("bodySmall"))
    box:SetTextColor(C.text1[1], C.text1[2], C.text1[3])
    box:SetTextInsets(9, 9, 0, 0)
    Widgets.InputPanel(box)
    box.placeholder = Widgets.Text(box, "small", C.text4)
    box.placeholder:SetPoint("LEFT", 9, 0)
    box.placeholder:SetPoint("RIGHT", -9, 0)
    box.placeholder:SetText(L("Name this set"))
    local function Keep(b)
        local text = strtrim(b:GetText() or "")
        LJ.cdb.planNames[DB().set] = text ~= "" and text or nil
        self:Refresh()
        LJ:Fire("PLANS_CHANGED")
    end
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(b)
        b:SetText(LJ.cdb.planNames[DB().set] or "")
        b:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", InputVisual)
    box:SetScript("OnEditFocusLost", function(b)
        InputVisual(b)
        Keep(b)
    end)
    box:SetScript("OnTextChanged", InputVisual)
    Widgets.SetTooltip(box, "Name this set", "Enter keeps the name. Empty: the set's number again.", "ANCHOR_TOP")
    return box
end

function SimUI:CreatePlan(body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    -- the toolbar: the set shown; what it starts from (empty, what is worn, the Best in Slot sheet)
    page.planning = Widgets.Text(page, "label", C.text4)
    page.planning:SetPoint("TOPLEFT", 0, -8)
    page.planning:SetText(Util.Upper(L("Planning")))
    page.chips = {}
    local left = page.planning
    for n = 1, PLANS do
        local chip = Chip(page, "", function()
            page.name:ClearFocus()   -- a name being typed belongs to the set shown so far
            DB().set = n
            self:HidePicker()
            self:Refresh()
        end)
        chip:SetPoint("LEFT", left, "RIGHT", n == 1 and 10 or 6, 0)
        left = chip
        page.chips[n] = chip
    end
    page.name = self:CreateNameBox(page)
    page.name:SetPoint("LEFT", left, "RIGHT", 10, 0)
    page.fromSheet = Widgets.CreateButton(page, "Best in Slot", "ghost", "crown", nil, 26)
    page.fromSheet:SetPoint("TOPRIGHT", 0, -1)
    page.fromSheet:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:StartPlan("sheet")
    end)
    Widgets.SetTooltip(page.fromSheet, "Best in Slot", "Puts the items of your Best in Slot sheet in this set.", "ANCHOR_TOP")
    page.fromWorn = Widgets.CreateButton(page, "What I wear", "ghost", "user", nil, 26)
    page.fromWorn:SetPoint("RIGHT", page.fromSheet, "LEFT", -6, 0)
    page.fromWorn:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:StartPlan("worn")
    end)
    Widgets.SetTooltip(page.fromWorn, "What I wear", "Puts what you wear in this set.", "ANCHOR_TOP")
    page.clear = Widgets.CreateButton(page, "Empty", "ghost", "xCircle", nil, 26)
    page.clear:SetPoint("RIGHT", page.fromWorn, "LEFT", -6, 0)
    page.clear:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:StartPlan("empty")
    end)
    Widgets.SetTooltip(page.clear, "Empty", "Takes every item out of this set.", "ANCHOR_TOP")
    page.startFrom = Widgets.Text(page, "label", C.text4)
    page.startFrom:SetPoint("RIGHT", page.clear, "LEFT", -10, 0)
    page.startFrom:SetText(Util.Upper(L("Start from")))
    -- the doll: two columns of slots, the weapons below
    page.tiles = {}
    for i, slot in ipairs(BiS.LEFT_SLOTS) do
        page.tiles[#page.tiles + 1] = self:CreatePlanTile(page, slot, 0, PLAN_TOP + (i - 1) * TILE_STEP, TILE_WIDTH, false)
    end
    for i, slot in ipairs(BiS.RIGHT_SLOTS) do
        page.tiles[#page.tiles + 1] = self:CreatePlanTile(page, slot, BODY_WIDTH - TILE_WIDTH,
            PLAN_TOP + (i - 1) * TILE_STEP, TILE_WIDTH, true)
    end
    local weaponWidth = (BODY_WIDTH - 12) / 3
    local weaponTop = PLAN_TOP + #BiS.LEFT_SLOTS * TILE_STEP + 8
    for i, slot in ipairs(BiS.WEAPON_SLOTS) do
        local t = self:CreatePlanTile(page, slot, (i - 1) * (weaponWidth + 6), weaponTop, weaponWidth, i == #BiS.WEAPON_SLOTS)
        t.weapon = true
        page.tiles[#page.tiles + 1] = t
    end
    -- between the columns: the set against what is worn, then where the difference comes from
    local mid = TILE_WIDTH + 12
    local card = Card(page)
    card:SetPoint("TOPLEFT", mid, -PLAN_TOP)
    card:SetHeight(118)
    card.big = Widgets.Text(card, "hero", C.white)
    card.big:SetPoint("TOPLEFT", 16, -36)
    card.unit = Widgets.Text(card, "big", Theme.accent)
    card.unit:SetPoint("BOTTOMLEFT", card.big, "BOTTOMRIGHT", 6, 4)
    card.unit:SetText(L("DPS"))
    card.delta = Widgets.Text(card, "nameBold", C.text3, nil, "RIGHT")
    card.delta:SetPoint("TOPRIGHT", -16, -50)
    card.note = Widgets.Text(card, "small", C.text3)
    card.note:SetPoint("TOPLEFT", card.big, "BOTTOMLEFT", 0, -10)
    card.note:SetPoint("RIGHT", -16, 0)
    card.note:SetJustifyH("LEFT")
    card.note:SetWordWrap(true)
    page.card = card
    local src = Card(page)
    src:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -12)
    src.label:SetText(Util.Upper(L("Damage by ability")))
    src.rows = {}
    for i = 1, 8 do
        local r = CreateFrame("Frame", nil, src)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 16, -36 - (i - 1) * 25)
        r:SetPoint("RIGHT", -16, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = Widgets.Text(r, "bodySmall", C.text1)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetWidth(130)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.value = Widgets.Text(r, "smallSemi", C.text1, nil, "RIGHT")
        r.value:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.value:SetWidth(40)
        r.share = Widgets.Text(r, "small", C.text3, nil, "RIGHT")
        r.share:SetPoint("RIGHT")
        r.share:SetWidth(36)
        r.share:SetJustifyH("RIGHT")
        r.bar = Widgets.CreateProgressBar(r, 7)
        r.bar:SetPoint("LEFT", r.value, "RIGHT", 10, 0)
        r.bar:SetPoint("RIGHT", r.share, "LEFT", -8, 0)
        r:Hide()
        src.rows[i] = r
    end
    src.hint = Widgets.Text(src, "bodySmall", C.text3)
    src.hint:SetPoint("LEFT", 20, -10)
    src.hint:SetPoint("RIGHT", -20, -10)
    src.hint:SetJustifyH("CENTER")
    src.hint:SetWordWrap(true)
    src.hint:SetText(L("Click a slot to pick an item, or drag an item from your bags onto it. After Sim: the damage of each ability."))
    page.sources = src
    -- the right column at the right edge, the weapons along the bottom, the middle between them gets the room
    function page:Layout(w, h)
        local top = math.max(weaponTop, h - TILE_HEIGHT - 4)
        local width = math.floor((w - 12) / 3)
        local n = 0
        for _, t in ipairs(self.tiles) do
            if t.weapon then
                t.x, t.y = n * (width + 6), top
                t:SetWidth(width)
                t.name:SetWidth(width - 6 - 32 - 9 - 30)
                t.sub:SetWidth(width - 6 - 32 - 9 - 30)
                n = n + 1
            elseif t.right then
                t.x = w - TILE_WIDTH
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", t.x, -t.y)
        end
        self.card:SetWidth(w - 2 * mid)
        self.sources:SetSize(w - 2 * mid, top - 12 - (PLAN_TOP + 118 + 12))
    end
    page.picker = self:CreatePicker(page)
    return page
end

-- The picker beside a slot: a search line and the "Higher levels" switch, then every item the character can wear there
-- (each with its number: SimUI.ItemNumber; the mouse wheel scrolls through them; with the switch on also those of
-- higher levels, each with its level),
-- or those whose name has the words typed.
function SimUI:CreatePicker(page)
    local p = CreateFrame("Frame", nil, page)
    p:SetWidth(PICK_WIDTH)
    p:SetFrameLevel(page:GetFrameLevel() + 40)
    p:EnableMouse(true)
    -- items: the slot's items (SimUI.SlotItems); found: how many show with the words typed; shown: the rows that fit;
    -- offset: the items found above the first row
    p.offset = 0
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        local offset = math.max(0, math.min(p.found - p.shown, p.offset - delta))
        if offset ~= p.offset then
            p.offset = offset
            self:ShowPicker()
        end
    end)
    Widgets.CreateShadow(p, 12, 0.7)
    p.panel = Widgets.CreatePopupPanel(p, 10)
    p.slotName = Widgets.Text(p, "label", Theme.accent)
    p.slotName:SetPoint("TOPLEFT", 12, -14)
    p.title = Widgets.Text(p, "nameBold", C.text1)
    p.title:SetPoint("LEFT", p.slotName, "RIGHT", 8, 0)
    p.close = Widgets.CreateButton(p, nil, "icon", "close", 22, 22)
    p.close:SetPoint("TOPRIGHT", -6, -7)
    p.close:SetScript("OnClick", function() self:HidePicker() end)
    Theme.OnAccent(p, function(x, r, g, b) x.slotName:SetTextColor(r, g, b) end)
    p.search = Widgets.CreateSearchBox(p, PICK_WIDTH - 24, "Search name or source", function()
        p.offset = 0
        self:ShowPicker()
    end)
    p.search:SetPoint("TOPLEFT", 12, -38)
    -- the items of higher levels too (kept: LJ.db.sim.higher)
    p.higher = Widgets.CreateToggle(p, "Higher levels",
        "Also the items your class can put on from a higher level, up to 60. The sim counts them as if you could wear them now.")
    p.higher:SetPoint("TOPLEFT", 12, -68)
    p.higher.onChange = function(_, on)
        DB().higher = on
        p.items, p.offset = SimUI.SlotItems(self.spec, p.tile.slot, DB().set, DB().higher), 0
        self:ShowPicker()
    end
    p.rows = {}
    for i = 1, PICK_ROWS do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(PICK_ROW_HEIGHT)
        r:SetPoint("TOPLEFT", 8, -PICK_TOP - (i - 1) * (PICK_ROW_HEIGHT + 3))
        r:SetPoint("RIGHT", -8, 0)
        r.fill = Widgets.CreateBox(r, "BACKGROUND", 1, 6)
        r.ring = Widgets.CreateBox(r, "BACKGROUND", 2, 6, true)
        r.icon = Widgets.CreateItemIcon(r, 28)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:EnableMouse(false)
        r.name = Widgets.Text(r, "item", C.text1)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
        r.sub = Widgets.Text(r, "small", C.text3)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        for _, fs in ipairs({ r.name, r.sub }) do
            fs:SetWidth(PICK_WIDTH - 16 - 4 - 28 - 8 - 90)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
        end
        r.gain = Widgets.Text(r, "smallSemi", C.ok, nil, "RIGHT")
        r.gain:SetPoint("TOPRIGHT", -6, -5)
        r.tag = Widgets.Text(r, "small", C.text3, nil, "RIGHT")
        r.tag:SetPoint("BOTTOMRIGHT", -6, 5)
        r:SetScript("OnEnter", function(b)
            b.hovered = true
            RowVisual(b)
            Widgets.ShowItemTooltip(b, b.itemID)
        end)
        r:SetScript("OnLeave", function(b)
            b.hovered = false
            RowVisual(b)
            GameTooltip:Hide()
        end)
        r:SetScript("OnClick", function(b)
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            self:SetPlanItem(p.tile.slot, b.itemID)
        end)
        r:Hide()
        p.rows[i] = r
    end
    p.empty = Widgets.Text(p, "small", C.text3)
    p.empty:SetPoint("TOPLEFT", 14, -PICK_TOP - 4)
    p.empty:SetText(L("No items found."))
    p.more = Widgets.Text(p, "small", C.text4)
    p.more:SetJustifyH("LEFT")
    p.note = Widgets.Text(p, "small", C.text4)
    p.note:SetPoint("LEFT", 14, 0)
    p.note:SetPoint("RIGHT", -14, 0)
    p.note:SetJustifyH("LEFT")
    p:Hide()
    return p
end

-- The items in the bags that go in a slot, the player can put on now (SimBiS.CanWear) and the simulator has numbers for.
local function BagItems(slot)
    local out = {}
    for bag = 0, Constants.InventoryConstants.NumBagSlots do
        for i = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, i)
            if id and SimBiS.Fits(id, slot) and SimBiS.CanWear(id) and Simmable(id) then out[#out + 1] = id end
        end
    end
    return out
end

-- The lists below, kept per class and level.
local wearable, wearableKey
local function Kept()
    local key = Player.class .. ":" .. (Player.level or 1)
    if wearableKey ~= key then wearable, wearableKey = {}, key end
    return wearable
end

-- Every item of the addon with shipped data (the search's: UI.SearchItemIDs) the player can put on now, whatever the
-- simulator makes of it (SimBiS.CanWear), by sheet slot. { [sheet slot] = { item IDs } }
local function WearableItems()
    local kept = Kept()
    if kept.now then return kept.now end
    local out = {}
    for _, id in ipairs(UI.SearchItemIDs()) do
        if Simmable(id) and SimBiS.CanWear(id) then
            for _, slot in ipairs(SimBiS.SheetSlots(id) or {}) do
                out[slot] = out[slot] or {}
                table.insert(out[slot], id)
            end
        end
    end
    kept.now = out
    return out
end

-- The same of the items the player can put on from a higher level up to the top one (the picker's "Higher levels",
-- made the first time it is on): { [sheet slot] = { item IDs } }, { [item ID] = that level (SimBiS.WearLevel) }.
local function HigherItems()
    local kept = Kept()
    if kept.higher then return kept.higher, kept.levels end
    local out, levels, now = {}, {}, Player.level or 1
    for _, id in ipairs(UI.SearchItemIDs()) do
        local level = Simmable(id) and SimBiS.WearLevel(id)
        if level and level > now then
            levels[id] = level
            for _, slot in ipairs(SimBiS.SheetSlots(id) or {}) do
                out[slot] = out[slot] or {}
                table.insert(out[slot], id)
            end
        end
    end
    kept.higher, kept.levels = out, levels
    return out, levels
end

-- The items of a slot to pick from (the planner's picker, the Best in Slot page's), each once: what is worn, own set
-- n's item (n nil: none), the Best in Slot sheet's, the sim's picks with a gain (the last sim Best in Slot) and the bag
-- items first, then the items of the list (Items.InList: the sources the player picked) the player can put on there
-- (WearableItems): by the hidden ranking the sheet's own first, then the rest of the ranking (a tank's lighter armor,
-- tagged), then the others by item level; with higher, last, the list's items of higher levels (HigherItems: their
-- sources up to the top level), the nearest level first, each tagged with its level. { { id, tag, higher } }
function SimUI.SlotItems(spec, slot, n, higher)
    local out, seen = {}, {}
    local function Add(id, tag, high)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, tag = tag, higher = high }
        end
    end
    Add(Worn(slot), L("worn now"))
    if n then Add(LJ.cdb.plans[n][slot], F(L("in %s"), SimUI.PlanName(n))) end
    local sheet = BiS.ResolveSlot(spec, slot, BiS.Ranking(spec))
    if sheet and Simmable(sheet) then Add(sheet, L("Best in Slot")) end
    local rec = SimBiS.Get(spec)
    for _, row in ipairs(rec and rec.slots[slot] and rec.slots[slot].rows or {}) do
        if not row.failed and SimBiS.Shows(row.delta, row.err) then Add(row.id, "") end
    end
    for _, id in ipairs(BagItems(slot)) do Add(id, L("in your bags")) end
    local level = BiS.ListLevel(spec)
    local all, inAll = WearableItems()[slot] or {}, {}
    for _, id in ipairs(all) do inAll[id] = true end
    -- the sheet's items by rank, then the rest of the ranking (the list's items: Core/Scoring.lua)
    local ranking = BiS.Ranking(spec)
    local _, _, dataSlot, ranked = BiS.RankedPick(spec, slot, ranking)
    for _, x in ipairs(ranked or {}) do
        if inAll[x.id] then Add(x.id, "") end
    end
    for _, x in ipairs(dataSlot and ranking.bySlot[dataSlot] or {}) do
        if inAll[x.id] then Add(x.id, "") end
    end
    local rest, levels = {}, {}
    for _, id in ipairs(all) do
        if not seen[id] and Items.InList(id, spec.class, level) then
            rest[#rest + 1] = id
            levels[id] = select(2, Items.GetKnownLevels(id)) or 0
        end
    end
    table.sort(rest, function(a, b)
        if levels[a] ~= levels[b] then return levels[a] > levels[b] end
        return a < b
    end)
    for _, id in ipairs(rest) do Add(id, "") end
    if higher then
        local above, from = HigherItems()
        local later = {}
        for _, id in ipairs(above[slot] or {}) do
            if not seen[id] and Items.InList(id, spec.class, BiS.MAX_LEVEL) then
                later[#later + 1] = id
                levels[id] = select(2, Items.GetKnownLevels(id)) or 0
            end
        end
        table.sort(later, function(a, b)
            if from[a] ~= from[b] then return from[a] < from[b] end
            if levels[a] ~= levels[b] then return levels[a] > levels[b] end
            return a < b
        end)
        for _, id in ipairs(later) do Add(id, F(L("Level %d"), from[id]), true) end
    end
    -- a tank's lighter armor (BiS.ArmorFits): the sheet leaves it to the slot's list
    for _, e in ipairs(out) do
        if e.tag == "" and not BiS.ArmorFits(spec, e.id, level) then e.tag = L("Lighter armor") end
    end
    return out
end

-- The number beside an item of a slot (the pickers): with Sim what the last Best in Slot sim found it adds there, with
-- Percent the share it adds by the stat weights (LJ.ItemCheck.SlotShare); nil for what is worn and an item without
-- one. text, color
function SimUI.ItemNumber(spec, slot, id)
    if id == Worn(slot) then return nil end
    if SimUI.RanksItems(spec) then
        local gain = SimBiS.SlotGain(spec, slot, id)
        if not gain then return nil end
        return F("%s DPS", Signed(gain.delta)), DeltaColor(gain.delta, gain.err)
    end
    local pct = LJ.ItemCheck.SlotShare(spec, slot, id)
    if not pct then return nil end
    local dir = LJ.ItemCheck.StatsDirection({ pct = pct })
    return Signed(pct) .. "%", dir == "up" and C.ok or dir == "down" and C.bad or C.text3
end

-- The note under the pickers' items: what their numbers are (shown: some have one); Sim without a Best in Slot sim:
-- the sim finds them. nil: no note.
function SimUI.NumbersNote(spec, shown)
    local damage = SimUI.RanksItems(spec)
    if damage and not SimBiS.Get(spec) then return L("No DPS yet: the Best in Slot sim finds what the best items add.") end
    if not shown then return nil end
    return L(damage and "+DPS: your last Best in Slot sim, item by item." or "%: the upgrade by your stat weights.")
end

function SimUI:HidePicker()
    local page = self.frame and self.frame.pages.plan
    if not (page and page.picker:IsShown()) then return end
    local t = page.picker.tile
    page.picker:Hide()
    t.picked = false
    TileVisual(t)
end

-- Opens the picker of a slot, or closes it when it shows that slot.
function SimUI:TogglePicker(t)
    local p = self.frame.pages.plan.picker
    if p:IsShown() and p.tile == t then
        self:HidePicker()
        return
    end
    self:HidePicker()
    p.tile = t
    t.picked = true
    TileVisual(t)
    p.items, p.offset = SimUI.SlotItems(self.spec, t.slot, DB().set, DB().higher), 0
    p.search:SetText("")
    p.higher:SetChecked(DB().higher)
    p:Show()
    self:ShowPicker()
end

-- The picker's rows (the slot's items, those whose name has the words typed), as many as fit the page; its size and
-- place: beside its slot (the weapons: above it), inside the page.
function SimUI:ShowPicker()
    local p = self.frame.pages.plan.picker
    if not p:IsShown() then return end
    local t = p.tile
    local slot = t.slot
    local n = DB().set
    p.slotName:SetText(Util.Upper(SlotName(slot)))
    p.title:SetText(F(L("Pick an item for %s"), SimUI.PlanName(n)))
    local ids, entries = {}, {}
    for i, e in ipairs(p.items) do ids[i], entries[e.id] = e.id, e end
    local found = UI.FilterItems(ids, p.search:GetText() or "")
    -- (above the rows PICK_TOP, below them the more line and the note: 42)
    p.shown = math.max(1, math.min(PICK_ROWS,
        math.floor((self.frame.pages.plan:GetHeight() - PICK_TOP - 42) / (PICK_ROW_HEIGHT + 3))))
    p.found = #found
    p.offset = math.max(0, math.min(p.found - p.shown, p.offset))
    local list = {}
    for i = 1, math.min(p.found - p.offset, p.shown) do list[i] = entries[found[p.offset + i]] end
    local planned = LJ.cdb.plans[n][slot]
    local gains = false
    for i, r in ipairs(p.rows) do
        local e = list[i]
        r:SetShown(e ~= nil)
        if e then
            local rec = Items.Get(e.id)
            r.itemID = e.id
            r.selected = e.id == planned
            RowVisual(r)
            r.icon:SetItem(e.id)
            r.name:SetText(Items.GetName(e.id))
            r.name:SetTextColor(Util.QualityColor(rec.quality or 1))
            r.sub:SetText(BiS.SourceText(e.id) or "")
            r.tag:SetText(e.tag)
            SetColor(r.tag, e.higher and C.warn or C.text3)
            local text, color = SimUI.ItemNumber(self.spec, slot, e.id)
            r.gain:SetText(text or "")
            if text then
                SetColor(r.gain, color)
                gains = true
            end
        end
    end
    p.empty:SetShown(#list == 0)
    local height = PICK_TOP + math.max(1, #list) * (PICK_ROW_HEIGHT + 3) + 6
    -- more found than rows: which ones show, the wheel shows the others
    local more = p.found > p.shown
    p.more:SetShown(more)
    if more then
        p.more:SetText(F(L("%d-%d of %d found · scroll for more"), p.offset + 1, p.offset + #list, p.found))
        p.more:ClearAllPoints()
        p.more:SetPoint("TOPLEFT", 14, -height)
        p.more:SetPoint("RIGHT", -14, 0)
        height = height + 18
    end
    local note = SimUI.NumbersNote(self.spec, gains)
    p.note:SetShown(note ~= nil)
    if note then
        p.note:SetText(note)
        p.note:ClearAllPoints()
        p.note:SetPoint("TOPLEFT", 14, -height)
        p.note:SetPoint("RIGHT", -14, 0)
        height = height + 18
    end
    p:SetHeight(height)
    local x, y
    if t.weapon then
        x = t.right and (t.x + t:GetWidth() - PICK_WIDTH) or t.x
        y = t.y - 6 - height
    elseif t.right then
        x, y = t.x - 8 - PICK_WIDTH, t.y
    else
        x, y = t.x + t:GetWidth() + 8, t.y
    end
    y = math.max(0, math.min(y, self.frame.pages.plan:GetHeight() - height))
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", x, -y)
end

-- A slot clicked: an item on the cursor goes in; else its picker opens (the off hand beside a two-hander has none).
function SimUI:PlanTileClick(t, button)
    if button == "LeftButton" and BiS.CursorItem() then
        self:DropOnTile(t)
        return
    end
    if t.itemID and Items.HandleClick(t.itemID, button) then return end
    if button == "RightButton" then
        if t.itemID then Widgets.ShowItemMenu(t, t.itemID) end
        return
    end
    if t.off then return end
    Util.PlaySound("U_CHAT_SCROLL_BUTTON")
    self:TogglePicker(t)
end

-- An item dropped on a slot: it goes in that slot, or in its own slot when it is for another one.
function SimUI:DropOnTile(t)
    local id = BiS.CursorItem()
    if not id then return end
    ClearCursor()
    self:PutInPlan(SimBiS.Fits(id, t.slot) and t.slot or (SimBiS.SheetSlots(id) or {})[1], id)
end

-- Puts an item in a slot of the set the planner shows (an item dropped on a slot; one the player can put
-- on now or from a higher level: SimBiS.WearLevel); the chat says why one cannot go in.
function SimUI:PutInPlan(slot, id)
    if not (slot and SimBiS.Fits(id, slot) and SimBiS.WearLevel(id)) then
        LJ:Print("Your character cannot wear this item.")
    elseif not Simmable(id) then
        LJ:Print("The simulator has no numbers for this item.")
    elseif slot == "OFFHAND" and IsTwoHand(LJ.cdb.plans[DB().set].MAINHAND) then
        LJ:Print("Two-hander in the main hand")
    else
        self:SetPlanItem(slot, id)
    end
end

-- An own set changed: its numbers (and those of the Sets tab) no longer fit; a running sim of them stops. The Best in
-- Slot page shows the sets too (PLANS_CHANGED).
function SimUI:PlanChanged()
    if self.running and (self.running.view == "plan" or self.running.view == "sets") then self:Cancel() end
    self.results.plan, self.results.sets = nil, nil
    self:Refresh()
    LJ:Fire("PLANS_CHANGED")
end

-- Puts an item in a slot of own set n (nil: the slot is empty again; the planner, the Best in Slot page). A two-hander
-- in the main hand leaves no off hand.
function SimUI.PutInSet(n, slot, id)
    local plan = LJ.cdb.plans[n]
    plan[slot] = id
    if IsTwoHand(plan.MAINHAND) then plan.OFFHAND = nil end
    SimUI:PlanChanged()
end

-- Puts an item in a slot of the set the planner shows (nil: the slot is empty again).
function SimUI:SetPlanItem(slot, id)
    self:HidePicker()
    SimUI.PutInSet(DB().set, slot, id)
end

-- Own set n starts again: empty ("empty"), or with what is worn ("worn") or the Best in Slot sheet's items of a spec
-- ("sheet"); items that do not fit the slot or the simulator has no numbers for stay out (the chat names them). The
-- caller says it changed (SimUI:PlanChanged).
function SimUI.FillSet(n, from, spec)
    local plan = wipe(LJ.cdb.plans[n])
    if from ~= "empty" then
        local ranking = from == "sheet" and BiS.Ranking(spec)
        local left = {}
        for _, slot in ipairs(BiS.SLOTS) do
            local id
            if from == "sheet" then id = BiS.ResolveSlot(spec, slot, ranking) else id = Worn(slot) end
            if id and SimBiS.Fits(id, slot) and Simmable(id) then
                plan[slot] = id
            elseif id then
                left[#left + 1] = Items.GetName(id)
            end
        end
        if IsTwoHand(plan.MAINHAND) then plan.OFFHAND = nil end
        if #left > 0 then LJ:Print("Not in the set, the simulator has no numbers for: %s", table.concat(left, ", ")) end
    end
end

-- "Start from" of the set the planner shows.
function SimUI:StartPlan(from)
    self:HidePicker()
    SimUI.FillSet(DB().set, from, self.spec)
    self:PlanChanged()
end

function SimUI:ShowPlan()
    local page = self.frame.pages.plan
    local n = DB().set
    local plan = LJ.cdb.plans[n]
    for i, chip in ipairs(page.chips) do
        chip:SetLabel(SimUI.PlanName(i), "bookmark", true)
        chip:SetActive(i == n)
    end
    if not page.name:HasFocus() then page.name:SetText(LJ.cdb.planNames[n] or "") end
    -- only the set's items; its two-hander leaves no off hand. Percent: each item with the share it adds there by the
    -- stat weights (as in the pickers: SimUI.ItemNumber), the set with its own (ItemCheck.SetShare), no sim needed
    local twoHand = IsTwoHand(plan.MAINHAND)
    local shares = not SimUI.RanksItems(self.spec)
    for _, t in ipairs(page.tiles) do
        local slot = t.slot
        local name, emptyIcon = SlotName(slot)
        t.off = slot == "OFFHAND" and twoHand
        local id = not t.off and plan[slot] or nil
        t.itemID = id
        t.reset:SetShown(id ~= nil)
        t:SetAlpha(t.off and 0.45 or 1)
        t.icon:SetShown(id ~= nil)
        t.empty:SetShown(id == nil)
        if id then
            t.icon:SetItem(id)
            t.name:SetText(Items.GetName(id))
            t.name:SetTextColor(Util.QualityColor(Items.Get(id).quality or 1))
        else
            t.empty:SetTexture(emptyIcon)
            t.name:SetText(L(t.off and "Two-hand weapon" or "Empty"))
            SetColor(t.name, C.text3)
        end
        -- an item of a higher level: its level
        local from = id and SimBiS.WearLevel(id)
        local higher = from and from > (Player.level or 1)
        local sub = t.off and L("Two-hander in the main hand") or higher and (name .. " · " .. F(L("Level %d"), from)) or name
        local number, color
        if shares and id then number, color = SimUI.ItemNumber(self.spec, slot, id) end
        t.sub:SetText(number and (sub .. " · " .. Theme.ColorText(number, color)) or sub)
        SetColor(t.sub, higher and C.warn or C.text3)
        TileVisual(t)
    end
    -- the numbers of the set on its own: its damage once simmed; Percent its share by the stat weights (an empty set
    -- none), its damage beside it once simmed
    local set = self:PlanSet(n)
    local card = page.card
    card.label:SetText(Util.Upper(set.label))
    card.unit:SetText(shares and "%" or L("DPS"))
    local result = self.results.plan
    local run = result and result.run
    local simming = self.running and self.running.view == "plan"
    if shares then
        local pct = not set.empty and LJ.ItemCheck.SetShare(self.spec, function(slot) return set.bySlot[slot] end)
        card.big:SetText(pct and Signed(pct) or "-")
        card.delta:SetText(run and F("%s DPS (±%.1f)", string.format("%.1f", run.dps), run.error)
            or simming and L("Simming ...") or pct and L("by your stats") or "")
    elseif run then
        card.big:SetText(string.format("%.1f", run.dps))
        card.delta:SetText(F(L("±%.1f DPS"), run.error))
    else
        card.big:SetText("-")
        card.delta:SetText((set.empty or set.missing or (result and result.failed)) and ""
            or L(simming and "Simming ..." or "Not simmed yet"))
    end
    SetColor(card.delta, C.text3)
    card.note:SetText(result and result.failed and F(L("Could not sim this set: %s"), (result.failed:gsub("^.-:%d+: ", "")))
        or PlanNote(set, SwingHands(self.char, self.model)))
    -- the set's damage by ability (Sim.TallyResult: biggest first)
    local src = page.sources
    local sources = run and run.sources or {}
    src.hint:SetShown(run == nil)
    local top = sources[1] and sources[1].dps or 0
    for i, r in ipairs(src.rows) do
        local e = sources[i]
        r:SetShown(e ~= nil)
        if e then
            local name, icon = self:Source(e.key)
            r.icon:SetTexture(icon)
            r.name:SetText(name)
            r.value:SetText(string.format("%.1f", e.dps))
            r.share:SetText(string.format("%.0f%%", e.share * 100))
            r.bar:SetProgress(top > 0 and e.dps / top or 0, i == 1 and C.text4 or nil)
        end
    end
    if page.picker:IsShown() then self:ShowPicker() end
end

---------------------------------------------------------------------------
-- My damage
---------------------------------------------------------------------------
function SimUI:CreateOwn(body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    local left = Card(page)
    left:SetPoint("TOPLEFT")
    left:SetSize(300, CARD_HEIGHT)
    left.label:SetText(Util.Upper(L("Your damage")))
    left.big = Widgets.Text(left, "hero", C.white)
    left.big:SetPoint("TOPLEFT", 16, -40)
    left.unit = Widgets.Text(left, "big", Theme.accent)
    left.unit:SetPoint("BOTTOMLEFT", left.big, "BOTTOMRIGHT", 6, 4)
    left.unit:SetText(L("DPS"))
    left.sub = Widgets.Text(left, "small", C.text3)
    left.sub:SetPoint("TOPLEFT", left.big, "BOTTOMLEFT", 0, -6)
    left.lines = {}
    for i = 1, 4 do
        local l = CreateFrame("Frame", nil, left)
        l:SetHeight(26)
        l:SetPoint("TOPLEFT", 16, -108 - (i - 1) * 32)
        l:SetPoint("RIGHT", -16, 0)
        l.name = Widgets.Text(l, "bodySmall", C.text2)
        l.name:SetPoint("LEFT")
        l.value = Widgets.Text(l, "nameBold", C.white, nil, "RIGHT")
        l.value:SetPoint("RIGHT")
        local sep = Kit.Line(l)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT")
        sep:SetPoint("BOTTOMRIGHT")
        left.lines[i] = l
    end
    page.left = left

    local right = Card(page)
    right:SetPoint("TOPLEFT", 316, 0)
    right:SetPoint("RIGHT")
    right:SetHeight(CARD_HEIGHT)
    right.label:SetText(Util.Upper(L("Damage by ability")))
    right.head = Widgets.Text(right, "small", C.text4, nil, "RIGHT")
    right.head:SetPoint("TOPRIGHT", -16, -14)
    right.head:SetText(L("DPS · share"))
    right.rows = {}
    for i = 1, SOURCE_ROWS do
        local r = CreateFrame("Frame", nil, right)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 16, -38 - (i - 1) * 27)
        r:SetPoint("RIGHT", -16, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = Widgets.Text(r, "bodySemi", C.text1)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 9, 0)
        r.name:SetWidth(150)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.share = Widgets.Text(r, "small", C.text3, nil, "RIGHT")
        r.share:SetPoint("RIGHT")
        r.share:SetWidth(40)
        r.dps = Widgets.Text(r, "nameBold", C.white, nil, "RIGHT")
        r.dps:SetPoint("RIGHT", r.share, "LEFT", -6, 0)
        r.dps:SetWidth(54)
        r.bar = Widgets.CreateProgressBar(r, 8)
        r.bar:SetPoint("LEFT", r.icon, "RIGHT", 170, 0)
        r.bar:SetPoint("RIGHT", r.dps, "LEFT", -12, 0)
        r:Hide()
        right.rows[i] = r
    end
    right.hint = Widgets.Text(right, "bodySmall", C.text3)
    right.hint:SetPoint("LEFT", 24, -10)
    right.hint:SetPoint("RIGHT", -24, -10)
    right.hint:SetJustifyH("CENTER")
    right.hint:SetWordWrap(true)
    right.hint:SetText(L("After Sim: the damage of every ability here, what one more point of each stat is worth below."))
    page.right = right

    local stats = Card(page)
    stats:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -12)
    stats:SetPoint("RIGHT")
    stats:SetHeight(76)
    stats.label:SetText(Util.Upper(L("What one more point is worth")))
    stats.chips = {}
    page.stats = stats

    page.known = Widgets.Text(page, "small", C.text4)
    page.known:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 2, -10)
    page.known:SetPoint("RIGHT", -2, 0)
    page.known:SetJustifyH("LEFT")
    page.known:SetWordWrap(true)

    -- under the text, when the window has the room: what the fights start from (SimUI:ShowRead)
    local function ReadCard()
        local card = Card(page)
        card.rows = {}
        for i = 1, READ_ROWS do
            local l = CreateFrame("Frame", nil, card)
            l:SetHeight(26)
            l:SetPoint("TOPLEFT", 16, -36 - (i - 1) * READ_STEP)
            l:SetPoint("RIGHT", -16, 0)
            l.name = Widgets.Text(l, "bodySmall", C.text2)
            l.name:SetPoint("LEFT")
            l.value = Widgets.Text(l, "nameBold", C.white, nil, "RIGHT")
            l.value:SetPoint("RIGHT")
            local sep = Kit.Line(l)
            sep:SetHeight(1)
            sep:SetPoint("BOTTOMLEFT")
            sep:SetPoint("BOTTOMRIGHT")
            card.rows[i] = l
        end
        return card
    end
    page.you = ReadCard()
    page.you:SetPoint("TOPLEFT", page.known, "BOTTOMLEFT", -2, -12)
    page.you:SetPoint("BOTTOMRIGHT", page, "BOTTOM", -6, 0)
    page.you.label:SetText(Util.Upper(L("You, as the sim read you")))
    page.target = ReadCard()
    page.target:SetPoint("TOPLEFT", page.you, "TOPRIGHT", 12, 0)
    page.target:SetPoint("BOTTOMRIGHT")
    return page
end

-- The label of a school's spell power (the addon's stat names, as the Database look's).
local SPELL_POWER = { holy = "Holy Spell Power", fire = "Fire Spell Power", nature = "Nature Spell Power",
    frost = "Frost Spell Power", shadow = "Shadow Spell Power", arcane = "Arcane Spell Power" }

-- What the fights start from: the character as the sim read it (the weapons it fights with and their skill, attack
-- power, crit and hit, the spell power of the schools its spells use, mana) and the target (level and armor, how often
-- swings miss, are dodged and glance, the crit against it, how often spells miss). Two lists of { label, value, color
-- (nil: white) }.
function SimUI:ReadRows()
    local c = self.char
    local hands = c.hands or self.model.hands
    local tgt = Sim.Target(c, self:FightOpts())
    local skills = Sim.Character.WeaponSkills()
    local you, target = {}, {}
    local function Add(list, label, value, color) list[#list + 1] = { label, value, color } end
    -- the weapons it fights with (not a cat's paws) and their skill (a skill below the level's maximum counts as
    -- trained: the text above says so)
    local kinds, low = {}, false
    for _, hand in ipairs(hands) do
        local w = c[hand]
        if w and not w.paws then
            Add(you, SlotName(HAND_SLOT[hand]), F("|T%s:16:16|t %s · %d–%d · %s", C_Item.GetItemIconByID(w.id),
                Theme.ItemName(w.id), w.min, w.max, F(L("speed %.2f"), w.speed)))
            local rank, top = Sim.Character.WeaponSkill(w.subclass, skills, c.level)
            local text = F("%s %d/%d", select(3, C_Item.GetItemInfoInstant(w.id)), rank, top)
            if not tContains(kinds, text) then kinds[#kinds + 1] = text end
            low = low or rank < top
        end
    end
    if #kinds > 0 then Add(you, L("Weapon skill"), table.concat(kinds, " · "), low and C.warn or nil) end
    local ranged = hands[1] == "ranged"
    if ranged then
        Add(you, L("Ranged Attack Power"), string.format("%d", c.rap))
        Add(you, L("Crit · hit"), string.format("%.1f%% · %+.1f%%", c.rangedCrit, c.rangedHit))
    elseif hands[1] then
        Add(you, L("Attack Power"), string.format("%d", c.ap))
        Add(you, L("Crit · hit"), string.format("%.1f%% · %+.1f%%", c.crit, c.hit))
    end
    -- the spells the spec casts (the class model's schools, the main one first; none: it casts none): the spell power
    -- of each school, a caster's spell crit (the best of its schools) and hit
    local schools = self.model.Schools and self.model.Schools(c) or {}
    local crit = 0
    for _, school in ipairs(schools) do
        Add(you, L(SPELL_POWER[school]), string.format("%d", c.sp[school]))
        crit = math.max(crit, c.spellCrit[school])
    end
    if schools[1] and not hands[1] then Add(you, L("Spell crit · hit"), string.format("%.1f%% · %+.1f%%", crit, c.spellHit)) end
    if c.manaMax > 0 then Add(you, L("Mana"), string.format("%d", c.manaMax)) end

    -- the target
    Add(target, L("Level · armor"), F(L("%d · %d (−%d%% physical damage)"), tgt.level, tgt.armor,
        math.floor((1 - Sim.ArmorFactor(tgt.armor, c.level)) * 100 + 0.5)))
    local w = hands[1] and c[hands[1]]
    if w and ranged then
        Add(target, L("Your shots: missed"), string.format("%.1f%%", Sim.MissChance(tgt.defense, w.skill,
            c.rangedHit + (w.hitBonus or 0), false)))
        Add(target, L("Your crit against it"), string.format("%.1f%%",
            math.max(0, Sim.WeaponCrit(c.rangedCrit + (w.critBonus or 0), tgt.defense, w.skill))))
    elseif w then
        local miss = Sim.MissChance(tgt.defense, w.skill, c.hit + (w.hitBonus or 0), hands[2] ~= nil and c.oh ~= nil)
        local dodge = math.max(0, Sim.DodgeChance(tgt.defense, w.skill) - (c.dodgeReduce or 0))
        Add(target, L("Your swings: missed · dodged"), string.format("%.1f%% · %.1f%%", miss, dodge))
        local lo, hi = Sim.GlanceRange(tgt.defense, w.skill)
        Add(target, L("Glancing blows"), F(L("%.0f%% of the swings, %.0f%% damage"),
            Sim.GlanceChance(tgt.defense, w.skill, c.level), (lo + hi) / 2 * 100))
        Add(target, L("Your crit against it"), string.format("%.1f%%",
            math.max(0, Sim.WeaponCrit(c.crit + (w.critBonus or 0), tgt.defense, w.skill))))
    end
    -- the main school's spells, with the talents' hit the fights add (model.SpellHit)
    if schools[1] then
        local hit = c.spellHit + (self.model.SpellHit and self.model.SpellHit(c, schools[1]) or 0)
        Add(target, L("Your spells miss"), string.format("%.1f%%", Sim.SpellMissChance(tgt.level - c.level, hit)))
    end
    return you, target
end

-- The two cards under the Character tab's text: they show when all their rows fit. Until the player sizes the window
-- (its grip) after it opens, it grows to the height they need (SimUI.fitHeight, within the screen: ClampSize).
function SimUI:ShowRead()
    local page = self.frame.pages.own
    local you, target
    if self.char then you, target = self:ReadRows() end
    local rows = you and math.max(#you, #target) or 0
    local cards = 36 + rows * READ_STEP + 8
    if rows > 0 and page:IsVisible() then
        -- the window's height: its head, the page down to the text above the cards, the cards, its foot
        self.fitHeight = math.ceil(BODY_TOP + page:GetTop() - page.known:GetBottom() + 12 + cards + BODY_BOTTOM)
        local win = self.frame.win
        local _, h = ClampSize(win, win:GetWidth(), self.fitHeight)
        if self.autoFit and h > self.height then
            -- (its Layout shows the cards)
            self:Resize(win:GetWidth(), h)
            return
        end
    end
    -- (in whole units: the game reports the cards' height a hair off too)
    local shown = rows > 0 and math.floor(page.you:GetHeight() + 0.5) >= cards
    page.you:SetShown(shown)
    page.target:SetShown(shown)
    if not shown then return end
    page.target.label:SetText(Util.Upper(F(L("The target: %s"), L(TargetLabel(DB().target)))))
    for _, pair in ipairs({ { page.you, you }, { page.target, target } }) do
        local card, list = pair[1], pair[2]
        for i, l in ipairs(card.rows) do
            local e = list[i]
            l:SetShown(e ~= nil)
            if e then
                l.name:SetText(e[1])
                l.value:SetText(e[2])
                SetColor(l.value, e[3] or C.white)
            end
        end
    end
end

-- What the simulator read from the character: abilities with their rank; every talent with points, the ones the sim
-- plays itself apart from the others (those count where the game's own numbers have them).
-- Why the sim does not play a spell or talent the character has (Character.NotSimmed's kinds).
local NOT_SIMMED = {
    aoe = "only against groups", type = "only against some kinds of enemies",
    chance = "the game does not say how often", attacked = "only when you are attacked",
    kill = "only after a kill", later = "not simmed yet", new = "new, unknown to the simulator",
    tank = "only when you tank",
}

function SimUI:KnownText()
    local parts = {}
    local keys = {}
    for key in pairs(self.char.spells) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local spell = self.char.spells[key]
        local rank = C_Spell.GetSpellSubtext(spell.id)
        parts[#parts + 1] = (rank and rank ~= "") and F("%s (%s)", spell.name, rank) or spell.name
    end
    -- the talents the model plays, and those the game's own numbers carry (Data/SimInventory.lua); the ones not simmed
    -- follow below with why
    local played, others = {}, {}
    -- (the talents only the class's tank spec plays: not simmed for the other specs)
    local model = self.model
    local tankOnly = model.tankSpec and self.spec.key ~= model.tankSpec and model.tankSpells or {}
    for _, t in ipairs(self.char.talentList) do
        local entry = F("%s %d/%d", t.name, t.rank, t.max or t.rank)
        if t.key and not tankOnly[t.key] then
            played[#played + 1] = entry
        elseif Sim.Character.InventoryKind(self.char.class, t.id) == "game" then
            others[#others + 1] = entry
        end
    end
    table.sort(played)
    table.sort(others)
    local text = F(L("Read from your character: %s."), table.concat(parts, ", "))
    if #self.char.talentList == 0 then
        text = text .. " " .. L("No talents found.")
    else
        text = text .. " " .. F(L("Talents the sim plays itself: %s."), #played > 0 and table.concat(played, ", ") or L("none"))
        if #others > 0 then
            text = text .. " " .. F(L("Your other talents count where the game's own numbers have them (crit, costs, cooldowns, spells): %s."),
                table.concat(others, ", "))
        end
    end
    -- what the character has learned that the sim does not play, and why
    local missing = {}
    for _, m in ipairs(self.char.notSimmed) do missing[#missing + 1] = F("%s (%s)", m.name, L(NOT_SIMMED[m.kind])) end
    if #missing > 0 then text = text .. " " .. F(L("Not simmed: %s."), table.concat(missing, ", ")) end
    -- the poisons and imbues on the weapons, the pet
    local extras = {}
    for _, id in pairs(self.char.weaponSpells or {}) do extras[#extras + 1] = C_Spell.GetSpellName(id) end
    table.sort(extras)
    if #extras > 0 then text = text .. " " .. F(L("On your weapons: %s."), table.concat(extras, ", ")) end
    local pet = self.char.pet
    if pet then
        local names = {}
        for _, spell in ipairs(pet.list) do names[#names + 1] = spell.name end
        text = text .. " " .. F(L("Pet: %s (%s)."), pet.name, #names > 0 and table.concat(names, ", ") or L("Melee"))
    end
    -- worn weapons the fights swing whose skill is not trained yet (the sim counts them as trained), each kind once
    local notes = {}
    for _, hand in ipairs(SwingHands(self.char, self.model)) do
        local w = self.char[hand]
        local skill = w and w.id and SkillNote(w.id)
        if skill and not tContains(notes, skill) then notes[#notes + 1] = skill end
    end
    if #notes > 0 then text = text .. " " .. table.concat(notes, " ") end
    return text
end

-- The Character tab's numbers: the last Character sim of the spec, kept over reloads (LootifiedCharData.simOwn) until
-- the next Sim; none while that runs.
function SimUI:Own()
    if self.running and self.running.view == "own" then return nil end
    return LJ.cdb.simOwn[self.spec.key]
end

-- Keeps a Character sim (Sim.Jobs.OwnDamage's result; opts: its fight) with the gear and level it was made with: the
-- fights' numbers without each fight's own (list) and the other ways (ways).
function SimUI:KeepOwn(result, opts)
    local b = result.base
    LJ.cdb.simOwn[self.spec.key] = {
        base = { dps = b.dps, error = b.error, fights = b.fights, sources = b.sources, manaLeft = b.manaLeft },
        stats = result.stats, foot = result.foot, length = opts.length, target = opts.levelOffset,
        level = Player.level, setup = SimBiS.Setup(),
    }
end

-- True when kept Character numbers were made with what is worn now, at this level, with the fight set now.
local function OwnFits(own)
    return own.level == Player.level and own.setup == SimBiS.Setup() and own.length == DB().length
        and own.target == DB().target
end

function SimUI:ShowOwn()
    local page = self.frame.pages.own
    local result = self:Own()
    page.known:SetShown(self.char ~= nil)
    if self.char then page.known:SetText(self:KnownText()) end
    page.right.hint:SetShown(result == nil)
    if not result then
        -- not simmed yet, or the fights run
        page.left.big:SetText("-")
        page.left.sub:SetText(L(self.running and self.running.view == "own" and "Simming ..." or "Not simmed yet"))
        for _, l in ipairs(page.left.lines) do l:Hide() end
        for _, r in ipairs(page.right.rows) do r:Hide() end
        for _, chip in ipairs(page.stats.chips) do chip:Hide() end
        page.stats:SetHeight(76)
        self:ShowRead()
        return
    end
    local base = result.base
    page.left.big:SetText(string.format("%.1f", base.dps))
    page.left.sub:SetText(F(L("±%.1f · %d fights of %s"), base.error, base.fights, F(L("%d min"), result.length / 60)))
    local fights = FightNumbers(base, result.length, self.model)
    local lines = {}
    for _, f in ipairs(FIGHT_LINES) do
        if f.key ~= "mana" or fights.mana then
            lines[#lines + 1] = { L(f.text), fights[f.key] and string.format(f.format, fights[f.key]) or "-" }
        end
    end
    for i, l in ipairs(page.left.lines) do
        l:SetShown(lines[i] ~= nil)
        if lines[i] then
            l.name:SetText(lines[i][1])
            l.value:SetText(lines[i][2])
        end
    end
    local top = base.sources[1] and base.sources[1].dps or 0
    for i, r in ipairs(page.right.rows) do
        local s = base.sources[i]
        r:SetShown(s ~= nil)
        if s then
            local name, icon = self:Source(s.key)
            r.icon:SetTexture(icon)
            r.name:SetText(name)
            r.dps:SetText(string.format("%.1f", s.dps))
            r.share:SetText(string.format("%.0f%%", s.share * 100))
            r.bar:SetProgress(top > 0 and s.dps / top or 0, i == 1 and C.text4 or nil)
        end
    end
    local stats = page.stats
    local x, y = 16, -36
    for i, s in ipairs(result.stats) do
        local chip = stats.chips[i]
        if not chip then
            chip = Widgets.CreateChip(stats, "", nil, 24)
            chip:EnableMouse(false)
            stats.chips[i] = chip
        end
        chip:SetLabel(F("%s  %s DPS", StatName(s.key), Signed(s.perPoint, 2)))
        chip:ClearAllPoints()
        if x + chip:GetWidth() > stats:GetWidth() - 16 then x, y = 16, y - 30 end
        chip:SetPoint("TOPLEFT", x, y)
        chip:Show()
        x = x + chip:GetWidth() + 8
    end
    for i = #result.stats + 1, #stats.chips do stats.chips[i]:Hide() end
    stats:SetHeight(-y + 24 + 14)
    -- (the cards below the text: after the chips, whose rows move them)
    self:ShowRead()
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------
function SimUI:Status(text, progress)
    local win = self.frame.win
    win.status:SetText(text or "")
    win.progress:SetShown(progress ~= nil)
    if progress then win.progress:SetProgress(progress) end
    -- the line ends before the progress bar while it shows, else before the Sim button
    win.status:SetPoint("RIGHT", progress and win.progress or win.sim, "LEFT", -12, 0)
end

local ERRORS = {
    ["in combat"] = "Leave combat, then try again.",
    ["no weapon"] = "Equip a weapon to sim.",
    ["no ranged weapon"] = "Equip a ranged weapon to sim.",
    ["no pet"] = "Call your pet, then try again: this spec fights with it.",
    ["no pet at this level"] = "This spec fights with a pet, which hunters get at level 10. Until then, pick another spec on the Best in Slot sheet.",
    ["not in cat form"] = "Shift into Cat Form, then try again: the simulator reads your cat's numbers.",
    ["no cat form at this level"] = "This spec fights in Cat Form, which druids learn at level 20. Until then, pick another spec on the Best in Slot sheet.",
    ["spell texts loading"] = "The game is still loading your spell texts: try again in a moment.",
    -- the tank specs
    ["no shield"] = "This spec tanks with a shield: put one on, then try again.",
    ["not in defensive stance"] = "Go into Defensive Stance, then try again: the simulator reads your stance's numbers.",
    ["no defensive stance at this level"] = "This spec fights in Defensive Stance, which warriors learn at level 10. Until then, pick another spec on the Best in Slot sheet.",
    ["not in berserker stance"] = "Go into Berserker Stance, then try again: the simulator reads your stance's numbers.",
    ["not in bear form"] = "Shift into Bear Form, then try again: the simulator reads your bear's numbers.",
    ["no bear form at this level"] = "This spec fights in Bear Form, which druids learn at level 10. Until then, pick another spec on the Best in Slot sheet.",
}

-- What to tell the player when the character cannot be read (err: Sim.Character.Read's error; the simulator and
-- /lf export say it: "try again" fits both).
function SimUI.ProblemText(err)
    local msg = tostring(err):gsub("^.-:%d+: ", "")
    return ERRORS[msg] and L(ERRORS[msg]) or F(L("The simulator could not read your character: %s"), msg)
end

-- Reads the character; self.problem: why it cannot be read (Sim says it in the popup, UI/SimNotice.lua).
function SimUI:Read()
    self.char, self.problem = nil, nil
    local ok, char = pcall(Sim.Character.Read, self.model, self.spec.key)
    if ok then self.char = char else self.problem = SimUI.ProblemText(char) end
end

function SimUI:FightOpts()
    return { length = DB().length, levelOffset = DB().target }
end


-- Stops the window's own fights (their numbers are not kept).
function SimUI:Cancel()
    local run = self.running
    self.running = nil
    if run then Sim.Jobs.Cancel() end
end

-- Sims the shown view: the character as it is, a planned set or the sets.
-- self.running = { view } names the run until its numbers arrive; switching tabs does not touch it.
function SimUI:Run()
    self:Cancel()
    local view = self:View()
    self.results[view] = nil
    assert(self.char, "no character read")
    local run = { view = view }
    local n = Sim.Jobs.FIGHTS
    local opts = self:FightOpts()
    local started = debugprofilestop()
    local function Done(result, err)
        if self.running ~= run then return end
        self.running = nil
        if err then
            UI.SimNotice:Show(L("Simulator"), F(L("The simulator stopped: %s"), (tostring(err):gsub("^.-:%d+: ", ""))))
        else
            local seconds = (debugprofilestop() - started) / 1000
            result.foot = F(L("%d fights each · %.1f s"), n, seconds)
            if view == "own" then self:KeepOwn(result, opts) else self.results[view] = result end
        end
        self:Refresh()
    end
    -- another job took the fights' place (the sim Best in Slot, an item's check)
    local function Cancelled()
        if self.running ~= run then return end
        self.running = nil
        self:Refresh()
    end
    local function Progress(p) self:Status(F(L("Simming: %s"), L(TAB_TEXT[view])), p) end
    local char, model = self.char, self.model
    if view == "own" then
        self.running = run
        Progress(0)
        self:Refresh()
        Sim.Jobs.Start(Sim.Jobs.OwnDamage(char, model, opts, n), Progress, Done, Cancelled)
        return
    end
    -- a planned set or the sets (those that differ from what is worn and can fight)
    local job
    if view == "plan" then
        -- the planner's set on its own (empty, or without the weapon its spec fights with: nothing to fight, it says so)
        local set = self:PlanSet(DB().set)
        if set.empty or set.missing then
            UI.SimNotice:Show(L("Simulator"), PlanNote(set, {}))
            self:Refresh()
            return
        end
        job = Sim.Jobs.SetDamage(char, model, opts, n, set)
    else
        -- the ticked sets against what is worn (run.keys: the sets that get numbers, the cards say "Simming ...")
        local sets = {}
        run.keys = { worn = true }
        for _, set in ipairs(self:Sets()) do
            if not (set.empty or set.missing) and not LJ.cdb.setsOff[set.key] then
                run.keys[set.key] = true
                if #set.items > 0 then sets[#sets + 1] = set end
            end
        end
        job = Sim.Jobs.CompareSets(char, model, opts, n, sets)
    end
    self.running = run
    Progress(0)
    self:Refresh()
    Sim.Jobs.Start(job, Progress, Done, Cancelled)
end

-- The fights the Sim button stops: the window's own.
function SimUI:Busy()
    return self.running ~= nil
end

-- The Sim button: reads the character again (once the game has the data of what is worn) and sims the shown view (a
-- character it cannot read: the popup says why); while fights run it stops them.
function SimUI:Press()
    if self:Busy() then
        self:Cancel()
        self:Refresh()
        return
    end
    UI.SimSpeed:Then(function()
        SimBiS.WhenGearRead(function(gear)
            if not self:IsShown() then return end
            self:Read()
            if not self.char then
                UI.SimNotice:Show(L("Simulator"), self.problem)
                self:Refresh()
                return
            end
            self.char.slotStats = gear
            self:Run()
        end)
    end)
end

-- A setting or the gear changed: the numbers no longer fit (Sim makes new ones; Character keeps its last ones:
-- SimUI:Own).
function SimUI:Reset()
    self:Cancel()
    self.results = {}
    self:RefreshControls()
    self:Refresh()
end

-- A tab only shows: running fights go on, nothing starts.
function SimUI:ShowTab(key)
    self:HidePicker()
    DB().tab = key
    self:RefreshControls()
    self:Refresh()
end

function SimUI:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    -- Percent: the upgrades follow the stat weights, the simulator still fights for damage
    f.win.role:SetText(SimUI.RanksItems(self.spec) and "" or L("The simulator rates your damage. Your upgrades follow your stat weights."))
    local view = self:View()
    for key, page in pairs(f.pages) do page:SetShown(key == view) end
    self:RefreshFoot()
    if view == "plan" then
        self:ShowPlan()
    elseif view == "sets" then
        self:ShowSets()
    else
        self:ShowOwn()
    end
end

-- The foot: the running fights' progress (Run sets it), the sim Best in Slot building in the background, else what the
-- shown view's fights were or what Sim does there; the tab's Sim button turns into Stop while fights run.
function SimUI:RefreshFoot()
    local win = self.frame.win
    local busy = self:Busy()
    win.sim:SetLabel(busy and "Stop" or SIM_TEXT[self:View()])
    win.sim:SetGlyph(busy and "xCircle" or "lightning")
    if self.running then return end
    local bg = SimBiS.running
    if bg then
        self:Status(F(L("Building your Best in Slot list: %d%%"), math.floor(bg.progress * 100)), bg.progress)
        return
    end
    local view = self:View()
    if view == "own" then
        -- the Character tab's last numbers: made with other gear, talents, level or fight settings, it says so
        local own = self:Own()
        self:Status(own and (OwnFits(own) and own.foot
            or L("Your last sim, with other gear, talents, level or fight settings: press Sim for new numbers.")) or L(IDLE.own))
        return
    end
    local result = self.results[view]
    self:Status(result and result.foot or L(IDLE[view]))
end

---------------------------------------------------------------------------
-- Open and close
---------------------------------------------------------------------------
function SimUI:Frame()
    local host = UI:CreateMainFrame()
    if not (self.frame and self.frame.host == host) then
        self.frame = Create(host)
        self.results = {}
    end
    return self.frame
end

-- Opens the window on a tab ("own": Character without one; the Best in Slot sheet's "Sim this set" opens "plan") for a
-- spec (the player's own without one). Nothing is simmed before Sim.
function SimUI:Open(spec, tab)
    local model
    model, spec = SimUI.Model(spec)
    assert(model, "the simulator plays the specs of the player's class")
    if not (UI.frame and UI.frame:IsShown()) then UI:Toggle() end
    local f = self:Frame()
    UI:ClosePopups()
    self:Cancel()
    self.model, self.spec = model, spec
    self.results = {}
    DB().tab = tab or "own"
    f.win.sub:SetText(F("%s · %s · %s", UnitName("player") or "", L(spec.name), F(L("Level %d"), Player.level or 1)))
    f:Show()
    -- (as tall as the Character tab's cards need until the player sizes it: SimUI:ShowRead)
    self.autoFit = true
    self:ApplySize()
    self:Read()
    self:RefreshControls()
    self:Refresh()
    -- the first time: the window explains itself (once its layout settled)
    C_Timer.After(0.3, function() if self:IsShown() then self:StartTour() end end)
end

---------------------------------------------------------------------------
-- The window's tour
---------------------------------------------------------------------------
-- The first time the window opens it explains itself (LJ.db.simTour; starting the main tour again resets it): the Sim
-- button of each tab, then the three tabs. It uses the spotlight of the main tour (UI/Tour.lua).
local simTour
local function TabStep(key, text)
    return { title = TAB_TEXT[key], text = text, place = "inside",
        enter = function() SimUI:ShowTab(key) end,
        target = function() return SimUI.tabs.byKey[key], SimUI.frame.body end }
end
local SIM_TOUR = {
    { title = "Sim",
      text = function()
          return F(L("Sims the tab you see against the target and for the fight length at the top right: \"%s\" on Character, \"%s\" in the Planner, \"%s\" on Sets. While it sims, it stops it."),
              L(SIM_TEXT.own), L(SIM_TEXT.plan), L(SIM_TEXT.sets))
      end,
      enter = function() SimUI:ShowTab("own") end,
      target = function() return SimUI.frame.win.sim end, pad = 6 },
    TabStep("own", "Your character as you wear it: your damage per second, the damage of every ability, what one more point of each stat is worth and what the sim read from you and the target."),
    TabStep("plan", "Two sets of your own: click a slot to pick any item your character can put on there, or drop an item from your bags on it. The set fights on its own."),
    TabStep("sets", "What you wear, your Best in Slot sheet and your own sets side by side, all in the same fights."),
}

function SimUI:StartTour()
    local Tour = UI.Tour
    if Tour.active or LJ.db.simTour or InCombatLockdown() then return end
    simTour = simTour or Tour.New({
        host = function() return SimUI.frame.win end,
        -- the tour ended: it counts as seen
        seen = function() LJ.db.simTour = true end,
    })
    if simTour.active then return end
    simTour.steps = SIM_TOUR
    simTour:Begin()
end

-- The window closed: its tour ends (and counts as seen).
function SimUI:StopTour()
    if simTour and simTour.active then simTour:Stop(true) end
end

-- The window's tour (nil until it ran once), for the tests.
function SimUI.Tour() return simTour end

-- The item menu's "Simulate" (the upgrade check's window: UI/ItemCheckBox.lua): the item can be simmed when the Best
-- in Slot module is on, items are rated by the simulator for the player's spec (Sim) and the item goes in one of the
-- player's slots.
function SimUI.CanSim(itemID)
    return LJ.Modules.On("bis") and SimUI.RanksItems(Player:GetActiveSpec()) and SimBiS.SheetSlots(itemID) ~= nil
end

function SimUI:Close()
    self:Cancel()
    self:HidePicker()
    if self.frame then self.frame:Hide() end
end

function SimUI:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

-- The Best in Slot module off: the simulator's window closes and every fight stops (the sim Best in Slot, the window's,
-- an item's).
LJ:Listen("MODULES_CHANGED", function(_, key, on)
    if key ~= "bis" or on then return end
    Sim.Jobs.Cancel()
    if SimUI:IsShown() then SimUI:Close() end
end)

-- Gear changed while the window shows: read the character again; its numbers are gone (Sim makes new ones).
-- Gear or talents changed while the window shows: read the character again; its numbers are gone (Sim makes new ones).
local function SetupChanged()
    if SimUI:IsShown() then
        SimUI:Read()
        SimUI:Reset()
    end
end
LJ:Listen("EQUIPMENT_CHANGED", SetupChanged)
LJ:Listen("SPEC_CHANGED", SetupChanged)
-- The sim Best in Slot started, finished or stopped, or the list's sources changed: the sheet's set (Sets) and the
-- planner's gains follow.
for _, message in ipairs({ "SIM_BIS_CHANGED", "LIST_CHANGED" }) do
    LJ:Listen(message, function()
        if SimUI:IsShown() and not SimUI.running then SimUI:Refresh() end
    end)
end
LJ:Listen("SIM_BIS_PROGRESS", function()
    if SimUI:IsShown() and not SimUI.running then SimUI:RefreshFoot() end
end)
