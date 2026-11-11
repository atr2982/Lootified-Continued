-- Lootified - the list's filter: the armor the Best in Slot list takes and where its items may come from (LJ.cdb.list,
-- Items.InList) and, on the Best in Slot page, the spec it is made for. The list's box (a chip per armor kind the class
-- wears, a chip per source, the drop chance) sits in the first start's question (UI/RatingPicker.lua) and in the
-- filter's panel; the Best in Slot page's header has the filter's button (the spec and the list), a click opens the
-- panel at the right (Filter: the spec as cards, the list's box, Back to realistic; Stat priority, with Percent only:
-- UI/StatPrioView.lua).
-- A change counts at once for the whole addon: the list, For you, the marks and the sims.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local C = Theme.COLORS

local Filter = {}
UI.ListFilter = Filter

-- The sources (Items.LIST_SOURCES): the chip's name and what it takes.
Filter.SOURCES = {
    quests = { text = "Quests", tip = "Rewards of the quests you can take at your level: dungeon, open world and class quests." },
    dungeons = { text = "Dungeons", tip = "The loot of the dungeons' and raids' bosses and trash." },
    rare = { text = "Rare", tip = "The loot of the open world's rares and other mobs that carry the item." },
    crafted = { text = "Crafted", tip = "Everything the professions make, also what you do not make yourself." },
    world = { text = "World", tip = "Random drops any mob of a level range can drop, often under 1 %." },
}
-- The armor kinds' names (Items.LIST_ARMOR's order).
Filter.ARMOR_NAMES = { "Cloth", "Leather", "Mail", "Plate" }
local ARMOR_TIP = "Your list takes armor of this kind from head to feet; cloaks always count."

-- The armor kinds the character's class wears by the top level (Items.LIST_ARMOR's indexes).
function Filter.ClassArmor()
    local kinds = {}
    for k = 1, #Items.LIST_ARMOR do
        if Player.ARMOR[Player.class][k] then kinds[#kinds + 1] = k end
    end
    return kinds
end

-- The list in a line: the armor kinds when it takes not every one the class wears ("Mail + Plate", "No armor"), then
-- the picked sources in order ("Quests · Dungeons · Rare · Crafted"; "No sources" without one).
function Filter.ListText()
    local list, sources, kinds, worn = LJ.cdb.list, {}, {}, Filter.ClassArmor()
    for _, source in ipairs(Items.LIST_SOURCES) do
        if list[source] then sources[#sources + 1] = L(Filter.SOURCES[source].text) end
    end
    local text = #sources > 0 and table.concat(sources, " · ") or L("No sources")
    for _, k in ipairs(worn) do
        if list[Items.LIST_ARMOR[k]] then kinds[#kinds + 1] = L(Filter.ARMOR_NAMES[k]) end
    end
    if #kinds == #worn then return text end
    return F("%s · %s", #kinds > 0 and table.concat(kinds, " + ") or L("No armor"), text)
end

---------------------------------------------------------------------------
-- The list's box: what the list may use, a chip per armor kind the class wears and per source, the drop chance
---------------------------------------------------------------------------
local BOX_PAD, CHIP_GAP, CHIP_HEIGHT = 12, 5, 22
local MAX_CHANCE = 50   -- the drop chance's slider: every drop (0) to 50 %

-- chip.info: its name, what it takes and from which level the class wears it (an armor kind)
local function ChipTip(chip)
    GameTooltip:SetOwner(chip, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L(chip.info.text), 1, 1, 1)
    GameTooltip:AddLine(L(chip.info.tip), 0.8, 0.8, 0.8, true)
    if chip.info.from then GameTooltip:AddLine(F("Your class wears it from level %d.", chip.info.from), 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

-- The drop chance above its slider: every drop, or at least the chance.
local function ChanceText(box, chance)
    box.chanceText:SetText(chance == 0 and L("All drops") or F("At least %d %%", chance))
end

-- The chips and the drop chance as the list is now.
local function BoxRefresh(box)
    for _, chip in ipairs(box.chips) do chip:SetActive(LJ.cdb.list[chip.key]) end
    box.chance:SetValue(LJ.cdb.list.chance)
    ChanceText(box, LJ.cdb.list.chance)
end

-- The drop chance's slider under its label and its value: from every drop to MAX_CHANCE; it counts when it is let go.
local function AddChance(box, width, top)
    local label = Widgets.Text(box, "label", C.text4)
    label:SetPoint("TOPLEFT", BOX_PAD, -top)
    label:SetText(Util.Upper(L("Drop chance")))
    box.chanceText = Widgets.Text(box, "smallSemi", C.white, nil, "RIGHT")
    box.chanceText:SetPoint("TOPRIGHT", -BOX_PAD, -(top - 1))
    top = top + 17
    local slider = Widgets.CreateSlider(box, width - BOX_PAD * 2, 0, MAX_CHANCE)
    slider:SetPoint("TOPLEFT", BOX_PAD, -top)
    slider.onMove = function(_, chance) ChanceText(box, chance) end
    slider.onChange = function(_, chance) Items.SetListChoice("chance", chance) end
    slider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L("Drop chance"), 1, 1, 1)
        GameTooltip:AddLine(L("Dungeon and mob drops below it stay out: nobody farms an item that drops once in hundreds of kills. A drop without a known chance always counts. The mouse wheel moves it by 1 %."),
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.chance = slider
    top = top + 16 + 2
    local low = Widgets.Text(box, "small", C.text4)
    low:SetPoint("TOPLEFT", BOX_PAD, -top)
    low:SetText(L("All drops"))
    local high = Widgets.Text(box, "small", C.text4, nil, "RIGHT")
    high:SetPoint("TOPRIGHT", -BOX_PAD, -top)
    high:SetText(string.format("%d %%", MAX_CHANCE))
    return top + 12
end

-- A section of the box from top: its label over a chip per key of the list (infos: the chips' info), the next line
-- where one is full; a click switches the key (Items.SetListChoice). The y under it.
local function AddSection(box, label, keys, infos, top)
    local fs = Widgets.Text(box, "label", C.text4)
    fs:SetPoint("TOPLEFT", BOX_PAD, -top)
    fs:SetText(Util.Upper(L(label)))
    top = top + 12 + 6
    local x, y = 0, 0
    for i, key in ipairs(keys) do
        local chip = Widgets.CreateChip(box, infos[i].text, nil, CHIP_HEIGHT)
        chip.key, chip.info = key, infos[i]
        if x > 0 and x + chip:GetWidth() > box:GetWidth() - BOX_PAD * 2 then x, y = 0, y + CHIP_HEIGHT + CHIP_GAP end
        chip:SetPoint("TOPLEFT", BOX_PAD + x, -(top + y))
        x = x + chip:GetWidth() + CHIP_GAP
        chip:SetScript("OnClick", function(c)
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            Items.SetListChoice(c.key, not LJ.cdb.list[c.key])
        end)
        chip:HookScript("OnEnter", ChipTip)
        chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
        box.chips[#box.chips + 1] = chip
    end
    return top + y + CHIP_HEIGHT
end

-- A box as wide as width under its title, note: the line under the title. Its sections: Armor (a class that wears more
-- than one kind), Sources and the drop chance. box:Refresh() shows the list again (it does so by itself on
-- LIST_CHANGED while it shows); its height fits its content.
function Filter.CreateListBox(parent, width, note)
    local box = CreateFrame("Frame", nil, parent)
    box:SetWidth(width)
    box.fill = Widgets.CreateBox(box, "BACKGROUND", 1, 8)
    box.ring = Widgets.CreateBox(box, "BACKGROUND", 2, 8, true)
    Widgets.BoxFill(box.fill, box.ring, "row")
    box.title = Widgets.Text(box, "label", Theme.accent)
    box.title:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
    box.title:SetText(Util.Upper(L("What your Best in Slot list may use")))
    Theme.OnAccent(box, function(b, r, g, bl) b.title:SetTextColor(r, g, bl) end)
    box.note = Widgets.Text(box, "small", C.text2)
    box.note:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -5)
    box.note:SetWidth(width - BOX_PAD * 2)
    box.note:SetJustifyH("LEFT")
    box.note:SetWordWrap(true)
    box.note:SetText(L(note))
    local top = BOX_PAD + 12 + 5 + math.ceil(box.note:GetStringHeight()) + 10
    box.chips = {}
    local worn = Filter.ClassArmor()
    if #worn > 1 then
        local keys, infos = {}, {}
        for i, k in ipairs(worn) do
            local from = Player.ARMOR[Player.class][k]
            keys[i] = Items.LIST_ARMOR[k]
            infos[i] = { text = Filter.ARMOR_NAMES[k], tip = ARMOR_TIP, from = from > 1 and from or nil }
        end
        top = AddSection(box, "Armor", keys, infos, top) + 10
    end
    local infos = {}
    for i, source in ipairs(Items.LIST_SOURCES) do infos[i] = Filter.SOURCES[source] end
    top = AddSection(box, "Sources", Items.LIST_SOURCES, infos, top) + 10
    top = AddChance(box, width, top)
    box:SetHeight(top + BOX_PAD)
    box.Refresh = BoxRefresh
    LJ:Listen("LIST_CHANGED", function() if box:IsVisible() then box:Refresh() end end)
    box:SetScript("OnShow", BoxRefresh)
    box:Refresh()
    return box
end

---------------------------------------------------------------------------
-- The Best in Slot page's button: FILTER · the spec over the list (Filter.ListText)
---------------------------------------------------------------------------
local BUTTON_HEIGHT, ICON = 40, 24

local function ButtonVisual(b)
    local a = Theme.accent
    local hover = Widgets.Hover(b)
    if Theme.IsClassic() then
        Widgets.BoxFill(b.fill, b.ring, b.active and "red" or "button", hover)
    elseif b.active then
        b.fill:SetColor(a[1], a[2], a[3], 0.14)
        b.ring:SetColor(a[1], a[2], a[3], 0.7)
    else
        b.fill:SetColor(1, 1, 1, hover and 0.10 or 0.05)
        b.ring:SetColor(1, 1, 1, hover and 0.22 or 0.13)
    end
    b.mark:SetColor(a[1], a[2], a[3], 0.2)
    b.glyph:SetVertexColor(a[1], a[2], a[3], 1)
    b.head:SetTextColor(a[1], a[2], a[3])
end

-- Its texts for a spec and the list now, no wider than maxWidth (a longer list line loses its end).
local function ButtonUpdate(b, spec, maxWidth)
    b.head:SetText(Util.Upper(F("Filter · %s", L(spec.name))))
    b.sources:SetText(Filter.ListText())
    local text = math.max(Widgets.TextWidth(b.head), Widgets.TextWidth(b.sources))
    local fixed = 8 + ICON + 9 + 8 + 12 + 10
    text = math.min(text, maxWidth - fixed)
    for _, fs in ipairs({ b.head, b.sources }) do fs:SetWidth(text) end
    b:SetWidth(math.floor(fixed + text + 0.5))
end

-- onClick(button): opens or closes the panel. button:Update(spec, maxWidth), button:SetActive(open).
function Filter.CreateButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(BUTTON_HEIGHT)
    b.fill = Widgets.CreateBox(b, "BACKGROUND", 1, 8)
    b.ring = Widgets.CreateBox(b, "BACKGROUND", 2, 8, true)
    local mark = CreateFrame("Frame", nil, b)
    mark:SetSize(ICON, ICON)
    mark:SetPoint("LEFT", 8, 0)
    b.mark = Widgets.CreateBox(mark, "ARTWORK", 0, 6)
    b.glyph = Widgets.Glyph(mark, "funnel", 13, nil, "ARTWORK", 2)
    b.glyph:SetPoint("CENTER")
    b.head = Widgets.Text(b, "label", Theme.accent)
    b.head:SetPoint("TOPLEFT", mark, "TOPRIGHT", 9, 1)
    b.sources = Widgets.Text(b, "smallSemi", C.text1)
    b.sources:SetPoint("BOTTOMLEFT", mark, "BOTTOMRIGHT", 9, -1)
    for _, fs in ipairs({ b.head, b.sources }) do
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    b.caret = Widgets.Glyph(b, "caretDown", 10, C.text3)
    b.caret:SetPoint("RIGHT", -10, 0)
    b.Update = ButtonUpdate
    function b:SetActive(on)
        self.active = on
        ButtonVisual(self)
    end
    b:SetScript("OnClick", function(self)
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        onClick(self)
    end)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        ButtonVisual(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L("Filter"), 1, 1, 1)
        GameTooltip:AddLine(Filter.ListText(), 1, 1, 1, true)
        GameTooltip:AddLine(L("Your spec, the armor and the sources your Best in Slot list, For you and the sims take. Click to change them."),
            0.8, 0.8, 0.8, true)
        local spec = Player:GetActiveSpec()
        if spec and LJ.StatPrio.IsCustom(spec) then GameTooltip:AddLine(L("Your own stat priority counts."), 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        ButtonVisual(self)
        GameTooltip:Hide()
    end)
    Theme.OnAccent(b, ButtonVisual)
    ButtonVisual(b)
    return b
end

---------------------------------------------------------------------------
-- The panel: two tabs. Filter: the spec as cards, the list's box, Back to realistic and Done; Stat priority: the spec's
-- stats to drag (UI/StatPrioView.lua)
---------------------------------------------------------------------------
Filter.PANEL_WIDTH = 430
local PAD, CARD_GAP, CARD_HEIGHT = 16, 8, 46
local PANEL_BUTTON_HEIGHT = 28    -- Back to realistic and Done

local function CardVisual(card)
    Widgets.BoxFill(card.fill, card.ring, card.active and "pick" or "row", card.hovered)
    Widgets.SetTextColor(card.name, card.active and C.white or C.text1)
end

local function NewCard(panel, width)
    local card = CreateFrame("Button", nil, panel)
    card:SetSize(width, CARD_HEIGHT)
    card.fill = Widgets.CreateBox(card, "BACKGROUND", 1, 8)
    card.ring = Widgets.CreateBox(card, "BACKGROUND", 2, 8, true)
    card.name = Widgets.Text(card, "h3", C.text1)
    card.name:SetPoint("TOPLEFT", 12, -8)
    card.sub = Widgets.Text(card, "small", C.text3)
    card.sub:SetPoint("BOTTOMLEFT", 12, 8)
    for _, fs in ipairs({ card.name, card.sub }) do
        fs:SetWidth(width - 24)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    card:SetScript("OnClick", function(c)
        if c.active then return end
        Util.PlaySound("IG_CHARACTER_INFO_TAB")
        Player:SetChosenSpec(Player.class, c.specKey)
    end)
    card:SetScript("OnEnter", function(c) c.hovered = true CardVisual(c) end)
    card:SetScript("OnLeave", function(c) c.hovered = false CardVisual(c) end)
    return card
end

-- The tab picked: Filter with the cards of the class's specs (the active one picked; the one the talents point to says
-- so) and the box as the list is now, or Stat priority with the active spec's stats. With Sim there is no Stat priority
-- tab: the simulator rates the items (StatPrio.Counts).
local function PanelRefresh(panel)
    local specs, active = Player:GetSpecs(Player.class), Player:GetActiveSpec()
    local prio = active ~= nil and LJ.StatPrio.Counts(active)
    panel.tabs.stats:SetShown(prio)
    if not prio then panel.tab = "filter" end
    for key, chip in pairs(panel.tabs) do chip:SetActive(panel.tab == key) end
    panel.filter:SetShown(panel.tab == "filter")
    panel.stats:SetShown(panel.tab == "stats")
    if panel.tab == "stats" then
        panel.stats:Refresh(active)
        return
    end
    local detected = Player:DetectSpecKey()
    local width = math.floor((Filter.PANEL_WIDTH - PAD * 2 - CARD_GAP) / 2)
    for i, spec in ipairs(specs) do
        local card = panel.cards[i] or NewCard(panel.filter, width)
        panel.cards[i] = card
        card.specKey = spec.key
        card.active = active ~= nil and spec.key == active.key
        card.name:SetText(L(spec.name))
        card.sub:SetText(spec.key == detected and F("%s · %s", L(spec.role), L("your talents")) or L(spec.role))
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", PAD + ((i - 1) % 2) * (width + CARD_GAP),
            -(panel.cardsTop + math.floor((i - 1) / 2) * (CARD_HEIGHT + CARD_GAP)))
        CardVisual(card)
        card:Show()
    end
    for i = #specs + 1, #panel.cards do panel.cards[i]:Hide() end
    local y = panel.cardsTop + math.ceil(#specs / 2) * (CARD_HEIGHT + CARD_GAP) + 4
    panel.box:ClearAllPoints()
    panel.box:SetPoint("TOPLEFT", PAD, -y)
    panel.box:Refresh()
    y = y + panel.box:GetHeight() + 10
    -- the line under the box where it fits with the buttons below it, at least half the padding above the panel's
    -- bottom (not in the classic look's lower page in most languages: the buttons stay inside the panel)
    local whole = math.ceil(panel.whole:GetStringHeight()) + 14
    local fits = y + whole + PANEL_BUTTON_HEIGHT + PAD / 2 <= panel:GetHeight()
    panel.whole:SetShown(fits)
    if fits then
        panel.whole:ClearAllPoints()
        panel.whole:SetPoint("TOPLEFT", PAD, -y)
        y = y + whole
    end
    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("TOPLEFT", PAD, -y)
    panel.done:ClearAllPoints()
    panel.done:SetPoint("TOPRIGHT", -PAD, -y)
end

-- The panel inside parent (the page places it); onDone() closes it (Done, its close button). panel:Refresh().
function Filter.CreatePanel(parent, onDone)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(Filter.PANEL_WIDTH)
    panel:EnableMouse(true)
    Widgets.CreateShadow(panel, 14, 0.7)
    panel.bg = Widgets.CreatePopupPanel(panel, 10)
    panel.close = Widgets.CreateButton(panel, nil, "icon", "close", 24, 24)
    panel.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD)
    panel.close:SetScript("OnClick", function() onDone() end)
    -- the tabs at the top (the one picked kept while the session lasts)
    panel.tab, panel.tabs = "filter", {}
    local x = PAD
    for _, tab in ipairs({ { key = "filter", text = "Filter", glyph = "funnel" },
        { key = "stats", text = "Stat priority", glyph = "sortDown" } }) do
        local chip = Widgets.CreateChip(panel, tab.text, tab.glyph, 24)
        chip.key = tab.key
        chip:SetPoint("TOPLEFT", x, -PAD)
        x = x + chip:GetWidth() + 6
        chip:SetScript("OnClick", function(c)
            if panel.tab == c.key then return end
            Util.PlaySound("U_CHAT_SCROLL_BUTTON")
            panel.tab = c.key
            panel:Refresh()
        end)
        panel.tabs[tab.key] = chip
    end
    local top = PAD + 24 + 14
    -- Filter
    panel.filter = CreateFrame("Frame", nil, panel)
    panel.filter:SetAllPoints()
    panel.specLabel = Widgets.Text(panel.filter, "label", C.text4)
    panel.specLabel:SetPoint("TOPLEFT", PAD, -top)
    panel.specLabel:SetText(Util.Upper(L("Spec")))
    panel.cardsTop = top + 18
    panel.cards = {}
    panel.box = Filter.CreateListBox(panel.filter, Filter.PANEL_WIDTH - PAD * 2,
        "Picked at your first start. Percent and Sim both use it.")
    panel.whole = Widgets.Text(panel.filter, "small", C.text3)
    panel.whole:SetWidth(Filter.PANEL_WIDTH - PAD * 2)
    panel.whole:SetJustifyH("LEFT")
    panel.whole:SetWordWrap(true)
    panel.whole:SetText(L("Counts for the whole addon: Best in Slot, For you and the simulator."))
    panel.reset = Widgets.CreateButton(panel.filter, "Back to realistic", "ghost", "reset", nil, PANEL_BUTTON_HEIGHT)
    panel.reset:SetScript("OnClick", function()
        Util.PlaySound("U_CHAT_SCROLL_BUTTON")
        Items.ResetList()
    end)
    Widgets.SetTooltip(panel.reset, "Back to realistic",
        "The list of the first start: every armor your class wears, quests, dungeons and rares, drops of 10 % or more.",
        "ANCHOR_TOP")
    panel.done = Widgets.CreateButton(panel.filter, "Done", "primary", nil, nil, PANEL_BUTTON_HEIGHT)
    panel.done:SetScript("OnClick", function() onDone() end)
    -- Stat priority
    panel.stats = UI.StatPrioView.Create(panel, Filter.PANEL_WIDTH - PAD * 2)
    panel.stats:SetPoint("TOPLEFT", PAD, -top)
    panel.Refresh = PanelRefresh
    panel:Hide()
    return panel
end

---------------------------------------------------------------------------
-- The panel's tour: the first time it opens the panel explains itself, each part once (LJ.db.filterTour; starting the
-- main tour again resets it): the spec, the list's box and, where it counts (Percent), the Stat priority tab. It uses
-- the spotlight of the main tour (UI/Tour.lua).
---------------------------------------------------------------------------
local filterTour

-- The steps of the parts not seen yet (key: the part a step belongs to).
local function TourSteps(panel)
    local seen, steps = LJ.db.filterTour or {}, {}
    local function Tab(key)
        return function()
            panel.tab = key
            panel:Refresh()
        end
    end
    if not seen.filter then
        steps[#steps + 1] = { key = "filter", title = "Spec",
            text = "Lootified rates items for the spec picked here: your list, For you and the marks. \"your talents\" marks the one your talents point to.",
            enter = Tab("filter"),
            target = function() return panel.specLabel, unpack(panel.cards) end }
        local armor = #Filter.ClassArmor() > 1
        steps[#steps + 1] = { key = "filter", title = armor and "Armor and sources" or "Sources",
            text = armor
                and "What your list may use: the armor kinds (cloaks always count) and where its items may come from. The drop chance leaves out rarer drops (10 % at the start). Every change counts at once, for the sims too; Back to realistic gives back the list of your first start."
                or "What your list may use: where its items may come from. The drop chance leaves out rarer drops (10 % at the start). Every change counts at once, for the sims too; Back to realistic gives back the list of your first start.",
            enter = Tab("filter"),
            target = function() return panel.box, panel.reset end }
    end
    local spec = Player:GetActiveSpec()
    if not seen.stats and spec and LJ.StatPrio.Counts(spec) then
        steps[#steps + 1] = { key = "stats", title = "Stat priority",
            text = "Your spec's stats, the one that counts most on top. Drag a stat up or down: your list and the Percent numbers follow at once; Default order gives back your spec's own order. Only with Percent: Sim rates your items by DPS.",
            enter = Tab("stats"),
            target = function() return panel.tabs.stats, panel.stats end }
    end
    return steps
end

-- The panel opened (the Best in Slot page): it explains the parts not seen yet, not during the main tour or a fight.
function Filter.StartTour(panel)
    local Tour = UI.Tour
    if Tour.active or InCombatLockdown() then return end
    local steps = TourSteps(panel)
    if #steps == 0 then return end
    filterTour = filterTour or Tour.New({
        host = function() return UI.frame end,
        -- the tour ended: its parts count as seen
        seen = function(t)
            LJ.db.filterTour = LJ.db.filterTour or {}
            for _, step in ipairs(t.steps) do LJ.db.filterTour[step.key] = true end
        end,
    })
    if filterTour.active then return end
    filterTour.steps = steps
    filterTour:Begin()
end

-- The panel closed: its tour ends (its parts count as seen).
function Filter.StopTour()
    if filterTour and filterTour.active then filterTour:Stop(true) end
end

-- The panel's tour (nil until it ran once), for the tests.
function Filter.Tour() return filterTour end
