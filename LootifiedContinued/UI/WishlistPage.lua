-- Lootified - wishlist: every starred item grouped by where it drops, and "Where to go" (sidebar): the
-- instances to run, busiest first.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Quests = LJ.Quests
local Lists = LJ.Lists
local C = Theme.COLORS

local Page = {}

local SIDEBAR = 244
local HEADER_HEIGHT = 96
local GROUP_HEIGHT = 34
local PLAN_ROW = 44

function Page:Create(root)
    -- sidebar: where to go
    local side = Widgets.CreateSidebar(root, SIDEBAR)
    self.side = side
    self.planLabel = Widgets.CreateGroupHeader(side)
    self.planLabel:EnableMouse(false)
    self.planLabel.caret:Hide()
    self.planLabel.text:ClearAllPoints()
    self.planLabel.text:SetPoint("LEFT", 10, -2)
    self.planLabel:SetPoint("TOPLEFT", 4, -10)
    self.planLabel:SetPoint("RIGHT", -4, 0)
    self.planScroll = Widgets.CreateScrollArea(side, -6)
    self.planScroll:SetPoint("TOPLEFT", 0, -38)
    self.planScroll:SetPoint("BOTTOMRIGHT", 0, 130)
    self.planRows = {}
    self.clear = Widgets.CreateButton(side, "Clear wishlist", "ghost", "close", nil, 26)
    self.clear:SetPoint("BOTTOM", side, "BOTTOM", 0, 58)
    self.clear:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            LJ:Print("Hold Shift and click again to clear your whole wishlist.")
            return
        end
        wipe(LJ.cdb.wishlist)
        LJ:Fire("WISHLIST_CHANGED")
        LJ:Print("Wishlist cleared.")
    end)
    Widgets.SetTooltip(self.clear, "Clear wishlist", "Shift-click to remove every item.", "ANCHOR_TOP")
    self.planNote = Widgets.Text(side, "small", C.text4, nil, "CENTER")
    self.planNote:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 14, 92)
    self.planNote:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -14, 92)
    self.planNote:SetWordWrap(true)
    self.me = Widgets.CreateCharacterChip(side, function(b) UI:ShowOptions(b) end)
    self.me:SetPoint("BOTTOMLEFT")
    self.me:SetPoint("BOTTOMRIGHT", -1, 0)

    -- main: header + grouped item list
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
    header.title = Widgets.Text(header, "heroMid", C.white)
    header.title:SetPoint("TOPLEFT", 22, -40)
    header.title:SetText(Theme.Case(L("Wishlist")))
    header.sub = Widgets.Text(header, "bodySemi", C.text2)
    header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.line = Widgets.Line(header, "BORDER", 0.06)
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    self.header = header
    self.bisButton = Widgets.CreateButton(header, "Add my BiS", "ghost", "crown", nil, 28)
    self.bisButton:SetPoint("TOPRIGHT", -18, -18)
    self.bisButton:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        LJ.BiS.AddMyBiSToWishlist()
    end)
    Widgets.SetTooltip(self.bisButton, "Add my Best in Slot", "Adds the items of your Best in Slot sheet that you do not own yet.", "ANCHOR_BOTTOM")

    self.scroll = Widgets.CreateScrollArea(main, -8)
    self.scroll:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT + 10))
    self.scroll:SetPoint("BOTTOMRIGHT", -16, 0)
    self.rows = {}
    self.headers = {}

    self.empty = Widgets.CreateEmptyState(main, "star", 380)
    self.empty:SetPoint("TOP", self.scroll, "TOP", 0, -70)
    self:SetEmptyText()
    self.empty:Hide()
end

local function PlanRowVisual(row)
    row.hl:SetColor(1, 1, 1, Widgets.Hover(row) and 0.05 or 0)
end

function Page:GetPlanRow(i)
    local row = self.planRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, self.planScroll.content)
    row:SetHeight(PLAN_ROW)
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 8)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture(Theme.TEX.segment)
    row.bar:SetSize(3, 20)
    row.bar:SetPoint("LEFT", 4, 0)
    row.count = Widgets.CreatePill(row, 20, "count")
    row.count:SetPoint("RIGHT", -8, 0)
    row.name = Widgets.Text(row, "h3", C.text1)
    row.name:SetPoint("TOPLEFT", 14, -7)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.sub = Widgets.Text(row, "small", C.text3)
    row.sub:SetPoint("BOTTOMLEFT", 14, 7)
    row.sub:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row:SetScript("OnClick", function(btn)
        if btn.inst then
            UI:Open("instance", btn.inst.key, btn.firstBoss)
        elseif btn.itemID then
            UI:Open("item", btn.itemID)
        end
    end)
    row:SetScript("OnEnter", function(btn) btn.hovered = true PlanRowVisual(btn) end)
    row:SetScript("OnLeave", function(btn) btn.hovered = false PlanRowVisual(btn) end)
    self.planRows[i] = row
    return row
end

function Page:GetHeader(i)
    local h = self.headers[i]
    if h then return h end
    h = CreateFrame("Button", nil, self.scroll.content)
    h:SetHeight(GROUP_HEIGHT)
    h.bar = h:CreateTexture(nil, "ARTWORK")
    h.bar:SetTexture(Theme.TEX.segment)
    h.bar:SetSize(3, 16)
    h.bar:SetPoint("LEFT", 2, -2)
    h.name = Widgets.Text(h, "h2", C.white)
    h.name:SetPoint("LEFT", 12, -2)
    h.right = Widgets.Text(h, "tiny", C.text3, nil, "RIGHT")
    h.right:SetPoint("RIGHT", -6, -2)
    h.arrow = Widgets.Glyph(h, "arrowRight", 12, C.text4)
    h.arrow:SetPoint("LEFT", h.name, "RIGHT", 6, 0)
    h.arrow:SetAlpha(0)
    h:SetScript("OnClick", function(btn)
        if btn.inst then UI:Open("instance", btn.inst.key) end
    end)
    h:SetScript("OnEnter", function(btn) if btn.inst then btn.arrow:SetAlpha(1) end end)
    h:SetScript("OnLeave", function(btn) btn.arrow:SetAlpha(0) end)
    self.headers[i] = h
    return h
end

-- The empty wishlist: how to add items (and the drop alert while it is on in the options); "Add my Best in Slot"
-- with the Best in Slot module on.
function Page:SetEmptyText()
    local bis = LJ.Modules.On("bis")
    self.empty:Set(L("Your wishlist is empty"),
        L(LJ.db.wishlistAlerts and "Click the star on any item in the journal to track it here. You get an alert as soon as it drops."
            or "Click the star on any item in the journal to track it here."),
        nil, bis and "Add my Best in Slot" or nil, function()
            Util.PlaySound("IG_MAINMENU_OPTION")
            LJ.BiS.AddMyBiSToWishlist()
        end, "crown")
end

function Page:RefreshPlan(groups, order)
    local plan = Lists.WishlistPlan(groups, order)
    local width = self.planScroll:GetWidth()
    if not width or width < 50 then width = SIDEBAR end
    for i, p in ipairs(plan) do
        local row = self:GetPlanRow(i)
        row.inst = p.inst
        row.firstBoss = p.firstBoss
        row.itemID = p.itemID
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -(i - 1) * PLAN_ROW)
        row:SetWidth(width - 12)
        if p.inst then
            local a = Theme.InstanceAccent(p.inst)
            row.bar:SetVertexColor(a[1], a[2], a[3], 0.9)
            row.name:SetText(p.inst.name)
            row.sub:SetText(table.concat(p.bosses, ", "))
        else
            row.bar:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.9)
            row.name:SetText(p.mob.name .. (p.mob.rankText and (" (" .. L(p.mob.rankText) .. ")") or ""))
            row.sub:SetText(F("%s · Level %s", Items.GetMobZone(p.mob) or L("Open world"), Util.LevelRange(p.mob.minLevel, p.mob.maxLevel)))
        end
        row.count:Set(tostring(p.count), "acc")
        PlanRowVisual(row)
        row:Show()
    end
    for i = #plan + 1, #self.planRows do
        self.planRows[i]:Hide()
        self.planRows[i].inst = nil
        self.planRows[i].itemID = nil
    end
    self.planScroll:SetContentHeight(#plan * PLAN_ROW + 4)
    self.planLabel:Set(L("Where to go"), #plan, false)
    local note = "Click an entry to see where it drops."
    if #plan == 0 then
        -- starred items that no dungeon, boss or rare drops (quest rewards, crafted items)
        note = next(LJ.cdb.wishlist) and "None of these items drops from a dungeon, boss or rare."
            or "Star items to see which dungeons, bosses and rares to run."
    end
    self.planNote:SetText(L(note))
end

function Page:Refresh()
    Theme.SetAccent(Theme.COLORS.defaultAccent)
    local groups, order, count = Lists.WishlistGroups()

    self.header.pill:Set(Util.Plural(count, "ITEM", "ITEMS"), "acc", "star")
    self.header.sub:SetText(count == 0 and L("Nothing tracked yet")
        or F(LJ.db.wishlistAlerts and "From %d %s · you get an alert when one drops" or "From %d %s",
            #order, Util.PluralWord(#order, "source")))
    if count == 0 then self:SetEmptyText() end
    self.empty:SetShown(count == 0)
    self.clear:SetShown(count > 0)
    self.bisButton:SetShown(count > 0 and LJ.Modules.On("bis"))

    local width = self.scroll:GetWidth()
    if not width or width < 100 then width = 704 end
    local y, rowIndex = 0, 0
    for hi, key in ipairs(order) do
        local inst = LJ.instanceByKey[key]
        local h = self:GetHeader(hi)
        h.inst = inst
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(width - 4)
        if inst then
            local a = Theme.InstanceAccent(inst)
            h.bar:SetVertexColor(a[1], a[2], a[3], 1)
            h.name:SetText(inst.name)
            h.right:SetText(F("Level %s", (Util.LevelRange(inst.minLevel, inst.maxLevel):gsub("-", "–"))))
        elseif key == "_WORLD" then
            h.bar:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
            h.name:SetText(L("Open world"))
            h.right:SetText(L("Rares, mobs & quests"))
        else
            h.bar:SetVertexColor(C.text4[1], C.text4[2], C.text4[3], 1)
            h.name:SetText(L("Quest rewards, crafted & other sources"))
            h.right:SetText("")
        end
        h:Show()
        y = y + GROUP_HEIGHT
        local list = groups[key]
        local anyChance = false
        for _, entry in ipairs(list) do
            if entry.source and entry.source.chance and entry.source.chance > 0 then anyChance = true break end
        end
        for _, entry in ipairs(list) do
            rowIndex = rowIndex + 1
            local row = self.rows[rowIndex]
            if not row then
                row = Widgets.CreateItemRow(self.scroll.content)
                self.rows[rowIndex] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetWidth(width - 8)
            local opts = { upgrade = LJ.BiS.Upgrade(entry.id) }
            row.questID = nil
            row.worldItem = nil
            if entry.source and inst then
                opts.right = entry.source.boss == 0 and L("Trash") or (inst.bosses[entry.source.boss] and inst.bosses[entry.source.boss].name)
                opts.chance = entry.source.chance
                opts.noChance = not anyChance
            elseif key == "_WORLD" then
                -- "Vultros (Rare) · Westfall"; a click opens the item page with every mob and its map marker
                local text = Items.GetQuestSourceText(entry.id) or Items.GetWorldSourceText(entry.id)
                opts.right = text and text:gsub(" %- ", " · ")
                opts.chance = Items.GetBestChance(entry.id)
                opts.noChance = opts.chance == nil
                row.worldItem = entry.id
            else
                local qids = Quests.rewardOf[entry.id]
                if qids and qids[1] then
                    opts.right = Quests.GetName(qids[1])
                    opts.rightText = "QUEST"
                    opts.rightKind = "gold"
                    row.questID = qids[1]
                end
            end
            row.onClick = function(r)
                if r.worldItem then
                    UI:Open("item", r.worldItem)
                elseif r.questID then
                    UI:Open("quest", r.questID)
                end
            end
            row:SetItem(entry.id, opts)
            row:Show()
            y = y + Widgets.ItemRowHeight()
        end
        y = y + 8
    end
    for i = #order + 1, #self.headers do
        self.headers[i]:Hide()
        self.headers[i].inst = nil
    end
    for i = rowIndex + 1, #self.rows do
        self.rows[i]:Hide()
        self.rows[i].itemID = nil
    end
    self.scroll:SetContentHeight(y)
    self:RefreshPlan(groups, order)
    self.me:Update()
end

function Page:Show()
    self:Refresh()
end

UI:RegisterPage("wishlist", Page)
