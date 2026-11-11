-- Lootified - the stat priority: the order of a spec's stats the player drags in the filter's panel (UI/StatPrioView.lua)
-- and the stat weights it gives (Core/Scoring.lua scores every item with StatPrio.Weights). A stat's value is what an
-- item's usual amount of it counts by the spec's weights (STATS: typical); the spec's own order sorts its stats by it.
-- A stat the player drags takes a value between its new neighbours' (their geometric mean; above the first STEP more,
-- below the last STEP less): its weights scale by as much, every other weight stays. An order like the spec's own is
-- the spec's own (its weights as they are). Saved per character and spec of its class (LJ.cdb.statPrio[specKey] =
-- { order = the stat keys top down, factor = { [stat key] = what the drags made of its weights } }; none: the spec's
-- own). Weapon damage keeps its weight. It counts only while items are rated in Percent: with Sim the simulator rates
-- them and what it has no number for yet goes by the spec's own weights (StatPrio.Counts); the saved order is kept.
local _, LJ = ...

local StatPrio = {}
LJ.StatPrio = StatPrio

local Player = LJ.Player
local Scoring = LJ.Scoring

-- The stats an order can have, in the order of equal values: the name items show, what an item gives of it in place of
-- 13 points of a primary stat (13: the median of a primary stat on the shipped uncommon and better items of required
-- level 50 to 60, Data/ItemStats.lua; the item budget of the others from the same items' medians: 2 attack power, 2.5
-- ranged attack power, 1.15 spell power, 2.2 healing, 2 school damage, 0.4 MP5, 0.77 Defense, 1.3 block value or 14
-- armor for a point of a primary stat, ratings 1 to 1; research/build_forever_specs.py checks the specs' weights the
-- same way) and the weights it stands for (Core/Scoring.lua keys) with the rating one point of a weight counts (its
-- Scoring.CR name: the rating per 1 % at level 60, Scoring.RATING_PER_PCT_60); a stat without them stands for its own
-- key, 1 to 1.
StatPrio.STATS = {
    { key = "Strength", text = "Strength", typical = 13 },
    { key = "Agility", text = "Agility", typical = 13 },
    { key = "Stamina", text = "Stamina", typical = 13 },
    { key = "Intellect", text = "Intellect", typical = 13 },
    { key = "Spirit", text = "Spirit", typical = 13 },
    { key = "AttackPower", text = "Attack Power", typical = 26 },
    { key = "RangedAttackPower", text = "Ranged Attack Power", typical = 32.5 },
    { key = "SpellPower", text = "Spell Power", typical = 15 },
    { key = "Healing", text = "Healing", typical = 29 },
    { key = "ShadowPower", text = "Shadow Spell Power", typical = 26 },
    { key = "FirePower", text = "Fire Spell Power", typical = 26 },
    { key = "FrostPower", text = "Frost Spell Power", typical = 26 },
    { key = "NaturePower", text = "Nature Spell Power", typical = 26 },
    { key = "ArcanePower", text = "Arcane Spell Power", typical = 26 },
    { key = "HolyPower", text = "Holy Spell Power", typical = 26 },
    { key = "Hit", text = "Hit Rating", typical = 13, weights = { Hit = "HIT_MELEE", SpellHit = "HIT_SPELL" } },
    { key = "Crit", text = "Critical Strike Rating", typical = 13, weights = { Crit = "CRIT_MELEE", SpellCrit = "CRIT_SPELL" } },
    { key = "Haste", text = "Haste Rating", typical = 13, weights = { Haste = "HASTE" } },
    { key = "Expertise", text = "Expertise Rating", typical = 13, weights = { Expertise = "EXPERTISE" } },
    { key = "MP5", text = "Mana per 5 sec.", typical = 5.2 },
    { key = "Defense", text = "Defense", typical = 10 },
    { key = "Dodge", text = "Dodge Rating", typical = 13, weights = { Dodge = "DODGE" } },
    { key = "Parry", text = "Parry Rating", typical = 13, weights = { Parry = "PARRY" } },
    { key = "Block", text = "Block Rating", typical = 13, weights = { Block = "BLOCK" } },
    { key = "BlockValue", text = "Block Value", typical = 17 },
    { key = "Armor", text = "Armor", typical = 183 },
}
-- the weights no stat stands for: weapon damage
local WEAPON = { WeaponDPS = true, OffHandWeaponDPS = true, RangedWeaponDPS = true }
local STEP = 1.15

local BY_KEY, OF_WEIGHT = {}, {}   -- stat key -> stat; weight key -> the stat that stands for it
for i, stat in ipairs(StatPrio.STATS) do
    stat.index = i
    stat.weights = stat.weights or { [stat.key] = false }
    BY_KEY[stat.key] = stat
    for weight in pairs(stat.weights) do OF_WEIGHT[weight] = stat end
end

-- What one point of a weight counts of the stat's item amount (1, or a rating per 1 %).
local function Per(stat, weight)
    local cr = stat.weights[weight]
    return cr and Scoring.RATING_PER_PCT_60[cr] or 1
end

-- What an item's usual amount of a stat counts by weights.
local function Value(weights, stat)
    local v = 0
    for weight in pairs(stat.weights) do v = v + (weights[weight] or 0) * stat.typical / Per(stat, weight) end
    return v
end

-- The spec's own order: its stats with a value, the highest first (equal ones in STATS' order).
function StatPrio.DefaultOrder(spec)
    local order, values = {}, {}
    for weight, w in pairs(spec.weights) do
        assert(OF_WEIGHT[weight] or WEAPON[weight], "stat priority: no stat for the weight " .. weight)
        local stat = OF_WEIGHT[weight]
        if stat and w > 0 and not values[stat.key] then
            values[stat.key] = Value(spec.weights, stat)
            order[#order + 1] = stat.key
        end
    end
    table.sort(order, function(a, b)
        if values[a] ~= values[b] then return values[a] > values[b] end
        return BY_KEY[a].index < BY_KEY[b].index
    end)
    return order
end

-- The player's priority counts for a spec: one of the character's class while its items are rated in Percent (with
-- Sim the simulator rates them: UI.Sim.RanksItems).
function StatPrio.Counts(spec)
    return spec.class == Player.class and not LJ.UI.Sim.RanksItems(spec)
end

-- The priority the player set for a spec while it counts; nil: the spec's own counts.
local function Saved(spec)
    return StatPrio.Counts(spec) and LJ.cdb.statPrio[spec.key] or nil
end

-- A saved priority's weights, its stats' values, the stats it moved and its key (the rankings are kept per key); kept
-- per spec until it changes.
local computed = {}
local function Computed(spec)
    local saved = Saved(spec)
    if not saved then return nil end
    local c = computed[spec.key]
    if c then return c end
    c = { weights = {}, value = {}, moved = {} }
    for weight, w in pairs(spec.weights) do c.weights[weight] = w end
    local parts = {}
    for _, key in ipairs(saved.order) do
        local stat, f = BY_KEY[key], saved.factor[key]
        c.value[key] = Value(spec.weights, stat) * (f or 1)
        if f then
            c.moved[key] = true
            parts[#parts + 1] = key .. "=" .. f
            for weight in pairs(stat.weights) do
                if spec.weights[weight] then c.weights[weight] = spec.weights[weight] * f end
            end
        end
    end
    c.key = table.concat(saved.order, ",") .. "|" .. table.concat(parts, ",")
    computed[spec.key] = c
    return c
end

-- The weights a spec's items are scored with: its own (the same table), or those of the priority the player set.
function StatPrio.Weights(spec)
    local c = Computed(spec)
    return c and c.weights or spec.weights
end

-- The priority as one text for the rankings kept per priority ("": the spec's own).
function StatPrio.Key(spec)
    local c = Computed(spec)
    return c and c.key or ""
end

function StatPrio.IsCustom(spec)
    return Saved(spec) ~= nil
end

-- The order of a spec now (stat keys top down; a copy).
function StatPrio.Order(spec)
    local saved, order = Saved(spec), {}
    for i, key in ipairs(saved and saved.order or StatPrio.DefaultOrder(spec)) do order[i] = key end
    return order
end

-- The stats top down as the panel shows them: { key, text, value (what an item's usual amount counts now), moved
-- (dragged: its weights changed) }.
function StatPrio.Rows(spec)
    local c, rows = Computed(spec), {}
    for i, key in ipairs(StatPrio.Order(spec)) do
        local stat = BY_KEY[key]
        rows[i] = { key = key, text = stat.text, value = c and c.value[key] or Value(spec.weights, stat),
            moved = c ~= nil and c.moved[key] == true }
    end
    return rows
end

-- Saves a spec's priority (nil: its own) and everything that rates items follows (LIST_CHANGED).
local function Store(spec, saved)
    assert(StatPrio.Counts(spec), "stat priority of another class or with Sim: " .. spec.class .. " " .. spec.key)
    LJ.cdb.statPrio[spec.key] = saved
    computed[spec.key] = nil
    LJ:Fire("LIST_CHANGED")
end

-- A stat dragged to place index of the order (1: the top): it takes a value between its new neighbours' (above the
-- first STEP more, below the last STEP less), the others keep theirs; an order like the spec's own is its own again.
function StatPrio.Move(spec, key, index)
    local rows = StatPrio.Rows(spec)
    local order, value, from = {}, {}, nil
    for i, r in ipairs(rows) do
        order[i], value[r.key] = r.key, r.value
        if r.key == key then from = i end
    end
    assert(from, "stat priority: no stat " .. tostring(key) .. " for " .. spec.key)
    assert(index >= 1 and index <= #order, "stat priority: no place " .. tostring(index))
    if index == from then return end
    table.remove(order, from)
    table.insert(order, index, key)
    local above = order[index - 1] and value[order[index - 1]]
    local below = order[index + 1] and value[order[index + 1]]
    local v
    if above and below then
        v = math.sqrt(above * below)
    elseif below then
        v = below * STEP
    else
        v = above / STEP
    end
    local factor, saved = {}, Saved(spec)
    for k, f in pairs(saved and saved.factor or {}) do factor[k] = f end
    factor[key] = v / Value(spec.weights, BY_KEY[key])
    local own = table.concat(StatPrio.DefaultOrder(spec), ",") == table.concat(order, ",")
    Store(spec, not own and { order = order, factor = factor } or nil)
end

function StatPrio.Reset(spec)
    Store(spec, nil)
end

-- A saved priority goes when its spec is gone, its stats are not the spec's or its values no longer fall top down (the
-- spec's weights changed in an update); read with the saved data.
local function Valid(spec, saved)
    if not spec or type(saved.order) ~= "table" or type(saved.factor) ~= "table" then return false end
    local own, keys = StatPrio.DefaultOrder(spec), {}
    for i, k in ipairs(saved.order) do keys[i] = k end
    table.sort(own)
    table.sort(keys)
    if table.concat(own, ",") ~= table.concat(keys, ",") then return false end
    local last
    for _, key in ipairs(saved.order) do
        local f = saved.factor[key]
        if f ~= nil and not (type(f) == "number" and f > 0) then return false end
        local v = Value(spec.weights, BY_KEY[key]) * (f or 1)
        if last and v > last * (1 + 1e-9) then return false end
        last = v
    end
    return true
end

function StatPrio.DropStale()
    computed = {}
    for key, saved in pairs(LJ.cdb.statPrio) do
        if not Valid(Player:GetSpec(Player.class, key), saved) then LJ.cdb.statPrio[key] = nil end
    end
end
LJ:Listen("DB_READY", StatPrio.DropStale)
