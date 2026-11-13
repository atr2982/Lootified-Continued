-- Lootified - the modules: the pages of the Modern and Classic looks, each of which the player can switch off in the
-- settings (LootifiedData.modules). A module that is off has no tab; links to it open the start page. Best in Slot off
-- also takes away its upgrade marks, tooltip lines and upgrade check for loot. At least one module stays on.
local _, LJ = ...

local Modules = {}
LJ.Modules = Modules

-- In the order of the navigation.
Modules.LIST = {
    { key = "foryou", name = "For you", glyph = "sparkle",
      text = "Your start page: the best dungeon for your level and your next upgrades." },
    { key = "journal", name = "Journal", glyph = "book",
      text = "Every dungeon and raid: bosses, loot and quests." },
    { key = "world", name = "Open World", glyph = "globe",
      text = "The rares and mobs of every zone with their drops and camps." },
    { key = "bis", name = "Best in Slot", glyph = "crown",
      text = "Your best gear for every slot, the crowns on items, the tooltip line and the percent upgrade check for loot." },
}

function Modules.On(key)
    if key == "wishlist" then return false end
    return LJ.db.modules[key] == true
end

function Modules.Count()
    local n = 0
    for _, m in ipairs(Modules.LIST) do
        if Modules.On(m.key) then n = n + 1 end
    end
    return n
end

-- False for the last module that is on (one always stays).
function Modules.CanSwitch(key)
    return not Modules.On(key) or Modules.Count() > 1
end

function Modules.Set(key, on)
    assert(LJ.db.modules[key] ~= nil, "unknown module " .. tostring(key))
    assert(on or Modules.CanSwitch(key), "the last module stays on")
    if Modules.On(key) == on then return end
    LJ.db.modules[key] = on
    LJ:Fire("MODULES_CHANGED", key, on)
end

-- The first module that is on: the window opens there.
function Modules.Start()
    for _, m in ipairs(Modules.LIST) do
        if Modules.On(m.key) then return m.key end
    end
    error("no module is on")
end
