-- Lootified - the journal of the classic and the modern look. The start page shows every dungeon as a picture card: the
-- best one for the character big on top, the others for the level below it, then the ones coming up (or all of them). A
-- dungeon has a header with its picture, its name, a link back to all dungeons and its entrance
-- buttons; below it a Bosses | Quests switch over the bosses on the left (round portraits with their level, the picked
-- one highlighted) and the picked boss's loot on the right, the boss itself beside it as an animated 3D model.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Kit = LJ.Kit
local PQ = LJ.PaneQuests
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Items = LJ.Items
local Player = LJ.Player
local Quests = LJ.Quests
local Lists = LJ.Lists
local BiS = LJ.BiS
local C = Theme.COLORS
local H = Theme.PANE    -- the panels and colors of the classic or the modern look

local Page = {}

local GAP = 12
local HEAD_HEIGHT = 92          -- the dungeon's header panel
local LEFT_WIDTH = 300          -- the boss list panel
local COLUMNS = 4               -- dungeon cards per row
local CARD_HEIGHT, FEATURE_HEIGHT = 112, 148
local BOSS_HEIGHT = 46
local LOOT_HEAD = 56            -- the picked boss above its loot
local MODEL_WIDTH = 210         -- the picked boss's model beside its loot
local SWITCH_HEIGHT = 30        -- the Bosses | Quests switch above the list
local TABS = {
    { key = "loot", text = "Bosses" },
    { key = "quests", text = "Quests", glyph = "scroll" },
}

-- A square line around a frame (the dungeon cards): four 1-unit textures; returns them as a list.
local function Edge(frame, color)
    local lines = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetTexture(Util.WHITE)
        t:SetPoint(p[1])
        t:SetPoint(p[2])
        if p[3] then t:SetHeight(1) else t:SetWidth(1) end
        lines[i] = t
    end
    function lines:SetColor(c)
        for _, t in ipairs(self) do t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    end
    lines:SetColor(color)
    return lines
end

-- Shadows over a picture: dark at the top (for the name) and at the bottom (for the level and the counts).
local function Shades(holder, pic, height)
    local top = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
    top:SetTexture(Util.WHITE)
    top:SetPoint("TOPLEFT", pic)
    top:SetPoint("TOPRIGHT", pic)
    top:SetHeight(math.floor(height * 0.5))
    -- WoW: VERTICAL gradients go from minColor (bottom) to maxColor (top)
    local c = H.shade
    top:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 0.82))
    local bottom = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
    bottom:SetTexture(Util.WHITE)
    bottom:SetPoint("BOTTOMLEFT", pic)
    bottom:SetPoint("BOTTOMRIGHT", pic)
    bottom:SetHeight(math.floor(height * 0.42))
    bottom:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0.78), CreateColor(c[1], c[2], c[3], 0))
end

local function LevelText(inst)
    if inst.kind == "raid" then return F("%d players", inst.size or 40) end
    return F("Level %s", Kit.RangeText(inst.minLevel, inst.maxLevel))
end

local function OpenCard(f)
    local d = f.sheet.data[f.entry]
    if d and d.onClick then
        Util.PlaySound("IG_SPELLBOOK_OPEN")
        d.onClick(d)
    end
end

local function CardEnter(f)
    f.hovered = true
    f.edge:SetColor(H.title)
    local d = f.sheet.data[f.entry]
    if d then
        LJ.Tooltip.ShowInstance(f.card, d.inst)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("Click: open the dungeon."), 0.6, 0.62, 0.66, true)
        GameTooltip:Show()
    end
end

local function CardLeave(f)
    f.hovered = false
    f.edge:SetColor(f.edgeColor)
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Kinds of this page: the dungeon cards (the featured one and the grid), the boss rows
---------------------------------------------------------------------------
-- A dungeon card: its picture, the name at the top, the level at the bottom left, the upgrades for the character and
-- the quests at the bottom right, a bar in the level's color at the bottom edge. data = { inst, upgrades, quests, onClick }
Kit.KINDS.tile = {
    height = CARD_HEIGHT + GAP,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        local card = CreateFrame("Frame", nil, f)
        card:SetPoint("TOPLEFT")
        card:SetPoint("TOPRIGHT")
        card:SetHeight(CARD_HEIGHT)
        f.card = card
        f.pic = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.pic:SetPoint("TOPLEFT", 1, -1)
        f.pic:SetPoint("BOTTOMRIGHT", -1, 1)
        Shades(card, f.pic, CARD_HEIGHT)
        f.edgeColor = H.cardBorder
        f.edge = Edge(card, f.edgeColor)
        f.name = Widgets.Text(card, "h2", H.title)
        f.name:SetPoint("TOPLEFT", 11, -9)
        f.name:SetPoint("RIGHT", -10, 0)
        f.name:SetWordWrap(true)
        f.name:SetMaxLines(2)
        f.level = Widgets.Text(card, "small", C.text1)
        f.level:SetPoint("BOTTOMLEFT", 11, 11)
        f.quests = Widgets.CreatePill(card, 18, "pill")
        f.quests:SetPoint("BOTTOMRIGHT", -9, 8)
        f.ups = Widgets.CreatePill(card, 18, "pill")
        f.fit = card:CreateTexture(nil, "ARTWORK")
        f.fit:SetTexture(Util.WHITE)
        f.fit:SetHeight(3)
        f.fit:SetPoint("BOTTOMLEFT", 1, 1)
        f.fit:SetPoint("BOTTOMRIGHT", -1, 1)
        f:SetScript("OnEnter", CardEnter)
        f:SetScript("OnLeave", CardLeave)
        f:SetScript("OnClick", OpenCard)
        return f
    end,
    fill = function(f, d, w)
        local inst = d.inst
        local fallback = Theme.SetDungeonPicture(f.pic, inst, (w - 2) / (CARD_HEIGHT - 2))
        if fallback then
            local a = Theme.InstanceAccent(inst)
            f.pic:SetVertexColor(0.55 + a[1] * 0.45, 0.55 + a[2] * 0.45, 0.55 + a[3] * 0.45, 1)
        else
            f.pic:SetVertexColor(1, 1, 1, 1)
        end
        f.pic:SetDesaturated(inst.status == "announced")
        f.name:SetText(inst.name)
        f.level:SetText(LevelText(inst))
        local right = f.quests
        f.quests:SetShown((d.quests or 0) > 0)
        if (d.quests or 0) > 0 then f.quests:Set(tostring(d.quests), "art", "scroll") else right = nil end
        f.ups:SetShown((d.upgrades or 0) > 0)
        if (d.upgrades or 0) > 0 then
            f.ups:Set(tostring(d.upgrades), "artOk", "upgrade")
            f.ups:ClearAllPoints()
            if right then f.ups:SetPoint("RIGHT", right, "LEFT", -5, 0) else f.ups:SetPoint("BOTTOMRIGHT", -9, 8) end
        end
        local c = Theme.RangeColor(inst.minLevel, inst.maxLevel)
        f.fit:SetVertexColor(c[1], c[2], c[3], 1)
        f.fit:SetShown(inst.kind ~= "raid")
        f.hovered = f:IsMouseOver()
        f.edge:SetColor(f.hovered and H.title or f.edgeColor)
    end,
}

-- The featured dungeon: a wide picture with the name, its numbers for the character and a button to open it.
-- data = { inst, upgrades, quests, bis, onClick }
Kit.KINDS.feature = {
    height = FEATURE_HEIGHT + GAP + 4,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        local card = CreateFrame("Frame", nil, f)
        card:SetPoint("TOPLEFT")
        card:SetPoint("TOPRIGHT")
        card:SetHeight(FEATURE_HEIGHT)
        f.card = card
        f.pic = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.pic:SetPoint("TOPLEFT", 1, -1)
        f.pic:SetPoint("BOTTOMRIGHT", -1, 1)
        -- the left part dark for the texts, the bottom a little darker
        f.left = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        f.left:SetTexture(Util.WHITE)
        f.left:SetPoint("TOPLEFT", f.pic)
        f.left:SetPoint("BOTTOMLEFT", f.pic)
        local c = H.shade
        f.left:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], 0.93), CreateColor(c[1], c[2], c[3], 0))
        f.bottom = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        f.bottom:SetTexture(Util.WHITE)
        f.bottom:SetPoint("BOTTOMLEFT", f.pic)
        f.bottom:SetPoint("BOTTOMRIGHT", f.pic)
        f.bottom:SetHeight(math.floor(FEATURE_HEIGHT * 0.55))
        f.bottom:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0.45), CreateColor(c[1], c[2], c[3], 0))
        f.edgeColor = H.windowBorder
        f.edge = Edge(card, f.edgeColor)
        f.kicker = Widgets.Text(card, "small", Theme.accent)
        f.kicker:SetPoint("TOPLEFT", 22, -20)
        Theme.OnAccent(card, function(_, r, g, b) f.kicker:SetTextColor(r, g, b) end)
        f.name = Widgets.Text(card, "heroMid", H.title)
        f.name:SetPoint("TOPLEFT", f.kicker, "BOTTOMLEFT", 0, -6)
        f.meta = Widgets.Text(card, "bodySmall", C.text1)
        f.meta:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -5)
        f.chips = {}
        for i = 1, 3 do f.chips[i] = Widgets.CreatePill(card, 20, "pill") end
        f.open = Widgets.CreateButton(card, "Open dungeon", "primary", nil, nil, 28)
        f.open:SetPoint("BOTTOMRIGHT", -16, 16)
        f.open:SetScript("OnClick", function(b) OpenCard(b:GetParent():GetParent()) end)
        f.fit = card:CreateTexture(nil, "ARTWORK")
        f.fit:SetTexture(Util.WHITE)
        f.fit:SetHeight(3)
        f.fit:SetPoint("BOTTOMLEFT", 1, 1)
        f.fit:SetPoint("BOTTOMRIGHT", -1, 1)
        -- the card shows what the tooltip would: only the line lights up
        f:SetScript("OnEnter", function(self)
            self.hovered = true
            self.edge:SetColor(H.title)
        end)
        f:SetScript("OnLeave", function(self)
            self.hovered = false
            self.edge:SetColor(self.edgeColor)
        end)
        f:SetScript("OnClick", OpenCard)
        return f
    end,
    fill = function(f, d, w)
        local inst = d.inst
        Theme.SetInstanceArt(f.pic, inst, (w - 2) / (FEATURE_HEIGHT - 2))
        f.pic:SetVertexColor(1, 1, 1, 1)
        f.left:SetWidth(math.floor(w * 0.62))
        f.kicker:SetText(Util.Upper(L("Best for you right now")))
        f.name:SetText(Theme.Case(inst.name))
        local parts = { LevelText(inst), inst.zone or "" }
        if #inst.bosses > 0 then parts[#parts + 1] = Util.Plural(#inst.bosses, "boss", "bosses") end
        f.meta:SetText(table.concat(parts, "  ·  "))
        local defs = {}
        if (d.upgrades or 0) > 0 then defs[#defs + 1] = { Util.Plural(d.upgrades, "upgrade", "upgrades"), "artOk", "upgrade" } end
        if (d.quests or 0) > 0 then defs[#defs + 1] = { Util.Plural(d.quests, "quest", "quests"), "art", "scroll" } end
        local x = 0
        for i, chip in ipairs(f.chips) do
            local def = defs[i]
            chip:SetShown(def ~= nil)
            if def then
                chip:Set(def[1], def[2], def[3])
                chip:ClearAllPoints()
                chip:SetPoint("TOPLEFT", f.meta, "BOTTOMLEFT", x, -14)
                x = x + chip:GetWidth() + 8
            end
        end
        local c = Theme.RangeColor(inst.minLevel, inst.maxLevel)
        f.fit:SetVertexColor(c[1], c[2], c[3], 1)
        f.fit:SetShown(inst.kind ~= "raid")
        f.hovered = f:IsMouseOver()
        f.edge:SetColor(f.hovered and H.title or f.edgeColor)
    end,
}

-- The level of a boss for its badge: "??" stays, of a range the higher level.
local function BadgeLevel(level)
    if not level then return nil end
    level = tostring(level)
    if level == "??" or level == "999" then return "??" end
    return level:match("(%d+)$") or level
end

-- A square with a glyph in place of a portrait (trash, quest rewards).
local function CreateSquare(parent, size)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(size, size)
    s.fill = Widgets.CreateBox(s, "ARTWORK", 0, 4)
    s.fill:SetColor(H.badgeFill)
    s.ring = Widgets.CreateBox(s, "ARTWORK", 1, 4, true)
    s.ring:SetColor(H.cardBorder)
    s.glyph = Widgets.Glyph(s, "package", math.floor(size * 0.5), H.glyph, "ARTWORK", 2)
    s.glyph:SetPoint("CENTER")
    return s
end

-- A boss of the list: its portrait with the level, the name, Rare and the upgrades for the character at the right; the
-- picked one highlighted. data = { group (boss index, 0 trash, -1 quest rewards), boss, glyph, text, upgrades,
-- selected, onClick }
Kit.KINDS.boss = {
    height = BOSS_HEIGHT,
    create = function(parent)
        local f = CreateFrame("Button", nil, parent)
        Kit.AddMarks(f)
        local dy = Kit.RowDY()
        f.emblem = Widgets.CreateEmblem(f, 32)
        f.emblem:SetPoint("LEFT", 9, dy)
        f.badge = Kit.Badge(f, 17)
        f.badge:SetPoint("CENTER", f.emblem, "BOTTOMLEFT", 2, 3)
        f.square = CreateSquare(f, 32)
        f.square:SetPoint("LEFT", 9, dy)
        f.name = Widgets.Text(f, "item", C.text1)
        f.name:SetPoint("LEFT", f.emblem, "RIGHT", 12, 0)
        f.right = Widgets.Text(f, "smallSemi", C.text3, nil, "RIGHT")
        f.right:SetPoint("RIGHT", -10, dy)
        f:SetScript("OnEnter", function(self)
            self.hovered = true
            Kit.MarkVisual(self)
            local d = self.sheet.data[self.entry]
            if d and d.boss then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(d.boss.name, 1, 1, 1)
                if d.boss.level then GameTooltip:AddLine(F("Level %s", tostring(d.boss.level)), 0.8, 0.8, 0.8) end
                if d.boss.rare then GameTooltip:AddLine(L("Rare spawn"), 0.8, 0.82, 0.9) end
                GameTooltip:AddLine(L("Click to show the loot."), 0.6, 0.62, 0.66)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function(self)
            self.hovered = false
            Kit.MarkVisual(self)
            GameTooltip:Hide()
        end)
        f:SetScript("OnClick", function(self)
            local d = self.sheet.data[self.entry]
            if d and d.onClick then
                Util.PlaySound("IG_MAINMENU_OPTION")
                d.onClick(d)
            end
        end)
        return f
    end,
    fill = function(f, d, w)
        local level = d.boss and BadgeLevel(d.boss.level)
        f.emblem:SetShown(d.boss ~= nil)
        f.square:SetShown(d.boss == nil)
        f.badge:SetShown(level ~= nil)
        if d.boss then
            f.emblem:SetBoss(d.boss)
            f.badge.text:SetText(level or "")
        else
            Theme.SetGlyph(f.square.glyph, d.glyph or "package")
        end
        f.name:SetText(d.text)
        local c = d.selected and H.pickText or C.text1
        f.name:SetTextColor(c[1], c[2], c[3])
        local parts = {}
        if d.boss and d.boss.rare then parts[#parts + 1] = Theme.ColorText(L("Rare"), C.rare) end
        if (d.upgrades or 0) > 0 then
            parts[#parts + 1] = Theme.GlyphString("upgrade", 11, C.okText) .. " " .. Theme.ColorText(d.upgrades, C.okText)
        end
        f.right:SetText(table.concat(parts, "   "))
        local rightW = #parts > 0 and (Widgets.TextWidth(f.right) + 10) or 0
        f.name:SetWidth(math.max(40, w - 9 - 32 - 12 - 10 - rightW))
        f.selected = d.selected
        f.hovered = f:IsMouseOver()
        Kit.MarkVisual(f)
    end,
}

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------
function Page:Create(root)
    root = Kit.Page(root)
    self.tab = LJ.db.journal.tab
    self:CreateHome(root)
    self:CreateDungeon(root)
end

function Page:CreateHome(root)
    local home = CreateFrame("Frame", nil, root)
    home:SetAllPoints()
    self.home = home
    home.title = Widgets.Text(home, "title", H.title)
    home.title:SetPoint("TOPLEFT", 0, -2)
    home.sub = Widgets.Text(home, "bodySmall", C.text4)
    home.sub:SetPoint("TOPLEFT", home.title, "BOTTOMLEFT", 0, -5)
    self.kindTabs = Widgets.CreateTabs(home, {
        { key = "dungeon", text = "Dungeons" },
        { key = "raid", text = "Raids" },
    }, function(key) self:ShowHome(key) end, { font = "tab", height = 30, onLayout = function(bar) bar:SetWidth(bar.width) end })
    self.kindTabs:SetPoint("TOPRIGHT", 0, -6)
    self.nearToggle = Widgets.CreateToggle(home, "My level only", "Only the dungeons and raids for your level.")
    self.nearToggle:SetPoint("RIGHT", self.kindTabs, "LEFT", -16, 0)
    self.nearToggle.onChange = function(_, on)
        LJ.db.journal.filter = on and "NEAR" or "ALL"
        self:RefreshHome()
    end
    home.line = Kit.FadeLine(home, 0.55)
    home.line:SetPoint("TOPLEFT", 0, -50)
    home.line:SetPoint("TOPRIGHT", 0, -50)
    self.grid = Kit.Sheet(home, 4)
    self.grid.scroll:SetPoint("TOPLEFT", 0, -60)
    self.grid.scroll:SetPoint("BOTTOMRIGHT", -10, 0)
end

function Page:CreateDungeon(root)
    local view = CreateFrame("Frame", nil, root)
    view:SetAllPoints()
    self.view = view

    -- header: the dungeon's picture fading in from the left, name, level and the buttons
    local head = Kit.Panel(view, 0)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_HEIGHT)
    self.head = head
    head.art = head:CreateTexture(nil, "BACKGROUND", nil, 0)
    head.art:SetPoint("TOPLEFT", head, "TOP", -150, -1)
    head.art:SetPoint("BOTTOMRIGHT", -1, 1)
    head.shade = head:CreateTexture(nil, "BACKGROUND", nil, 1)
    head.shade:SetTexture(Util.WHITE)
    head.shade:SetAllPoints(head.art)
    local c = H.shade
    head.shade:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], 0.55), CreateColor(c[1], c[2], c[3], 0))
    -- back to all dungeons (all raids), above the name
    self.backButton = Kit.BackLink(head, function() UI:Open("home", self.inst.kind) end)
    self.backButton:SetPoint("TOPLEFT", 18, -15)
    head.title = Widgets.Text(head, "heroMid", H.title)
    head.title:SetPoint("TOPLEFT", 20, -31)
    head.meta = Widgets.Text(head, "bodySmall", C.text3)
    head.meta:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -6)
    self.entranceButton = Widgets.CreateButton(head, "Entrance", "ghost", "mapPin", nil, 30)
    Widgets.SetTooltip(self.entranceButton, "Dungeon entrance", "Shows the entrance on the world map.", "ANCHOR_BOTTOM")
    self.entranceButton:SetScript("OnClick", function()
        local inst = self.inst
        local entrance = inst.entrance
        if entrance then
            LJ.MapPin.Show({ map = entrance.map, x = entrance.x, y = entrance.y, title = inst.name, detail = L("Dungeon entrance") })
        end
    end)

    -- left: the Bosses | Quests switch over the bosses (or the quest list)
    local leftPanel = Kit.Panel(view)
    leftPanel:SetPoint("TOPLEFT", 0, -(HEAD_HEIGHT + GAP))
    leftPanel:SetPoint("BOTTOMLEFT")
    leftPanel:SetWidth(LEFT_WIDTH)
    self.leftPanel = leftPanel
    local left = leftPanel.inner
    -- the switch fills the panel's inner width (LEFT_WIDTH less the panel's padding of 12 on both sides)
    self.switch = Widgets.CreateTabs(left, TABS, function(key) self:SetTab(key) end,
        { font = "tab", height = SWITCH_HEIGHT, tabHeight = SWITCH_HEIGHT, fill = LEFT_WIDTH - 24 })
    self.switch:SetPoint("TOPLEFT")
    self.questControls = PQ.CreateControls(left, function() self:RefreshQuests() end)
    self.questControls.filter:SetPoint("TOPLEFT", 0, -(SWITCH_HEIGHT + 12))
    self.left = Kit.Sheet(left, 4)
    self.left.scroll:SetPoint("BOTTOMRIGHT", -8, 0)

    -- right: the picked boss and its loot, or the picked quest
    local rightPanel = Kit.Panel(view)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", GAP, 0)
    rightPanel:SetPoint("BOTTOMRIGHT")
    self.rightPanel = rightPanel
    local right = rightPanel.inner
    self:CreateLootHead(right)
    self.right = Kit.Sheet(right, 4)
    self.right.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    self:CreateBossModel(right)
end

-- Beside the loot: the picked boss as its 3D model, moving as it stands in the game; drag it to turn it.
local function ModelTurn(m)
    local x = GetCursorPosition()
    m.rotation = m.rotation + (x - m.lastX) * 0.012
    m.lastX = x
    m:SetFacing(m.rotation)
end

function Page:CreateBossModel(pane)
    local model = CreateFrame("PlayerModel", nil, pane)
    model:SetPoint("TOPRIGHT", 0, -(LOOT_HEAD + 8))
    model:SetPoint("BOTTOMRIGHT")
    model:SetWidth(MODEL_WIDTH)
    model:SetKeepModelOnHide(true)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(m, button)
        if button ~= "LeftButton" then return end
        m.lastX = GetCursorPosition()
        m:SetScript("OnUpdate", ModelTurn)
    end)
    -- released or hidden mid-drag: the turning stops
    local function StopTurn(m) m:SetScript("OnUpdate", nil) end
    model:SetScript("OnMouseUp", StopTurn)
    model:SetScript("OnHide", StopTurn)
    model:Hide()
    self.model = model
end

-- The model of a boss beside its loot; none for trash and quest rewards or without a model in the game's data (its
-- place stays: the loot keeps its width).
function Page:SetBossModel(boss)
    local display = boss and boss.display
    local model = self.model
    model:SetShown(display ~= nil)
    if not display or model.display == display then return end
    -- a little turned toward its loot
    model.display, model.rotation = display, -0.4
    model:SetDisplayInfo(display)
    model:SetFacing(model.rotation)
end

-- Above the loot: the picked boss's name and numbers (its portrait is in the list) and the loot filters.
function Page:CreateLootHead(pane)
    local head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(LOOT_HEAD)
    self.lootHead = head
    head.name = Widgets.Text(head, "titleSmall", C.text1)
    head.name:SetPoint("TOPLEFT", 2, -4)
    head.sub = Widgets.Text(head, "bodySmall", C.text4)
    head.sub:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -6)
    head.line = Kit.FadeLine(head, 0.55)
    head.line:SetPoint("BOTTOMLEFT", 0, 2)
    head.line:SetPoint("BOTTOMRIGHT", 0, 2)
    local db = LJ.db.lootFilter
    self.upgrades = Kit.Toggle(head, "Upgrades only", "Only items that are an upgrade for your character.", function(on)
        db.spec = on and "UPGRADE" or "ALL"
        self:RefreshRight()
    end)
    -- the filters at the top right, beside the name: the line below it has the whole width
    self.upgrades:SetPoint("TOPRIGHT", 0, -3)
    self.usable = Kit.Toggle(head, "Usable by me", "Only items your character can use.", function(on)
        db.spec = on and "MINE" or "ALL"
        self:RefreshRight()
    end)
    self.usable:SetPoint("RIGHT", self.upgrades, "LEFT", -12, 0)
end

---------------------------------------------------------------------------
-- Journal home: the dungeon cards
---------------------------------------------------------------------------
function Page:ShowHome(kind)
    self.mode = "home"
    self.kind = (kind == "raid" or kind == "dungeon") and kind or self.kind or "dungeon"
    self.home:Show()
    self.view:Hide()
    Theme.SetAccent(C.defaultAccent)
    self:RefreshHome()
end

-- The cards: the instance with the most upgrades for the character on top, the others for the level below it, then
-- the next ones coming up ("My level only") or all the others by level (Classic and new Forever ones together).
function Page:RefreshHome()
    local kind = self.kind or "dungeon"
    self.kindTabs:Select(kind)
    local isRaid = kind == "raid"
    self.home.title:SetText(Theme.Case(L(isRaid and "Raids" or "Dungeons")))
    self.home.sub:SetText(L(isRaid and "Pick a raid for its bosses, loot and quests" or "Pick a dungeon for its bosses, loot and quests"))
    local nearOnly = LJ.db.journal.filter == "NEAR"
    self.nearToggle:SetChecked(nearOnly)
    local level = Player.level or 1
    local near, coming, others = {}, {}, {}
    local open = function(d) UI:Open("instance", d.inst.key) end
    for _, inst in ipairs(LJ.instancesByKind[kind] or {}) do
        local d = { inst = inst, onClick = open }
        if inst.status ~= "announced" then d.quests = Lists.OpenQuests(inst) end
        if Lists.IsNear(inst) and inst.status ~= "announced" then
            d.upgrades = Lists.CountFor(inst)
            near[#near + 1] = d
        elseif nearOnly then
            if inst.minLevel > level and inst.status ~= "announced" then coming[#coming + 1] = d end
        else
            others[#others + 1] = d
        end
    end
    -- the featured one: the best (as For you picks it: Lists.Better)
    local feature
    for _, d in ipairs(near) do
        if not feature or Lists.Better(d, feature) then feature = d end
    end
    local sheet = self.grid
    sheet:Reset(UI.FRAME_WIDTH - 60)
    local function Section(text, sub, list, max)
        if #list == 0 then return end
        if max and #list > max then
            local cut = {}
            for i = 1, max do cut[i] = list[i] end
            list = cut
        end
        sheet:Add("section", { text = text, count = sub })
        sheet:Grid("tile", list, COLUMNS, CARD_HEIGHT + GAP, GAP)
    end
    -- the featured one big on top, and in the tiles for the level too (the banner alone is easy to overlook)
    if feature then sheet:Add("feature", feature) end
    Section(L("For your level"), F("Level %d", level), near)
    local function ByLevel(a, b)
        if a.inst.minLevel ~= b.inst.minLevel then return a.inst.minLevel < b.inst.minLevel end
        return a.inst.name < b.inst.name
    end
    if nearOnly then
        table.sort(coming, ByLevel)
        for _, d in ipairs(coming) do d.upgrades = Lists.CountFor(d.inst) end
        Section(L("Coming up"), L("a few levels above you"), coming, COLUMNS)
    else
        table.sort(others, ByLevel)
        Section(L(isRaid and "Raids" or "Dungeons"), #others, others)
    end
    if sheet.n == 0 then
        sheet:Add("empty", { title = L("Nothing for your level"), text = L("No dungeon or raid fits your level. Turn off \"My level only\" to see all of them."), glyph = "castle" })
    end
    sheet:Finish(10)
end

---------------------------------------------------------------------------
-- A dungeon
---------------------------------------------------------------------------
-- quest: the quest to show on the Quests tab (set after the dungeon changed, which forgets the last one)
function Page:OpenInstance(key, tab, group, quest)
    local inst = LJ.instanceByKey[key]
    if not inst then return self:ShowHome() end
    local changed = self.inst ~= inst
    self.inst = inst
    self.mode = "instance"
    UI.state.instKey = key
    UI.state.kind = inst.kind
    LJ.db.journal.last[inst.kind] = key
    LJ.db.journal.lastKey = key
    Theme.SetAccent(Theme.InstanceAccent(inst))
    if changed then
        self.group = nil
        self.quest, self.questRow = nil, nil
        self.left:ScrollToTop()
        self.right:ScrollToTop()
    end
    if group ~= nil then self.group = group end
    if self.group == nil then self.group = (#inst.bosses > 0) and 1 or 0 end
    if quest then self.quest, self.questRow = quest, quest end
    self.home:Hide()
    self.view:Show()
    self:RefreshHead()
    self:SetTab(tab or self.tab or "loot")
    -- a boss picked from elsewhere (a link, the search) is in view in the list
    local y = group ~= nil and self.groupY and self.groupY[group]
    if y then
        local view = self.left.scroll:GetHeight() or 0
        local top = self.left.scroll:GetVerticalScroll()
        if y < top or y + BOSS_HEIGHT > top + view then self.left:Reveal(y, math.floor(view / 3)) end
    end
end

-- The header: picture, the link back, name, level, zone, group size, the map and entrance buttons.
function Page:RefreshHead()
    local inst = self.inst
    local head = self.head
    Theme.SetInstanceArt(head.art, inst, math.max(1, (head.art:GetWidth() or 600)) / (HEAD_HEIGHT - 2))
    head.art:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.95))
    head.art:SetDesaturated(inst.status == "announced")
    head.title:SetText(Theme.Case(inst.name))
    local parts = { LevelText(inst) }
    if inst.zone and inst.zone ~= "" then parts[#parts + 1] = inst.zone end
    if inst.kind ~= "raid" then parts[#parts + 1] = F("%d players", inst.size or 5) end
    head.meta:SetText(table.concat(parts, "   |   "))
    self.backButton:SetLabel(inst.kind == "raid" and "All raids" or "All dungeons")
    self.entranceButton:SetShown(inst.entrance ~= nil)
    self.entranceButton:ClearAllPoints()
    self.entranceButton:SetPoint("RIGHT", -16, 0)
end

-- key: "loot" (the bosses and the picked one's loot) or "quests"
function Page:SetTab(key)
    if not self.inst then return end
    if key ~= "quests" then key = "loot" end
    self.tab = key
    LJ.db.journal.tab = key
    self.switch:Select(key)
    self:RefreshLeft()
    self:RefreshRight()
end

-- Picks a boss: its loot on the right.
function Page:SelectGroup(group)
    self.group = group
    self.tab = "loot"
    self.switch:Select("loot")
    self.right:ScrollToTop()
    self:RefreshLeft()
    self:RefreshRight()
end

-- The groups of the boss list: the bosses, then trash and quest rewards when the dungeon has them.
function Page:Groups()
    return Lists.BuildGroups(self.inst)
end

-- The upgrades for the character among a group's items (the items of its Best in Slot list).
local function CountUpgrades(g)
    local n = 0
    for _, e in ipairs(g.entries) do
        if BiS.Upgrade(e.id) then n = n + 1 end
    end
    return n
end

function Page:RefreshLeft()
    local inst = self.inst
    local quests = self.tab == "quests"
    self.switch:SetCount("loot", #inst.bosses)
    self.switch:SetCount("quests", Quests.CountForInstance(inst.key))
    self.questControls.filter:SetShown(quests)
    self.left.scroll:SetPoint("TOPLEFT", 0, -(SWITCH_HEIGHT + 10 + (quests and 38 or 0)))
    local sheet = self.left
    sheet:Reset(LEFT_WIDTH - 32)
    if quests then
        self.questControls:Update()
        local list, rowY = PQ.FillList(sheet, inst, self.questRow, function(qid) self:SelectQuest(qid) end)
        self.questList, self.questRowY = list, rowY
        sheet:Finish()
        return
    end
    local groups = self:Groups()
    local pick = function(d) self:SelectGroup(d.group) end
    self.groupY = {}
    for _, g in ipairs(groups) do
        local d = { group = g.index, selected = self.group == g.index, onClick = pick,
            upgrades = CountUpgrades(g) }
        if g.kind == "boss" then
            d.boss, d.text = g.boss, g.boss.name
        elseif g.kind == "trash" then
            if self.groupY[0] == nil then sheet:Space(4) end
            d.glyph, d.text = "package", L("Trash & zone drops")
        else
            d.glyph, d.text = "scroll", L("Quest rewards")
        end
        self.groupY[g.index] = sheet.cursor
        sheet:Add("boss", d)
    end
    if #groups == 0 then
        sheet:Add("empty", { title = L("Bosses not revealed yet"), text = L("The bosses and their loot are added as soon as they are seen in the game or revealed."), glyph = "hourglass" })
    end
    sheet:Finish(8)
end

-- The group to show on the right (falls back to the first one).
function Page:CurrentGroup(groups)
    for _, g in ipairs(groups) do
        if g.index == self.group then return g end
    end
    return groups[1]
end

function Page:RefreshRight()
    local loot = self.tab == "loot"
    self.lootHead:SetShown(loot)
    self.right.scroll:SetPoint("TOPLEFT", 0, -(loot and (LOOT_HEAD + 8) or 0))
    -- the loot leaves the boss's place on the right, a quest has the whole width
    self.right.scroll:SetPoint("BOTTOMRIGHT", loot and -(MODEL_WIDTH + 12) or -8, 0)
    if loot then
        self:RefreshLoot()
    else
        self:SetBossModel(nil)
        self:RefreshQuestDetail()
    end
end

-- The loot head for a group: the boss's name (or trash / quest rewards) and its numbers.
function Page:SetLootHead(g, sub)
    local head = self.lootHead
    if g and g.boss then
        head.name:SetText(g.boss.name)
    else
        local trash = g and g.kind == "trash"
        head.name:SetText(g and L(trash and "Trash & zone drops" or "Quest rewards") or self.inst.name)
    end
    head.sub:SetText(sub or "")
    local width = head:GetWidth() or 600
    local room = width - (self.usable:GetWidth() + (self.upgrades:IsShown() and self.upgrades:GetWidth() + 12 or 0) + 12)
    head.name:SetWidth(0)
    head.name:SetWidth(math.max(60, math.min(Widgets.TextWidth(head.name) + 2, room)))
    head.sub:SetWidth(math.max(60, width))
end

function Page:RefreshLoot()
    local inst = self.inst
    local db = LJ.db.lootFilter
    -- the Best in Slot module off: no "Upgrades only" (its filter shows everything), "Usable by me" at the right
    local bis = LJ.Modules.On("bis")
    if db.spec == "UPGRADE" and not bis then db.spec = "ALL" end
    self.upgrades:SetShown(bis)
    self.usable:ClearAllPoints()
    if bis then
        self.usable:SetPoint("RIGHT", self.upgrades, "LEFT", -12, 0)
    else
        self.usable:SetPoint("TOPRIGHT", 0, -3)
    end
    self.usable:SetChecked(db.spec == "MINE")
    self.upgrades:SetChecked(db.spec == "UPGRADE")
    local groups = self:Groups()
    local g = self:CurrentGroup(groups)
    self:SetBossModel(g and g.boss)
    local sheet = self.right
    sheet:Reset(560)
    if not g then
        self:SetLootHead(nil, "")
        sheet:Add("empty", { title = L("Bosses not revealed yet"), text = L("The bosses and their loot are added as soon as they are seen in the game or revealed."), glyph = "hourglass" })
        sheet:Finish()
        return
    end
    self.group = g.index
    local spec = Player:GetActiveSpec()
    local cells, upgrades = {}, 0
    for _, e in ipairs(g.entries) do
        local d = Kit.ItemData(e.id, spec)
        if d.upgrade then upgrades = upgrades + 1 end
        if Lists.PassesClass(Items.Get(e.id), db.spec, d.upgrade) then
            if g.kind == "quests" then
                d.sub = e.questName
                d.tag = e.isChoice and "CHOICE" or "REWARD"
                d.questID = e.questID
                d.onClick = function(x) UI:Open("quest", x.questID) end
            else
                d.chance = e.chance
                if e.label then
                    d.sub = e.label
                    d.extraTooltip = d.extraTooltip or {}
                    table.insert(d.extraTooltip, 1, { F("Drops from: %s", e.label), 0.97, 0.78, 0.27 })
                end
            end
            cells[#cells + 1] = d
        end
    end
    local count = #g.entries
    local parts = {}
    if g.kind == "boss" then
        local bosses = #inst.bosses
        if g.boss.rare then parts[#parts + 1] = L("Rare spawn") else parts[#parts + 1] = F("Boss %d of %d", g.index, bosses) end
    end
    parts[#parts + 1] = (#cells == count) and Util.Plural(count, g.kind == "quests" and "reward" or "drop")
        or F(g.kind == "quests" and "%d of %d rewards" or "%d of %d drops", #cells, count)
    if upgrades > 0 then
        parts[#parts + 1] = Theme.ColorText(F(upgrades == 1 and "%s upgrade for you" or "%s upgrades for you", upgrades), C.okText)
    end
    self:SetLootHead(g, table.concat(parts, "  ·  "))
    if count == 0 then
        sheet:Add("empty", { title = L("No drops recorded"), text = L((inst.status == "pending" or inst.status == "announced")
            and "No drops recorded yet. Loot is added as soon as it is seen or revealed." or "No drops recorded for this encounter."), glyph = "hourglass" })
    elseif #cells == 0 then
        local onlyUpgrades = db.spec == "UPGRADE"
        sheet:Add("empty", { title = L(onlyUpgrades and "No upgrades here" or "No items match"),
            text = L(onlyUpgrades and "Nothing here is an upgrade for your character right now." or "Nothing in this instance fits the current filters."),
            glyph = "funnel", button = "Reset filters", buttonGlyph = "reset", onClick = function()
                db.spec = "ALL"
                self:RefreshRight()
            end })
    else
        sheet:Grid("item", cells, 1, Kit.M().item)
    end
    sheet:Finish(10)
end

---------------------------------------------------------------------------
-- Quests (both panels)
---------------------------------------------------------------------------
-- Shows a quest: a row of the list (it becomes the picked row), or a step of the shown quest's chain (step: the row
-- that holds the chain stays picked).
function Page:SelectQuest(qid, step)
    self.quest = qid
    if not step then self.questRow = qid end
    if self.tab ~= "quests" then
        self:SetTab("quests")
        return
    end
    self:RefreshLeft()
    self:RefreshQuestDetail()
    self.right:ScrollToTop()
end

function Page:RefreshQuests()
    self:RefreshLeft()
    self:RefreshQuestDetail()
end

function Page:RefreshQuestDetail()
    local sheet = self.right
    sheet:Reset(560)
    -- nothing picked: the first quest of the list
    if not (self.quest and Quests.Get(self.quest)) and self.questList and self.questList[1] then
        self.quest = self.questList[1].id
        self.questRow = self.quest
        self:RefreshLeft()
    end
    PQ.FillDetail(sheet, self.quest, self.inst, function(qid) self:SelectQuest(qid, true) end)
    sheet:Finish(12)
end

---------------------------------------------------------------------------
-- Page interface
---------------------------------------------------------------------------
-- mode: "home" (kind) | "instance" (key, bossIndex) | "quest" (questID)
function Page:Show(mode, a, b)
    if mode == "instance" then
        if b ~= nil then
            self:OpenInstance(a, "loot", b)
        else
            self:OpenInstance(a)
        end
        return
    end
    if mode == "quest" then
        local q = Quests.Get(a)
        local instKey = q and q.inst and q.inst[1] or (self.inst and self.inst.key) or LJ.db.journal.lastKey
        if not LJ.instanceByKey[instKey] then instKey = LJ.Data.Instances[1] and LJ.Data.Instances[1].key end
        self:OpenInstance(instKey, "quests", nil, a)
        -- the quest's row in view
        local y = self.questRowY and self.questRowY[a]
        if y then self.left:Reveal(y, 60) end
        return
    end
    self:ShowHome(a)
end

function Page:Refresh()
    if self.mode == "instance" and self.inst then
        Theme.SetAccent(Theme.InstanceAccent(self.inst))
        self:RefreshHead()
        self:RefreshLeft()
        self:RefreshRight()
    else
        self:RefreshHome()
    end
end

---------------------------------------------------------------------------
-- The tour (UI/Tour.lua)
---------------------------------------------------------------------------
-- Shows what a step of the tour explains. what: "journal" (the start page), "loot" (the boss with the best upgrade
-- for the character); key: the tour's dungeon.
function Page:TourShow(what, key)
    if what == "journal" then
        UI:Open("home", "dungeon")
        return
    end
    UI:Open("instance", key)
    self.left:ScrollToTop()
    self.right:ScrollToTop()
end

-- Map buttons show "Marked" for the spot on the map: redraw the quest when the mark changes.
LJ:Listen("MAP_TARGET_CHANGED", function()
    if Page.root and Page.root:IsVisible() and Page.mode == "instance" and Page.tab == "quests" then Page:RefreshQuestDetail() end
end)

UI:RegisterPage("journal", Page, { "modern", "classic" })
