-- Lootified - Best in Slot of the modern and the classic look: the character's Best in Slot list (Core/BiS.lua: the sim's
-- winners with Sim, the hidden ranking with Percent) as a character sheet: the character in the middle wears the list,
-- its slots around it (a column at each side, the weapons below), each with the item's icon and name and, in green, the
-- damage the sim found it adds (Percent: the share by the stat weights); where it drops shows in its tooltip. Chips
-- above the character switch the sheet between what is worn (each slot with what its Best in Slot item adds) and the
-- list, what the list's set adds between them, or to an own set of the planner, with what that set adds below them. A
-- click on a slot lists the items of the list it can put on there (a search, the armor kinds), with their numbers: a
-- pick goes in the own set the sheet shows (on the list or what is worn, a free own set takes that view's items first);
-- on an own set None takes the slot's item out.
-- The header: the spec, the list's level, the weapons, what the sim found, in the middle the filter (UI/ListFilter.lua:
-- the spec and the sources the list takes, in a panel at the right), at the right the Best in Slot sim and the simulator
-- (on an own set with Sim: that set simmed). The wishlist takes items by the item menu (a right click). The classic
-- look draws the header and the character on dark panels.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local BiS = LJ.BiS
local C = Theme.COLORS
local H = Theme.HEARTH

local Page = {}

local HEADER_HEIGHT = 72
local ICON = 40           -- the slots' item icons
local STEP = 54           -- from one slot to the next in a column
local COLUMN = 276        -- the slot columns at the left and the right of the character
local TEXT = COLUMN - ICON - 22   -- the most a slot's name takes beside its icon
local GAP = 16            -- between a column and the character, between two weapons
local VIEW_GAP = 6        -- between the view chips above the character
local ResolveDataSlot = BiS.ResolveDataSlot
local PICK_ROWS = 8       -- the slot list's items shown at a time (the mouse wheel scrolls)

---------------------------------------------------------------------------
-- Slot: the item's icon and name, under the name the damage the sim found it adds
---------------------------------------------------------------------------
-- The mouse over a slot, and the slot whose list is open: a soft box behind it.
local function SlotVisual(f)
    f.hl:SetColor(1, 1, 1, f.picked and 0.09 or Widgets.Hover(f) and 0.05 or 0)
end

-- right: the icon at the right edge and the texts at its left (the right column, the main hand).
local function CreateSlot(parent, slot, right)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(COLUMN, ICON + 8)
    f.slot = slot
    f.right = right
    f.near, f.far, f.dx = right and "RIGHT" or "LEFT", right and "LEFT" or "RIGHT", right and -10 or 10
    f.hl = Widgets.CreateLazyBox(f, "BACKGROUND", 0, 6)
    f.icon = Widgets.CreateItemIcon(f, ICON)
    f.icon:EnableMouse(false)
    f.icon:SetPoint(f.near, right and -4 or 4, 0)
    f.name = Widgets.Text(f, "item", C.text1, nil, f.near)
    f.name:SetWordWrap(false)
    f.gain = Widgets.Text(f, "smallSemi", C.okText, nil, f.near)
    f.gain:SetPoint("BOTTOM" .. f.near, f.icon, "BOTTOM" .. f.far, f.dx, 3)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnEnter", function(self)
        self.hovered = true
        SlotVisual(self)
        if self.itemID then
            local lines = {}
            if self.wornBest then lines[1] = { L("Percent: what you wear is best"), C.okText[1], C.okText[2], C.okText[3] } end
            lines[#lines + 1] = LJ.Tooltip.Hint("Click for alternatives")
            Widgets.ShowItemTooltip(self, self.itemID, lines)
        else
            GameTooltip:SetOwner(self, Widgets.TooltipAnchor(self))
            GameTooltip:SetText(self.labelText, 1, 1, 1)
            GameTooltip:AddLine(self.why, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        self.hovered = false
        SlotVisual(self)
        GameTooltip:Hide()
    end)
    SlotVisual(f)
    return f
end

-- The texts beside the icon, as wide as width: the name over the gain, or the name alone in the middle.
local function LayoutSlotText(f, width)
    f.name:SetWidth(width)
    f.gain:SetWidth(width)
    f.name:ClearAllPoints()
    if f.gain:IsShown() then
        f.name:SetPoint("TOP" .. f.near, f.icon, "TOP" .. f.far, f.dx, -3)
    else
        f.name:SetPoint(f.near, f.icon, f.far, f.dx, 0)
    end
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function Page:CreateHeader(main)
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    self.header = header
    if Theme.IsClassic() then
        -- a dark panel
        header.fill = Widgets.CreateBox(header, "BACKGROUND", -6, 4)
        header.ring = Widgets.CreateBox(header, "BACKGROUND", -5, 4, true)
        Widgets.BoxFill(header.fill, header.ring, "panel")
    end
    header.title = Widgets.Text(header, "heroMid", Theme.IsClassic() and H.title or C.white)
    header.title:SetPoint("TOPLEFT", 22, -12)
    if not Theme.IsClassic() then header.title:SetShadowOffset(0, -2) end
    -- the list's level, the weapons, what the sim found
    header.sub = Widgets.Text(header, "body", C.text3)
    header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -3)

    -- the simulator (UI/SimWindow.lua) on "Character" with its last numbers (nothing is simmed before Sim is pressed
    -- there); on an own set with Sim it sims that set (Page:PressSim)
    self.simButton = Widgets.CreateButton(header, "Open simulator", "primary", "lightning", nil, 28)
    self.simButton:SetPoint("RIGHT", -18, 0)
    self.simButton:SetScript("OnClick", function() self:PressSim() end)
    -- the sim Best in Slot (Sim/SimBiS.lua) of the sheet's spec, beside the simulator: what a press does shows on it
    -- (UI.BiSSimButton)
    self.bisButton = Widgets.CreateButton(header, "Best in Slot sim", "ghost", "lightning", nil, 28)
    self.bisButton:SetPoint("RIGHT", self.simButton, "LEFT", -6, 0)
    self.bisButton:SetScript("OnClick", function() UI.PressBiSSim(self:GetViewSpec()) end)
    if LJ.NO_SIM then
        self.simButton:Hide()
        self.bisButton:Hide()
    end
    -- the filter in the middle: the spec and the sources the list takes (Page:RefreshFilter, Page:ToggleFilter opens its
    -- panel)
    self.filterButton = UI.ListFilter.CreateButton(header, function() self:ToggleFilter() end)
    self.filterButton:SetPoint("CENTER")
end

-- The Best in Slot sim's button of a spec (the sheet's header, For you's upgrades) says what a press does: Stop while it
-- runs; "Up to date" while the list was simmed with the level and the gear of now (a press sims it again all the same);
-- else the sim, with the warning glyph when the level or the gear changed since. { text, glyph, tip }
function UI.BiSSimButton(spec)
    local run = LJ.SimBiS.running
    local rec = LJ.SimBiS.Get(spec)
    if run and run.spec.key == spec.key then
        return { text = "Stop", glyph = "xCircle", tip = "It tests every item you can wear and goes on while you play." }
    elseif rec and not LJ.SimBiS.IsOutdated(rec) then
        return { text = "Up to date", glyph = "checkCircle",
            tip = "Your list was simmed with your level, talents and the gear you wear: no new sim needed. A click sims it again all the same." }
    end
    return { text = "Best in Slot percent list", glyph = rec and "warning" or "lightning",
        tip = rec and "Your level, talents, gear or list changed since the last sim: sim again for a list that fits."
            or "Fights with your character as it is and tests every item you can wear in every slot (a few minutes). Your Best in Slot list, the upgrade marks and tooltips show what it finds." }
end

-- A press of that button: runs the sim Best in Slot of the spec (the sim speed is asked the first time); while it runs,
-- stops it.
function UI.PressBiSSim(spec)
    local run = LJ.SimBiS.running
    if run and run.spec.key == spec.key then
        LJ.SimBiS.Cancel()
        return
    end
    UI.SimSpeed:Then(function() LJ.SimBiS.Start(spec) end)
end

function Page:RefreshBiSButton(spec)
    if LJ.NO_SIM then self.bisButton:Hide(); return end
    local b, s = self.bisButton, UI.BiSSimButton(spec)
    b:SetLabel(s.text)
    b:SetGlyph(s.glyph)
    Widgets.SetTooltip(b, "Best in Slot sim", s.tip, "ANCHOR_BOTTOM")
end

-- The simulator's button: "Sim this set" on an own set with Sim (simSet), else "Open simulator".
function Page:RefreshSimButton(simSet)
    if LJ.NO_SIM then self.simButton:Hide(); return end
    self.simSet = simSet
    local b = self.simButton
    if simSet then
        b:SetLabel("Rate this set")
        Widgets.SetTooltip(b, "Sim this set",
            "The set fights in the simulator's planner for its exact damage: the number on the sheet is an estimate from each item simmed alone.",
            "ANCHOR_BOTTOM")
    else
        b:SetLabel("Open percent list")
        Widgets.SetTooltip(b, "Open simulator", "Your character's damage, your own sets in the planner and the sets side by side.",
            "ANCHOR_BOTTOM")
    end
end

-- A press of it: the own set the sheet shows fights in the simulator's planner, else the simulator opens.
function Page:PressSim()
    local spec = self:GetViewSpec()
    if not self.simSet then
        UI.Sim:Open(spec)
        return
    end
    LJ.db.sim.set = self.view
    UI.Sim:Open(spec, "plan")
    UI.Sim:Press()
end

function Page:Create(root)
    local main = CreateFrame("Frame", nil, root)
    main:SetAllPoints()
    self.main = main
    self:CreateHeader(main)

    local doll = CreateFrame("Frame", nil, main)
    doll:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    doll:SetPoint("BOTTOMRIGHT")
    self.doll = doll
    -- what the sheet shows: "bis" (the Best in Slot list), "worn" or the number of an own set
    self.view = "bis"
    self:CreateWell(doll)

    -- the right column and the main hand: their icons at the right
    self.slots = {}
    for _, slot in ipairs(BiS.SLOTS) do
        local s = CreateSlot(doll, slot, tContains(BiS.RIGHT_SLOTS, slot) or slot == "MAINHAND")
        s:SetScript("OnClick", function(btn, button) self:OnSlotClick(btn, button) end)
        self.slots[slot] = s
    end
    self:LayoutSlots()
    self:CreateFlyout(root)
    self:CreateFilter(main)
end

-- The filter's panel over the sheet's right side (UI/ListFilter.lua) and the shade over the rest of the sheet: a click
-- on it closes the panel.
function Page:CreateFilter(main)
    local shade = CreateFrame("Button", nil, main)
    shade:SetPoint("TOPLEFT", self.doll)
    shade:SetPoint("BOTTOMRIGHT", self.doll)
    shade:SetFrameLevel(self.doll:GetFrameLevel() + 30)
    shade.tex = shade:CreateTexture(nil, "BACKGROUND")
    shade.tex:SetAllPoints()
    shade.tex:SetColorTexture(0.02, 0.025, 0.035, 0.45)
    shade:SetScript("OnClick", function() self:CloseFilter() end)
    shade:Hide()
    self.filterShade = shade
    local panel = UI.ListFilter.CreatePanel(main, function() self:CloseFilter() end)
    panel:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -(HEADER_HEIGHT - 2))
    panel:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -8, 8)
    panel:SetFrameLevel(shade:GetFrameLevel() + 5)
    self.filterPanel = panel
end

-- The filter's panel opens (the slot list closes) or closes again.
function Page:ToggleFilter()
    if self.filterPanel:IsShown() then
        self:CloseFilter()
        return
    end
    self.flyout:Hide()
    self.filterPanel:Show()
    self.filterShade:Show()
    self.filterPanel:Refresh()
    self.filterButton:SetActive(true)
    -- the first time the panel explains itself
    UI.ListFilter.StartTour(self.filterPanel)
end

function Page:CloseFilter()
    UI.ListFilter.StopTour()
    self.filterPanel:Hide()
    self.filterShade:Hide()
    self.filterButton:SetActive(false)
end

-- The filter's button in the middle of the header (above the character), as wide as the room between the title (and
-- the line under it) and the header's buttons allows on both sides (at least 150: a longer line of sources loses its
-- end, the tooltip names them all), and its panel.
function Page:RefreshFilter(spec, ranks)
    local b, header = self.filterButton, self.header
    local half = UI:ContentWidth() / 2
    local left = 22 + math.max(Widgets.TextWidth(header.title), Widgets.TextWidth(header.sub)) + 16
    local buttons = 18 + self.simButton:GetWidth() + (ranks and 6 + self.bisButton:GetWidth() or 0) + 16
    b:Update(spec, math.max(150, 2 * math.min(half - left, half - buttons)))
    b:SetActive(self.filterPanel:IsShown())
    if self.filterPanel:IsShown() then self.filterPanel:Refresh() end
end

-- The character between the columns (classic: on a dark panel): it wears the sheet's items (Page:DressModel), turns
-- while dragged, zooms with the mouse wheel; the view chips above it.
function Page:CreateWell(doll)
    local well = CreateFrame("Frame", nil, doll)
    if Theme.IsClassic() then
        well.fill = Widgets.CreateBox(well, "BACKGROUND", 0, 4)
        well.ring = Widgets.CreateBox(well, "BACKGROUND", 1, 4, true)
        Widgets.BoxFill(well.fill, well.ring, "panel")
    else
        well.panel = Widgets.CreatePanel(well, 12, "BACKGROUND", 0)
        well.panel:SetFill(0, 0, 0, 0.18)
        well.panel:SetBorder(1, 1, 1, 0.05)
        -- the class color glows behind the character and on its floor
        well.glow = well:CreateTexture(nil, "BACKGROUND", nil, 3)
        well.glow:SetTexture(Theme.TEX.glow)
        well.glow:SetPoint("TOPLEFT", -10, -30)
        well.glow:SetPoint("BOTTOMRIGHT", 10, 10)
        well.floor = well:CreateTexture(nil, "BACKGROUND", nil, 4)
        well.floor:SetTexture(Theme.TEX.glow)
        well.floor:SetSize(170, 30)
        well.floor:SetPoint("BOTTOM", 0, 16)
        Theme.OnAccent(well, function(w, r, g, b)
            w.glow:SetVertexColor(r, g, b, 0.22)
            w.floor:SetVertexColor(r, g, b, 0.4)
        end)
    end
    self.well = well

    local model = CreateFrame("DressUpModel", nil, well)
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 4)
    -- the look stays while the page is hidden; it is dressed again only when the sheet's items change
    model:SetKeepModelOnHide(true)
    model.rotation, model.zoom = 0, 1
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(m, button)
        if button == "LeftButton" then
            m.dragging = true
            m.lastX = GetCursorPosition()
        end
    end)
    local function StopDrag(m) m.dragging = false end
    model:SetScript("OnMouseUp", StopDrag)
    model:SetScript("OnHide", StopDrag)   -- hidden mid-drag: no turning when it shows again
    model:SetScript("OnUpdate", function(m)
        if m.dragging then
            local x = GetCursorPosition()
            m.rotation = m.rotation + (x - m.lastX) * 0.012
            m.lastX = x
            m:SetFacing(m.rotation)
        end
    end)
    model:SetScript("OnMouseWheel", function(m, delta)
        m.zoom = math.max(0.5, math.min(1.6, m.zoom - delta * 0.08))
        m:SetCamDistanceScale(m.zoom)
    end)
    self.model = model

    -- the views (Page:LayoutViews): what is worn and the Best in Slot list
    local row = CreateFrame("Frame", nil, well)
    row:SetFrameLevel(model:GetFrameLevel() + 2)
    row:SetPoint("TOPLEFT", 8, -8)
    row:SetPoint("TOPRIGHT", -8, -8)
    row:SetHeight(24 + VIEW_GAP + 24)
    self.viewRow = row
    self.viewChips = {}
    local views = { "worn", "bis" }
    for _, view in ipairs(views) do
        local chip = Widgets.CreateChip(row, "", nil, 24)
        chip.view = view
        chip:SetScript("OnClick", function(c) self:SetView(c.view) end)
        chip:HookScript("OnEnter", function(c)
            if c.cut then
                GameTooltip:SetOwner(c, "ANCHOR_TOP")
                GameTooltip:SetText(c.name, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
        self.viewChips[#self.viewChips + 1] = chip
    end
    -- between What I wear and Best in Slot: what the Best in Slot set adds, an arrow toward it
    self.viewGain = Widgets.Text(row, "smallSemi", C.okText)
    -- under the own sets: what the set the sheet shows adds
    self.setGain = Widgets.Text(row, "smallSemi", C.text3)
end

-- The view chips centered above the character: What I wear and Best in Slot with the percent gain between them.
function Page:LayoutViews(view, gain)
    local rows, line = 1, 0
    local width = self.well:GetWidth() - 16
    local worn, bis = self.viewChips[1], self.viewChips[2]
    worn:SetLabel("What I wear")
    bis:SetLabel("Best in Slot")
    local arrow = Theme.GlyphString("arrowRight", 12, C.okText)
    self.viewGain:SetText(gain and (gain .. " " .. arrow) or arrow)
    local x = math.floor((width - worn:GetWidth() - Widgets.TextWidth(self.viewGain) - bis:GetWidth()
        - 2 * VIEW_GAP) / 2)
    worn:ClearAllPoints()
    worn:SetPoint("TOPLEFT", x, 0)
    self.viewGain:ClearAllPoints()
    self.viewGain:SetPoint("LEFT", worn, "RIGHT", VIEW_GAP, 0)
    bis:ClearAllPoints()
    bis:SetPoint("LEFT", self.viewGain, "RIGHT", VIEW_GAP, 0)
    for _, chip in ipairs(self.viewChips) do chip:SetActive(chip.view == view) end
    self.model:SetPoint("TOPLEFT", 4, -(8 + rows * (24 + VIEW_GAP) + 4))
end

-- A view chip: the sheet and the character show that gear (an empty own set: its empty slots, a click on one puts an
-- item in it).
function Page:SetView(view)
    Util.PlaySound("U_CHAT_SCROLL_BUTTON")
    self.view = view
    self:Refresh()
end

-- The slots around the character: a column at each edge, the character between them, the weapons in a row centered
-- under it (each as wide as its texts).
function Page:LayoutSlots()
    local total = UI:ContentWidth() - 28
    for i, slot in ipairs(BiS.LEFT_SLOTS) do
        local s = self.slots[slot]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 14, -12 - (i - 1) * STEP)
        LayoutSlotText(s, TEXT)
    end
    for i, slot in ipairs(BiS.RIGHT_SLOTS) do
        local s = self.slots[slot]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", 14 + total - COLUMN, -12 - (i - 1) * STEP)
        LayoutSlotText(s, TEXT)
    end
    local height = 6 * STEP + ICON + 8
    self.well:ClearAllPoints()
    self.well:SetPoint("TOPLEFT", 14 + COLUMN + GAP, -12)
    self.well:SetSize(total - 2 * (COLUMN + GAP), height)
    local row, width = {}, -GAP
    for _, slot in ipairs(BiS.WEAPON_SLOTS) do
        local s = self.slots[slot]
        if s:IsShown() then
            local text = math.min(TEXT, math.ceil(math.max(Widgets.TextWidth(s.name),
                s.gain:IsShown() and Widgets.TextWidth(s.gain) or 0)))
            LayoutSlotText(s, text)
            s:SetWidth(4 + ICON + 10 + text + 4)
            row[#row + 1] = s
            width = width + s:GetWidth() + GAP
        end
    end
    local x = 14 + math.floor((total - width) / 2)
    for _, s in ipairs(row) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", x, -(12 + height + 12))
        x = x + s:GetWidth() + GAP
    end
end

---------------------------------------------------------------------------
-- Flyout: the slot's items to pick from
---------------------------------------------------------------------------
local FLY_WIDTH = 450     -- the armor chips in one row: German Mail in the classic look, with three-digit counts
local ROW_WIDTH = FLY_WIDTH - 20
local KIND_NAMES = UI.ListFilter.ARMOR_NAMES   -- the armor kinds (item subclasses 1-4)
-- the slots whose items come in cloth, leather, mail and plate (cloaks are cloth for everyone)
local ARMOR_SLOTS = { HEAD = true, SHOULDER = true, CHEST = true, WRIST = true, HANDS = true, WAIST = true, LEGS = true,
    FEET = true }

-- The armor kind of an item (1 cloth ... 4 plate), nil for other items.
local function ArmorKind(id)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if classID == 4 and subclassID >= 1 and subclassID <= 4 then return subclassID end
    return nil
end

-- The armor kinds the character's class wears that the list takes (the filter's); nil when it is one (no chips for it).
local function ClassKinds()
    local kinds = {}
    for _, k in ipairs(UI.ListFilter.ClassArmor()) do
        if LJ.cdb.list[Items.LIST_ARMOR[k]] then kinds[#kinds + 1] = k end
    end
    return #kinds > 1 and kinds or nil
end

function Page:CreateFlyout(root)
    local fly = CreateFrame("Frame", nil, root)
    fly:SetFrameStrata("DIALOG")
    fly:SetSize(FLY_WIDTH, 100)
    fly:SetClampedToScreen(true)
    fly:EnableMouse(true)
    Widgets.CreateShadow(fly, 14, 0.7)
    fly.panel = Widgets.CreatePopupPanel(fly, 10)
    fly:Hide()
    fly.title = Widgets.Text(fly, "h3", C.white)
    fly.title:SetPoint("TOPLEFT", 12, -11)
    fly.close = Widgets.CreateButton(fly, nil, "icon", "close", 22, 22)
    fly.close:SetPoint("TOPRIGHT", -6, -6)
    fly.close:SetScript("OnClick", function() fly:Hide() end)
    -- the search: the items' names and sources (UI.FilterItems)
    fly.search = Widgets.CreateSearchBox(fly, FLY_WIDTH - 24, "Search name or source", function()
        fly.offset = 0
        if fly:IsShown() then self:LayoutFlyout() end
    end)
    fly.search:SetPoint("TOPLEFT", 12, -36)
    -- the armor kinds: all, or one (Page:LayoutFlyout)
    fly.kindChips = {}
    for _, kind in ipairs({ "ALL", 1, 2, 3, 4 }) do
        local chip = Widgets.CreateChip(fly, "", nil, 22)
        chip.kind = kind
        chip:SetScript("OnClick", function(c)
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            fly.kind, fly.offset = c.kind, 0
            self:LayoutFlyout()
        end)
        fly.kindChips[#fly.kindChips + 1] = chip
    end
    fly.rows = {}
    fly.none = self:CreateNone(fly)
    fly.empty = Widgets.Text(fly, "small", C.text3)
    fly.empty:SetText(L("No items found."))
    -- entries: the slot's items (UI.Sim.SlotItems); kind: the armor chip picked; found: the items the search and the
    -- chip leave; offset: those above the first row (the mouse wheel scrolls)
    fly.entries, fly.kind, fly.found, fly.offset = {}, "ALL", 0, 0
    fly:EnableMouseWheel(true)
    fly:SetScript("OnMouseWheel", function(_, delta)
        local offset = math.max(0, math.min(fly.found - PICK_ROWS, fly.offset - delta))
        if offset ~= fly.offset then
            fly.offset = offset
            self:LayoutFlyout()
        end
    end)
    -- under the rows: the items of higher levels too (kept: LJ.db.sim.higher, the planner's picker's too), which items
    -- show, what their numbers are
    fly.higher = Widgets.CreateToggle(fly, "Higher levels",
        "Also the items your class can put on from a higher level, up to 60. The sim counts them as if you could wear them now.")
    fly.higher.onChange = function(_, on)
        LJ.db.sim.higher = on
        fly.offset = 0
        self:ShowFlyout(fly.owner)
    end
    fly.more = Widgets.Text(fly, "small", C.text4, nil, "RIGHT")
    fly.note = Widgets.Text(fly, "small", C.text4)
    fly.note:SetWidth(ROW_WIDTH - 8)
    fly.note:SetJustifyH("LEFT")
    fly.note:SetWordWrap(true)
    fly:SetScript("OnHide", function() self:MarkPicked() end)
    self.flyout = fly
    root:HookScript("OnHide", function() fly:Hide() end)
end

-- A row: the accent while the mouse is over it, a soft box on the item the slot shows.
local function FlyRowVisual(r)
    local a = Theme.accent
    if r.hovered then
        r.hl:SetColor(a[1], a[2], a[3], 0.14)
    else
        r.hl:SetColor(1, 1, 1, r.selected and 0.07 or 0)
    end
end

local function FlyRowEnter(r)
    r.hovered = true
    FlyRowVisual(r)
    Widgets.ShowItemTooltip(r, r.itemID, r.hint)
end

local function FlyRowLeave(r)
    r.hovered = false
    FlyRowVisual(r)
    GameTooltip:Hide()
end

function Page:FlyoutRowClick(r, button)
    if not r.itemID then return end
    if Items.HandleClick(r.itemID, button) then return end
    if button == "RightButton" then
        Widgets.ShowItemMenu(r, r.itemID)
    else
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:PickItem(self.flyout.owner.slot, r.itemID)
    end
end

-- Row of the slot's list: the item's icon, its name over its armor kind and where it drops; at the right its number
-- over why it is among the first.
function Page:FlyoutRow(i)
    local fly = self.flyout
    local row = fly.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, fly)
    row:SetSize(ROW_WIDTH, 32)
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 2, 6)
    row.icon = Widgets.CreateItemIcon(row, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:EnableMouse(false)
    row.value = Widgets.Text(row, "count", C.text2, nil, "RIGHT")
    row.value:SetPoint("TOPRIGHT", -8, -3)
    row.tag = Widgets.Text(row, "small", C.text3, nil, "RIGHT")
    row.tag:SetPoint("BOTTOMRIGHT", -8, 3)
    row.name = Widgets.Text(row, "itemSmall", C.text1)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.src = Widgets.Text(row, "small", C.text3)
    row.src:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    for _, fs in ipairs({ row.name, row.src }) do fs:SetWordWrap(false) end
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", FlyRowEnter)
    row:SetScript("OnLeave", FlyRowLeave)
    row:SetScript("OnClick", function(r, button) self:FlyoutRowClick(r, button) end)
    fly.rows[i] = row
    return row
end

-- None: first in the list of an own set's slot that shows an item (Page:LayoutFlyout), the slot's empty picture; a
-- click takes the item out of the set.
function Page:CreateNone(fly)
    local row = CreateFrame("Button", nil, fly)
    row:SetSize(ROW_WIDTH, 32)
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 2, 6)
    row.icon = Widgets.CreateItemIcon(row, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:EnableMouse(false)
    row.name = Widgets.Text(row, "itemSmall", C.text1)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetText(L("None"))
    row.src = Widgets.Text(row, "small", C.text3)
    row.src:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.src:SetText(L("Remove from this set"))
    row:SetScript("OnEnter", function(r) r.hovered = true FlyRowVisual(r) end)
    row:SetScript("OnLeave", function(r) r.hovered = false FlyRowVisual(r) end)
    row:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        self:PickItem(fly.owner.slot, nil)
    end)
    row:Hide()
    return row
end

-- The slot's list beside it (Page:LayoutFlyout): the items of the list the character can put on there (UI.Sim.SlotItems:
-- what is worn, the own set's, the Best in Slot item, the sim's picks and the bags first; with Higher levels those of
-- higher levels last), a click puts one in an own set (Page:PickItem); on an own set None first takes the slot's item
-- out.
function Page:ShowFlyout(slotFrame)
    local spec = self:GetViewSpec()
    if not spec then return end
    local fly = self.flyout
    fly.entries = UI.Sim.SlotItems(spec, slotFrame.slot, type(self.view) == "number" and self.view or nil,
        LJ.db.sim.higher)
    self:LayoutFlyout()
    if not fly:IsShown() then
        fly:Show()
        fly:SetAlpha(0)
        Widgets.Anim.Fade(fly, 1, 0.1)
    end
    self:MarkPicked()
end

-- The slot's list: its name and how many items it has, the search, the armor chips (the armor slots of a class that
-- wears more than one kind: how many items each kind has), None (an own set's slot with an item), the items the search
-- and the chip leave from the offset (PICK_ROWS) each with its number (UI.Sim.ItemNumber) and why it is among the
-- first, the item the slot shows marked; under them Higher levels, which items show and the note on the numbers. Its
-- place: beside the slot toward the character, inside the window.
function Page:LayoutFlyout()
    local fly = self.flyout
    local slotFrame = fly.owner
    local spec = self:GetViewSpec()
    local slot = slotFrame.slot
    local dataSlot = ResolveDataSlot(spec, slot)
    fly.title:SetText(F("%s · %d items", L(dataSlot == "TWOHAND" and "Two-hand weapon" or slotFrame.label), #fly.entries))
    for _, r in ipairs(fly.rows) do r:Hide() end
    local y = -70
    local kinds = ARMOR_SLOTS[slot] and ClassKinds()
    if not kinds or not tContains(kinds, fly.kind) then fly.kind = "ALL" end
    local counts, entries, ids = { ALL = #fly.entries }, {}, {}
    for _, e in ipairs(fly.entries) do
        local kind = ArmorKind(e.id)
        if kind then counts[kind] = (counts[kind] or 0) + 1 end
        entries[e.id] = e
        if fly.kind == "ALL" or kind == fly.kind then ids[#ids + 1] = e.id end
    end
    -- the chips in a row, the next line where the row is full
    local x0 = 14
    local x = x0
    for _, chip in ipairs(fly.kindChips) do
        local shown = kinds ~= nil and (chip.kind == "ALL" or tContains(kinds, chip.kind))
        chip:SetShown(shown)
        if shown then
            local n = counts[chip.kind] or 0
            chip:SetLabel(F("%s %d", L(chip.kind == "ALL" and "All" or KIND_NAMES[chip.kind]), n), nil, true)
            chip:SetActive(fly.kind == chip.kind)
            chip:SetEnabled(n > 0)
            chip:SetAlpha(n > 0 and 1 or 0.4)
            if x > x0 and x + chip:GetWidth() > FLY_WIDTH - 14 then x, y = x0, y - 27 end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", x, y)
            x = x + chip:GetWidth() + 5
        end
    end
    if kinds then y = y - 30 end
    -- an own set's slot that shows an item: None first
    local none = type(self.view) == "number" and slotFrame.itemID ~= nil
    fly.none:SetShown(none)
    if none then
        fly.none.icon:SetItem(nil)
        fly.none.icon.icon:SetTexture(select(2, BiS.SlotLabel(slot, Player.class)))
        fly.none:ClearAllPoints()
        fly.none:SetPoint("TOPLEFT", 10, y)
        y = y - 33
    end

    local found = UI.FilterItems(ids, fly.search:GetText() or "")
    fly.found = #found
    fly.offset = math.max(0, math.min(#found - PICK_ROWS, fly.offset))
    local first, count = fly.offset + 1, math.min(PICK_ROWS, #found - fly.offset)
    fly.empty:SetShown(count == 0)
    if count == 0 then
        fly.empty:ClearAllPoints()
        fly.empty:SetPoint("TOPLEFT", 14, y - 4)
        y = y - 24
    end
    local hint = { LJ.Tooltip.Hint(type(self.view) == "number" and "Click: put it in this set" or "Click: put it in an own set") }
    local numbers = false
    for i = 1, count do
        local entry = entries[found[first + i - 1]]
        local row = self:FlyoutRow(i)
        row.itemID = entry.id
        row.hint = hint
        row.icon:SetItem(entry.id)
        row.icon:SetOwned(Items.IsOwned(entry.id))
        row.name:SetText(Theme.ItemName(entry.id))
        local kind, src = ArmorKind(entry.id), BiS.SourceText(entry.id) or ""
        row.src:SetText(kind and (Theme.ColorText(Util.Upper(L(KIND_NAMES[kind])), C.text4) .. "  " .. src) or src)
        row.tag:SetText(entry.tag or "")
        Widgets.SetTextColor(row.tag, entry.higher and C.warn or C.text3)
        local value, color = UI.Sim.ItemNumber(spec, slot, entry.id)
        row.value:SetText(value or "")
        if value then
            Widgets.SetTextColor(row.value, color)
            numbers = true
        end
        local wide = math.max(value and Widgets.TextWidth(row.value) or 0, Widgets.TextWidth(row.tag))
        local right = wide > 0 and (8 + wide + 8) or 8
        row.name:SetPoint("TOPRIGHT", -right, -3)
        row.src:SetPoint("BOTTOMRIGHT", -right, 3)
        row.selected = entry.id == slotFrame.itemID
        FlyRowVisual(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, y)
        row:Show()
        y = y - 33
    end
    -- Higher levels, at its right which items show when there are more
    fly.higher:SetChecked(LJ.db.sim.higher)
    fly.higher:ClearAllPoints()
    fly.higher:SetPoint("TOPLEFT", 8, y - 4)
    fly.more:SetShown(#found > PICK_ROWS)
    if #found > PICK_ROWS then
        fly.more:SetText(F(L("%d-%d of %d found · scroll for more"), first, first + count - 1, #found))
        fly.more:ClearAllPoints()
        fly.more:SetPoint("RIGHT", fly, "TOPRIGHT", -14, y - 17)
    end
    y = y - 34
    local note = UI.Sim.NumbersNote(spec, numbers)
    fly.note:SetShown(note ~= nil)
    if note then
        fly.note:SetText(note)
        fly.note:ClearAllPoints()
        fly.note:SetPoint("TOPLEFT", 14, y)
        y = y - 4 - math.ceil(fly.note:GetStringHeight())
    end

    local height = -y + 8
    fly:SetHeight(height)
    fly:ClearAllPoints()
    -- kept inside the window: beside the slot toward the character, moved up where it would run out at the bottom and
    -- sideways where it would run out at a side
    local slotTop, rootBottom, rootTop = slotFrame:GetTop(), self.root:GetBottom(), self.root:GetTop()
    local limitTop = rootTop and (rootTop - 4)
    local limitBottom = rootBottom and (rootBottom + 4)
    local dy = 0
    if slotTop and limitBottom and slotTop - height < limitBottom then dy = limitBottom - (slotTop - height) end
    if slotTop and limitTop and slotTop + dy > limitTop then dy = math.max(0, limitTop - slotTop) end
    local dx = 0
    if slotFrame.right then
        local left, limit = slotFrame:GetLeft(), self.root:GetLeft()
        if left and limit and left - 8 - FLY_WIDTH < limit + 4 then dx = limit + 4 - (left - 8 - FLY_WIDTH) end
        fly:SetPoint("TOPRIGHT", slotFrame, "TOPLEFT", dx - 8, dy)
    else
        local right, limit = slotFrame:GetRight(), self.root:GetRight()
        if right and limit and right + 8 + FLY_WIDTH > limit - 4 then dx = limit - 4 - (right + 8 + FLY_WIDTH) end
        fly:SetPoint("TOPLEFT", slotFrame, "TOPRIGHT", dx + 8, dy)
    end
end

-- The slot whose list is open: a soft box behind it.
function Page:MarkPicked()
    local fly = self.flyout
    for _, s in pairs(self.slots) do
        s.picked = fly:IsShown() and fly.owner == s
        SlotVisual(s)
    end
end

function Page:OnSlotClick(slotFrame, button)
    if slotFrame.itemID and Items.HandleClick(slotFrame.itemID, button) then return end
    if button == "RightButton" then
        if slotFrame.itemID then Widgets.ShowItemMenu(slotFrame, slotFrame.itemID) end
        return
    end
    self:ToggleFlyout(slotFrame)
end

-- An item picked in a slot's list: it goes in the own set the sheet shows (nil: None, the own set's slot is empty
-- again). The Best in Slot list and what is worn stay as they are: a free own set takes the view's items first and the
-- sheet shows it (both sets have items: the popup says so). One PLANS_CHANGED refreshes the sheet (UI.Sim.PutInSet).
function Page:PickItem(slot, id)
    self.flyout:Hide()
    if id == self.slots[slot].itemID then return end
    local n = self.view
    if type(n) ~= "number" then
        assert(id, "None outside an own set")
        local from = n == "bis" and "sheet" or "worn"
        n = nil
        for i, plan in ipairs(LJ.cdb.plans) do
            if not next(plan) then
                n = i
                break
            end
        end
        if not n then
            UI.SimNotice:Show(L("Planner"),
                L("Both your own sets have items already: pick one of them above the character to change it, or empty one in the planner."))
            return
        end
        self.view = n
        UI.Sim.FillSet(n, from, self:GetViewSpec())
    end
    UI.Sim.PutInSet(n, slot, id)
end

-- The slot's list: shown (from its start: no search, every armor kind; the filter's panel closes), or hidden when it
-- shows already.
function Page:ToggleFlyout(slotFrame)
    local fly = self.flyout
    if fly:IsShown() and fly.owner == slotFrame then
        fly:Hide()
        return
    end
    self:CloseFilter()
    fly.search:SetText("")
    fly.owner, fly.offset, fly.kind = slotFrame, 0, "ALL"
    self:ShowFlyout(slotFrame)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- The spec the sheet shows: the character's active one (the filter's panel picks it).
function Page:GetViewSpec()
    return Player:GetActiveSpec()
end

-- The end of the header's sub line: what the sim found for the spec (the gain of its set), or that it is outdated.
local function SimState(spec)
    if LJ.NO_SIM then return "" end
    local rec = LJ.SimBiS.Get(spec)
    if not rec then return "" end
    if LJ.SimBiS.IsOutdated(rec) then
        return " · " .. Theme.GlyphString("warning", 12, C.warn) .. " " .. Theme.ColorText(L("Percent list outdated"), C.warn)
    end
    return " · " .. Theme.GlyphString("checkCircle", 12, C.ok) .. " "
        .. Theme.ColorText(F("Set %s DPS", string.format("%+.1f", rec.gain)), C.okText)
end

-- A share by the stat weights as the sheet shows it: "+4.1%".
local function Pct(pct) return string.format("%+.1f%%", pct) end

-- A text in the color of its number: green when it adds, red when it takes away.
local function InColor(text, v)
    return Theme.ColorText(text, v >= 0.05 and C.okText or v <= -0.05 and C.bad or C.text3)
end

function Page:Refresh()
    local class = Player.class
    Theme.SetAccent(Theme.ClassAccent(class))
    local spec = self:GetViewSpec()
    if not spec then return end
    local level = BiS.ListLevel(spec)
    -- the simulator plays every spec of the character's class: the header opens it (with Sim it also runs the Best in
    -- Slot sim), a click on a slot picks another item for an own set; with Percent (shares) the share by the stat
    -- weights shows where Sim shows what the sim found
    local ranks = UI.Sim.RanksItems(spec)
    local shares = not ranks

    -- what the sheet shows: the Best in Slot list, what is worn or an own set (only its items; an empty one: its empty
    -- slots, a click on one puts an item in it)
    self.ranking = BiS.Ranking(spec)
    local view = self.view
    local function ListOf(slot) return BiS.ResolveSlot(spec, slot, self.ranking) end
    local function ItemOf(slot)
        if view == "bis" then return ListOf(slot) end
        if view == "worn" then return GetInventoryItemID("player", LJ.SimBiS.INV_SLOT[slot]) end
    end

    -- header
    local header = self.header
    header.title:SetText(Theme.Case(F("%s %s", L(spec.name), Util.ClassName(class))))
    header.sub:SetText(F("Level %d", level) .. " · " .. BiS.WeaponText(spec) .. SimState(spec))
    self:RefreshSimButton(false)
    self.bisButton:SetShown(ranks)
    if ranks then self:RefreshBiSButton(spec) end
    self:RefreshFilter(spec, ranks)

    -- no off hand beside a two-hander
    local twoHand = BiS.IsTwoHand(ItemOf("MAINHAND"))
    self.slots.OFFHAND:SetShown(not twoHand)
    local rec = not LJ.NO_SIM and LJ.SimBiS.Get(spec) or nil
    for _, slot in ipairs(BiS.SLOTS) do
        local frame = self.slots[slot]
        local itemID = frame:IsShown() and ItemOf(slot) or nil
        local worn = GetInventoryItemID("player", LJ.SimBiS.INV_SLOT[slot])
        local label, emptyIcon = BiS.SlotLabel(slot, class)
        local n = slot:match("%u(%d)$")
        frame.label = label
        frame.labelText = L(label) .. (n and (" " .. n) or "")
        frame.itemID = itemID
        frame.icon:SetItem(itemID)
        frame.wornBest, frame.why = false, nil
        local gain = ""
        -- the sim's best pick of the slot (Sim/SimBiS.lua); what is worn shows what it adds over it (Percent: the
        -- list's item by the stat weights)
        local best = rec and rec.best[slot]
        local bestGain
        if view == "worn" then
            if shares then
                local listID = ListOf(slot)
                local pct = listID and listID ~= itemID and LJ.ItemCheck.SlotShare(spec, slot, listID)
                if pct and pct >= 0.05 then bestGain = F("%s with Best in Slot", Pct(pct)) end
            elseif best and best.id ~= itemID then
                bestGain = F("%s DPS with Best in Slot", string.format("+%.1f", best.delta))
            end
            bestGain = bestGain and (Theme.GlyphString("upgrade", 11, C.okText) .. " " .. bestGain)
        end
        if itemID then
            -- (what is worn: every item is owned, no marks)
            frame.icon:SetOwned(Items.IsOwned(itemID) and view ~= "worn")
            frame.name:SetText(Theme.ItemName(itemID))
            -- what is worn: what the slot's best adds over it; else the share the item adds (Percent), what is worn is
            -- best (no pick of the sim beats it) or the damage the item adds
            if bestGain then
                gain = bestGain
            elseif shares then
                local pct = LJ.ItemCheck.SlotShare(spec, slot, itemID)
                if pct and pct >= 0.05 then gain = Pct(pct) end
            else
                local simmed = LJ.SimBiS.SlotGain(spec, slot, itemID)
                if simmed and simmed.delta == 0 and not best and itemID == worn then
                    frame.wornBest = true
                elseif simmed and LJ.SimBiS.Shows(simmed.delta, simmed.err) then
                    gain = F("%s DPS", string.format("+%.1f", simmed.delta))
                end
            end
        else
            -- the slot's own empty picture, its name in grey; the tooltip says why it is empty
            frame.icon.icon:SetTexture(emptyIcon)
            frame.name:SetText(Theme.ColorText(frame.labelText, C.text4))
            gain = bestGain or ""
            if view == "worn" then
                frame.why = L("Nothing worn")
            elseif LJ.SimBiS.Simmed(spec, slot) then
                frame.why = L("No item adds a percent upgrade")
            else
                frame.why = L("Nothing of your list fits this slot at your level: the filter at the top takes more armor or sources.")
            end
        end
        frame.gain:SetText(gain)
        frame.gain:SetShown(gain ~= "")
        SlotVisual(frame)
    end
    self:LayoutSlots()
    -- the Best in Slot list's total gain compared with what is worn
    local listGain
    if shares then
        local pct = LJ.ItemCheck.SetShare(spec, ListOf)
        listGain = pct and Pct(pct)
    elseif ranks then
        listGain = rec and not LJ.SimBiS.IsOutdated(rec) and F("%s DPS", string.format("%+.1f", rec.gain)) or nil
    end
    self:LayoutViews(view, listGain)
    self:DressModel()

    if self.flyout:IsShown() and self.flyout.owner then
        self:ShowFlyout(self.flyout.owner)
    end
end

-- The character wears the sheet's items, in sheet order (the main hand before the off hand); dressed again only when
-- they change.
function Page:DressModel()
    local ids = {}
    for _, slot in ipairs(BiS.SLOTS) do
        local id = self.slots[slot].itemID
        if id then ids[#ids + 1] = id end
    end
    local signature = table.concat(ids, ",")
    if signature == self.dressed then return end
    self.dressed = signature
    local model = self.model
    model:SetUnit("player")
    model:SetSheathed(false)
    model:Undress()
    for _, id in ipairs(ids) do model:TryOn("item:" .. id) end
end

function Page:Show()
    Player:Refresh()
    self:Refresh()
end

function Page:OnHide()
    if self.flyout then self.flyout:Hide() end
    if self.filterPanel then self:CloseFilter() end
end

UI:RegisterPage("bis", Page, { "modern", "classic" })
