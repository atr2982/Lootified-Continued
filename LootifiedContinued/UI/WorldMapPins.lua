-- Lootified - dungeon entrances on the world map: a pin at every entrance the addon knows (inst.entrance). A click
-- opens the dungeon in Lootified with its dungeon map; dungeons that share an entrance (Scarlet
-- Monastery, Blackrock Spire) share a pin that offers a choice. The pins come from a data provider of the game's
-- world map (MapCanvasDataProviderMixin): drawn when the map shows a zone with entrances, gone when it closes.
-- The addon's own "Map" buttons for an entrance open the map with its pin lit (Core/MapPin.lua) instead of a second
-- marker.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local UI = LJ.UI
local Widgets = LJ.Widgets
local Theme = LJ.Theme
local Util = LJ.Util
local C = Theme.COLORS

local Pins = {}
LJ.WorldMapPins = Pins

local SIZE = 24
local SHARE = 1.5      -- entrances closer than this (map coordinates 0-100) share a pin
local PING = 1.2       -- seconds of one ping of the lit pin (a ring that grows and fades), for as long as it is lit

local byMap            -- uiMapID -> { { x, y, insts = { ... } } }, built on first use
local pins = {}        -- pin buttons, reused
local provider
local lit              -- { map, spot }: the pin a "Map" button asked for, lit until the map closes

local function BuildIndex()
    byMap = {}
    for _, inst in ipairs(LJ.Data.Instances or {}) do
        local e = inst.entrance
        if e and e.map and e.x and e.y then
            local list = byMap[e.map]
            if not list then
                list = {}
                byMap[e.map] = list
            end
            local spot
            for _, s in ipairs(list) do
                if math.abs(s.x - e.x) < SHARE and math.abs(s.y - e.y) < SHARE then
                    spot = s
                    break
                end
            end
            if not spot then
                spot = { x = e.x, y = e.y, insts = {} }
                list[#list + 1] = spot
            end
            spot.insts[#spot.insts + 1] = inst
        end
    end
end

-- The entrance spots of a map (0-100), nil for maps without any.
function Pins.SpotsFor(mapID)
    if not byMap then BuildIndex() end
    return byMap[mapID]
end

-- The spot of an entrance pin at exactly this place (map, x and y 0-100), nil when there is none or the pins are off.
function Pins.SpotAt(mapID, x, y)
    if not (provider and LJ.db and LJ.db.worldMapEntrances) then return nil end
    for _, spot in ipairs(Pins.SpotsFor(mapID) or {}) do
        for _, inst in ipairs(spot.insts) do
            local e = inst.entrance
            if math.abs(e.x - x) < 0.05 and math.abs(e.y - y) < 0.05 then return spot end
        end
    end
    return nil
end

local function LevelText(inst)
    local range = Util.LevelRange(inst.minLevel, inst.maxLevel):gsub("-", "–")
    return F("Level %s", range)
end

local function OpenDungeon(inst)
    -- during combat the game does not let addons close the world map (HideUIPanel refuses and prints "Interface action
    -- failed because of an AddOn"): the map stays open then
    if WorldMapFrame:IsShown() and not InCombatLockdown() then
        HideUIPanel(WorldMapFrame)
    end
    UI:Open("instance", inst.key, "map")
end

local function PinOnEnter(pin)
    pin.glow:Show()
    local insts = pin.spot.insts
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if #insts == 1 then
        local inst = insts[1]
        local c = Theme.RangeColor(inst.minLevel, inst.maxLevel, true)
        GameTooltip:SetText(inst.name, 1, 1, 1)
        GameTooltip:AddLine(LevelText(inst), c[1], c[2], c[3])
        GameTooltip:AddLine(L("Click to open in Lootified."), 0.6, 0.62, 0.66)
    else
        GameTooltip:SetText(L("Dungeon entrance"), 1, 1, 1)
        for _, inst in ipairs(insts) do
            local c = Theme.RangeColor(inst.minLevel, inst.maxLevel, true)
            GameTooltip:AddDoubleLine(inst.name, LevelText(inst), 0.9, 0.9, 0.9, c[1], c[2], c[3])
        end
        GameTooltip:AddLine(L("Click to choose a dungeon."), 0.6, 0.62, 0.66)
    end
    GameTooltip:Show()
end

local function PinOnLeave(pin)
    if not pin.lit then pin.glow:Hide() end
    if GameTooltip:GetOwner() == pin then GameTooltip:Hide() end
end

-- The lit pin pings while it is lit (the map open on its zone): a ring grows from the pin and fades, its glow breathes,
-- so it stands out among the other entrances.
local function PulseOnUpdate(pin)
    local t = GetTime() - lit.t
    local phase = (t % PING) / PING
    pin.ping:SetSize(SIZE * (1 + 1.6 * phase), SIZE * (1 + 1.6 * phase))
    pin.ping:SetAlpha(1 - phase)
    pin.glow:SetAlpha(0.55 + 0.45 * math.abs(math.cos(t * math.pi / PING)))
end

local function SetLit(pin, on)
    pin.lit = on
    pin.glow:SetShown(on)
    pin.glow:SetAlpha(1)
    pin.ping:SetShown(on)
    pin:SetScript("OnUpdate", on and PulseOnUpdate or nil)
end

local function PinOnClick(pin)
    local insts = pin.spot.insts
    Util.PlaySound("IG_MAINMENU_OPTION")
    GameTooltip:Hide()
    if #insts == 1 then
        OpenDungeon(insts[1])
        return
    end
    Widgets.ShowContextMenu(pin, function(root)
        root:CreateTitle("Dungeon entrance")
        for _, inst in ipairs(insts) do
            root:CreateButton(inst.name .. "  |cff8a8f99" .. Util.LevelRange(inst.minLevel, inst.maxLevel) .. "|r",
                function() OpenDungeon(inst) end)
        end
    end)
end

local function AcquirePin(i, canvas)
    local pin = pins[i]
    if pin then
        if pin:GetParent() ~= canvas then pin:SetParent(canvas) end
        return pin
    end
    pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(SIZE, SIZE)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
    pin.glow:SetTexture(Theme.TEX.glow or Theme.TEX.circle)
    pin.glow:Hide()
    pin.ping = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
    pin.ping:SetPoint("CENTER")
    pin.ping:SetTexture(Theme.TEX.circleRing)
    pin.ping:Hide()
    pin.bg = pin:CreateTexture(nil, "ARTWORK")
    pin.bg:SetTexture(Theme.TEX.circle)
    pin.bg:SetAllPoints()
    pin.bg:SetVertexColor(0.06, 0.07, 0.09, 0.95)
    pin.ring = pin:CreateTexture(nil, "OVERLAY")
    pin.ring:SetTexture(Theme.TEX.circleRing)
    pin.ring:SetAllPoints()
    pin.glyph = Widgets.Glyph(pin, "castle", 13, C.white, "OVERLAY", 2)
    pin.glyph:SetPoint("CENTER")
    -- how many dungeons share the entrance
    pin.badge = CreateFrame("Frame", nil, pin)
    pin.badge:SetSize(14, 14)
    pin.badge:SetPoint("CENTER", pin, "TOPRIGHT", -2, -2)
    pin.badge.bg = pin.badge:CreateTexture(nil, "ARTWORK")
    pin.badge.bg:SetTexture(Theme.TEX.circle)
    pin.badge.bg:SetAllPoints()
    pin.badge.text = Widgets.Text(pin.badge, "tiny", { 0.05, 0.05, 0.06, 1 }, nil, "CENTER")
    pin.badge.text:SetPoint("CENTER", 0, 0)
    pin:SetScript("OnEnter", PinOnEnter)
    pin:SetScript("OnLeave", PinOnLeave)
    pin:SetScript("OnClick", PinOnClick)
    pins[i] = pin
    return pin
end

-- The canvas is scaled when the map zooms: the pins are scaled back so they keep their size on screen (their offsets
-- are in their own scaled units, as in Core/MapPin.lua).
local function LayoutPin(pin, canvas)
    local canvasScale = canvas:GetScale() or 1
    local scale = canvasScale > 0 and 1 / canvasScale or 1
    pin:SetScale(scale)
    local spot = pin.spot
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * spot.x / 100 / scale,
        -canvas:GetHeight() * spot.y / 100 / scale)
end

-- the pins sit on the game's world map: the bright accent in every look
local function PinColors(pin)
    local a = Theme.BrightAccent()
    pin.ring:SetVertexColor(a[1], a[2], a[3], 1)
    pin.glyph:SetVertexColor(a[1], a[2], a[3], 1)
    pin.glow:SetVertexColor(a[1], a[2], a[3], 0.8)
    pin.ping:SetVertexColor(a[1], a[2], a[3], 1)
    pin.badge.bg:SetVertexColor(a[1], a[2], a[3], 1)
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local Provider = {}

function Provider:RemoveAllData()
    for _, pin in ipairs(pins) do
        pin:Hide()
        if pin.lit then SetLit(pin, false) end
    end
    self.shown = 0
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    if not (LJ.db and LJ.db.worldMapEntrances) then return end
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    local spots = mapID and Pins.SpotsFor(mapID)
    if not spots then return end
    local canvas = map:GetCanvas()
    if not canvas or (canvas:GetWidth() or 0) <= 1 then return end
    -- the frame level of the game's own dungeon entrance pins: above the map's explored areas and fog of war (pins of
    -- the map too, at frame levels from 2000 up: Blizzard_MapCanvas), below its quest and player pins
    local level = map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    for i, spot in ipairs(spots) do
        local pin = AcquirePin(i, canvas)
        pin.spot = spot
        pin:SetFrameStrata(canvas:GetFrameStrata())
        pin:SetFrameLevel(level)
        pin.badge:SetShown(#spot.insts > 1)
        pin.badge.text:SetText(tostring(#spot.insts))
        PinColors(pin)
        LayoutPin(pin, canvas)
        pin:Show()
        if lit and lit.map == mapID and lit.spot == spot then
            SetLit(pin, true)
            pin:SetFrameLevel(level + 1)   -- above the other entrances
        end
    end
    self.shown = #spots
end

function Provider:Relayout()
    local map = self:GetMap()
    local canvas = map and map:GetCanvas()
    if not canvas then return end
    for i = 1, self.shown or 0 do LayoutPin(pins[i], canvas) end
end

function Provider:OnCanvasScaleChanged() self:Relayout() end
-- a canvas that had no size yet at the first refresh gets its pins now
function Provider:OnCanvasSizeChanged() self:RefreshAllData() end
-- the lit pin stays lit only while the map is open
function Provider:OnHide()
    lit = nil
    self:RemoveAllData()
end

-- Adds the provider to the game's world map.
function Pins.Attach()
    if provider then return end
    provider = CreateFromMixins(MapCanvasDataProviderMixin, Provider)
    WorldMapFrame:AddDataProvider(provider)
    Pins.provider = provider
end

-- Shows or hides the pins at once when the option changes while the map is open.
function Pins.Refresh()
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

-- Lights the pin of an entrance spot (Pins.SpotAt) while the map shows its zone, until the map closes.
function Pins.Light(mapID, spot)
    lit = { map = mapID, spot = spot, t = GetTime() }
    Pins.Refresh()
end

-- The pin lit now (nil: none), for the tests.
function Pins.LitSpot()
    return lit and lit.spot
end

LJ:Listen("LOGIN", function() Pins.Attach() end)
LJ:Listen("SETTINGS_CHANGED", function(_, key)
    if key == "worldMapEntrances" or key == "accent" then Pins.Refresh() end
end)
