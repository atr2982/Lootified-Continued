-- Lootified - search across every instance, boss, quest and item.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Quests = LJ.Quests
local C = Theme.COLORS

---------------------------------------------------------------------------
-- Search engine
---------------------------------------------------------------------------
local bossKeys = {}
local questKeys = {}

local function Matches(key, tokens)
    if not key then return false end
    for i = 1, #tokens do
        if not key:find(tokens[i], 1, true) then return false end
    end
    return true
end

-- Items the search knows: dungeon, raid and BiS items plus the open world drops (the database's Items page lists them).
local searchIDs
local function SearchItemIDs()
    if searchIDs then return searchIDs end
    local seen, list = {}, {}
    for _, id in ipairs(LJ.Scoring.GetAllCandidateIDs()) do
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    -- random world drops and the items the game's recipes make (Data/Crafted.lua)
    local more = {}
    for _, source in ipairs({ LJ.Data.WorldDrops or {}, LJ.Data.Crafted }) do
        for id in pairs(source) do
            if not seen[id] then
                seen[id] = true
                more[#more + 1] = id
            end
        end
    end
    table.sort(more)
    for _, id in ipairs(more) do list[#list + 1] = id end
    searchIDs = list
    return list
end

UI.SearchItemIDs = SearchItemIDs

-- rebuilt on the next search after the window was closed
LJ:Listen("WINDOW_CLOSED", function() searchIDs = nil end)

local function Tokenize(text)
    local tokens = {}
    for word in Util.SearchKey(text):gmatch("%S+") do
        tokens[#tokens + 1] = word
    end
    return tokens
end

-- A search starts at 3 letters (shorter words match hundreds of items). A dungeon shortcut like "dm" or "zf"
-- still finds its dungeon.
UI.SEARCH_MIN_LETTERS = 3

-- The items whose name has every word of the search (tokens), the best quality first, then by name; matched and
-- sorted without item records. filter(id) keeps an item (nil: every item).
local function MatchItems(tokens, filter)
    local hits, quality, names = {}, {}, {}
    for _, id in ipairs(SearchItemIDs()) do
        local key = Items.GetSearchKey(id)
        if Matches(key, tokens) and (not filter or filter(id)) then
            hits[#hits + 1] = id
            local _, q = Items.GetQuickInfo(id)
            quality[id], names[id] = q or 1, key
        end
    end
    table.sort(hits, function(a, b)
        if quality[a] ~= quality[b] then return quality[a] > quality[b] end
        return names[a] < names[b]
    end)
    return hits
end

-- The items of a list whose name, or name and source together (Core/BiS.lua: "blacksmithing", "scarlet monastery"),
-- have every word of a text, in the list's order (the pickers of a slot: any length, a short list, not every item; an
-- empty text keeps them all).
function UI.FilterItems(ids, text)
    local tokens = Tokenize(text)
    local out = {}
    for _, id in ipairs(ids) do
        local key = Items.GetSearchKey(id)
        if Matches(key, tokens) or Matches(key .. " " .. Util.SearchKey(LJ.BiS.SourceText(id)), tokens) then
            out[#out + 1] = id
        end
    end
    return out
end

-- The items a text finds, and true when it is too short to search (below SEARCH_MIN_LETTERS letters: no items);
-- filter(id) keeps an item.
function UI.SearchItems(text, filter)
    local tokens = Tokenize(text)
    if Util.LetterCount(tokens) < UI.SEARCH_MIN_LETTERS then return {}, true end
    return MatchItems(tokens, filter), false
end

-- Returns a list of results: { kind, text, sub, icon, iconCoords, atlas, instKey, bossIndex, itemID, questID },
-- the number of matching items (at most maxItems of them are in the list) and true when the text is too short
-- to search (then only a dungeon shortcut is looked up).
-- idsOnly: item results carry only their itemID (the search page builds the text of the rows it shows).
function UI.Search(text, limit, maxItems, idsOnly)
    local tokens = Tokenize(text)
    local results = {}
    local tooShort = Util.LetterCount(tokens) < UI.SEARCH_MIN_LETTERS
    if #tokens == 0 then return results, 0, tooShort end
    limit = limit or 500

    for _, inst in ipairs(LJ.Data.Instances) do
        local hit = not tooShort and Matches(inst.searchKey, tokens)
        if not hit then
            for _, alias in ipairs(inst.slash or {}) do
                if alias == tokens[1] and #tokens == 1 then hit = true break end
            end
        end
        if hit then
            results[#results + 1] = {
                kind = "instance", text = inst.name, instKey = inst.key, icon = Theme.GetInstanceIconPath(inst),
                sub = F("%s  ·  Level %s  ·  %s", inst.kind == "raid" and L("Raid") or L("Dungeon"),
                    Util.LevelRange(inst.minLevel, inst.maxLevel), Util.Plural(#inst.bosses, "boss", "bosses")),
            }
        end
    end

    if tooShort then return results, 0, true end

    for _, inst in ipairs(LJ.Data.Instances) do
        for i, boss in ipairs(inst.bosses) do
            local key = bossKeys[boss]
            if not key then
                key = Util.SearchKey(boss.name)
                bossKeys[boss] = key
            end
            if Matches(key, tokens) then
                results[#results + 1] = {
                    kind = "boss", text = boss.name, instKey = inst.key, bossIndex = i,
                    icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze",
                    sub = inst.name .. (#boss.loot > 0 and ("  ·  " .. Util.Plural(#boss.loot, "item")) or ""),
                }
            end
        end
    end

    -- quests listed on an instance page
    local questHits = {}
    for instKey, ids in pairs(LJ.Data.InstanceQuests or {}) do
        for _, qid in ipairs(ids) do
            local q = Quests.Get(qid)
            if q and not questHits[qid] then
                local key = questKeys[qid]
                if not key then
                    key = Util.SearchKey(q.name)
                    questKeys[qid] = key
                end
                if Matches(key, tokens) then
                    questHits[qid] = instKey
                end
            end
        end
    end
    local questList = {}
    for qid, instKey in pairs(questHits) do questList[#questList + 1] = { id = qid, inst = instKey } end
    table.sort(questList, function(a, b)
        local qa, qb = Quests.Get(a.id), Quests.Get(b.id)
        local ma, mb = Quests.IsForPlayer(qa), Quests.IsForPlayer(qb)
        if ma ~= mb then return ma end
        if (qa.level or 0) ~= (qb.level or 0) then return (qa.level or 0) < (qb.level or 0) end
        return qa.name < qb.name
    end)
    for _, e in ipairs(questList) do
        local q = Quests.Get(e.id)
        -- the dungeon the result opens (quests of several dungeons open their first one)
        local inst = LJ.instanceByKey[(q.inst and q.inst[1]) or e.inst] or LJ.instanceByKey[e.inst]
        results[#results + 1] = {
            kind = "quest", questID = e.id, text = q.name, atlas = "QuestNormal", icon = "Interface\\GossipFrame\\AvailableQuestIcon",
            iconCoords = { 0, 1, 0, 1 },
            sub = (inst and inst.name or "") .. (q.level and ("  ·  " .. F("Level %s", q.level)) or "") .. "  ·  " .. Quests.SideText(q.side),
        }
    end

    -- open world (the Open World page): zones, then the mobs of the zones in level order, rares first
    local zones = Items.GetWorldZones()
    for _, zone in ipairs(zones) do
        zone.searchKey = zone.searchKey or Util.SearchKey(zone.name)
        if Matches(zone.searchKey, tokens) then
            results[#results + 1] = {
                kind = "world", text = zone.name, map = zone.map,
                sub = F("%s  ·  Level %s  ·  %s", L("Zone"), Util.LevelRange(zone.minLevel, zone.maxLevel),
                    Util.Plural(#zone.mobs, "mob")),
            }
        end
    end
    for _, zone in ipairs(zones) do
        for _, mob in ipairs(zone.mobs) do
            mob.searchKey = mob.searchKey or Util.SearchKey(mob.name)
            if Matches(mob.searchKey, tokens) then
                results[#results + 1] = {
                    kind = "world", text = mob.name, map = zone.map, npcID = mob.id, rare = mob.isRare,
                    sub = F("%s  ·  Level %s  ·  %s", zone.name, Util.LevelRange(mob.minLevel, mob.maxLevel),
                        Util.Plural(#(Items.GetMobDrops(mob.id) or {}), "drop")),
                }
            end
        end
    end

    -- items: names and qualities are matched and sorted without item records; only the shown hits get one
    local hits = MatchItems(tokens)
    local shown = 0
    for _, id in ipairs(hits) do
        if #results >= limit or shown >= (maxItems or limit) then break end
        if idsOnly then
            results[#results + 1] = { kind = "item", itemID = id }
        else
            local rec = Items.Peek(id)
            results[#results + 1] = {
                kind = "item", itemID = id, text = Theme.ItemName(id),
                icon = rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                sub = Items.GetSourceText(id, 1, true) or L("Crafted, quest or other source"),
            }
        end
        shown = shown + 1
    end
    return results, #hits, false
end

function UI:OpenSearchResult(r)
    if r.kind == "instance" then
        UI:Open("instance", r.instKey)
    elseif r.kind == "boss" then
        UI:Open("instance", r.instKey, r.bossIndex)
    elseif r.kind == "quest" then
        UI:Open("quest", r.questID)
    elseif r.kind == "world" then
        UI:Open("world", r.map, r.npcID)
    elseif r.kind == "item" then
        local sources = Items.GetSources(r.itemID)
        if Items.HasWorldDrop(r.itemID) or Items.GetWorldQuestSources(r.itemID) then
            -- open world drops and quest rewards get their own page: mobs, chances, spawn points, quest givers
            UI:Open("item", r.itemID)
        elseif sources and sources[1] then
            UI:Open("instance", sources[1].inst, sources[1].boss)
        else
            local qids = Quests.rewardOf[r.itemID]
            if qids and qids[1] then
                UI:Open("quest", qids[1])
            else
                UI:Open("search", Items.GetName(r.itemID))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local Page = {}
local SIDEBAR = 244
local HEADER_HEIGHT = 96
local ENTRY_HEIGHT = 44
local LABEL_HEIGHT = 30
local MAX_ITEMS = 100     -- items listed for one search
local NOTHING_FOUND = "Try the name of a dungeon, boss, quest, zone, mob or item. Parts of words work too, e.g. \"vanc\" or \"blade\"."
-- Only the rows in view (plus this margin above and below) exist: a search with hundreds of results builds the
-- same few rows, which are filled again while scrolling.
local BUFFER = 120

local SECTIONS = {
    { key = "ALL", text = "All results", glyph = "grid" },
    { key = "instance", text = "Dungeons & raids", glyph = "castle" },
    { key = "boss", text = "Bosses", glyph = "skull" },
    { key = "quest", text = "Quests", glyph = "scroll" },
    { key = "world", text = "Open world", glyph = "globe" },
    { key = "item", text = "Items", glyph = "package" },
}
local SECTION_LABEL = { instance = "Dungeons & raids", boss = "Bosses", quest = "Quests", world = "Zones & mobs",
    item = "Items" }

local function CategoryVisual(row)
    local a = Theme.accent
    if row.selected then
        row.hl:SetGradient("HORIZONTAL", { a[1], a[2], a[3], 0.24 }, { a[1], a[2], a[3], 0 })
        row.icon:SetVertexColor(a[1], a[2], a[3], 1)
        Widgets.SetTextColor(row.text, C.white)
    else
        local hover = Widgets.Hover(row)
        row.hl:SetColor(1, 1, 1, hover and 0.045 or 0)
        row.icon:SetVertexColor(C.text4[1], C.text4[2], C.text4[3], 1)
        Widgets.SetTextColor(row.text, hover and C.white or Theme.ListNameColor())
    end
end

function Page:Create(root)
    local side = Widgets.CreateSidebar(root, SIDEBAR)
    self.side = side
    local label = Widgets.CreateGroupHeader(side)
    label:EnableMouse(false)
    label.caret:Hide()
    label.text:ClearAllPoints()
    label.text:SetPoint("LEFT", 10, -2)
    label:SetPoint("TOPLEFT", 4, -10)
    label:SetPoint("RIGHT", -4, 0)
    label:Set(L("Results"), nil, false)
    self.categories = {}
    for i, sec in ipairs(SECTIONS) do
        local row = CreateFrame("Button", nil, side)
        row:SetHeight(34)
        row:SetPoint("TOPLEFT", 6, -38 - (i - 1) * 36)
        row:SetPoint("RIGHT", -7, 0)
        row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 8)
        row.icon = Widgets.Glyph(row, sec.glyph, 14, C.text4)
        row.icon:SetPoint("LEFT", 12, 0)
        row.text = Widgets.Text(row, "item", C.text1)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.text:SetText(L(sec.text))
        row.count = Widgets.CreatePill(row, 18, "count")
        row.count:SetPoint("RIGHT", -8, 0)
        row.key = sec.key
        row:SetScript("OnClick", function(btn)
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            self.section = btn.key
            self.scroll:ScrollToTop()
            self:Refresh()
        end)
        row:SetScript("OnEnter", function(btn) btn.hovered = true CategoryVisual(btn) end)
        row:SetScript("OnLeave", function(btn) btn.hovered = false CategoryVisual(btn) end)
        Theme.OnAccent(row, function(r) CategoryVisual(r) end)
        self.categories[#self.categories + 1] = row
    end
    self.me = Widgets.CreateCharacterChip(side, function(b) UI:ShowOptions(b) end)
    self.me:SetPoint("BOTTOMLEFT")
    self.me:SetPoint("BOTTOMRIGHT", -1, 0)

    local main = CreateFrame("Frame", nil, root)
    main:SetPoint("TOPLEFT", SIDEBAR, 0)
    main:SetPoint("BOTTOMRIGHT")
    self.main = main
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header.glow = header:CreateTexture(nil, "BACKGROUND", nil, -3)
    header.glow:SetTexture(Theme.TEX.glow)
    header.glow:SetSize(520, 260)
    header.glow:SetPoint("CENTER", header, "BOTTOMLEFT", 110, -20)
    Theme.OnAccent(header, function(h, r, g, b) h.glow:SetVertexColor(r, g, b, 0.3) end)
    header.pill = Widgets.CreatePill(header, 20)
    header.pill:SetPoint("TOPLEFT", 22, -16)
    header.title = Widgets.Text(header, "heroSmall", C.white)
    header.title:SetPoint("TOPLEFT", 22, -42)
    header.title:SetPoint("RIGHT", -22, 0)
    header.sub = Widgets.Text(header, "bodySemi", C.text2)
    header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -5)
    header.line = Widgets.Line(header, "BORDER", 0.06)
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    self.header = header
    self.title = header.title

    self.scroll = Widgets.CreateScrollArea(main, -8)
    self.scroll:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT + 6))
    self.scroll:SetPoint("BOTTOMRIGHT", -16, 0)
    -- row pools per kind; a row with a layoutIndex shows that entry of the layout
    self.pools = { label = {}, entry = {}, quest = {}, item = {} }
    self.itemRows = self.pools.item
    self.entryRows = self.pools.entry
    self.questRows = self.pools.quest
    self.labels = self.pools.label
    -- the layout of the current results (parallel lists, reused): kind, top offset, result or label text
    self.layoutKind, self.layoutY, self.layoutData = {}, {}, {}
    self.layoutCount = 0
    self.bound = {}         -- [layout index] = row showing it
    self.scroll.onScroll = function() if not self.refreshing then self:BindVisible(false) end end

    self.empty = Widgets.CreateEmptyState(main, "search", 380)
    self.empty:SetPoint("TOP", self.scroll, "TOP", 0, -70)
    self.empty:Set(L("Nothing found"), L(NOTHING_FOUND))
    self.empty:Hide()
end

function Page:CreateLabel()
    return Widgets.CreateSectionLabel(self.scroll.content)
end

local function EntryVisual(b)
    b.hl:SetColor(1, 1, 1, Widgets.Hover(b) and 0.05 or 0)
end

function Page:CreateEntryRow()
    local b = CreateFrame("Button", nil, self.scroll.content)
    b:SetHeight(ENTRY_HEIGHT)
    b.hl = Widgets.CreateLazyBox(b, "BACKGROUND", 1, 8)
    b.emblem = Widgets.CreateEmblem(b, 32)
    b.emblem:SetPoint("LEFT", 6, 0)
    b.text = Widgets.Text(b, "h3", C.text1)
    b.text:SetPoint("TOPLEFT", b.emblem, "TOPRIGHT", 10, 0)
    b.text:SetPoint("RIGHT", -10, 0)
    b.sub = Widgets.Text(b, "small", C.text3)
    b.sub:SetPoint("BOTTOMLEFT", b.emblem, "BOTTOMRIGHT", 10, 0)
    b.sub:SetPoint("RIGHT", -10, 0)
    b.globe = Widgets.Glyph(b.emblem, "globe", 16, C.gold, "OVERLAY", 2)
    b.globe:SetPoint("CENTER")
    b.globe:Hide()
    b:SetScript("OnClick", function(btn) if btn.result then UI:OpenSearchResult(btn.result) end end)
    b:SetScript("OnEnter", function(btn) btn.hovered = true EntryVisual(btn) end)
    b:SetScript("OnLeave", function(btn) btn.hovered = false EntryVisual(btn) end)
    return b
end

function Page:CreateQuestRow()
    local row = CreateFrame("Button", nil, self.scroll.content)
    row:SetHeight(ENTRY_HEIGHT)
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 8)
    row.icon = CreateFrame("Frame", nil, row)
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon.bg = row.icon:CreateTexture(nil, "ARTWORK")
    row.icon.bg:SetTexture(Theme.TEX.circle)
    row.icon.bg:SetAllPoints()
    row.icon.ring = row.icon:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon.ring:SetTexture(Theme.TEX.circleRingThin)
    row.icon.ring:SetAllPoints()
    row.icon.symbol = Widgets.Text(row.icon, "glyphText", C.gold, nil, "CENTER")
    row.icon.symbol:SetPoint("CENTER", 0, 0)
    row.icon.glyph = Widgets.Glyph(row.icon, "check", 14, C.text4, "ARTWORK", 2)
    row.icon.glyph:SetPoint("CENTER")
    row.pill = Widgets.CreatePill(row, 18)
    row.pill:SetPoint("RIGHT", -10, 0)
    row.name = Widgets.Text(row, "h3", C.text1)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 0)
    row.name:SetPoint("RIGHT", row.pill, "LEFT", -8, 0)
    row.sub = Widgets.Text(row, "small", C.text3)
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 12, 0)
    row.sub:SetPoint("RIGHT", row.pill, "LEFT", -8, 0)
    row:SetScript("OnClick", function(btn) if btn.result then UI:OpenSearchResult(btn.result) end end)
    row:SetScript("OnEnter", function(btn) btn.hovered = true EntryVisual(btn) end)
    row:SetScript("OnLeave", function(btn) btn.hovered = false EntryVisual(btn) end)
    return row
end

local function OpenResult(btn)
    if btn.result then UI:OpenSearchResult(btn.result) end
end

function Page:CreateItemRow()
    local row = Widgets.CreateItemRow(self.scroll.content)
    row.onClick = OpenResult
    return row
end

local CREATE = { label = Page.CreateLabel, entry = Page.CreateEntryRow, quest = Page.CreateQuestRow, item = Page.CreateItemRow }
-- height of a result row by its kind
local function Height(kind)
    if kind == "item" then return Widgets.ItemRowHeight() end
    return kind == "label" and LABEL_HEIGHT or ENTRY_HEIGHT
end

-- A free row of a kind (hidden, showing no entry), created when every row of the kind is in use.
function Page:AcquireRow(kind)
    local pool = self.pools[kind]
    for _, row in ipairs(pool) do
        if not row.layoutIndex then return row end
    end
    local row = CREATE[kind](self)
    pool[#pool + 1] = row
    return row
end

function Page:ReleaseRow(row)
    self.bound[row.layoutIndex] = nil
    row.layoutIndex = nil
    row.result = nil
    row.itemID = nil
    row:Hide()
end

-- Fills a row with entry i of the layout and puts it at its place in the list.
function Page:BindRow(row, i)
    local kind, y, data = self.layoutKind[i], self.layoutY[i], self.layoutData[i]
    local width = self.rowWidth
    row.layoutIndex = i
    self.bound[i] = row
    row:ClearAllPoints()
    if kind == "label" then
        row:SetPoint("TOPLEFT", 4, -y)
        row:SetWidth(width - 8)
        row:SetLabel(data)
        row:Show()
        return
    end
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetWidth(width - 4)
    local r = data
    row.result = r
    if kind == "item" then
        local source = Items.GetSourceText(r.itemID, 1)
        row:SetItem(r.itemID, { right = source and source:gsub(" %- ", " · ") or L("Crafted, quest or other source"),
            chance = Items.GetBestChance(r.itemID), noChance = not self.anyChance, upgrade = LJ.BiS.Upgrade(r.itemID) })
    elseif kind == "quest" then
        local q = Quests.Get(r.questID)
        local status, detail = Quests.GetStatus(q)
        LJ.PaneQuests.SetStatusIcon(row.icon, status)
        local st = Theme.QUEST_STATUS[status]
        local label = st.label
        if status == Quests.LOW_LEVEL then label = F(label, detail or 1) end
        row.pill:Set(label, st.pill)
        row.name:SetText(q.name)
        row.sub:SetText(r.sub or "")
        EntryVisual(row)
    else
        row.text:SetText(r.text)
        row.sub:SetText(r.sub or "")
        local inst = LJ.instanceByKey[r.instKey]
        row.globe:Hide()
        if r.kind == "world" then
            -- a mob: its emblem; a zone: the globe
            row.emblem:SetRare(r.rare)
            row.emblem:SetGlyph(Theme.BossEmblem({ name = r.text }))
            if not r.npcID then
                row.emblem.glyph:Hide()
                row.globe:Show()
            end
        elseif r.kind == "boss" and inst then
            row.emblem:SetBoss(inst.bosses[r.bossIndex])
        elseif inst then
            row.emblem:SetRare(false)
            row.emblem.glyph:Hide()
            row.emblem.portrait:Show()
            Theme.SetInstanceIcon(row.emblem.portrait, inst)
        end
        EntryVisual(row)
    end
    row:Show()
end

-- Shows the entries in view: rows that scrolled out are freed, entries that scrolled in get a free row.
-- force: fill every row again (new results).
function Page:BindVisible(force)
    local n = self.layoutCount
    local offset = self.scroll:GetVerticalScroll() or 0
    local top = offset - BUFFER
    local bottom = offset + (self.scroll:GetHeight() or 0) + BUFFER
    local ys, kinds = self.layoutY, self.layoutKind
    for kind, pool in pairs(self.pools) do
        for _, row in ipairs(pool) do
            local i = row.layoutIndex
            if i and (force or i > n or ys[i] + Height(kind) < top or ys[i] > bottom) then
                self:ReleaseRow(row)
            elseif not i and row:IsShown() then
                row:Hide()
            end
        end
    end
    -- first entry that reaches into the window (entries are sorted by their offset)
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if ys[mid] + Height(kinds[mid]) < top then lo = mid + 1 else hi = mid end
    end
    for i = lo, n do
        if ys[i] > bottom then break end
        if not self.bound[i] then self:BindRow(self:AcquireRow(kinds[i]), i) end
    end
end

function Page:Refresh()
    Theme.SetAccent(Theme.COLORS.defaultAccent)
    local text = self.query or ""
    -- items are capped (a longer list helps nobody: type more to narrow it down)
    local results, itemTotal, tooShort = UI.Search(text, 400, MAX_ITEMS, true)
    local counts = { ALL = #results, instance = 0, boss = 0, quest = 0, world = 0, item = 0 }
    for _, r in ipairs(results) do counts[r.kind] = counts[r.kind] + 1 end
    itemTotal = math.max(itemTotal or 0, counts.item)
    local section = self.section or "ALL"
    if section ~= "ALL" and counts[section] == 0 then section = "ALL" end
    for _, row in ipairs(self.categories) do
        row.selected = row.key == section
        row.count:Set(tostring((row.key == "item" and itemTotal) or counts[row.key] or 0), row.selected and "solid" or "dark")
        CategoryVisual(row)
    end
    self.header.pill:Set("SEARCH", "acc", "search")
    self.title:SetText(text ~= "" and F("\"%s\"", text) or L("Search"))
    if tooShort then
        self.header.sub:SetText(#results > 0 and L("Dungeon shortcut · type at least 3 letters to search everything")
            or L("Type at least 3 letters"))
        self.empty:Set(L("Type at least 3 letters"), L("Short words match hundreds of items, so the search starts at 3 letters. "
            .. "Dungeon shortcuts like \"dm\" or \"zf\" work right away."))
    else
        self.header.sub:SetText(F("%s · %s · %s · %s", Util.Plural(counts.instance, "dungeon or raid", "dungeons & raids"),
            Util.Plural(counts.boss, "boss", "bosses"), Util.Plural(counts.quest, "quest"), Util.Plural(itemTotal, "item"))
            .. (counts.world > 0 and (" · " .. Util.Plural(counts.world, "zone or mob", "zones & mobs")) or ""))
        self.empty:Set(L("Nothing found"), L(NOTHING_FOUND))
    end
    self.empty:SetShown(#results == 0)

    local width = self.scroll:GetWidth()
    if not width or width < 100 then width = 704 end
    self.rowWidth = width
    local anyChance = false
    for _, r in ipairs(results) do
        if r.kind == "item" and (section == "ALL" or section == "item") then
            local chance = Items.GetBestChance(r.itemID)
            if chance and chance > 0 then anyChance = true break end
        end
    end
    self.anyChance = anyChance
    -- layout: a label per kind, then its entries
    local kinds, ys, datas = self.layoutKind, self.layoutY, self.layoutData
    local n, y = 0, 0
    local lastKind
    for _, r in ipairs(results) do
        if section == "ALL" or r.kind == section then
            if r.kind ~= lastKind then
                if lastKind then y = y + 8 end
                lastKind = r.kind
                n = n + 1
                kinds[n], ys[n] = "label", y + 8
                if r.kind == "item" and itemTotal > counts.item then
                    datas[n] = F("%s · %d of %d, type more to narrow it down", L(SECTION_LABEL.item), counts.item, itemTotal)
                else
                    datas[n] = string.format("%s · %d", L(SECTION_LABEL[r.kind]), counts[r.kind])
                end
                y = y + LABEL_HEIGHT
            end
            n = n + 1
            local kind = (r.kind == "item" and "item") or (r.kind == "quest" and "quest") or "entry"
            kinds[n], ys[n], datas[n] = kind, y, r
            y = y + Height(kind)
        end
    end
    for i = n + 1, #kinds do kinds[i], ys[i], datas[i] = nil, nil, nil end
    self.layoutCount = n
    self.refreshing = true
    self.scroll:SetContentHeight(y + 10)
    self.refreshing = false
    self:BindVisible(true)
    self.me:Update()
end

-- The results are made again whenever the page is shown: nothing of them is kept while it is hidden.
function Page:OnHide()
    for _, pool in pairs(self.pools) do
        for _, row in ipairs(pool) do
            if row.layoutIndex then self:ReleaseRow(row) end
        end
    end
    local kinds, ys, datas = self.layoutKind, self.layoutY, self.layoutData
    for i = #kinds, 1, -1 do kinds[i], ys[i], datas[i] = nil, nil, nil end
    self.layoutCount = 0
end

function Page:Show(text)
    local query = Util.Trim(text or self.query or "")
    if query ~= self.query then self.section = "ALL" end
    self.query = query
    if UI.frame and UI.frame.search and UI.frame.search:GetText() ~= self.query then
        UI.frame.search:SetText(self.query)
    end
    self.scroll:ScrollToTop()
    self:Refresh()
end

UI:RegisterPage("search", Page)
