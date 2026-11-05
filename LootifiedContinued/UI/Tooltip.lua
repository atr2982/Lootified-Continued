-- Lootified - item tooltip lines (what the sim found for the item, with Percent the share it adds by the stat weights,
-- the Best in Slot list, drop source and chance, quest links, wishlist, Alt+Click to sim it) and wishlist loot alerts.
local _, LJ = ...
local L, F = LJ.L, LJ.F

local Tooltip = {}
LJ.Tooltip = Tooltip

local Items = LJ.Items
local Util = LJ.Util
local Theme = LJ.Theme

-- Our lines under an item tooltip: each source in gold (the boss, mob, quest or profession; the drop chance in white),
-- below it where (light grey); notes, the wishlist mark, what a click does (dim)
local GOLD, WHITE, BELOW, GAIN = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.78, 0.8, 0.84 }, { 0.34, 0.89, 0.54 }
local LOSS, SAME = { 0.97, 0.44, 0.44 }, { 0.62, 0.65, 0.7 }
local NOTE, WISH, HINT = { 0.8, 0.8, 0.8 }, { 1, 0.55, 0.8 }, { 0.55, 0.59, 0.66 }
local TITLE_FONT = "GameTooltipHeaderText"   -- the item name's font: a source line in that size
local INDENT = 19                            -- the line below a source starts under its name (after the symbol)

-- An instance's tooltip next to a list row, downwards (above it, the tooltip of the first rows would cover the window's
-- top bar): name, level, zone, group size, data status, description, bosses, drops, quests and upgrades (the items of
-- the Best in Slot list).
function Tooltip.ShowInstance(row, inst)
    local Quests = LJ.Quests
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
    local a = Theme.InstanceAccent(inst)
    GameTooltip:SetText(inst.name, a[1], a[2], a[3])
    local levelText = inst.kind == "raid" and L("Level 60") or F("Level %s", Util.LevelRange(inst.minLevel, inst.maxLevel))
    GameTooltip:AddLine(Theme.DotSafe(F("%s  ·  %s  ·  %d players", levelText, inst.zone or "", inst.size or 5)), 1, 1, 1)
    GameTooltip:AddLine(inst.statusText, 0.75, 0.78, 0.82, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(inst.desc, 0.85, 0.86, 0.88, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L("Bosses"), #inst.bosses, 0.6, 0.64, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L("Known drops"), inst.itemCount or 0, 0.6, 0.64, 0.7, 1, 1, 1)
    local total, open, done = Quests.CountForInstance(inst.key)
    if total > 0 then
        GameTooltip:AddDoubleLine(L("Quests for you"), F("%d  (%d open, %d completed)", total, open, done), 0.6, 0.64, 0.7, 1, 1, 1)
    end
    local upgrades = LJ.Lists.CountFor(inst)
    if upgrades > 0 then
        GameTooltip:AddDoubleLine(L("Upgrades for you"), upgrades, 0.6, 0.64, 0.7, 0.34, 0.89, 0.54)
    end
    GameTooltip:Show()
end

-- A line that says what a click does: the last of an item tooltip, dim, after a cursor ({ text, r, g, b }: an extra
-- line of Widgets.ShowItemTooltip).
function Tooltip.Hint(text)
    return { Theme.GlyphString("cursor", 12, HINT) .. " " .. L(text), HINT[1], HINT[2], HINT[3] }
end

-- Source lines in the title's size: the game keeps a line's font for the tooltips after this one, so every line made
-- bigger gets its own font back when the tooltip is cleared (OnTooltipCleared: before the next lines come in).
local bigLines = {}   -- [tooltip] = { [font string] = its own font }
local function RestoreFonts(tooltip)
    local list = bigLines[tooltip]
    if not list then return end
    for fs, font in pairs(list) do fs:SetFontObject(font) end
    bigLines[tooltip] = nil
end

-- (a font object brings its own color: the line's colors are set again after it)
local function MakeBig(tooltip, index, left, right)
    local list = bigLines[tooltip]
    if not list then
        list = {}
        bigLines[tooltip] = list
        if not tooltip.lootifiedRestores then
            tooltip.lootifiedRestores = true
            tooltip:HookScript("OnTooltipCleared", RestoreFonts)
        end
    end
    for fs, color in pairs({ [tooltip:GetLeftLine(index)] = left, [tooltip:GetRightLine(index)] = right }) do
        list[fs] = list[fs] or assert(fs:GetFontObject(), "a tooltip line without a font object")
        fs:SetFontObject(TITLE_FONT)
        fs:SetTextColor(color[1], color[2], color[3])
    end
end

-- A source: its symbol and name in gold in the title's size, the drop chance at the right; below it in light grey
-- where it is or what kind of source it is.
local function AddSource(tooltip, glyph, name, chance, below)
    local text = Theme.GlyphString(glyph, 14, GOLD) .. " " .. name
    if chance then
        tooltip:AddDoubleLine(text, chance, GOLD[1], GOLD[2], GOLD[3], WHITE[1], WHITE[2], WHITE[3])
    else
        tooltip:AddLine(text, GOLD[1], GOLD[2], GOLD[3])
    end
    MakeBig(tooltip, tooltip:NumLines(), GOLD, WHITE)
    tooltip:AddLine(Theme.DotSafe(below), BELOW[1], BELOW[2], BELOW[3], false, INDENT)
end

-- The gain beside the item's name: the first line's right text, in the tooltip's title font. What the sim found for the
-- item (link) with what is worn now (Sim/ItemCheck.lua: an upgrade green after an arrow, a loss red, about the same
-- grey); Percent: what it adds to the whole gear by the stat weights ("+4.2%", "Upgrade" while nothing worn scores);
-- else the mark of the Best in Slot list ("+1.1 DPS" or "BiS" after a green arrow); none for other items. The game
-- clears it with the tooltip's lines and sizes the tooltip after our lines (TooltipDataHandler).
local function ShowTopGain(tooltip, itemID, link)
    local n = LJ.ItemCheck.Number(link)
    local v = not n and LJ.ItemCheck.Get(link)
    local text, color, dir
    if n then
        dir = LJ.ItemCheck.Direction(n)
        text = string.format("%+.1f DPS", n.delta)
    elseif v and v.kind == "stats" and (v.pct or v.better) then
        dir = LJ.ItemCheck.StatsDirection(v)
        text = v.pct and string.format("%+.1f%%", v.pct) or L("Upgrade")
    end
    if text then
        if dir == "up" then text = Theme.IconString("upgrade", 14) .. " " .. text end
        color = dir == "up" and GAIN or dir == "down" and LOSS or SAME
    elseif LJ.BiS.Target(itemID) then
        text, color = Theme.IconString("upgrade", 14) .. " " .. LJ.BiS.UpgradeText(itemID), GAIN
    else
        return
    end
    local top = tooltip.TextRight1
    top:SetText(text)
    top:SetTextColor(color[1], color[2], color[3])
    top:Show()
end

-- Our lines in the tooltip of itemID (link: the item as the tooltip shows it, a random suffix counts): the gain beside
-- its name, then where it comes from (each source as AddSource makes it: dungeon or world drop, quest, profession),
-- its note and the wishlist mark; with hint, last, that Alt+Click sims it (an item the simulator can fight that has no
-- number for what is worn yet: Sim/ItemCheck.lua, UI/ItemCheckBox.lua).
function Tooltip.AddLines(tooltip, itemID, force, link, hint)
    local db = LJ.db
    if not itemID then return end
    link = link or ("item:" .. itemID)
    if db.tooltipUpgrade and LJ.Modules.On("bis") then ShowTopGain(tooltip, itemID, link) end
    -- the lines come after a blank line, once there is one
    local started = false
    local function Start()
        if not started then tooltip:AddLine(" ") end
        started = true
    end
    local function More(list) return #list > 1 and F(" |cff9d9d9d(+%d more)|r", #list - 1) or "" end

    if db.tooltipSource or force then
        local sources = Items.GetSources(itemID)
        local s = sources and sources[1]
        local inst = s and LJ.instanceByKey[s.inst]
        if inst then
            Start()
            local trash = s.boss == 0
            local bossName = trash and L("Trash") or (inst.bosses[s.boss] and inst.bosses[s.boss].name) or "?"
            AddSource(tooltip, trash and "castle" or "skull", bossName, Util.FormatChance(s.chance), inst.name .. More(sources))
        elseif not (sources and sources[1]) and Items.HasWorldDrop(itemID) then
            -- open world: the best mob (rares marked) with its zone, or the level range of a random world drop
            local mobs, random = Items.GetWorldSources(itemID)
            local m = mobs and mobs[1]
            if m then
                Start()
                local rank = m.mob.rankText and (" (" .. L(m.mob.rankText) .. ")") or ""
                AddSource(tooltip, "skull", m.mob.name .. rank, Util.FormatChance(m.chance),
                    (Items.GetMobZone(m.mob) or L("Open world")) .. More(mobs))
            elseif random then
                Start()
                AddSource(tooltip, "mapPin", L("World drop"), nil,
                    F(L("Mobs level %s"), Util.LevelRange(random.minLevel, random.maxLevel)))
            end
        end
        -- the professions that make it (Data/Crafted.lua)
        local craftedBy = Items.GetCraftedBy(itemID)
        if craftedBy then
            Start()
            AddSource(tooltip, "gear", craftedBy, nil, L("Crafted"))
        end
    end

    local Quests = LJ.Quests
    if Quests and (db.tooltipQuests or force) then
        local function QuestSource(list, kind)
            local q = list and list[1] and Quests.Get(list[1])
            if not q then return end
            Start()
            AddSource(tooltip, "exclamation", q.name, nil, L(kind) .. More(list))
        end
        QuestSource(Quests.rewardOf[itemID], "Quest reward")
        if not Quests.rewardOf[itemID] then
            -- open world quest: the one for this character first, with the zone of the quest giver
            local list = Items.GetWorldQuestSources(itemID)
            local q = list and list[1]
            if q then
                Start()
                local zone = Items.GetQuestZone(q)
                AddSource(tooltip, "exclamation", q.name, nil, L("Quest reward") .. (zone and (" · " .. zone) or "") .. More(list))
            end
        end
        QuestSource(Quests.neededFor[itemID], "Needed for quest")
        if Quests.startedBy[itemID] then QuestSource({ Quests.startedBy[itemID] }, "Starts the quest") end
    end

    -- where a special quest item or key comes from (Data/Items.lua ItemNotes, German when German is used)
    local note = (db.tooltipSource or force) and LJ.Data.ItemNotes and LJ.Data.ItemNotes[itemID]
    if note then
        Start()
        tooltip:AddLine(note, NOTE[1], NOTE[2], NOTE[3], true)
    end
    if (db.tooltipWishlist or force) and Items.IsWishlisted(itemID) then
        Start()
        tooltip:AddLine(Theme.IconString("star", 12) .. " " .. L("On your Wishlist"), WISH[1], WISH[2], WISH[3])
    end
    if hint and db.tooltipUpgrade and db.upgradeCheck and LJ.Modules.On("bis") then
        local v = LJ.ItemCheck.Get(link)
        if v and v.canSim and v.kind ~= "sim" then
            Start()
            tooltip:AddLine(Theme.GlyphString("cursor", 12, HINT) .. " " .. L("Alt+Click: sim it against what you wear"),
                HINT[1], HINT[2], HINT[3])
        end
    end
end

-- Lines an addon list adds under one item's tooltip. They go in after the game's lines each time the game fills
-- the tooltip, so they stay when it fills it again (the item's data arriving from the server).
local extra = {}

function Tooltip.SetExtraLines(owner, itemID, lines)
    extra.owner, extra.itemID, extra.lines = owner, itemID, lines
end

function Tooltip.AddExtraLines(tooltip)
    for _, line in ipairs(extra.lines) do
        tooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
    end
end

-- The game's comparison tooltips (what is worn, beside an item's tooltip and beside a chat link's ItemRefTooltip:
-- GameTooltip.xml, ItemRef.xml) get no lines.
local COMPARISON = { ShoppingTooltip1 = true, ShoppingTooltip2 = true, ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true }

local function OnItemTooltip(tooltip, data)
    if tooltip:IsForbidden() then return end
    if COMPARISON[tooltip:GetName()] then return end
    local itemID = data.id
    if not itemID or Util.IsSecret(itemID) then return end
    -- the item's link as the game's TooltipUtil.GetDisplayedItem reads it (a random suffix counts)
    local link = (data.guid and C_Item.GetItemLinkByGUID(data.guid)) or data.hyperlink
    if link and Util.IsSecret(link) then link = nil end
    local ours = tooltip == GameTooltip and itemID == extra.itemID and tooltip:GetOwner() == extra.owner
    Tooltip.AddLines(tooltip, itemID, nil, link, true)
    if extra.lines and ours then
        Tooltip.AddExtraLines(tooltip)
    end
end

LJ:Listen("LOGIN", function()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        LJ:SafeCall(OnItemTooltip, tooltip, data)
    end)
end)

---------------------------------------------------------------------------
-- Wishlist alerts
---------------------------------------------------------------------------
local lastAlert = {}

local function Alert(itemID, link)
    local now = GetTime()
    if lastAlert[itemID] and now - lastAlert[itemID] < 15 then return end
    lastAlert[itemID] = now
    local text = F("%s Wishlist item dropped: %s", Theme.IconString("star", 16), link or Items.GetColoredName(itemID))
    -- the raid warning on screen
    RaidWarningUtil.AddMessage(text, ChatTypeInfo.RAID_WARNING)
    Util.PlaySound("RAID_WARNING")
    LJ:Print(text)
end

local function ItemIDFromLink(link)
    if type(link) ~= "string" or Util.IsSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

LJ:On("LOOT_READY", function()
    if not LJ.db.wishlistAlerts or not GetNumLootItems then return end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = ItemIDFromLink(link)
        if itemID and Items.IsWishlisted(itemID) then
            Alert(itemID, link)
        end
    end
end)

LJ:On("START_LOOT_ROLL", function(_, rollID)
    if not LJ.db.wishlistAlerts or not GetLootRollItemLink then return end
    local link = GetLootRollItemLink(rollID)
    local itemID = ItemIDFromLink(link)
    if itemID and Items.IsWishlisted(itemID) then
        Alert(itemID, link)
    end
end)
