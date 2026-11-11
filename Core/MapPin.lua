-- Lootified - "Show on Map": opens the world map on a zone and marks a spot (quest givers, dungeon entrances).
-- The game's own waypoint is set as well (pin on the map and minimap, marker on screen).
local _, LJ = ...
local L = LJ.L

local MapPin = {}
LJ.MapPin = MapPin

local target        -- { map, x, y (0-100), title, detail }
local pin, ticker

local function EnsurePin(parent)
    if pin then
        if pin:GetParent() ~= parent then pin:SetParent(parent) end
        return pin
    end
    pin = CreateFrame("Button", "LootifiedMapPin", parent)
    pin:SetSize(32, 32)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(44, 44)
    pin.glow:SetAtlas("common-roundhighlight")
    pin.glow:SetVertexColor(1, 0.82, 0.2, 0.8)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetAtlas("Waypoint-MapPin-Tracked")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnClick", function(_, button)
        if button == "RightButton" then MapPin.Clear() end
    end)
    pin:SetScript("OnEnter", function(self)
        if not target then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(target.title or "Lootified", 1, 0.82, 0)
        if target.detail then GameTooltip:AddLine(target.detail, 1, 1, 1, true) end
        GameTooltip:AddLine(L("Right-click to remove"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    return pin
end

-- Places the pin on the map when the map shows the target zone.
local function UpdatePin()
    if not target or not WorldMapFrame:IsShown() then
        if pin then pin:Hide() end
        return
    end
    local mapID = WorldMapFrame:GetMapID()
    if mapID and mapID ~= target.map then
        if pin then pin:Hide() end
        return
    end
    -- the map canvas: the coordinate surface of the world map
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or not h or w <= 1 or h <= 1 then return end
    local p = EnsurePin(canvas)
    p:SetFrameStrata("HIGH")
    p:SetFrameLevel(2000)
    -- The canvas is scaled when the map zooms: counter-scale the pin so it keeps its size on screen.
    -- (WorldMapFrame:SetPinPosition needs a MapCanvasPinMixin pin, so the position is applied here
    -- the same way MapCanvasMixin:ApplyPinPosition does it: offsets divided by the pin scale.)
    local canvasScale = canvas:GetScale() or 1
    local scale = canvasScale > 0 and (1 / canvasScale) or 1
    p:SetScale(scale)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", (w * target.x / 100) / scale, -(h * target.y / 100) / scale)
    p:Show()
end

-- One frame for the whole session (frames are never freed), a child of the world map: its OnUpdate runs while a spot is
-- marked and the map is open (a closed map hides it, so a marked spot costs nothing then).
local function TickerUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.1 then return end
    self.elapsed = 0
    if not target then
        self:SetScript("OnUpdate", nil)
        return
    end
    UpdatePin()
end

local function StartTicker()
    ticker = ticker or CreateFrame("Frame", nil, WorldMapFrame)
    if ticker:GetScript("OnUpdate") then return end
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", TickerUpdate)
end

-- C_Map.OpenWorldMap is a restricted function in this game client: while an addon restriction is active (combat, a
-- boss encounter, ...) the game blocks it when an addon calls it, and every blocked call counts as a failed interface
-- action of the addon in the AddOn list. A map switched by the addon in combat is blocked the same way, in the game's
-- own pin code. The addon does not touch the map then: the spot is marked and the player opens the map.
local function MapRestricted()
    if InCombatLockdown() then return true end
    for _, t in pairs(Enum.AddOnRestrictionType) do
        if C_RestrictedActions.IsAddOnRestrictionActive(t) then return true end
    end
    return false
end
MapPin.MapRestricted = MapRestricted

local RESTRICTED_TEXT = "The game does not let addons open the world map right now. The spot is marked: open your world map to see it."

-- Shows the world map on the target zone; false when the game does not let addons open it now (nothing is called
-- then). The map can switch back to the last viewed zone while it opens, so the zone is set again a few times.
local function OpenMap(mapID)
    if MapRestricted() then return false end
    C_Map.OpenWorldMap(mapID)
    if WorldMapFrame:IsShown() then WorldMapFrame:SetMapID(mapID) end
    return true
end

-- Sets the zone again while the map opens (see OpenMap), never while the game restricts addons.
local function KeepMapOn(mapID)
    if WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() ~= mapID and not MapRestricted() then
        WorldMapFrame:SetMapID(mapID)
    end
end

-- The game's own waypoint: pin on the world map and minimap plus the tracked marker on screen. ownWaypoint is the
-- point the addon set ({ map, x, y } in 0-1), nil when none.
local ownWaypoint

local function SetGameWaypoint(loc)
    if not C_Map.CanSetUserWaypointOnMap(loc.map) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.map, loc.x / 100, loc.y / 100))
    ownWaypoint = { map = loc.map, x = loc.x / 100, y = loc.y / 100 }
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end

-- Removes the game's waypoint only while it is still the one the addon set: the player may have placed an own one
-- since.
local function ClearGameWaypoint()
    local own = ownWaypoint
    ownWaypoint = nil
    if not own then return end
    -- the waypoint's position on the map the addon set it on (nothing when it lies elsewhere)
    local pos = C_Map.GetUserWaypointPositionForMap(own.map)
    if not (pos and math.abs(pos.x - own.x) < 0.0005 and math.abs(pos.y - own.y) < 0.0005) then return end
    C_Map.ClearUserWaypoint()
end

-- A waypoint the addon set on exactly this spot (in an earlier session too) goes: the entrance pin marks it now.
local function ClearWaypointAt(loc)
    local pos = C_Map.GetUserWaypointPositionForMap(loc.map)
    if pos and math.abs(pos.x - loc.x / 100) < 0.0005 and math.abs(pos.y - loc.y / 100) < 0.0005 then
        C_Map.ClearUserWaypoint()
        ownWaypoint = nil
    end
end

-- A dungeon entrance that has its pin on the world map (UI/WorldMapPins.lua): the map opens on its zone with that pin
-- lit, and no second marker or waypoint is set. False when the spot has no entrance pin (the pins may be off).
local function ShowEntrance(loc)
    local pins = LJ.WorldMapPins
    local spot = pins and pins.SpotAt(loc.map, loc.x, loc.y)
    if not spot then return false end
    if MapPin.IsTarget(loc) then MapPin.Clear() end
    ClearWaypointAt(loc)
    local ok, opened = LJ:SafeCall(OpenMap, loc.map)
    if not ok then
        LJ:Print("Could not open the world map: %s", tostring(opened))
        return true
    end
    -- lit until the map closes: when the game kept the map shut, it is lit the next time the player opens it
    pins.Light(loc.map, spot)
    if not opened then
        LJ:Print(RESTRICTED_TEXT)
        return true
    end
    for _, delay in ipairs({ 0.05, 0.15, 0.3, 0.6 }) do
        C_Timer.After(delay, function() KeepMapOn(loc.map) end)
    end
    return true
end

-- loc = { map = UiMapID, x = 0-100, y = 0-100, title = text, detail = text }
function MapPin.Show(loc)
    if not loc or not loc.map or not loc.x or not loc.y then return false end
    if ShowEntrance(loc) then return true end
    target = loc
    local ok, opened = LJ:SafeCall(OpenMap, loc.map)
    if not ok then
        LJ:Print("Could not open the world map: %s", tostring(opened))
        return false
    end
    -- the marker follows the map whenever it shows the zone, also when the player opens it later
    StartTicker()
    UpdatePin()
    if opened then
        for _, delay in ipairs({ 0.05, 0.15, 0.3, 0.6 }) do
            C_Timer.After(delay, function()
                if target ~= loc then return end
                KeepMapOn(loc.map)
                UpdatePin()
            end)
        end
    end
    local tracked = SetGameWaypoint(loc)
    LJ:Print("Marked %s on your map (%.1f, %.1f)%s.", loc.title or L("the location"), loc.x, loc.y,
        tracked and L(", follow the marker on your screen") or "")
    if not opened then LJ:Print(RESTRICTED_TEXT) end
    LJ:Fire("MAP_TARGET_CHANGED")
    return true
end

-- Opens the world map on a zone (the database's Places page); says why when the game does not let addons open it.
function MapPin.OpenZone(mapID)
    local ok, opened = LJ:SafeCall(OpenMap, mapID)
    if ok and not opened then LJ:Print("The game does not let addons open the world map right now.") end
end

function MapPin.Clear()
    target = nil
    if pin then pin:Hide() end
    GameTooltip:Hide()
    ClearGameWaypoint()
    LJ:Fire("MAP_TARGET_CHANGED")
end

-- true when loc is the spot currently marked
function MapPin.IsTarget(loc)
    return target ~= nil and loc ~= nil and target.map == loc.map
        and math.abs(target.x - loc.x) < 0.05 and math.abs(target.y - loc.y) < 0.05
end

function MapPin.GetTarget()
    return target
end

-- Quest NPCs and objects carry their spawn point in world coordinates (loc.w = { continent, x, y }); the game
-- turns that into the zone map and 0-100 map coordinates here. The result is stored in loc (map, x, y, zone).
local CONTINENT_MAPS = { [0] = 1415, [1] = 1414 } -- Eastern Kingdoms, Kalimdor
local ZONE_TYPE = Enum.UIMapType.Zone

function MapPin.Resolve(loc)
    if not loc or loc.map or not loc.w or loc.resolved then return loc end
    loc.resolved = true
    local continent, wx, wy = loc.w[1], loc.w[2], loc.w[3]
    local mapID = CONTINENT_MAPS[continent]
    if not mapID then return loc end
    local world = CreateVector2D(wx, wy)
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, mapID)
    if not pos then return loc end
    -- walk down from the continent to the most detailed zone or city map at that spot
    for _ = 1, 3 do
        local info = C_Map.GetMapInfoAtPosition(mapID, pos.x, pos.y)
        if not info or info.mapID == mapID or (info.mapType and info.mapType > ZONE_TYPE) then break end
        local _, childPos = C_Map.GetMapPosFromWorldPos(continent, world, info.mapID)
        if not childPos then break end
        mapID, pos = info.mapID, childPos
    end
    if mapID == CONTINENT_MAPS[continent] then return loc end
    local info = C_Map.GetMapInfo(mapID)
    loc.map, loc.x, loc.y = mapID, pos.x * 100, pos.y * 100
    local zoneNames = LJ.Locale and LJ.Locale.zoneById   -- German names on an English client (Core/Locale.lua)
    loc.zone = loc.zone or (zoneNames and zoneNames[mapID]) or (info and info.name)
    return loc
end
