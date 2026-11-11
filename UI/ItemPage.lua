-- Lootified - item page: where one item comes from. Open world mobs (rares included) with drop chance, level,
-- zone and a map marker for their camps, random world drops with their level range, dungeon bosses, and quests
-- (open world quests with their quest giver on the map).
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
local MOB_HEIGHT = 52
local ENTRY_HEIGHT = 44
local LABEL_HEIGHT = 30

-- the chance as the other pages show it (Core/Util.lua)
local FormatChance = Util.FormatChance

local function OnMapClick(button)
    if button.mob then Lists.MarkNextCamp(button.mob, button.itemName) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function RowVisual(row)
    row.hl:SetColor(1, 1, 1, Widgets.Hover(row) and 0.05 or 0)
end

local function CreateMobRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(MOB_HEIGHT)
    row:EnableMouse(true)
    row.hl = Widgets.CreateLazyBox(row, "BACKGROUND", 1, 8)
    row.emblem = Widgets.CreateEmblem(row, 36)
    row.emblem:SetPoint("LEFT", 6, 0)
    row.name = Widgets.Text(row, "h3", C.white)
    row.name:SetPoint("TOPLEFT", row.emblem, "TOPRIGHT", 11, -2)
    row.rank = Widgets.CreatePill(row, 16, "pillTiny")
    row.rank:SetPoint("LEFT", row.name, "RIGHT", 7, 0)
    row.sub = Widgets.Text(row, "small", C.text3)
    row.sub:SetPoint("BOTTOMLEFT", row.emblem, "BOTTOMRIGHT", 11, 2)
    row.map = Widgets.CreateButton(row, "Map", "solidAccent", "mapPin", nil, 22)
    -- its tooltip explains why the button is off when the game has no map position
    row.map:SetMotionScriptsWhileDisabled(true)
    row.map:SetPoint("RIGHT", -8, 0)
    row.map:SetFrameLevel(row:GetFrameLevel() + 4)
    row.map:SetScript("OnClick", OnMapClick)
    row.chance = Widgets.CreatePill(row, 19, "count")
    row.chance:SetPoint("RIGHT", row.map, "LEFT", -10, 0)
    row:SetScript("OnEnter", function(r)
        r.hovered = true
        RowVisual(r)
        if not r.mob then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.mob.name, 1, 0.82, 0)
        GameTooltip:AddLine(F("Level %s%s", Util.LevelRange(r.mob.minLevel, r.mob.maxLevel),
            r.mob.rankText and (" " .. L(r.mob.rankText)) or ""), 1, 1, 1)
        if r.mob.isRare then
            GameTooltip:AddLine(L("Rare spawn: it is not always up, check its camps."), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(F("%s in the Classic data.", Util.Plural(r.mob.spawns, "spawn point")), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(r)
        r.hovered = false
        RowVisual(r)
        GameTooltip:Hide()
    end)
    return row
end

local function CreateEntryRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ENTRY_HEIGHT)
    b.hl = Widgets.CreateLazyBox(b, "BACKGROUND", 1, 8)
    b.emblem = Widgets.CreateEmblem(b, 32)
    b.emblem:SetPoint("LEFT", 6, 0)
    b.text = Widgets.Text(b, "h3", C.text1)
    b.text:SetPoint("TOPLEFT", b.emblem, "TOPRIGHT", 10, 0)
    b.text:SetPoint("RIGHT", -70, 0)
    b.sub = Widgets.Text(b, "small", C.text3)
    b.sub:SetPoint("BOTTOMLEFT", b.emblem, "BOTTOMRIGHT", 10, 0)
    b.sub:SetPoint("RIGHT", -70, 0)
    b.chance = Widgets.CreatePill(b, 19, "count")
    b.chance:SetPoint("RIGHT", -8, 0)
    -- quest giver on the map (open world quests)
    b.map = Widgets.CreateButton(b, "Map", "solidAccent", "mapPin", nil, 22)
    b.map:SetMotionScriptsWhileDisabled(true)
    b.map:SetPoint("RIGHT", -8, 0)
    b.map:SetFrameLevel(b:GetFrameLevel() + 4)
    b.map:SetScript("OnClick", function(btn)
        if not btn.spot then return end
        if LJ.MapPin.IsTarget(btn.spot) then LJ.MapPin.Clear() else LJ.MapPin.Show(btn.spot) end
    end)
    b.map:Hide()
    b:SetScript("OnClick", function(btn) if btn.onClick then btn.onClick() end end)
    b:SetScript("OnEnter", function(btn) btn.hovered = true RowVisual(btn) end)
    b:SetScript("OnLeave", function(btn) btn.hovered = false RowVisual(btn) end)
    return b
end

-- Card with a glyph, a headline and a wrapped text (random world drops, "no source" notice).
local function CreateNoteCard(parent)
    local f = CreateFrame("Frame", nil, parent)
    Widgets.StyleCard(f, 10)
    f.icon = Widgets.Glyph(f, "globe", 16, C.gold)
    f.icon:SetPoint("TOPLEFT", 14, -14)
    f.title = Widgets.Text(f, "h3", C.white)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 9, 1)
    f.title:SetPoint("RIGHT", -14, 0)
    f.text = Widgets.Text(f, "body", C.text2)
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.text:SetPoint("RIGHT", -14, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(true)
    function f:Set(glyph, title, text, width)
        Theme.SetGlyph(self.icon, glyph, C.gold)
        self.title:SetText(title)
        self.text:SetText(text)
        self:SetWidth(width)
        self.text:SetWidth(width - 53)
        self:SetHeight(math.ceil(14 + self.title:GetStringHeight() + 6 + self.text:GetStringHeight() + 14))
    end
    return f
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function Page:Create(root)
    local side = Widgets.CreateSidebar(root, SIDEBAR)
    self.side = side
    self.icon = Widgets.CreateItemIcon(side, 56)
    self.icon:SetPoint("TOP", 0, -24)
    self.icon:SetScript("OnEnter", function(b)
        if self.itemID then Widgets.ShowItemTooltip(b, self.itemID) end
    end)
    self.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.icon:SetScript("OnClick", function(_, button)
        if self.itemID then Items.HandleClick(self.itemID, button) end
    end)
    self.name = Widgets.Text(side, "h2", C.white, nil, "CENTER")
    self.name:SetPoint("TOP", self.icon, "BOTTOM", 0, -12)
    self.name:SetWidth(SIDEBAR - 28)
    self.name:SetWordWrap(true)
    self.slot = Widgets.Text(side, "small", C.text3, nil, "CENTER")
    self.slot:SetPoint("TOP", self.name, "BOTTOM", 0, -5)
    self.slot:SetWidth(SIDEBAR - 28)
    self.slot:SetWordWrap(true)

    self.wish = Widgets.CreateButton(side, "Add to Wishlist", "primary", "star", SIDEBAR - 40, 28)
    self.wish:SetPoint("TOP", self.slot, "BOTTOM", 0, -18)
    self.wish:SetScript("OnClick", function() if self.itemID then Items.ToggleWishlist(self.itemID) end end)
    self.tryOn = Widgets.CreateButton(side, "Try on", "ghost", "shirt", SIDEBAR - 40, 28)
    self.tryOn:SetPoint("TOP", self.wish, "BOTTOM", 0, -8)
    self.tryOn:SetScript("OnClick", function()
        if self.itemID then DressUpItemLink(Items.GetLink(self.itemID)) end
    end)
    Widgets.SetTryOn(self.tryOn, true)
    self.back = Widgets.CreateButton(side, "Back to search", "ghost", "caretLeft", SIDEBAR - 40, 28)
    self.back:SetPoint("TOP", self.tryOn, "BOTTOM", 0, -8)
    self.back:SetScript("OnClick", function()
        local search = UI.pages.search
        UI:Open("search", search and search.query or "")
    end)
    self.me = Widgets.CreateCharacterChip(side, function(b) UI:ShowOptions(b) end)
    self.me:SetPoint("BOTTOMLEFT")
    self.me:SetPoint("BOTTOMRIGHT", -1, 0)

    local main = CreateFrame("Frame", nil, root)
    main:SetPoint("TOPLEFT", SIDEBAR, 0)
    main:SetPoint("BOTTOMRIGHT")
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
    header.sub:SetPoint("RIGHT", -22, 0)
    header.line = Widgets.Line(header, "BORDER", 0.06)
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    self.header = header

    self.scroll = Widgets.CreateScrollArea(main, -8)
    self.scroll:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT + 6))
    self.scroll:SetPoint("BOTTOMRIGHT", -16, 0)
    self.pools = { label = {}, mob = {}, entry = {}, note = {} }
    self.footer = Widgets.Text(self.scroll.content, "small", C.text4)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetWordWrap(true)
end

-- Frame number i of a pool (created on first use).
function Page:Get(kind, i)
    local pool = self.pools[kind]
    local f = pool[i]
    if f then return f end
    local content = self.scroll.content
    if kind == "label" then
        f = Widgets.CreateSectionLabel(content)
    elseif kind == "mob" then
        f = CreateMobRow(content)
    elseif kind == "entry" then
        f = CreateEntryRow(content)
    else
        f = CreateNoteCard(content)
    end
    pool[i] = f
    return f
end

function Page:Refresh()
    local itemID = self.itemID
    if not itemID then return end
    Theme.SetAccent(Theme.COLORS.defaultAccent)
    local rec = Items.Get(itemID)
    local itemName = rec.name or rec.fallbackName or F("Item #%d", itemID)
    local mobs, random = Items.GetWorldSources(itemID)
    mobs = mobs or {}
    local sources = Items.GetSources(itemID) or {}
    local rewardOf = Quests and Quests.rewardOf and Quests.rewardOf[itemID] or {}
    local worldQuests = Items.GetWorldQuestSources(itemID) or {}

    -- sidebar
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
    self.tryOn:SetPoint("TOP", wishOn and self.wish or self.slot, "BOTTOM", 0, wishOn and -8 or -18)
    self.back:SetShown(UI.pages.search and UI.pages.search.query and UI.pages.search.query ~= "" and true or false)

    -- header
    local h = self.header
    if #mobs > 0 then
        local rare = false
        for _, s in ipairs(mobs) do if s.mob.isRare then rare = true break end end
        h.pill:Set(rare and "RARE DROP" or "OPEN WORLD", "gold", "globe")
    elseif random then
        h.pill:Set("WORLD DROP", "gold", "globe")
    elseif #sources == 0 and #rewardOf + #worldQuests > 0 then
        h.pill:Set("QUEST REWARD", "gold", "scroll")
    else
        h.pill:Set("ITEM", "acc", "package")
    end
    h.title:SetText(itemName)
    h.title:SetTextColor(r, g, b)
    local parts = {}
    if #mobs > 0 then parts[#parts + 1] = #mobs == 1 and L("1 mob drops it") or F("%d mobs drop it", #mobs) end
    if random then parts[#parts + 1] = F("random drop from mobs level %s", Util.LevelRange(random.minLevel, random.maxLevel)) end
    if #sources > 0 then parts[#parts + 1] = Util.Plural(#sources, "dungeon source") end
    if #rewardOf + #worldQuests > 0 then parts[#parts + 1] = F("reward of %s", Util.Plural(#rewardOf + #worldQuests, "quest")) end
    h.sub:SetText(#parts > 0 and table.concat(parts, "  ·  ") or L("No known drop source"))

    -- content
    local width = self.scroll:GetWidth()
    if not width or width < 100 then width = 704 end
    local used = { label = 0, mob = 0, entry = 0, note = 0 }
    local y = 0
    local function Label(text)
        if y > 0 then y = y + 8 end
        used.label = used.label + 1
        local l = self:Get("label", used.label)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", 4, -(y + 8))
        l:SetWidth(width - 8)
        l:SetLabel(text)
        l:Show()
        y = y + LABEL_HEIGHT
    end
    local function Note(glyph, title, text)
        used.note = used.note + 1
        local n = self:Get("note", used.note)
        n:ClearAllPoints()
        n:SetPoint("TOPLEFT", 0, -y)
        n:Set(glyph, title, text, width - 4)
        n:Show()
        y = y + n:GetHeight() + 6
    end

    if #mobs > 0 then
        Label(F("Drops from · %d", #mobs))
        for _, s in ipairs(mobs) do
            local mob = s.mob
            used.mob = used.mob + 1
            local row = self:Get("mob", used.mob)
            row.mob = mob
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetWidth(width - 4)
            row.emblem:SetGlyph(Theme.BossEmblem({ name = mob.name }))
            row.emblem:SetRare(mob.isRare)
            row.name:SetText(mob.name)
            if mob.rankText then
                row.rank:Set(Util.Upper(L(mob.rankText)), mob.isRare and "gold" or "neutral")
                row.rank:Show()
            else
                row.rank:Hide()
            end
            local zone = Items.GetMobZone(mob)
            local sub = F("Level %s", Util.LevelRange(mob.minLevel, mob.maxLevel))
            if zone then sub = sub .. "  ·  " .. zone end
            if #mob.locs > 1 then sub = sub .. "  ·  " .. F("%d camps", #mob.locs) end
            row.sub:SetText(sub)
            local chance = FormatChance(s.chance)
            row.chance:Set(chance or "", "chance", nil, 52)
            if chance then row.chance:SetTextColorOverride(Theme.ChanceColor(s.chance)) end
            row.chance:SetShown(chance ~= nil)
            -- map marker
            row.map.mob, row.map.itemName = mob, itemName
            local label, glyph, tipTitle, tip, canMark = Lists.MapButtonState(mob, itemName)
            row.map:SetEnabled(canMark)
            row.map:SetGlyph(glyph)
            row.map:SetLabel(label)
            Widgets.SetTooltip(row.map, tipTitle, tip, "ANCHOR_TOP")
            -- keep the name clear of the pills and the button on the right
            local right = row.map:GetWidth() + 10 + (chance and 62 or 0) + 12
            local rankW = mob.rankText and (row.rank:GetWidth() + 7) or 0
            row.name:SetWidth(math.max(40, math.min(Widgets.TextWidth(row.name) + 2, width - 4 - 53 - right - rankW)))
            row.sub:SetWidth(math.max(40, width - 4 - 53 - right))
            RowVisual(row)
            row:Show()
            y = y + MOB_HEIGHT
        end
    end

    if random then
        if #mobs == 0 then Label("Open world") else y = y + 6 end
        Note("globe", L("Random world drop"),
            F("Can drop from almost any mob around level %s in the open world (%d mobs in the Classic data). "
                .. "The chance per kill is very low, so there is no single mob to farm.",
                Util.LevelRange(random.minLevel, random.maxLevel), random.mobs or 0))
    end

    if #sources > 0 then
        Label(F("Dungeons & raids · %d", #sources))
        for _, s in ipairs(sources) do
            local inst = LJ.instanceByKey[s.inst]
            if inst then
                used.entry = used.entry + 1
                local e = self:Get("entry", used.entry)
                e:ClearAllPoints()
                e:SetPoint("TOPLEFT", 0, -y)
                e:SetWidth(width - 4)
                local boss = s.boss > 0 and inst.bosses[s.boss] or nil
                e.text:SetText(boss and boss.name or L("Trash mobs"))
                e.sub:SetText(F("%s  ·  Level %s", inst.name, Util.LevelRange(inst.minLevel, inst.maxLevel)))
                if boss then
                    e.emblem:SetBoss(boss)
                else
                    e.emblem:SetRare(false)
                    e.emblem:SetGlyph("skull")
                end
                local chance = FormatChance(s.chance)
                e.chance:Set(chance or "", "chance", nil, 52)
                if chance then e.chance:SetTextColorOverride(Theme.ChanceColor(s.chance)) end
                e.chance:SetShown(chance ~= nil)
                e.map:Hide()
                -- rows are reused: a quest row of another faction left it dimmed
                e:SetAlpha(1)
                local instKey, bossIndex = inst.key, s.boss
                -- boss 0 is the trash: the loot view opens on its card
                e.onClick = function() UI:Open("instance", instKey, bossIndex) end
                RowVisual(e)
                e:Show()
                y = y + ENTRY_HEIGHT
            end
        end
    end

    if #rewardOf + #worldQuests > 0 then
        Label(F("Quest reward · %d", #rewardOf + #worldQuests))
        -- dungeon quests: a click opens the quest in the journal
        for _, qid in ipairs(rewardOf) do
            local q = Quests.Get(qid)
            if q then
                used.entry = used.entry + 1
                local e = self:Get("entry", used.entry)
                e:ClearAllPoints()
                e:SetPoint("TOPLEFT", 0, -y)
                e:SetWidth(width - 4)
                e.text:SetText(q.name)
                e.sub:SetText((q.level and (F("Level %s", q.level) .. "  ·  ") or "") .. Quests.SideText(q.side))
                e.emblem:SetRare(false)
                e.emblem:SetGlyph("scroll")
                e.chance:Hide()
                e.map:Hide()
                e:SetAlpha(1)
                e.onClick = function() UI:Open("quest", qid) end
                RowVisual(e)
                e:Show()
                y = y + ENTRY_HEIGHT
            end
        end
        -- open world quests: quest giver, zone and a map marker on the giver
        for _, q in ipairs(worldQuests) do
            used.entry = used.entry + 1
            local e = self:Get("entry", used.entry)
            e:ClearAllPoints()
            e:SetPoint("TOPLEFT", 0, -y)
            e:SetWidth(width - 4)
            local mine = Quests.IsForPlayer(q)
            e.text:SetText(q.name)
            local zone = Items.GetQuestZone(q)
            local sub = F("Level %d  ·  %s  ·  %s%s", q.level or 0, Quests.SideText(q.side), q.giver or "",
                zone and ("  ·  " .. zone) or "")
            if q.classes then
                local names = {}
                for _, c in ipairs(q.classes) do
                    names[#names + 1] = Util.ClassName(c:upper())
                end
                sub = sub .. "  ·  " .. table.concat(names, ", ")
            end
            e.sub:SetText(sub)
            e:SetAlpha(mine and 1 or 0.55)
            e.emblem:SetRare(false)
            e.emblem:SetGlyph("scroll")
            e.chance:Hide()
            e.onClick = nil
            local spot
            if q.loc then
                LJ.MapPin.Resolve(q.loc)
                if q.loc.map and q.loc.x and q.loc.y then
                    spot = { map = q.loc.map, x = q.loc.x, y = q.loc.y, title = q.giver, detail = F("Quest: %s", q.name) }
                end
            end
            e.map.spot = spot
            if spot then
                local marked = LJ.MapPin.IsTarget(spot)
                e.map:SetGlyph(marked and "check" or "mapPin")
                e.map:SetLabel(marked and "Marked" or "Map")
                Widgets.SetTooltip(e.map, marked and "Marked on your map" or "Show the quest giver on the map",
                    marked and L("Click to remove the mark.") or L("Opens the world map and sets a marker you can follow."), "ANCHOR_TOP")
                e.map:Show()
            else
                e.map:Hide()
            end
            RowVisual(e)
            e:Show()
            y = y + ENTRY_HEIGHT
        end
    end

    if #mobs == 0 and not random and #sources == 0 and #rewardOf + #worldQuests == 0 then
        Note("info", L("No drop source known"), L("This item is not in the loot data. It may be crafted, sold by a vendor or come from a source that is new in Forever."))
    end

    y = y + 14
    self.footer:ClearAllPoints()
    self.footer:SetPoint("TOPLEFT", 4, -y)
    self.footer:SetWidth(width - 12)
    self.footer:SetText(L("Open world drop chances and spawn points are the Classic values and can differ in WoW: Forever."))
    self.footer:SetShown(#mobs > 0 or random ~= nil)
    y = y + (self.footer:IsShown() and self.footer:GetStringHeight() or 0) + 12

    for kind, pool in pairs(self.pools) do
        for i = used[kind] + 1, #pool do pool[i]:Hide() end
    end
    self.scroll:SetContentHeight(y)
    self.me:Update()
end

function Page:Show(itemID)
    if itemID and itemID ~= self.itemID then
        self.itemID = itemID
        self.scroll:ScrollToTop()
        -- ask the client for the item so the name, quality and slot are the live ones
        Items.WhenLoaded(itemID, function()
            if self.itemID == itemID and self.root and self.root:IsVisible() then self:Refresh() end
        end)
    end
    self:Refresh()
end

-- The map buttons show which camp is marked: redraw when the mark changes.
LJ:Listen("MAP_TARGET_CHANGED", function()
    -- only while the window shows the page (its root stays "shown" while the window is closed)
    if Page.root and Page.root:IsVisible() and Page.itemID then Page:Refresh() end
end)

UI:RegisterPage("item", Page)
