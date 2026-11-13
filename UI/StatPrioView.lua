-- Lootified - the filter panel's Stat priority tab (UI/ListFilter.lua): the active spec's stats top down
-- (Core/StatPrio.lua), each with a bar of what an item's usual amount of it counts now (the top one full) and in the
-- accent color the ones the player moved. Drag a stat up or down to change the order: the list, For you and the Percent
-- numbers follow at once. Default order gives the spec's own order back. Shown with Percent only (with Sim the panel has
-- no such tab: Core/StatPrio.lua, StatPrio.Counts).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local StatPrio = LJ.StatPrio
local C = Theme.COLORS

local View = {}
UI.StatPrioView = View

local ROW_HEIGHT, ROW_STEP, BAR_WIDTH = 17, 18, 110

local function RowVisual(row)
    local a = Theme.accent
    if row.dragged then
        row.hl:SetColor(a[1], a[2], a[3], 0.24)
    elseif row.hovered then
        row.hl:SetColor(a[1], a[2], a[3], 0.12)
    else
        row.hl:SetColor(1, 1, 1, 0.035)
    end
    Widgets.SetTextColor(row.name, row.moved and a or C.text1)
    row.bar:SetColorTexture(a[1], a[2], a[3], 0.9)
end

-- The rows at their places, numbered: while one is dragged the others make room at the place it points to.
local function PlaceRows(view)
    local dragged, slot = view.dragged, 1
    for i = 1, view.count do
        local row = view.rows[i]
        if row == dragged then
            row.rank:SetText(view.target)
        else
            if dragged and slot == view.target then slot = slot + 1 end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(slot - 1) * ROW_STEP)
            row.rank:SetText(slot)
            slot = slot + 1
        end
    end
end

-- The cursor's height in the list, from its top (negative below it).
local function CursorY(view)
    local _, y = GetCursorPosition()
    return y / view.list:GetEffectiveScale() - view.list:GetTop()
end

-- The dragged row follows the cursor inside the list; the place it points to (1 .. the stats) opens.
local function DragUpdate(row)
    local view = row.view
    local y = CursorY(view)
    local target = math.max(1, math.min(view.count, math.floor(-y / ROW_STEP) + 1))
    if target ~= view.target then
        view.target = target
        PlaceRows(view)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, math.max(-(view.count - 1) * ROW_STEP, math.min(0, y + ROW_HEIGHT / 2)))
end

local function DragStart(row)
    local view = row.view
    view.dragged, view.target = row, row.index
    row.dragged = true
    row:SetFrameLevel(view.list:GetFrameLevel() + 10)
    RowVisual(row)
    GameTooltip:Hide()
    row:SetScript("OnUpdate", DragUpdate)
end

-- The drag ends: the stat goes to the place it points to (StatPrio.Move: everything follows) unless commit is false.
local function EndDrag(view, commit)
    local row, target = view.dragged, view.target
    if not row then return end
    row:SetScript("OnUpdate", nil)
    row.dragged = false
    row:SetFrameLevel(view.list:GetFrameLevel() + 1)
    view.dragged, view.target = nil, nil
    if commit and target ~= row.index then
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        StatPrio.Move(view.spec, row.key, target)
    end
    view:Refresh(view.spec)
end

local function NewRow(view)
    local row = CreateFrame("Button", nil, view.list)
    row:SetSize(view.width, ROW_HEIGHT)
    row:SetFrameLevel(view.list:GetFrameLevel() + 1)
    row.view = view
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 4)
    row.grip = Widgets.Glyph(row, "list", 11, C.text4)
    row.grip:SetPoint("LEFT", 6, 0)
    row.rank = Widgets.Text(row, "small", C.text4, nil, "RIGHT")
    row.rank:SetWidth(16)
    row.rank:SetPoint("LEFT", row.grip, "RIGHT", 2, 0)
    row.name = Widgets.Text(row, "bodySmall", C.text1)
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -(BAR_WIDTH + 20), 0)
    row.track = row:CreateTexture(nil, "ARTWORK")
    row.track:SetSize(BAR_WIDTH, 4)
    row.track:SetPoint("RIGHT", -10, 0)
    row.track:SetColorTexture(1, 1, 1, 0.08)
    row.bar = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.bar:SetHeight(4)
    row.bar:SetPoint("LEFT", row.track, "LEFT")
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnEnter", function(r) r.hovered = true RowVisual(r) end)
    row:SetScript("OnLeave", function(r) r.hovered = false RowVisual(r) end)
    row:SetScript("OnDragStart", DragStart)
    row:SetScript("OnDragStop", function(r) EndDrag(r.view, true) end)
    Theme.OnAccent(row, RowVisual)
    return row
end

-- The spec's stats now: a row each (the bar: its value against the top one's); the view's height fits.
local function ViewRefresh(view, spec)
    view.spec = spec
    view.label:SetText(Util.Upper(F("Stats for %s", L(spec.name))))
    view.reset:SetEnabled(StatPrio.IsCustom(spec))
    local top = 24 + 6 + math.ceil(view.text:GetStringHeight()) + 10
    view.list:ClearAllPoints()
    view.list:SetPoint("TOPLEFT", 0, -top)
    local rows, best = StatPrio.Rows(spec), 0
    for _, r in ipairs(rows) do best = math.max(best, r.value) end
    for i, r in ipairs(rows) do
        local row = view.rows[i] or NewRow(view)
        view.rows[i] = row
        row.index, row.key, row.moved = i, r.key, r.moved
        row.name:SetText(L(r.text))
        row.bar:SetWidth(math.max(1, BAR_WIDTH * r.value / best))
        RowVisual(row)
        row:Show()
    end
    for i = #rows + 1, #view.rows do view.rows[i]:Hide() end
    view.count = #rows
    view.list:SetHeight(#rows * ROW_STEP - (ROW_STEP - ROW_HEIGHT))
    PlaceRows(view)
    view:SetHeight(top + view.list:GetHeight())
end

-- The tab inside parent (the panel places it), width wide: its label with Default order beside it, the line on how
-- it works, the stats. view:Refresh(spec).
function View.Create(parent, width)
    local view = CreateFrame("Frame", nil, parent)
    view:SetWidth(width)
    view.width = width
    view.reset = Widgets.CreateButton(view, "Default order", "ghost", "reset", nil, 24)
    view.reset:SetPoint("TOPRIGHT", 0, 0)
    view.label = Widgets.Text(view, "label", C.text4)
    view.label:SetPoint("LEFT", view, "TOPLEFT", 0, -12)
    view.label:SetPoint("RIGHT", view.reset, "LEFT", -10, 0)
    view.text = Widgets.Text(view, "small", C.text2)
    view.text:SetPoint("TOPLEFT", 0, -30)
    view.text:SetWidth(width)
    view.text:SetJustifyH("LEFT")
    view.text:SetWordWrap(true)
    view.text:SetText(L("Drag a stat up or down: the higher, the more it counts. Your list and the percent numbers follow at once."))
    view.list = CreateFrame("Frame", nil, view)
    view.list:SetWidth(width)
    view.rows, view.count = {}, 0
    view.reset:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        StatPrio.Reset(view.spec)
        view:Refresh(view.spec)
    end)
    Widgets.SetTooltip(view.reset, "Default order", "Your spec's own order again.", "ANCHOR_TOP")
    view.Refresh = ViewRefresh
    -- a drag the panel's closing ends changes nothing
    view:SetScript("OnHide", function(v) EndDrag(v, false) end)
    return view
end
