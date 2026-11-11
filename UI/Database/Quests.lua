-- Lootified - the database's Quests page: every quest the addon knows, the dungeon and raid quests and the open world
-- quests that reward gear. Filters: the status for the character ("Not for you": the other faction's and other
-- classes' quests), level, where, the reward (usable, an upgrade). The picked quest shows as in the journal: status and
-- facts, objective, where it starts and ends (map buttons), the quest chain and the rewards.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local DB = LJ.Database
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Items = LJ.Items
local Player = LJ.Player
local Quests = LJ.Quests
local BiS = LJ.BiS
local PQ = LJ.PaneQuests
local C = Theme.COLORS

local STATUS = {
    { key = "READY", text = "Turn in" },
    { key = "ACTIVE", text = "In log" },
    { key = "AVAILABLE", text = "Available" },
    { key = "LOCKED", text = "Locked" },
    { key = "LOW_LEVEL", text = "Level too low" },
    { key = "COMPLETED", text = "Completed" },
    { key = "OTHER", text = "Not for you" },
}
-- the status column: short words in the status's color
local STATUS_SHORT = { READY = "Turn in", ACTIVE = "In log", AVAILABLE = "Available", LOCKED = "Locked",
    LOW_LEVEL = "Level %d", COMPLETED = "Completed", OTHER = "Not for you" }

local WHERE = {
    { key = "dungeon", text = "Dungeon", glyph = "castle" },
    { key = "raid", text = "Raid", glyph = "crown" },
    { key = "world", text = "Open world", glyph = "globe" },
}

local REWARDS = {
    { key = "ANY", text = "Any" },
    { key = "MINE", text = "Usable by me" },
    { key = "UPGRADE", text = "Upgrade", module = "bis" },
}

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function Rewards(q)
    local list = {}
    for _, id in ipairs(q.choice or {}) do list[#list + 1] = id end
    for _, id in ipairs(q.reward or {}) do list[#list + 1] = id end
    return list
end

local function Records()
    local list = {}
    for qid, q in pairs(LJ.Data.Quests or {}) do
        local places, kind = {}, "dungeon"
        for i, key in ipairs(q.inst or {}) do
            local inst = LJ.instanceByKey[key]
            if inst then
                places[#places + 1] = inst.name
                if i == 1 and inst.kind == "raid" then kind = "raid" end
            end
        end
        -- who or what starts it: an item by its name as the quest's details show it; an NPC or object by its name,
        -- else the name its location text starts with
        local giver
        if q.start and q.start.kind == "item" then
            giver = Items.GetQuickInfo(q.start.id) or ""
        else
            giver = (q.start and q.start.name) or (q.startText and q.startText:match("^([^,]+)")) or ""
        end
        local where = table.concat(places, ", ")
        -- a quest of no dungeon (an earlier quest of a chain) is an open world quest: where it starts
        if #places == 0 then kind, where = "world", Items.GetQuestZone(q) or "" end
        list[#list + 1] = { id = qid, q = q, name = q.name, level = q.level, min = q.min, giver = giver, where = where,
            kind = kind, inst = q.inst and LJ.instanceByKey[q.inst[1]], rewards = Rewards(q) }
    end
    for qid in pairs(LJ.Data.WorldQuests or {}) do
        local q = not LJ.Data.Quests[qid] and Items.GetWorldQuest(qid)
        if q then
            local zone = Items.GetQuestZone(q) or ""
            list[#list + 1] = { id = qid, q = q, name = q.name, level = q.level, min = q.min, giver = q.giver or "",
                where = zone, kind = "world", rewards = Rewards(q) }
        end
    end
    return list
end

-- A reward the character's class can use (kept per quest: the class does not change).
local function UsableReward(rec)
    if rec.usable == nil then
        rec.usable = false
        for _, id in ipairs(rec.rewards) do
            local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
            if Player:CanClassUse({ id = id, equipLoc = equipLoc, classID = classID, subclassID = subclassID }) then
                rec.usable = true
                break
            end
        end
    end
    return rec.usable
end

local function UpgradeReward(rec)
    for _, id in ipairs(rec.rewards) do
        if BiS.Upgrade(id) then return true end
    end
    return false
end

local function Passes(rec, state)
    local status = Quests.GetStatus(rec.q)
    rec.status = status
    if not state.status[status] then return false end
    if not state.where[rec.kind] then return false end
    if not DB.InLevels(state.level, rec.level) then return false end
    if state.reward == "MINE" then return UsableReward(rec) end
    if state.reward == "UPGRADE" then return UpgradeReward(rec) end
    return true
end

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function ByLevel(a, b)
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    return ByName(a, b)
end

local SORTS = {
    { key = "status", text = "Status", column = 3, compare = function(a, b)
        local sa, sb = Quests.STATUS_ORDER[a.status] or 9, Quests.STATUS_ORDER[b.status] or 9
        if sa ~= sb then return sa < sb end
        return ByLevel(a, b)
    end },
    { key = "level", text = "Level", column = 2, compare = ByLevel },
    { key = "name", text = "Name", column = 1, compare = ByName },
}

---------------------------------------------------------------------------
-- The row: the status glyph, name and giver · place, level, status
---------------------------------------------------------------------------
local GLYPH = 18

Kit.KINDS.dbQuest = {
    height = DB.ROW_HEIGHT,
    create = function(parent, sheet)
        local f = DB.CreateRow(parent)
        f.glyph = Widgets.Glyph(f, "exclamation", GLYPH, C.gold)
        f.glyph:SetPoint("LEFT", sheet.page.cols.pos[1] + 2, 1)
        f.level = DB.Cell(f, "chip")
        f.status = DB.Cell(f, "chip", "RIGHT")
        return f
    end,
    fill = function(f, rec)
        local page = f.sheet.page
        local status, detail = Quests.GetStatus(rec.q)
        local glyph, color = PQ.StatusGlyph(status)
        Theme.SetGlyph(f.glyph, glyph, color)
        local dim = status == Quests.COMPLETED or status == Quests.OTHER
        f.name:SetText(rec.name)
        Widgets.SetTextColor(f.name, dim and C.text3 or C.text1)
        local sub = rec.giver
        if rec.where ~= "" then sub = (sub ~= "" and (sub .. " · ") or "") .. rec.where end
        f.sub:SetText(sub)
        DB.PlaceName(f, GLYPH + 4)
        -- level 0: a quest of any level (shown without one)
        local level = rec.level and rec.level > 0 and rec.level
        f.level:SetText(level and tostring(level) or "")
        Widgets.SetTextColor(f.level, level and Theme.LevelColor(level) or DB.TEXT)
        DB.PlaceCell(f, f.level, 2)
        local st = Theme.QUEST_STATUS[status]
        f.status:SetText(status == Quests.LOW_LEVEL and F(STATUS_SHORT[status], detail or rec.min or 1) or L(STATUS_SHORT[status]))
        Widgets.SetTextColor(f.status, st.color)
        DB.PlaceCell(f, f.status, 3)
        f:SetAlpha(dim and 0.8 or 1)
        f.selected = page.selected == rec.id
        f.hovered = f:IsMouseOver()
        DB.RowVisual(f)
    end,
}

---------------------------------------------------------------------------
-- The detail: the quest as the journal shows it (UI/Pane/Quests.lua)
---------------------------------------------------------------------------
local function CreateDetail(page, panel)
    local sheet = Kit.Sheet(panel, 5)
    sheet.scroll:SetPoint("TOPLEFT", 16, -14)
    sheet.scroll:SetPoint("BOTTOMRIGHT", -16, 12)
    page.detailSheet = sheet
end

local function FillDetail(page, rec)
    local sheet = page.detailSheet
    sheet:Reset(272)
    if not rec then
        sheet:Add("empty", { title = L("No quest picked"), text = L("Pick a quest in the list to see where it starts and what it gives."),
            glyph = "scroll" })
    else
        PQ.FillDetail(sheet, rec.id, rec.inst, function(qid) DB.Go("quests", qid) end)
    end
    sheet:Finish(8)
end

DB.Page({
    key = "quests", scope = "Quests", placeholder = "Search quests, givers, places",
    sorts = SORTS,
    filters = {
        { key = "status", label = "Status", kind = "multi", options = STATUS },
        { key = "level", label = "Level", kind = "range" },
        { key = "where", label = "Where", kind = "multi", options = WHERE },
        { key = "reward", label = "Reward", kind = "chips", options = REWARDS },
    },
    columns = { { title = "Quest" }, { title = "Lv", width = 30 }, { title = "Status", width = 84, justify = "RIGHT" } },
    rowKind = "dbQuest", icon = GLYPH + 4,
    Records = Records, Passes = Passes,
    SearchKey = function(rec) return DB.SearchKey(rec.name, rec.giver, rec.where) end,
    CreateDetail = CreateDetail, FillDetail = FillDetail,
})
