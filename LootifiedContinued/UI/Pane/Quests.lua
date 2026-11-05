-- Lootified - an instance's quests in the journal pages of every look: the quest list (by status, one line per quest)
-- and a quest's details (its name with XP and money, the status and facts; the rewards and the whole quest chain side by
-- side, the parts of one name numbered; the objective, where it starts and ends with map buttons, notes) as sheet
-- entries. The journal pages and the database's Quests page hold the state (the picked quest)
-- and call these to fill their panes; the database also shows the open world quests (giver and rewards) this way.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local PQ = {}
LJ.PaneQuests = PQ

local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Player = LJ.Player
local Quests = LJ.Quests
local Items = LJ.Items
local C = Theme.COLORS

local GROUP_TEXT = {
    READY = "Ready to turn in", ACTIVE = "In your quest log", AVAILABLE = "Available", LOCKED = "Earlier quests missing",
    LOW_LEVEL = "Level too low", COMPLETED = "Completed", OTHER = "Not for your character",
}
-- The quests one line each.
local ROW_HEIGHT, SECTION_HEIGHT = 34, 28
local GAP = 6                 -- between the columns of the objectives
local COL_GAP = 18            -- between the rewards and the chain
local REWARD_SHARE = 0.5      -- the rewards' part of the width beside the chain

-- Where a quest's data comes from (the facts line of its details).
local SOURCE_TEXT = { forever = "Checked in Forever", new = "New in Forever", classic = "Classic data" }

PQ.FILTERS = {
    { key = "MINE", text = "My faction" },
    { key = "ALLIANCE", text = "Alliance quests" },
    { key = "HORDE", text = "Horde quests" },
    { key = "ALL", text = "All quests" },
}

function PQ.FilterText(key)
    for _, f in ipairs(PQ.FILTERS) do
        if f.key == key then return f.text end
    end
    return PQ.FILTERS[1].text
end

-- The glyph of a quest status: "!" and "?" of the game, a lock, a check.
local STATUS_GLYPH = { READY = "question", ACTIVE = "exclamation", AVAILABLE = "exclamation", LOCKED = "lock",
    LOW_LEVEL = "exclamation", COMPLETED = "check", OTHER = "xCircle" }
function PQ.StatusGlyph(status)
    local s = Theme.QUEST_STATUS[status] or Theme.QUEST_STATUS.AVAILABLE
    return STATUS_GLYPH[status] or "exclamation", s.color
end

local function SideShort(side)
    if side == "A" then return L("Alliance") end
    if side == "H" then return L("Horde") end
    return L("Both")
end

-- The classes of a class quest in their colors (onDark: for a tooltip, the game's class colors in every look).
local function ClassNames(q, onDark)
    if q.classes and #q.classes > 0 then
        local names = {}
        for _, c in ipairs(q.classes) do
            local class = c:upper()   -- the data can name a class as "Warlock"
            local code = onDark and Util.ClassColorCode(class) or Theme.ClassColorCode(class)
            names[#names + 1] = code .. Util.ClassName(class) .. "|r"
        end
        return table.concat(names, ", ")
    end
end

-- A quest's status line (lists, tooltips, search results). onDark: for a tooltip (its colors in every look).
function PQ.StatusText(q, status, detail, onDark)
    local s = Theme.QUEST_STATUS[status] or Theme.QUEST_STATUS.AVAILABLE
    local color = onDark and Theme.TooltipColor(s.key) or s.color
    if status == Quests.LOW_LEVEL then
        return Theme.ColorText(F(s.long, detail or q.min or 1), color)
    end
    if status == Quests.LOCKED then
        local missing, groups = Quests.GetMissingPrerequisites(q)
        local first = missing[1] or (groups[1] and Quests.PickFromGroup(groups[1]))
        local name = first and Quests.GetName(first)
        if name and name ~= q.name then return Theme.ColorText(F("Requires: %s", name), color) end
        return Theme.ColorText(L("Requires the earlier part of this chain"), color)
    end
    if status == Quests.OTHER then
        if q.side == "A" and Player.faction ~= "Alliance" then return Theme.ColorText(L("Alliance only"), color) end
        if q.side == "H" and Player.faction ~= "Horde" then return Theme.ColorText(L("Horde only"), color) end
        -- (a quest of the character's class only other races can take: "Not for your character")
        local classes = not Quests.IsForClass(q, Player.class) and ClassNames(q, onDark)
        return Theme.ColorText(classes and F("%s only", classes) or L(s.long), color)
    end
    return Theme.ColorText(L(s.long), color)
end

-- A quest's status icon (bg, ring, symbol, glyph: the search results' rows).
function PQ.SetStatusIcon(icon, status)
    local s = Theme.QUEST_STATUS[status] or Theme.QUEST_STATUS.AVAILABLE
    local c = s.color
    icon.bg:SetVertexColor(c[1], c[2], c[3], 0.12)
    icon.ring:SetVertexColor(c[1], c[2], c[3], 0.36)
    if s.symbol then
        icon.symbol:SetText(s.symbol)
        Widgets.SetTextColor(icon.symbol, c)
        icon.symbol:Show()
        icon.glyph:Hide()
    else
        icon.symbol:Hide()
        Theme.SetGlyph(icon.glyph, s.glyph or "check", c)
        icon.glyph:Show()
    end
end

-- The quests of an instance as the list shows them (the journal's faction filter), open ones first, the finished ones
-- last; with their statuses.
function PQ.List(inst)
    local list = Quests.ForInstance(inst.key, LJ.db.journal.questFilter, true)
    local status, detail, order = {}, {}, {}
    for i, q in ipairs(list) do
        order[q] = i
        status[q], detail[q] = Quests.GetStatus(q)
    end
    table.sort(list, function(a, b)
        local sa, sb = Quests.STATUS_ORDER[status[a]] or 9, Quests.STATUS_ORDER[status[b]] or 9
        if sa ~= sb then return sa < sb end
        return order[a] < order[b]
    end)
    return list, status, detail
end

-- A frame whose text (f.text) is cut at its end: the whole text (d.text) in a tooltip (the rows of the quest list, the
-- steps of a chain, the status of a quest's details).
local function CutTextEnter(f, d)
    if f.text:IsTruncated() then
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function CutTextLeave(f)
    if GameTooltip:GetOwner() == f then GameTooltip:Hide() end
end

-- Fills a sheet with the quest list of an instance: a section per status, a row per quest (one per chain). selected: the
-- picked row's quest. Returns the quests in list order and the entry of each quest's row ([questID] = cursor offset).
function PQ.FillList(sheet, inst, selected, onSelect)
    local list, status = PQ.List(inst)
    local rowY = {}
    local i = 1
    while i <= #list do
        local s = status[list[i]]
        local j = i
        while list[j + 1] and status[list[j + 1]] == s do j = j + 1 end
        sheet:Add("section", { text = L(GROUP_TEXT[s] or s), count = j - i + 1 }, SECTION_HEIGHT)
        for k = i, j do
            local q = list[k]
            local glyph, color = PQ.StatusGlyph(s)
            local key = Quests.IsAccessQuest(inst.key, q.id)
            rowY[q.id] = sheet.cursor
            sheet:Add("row", { text = q.name, right = q.level and tostring(q.level), rightColor = q.level and Theme.LevelColor(q.level),
                tag = key and Util.Upper(L("Key")) or nil, tagKind = "gold", glyph = glyph, glyphColor = color,
                selected = q.id == selected, dim = s == Quests.COMPLETED or s == Quests.OTHER, questID = q.id,
                onClick = function() onSelect(q.id) end, onEnter = CutTextEnter }, ROW_HEIGHT)
        end
        sheet:Space(6)
        i = j + 1
    end
    if #list == 0 then
        local total = #(LJ.Data.InstanceQuests and LJ.Data.InstanceQuests[inst.key] or {})
        local text = L(total == 0 and "No quests are known for this instance yet." or "No quests match this filter.")
        sheet:Add("empty", { title = L("No quests"), text = text, glyph = "scroll" })
    end
    return list, rowY
end

---------------------------------------------------------------------------
-- Detail kinds: where a quest starts and ends, the chain
---------------------------------------------------------------------------
local function LocationLine(loc, text)
    local line = text
    if line and loc and loc.name then
        local prefix = loc.name .. ", "
        if line:sub(1, #prefix) == prefix then line = line:sub(#prefix + 1) end
    end
    if not line or line == "" then line = loc and loc.zone or "" end
    return line
end

local function SameSpot(a, b)
    return a and b and a.id and a.id == b.id and a.kind == b.kind
        and (a.map == b.map) and math.abs((a.x or 0) - (b.x or 0)) < 1 and math.abs((a.y or 0) - (b.y or 0)) < 1
end

-- "Start" / "Turn in" row, the name and the place on one line: data = { label, glyph, name, zone, spot (map marker or
-- nil), mapLabel }
local function WhereText(d)
    if not d.zone or d.zone == "" then return d.name or "" end
    return (d.name or "") .. "  ·  " .. Theme.ColorText(d.zone, C.text3)
end

-- The room right of the name for the map button: its label, glyph and padding (Widgets.CreateButton) and a gap.
local function MapRoom(d)
    if not d.spot then return 0 end
    return Kit.TextWidth(L(LJ.MapPin.IsTarget(d.spot) and "Marked" or (d.mapLabel or "Map")), "button") + 52
end

Kit.KINDS.where = {
    height = function(d, w)
        return math.max(30, 12 + Kit.TextHeight(WhereText(d), "itemSmall", w - 96 - MapRoom(d), 2))
    end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.icon = Widgets.Glyph(f, "flag", 13, Kit.SectionColor())
        f.icon:SetPoint("TOPLEFT", 2, -8)
        f.label = Widgets.Text(f, "label", Kit.SectionColor())
        f.label:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
        f.name = Widgets.Text(f, "itemSmall", C.white)
        f.name:SetPoint("TOPLEFT", 96, -8)
        f.name:SetWordWrap(true)
        f.map = Widgets.CreateButton(f, "Map", "ghost", "mapPin", nil, 22)
        f.map:SetPoint("TOPRIGHT", -4, -5)
        f.map:SetScript("OnClick", function(b)
            if not b.spot then return end
            if LJ.MapPin.IsTarget(b.spot) then LJ.MapPin.Clear() else LJ.MapPin.Show(b.spot) end
        end)
        return f
    end,
    fill = function(f, d, w)
        Theme.SetGlyph(f.icon, d.glyph, Kit.SectionColor())
        f.label:SetText(Util.Upper(L(d.label)))
        f.name:SetWidth(w - 96 - MapRoom(d))
        f.name:SetText(WhereText(d))
        f.map.spot = d.spot
        f.map:SetShown(d.spot ~= nil)
        if d.spot then
            local marked = LJ.MapPin.IsTarget(d.spot)
            f.map:SetGlyph(marked and "check" or "mapPin")
            f.map:SetLabel(marked and "Marked" or (d.mapLabel or "Map"))
            Widgets.SetTooltip(f.map, marked and "Marked on your map" or "Show on the map",
                marked and "Click to remove the mark." or "Opens the world map and sets a marker you can follow.", "ANCHOR_TOP")
        end
    end,
}

-- The head of a quest's details: its name with the XP and money at the right (a narrow pane: at the bottom), below it
-- the status as a tag and the facts (level, side, group, classes, key, where the data comes from) beside it, or under it
-- on as many lines as they need where they do not fit beside it. A status wider than the pane is cut at its edge (the
-- whole status in a tooltip).
-- data = { q, status, detail, reward, facts }
local HEAD_RIGHT = 150            -- room for the XP and money
local WIDE = 400                  -- from this width: the XP beside the name, the objectives and rewards in two columns
local FACTS_GAP = 10              -- between the status and the facts beside it
local STATUS_PAD = 14             -- the status tag's padding around its text (Widgets.CreatePill, 20 high)

-- Whether the facts fit on one line beside the status tag (its width as Widgets.CreatePill gives it).
local function FactsBeside(d, w)
    local status = math.floor(Kit.TextWidth(PQ.StatusText(d.q, d.status, d.detail), "pill") + STATUS_PAD + 0.5)
    return status + FACTS_GAP + Kit.TextWidth(d.facts, "small") <= w
end

local function StatusEnter(tag)
    local head = tag:GetParent()
    local d = head.sheet.data[head.entry]
    CutTextEnter(tag, { text = PQ.StatusText(d.q, d.status, d.detail, true) })
end

Kit.KINDS.questHead = {
    height = function(d, w)
        local wide = w >= WIDE
        return math.ceil(Kit.TextHeight(Theme.Case(d.q.name), "title", w - (wide and HEAD_RIGHT or 0), 0)) + 40
            + (FactsBeside(d, w) and 0 or (6 + math.ceil(Kit.TextHeight(d.facts, "small", w, 0))))
            + ((not wide and d.reward ~= "") and 20 or 0)
    end,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.name = Widgets.Text(f, "title", C.white)
        f.name:SetPoint("TOPLEFT", 0, -4)
        f.name:SetWordWrap(true)
        f.reward = Widgets.Text(f, "nameBold", C.text2)
        f.status = Widgets.CreatePill(f, 20)
        f.status:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -8)
        f.status:EnableMouse(true)
        f.status:SetScript("OnEnter", StatusEnter)
        f.status:SetScript("OnLeave", CutTextLeave)
        f.facts = Widgets.Text(f, "small", C.text3)
        f.facts:SetWordWrap(true)
        return f
    end,
    fill = function(f, d, w)
        local wide = w >= WIDE
        local beside = FactsBeside(d, w)
        f.name:SetWidth(w - (wide and HEAD_RIGHT or 0))
        f.name:SetText(Theme.Case(d.q.name))
        f.reward:SetText(d.reward)
        f.reward:ClearAllPoints()
        if wide then
            f.reward:SetPoint("TOPRIGHT", 0, -8)
            f.reward:SetJustifyH("RIGHT")
        else
            f.reward:SetPoint("TOPLEFT", beside and f.status or f.facts, "BOTTOMLEFT", 0, -7)
            f.reward:SetJustifyH("LEFT")
        end
        f.status.text:SetWidth(0)
        f.status:Set(PQ.StatusText(d.q, d.status, d.detail), Theme.QUEST_STATUS[d.status].pill)
        if f.status:GetWidth() > w then
            -- wider than the pane: the tag ends at its edge, its text is cut there
            f.status:SetWidth(w)
            f.status.text:SetWidth(w - STATUS_PAD)
        end
        f.facts:ClearAllPoints()
        if beside then
            f.facts:SetPoint("LEFT", f.status, "RIGHT", FACTS_GAP, 0)
            f.facts:SetWidth(w - f.status:GetWidth() - FACTS_GAP)
        else
            f.facts:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -6)
            f.facts:SetWidth(w)
        end
        f.facts:SetText(d.facts)
    end,
}

-- A hairline between the parts of the details.
Kit.KINDS.rule = {
    height = 13,
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        f.line = Kit.Line(f)
        f.line:SetHeight(1)
        f.line:SetPoint("LEFT")
        f.line:SetPoint("RIGHT")
        return f
    end,
    fill = function() end,
}

-- A step of the quest chain: a click shows its quest in the details like a quest of the list (onStep(questID)). The node
-- always shows the step's status; the quest shown is marked by the row (accent bar, bold name), a dungeon quest (the
-- chain's quest in the dungeon's list) by a castle. data = { questID, text, meta, nodeColor, ring, done, current,
-- before, first, last, main, onStep }
Kit.KINDS.chain = {
    height = 26,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        Kit.AddMarks(f)
        f.up = Widgets.Solid(f, "ARTWORK", 0, Theme.IsClassic() and Theme.HEARTH.line or { 1, 1, 1 }, Theme.IsClassic() and 0.35 or 0.14)
        f.up:SetWidth(1)
        f.down = Widgets.Solid(f, "ARTWORK", 0, Theme.IsClassic() and Theme.HEARTH.line or { 1, 1, 1 }, Theme.IsClassic() and 0.35 or 0.14)
        f.down:SetWidth(1)
        f.node = f:CreateTexture(nil, "ARTWORK", nil, 2)
        f.node:SetSize(11, 11)
        f.node:SetPoint("LEFT", 8, 0)
        f.mark = Widgets.Glyph(f, "check", 8, C.dark, "ARTWORK", 3)
        f.mark:SetPoint("CENTER", f.node, "CENTER")
        f.up:SetPoint("BOTTOM", f.node, "TOP")
        f.up:SetPoint("TOP", f, "TOP")
        f.down:SetPoint("TOP", f.node, "BOTTOM")
        f.down:SetPoint("BOTTOM", f, "BOTTOM")
        f.text = Widgets.Text(f, "itemSmall", C.text1)
        f.text:SetPoint("LEFT", f.node, "RIGHT", 9, 0)
        f.meta = Widgets.Text(f, "tiny", C.text3, nil, "RIGHT")
        f.meta:SetPoint("RIGHT", -8, 0)
        f.main = Widgets.Glyph(f, "castle", 11, C.goldText)
        f.main:SetPoint("RIGHT", f.meta, "LEFT", -6, 0)
        f:SetScript("OnClick", function(self)
            local d = self.sheet.data[self.entry]
            if d.current then return end      -- the quest itself is shown already
            Util.PlaySound("IG_MAINMENU_OPTION")
            d.onStep(d.questID)
        end)
        f:SetScript("OnEnter", function(self)
            self.hovered = true
            Kit.MarkVisual(self)
            CutTextEnter(self, self.sheet.data[self.entry])
        end)
        f:SetScript("OnLeave", function(self)
            self.hovered = false
            Kit.MarkVisual(self)
            CutTextLeave(self)
        end)
        return f
    end,
    fill = function(f, d)
        local c = d.nodeColor
        f.node:SetTexture(d.ring and Theme.TEX.circleRing or Theme.TEX.circle)
        f.node:SetVertexColor(c[1], c[2], c[3], 1)
        f.mark:SetShown(d.done == true)
        f.up:SetShown(not d.first)
        f.down:SetShown(not d.last)
        f.text:SetText(d.text)
        f.main:SetShown(d.main == true)
        f.text:SetPoint("RIGHT", d.main and f.main or f.meta, "LEFT", -8, 0)
        f.text:SetFontObject(Theme.Font(d.current and "h3" or "itemSmall"))
        Widgets.SetTextColor(f.text, d.current and C.white or (d.dim and C.text3 or C.text1))
        f.meta:SetText(d.meta or "")
        f.selected = d.current
        f.hovered = f:IsMouseOver()
        Kit.MarkVisual(f)
    end,
}

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------
-- The map marker of a quest's start or turn-in spot: the spot itself, or the dungeon's entrance for a spot inside.
local function WhereSpot(loc, fallbackText, fallbackInside, qname, role, inst)
    if loc and loc.map and loc.x and loc.y then
        return { map = loc.map, x = loc.x, y = loc.y, title = loc.name or qname, detail = L(role) .. ": " .. (qname or "") }, "Map"
    end
    local inside = (loc and (loc.inside or (loc.zone and loc.zone:find("^inside"))))
        or (fallbackText and (fallbackInside or fallbackText:lower():find("inside")))
    local e = inside and inst and inst.entrance
    if e then return { map = e.map, x = e.x, y = e.y, title = inst.name, detail = L("Dungeon entrance") }, "Entrance" end
end

local function WhereData(label, glyph, loc, fallbackText, fallbackInside, q, role, inst)
    LJ.MapPin.Resolve(loc)
    local name, zone
    if loc and loc.kind == "item" then
        name = loc.id and Theme.ItemName(loc.id) or L("An item")
        zone = loc.text or L("starts from an item")
    elseif loc and loc.name then
        name, zone = loc.name, LocationLine(loc, fallbackText)
    elseif fallbackText then
        local n, rest = fallbackText:match("^([^,]+),%s*(.+)$")
        name, zone = n or fallbackText, rest or ""
    else
        name, zone = L("Unknown"), ""
    end
    local spot, mapLabel = WhereSpot(loc, fallbackText, fallbackInside, q.name, role, inst)
    return { label = label, glyph = glyph, name = name, zone = zone, spot = spot, mapLabel = mapLabel }
end

-- The steps of a quest's chain with the quest itself marked: node color, ring, meta text. Returns the entries and the
-- chain's section title.
local function ChainEntries(q, inst)
    local chain = Quests.GetFullChain(q)
    if #chain <= 1 then return nil end
    local earlier, missing, completed = 0, 0, 0
    for _, e in ipairs(chain) do
        if e.role == "before" then
            earlier = earlier + 1
            if Quests.IsCompleted(e.id) then
                completed = completed + 1
            elseif not e.passed then
                missing = missing + 1
            end
        end
    end
    local label = L("Quest chain")
    if missing > 0 then
        label = F(missing == 1 and "Quest chain · %d earlier quest missing" or "Quest chain · %d earlier quests missing", missing)
    elseif earlier > 0 then
        label = L(completed == earlier and "Quest chain · all earlier quests completed" or "Quest chain · no earlier quest missing")
    end
    -- quests of one name in the chain get their part number (The Defias Brotherhood has seven parts)
    local named, part = {}, {}
    for _, e in ipairs(chain) do
        local name = Quests.GetName(e.id)
        named[name] = (named[name] or 0) + 1
    end
    -- the dungeon quests: the chain's quests in the dungeon's list (one per chain there)
    local main = {}
    for _, mq in ipairs(inst and Quests.ForInstance(inst.key, "ALL", true) or {}) do main[mq.id] = true end
    local list = {}
    for _, e in ipairs(chain) do
        local cq = Quests.Get(e.id)
        local cstatus = Quests.GetStatus(cq)
        local current = e.role == "current"
        local done = cstatus == Quests.COMPLETED
        local inLog = cstatus == Quests.READY or cstatus == Quests.ACTIVE
        local passed = e.passed and not done and not inLog
        local ahead = e.role == "after"
        local available = not done and not inLog and not passed and cstatus == Quests.AVAILABLE
        -- the node: the step's own status, the shown quest too (the row marks that one)
        local nodeColor, ring
        if done then
            nodeColor = C.ok
        elseif inLog then
            nodeColor = Theme.QUEST_STATUS[cstatus].color
        elseif passed then
            nodeColor = C.text4
        elseif available then
            nodeColor, ring = C.gold, true
        elseif e.role == "before" then
            nodeColor, ring = C.red, true
        else
            nodeColor, ring = C.text4, true
        end
        -- at the right: the level (the node shows the state); an earlier quest still to do: "missing"
        local meta
        if not done and not inLog and not passed and not available and not ahead and not current then
            meta = Theme.ColorText(L("missing"), C.redText)
        elseif cq.level then
            meta = Theme.ColorText(F("Lv %s", cq.level), (done or passed) and C.text4 or Theme.LevelColor(cq.level))
        end
        local name = Quests.GetName(e.id)
        local text = name
        if named[name] > 1 then
            part[name] = (part[name] or 0) + 1
            text = name .. "  " .. Theme.ColorText(F("Part %d", part[name]), C.text4)
        end
        list[#list + 1] = { questID = e.id, text = text, meta = meta, nodeColor = nodeColor, ring = ring,
            done = done, current = current, dim = done or passed, before = e.role == "before", main = main[e.id] == true }
    end
    return list, label
end

-- Entries side by side from the cursor: columns = { { width, entries = { { kind, data, h } } } } from the left. They are
-- placed top down (the sheet's order: by y, then x); the cursor moves below the longest column.
local function Columns(sheet, columns)
    local placed, x, top, bottom = {}, 0, sheet.cursor, sheet.cursor
    for _, col in ipairs(columns) do
        local y = top
        for _, e in ipairs(col.entries) do
            local k = Kit.KINDS[e.kind]
            local h = e.h or (type(k.height) == "function" and k.height(e.data, col.width) or k.height)
            placed[#placed + 1] = { kind = e.kind, data = e.data, x = x, y = y, w = col.width, h = h }
            y = y + h
        end
        bottom = math.max(bottom, y)
        x = x + col.width + COL_GAP
    end
    table.sort(placed, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    for _, e in ipairs(placed) do sheet:Place(e.kind, e.data, e.x, e.y, e.w, e.h) end
    sheet.cursor = bottom
end

-- The rewards one per line with the upgrade mark (an item of the Best in Slot list), the reputation below them.
local function RewardEntries(q)
    local entries = {}
    local choice, items = q.choice or {}, q.reward or {}
    if #choice == 0 and #items == 0 and not (q.rep and #q.rep > 0) then return entries end
    entries[1] = { kind = "section", data = { text = L(#choice > 1 and "Rewards · choose one" or "Rewards") }, h = SECTION_HEIGHT }
    local function Add(id, also)
        entries[#entries + 1] = { kind = "item", h = Kit.M().item, data = { id = id, upgrade = LJ.BiS.Upgrade(id),
            tag = also and "ALSO" or nil, col = 1, cols = 1 } }
    end
    for _, id in ipairs(choice) do Add(id, false) end
    for _, id in ipairs(items) do Add(id, #choice > 0) end
    local reps = {}
    for _, rep in ipairs(q.rep or {}) do
        reps[#reps + 1] = Theme.ColorText(string.format("%s %s%d", rep[1], rep[2] > 0 and "+" or "", rep[2]),
            rep[2] > 0 and C.okText or C.redText)
    end
    if #reps > 0 then
        entries[#entries + 1] = { kind = "text", data = { text = table.concat(reps, "   ·   "), font = "bodySemi", color = C.text2 } }
    end
    return entries
end

-- The whole quest chain in play order, every step on its own line (a click shows its quest: onStep(questID); the
-- dungeon quests of inst marked); a choice of earlier quests below it.
local function ChainColumn(q, onStep, inst)
    local entries = {}
    local steps, label = ChainEntries(q, inst)
    if not steps then return entries end
    entries[1] = { kind = "section", data = { text = label }, h = SECTION_HEIGHT }
    for i, e in ipairs(steps) do
        e.first, e.last, e.onStep = i == 1, i == #steps, onStep
        entries[#entries + 1] = { kind = "chain", data = e }
    end
    -- a choice of earlier quests: the versions that fit this character, when there is more than one
    local fits = Quests.ChainFilter(q)
    for _, group in ipairs(q.preAny or {}) do
        local names, listed = {}, {}
        for _, p in ipairs(group) do
            local rec = Quests.Get(p)
            local pname = Quests.GetName(p)
            if (not rec or fits(rec)) and not listed[pname] then
                listed[pname] = true
                names[#names + 1] = pname
            end
        end
        if #names > 1 then
            entries[#entries + 1] = { kind = "text", data = { text = F("One of: %s", table.concat(names, " / ")), font = "small", color = C.text3, indent = 16 } }
        end
    end
    return entries
end

-- Fills a sheet with a quest's details: a dungeon quest (Data/Quests.lua), or an open world quest (Data/WorldQuests.lua:
-- its giver and rewards). onStep(questID): a step of its chain was clicked (the page shows that quest).
function PQ.FillDetail(sheet, qid, inst, onStep)
    local q = Quests.Get(qid) or Items.GetWorldQuest(qid)
    if not q then
        sheet:Add("empty", { title = L("No quest selected"), text = L("Select a quest to see what you need to do and where it starts."), glyph = "scroll" })
        return nil
    end
    local status, detail = Quests.GetStatus(q)
    local cols = sheet.width >= WIDE and 2 or 1

    -- the name with the XP and money, the status and the facts
    local xp, copper = Quests.GetXPMoney(qid)
    local reward = {}
    if xp then reward[#reward + 1] = F("%s XP", BreakUpLargeNumbers(xp)) end
    if copper and copper > 0 then reward[#reward + 1] = Quests.FormatMoney(copper) end
    local facts = {}
    if q.level then facts[#facts + 1] = F("Level %s", q.level) end
    if q.side == "A" or q.side == "H" then facts[#facts + 1] = SideShort(q.side) end
    if q.group then facts[#facts + 1] = F("Group %s", q.group) end
    local classes = ClassNames(q)
    if classes and status ~= Quests.OTHER then facts[#facts + 1] = F("%s only", classes) end
    if q.min and status ~= Quests.LOW_LEVEL then facts[#facts + 1] = F("Needs level %s", q.min) end
    if inst and Quests.IsAccessQuest(inst.key, q.id) then facts[#facts + 1] = Theme.ColorText(L("Key"), C.goldText) end
    facts[#facts + 1] = L(SOURCE_TEXT[q.src] or SOURCE_TEXT.classic)
    sheet:Space(2)
    sheet:Add("questHead", { q = q, status = status, detail = detail, reward = table.concat(reward, "  ·  "),
        facts = table.concat(facts, "  ·  ") })

    -- the rewards and the quest chain side by side (one above the other in a narrow pane or when one is missing)
    local left, right = RewardEntries(q), (not q.world) and ChainColumn(q, onStep, inst) or {}
    if cols == 2 and #left > 0 and #right > 0 then
        local lw = math.floor((sheet.width - COL_GAP) * REWARD_SHARE)
        Columns(sheet, { { width = lw, entries = left }, { width = sheet.width - COL_GAP - lw, entries = right } })
    else
        for _, e in ipairs(right) do left[#left + 1] = e end
        Columns(sheet, { { width = sheet.width, entries = left } })
    end

    -- the objective: live progress from the quest log, else what the quest asks for
    sheet:Add("rule", {})
    if q.obj and q.obj ~= "" then
        sheet:Add("text", { text = q.obj, font = "body", color = C.text2, spacing = 3, pad = 8 })
    end
    local objectives = (status == Quests.ACTIVE or status == Quests.READY) and Quests.GetObjectives(q.id) or nil
    if objectives and #objectives > 0 then
        local rows = {}
        for _, o in ipairs(objectives) do
            local have, need = o.numFulfilled or 0, math.max(1, o.numRequired or 1)
            rows[#rows + 1] = { text = o.text or "", right = string.format("%d / %d", have, need),
                rightColor = o.finished and C.okText or C.blueText, glyph = o.finished and "checkCircle" or "circle",
                glyphColor = o.finished and C.ok or C.text4 }
        end
        sheet:Grid("row", rows, cols, ROW_HEIGHT, GAP)
    else
        local cells = {}
        for _, it in ipairs(q.items or {}) do
            local sub = it.src and it.src ~= "" and it.src or nil
            if it.count and it.count > 1 then sub = it.count .. "x" .. (sub and (" · " .. sub) or "") end
            cells[#cells + 1] = { id = it.id, count = it.count, chance = it.chance, sub = sub,
                extraTooltip = it.questDrop and { { L("Drops only while you are on the quest."), 0.8, 0.8, 0.8 } } or nil }
        end
        if #cells > 0 then sheet:Grid("item", cells, cols, 40, GAP) end
        local kills = {}
        for _, k in ipairs(q.kills or {}) do
            kills[#kills + 1] = { text = F(k.object and "Use %d %s" or "Kill %d %s", k.count or 1, k.name), glyph = "circle", glyphColor = C.text4 }
        end
        if #kills > 0 then sheet:Grid("row", kills, cols, ROW_HEIGHT, GAP) end
    end

    -- where it starts and ends (an open world quest: its giver; the data has no turn-in for those)
    sheet:Add("rule", {})
    if q.world then
        sheet:Add("where", WhereData("START", "flag", q.loc or { name = q.giver }, nil, nil, q, "Quest giver", inst))
    else
        LJ.MapPin.Resolve(q.start)
        LJ.MapPin.Resolve(q.finish)
        sheet:Add("where", WhereData("START", "flag", q.start, q.startText, q.startInside, q, "Quest giver", inst))
        if SameSpot(q.start, q.finish) then
            sheet:Add("where", { label = "TURN IN", glyph = "seal", name = L("back at the quest giver") })
        else
            sheet:Add("where", WhereData("TURN IN", "seal", q.finish, q.finishText, q.finishInside, q, "Turn in", inst))
        end
    end

    if q.note and q.note ~= "" then
        sheet:Add("section", { text = L("Note") }, SECTION_HEIGHT)
        sheet:Add("text", { text = q.note, font = "bodySmall", color = C.text3, spacing = 3 })
    end
end

-- The quest list control of a pane: the faction filter (the journal's setting). onChange(): redraw.
function PQ.CreateControls(parent, onChange)
    local db = LJ.db.journal
    local filter = Widgets.CreateDropdown(parent, nil, function(menu)
        for _, f in ipairs(PQ.FILTERS) do
            menu:CreateRadio(f.text, function() return LJ.db.journal.questFilter == f.key end, function()
                LJ.db.journal.questFilter = f.key
                onChange()
            end)
        end
    end, PQ.FilterText(db.questFilter), "shieldChevron")
    local controls = { filter = filter }
    function controls:Update()
        self.filter:SetLabel(PQ.FilterText(LJ.db.journal.questFilter))
    end
    return controls
end
