-- Lootified - the tour: a spotlight over the real window, one short step per part of the addon (the pages of the modules
-- that are on, a dungeon's map, the Best in Slot sheet's filter and sim buttons, search; in the database look its
-- search, filters, table, details and tabs), then the settings window category by category. Its first step runs the
-- Best in Slot sim, which goes on while the tour does (the progress window shows it).
-- It starts once by itself, the first time the player opens the window outside combat and instances
-- (LootifiedData.tourDone), and again from the options or with /lf tour. Tour.New makes a tour of another window with the
-- same spotlight and text box (the dungeon map, the simulator and the filter's panel explain themselves).
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local Player = LJ.Player
local C = Theme.COLORS

local Tour = { active = false, index = 0, time = 0 }
Tour.all = { Tour }   -- this tour and the ones made with Tour.New
UI.Tour = Tour

local BOX_WIDTH = 336
local PAD = 16
local GAP = 12           -- between the spotlight and the text box
local EDGE = 12          -- the text box keeps this far from the edges of the dimmed area
local DIM = 0.62
local START_DELAY = 0.4  -- after the window opened: its page is laid out and faded in
local ACTION_GAP = 10    -- between a step's action button and the buttons below it

---------------------------------------------------------------------------
-- What the steps show
---------------------------------------------------------------------------
-- The dungeon of the journal steps: of those around the character's level (as "My level" in the list), the one with
-- the most upgrades; else the first dungeon with known bosses.
local function PickInstance()
    local level = Player.level or 1
    local best, bestCount, first
    for _, inst in ipairs(LJ.instancesByKind.dungeon or {}) do
        if #inst.bosses > 0 then
            first = first or inst
            if inst.minLevel <= level + 3 and inst.maxLevel >= level - 2 then
                local count = LJ.Lists.CountFor(inst)
                if not best or count > bestCount then
                    best, bestCount = inst, count
                end
            end
        end
    end
    return best or first or (LJ.instancesByKind.dungeon or {})[1]
end

local function Journal() return UI.pages.journal end

local function Content() return UI.frame.content end

-- title, text: shown in the box. enter(tour): brings up what the step shows. target(tour): the frames the spotlight goes around (nil: everything
-- dimmed). place: "inside" puts the box into the spotlight (whole pages), otherwise it goes next to it. interactive:
-- the spotlight lets the mouse through (else the page below does not react). pad: spotlight margin around the target.
-- action(): a button above the others ({ text, glyph, onClick }), nil: none.
-- The spec the Best in Slot sim runs for from the tour: the character's, when the simulator builds its list (a damage
-- spec).
local function SimSpec()
    local spec = Player:GetActiveSpec()
    if LJ.Modules.On("bis") and UI.Sim.RanksItems(spec) then return spec end
end
local function SimRuns(spec)
    local run = LJ.SimBiS.running
    return run ~= nil and run.spec.key == spec.key
end
-- What Alt+Click on an item does (the upgrade check: UI/ItemCheckBox.lua): "sim" the item fights (Sim), "share" its
-- upgrade in percent by the stat weights (Percent); nil with the check off.
local function AltClick()
    local spec = Player:GetActiveSpec()
    if not (spec and LJ.db.upgradeCheck and LJ.Modules.On("bis")) then return nil end
    return UI.Sim.RanksItems(spec) and "sim" or "share"
end
local WELCOME = {
    title = "Welcome to Lootified",
    -- the upgrades and the Best in Slot items only with their module; the Best in Slot sim for the specs the simulator
    -- plays: to start, or that it runs
    text = function()
        if not LJ.Modules.On("bis") then
            return L("This is For you, your start page: the dungeons for your level. Click anything to open it.")
        end
        local text = L("This is For you, your start page: the dungeons for your level with your upgrades and your next Best in Slot items. Click anything to open it.")
        local spec = SimSpec()
        if not spec then return text end
        if SimRuns(spec) then
            return text .. "\n\n" .. L("The Best in Slot sim is running: the small window shows how far it is. Take the tour meanwhile; your list is ready when it is done.")
        end
        return text .. "\n\n" .. L("Start the Best in Slot sim here: it builds your list from every item you can wear while you take the tour (a few minutes).")
    end,
    -- the button that runs the Best in Slot sim: with Sim only (Percent has none), not while it runs
    action = function()
        local spec = SimSpec()
        if not spec or SimRuns(spec) then return nil end
        return { text = "Best in Slot sim", glyph = "lightning",
            onClick = function() UI.SimSpeed:Then(function() LJ.SimBiS.Start(spec) end) end }
    end,
    enter = function() UI:Open("foryou") end,
    target = Content, place = "inside", pad = 0,
}
-- For you is off: the start page is another module's
local WELCOME_PLAIN = {
    title = "Welcome to Lootified",
    text = "This tour shows every part of Lootified. At the end you see the settings, where you can switch off what you do not need.",
    enter = function() UI:Open("start") end,
    target = Content, place = "inside", pad = 0,
}
local WORLD = {
    title = "Open World",
    text = "The rares and other mobs of every zone with their drops, drop chances and camps on the map. The page shows the zone you are in.",
    enter = function() UI:Open("world") end,
    target = Content, place = "inside", pad = 0,
}
local BIS = {
    title = "Best in Slot",
    -- the damage specs: the sim builds the list, else it comes from the spec's stat weights; a click on an item swaps
    -- it (an own set takes it), Alt+Click checks any item
    text = function()
        local text = SimSpec()
            and L("Your Best in Slot list on your character: the Best in Slot sim builds it from every item you can wear. An item's tooltip says where it drops.")
            or L("Your Best in Slot list on your character, from the stat weights of your spec. An item's tooltip says where it drops.")
        text = text .. " " .. L("Click an item to swap it for another one: an own set takes it and shows what it adds.")
        local alt = AltClick()
        if alt == "sim" then
            text = text .. " " .. L("Alt+Click sims any item against what you wear, also in your bags, the loot window and chat.")
        elseif alt == "share" then
            text = text .. " " .. L("Alt+Click any item, also in your bags, the loot window and chat, for its upgrade in percent by your stats.")
        end
        return text
    end,
    enter = function() UI:Open("bis") end,
    target = Content, place = "inside", pad = 0,
}
-- the filter's button above the character; its panel explains itself the first time it opens (UI/ListFilter.lua). The
-- Stat priority tab only where it counts (Percent: Core/StatPrio.lua)
local FILTER = {
    title = "Filter",
    text = function()
        local spec = Player:GetActiveSpec()
        return spec and LJ.StatPrio.Counts(spec)
            and L("The filter of your Best in Slot list: the spec it is made for, the armor it takes and where its items may come from; its second tab orders your stats. Open it any time: the first time it explains itself.")
            or L("The filter of your Best in Slot list: the spec it is made for, the armor it takes and where its items may come from. Open it any time: the first time it explains itself.")
    end,
    enter = function() UI:Open("bis") end,
    target = function() return UI.pages.bis.filterButton end,
    pad = 6,
}
-- the sheet's two buttons: the Best in Slot sim, the simulator with everything else (the window explains itself the
-- first time: UI/SimWindow.lua)
local SIMULATOR = {
    title = "Simulator",
    text = function()
        return F(L("Best in Slot sim builds your list again after new gear or a level; it says \"%s\" while your list fits. Open simulator holds the rest: your character's damage, your own sets and the sets side by side. It explains itself the first time you open it."),
            L("Up to date"))
    end,
    enter = function() UI:Open("bis") end,
    target = function() return UI.pages.bis.bisButton, UI.pages.bis.simButton end,
    pad = 6,
}
local WISHLIST = {
    title = "Wishlist",
    text = "The items you starred, grouped by where they drop. You get an alert as soon as one drops.",
    enter = function() UI:Open("wishlist") end,
    target = Content, place = "inside", pad = 0,
}
local SEARCH = {
    title = "Search",
    text = "Search any item, boss, rare or quest here. The results show as you type.",
    enter = function() end,
    target = function() return UI.frame.search end,
    interactive = true,
}

-- The journal steps (the journal pages of UI/Pane/): the journal page shows what a step explains (Page:TourShow) and
-- names the frame the map step points at (Page:TourTarget).
local function PaneShow(what)
    return function(tour) Journal():TourShow(what, tour.inst.key) end
end
local PANE_JOURNAL = {
    title = "Journal",
    -- Alt+Click checks the loot
    text = function()
    local text = L("Every dungeon and raid as a picture: the best one for you on top, the others below (\"My level only\" shows the ones for your level). A dungeon shows its bosses on the left and the picked boss's loot on the right. Quests are next to Bosses.")
        local alt = AltClick()
        if alt == "sim" then
            text = text .. " " .. L("Alt+Click an item in the loot to sim it against what you wear.")
        elseif alt == "share" then
            text = text .. " " .. L("Alt+Click an item in the loot for its upgrade in percent by your stats.")
        end
        return text
    end,
    enter = PaneShow("journal"),
    target = Content, place = "inside", pad = 0,
}
-- The database look: its Items page shows the parts every page has (search, filters, table, details), then the tabs and
-- the options.
local function ItemsPage() return UI.pages.items end
local DB_WELCOME = {
    title = "Welcome to the Database",
    text = "Look everything up here: every item, mob, quest and place Lootified knows, with filters and details. This is the Items page.",
    enter = function() UI:Open("items") end,
    target = Content, place = "inside", pad = 0,
}
local DB_SEARCH = {
    title = "Search and sort",
    text = "Type a name, a slot or a place: the list follows as you type. The switch beside it and Sort change what shows and in which order.",
    enter = function() UI:Open("items") end,
    target = function() return ItemsPage().search, ItemsPage().sort end,
    interactive = true,
}
local DB_FILTERS = {
    title = "Filters",
    text = "Narrow the list down: slot, quality, required level and where an item comes from. Your filters are kept.",
    enter = function() UI:Open("items") end,
    target = function() return ItemsPage().filterPanel end,
    interactive = true,
}
local DB_TABLE = {
    title = "Results",
    -- the green arrow with Best in Slot (with the damage the sim found for the damage specs), Alt+Click with the check on
    text = function()
        local parts = {}
        local alt = AltClick()
        if LJ.Modules.On("bis") then
            parts[1] = UI.Sim.RanksItems(Player:GetActiveSpec())
                and L("The green arrow marks the items of your Best in Slot list, with the damage they add (sort by For you to see the biggest first).")
                or L("The green arrow marks the items of your Best in Slot list (sort by For you to see the best first).")
        end
        if alt == "sim" then
            parts[#parts + 1] = L("Click a row for its details; Alt+Click sims an item against what you wear, right-click for more.")
        elseif alt == "share" then
            parts[#parts + 1] = L("Click a row for its details; Alt+Click shows an item's upgrade in percent by your stats, right-click for more.")
        else
            parts[#parts + 1] = L("Click a row for its details, right-click for more.")
        end
        return table.concat(parts, " ")
    end,
    enter = function() UI:Open("items") end,
    target = function() return ItemsPage().tablePanel end,
    interactive = true,
}
local DB_DETAIL = {
    title = "Details",
    -- the wishlist button only with its module (else Try on is the main button)
    text = function()
        if LJ.Modules.On("wishlist") then
            return L("The picked item: its stats, where it drops (click a mob or a quest to open it) and the wishlist button. You get an alert when a wishlist item drops.")
        end
        return L("The picked item: its stats and where it drops (click a mob or a quest to open it).")
    end,
    enter = function() UI:Open("items") end,
    target = function() return ItemsPage().detail end,
    interactive = true,
}
local DB_TABS = {
    title = "Mobs, Quests and Places",
    text = "The same for bosses and rares, for quests (with their chains) and for dungeons, raids and zones. Links between the pages open the right entry.",
    enter = function() UI:Open("items") end,
    target = function() return UI.frame.nav end,
    interactive = true,
}
local DATABASE_STEPS = { DB_WELCOME, DB_SEARCH, DB_FILTERS, DB_TABLE, DB_DETAIL, DB_TABS }

-- The settings window, one category per step (every look ends with them). settings: the category the step shows.
local function SettingsWindow() return UI.Settings:Frame() end
local function SettingsStep(key, title, text)
    return { title = title, text = text, settings = key,
        enter = function() UI.Settings:Open(key, true) end,
        target = function() return SettingsWindow().body end }
end
local SETTINGS_STEPS = {
    { title = "Settings", settings = "general",
      text = "The gear button at the top right opens the settings. Pick a category on the left; every change applies at once.",
      enter = function() UI.Settings:Open("general", true) end,
      target = function() return SettingsWindow().side end },
    SettingsStep("modules", "Modules",
        "Switch off the pages you do not use. Best in Slot and Wishlist also take their marks, tooltip lines and alerts with them. One module always stays on."),
    SettingsStep("look", "Look & color", "Modern, Classic or Database, and the layout color: automatic, your class color or one you pick."),
    SettingsStep("tooltips", "Tooltips", "The lines Lootified adds to item tooltips, one switch each. The preview shows a real tooltip as you set it."),
    SettingsStep("map", "Map & alerts", "The dungeon entrances on the world map, the alert when a wishlist item drops and opening the dungeon you are in."),
    SettingsStep("help", "Language, tour and help",
        "The language is under Language; this tour starts again from Tour & help or with /lf tour. The Lootified Continued GitHub project is linked here and behind the ? at the top. Have fun!"),
}

-- The steps for the look and the modules that are on.
local function BuildSteps()
    local steps = {}
    local function Add(step) steps[#steps + 1] = step end
    if Theme.IsDatabase() then
        for _, step in ipairs(DATABASE_STEPS) do Add(step) end
    else
        local On = LJ.Modules.On
        Add(On("foryou") and WELCOME or WELCOME_PLAIN)
        if On("journal") then
            Add(PANE_JOURNAL)
        end
        if On("world") then Add(WORLD) end
        if On("bis") then
            Add(BIS)
            Add(FILTER)
            -- Sim: the sheet's Best in Slot sim and simulator buttons (in Percent the sheet has no Best in Slot sim)
            if UI.Sim.RanksItems(Player:GetActiveSpec()) then Add(SIMULATOR) end
        end
        if On("wishlist") then Add(WISHLIST) end
        Add(SEARCH)
    end
    for _, step in ipairs(SETTINGS_STEPS) do Add(step) end
    return steps
end
Tour.BuildSteps = BuildSteps
Tour.steps = {}

---------------------------------------------------------------------------
-- The overlay (made for each window: a new look builds a new window)
---------------------------------------------------------------------------
local function SwallowWheel() end

local function CreateOverlay(tour, frame)
    local ui = { frame = frame }
    local overlay = CreateFrame("Frame", nil, frame)
    -- a layer above the window and its dialogs (the settings, the simulator: the dialog layer). Frame levels inside a
    -- layer move when the game raises the window it was clicked in, so a level above them would not hold; the progress
    -- window and the sim speed question (the fullscreen dialog layer) stay above the tour
    overlay:SetFrameStrata("FULLSCREEN")
    local base = frame:GetFrameLevel() + 300
    overlay:SetFrameLevel(base)
    -- the window and what hangs out of it (its clamp insets)
    local l, r, t, b = frame:GetClampRectInsets()
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", math.min(0, l or 0), math.max(0, t or 0))
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", math.max(0, r or 0), math.min(0, b or 0))
    overlay:Hide()
    ui.overlay = overlay

    -- four panes dim everything around the spotlight; they take the mouse, so nothing below them reacts
    ui.dims = {}
    for i = 1, 4 do
        local pane = CreateFrame("Frame", nil, overlay)
        pane:SetFrameLevel(base + 1)
        pane:EnableMouse(true)
        pane:EnableMouseWheel(true)
        pane:SetScript("OnMouseWheel", SwallowWheel)
        pane.fill = Widgets.Solid(pane, "BACKGROUND", 0, C.black or { 0, 0, 0 }, DIM)
        pane.fill:SetAllPoints()
        ui.dims[i] = pane
    end

    -- the spotlight: a glow and a ring in the layout color; the mouse goes through to what it shows
    local hole = CreateFrame("Frame", nil, overlay)
    hole:SetFrameLevel(base + 3)
    hole:EnableMouse(false)
    hole.glow = Widgets.CreateShadow(hole, 12, 0.35)
    hole.glow[5]:Hide()
    hole.ring = Widgets.CreateBox(hole, "OVERLAY", 0, 8, true)
    hole.ring:SetAnchor(hole, -1, -1, -1, -1)
    ui.hole = hole

    -- over the spotlight of steps that only show a page: the page does not react while the text explains it
    local block = CreateFrame("Frame", nil, overlay)
    block:SetFrameLevel(base + 2)
    block:EnableMouse(true)
    block:EnableMouseWheel(true)
    block:SetScript("OnMouseWheel", SwallowWheel)
    block:SetAllPoints(hole)
    ui.block = block

    -- the text box
    local box = CreateFrame("Frame", nil, overlay)
    box:SetFrameLevel(base + 10)
    box:SetWidth(BOX_WIDTH)
    box:EnableMouse(true)
    Widgets.CreateShadow(box, 18, 0.85)
    box.panel = Widgets.CreatePopupPanel(box, 12)
    box.count = Widgets.Text(box, "label", C.text4)
    box.count:SetPoint("TOPLEFT", PAD, -PAD)
    box.title = Widgets.Text(box, "h2", C.white)
    box.title:SetPoint("TOPLEFT", PAD, -(PAD + 17))
    box.title:SetWidth(BOX_WIDTH - PAD * 2)
    box.text = Widgets.Text(box, "body", C.text2)
    box.text:SetPoint("TOPLEFT", PAD, -(PAD + 41))
    box.text:SetWidth(BOX_WIDTH - PAD * 2)
    box.text:SetWordWrap(true)
    box.text:SetSpacing(2)

    -- a step's action (the welcome step runs the Best in Slot sim): above the other buttons
    box.action = Widgets.CreateButton(box, "", "primary", nil, nil, 26)
    box.action:SetPoint("BOTTOMLEFT", PAD, 12 + 26 + ACTION_GAP)
    box.action:SetScript("OnClick", function(btn)
        Util.PlaySound("IG_MAINMENU_OPTION")
        btn.handler()
    end)
    box.next = Widgets.CreateButton(box, "Next", "primary", nil, nil, 26)
    box.next:SetPoint("BOTTOMRIGHT", -12, 12)
    box.next:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        if tour.index >= #tour.steps then
            tour:Finish()
        else
            tour:Go(tour.index + 1)
        end
    end)
    box.back = Widgets.CreateButton(box, "Previous", "ghost", nil, nil, 26)
    box.back:SetPoint("RIGHT", box.next, "LEFT", -6, 0)
    box.back:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        if tour.index > 1 then tour:Go(tour.index - 1) end
    end)
    box.skip = Widgets.CreateButton(box, "Skip tour", "ghost", nil, nil, 26)
    box.skip:SetPoint("BOTTOMLEFT", 10, 12)
    box.skip:SetScript("OnClick", function()
        Util.PlaySound("IG_MAINMENU_OPTION")
        tour:Stop(true)
    end)
    ui.box = box

    Theme.OnAccent(box, function(_, cr, cg, cb)
        box.count:SetTextColor(cr, cg, cb, 1)
        box.panel:SetBorder(cr, cg, cb, 0.45)
        hole.ring:SetColor(cr, cg, cb, 1)
        for i, piece in ipairs(hole.glow) do
            if i ~= 5 then piece:SetVertexColor(cr, cg, cb, 0.35) end
        end
    end)

    overlay:SetScript("OnUpdate", function(_, elapsed) tour:Update(elapsed) end)
    return ui
end

-- The window the tour shows (Tour.New: the window it was made for).
function Tour:Host() return UI:CreateMainFrame() end

function Tour:EnsureOverlay()
    local frame = self:Host()
    if not (self.ui and self.ui.frame == frame) then self.ui = CreateOverlay(self, frame) end
    return self.ui
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- The frames' rectangle in the overlay's coordinates (origin bottom left); nil when none of them is on screen.
local function TargetRect(overlay, ...)
    local ol, ob = overlay:GetLeft(), overlay:GetBottom()
    if not (ol and ob) then return nil end
    local os = overlay:GetEffectiveScale()
    local l, r, t, b
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        local fl, fr, ft, fb = f and f:IsVisible() and f:GetLeft(), f and f:GetRight(), f and f:GetTop(), f and f:GetBottom()
        if fl and fr and ft and fb then
            local k = f:GetEffectiveScale() / os
            fl, fr, ft, fb = fl * k - ol, fr * k - ol, ft * k - ob, fb * k - ob
            l, r = math.min(l or fl, fl), math.max(r or fr, fr)
            t, b = math.max(t or ft, ft), math.min(b or fb, fb)
        end
    end
    return l, r, t, b
end

local function Place(region, overlay, x, y, w, h)
    region:ClearAllPoints()
    if w <= 0.5 or h <= 0.5 then
        region:Hide()
        return
    end
    region:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x, y)
    region:SetSize(w, h)
    region:Show()
end

-- Sets the text box to a width; its height follows the text.
local function FitBox(box, width)
    if box.fitWidth == width then return end
    box.fitWidth = width
    box:SetWidth(width)
    box.title:SetWidth(width - PAD * 2)
    box.text:SetWidth(width - PAD * 2)
    local action = box.action:IsShown() and 26 + ACTION_GAP or 0
    box:SetHeight(math.floor(PAD + 41 + box.text:GetStringHeight() + 18 + action + 26 + 12 + 0.5))
end

-- the narrowest box its buttons fit in
local function MinBoxWidth(box)
    return 10 + box.skip:GetWidth() + 12 + box.back:GetWidth() + 6 + box.next:GetWidth() + 12
end

-- The text box: next to the spotlight where it fits (below, above, right, left), narrower beside it when only a
-- side has room (a page that fills the window's height), inside it for whole pages or when nothing else fits, in the
-- middle without a spotlight.
local function PlaceBox(box, overlay, l, r, t, b, inside)
    FitBox(box, BOX_WIDTH)
    local W, H = overlay:GetWidth(), overlay:GetHeight()
    local w, h = box:GetWidth(), box:GetHeight()
    local function ClampX(x) return math.max(EDGE, math.min(W - EDGE - w, x)) end
    local function ClampY(y) return math.max(EDGE, math.min(H - EDGE - h, y)) end
    local x, y
    if not l then
        x, y = (W - w) / 2, (H - h) / 2
    else
        local cx, cy = (l + r - w) / 2, (t + b - h) / 2
        if inside then
            x, y = ClampX(cx), ClampY(b + 16)
        elseif b - GAP - h >= EDGE then
            x, y = ClampX(cx), b - GAP - h
        elseif t + GAP + h <= H - EDGE then
            x, y = ClampX(cx), t + GAP
        elseif r + GAP + w <= W - EDGE then
            x, y = r + GAP, ClampY(cy)
        elseif l - GAP - w >= EDGE then
            x, y = l - GAP - w, ClampY(cy)
        else
            local right, left = W - EDGE - r - GAP, l - GAP - EDGE
            local side = math.floor(math.max(right, left))
            if side >= MinBoxWidth(box) then
                FitBox(box, side)
                h = box:GetHeight()
                x, y = right >= left and r + GAP or EDGE, ClampY((t + b - h) / 2)
            else
                x, y = ClampX(cx), ClampY(b + 16)
            end
        end
    end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", math.floor(x + 0.5), math.floor(y + 0.5))
end

function Tour:Layout(l, r, t, b)
    local ui = self.ui
    local overlay, dims = ui.overlay, ui.dims
    local W, H = overlay:GetWidth(), overlay:GetHeight()
    local step = self.steps[self.index]
    if l then
        local pad = step.pad or 4
        l, r = math.max(0, l - pad), math.min(W, r + pad)
        t, b = math.min(H, t + pad), math.max(0, b - pad)
        if r - l < 1 or t - b < 1 then l = nil end
    end
    if not l then
        Place(dims[1], overlay, 0, 0, W, H)
        for i = 2, 4 do dims[i]:Hide() end
        ui.hole:Hide()
        ui.block:Hide()
    else
        Place(dims[1], overlay, 0, t, W, H - t)      -- above
        Place(dims[2], overlay, 0, 0, W, b)          -- below
        Place(dims[3], overlay, 0, b, l, t - b)      -- left
        Place(dims[4], overlay, r, b, W - r, t - b)  -- right
        Place(ui.hole, overlay, l, b, r - l, t - b)
        ui.block:SetShown(not step.interactive)
    end
    PlaceBox(ui.box, overlay, l, r, t, b, step.place == "inside")
    self.rect = l and { l, r, t, b } or nil
end

-- Every frame while the tour shows: the spotlight follows its target (layouts settle, lists scroll, the window
-- moves) and the ring pulses softly.
function Tour:Update(elapsed)
    if not self.active then return end
    self.time = self.time + (elapsed or 0)
    local ui = self.ui
    local step = self.steps[self.index]
    local l, r, t, b = TargetRect(ui.overlay, step.target(self))
    local last = self.last
    if not last or last[1] ~= l or last[2] ~= r or last[3] ~= t or last[4] ~= b or last[5] ~= ui.overlay:GetWidth() then
        self.last = { l, r, t, b, ui.overlay:GetWidth() }
        self:Layout(l, r, t, b)
    end
    -- the ring pulses softly
    ui.hole.ring:SetAlpha(0.6 + 0.4 * math.sin(self.time * 4) ^ 2)
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
function Tour:FillBox()
    local box = self.ui.box
    local step = self.steps[self.index]
    box.count:SetText(F("%d / %d", self.index, #self.steps))
    box.title:SetText(L(step.title))
    box.text:SetText(type(step.text) == "function" and step.text() or L(step.text))
    local action = step.action and step.action()
    box.action:SetShown(action ~= nil)
    if action then
        box.action.handler = action.onClick
        box.action:SetGlyph(action.glyph)
        box.action:SetLabel(action.text)
    end
    local last = self.index == #self.steps
    box.next:SetLabel(last and "Done" or "Next")
    box.back:SetShown(self.index > 1)
    box.skip:SetShown(not last)
    -- the text changed: measured again at the full width (Tour:Layout may narrow it)
    box.fitWidth = nil
    FitBox(box, BOX_WIDTH)
end

function Tour:Go(index)
    self.index = index
    self.time = 0
    self.last = nil
    local step = self.steps[index]
    -- the settings window shows only for its own steps
    if self == Tour and not step.settings then UI.Settings:Close() end
    if step.enter then LJ:SafeCall(step.enter, self) end
    self:FillBox()
    self:Update(0)
end

-- Shows the overlay at the first step.
function Tour:Begin()
    local ui = self:EnsureOverlay()
    self.active = true
    ui.overlay:Show()
    self:Go(1)
end

function Tour:Start()
    if self.active then return end
    if UI.LayoutPicker:AskFirst(function() self:Start() end) then return end
    self:EnsureOverlay()
    self.steps = BuildSteps()
    self.inst = not Theme.IsDatabase() and LJ.Modules.On("journal") and PickInstance() or nil
    -- the simulator and the filter's panel explain themselves again the next time they open
    LJ.db.simTour = nil
    LJ.db.filterTour = nil
    UI:Open("start")
    self:Begin()
end

-- The tour counts as seen: it does not start by itself again.
function Tour:Seen()
    LJ.db.tourDone = true
end

-- done: the tour counts as seen
function Tour:Stop(done)
    if done then self:Seen() end
    if not self.active then return end
    self.active = false
    if self.ui then self.ui.overlay:Hide() end
    GameTooltip:Hide()
    if self == Tour then UI.Settings:Close() end
end

-- Done on the last step: the tour counts as seen; the main tour ends on the start page (For you, else the first page
-- that is on).
function Tour:Finish()
    self:Stop(true)
    if self == Tour then UI:Open("start") end
end

-- A tour of another window: def = { host = function() return frame end, steps = { ... },
-- seen = function(tour) (the tour ended: its steps count as seen) }. Steps as in STEPS; the tour runs with Begin.
-- It takes this tour's methods, never its state: the filter's panel shares the main window, and this tour's overlay
-- (its buttons drive this tour) would have become its own.
local function Method(_, key)
    local v = Tour[key]
    if type(v) == "function" then return v end
end

function Tour.New(def)
    local tour = setmetatable({ active = false, index = 0, time = 0, steps = def.steps or {} }, { __index = Method })
    tour.Host = function() return def.host() end
    tour.Seen = function(t) if def.seen then def.seen(t) end end
    Tour.all[#Tour.all + 1] = tour
    return tour
end

-- The window opened: the first time (outside combat and instances) the tour starts by itself.
function Tour:OnWindowShown()
    if self.active or self.pending or LJ.db.tourDone then return end
    self.pending = true
    C_Timer.After(START_DELAY, function()
        self.pending = false
        local frame = UI.frame
        if self.active or LJ.db.tourDone or not (frame and frame:IsShown()) then return end
        if InCombatLockdown() then return end
        local _, kind = GetInstanceInfo()
        if kind == "party" or kind == "raid" then return end
        self:Start()
    end)
end

-- Closing the window (or a new look replacing it) ends the tour; it counts as seen.
function Tour:OnWindowHidden(frame)
    if self.active and self.ui and self.ui.frame == frame then self:Stop(true) end
end

-- The Best in Slot sim started or ended while a step with an action shows (the welcome step): its box follows.
LJ:Listen("SIM_BIS_CHANGED", function()
    local step = Tour.active and Tour.steps[Tour.index]
    if not (step and step.action) then return end
    Tour:FillBox()
    Tour.last = nil
    Tour:Update(0)
end)

-- A fight ends a tour at once (the window may stay open); it is not marked as seen.
LJ:On("PLAYER_REGEN_DISABLED", function()
    for _, tour in ipairs(Tour.all) do
        if tour ~= Tour and tour.active then tour:Stop(false) end
    end
    if not Tour.active then return end
    Tour:Stop(false)
    LJ:Print("The tour stopped because of combat. /lf tour starts it again.")
end)
