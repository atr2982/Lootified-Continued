-- Lootified - an item in the classic look: the item on the left (icon, name, slot, wishlist, try on),
-- where it comes from on the right: the open world mobs (rares too) with drop chance, level, zone and a map button for
-- their camps, random world drops, dungeon bosses and quests (open world quests with their quest giver on the map).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Quests = LJ.Quests
local C = Theme.COLORS

local Page = {}

function Page:Create(root)
    local book = Kit.Book(root)
    self.book = book
    local left = book.left
    self.leftHeader = Kit.PaneHeader(left, "left")
    local top = self.leftHeader.height + 18
    self.icon = Widgets.CreateItemIcon(left, 56)
    self.icon:SetPoint("TOPLEFT", 6, -top)
    self.icon:SetScript("OnEnter", function(b)
        if self.itemID then Widgets.ShowItemTooltip(b, self.itemID) end
    end)
    self.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.icon:SetScript("OnClick", function(_, button)
        if self.itemID then Items.HandleClick(self.itemID, button) end
    end)
    self.name = Widgets.Text(left, "titleSmall", C.white)
    self.name:SetPoint("TOPLEFT", self.icon, "TOPRIGHT", 12, -2)
    self.name:SetPoint("RIGHT", -6, 0)
    self.name:SetWordWrap(true)
    self.name:SetMaxLines(2)
    self.slot = Widgets.Text(left, "small", C.text3)
    self.slot:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -5)
    self.slot:SetPoint("RIGHT", -6, 0)
    self.slot:SetWordWrap(true)
    local width = 220
    self.wish = Widgets.CreateButton(left, "Add to Wishlist", "ghost", "star", width, 26)
    self.wish:SetPoint("TOPLEFT", self.icon, "BOTTOMLEFT", 0, -22)
    self.wish:SetScript("OnClick", function() if self.itemID then Items.ToggleWishlist(self.itemID) end end)
    self.tryOn = Widgets.CreateButton(left, "Try on", "ghost", "shirt", width, 26)
    self.tryOn:SetPoint("TOPLEFT", self.wish, "BOTTOMLEFT", 0, -8)
    self.tryOn:SetScript("OnClick", function()
        if self.itemID then DressUpItemLink(Items.GetLink(self.itemID)) end
    end)
    Widgets.SetTryOn(self.tryOn, true)
    self.back = Widgets.CreateButton(left, "Back to search", "ghost", "caretLeft", width, 26)
    self.back:SetPoint("TOPLEFT", self.tryOn, "BOTTOMLEFT", 0, -8)
    self.back:SetScript("OnClick", function()
        local search = UI.pages.search
        UI:Open("search", search and search.query or "")
    end)

    self.header = Kit.PaneHeader(book.right, "right")
    self.sheet = Kit.Sheet(book.right, 0)
    self.sheet.scroll:SetPoint("TOPLEFT", 0, -(self.header.height + 4))
    self.sheet.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
end

local function MobEnter(f, d)
    local mob = d.mob
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:SetText(mob.name, 1, 0.82, 0)
    GameTooltip:AddLine(F("Level %s%s", Util.LevelRange(mob.minLevel, mob.maxLevel), mob.rankText and (" " .. L(mob.rankText)) or ""), 1, 1, 1)
    if mob.isRare then GameTooltip:AddLine(L("Rare spawn: it is not always up, check its camps."), 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(F("%s in the Classic data.", Util.Plural(mob.spawns, "spawn point")), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function Page:Refresh()
    local itemID = self.itemID
    if not itemID then return end
    Theme.SetAccent(C.defaultAccent)
    local rec = Items.Get(itemID)
    local itemName = rec.name or rec.fallbackName or F("Item #%d", itemID)
    local mobs, random = Items.GetWorldSources(itemID)
    mobs = mobs or {}
    local sources = Items.GetSources(itemID) or {}
    local rewardOf = Quests and Quests.rewardOf and Quests.rewardOf[itemID] or {}
    local worldQuests = Items.GetWorldQuestSources(itemID) or {}

    -- left: the item
    self.leftHeader:Set(L("Item"), "")
    self.icon:SetItem(itemID)
    self.icon:SetOwned(Items.IsOwned(itemID))
    local r, g, b = Util.QualityColor(rec.quality or 1)
    self.name:SetText(itemName)
    self.name:SetTextColor(r, g, b)
    local level = rec.minLevel and rec.minLevel > 1 and rec.minLevel
    local slot = Items.GetSlotText(itemID) or ""
    if level then slot = slot .. (slot ~= "" and "  ·  " or "") .. F("Requires level %d", level) end
    self.slot:SetText(slot)
    local wished = Items.IsWishlisted(itemID)
    self.wish:SetLabel(wished and "On your Wishlist" or "Add to Wishlist")
    self.wish:SetGlyph(wished and "check" or "star")
    -- the Wishlist module off: no wishlist button, Try on moves up
    local wishOn = LJ.Modules.On("wishlist")
    self.wish:SetShown(wishOn)
    self.tryOn:ClearAllPoints()
    if wishOn then
        self.tryOn:SetPoint("TOPLEFT", self.wish, "BOTTOMLEFT", 0, -8)
    else
        self.tryOn:SetPoint("TOPLEFT", self.icon, "BOTTOMLEFT", 0, -22)
    end
    local search = UI.pages.search
    self.back:SetShown(search and search.query and search.query ~= "" and true or false)

    -- right: where it comes from
    local parts = {}
    if #mobs > 0 then parts[#parts + 1] = #mobs == 1 and L("1 mob drops it") or F("%d mobs drop it", #mobs) end
    if random then parts[#parts + 1] = F("random drop from mobs level %s", Util.LevelRange(random.minLevel, random.maxLevel)) end
    if #sources > 0 then parts[#parts + 1] = Util.Plural(#sources, "dungeon source") end
    if #rewardOf + #worldQuests > 0 then parts[#parts + 1] = F("reward of %s", Util.Plural(#rewardOf + #worldQuests, "quest")) end
    self.header:Set(L("Where it comes from"), #parts > 0 and table.concat(parts, "  ·  ") or L("No known drop source"))
    local sheet = self.sheet
    sheet:Reset(420)
    if #mobs > 0 then
        sheet:Add("section", { text = L("Drops from"), count = #mobs })
        for _, s in ipairs(mobs) do
            local mob = s.mob
            local zone = Items.GetMobZone(mob)
            local sub = F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel))
            if zone then sub = sub .. "  ·  " .. zone end
            if #mob.locs > 1 then sub = sub .. "  ·  " .. F("%d camps", #mob.locs) end
            local chance = Util.FormatChance(s.chance)
            if chance then sub = sub .. "  ·  " .. Theme.ColorText(chance, C.text1) end
            sheet:Add("mob", { text = mob.name, tag = mob.rankText and Util.Upper(L(mob.rankText)) or nil, tagKind = mob.isRare and "rare" or "neutral",
                sub = sub, mob = mob, itemName = itemName, onEnter = MobEnter })
        end
    end
    if random then
        sheet:Add("section", { text = L("Random world drop") })
        sheet:Add("text", { text = F("Can drop from almost any mob around level %s in the open world (%d mobs in the Classic data). "
            .. "The chance per kill is very low, so there is no single mob to farm.",
            Util.LevelRange(random.minLevel, random.maxLevel), random.mobs or 0), font = "body", color = C.text2, spacing = 3 })
    end
    if #sources > 0 then
        sheet:Add("section", { text = L("Dungeons & raids"), count = #sources })
        for _, s in ipairs(sources) do
            local inst = LJ.instanceByKey[s.inst]
            if inst then
                local boss = s.boss > 0 and inst.bosses[s.boss] or nil
                local chance = Util.FormatChance(s.chance)
                sheet:Add("row", { text = boss and boss.name or L("Trash mobs"), sub = F("%s  ·  Level %s", inst.name, Util.LevelRange(inst.minLevel, inst.maxLevel)),
                    right = chance and Theme.ColorText(chance, C.text1) or nil,
                    glyph = boss and "skull" or "bag", glyphColor = C.text4, inst = inst.key, boss = s.boss,
                    onClick = function(d) UI:Open("instance", d.inst, d.boss) end })
            end
        end
    end
    if #rewardOf + #worldQuests > 0 then
        sheet:Add("section", { text = L("Quest reward"), count = #rewardOf + #worldQuests })
        for _, qid in ipairs(rewardOf) do
            local q = Quests.Get(qid)
            if q then
                local status = Quests.GetStatus(q)
                local glyph, color = LJ.PaneQuests.StatusGlyph(status)
                sheet:Add("row", { text = q.name, sub = (q.level and (F("Level %s", q.level) .. "  ·  ") or "") .. Quests.SideText(q.side),
                    glyph = glyph, glyphColor = color, onClick = function() UI:Open("quest", qid) end })
            end
        end
        -- open world quests: the giver's spot as a "where" line with its map button
        for _, q in ipairs(worldQuests) do
            local spot
            if q.loc then
                LJ.MapPin.Resolve(q.loc)
                if q.loc.map and q.loc.x and q.loc.y then
                    spot = { map = q.loc.map, x = q.loc.x, y = q.loc.y, title = q.giver, detail = F("Quest: %s", q.name) }
                end
            end
            local zone = Items.GetQuestZone(q)
            local line = F("Level %d  ·  %s  ·  %s%s", q.level or 0, Quests.SideText(q.side), q.giver or "", zone and ("  ·  " .. zone) or "")
            if q.classes then
                local names = {}
                for _, c in ipairs(q.classes) do names[#names + 1] = Util.ClassName(c:upper()) end
                line = line .. "  ·  " .. table.concat(names, ", ")
            end
            sheet:Add("where", { label = Quests.IsForPlayer(q) and "QUEST" or "OTHER", glyph = "scroll", name = q.name, zone = line, spot = spot })
        end
    end
    if #mobs == 0 and not random and #sources == 0 and #rewardOf + #worldQuests == 0 then
        sheet:Add("empty", { title = L("No drop source known"), text = L("This item is not in the loot data. It may be crafted, sold by a vendor or come from a source that is new in Forever."), glyph = "info" })
    end
    if #mobs > 0 or random then
        sheet:Space(8)
        sheet:Add("text", { text = L("Open world drop chances and spawn points are the Classic values and can differ in WoW: Forever."),
            font = "small", color = C.text4 })
    end
    sheet:Finish(10)
end

function Page:Show(itemID)
    if itemID and itemID ~= self.itemID then
        self.itemID = itemID
        self.sheet:ScrollToTop()
        -- ask the client for the item so the name, quality and slot are the live ones
        Items.WhenLoaded(itemID, function()
            if self.itemID == itemID and self.root and self.root:IsVisible() then self:Refresh() end
        end)
    end
    self:Refresh()
end

-- The map buttons show which camp is marked: redraw when the mark changes.
LJ:Listen("MAP_TARGET_CHANGED", function()
    if Page.root and Page.root:IsVisible() and Page.itemID then Page:Refresh() end
end)

UI:RegisterPage("item", Page, Kit.LOOKS)
