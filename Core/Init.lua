-- Lootified - Core initialisation: namespace, saved variables, events, slash commands.
local ADDON_NAME, LJ = ...

LJ.ADDON_NAME = ADDON_NAME
LJ.TITLE = "Lootified"
LJ.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")   -- the toc's version
-- Forever Lite intentionally uses the lightweight stat-priority scorer. The embedded combat
-- simulator remains in the source backup for now, but is never selected or started.
LJ.NO_SIM = true
LJ.Data = LJ.Data or {}
LJ.UI = LJ.UI or {}
LJ.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- Expose a single global for key bindings, the addon compartment and debugging.
_G.LootifiedAddon = LJ

---------------------------------------------------------------------------
-- Interface text in the chosen language. LJ.uiText (English text -> translated text) is set by Core/Locale.lua when
-- a language other than English is used; without it every text stays English. Texts are looked up when they are
-- shown, so tables made while the files load keep the English text and are translated where they are displayed.
---------------------------------------------------------------------------
function LJ.L(s)
    local t = LJ.uiText
    return t and s and t[s] or s
end

-- string.format with a translated format string
function LJ.F(fmt, ...)
    return string.format(LJ.L(fmt), ...)
end

-- The game client runs in English: item tooltip lines can be read with the addon's English patterns
-- (Core/Scoring.lua). Clients in other languages use the item stats shipped with the addon instead.
LJ.ENGLISH_CLIENT = not GetLocale or (GetLocale() or ""):sub(1, 2) == "en"

local L, F = LJ.L, LJ.F

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------
local PREFIX = "|cffe6c07bLootified|r"

function LJ:Print(msg, ...)
    if type(msg) == "string" then msg = LJ.L(msg) end
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. ": " .. tostring(msg))
end

function LJ:Debug(msg, ...)
    if self.db and self.db.debug then
        if select("#", ...) > 0 then
            msg = string.format(msg, ...)
        end
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " |cff888888[debug]|r " .. tostring(msg))
    end
end

---------------------------------------------------------------------------
-- Error handling
-- Errors are never swallowed: they are forwarded to the game's error handler
-- (the Blizzard error frame or whatever replaces it) and kept in LJ.errors for /lf errors.
-- Execution of other handlers continues, so one bug cannot break the addon.
---------------------------------------------------------------------------
LJ.errors = {}

-- Keeps a report for /lf errors (newest first, the last 50).
local function KeepError(text)
    table.insert(LJ.errors, 1, { time = date and date("%H:%M:%S") or "", text = text })
    if #LJ.errors > 50 then
        table.remove(LJ.errors)
    end
end

function LJ:ReportError(err)
    local text = tostring(err)
    KeepError(text)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(text)
    end
end

local function ErrorHandler(err)
    LJ:ReportError(err)
    return err
end

-- Calls fn(...) and reports (does not hide) any error. Returns ok, results...
-- The arguments go through a reused slot per call depth instead of a new table and closure per call: game
-- events such as GET_ITEM_INFO_RECEIVED fire constantly (for every addon's items) and would pile up garbage.
local callDepth = 0
local callSlots = {}
local function InvokeSlot()
    local slot = callSlots[callDepth]
    return slot.fn(unpack(slot, 1, slot.n))
end
local function FinishCall(...)
    local slot = callSlots[callDepth]
    for i = 1, slot.n do slot[i] = nil end
    slot.fn = nil
    callDepth = callDepth - 1
    return ...
end
function LJ:SafeCall(fn, ...)
    local n = select("#", ...)
    if n == 0 then
        return xpcall(fn, ErrorHandler)
    end
    callDepth = callDepth + 1
    local slot = callSlots[callDepth]
    if not slot then
        slot = {}
        callSlots[callDepth] = slot
    end
    slot.fn, slot.n = fn, n
    for i = 1, n do slot[i] = (select(i, ...)) end
    return FinishCall(xpcall(InvokeSlot, ErrorHandler))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Registers handler(event, ...) for a game event.
function LJ:On(event, handler)
    local list = eventHandlers[event]
    if not list then
        eventFrame:RegisterEvent(event)
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        LJ:SafeCall(list[i], event, ...)
    end
end)

---------------------------------------------------------------------------
-- Actions the game blocked. The AddOn list only counts them ("Interface actions failed because of this AddOn"); the
-- events name the function. Both events fire while the blocked call runs, so the call stack shows where it came from.
-- Each one is kept for /lf errors and announced in chat (the game shows its own message too, so it does not go to the
-- Lua error handler).
---------------------------------------------------------------------------
local lastBlockNotice

-- The call stack without the addon's own event dispatch at its top.
local function BlockedCallStack()
    local lines = {}
    for line in debugstack(2, 20, 0):gmatch("[^\n]+") do
        if #lines > 0 or not (line:find("Core[/\\]Init%.lua") or line:find("^%[C%]")) then
            lines[#lines + 1] = line
            if #lines >= 8 then break end
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

local function OnActionBlocked(event, addon, func)
    if addon ~= ADDON_NAME then return end
    local text = string.format("%s: %s", event == "ADDON_ACTION_FORBIDDEN" and "Action forbidden by the game"
        or "Action blocked by the game", tostring(func))
    local stack = BlockedCallStack()
    KeepError(stack and (text .. "\n" .. stack) or text)
    local now = GetTime()
    if not lastBlockNotice or now - lastBlockNotice > 10 then
        lastBlockNotice = now
        LJ:Print("The game blocked an action of Lootified (%s). /lf errors shows the details.", tostring(func))
    end
end
LJ:On("ADDON_ACTION_BLOCKED", OnActionBlocked)
LJ:On("ADDON_ACTION_FORBIDDEN", OnActionBlocked)

---------------------------------------------------------------------------
-- Internal message bus
---------------------------------------------------------------------------
local listeners = {}

function LJ:Listen(message, handler)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], handler)
end

function LJ:Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        self:SafeCall(list[i], message, ...)
    end
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local pendingDebounce = {}   -- [key] = { due = time, fn = function }

-- Runs fn once, delay seconds after the last call with the same key. Frequent calls (quest log and item
-- events fire a lot) only move the due time of the one waiting timer: no new timer or closure per call.
function LJ:Debounce(key, delay, fn)
    local now = GetTime()
    local p = pendingDebounce[key]
    if p then
        p.due, p.fn = now + delay, fn
        return
    end
    p = { due = now + delay, fn = fn }
    pendingDebounce[key] = p
    local function Check()
        local left = p.due - GetTime()
        if left > 0.01 then
            C_Timer.After(left, Check)
            return
        end
        pendingDebounce[key] = nil
        LJ:SafeCall(p.fn)
    end
    C_Timer.After(delay, Check)
end

-- Fires an internal message once, delay seconds after the last request (the message is the debounce key).
local fireMessage = {}
function LJ:FireDebounced(message, delay)
    local fn = fireMessage[message]
    if not fn then
        fn = function() LJ:Fire(message) end
        fireMessage[message] = fn
    end
    self:Debounce(message, delay, fn)
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
LJ.defaults = {
    debug = false,
    minimap = { hide = false, angle = 208 },
    tooltipSource = true,
    tooltipWishlist = true,
    tooltipUpgrade = true,      -- "+3.1 DPS for <spec>" on the tooltips of the Best in Slot list's items
    wishlistAlerts = true,
    upgradeCheck = true,        -- the box beside every loot roll and Alt+Click on an item: an upgrade for me? (UI/ItemCheckBox.lua)
    autoOpenInstance = true,
    worldMapEntrances = true,   -- dungeon entrances on the game's world map (UI/WorldMapPins.lua)
    modules = { foryou = true, journal = true, world = true, bis = true, wishlist = true },   -- the pages that are on
                                                                                          -- (Core/Modules.lua)
    scale = 1.0,
    position = nil,
    tooltipQuests = true,
    lootFilter = { spec = "ALL" },   -- the Loot tab's filter (Lists.PassesClass)
    journal = { filter = "ALL", tab = "loot", last = {}, questFilter = "MINE" },
    world = { upgradesOnly = false, zones = "NEAR" },   -- Open World page: "Upgrades only"; zone list: "NEAR" (for my
                                                        -- level) | "ALL"
    -- the simulator's window (UI/SimWindow.lua): tab shown ("own" | "plan" | "sets" | "slots"; set when it opens),
    -- compared slot (nil: the spec's weapon), the own set the planner shows (1 or 2), target level above the player's,
    -- fight length (s; not the sim Best in Slot's: Sim/SimBiS.lua), the window's size (size = { w, h }; nil: the
    -- smallest, 900 x 600) and center on the screen in pixels (pos = { x, y }; nil: the middle), the planner's picker
    -- with the items of higher levels (higher)
    sim = { tab = "own", set = 1, target = 0, length = 60, higher = false },
    -- layout color: "auto" (follows the page: dungeon art, class on Best in Slot) | "class" (my class) |
    -- "fixed" (color = hex "RRGGBB", a preset or picked in the color picker)
    accent = { mode = "auto", color = "E8B04B" },
    skin = "modern",            -- window look: "modern" (dark glass) | "classic" (dark leather) | "database" (the
                                -- lookup pages: items, mobs, quests, places)
    layoutChosen = false,       -- the player picked a look in the layout picker (it shows once; UI/LayoutPicker.lua)
    language = "auto",          -- addon language: "auto" (the client's language when the addon has it, else
                                -- English) | "enUS" | one of LJ.Locale.LANGUAGES (needs /reload)
    tourDone = false,           -- the tour was seen (it starts by itself until then; UI/Tour.lua)
    questRewards = {},          -- [questID] = { xp, xpLevel, money }: as the game stated them (Core/Quests.lua)
}

LJ.charDefaults = {
    spec = {},        -- [classFile] = chosen spec key
    -- rating: how this character's items are rated, "percent" or "sim" (UI/RatingPicker.lua: asked after the look, on
    -- every other character at its login); nil until picked
    wishlist = {},    -- [itemID] = { t = time(), inst = key }
    simBiS = {},      -- the simulator's Best in Slot list: [specKey] = what every slot simmed (Sim/SimBiS.lua)
    plans = { {}, {} },   -- the planner's own sets: [n] = { [sheet slot] = itemID }, only what the player put in
                              -- (UI/SimWindow.lua)
    planNames = {},       -- their names: [n] = text (nil: "Set n")
    setsOff = {},         -- the sets the simulator's Sets tab leaves out of Sim: [key] = true ("sheet", "set1", ...)
    itemSims = {},        -- what single items did against what was worn: [specKey] = { [item key] = { delta, err,
                          -- slot, setup, level } } (Sim/ItemCheck.lua)
    simOwn = {},          -- the simulator's Character tab, its last numbers: [specKey] = { base, stats, foot, length,
                          -- target, level, setup } (UI/SimWindow.lua)
    -- where the Best in Slot list's items may come from and the armor it takes (Items.InList; the first start and the
    -- Best in Slot page's filter change it: UI/ListFilter.lua): realistic until then, no crafted items (the professions
    -- are the player's to pick), no random world drops, drops of 10 % or more (chance: the least drop chance in %, 0:
    -- every drop), every armor kind the class wears
    list = { quests = true, dungeons = true, rare = true, crafted = false, world = false, chance = 10,
        cloth = true, leather = true, mail = true, plate = true },
    statPrio = {},        -- the stat priority the player dragged: [specKey] = { order, factor }; none: the spec's own
                          -- (Core/StatPrio.lua)
}

-- The Database look's filters, switches and sort per page: every login and /reload starts with these (they are not
-- saved; UI/Database/Kit.lua keeps them for the session). A choice switched off is false, not nil.
LJ.DATABASE_DEFAULTS = {
    items = { sort = "foryou", slot = "ALL", usable = false, level = { 1, 60 },
        quality = { true, true, true, true },
        sources = { dungeon = true, raid = true, rare = true, world = true, quest = true, other = true } },
    mobs = { sort = "level", upgrades = false, level = { 1, 60 },
        kinds = { boss = true, rare = true, elite = true, normal = true },
        where = { dungeon = true, raid = true, world = true } },
    quests = { sort = "status", level = { 1, 60 }, reward = "ANY",
        status = { READY = true, ACTIVE = true, AVAILABLE = true, LOCKED = true, LOW_LEVEL = true, COMPLETED = true,
            OTHER = true },
        where = { dungeon = true, raid = true, world = true } },
    places = { sort = "level", near = false, level = { 1, 60 },
        kinds = { dungeon = true, raid = true, zone = true } },
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Usable defaults from the very first line of code, even if SavedVariables
-- never load (known Forever beta issue in some builds).
LJ.db = CopyDefaults(LJ.defaults, {})
LJ.cdb = CopyDefaults(LJ.charDefaults, {})

-- Saved under the names of 1.9.4 (Lootified.toc): what earlier versions saved as LootifiedDB / LootifiedCharDB is never
-- read, every player started fresh with 1.9.4 (the game keeps only the toc's variables at the next logout).
LJ:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    LootifiedData = CopyDefaults(LJ.defaults, LootifiedData)
    LootifiedCharData = CopyDefaults(LJ.charDefaults, LootifiedCharData)
    -- as many own sets as the defaults have (1.9.20 took Set 3 out): one saved beyond them goes
    local plans = #LJ.charDefaults.plans
    for n = plans + 1, #LootifiedCharData.plans do
        LootifiedCharData.plans[n], LootifiedCharData.planNames[n], LootifiedCharData.setsOff["set" .. n] = nil, nil, nil
    end
    if LootifiedData.sim.set > plans then LootifiedData.sim.set = 1 end
    -- the Character tab's numbers of 1.0.2 and before (no setup) and a tank's of 1.0.3 and 1.0.4 (threat) go
    for key, own in pairs(LootifiedCharData.simOwn) do
        if not own.setup or own.base.tank then LootifiedCharData.simOwn[key] = nil end
    end
    -- the names and simulator data /lf collect read up to 1.0.11 (the pipeline reads the game's tables since 1.0.12)
    LootifiedData.gameNames, LootifiedData.gameSim = nil, nil
    -- the notes next to the folded class list of the Best in Slot page up to 1.4.7 (it has none since 1.4.8)
    LootifiedData.hints = nil
    -- the stat priority of 1.6.0 (only the order; 1.6.1 keeps what each drag made of a stat: statPrio)
    LootifiedCharData.statOrder = nil
    -- "Only good drops" of earlier versions (on: 10 %, off: every drop) is the drop chance now
    local list = LootifiedCharData.list
    if list.good ~= nil then
        list.chance = list.good and LJ.charDefaults.list.chance or 0
        list.good = nil
    end
    LJ.db = LootifiedData
    LJ.cdb = LootifiedCharData
    -- Migrate old characters away from the discontinued simulator mode. Percent scoring provides
    -- the upgrade percentages and level-aware lists without running combat simulations.
    LJ.cdb.rating = "percent"
    LJ:Fire("DB_READY")
end)

LJ:On("PLAYER_LOGIN", function()
    -- key binding labels in the chosen language (the translation table is ready after DB_READY)
    BINDING_NAME_LOOTIFIED_TOGGLE = L("Open / close Lootified")
    BINDING_NAME_LOOTIFIED_BIS = L("Open Best in Slot")
    LJ:Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- /lf items: what the item data loading does (for bug reports)
---------------------------------------------------------------------------
function LJ:PrintItemStatus()
    local Items = self.Items
    local c = self.db.itemCache
    local saved, withStats, missing = 0, 0, 0
    for _, e in pairs(c and c.items or {}) do
        saved = saved + 1
        if e.s then withStats = withStats + 1 end
    end
    for _ in pairs(c and c.missing or {}) do missing = missing + 1 end
    self:Print("Item data (game %s):", c and c.key or "?")
    self:Print("  Saved: %d items (%d with stats), %d marked missing; loaded from the last session: %d",
        saved, withStats, missing, Items.savedCount or 0)
    local shipped = self.Data.ItemStats
    self:Print("  Built into the addon: %d items, %d without server data (game %s)", Items.bakedCount or 0,
        shipped and #(shipped.missing or {}) or 0, shipped and shipped.build or "-")
    local st = Items.netStats
    self:Print("  Server this session: %d requests (%d repeated), %d answers, %d answers without data",
        st.requests, st.repeats, st.answers, st.noData)
    for i = 1, math.min(8, #st.noDataIDs) do
        local id = st.noDataIDs[i]
        self:Print("  no data: %d %s", id, Items.GetName(id))
    end
end

---------------------------------------------------------------------------
-- Public entry points (used by bindings, minimap, compartment)
---------------------------------------------------------------------------
function LJ:Toggle()
    if self.UI.Toggle then
        self.UI:Toggle()
    end
end

function LJ:Open(page, arg1, arg2)
    if self.UI.Open then
        self.UI:Open(page, arg1, arg2)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "|cffffd200/lf|r - open or close the window",
    "|cffffd200/lf start|r - the start page",
    "|cffffd200/lf settings|r - the settings: modules, look, tooltips, language",
    "|cffffd200/lf bis|r - Best in Slot for your character",
    "|cffffd200/lf wishlist|r - your wishlist",
    "|cffffd200/lf raids|r - raid overview",
    "|cffffd200/lf search <text>|r - search every boss and item",
    "|cffffd200/lf <dungeon>|r - open a dungeon directly (dm, wc, sfk, bfd, hot, rol, brd, strat ...)",
    "|cffffd200/lf tour|r - a short tour of Lootified",
    "|cffffd200/lf minimap|r - show/hide the minimap button",
    "|cffffd200/lf reset|r - reset the window position and scale",
    "|cffffd200/lf color|r - layout color back to automatic (set it in the settings)",
    "|cffffd200/lf modern|r / |cffffd200/lf classic|r / |cffffd200/lf database|r - switch the window look (also in the settings)",
    "|cffffd200/lf look|r - compare the looks and pick one",
    "|cffffd200/lf errors|r - show recent Lootified errors",
    "|cffffd200/lf items|r - item data status (saved, server requests, waiting items)",
    "|cffffd200/lf memory|r - memory Lootified uses, with and without garbage the game has not cleaned up yet",
    "|cffffd200/lf debug|r - toggle debug output",
    "|cffffd200/lf status|r - show client and Lootified data versions",
}

function LJ:HandleSlash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        self:Toggle()
    elseif cmd == "help" or cmd == "?" then
        self:Print("v%s commands:", self.VERSION)
        for _, line in ipairs(HELP) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. L(line))
        end
    elseif cmd == "start" or cmd == "foryou" or cmd == "you" then
        self:Open(cmd == "start" and "start" or "foryou")
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        LJ.UI.Settings:Open()
    elseif cmd == "bis" then
        self:Open("bis")
    elseif cmd == "sim" then
        self:Print("Percent scoring is enabled in Lootified.")
    elseif cmd == "export" then
        self:Print("Character export is disabled in Lootified.")
    elseif cmd == "wishlist" or cmd == "wish" or cmd == "wl" then
        self:Open("wishlist")
    elseif cmd == "raids" or cmd == "raid" then
        self:Open("home", "raid")
    elseif cmd == "dungeons" or cmd == "dungeon" or cmd == "home" then
        self:Open("home", "dungeon")
    elseif cmd == "search" or cmd == "find" then
        self:Open("search", rest)
    elseif cmd == "tour" or cmd == "tutorial" then
        self.UI.Tour:Start()
    elseif cmd == "minimap" then
        self.db.minimap.hide = not self.db.minimap.hide
        self:Fire("SETTINGS_CHANGED", "minimap")
        self:Print("Minimap button %s.", self.db.minimap.hide and L("hidden") or L("shown"))
    elseif cmd == "classic" or cmd == "modern" or cmd == "database" then
        self.UI:ApplySkin(cmd)
        self.db.layoutChosen = true
        self:Print("Look: %s.", L(self.UI.LookName(cmd)))
    elseif cmd == "look" or cmd == "looks" or cmd == "layout" then
        self.UI.LayoutPicker:Show()
    elseif cmd == "color" or cmd == "colour" then
        self.db.accent.mode = "auto"
        self:Fire("SETTINGS_CHANGED", "accent")
        self:Print("Layout color: automatic (follows the page).")
    elseif cmd == "reset" then
        self.db.position = nil
        self.db.scale = 1.0
        self.db.sim.size, self.db.sim.pos = nil, nil
        self:Fire("SETTINGS_CHANGED", "position")
        self:Print("Window position and scale reset.")
    elseif cmd == "debug" then
        self.db.debug = not self.db.debug
        self:Print("Debug output %s.", self.db.debug and L("enabled") or L("disabled"))
    elseif cmd == "errors" then
        if #self.errors == 0 then
            self:Print("No errors recorded this session.")
        else
            self:Print("%d error(s) this session (newest first):", #self.errors)
            for i = 1, math.min(5, #self.errors) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffff6060[%s]|r %s", self.errors[i].time, self.errors[i].text))
            end
        end
    elseif cmd == "items" then
        self:PrintItemStatus()
    elseif cmd == "memory" or cmd == "mem" then
        -- the AddOn list shows memory including garbage the game has not collected yet; this shows both
        UpdateAddOnMemoryUsage()
        local now = GetAddOnMemoryUsage(ADDON_NAME)
        collectgarbage("collect")
        UpdateAddOnMemoryUsage()
        local used = GetAddOnMemoryUsage(ADDON_NAME)
        self:Print("Memory: %.1f MB now, %.1f MB in use after the game cleaned up (%.1f MB was garbage).",
            now / 1024, used / 1024, math.max(0, now - used) / 1024)
    elseif cmd == "status" then
        local name, _, _, build = GetBuildInfo()
        self:Print("%s", self.TITLE)
        self:Print("Client: %s (%s)", tostring(name or "WoW Forever"), tostring(build or "unknown"))
        self:Print("Data: %s; checked %s; %s", tostring(self.DATA_BUILD or "unknown"),
            tostring(self.DATA_CHECKED or "unknown"), tostring(self.DATA_STATUS or "unknown"))
        self:Print("Sources: %s", tostring(self.DATA_SOURCES or "not recorded"))
    elseif cmd == "collect" then
        -- developer tool: collects what the game client knows about the addon's data (Core/Locale.lua)
        local sub = rest:lower()
        if sub == "stop" then
            self.Locale.Collect.Stop()
        elseif sub == "clear" then
            self.Locale.Collect.Clear()
        elseif sub == "" then
            self.Locale.Collect.Start(false)
        elseif sub == "language" then
            self.Locale.Collect.Start(true)
        else
            self:Print("Usage: /lf collect, /lf collect language, /lf collect stop or /lf collect clear.")
        end
    elseif cmd == "version" or cmd == "v" then
        self:Print("Version %s", self.VERSION)
        local c = self.db.itemCache
        local n, m = 0, 0
        for _ in pairs(c and c.items or {}) do n = n + 1 end
        for _ in pairs(c and c.missing or {}) do m = m + 1 end
        self:Print("Saved item data: %d items, %d not available in this game version (loaded from the last session: %d)",
            n, m, self.Items.savedCount or 0)
    else
        local inst = self.GetInstanceBySlash and self:GetInstanceBySlash(cmd)
        if inst then
            self:Open("instance", inst.key)
        else
            -- Treat anything else as a search.
            self:Open("search", msg)
        end
    end
end

SLASH_LOOTIFIED1 = "/lf"
SLASH_LOOTIFIED2 = "/lootified"
SlashCmdList.LOOTIFIED = function(msg)
    LJ:SafeCall(LJ.HandleSlash, LJ, msg)
end

-- Key binding labels
BINDING_HEADER_LOOTIFIED = "Lootified"
BINDING_NAME_LOOTIFIED_TOGGLE = "Open / close Lootified"
BINDING_NAME_LOOTIFIED_BIS = "Open Best in Slot"

-- The tooltip line of a right-click on the compartment entry and the minimap button (LJ:Open("bis")): the page it
-- opens, the Best in Slot page; with that module off the start page; in the database look the Items page.
function LJ.RightClickText()
    local name = "Items"
    if not LJ.Theme.IsDatabase() then
        local key = LJ.Modules.On("bis") and "bis" or LJ.Modules.Start()
        for _, m in ipairs(LJ.Modules.LIST) do
            if m.key == key then name = m.name end
        end
    end
    return F(L("Right-click: %s"), L(name))
end

-- Addon compartment (retail-style minimap addon menu)
function Lootified_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        LJ:Open("bis")
    else
        LJ:Toggle()
    end
end

function Lootified_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText(LJ.TITLE, 1, 0.82, 0)
    GameTooltip:AddLine(L("Left-click: open Lootified"), 1, 1, 1)
    GameTooltip:AddLine(LJ.RightClickText(), 1, 1, 1)
    GameTooltip:Show()
end

function Lootified_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
