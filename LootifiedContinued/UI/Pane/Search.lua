-- Lootified - the search page in the classic look: the kinds of results with their numbers on the left,
-- the results on the right (dungeons and raids, bosses, quests, zones and mobs, items). The search itself is UI.Search
-- (UI/SearchPage.lua), the same in every look.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local PQ = LJ.PaneQuests
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Quests = LJ.Quests
local C = Theme.COLORS

local Page = {}
local MAX_ITEMS = 100     -- items listed for one search
local NOTHING_FOUND = "Try the name of a dungeon, boss, quest, zone, mob or item. Parts of words work too, e.g. \"vanc\" or \"blade\"."

local SECTIONS = {
    { key = "ALL", text = "All results", glyph = "grid" },
    { key = "instance", text = "Dungeons & raids", glyph = "castle" },
    { key = "boss", text = "Bosses", glyph = "skull" },
    { key = "quest", text = "Quests", glyph = "scroll" },
    { key = "world", text = "Open world", glyph = "globe" },
    { key = "item", text = "Items", glyph = "package" },
}
local SECTION_LABEL = { instance = "Dungeons & raids", boss = "Bosses", quest = "Quests", world = "Zones & mobs", item = "Items" }

function Page:Create(root)
    local book = Kit.Book(root)
    self.book = book
    self.leftHeader = Kit.PaneHeader(book.left, "left")
    self.list = Kit.Sheet(book.left, 0)
    self.list.scroll:SetPoint("TOPLEFT", 0, -(self.leftHeader.height + 4))
    self.list.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
    self.header = Kit.PaneHeader(book.right, "right")
    self.sheet = Kit.Sheet(book.right, 0)
    self.sheet.scroll:SetPoint("TOPLEFT", 0, -(self.header.height + 4))
    self.sheet.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
end

local function OpenResult(d) UI:OpenSearchResult(d.result) end

function Page:Refresh()
    Theme.SetAccent(C.defaultAccent)
    local text = self.query or ""
    local results, itemTotal, tooShort = UI.Search(text, 400, MAX_ITEMS, true)
    local counts = { ALL = #results, instance = 0, boss = 0, quest = 0, world = 0, item = 0 }
    for _, r in ipairs(results) do counts[r.kind] = counts[r.kind] + 1 end
    itemTotal = math.max(itemTotal or 0, counts.item)
    local section = self.section or "ALL"
    if section ~= "ALL" and counts[section] == 0 then section = "ALL" end

    -- left: the kinds of results
    self.leftHeader:Set(L("Search"), L("Results"))
    local list = self.list
    list:Reset(276)
    for _, sec in ipairs(SECTIONS) do
        local n = (sec.key == "item" and itemTotal) or counts[sec.key] or 0
        list:Add("row", { text = L(sec.text), right = tostring(n), glyph = sec.glyph, glyphColor = C.text4, key = sec.key,
            selected = sec.key == section, dim = n == 0 and sec.key ~= "ALL", onClick = function(d)
                self.section = d.key
                self.sheet:ScrollToTop()
                self:Refresh()
            end })
    end
    list:Finish(8)

    -- right: the results
    local sub
    if tooShort then
        sub = #results > 0 and L("Dungeon shortcut · type at least 3 letters to search everything") or L("Type at least 3 letters")
    else
        sub = F("%s · %s · %s · %s", Util.Plural(counts.instance, "dungeon or raid", "dungeons & raids"),
            Util.Plural(counts.boss, "boss", "bosses"), Util.Plural(counts.quest, "quest"), Util.Plural(itemTotal, "item"))
    end
    self.header:Set(text ~= "" and F("\"%s\"", text) or L("Search"), sub)
    local sheet = self.sheet
    sheet:Reset(420)
    local lastKind
    local items = {}
    local function FlushItems()
        if #items > 0 then
            sheet:Grid("item", items, 1, Kit.M().item)
            items = {}
        end
    end
    for _, r in ipairs(results) do
        if section == "ALL" or r.kind == section then
            if r.kind ~= lastKind then
                FlushItems()
                lastKind = r.kind
                local label = L(SECTION_LABEL[r.kind])
                if r.kind == "item" and itemTotal > counts.item then
                    label = F("%s · %d of %d, type more to narrow it down", L(SECTION_LABEL.item), counts.item, itemTotal)
                end
                sheet:Add("section", { text = label, count = r.kind ~= "item" and counts[r.kind] or nil })
            end
            if r.kind == "item" then
                local source = Items.GetSourceText(r.itemID, 1)
                items[#items + 1] = { id = r.itemID, result = r, sub = source and source:gsub(" %- ", " · ") or L("Crafted, quest or other source"),
                    chance = Items.GetBestChance(r.itemID), upgrade = LJ.BiS.Upgrade(r.itemID), onClick = OpenResult }
            elseif r.kind == "quest" then
                local q = Quests.Get(r.questID)
                local status = Quests.GetStatus(q)
                local glyph, color = PQ.StatusGlyph(status)
                local subText = r.sub or ""
                if subText == "" then
                    local inst = q.inst and LJ.instanceByKey[q.inst[1]]
                    subText = inst and inst.name or ""
                end
                sheet:Add("row", { text = q.name, sub = subText, glyph = glyph, glyphColor = color, result = r, onClick = OpenResult })
            else
                local glyph, color = "castle", C.text4
                if r.kind == "boss" then
                    glyph = "skull"
                elseif r.kind == "world" then
                    glyph = r.npcID and "skull" or "globe"
                    color = r.rare and C.rare or C.text4
                end
                sheet:Add("row", { text = r.text, sub = r.sub, glyph = glyph, glyphColor = color, result = r, onClick = OpenResult })
            end
        end
    end
    FlushItems()
    if #results == 0 then
        if tooShort then
            sheet:Add("empty", { title = L("Type at least 3 letters"), text = L("Short words match hundreds of items, so the search starts at 3 letters. "
                .. "Dungeon shortcuts like \"dm\" or \"zf\" work right away."), glyph = "search" })
        else
            sheet:Add("empty", { title = L("Nothing found"), text = L(NOTHING_FOUND), glyph = "search" })
        end
    end
    sheet:Finish(10)
end

-- The results are made again whenever the page is shown: nothing of them is kept while it is hidden.
function Page:OnHide()
    if self.sheet then
        self.sheet:Clear()
        self.list:Clear()
    end
end

function Page:Show(text)
    local query = Util.Trim(text or self.query or "")
    if query ~= self.query then self.section = "ALL" end
    self.query = query
    if UI.frame and UI.frame.search and UI.frame.search:GetText() ~= self.query then
        UI.frame.search:SetText(self.query)
    end
    self.sheet:ScrollToTop()
    self:Refresh()
end

UI:RegisterPage("search", Page, Kit.LOOKS)
