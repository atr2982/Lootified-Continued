-- Lootified - minimap button (no library dependencies).
local _, LJ = ...
local L = LJ.L

local button

local function UpdatePosition()
    if not button or not Minimap then return end
    local angle = math.rad(LJ.db.minimap.angle or 208)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    LJ.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function CreateButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "LootifiedMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(LJ.MEDIA .. "LogoRound64")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            LJ:Open("bis")
        else
            LJ:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(LJ.TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L("Left-click: open Lootified"), 1, 1, 1)
        GameTooltip:AddLine(LJ.RightClickText(), 1, 1, 1)
        GameTooltip:AddLine(L("Drag: move this button"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    UpdatePosition()
end

local function Apply()
    if LJ.db.minimap.hide then
        if button then button:Hide() end
    else
        CreateButton()
        if button then
            button:Show()
            UpdatePosition()
        end
    end
end

LJ:Listen("LOGIN", Apply)
LJ:Listen("SETTINGS_CHANGED", function(_, what)
    if what == "minimap" then Apply() end
end)
