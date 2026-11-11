-- Lootified - the wishlist in the classic look. Left: where to go (the dungeons, bosses and rares that
-- drop the starred items, busiest first), "Add my Best in Slot" and "Clear wishlist"; right: the items, grouped by where
-- they drop (all of them, or the picked source).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Quests = LJ.Quests
local Lists = LJ.Lists
local C = Theme.COLORS

local Page = {}

function Page:Create(root)
    local book = Kit.Book(root)
    self.book = book
    self.leftHeader = Kit.PaneHeader(book.left, "left")
    self.list = Kit.Sheet(book.left, 0)
    self.list.scroll:SetPoint("TOPLEFT", 0, -(self.leftHeader.height + 4))
    self.list.scroll:SetPoint("BOTTOMRIGHT", -10, 76)
    self.addBiS = Widgets.CreateButton(book.left, "Add my Best in Slot", "ghost", "crown", nil, 24)
    self.addBiS:SetPoint("BOTTOMLEFT", 2, 44)
    self.addBiS:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        LJ.BiS.AddMyBiSToWishlist()
    end)
    Widgets.SetTooltip(self.addBiS, "Add my Best in Slot", "Adds the items of your Best in Slot sheet that you do not own yet.", "ANCHOR_TOP")
    self.clear = Widgets.CreateButton(book.left, "Clear wishlist", "ghost", "close", nil, 24)
    self.clear:SetPoint("TOPLEFT", self.addBiS, "BOTTOMLEFT", 0, -8)
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

    self.header = Kit.PaneHeader(book.right, "right")
    self.sheet = Kit.Sheet(book.right, 0)
    self.sheet.scroll:SetPoint("TOPLEFT", 0, -(self.header.height + 4))
    self.sheet.scroll:SetPoint("BOTTOMRIGHT", -10, 4)
end

-- The name of a source group and its line (level range, where).
local function GroupTitle(key)
    local inst = LJ.instanceByKey[key]
    if inst then
        return inst.name, inst.kind == "raid" and L("Raid") or F("Level %s", Kit.RangeText(inst.minLevel, inst.maxLevel)), inst
    elseif key == "_WORLD" then
        return L("Open world"), L("Rares, mobs & quests")
    end
    return L("Quest rewards, crafted & other sources"), nil
end

function Page:Refresh()
    Theme.SetAccent(C.defaultAccent)
    local groups, order, count = Lists.WishlistGroups()
    local plan = Lists.WishlistPlan(groups, order)
    if self.pick and not groups[self.pick] then self.pick = nil end

    -- left: where to go ("Add my Best in Slot" with the Best in Slot module on)
    local bis = LJ.Modules.On("bis")
    self.addBiS:SetShown(bis)
    self.leftHeader:Set(L("Wishlist"), Util.Plural(count, "item", "items"))
    local sheet = self.list
    sheet:Reset(276)
    local pick = function(d) self:Pick(d.key) end
    sheet:Add("row", { text = L("All items"), right = tostring(count), key = false, selected = not self.pick, onClick = pick })
    if #plan > 0 then sheet:Add("section", { text = L("Where to go"), count = #plan }) end
    for _, p in ipairs(plan) do
        if p.inst then
            sheet:Add("row", { text = p.inst.name, sub = table.concat(p.bosses, ", "), right = tostring(p.count),
                key = p.inst.key, selected = self.pick == p.inst.key, onClick = pick })
        else
            local zone = Items.GetMobZone(p.mob)
            sheet:Add("row", { text = p.mob.name .. (p.mob.rankText and (" (" .. L(p.mob.rankText) .. ")") or ""),
                sub = F("%s · Level %s", zone or L("Open world"), Util.LevelRange(p.mob.minLevel, p.mob.maxLevel)),
                right = tostring(p.count), key = "_WORLD", glyph = "skull", glyphColor = p.mob.isRare and C.rare or C.text4,
                selected = false, onClick = function() UI:Open("item", p.itemID) end })
        end
    end
    if groups._OTHER then
        sheet:Add("row", { text = L("Other sources"), right = tostring(#groups._OTHER), key = "_OTHER",
            selected = self.pick == "_OTHER", onClick = pick })
    end
    if #plan == 0 then
        sheet:Space(6)
        sheet:Add("text", { text = L(next(LJ.cdb.wishlist) and "None of these items drops from a dungeon, boss or rare."
            or "Star items to see which dungeons, bosses and rares to run."), font = "small", color = C.text4 })
    end
    sheet:Finish(8)
    self.clear:SetShown(count > 0)

    -- right: the items by source
    local right = self.sheet
    right:Reset(420)
    if self.pick then
        local title, sub = GroupTitle(self.pick)
        self.header:Set(title, sub)
    else
        self.header:Set(L("Your wishlist"), count == 0 and L("Nothing tracked yet")
            or F(LJ.db.wishlistAlerts and "From %d %s · you get an alert when one drops" or "From %d %s",
                #order, Util.PluralWord(#order, "source")))
    end
    if count == 0 then
        right:Add("empty", { title = L("Your wishlist is empty"),
            text = L(LJ.db.wishlistAlerts and "Click the star on any item in the journal to track it here. You get an alert as soon as it drops."
                or "Click the star on any item in the journal to track it here."),
            glyph = "star", button = bis and "Add my Best in Slot" or nil, buttonGlyph = "crown", onClick = function()
                Util.PlaySound("IG_MAINMENU_OPTION")
                LJ.BiS.AddMyBiSToWishlist()
            end })
    end
    for _, key in ipairs(order) do
        if not self.pick or self.pick == key then
            local title, sub, inst = GroupTitle(key)
            right:Add("mob", { text = title, sub = sub, inst = inst, onClick = inst and function(d) UI:Open("instance", d.inst.key) end or nil,
                onEnter = inst and function(f, d) LJ.Tooltip.ShowInstance(f, d.inst) end or nil })
            local cells = {}
            for _, entry in ipairs(groups[key]) do
                local d = { id = entry.id, upgrade = LJ.BiS.Upgrade(entry.id) }
                if entry.source and inst then
                    d.sub = entry.source.boss == 0 and L("Trash") or (inst.bosses[entry.source.boss] and inst.bosses[entry.source.boss].name)
                    d.chance = entry.source.chance
                    d.onClick = function() UI:Open("instance", inst.key, entry.source.boss) end
                elseif key == "_WORLD" then
                    local text = Items.GetQuestSourceText(entry.id) or Items.GetWorldSourceText(entry.id)
                    d.sub = text and text:gsub(" %- ", " · ")
                    d.chance = Items.GetBestChance(entry.id)
                    d.onClick = function(x) UI:Open("item", x.id) end
                else
                    local qids = Quests.rewardOf[entry.id]
                    if qids and qids[1] then
                        d.sub, d.tag, d.questID = Quests.GetName(qids[1]), "QUEST", qids[1]
                        d.onClick = function(x) UI:Open("quest", x.questID) end
                    end
                end
                cells[#cells + 1] = d
            end
            right:Grid("item", cells, 1, Kit.M().item)
            right:Space(10)
        end
    end
    right:Finish(10)
end

function Page:Pick(key)
    self.pick = key or nil
    self.sheet:ScrollToTop()
    self:Refresh()
end

function Page:Show()
    self:Refresh()
end

UI:RegisterPage("wishlist", Page, Kit.LOOKS)
