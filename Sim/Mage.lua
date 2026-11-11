-- Lootified - simulator model of the Mage in WoW: Forever. Arcane builds Arcane Blast to 4 stacks and spends them with
-- Arcane Missiles, Arcane Power and Presence of Mind on cooldown. Fire keeps Improved Scorch's 5 stacks up, casts
-- Pyroblast when Heating Up makes it quick, Fire Blast on cooldown, Fireball in between, Combustion on cooldown. Frost
-- casts Frostbolt, and Ice Lance while the target counts as frozen (Fingers of Frost, Frostbite's freeze). Presence of
-- Mind and Combustion share one cooldown that starts when the effect of the one used ends: Fire uses Combustion, the
-- others Presence of Mind. The burns of Fireball and Pyroblast crit. Missile Barrage sends free Arcane Missiles,
-- Clearcasting a free spell. Talents: Arcane Focus, Arcane Concentration, Arcane Impact, Missile Barrage, Arcane Mind,
-- Arcane Instability, Incineration, Ignite, Improved Scorch, Heating Up, Master of Elements, Critical Mass, Fire Power,
-- Elemental Precision, Ice Shards, Piercing Ice, Shatter, Fingers of Frost, Winter's Chill, Frostbite. Numbers from the
-- game's descriptions, costs, cast times and cooldowns from the game; spell power shares from the game's own tables
-- (Sim.SpellPower); rules below (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent, Average = Sim.Talent, Sim.Average

local M = { class = "MAGE", specs = { ARCANE = true, FIRE = true, FROST = true }, hands = {} }
Sim.models.MAGE = M

M.spells = {
    ARCANE_BLAST = 400574, ARCANE_MISSILES = 5143, ARCANE_POWER = 12042, PRESENCE_OF_MIND = 12043, FIREBALL = 133,
    SCORCH = 2948, FIRE_BLAST = 2136, PYROBLAST = 11366, COMBUSTION = 11129, FROSTBOLT = 116, ICE_LANCE = 1312002,
}
M.talents = {
    ARCANE_FOCUS = 11222, ARCANE_CONCENTRATION = 11213, ARCANE_IMPACT = 11242, MISSILE_BARRAGE = 400588,
    ARCANE_MIND = 11232, ARCANE_INSTABILITY = 15058, INCINERATION = 18459, IGNITE = 11119, IMPROVED_SCORCH = 11095,
    HEATING_UP = 400624, MASTER_OF_ELEMENTS = 29074, CRITICAL_MASS = 11115, FIRE_POWER = 11124,
    ELEMENTAL_PRECISION = 29438, ICE_SHARDS = 11207, PIERCING_ICE = 11151, SHATTER = 11170, FINGERS_OF_FROST = 400647,
    WINTERS_CHILL = 11180, FROSTBITE = 11071,
}

local FIREBALL_TICK, PYROBLAST_TICK, IGNITE_TICK = 2, 3, 2
local SCORCH_REFRESH = 6               -- Scorch again when Improved Scorch has less than this left
local COMBUSTION_CRITS = 3
-- Presence of Mind and Combustion: one spell category (SpellCategories 12043 and 11129: 1151 "Talent - DPS"), one
-- cooldown (SpellCooldowns CategoryRecoveryTime 180000, the tooltips' 3 min) for both. It starts when the effect of the
-- one used ends (SpellMisc Attributes[0] 0x02000000 of both, "cooldown after the effect"; the owner's research: "the
-- cooldown starts when the effect ends"): Presence of Mind's when its next spell uses it up, Combustion's at its third
-- crit (both last until then: duration -1). While the effect is on, neither is used (M.PresenceOfMind, M.Combustion,
-- EffectEnds).
local TALENT_DPS = "TALENT_DPS"
-- Arcane Concentration triggers at most once a second (SpellAuraOptions 11213: ProcCategoryRecovery 1000)
local CONCENTRATION_COOLDOWN = 1
-- Frostbolt's text gives its damage times $<frostdamage>: 1.02 while the mage knows Piercing Ice (spell 11151), at any
-- of its ranks (SpellDescriptionVariables 809: "$frostdamage1=$?s11151[${1.02}][${1.0}]"; its ranks 2 and 3 there,
-- spells 12952 and 12953, are not in the game); Piercing Ice's own percent comes in Mult
local FROST_DAMAGE = 1.02
local CHILL_SPELLS = { FROSTBOLT = true }
local SCHOOL = { ARCANE_BLAST = "arcane", ARCANE_MISSILES = "arcane", FIREBALL = "fire", SCORCH = "fire",
    FIRE_BLAST = "fire", PYROBLAST = "fire", FROSTBOLT = "frost", ICE_LANCE = "frost" }

-- Arcane Mind raises Intellect by a percent, an item's too (Character.WithStats): "Increases your Intellect by 10% and
-- increases the critical strike damage bonus of your Arcane spells by 100%." (its first percent; SpellEffect 11232:
-- aura 137 MOD_TOTAL_STAT_PERCENTAGE, EffectMiscValue[1] the stat mask: 8 Intellect).
function M.StatMods(c) return { str = 1, agi = 1, int = 1 + Talent(c, "ARCANE_MIND", "pct", 1) / 100 } end

function M.Setup(c)
    local ab, s = {}, c.spells
    local function A(key, fields)
        if not s[key] then return nil end
        -- a damage spell: its school and its shares of spell power (coef on a hit, dotCoef on a tick)
        if SCHOOL[key] then fields.school, fields.coef, fields.dotCoef = SCHOOL[key], Sim.SpellPower(s[key]) end
        return Sim.Ability(s[key], fields)
    end
    local function P(key, plain, time)
        local p = s[key].p
        assert(#p.plain >= plain and #p.time >= (time or 0), s[key].name .. ": unexpected description")
        return p
    end
    if s.FIREBALL then
        -- "causes 397 to 505 Fire damage and an additional 56 Fire damage over 8 sec"
        local p = P("FIREBALL", 3, 1)
        ab.fireball = A("FIREBALL", { damage = Average(p, 1), dot = p.plain[3], dotTime = p.time[1], fire = M.Bolt })
    end
    if s.FROSTBOLT then
        -- the text's damage without its $<frostdamage> (FROST_DAMAGE)
        local shown = c.talents.PIERCING_ICE and FROST_DAMAGE or 1
        ab.frostbolt = A("FROSTBOLT", { damage = Average(P("FROSTBOLT", 2), 1) / shown, fire = M.Bolt })
    end
    if s.SCORCH then ab.scorch = A("SCORCH", { damage = Average(P("SCORCH", 2), 1), fire = M.Bolt }) end
    if s.FIRE_BLAST then ab.fireBlast = A("FIRE_BLAST", { damage = Average(P("FIRE_BLAST", 2), 1), fire = M.Bolt }) end
    if s.PYROBLAST then
        local p = P("PYROBLAST", 3, 1)
        ab.pyroblast = A("PYROBLAST", { damage = Average(p, 1), dot = p.plain[3], dotTime = p.time[1], fire = M.Bolt })
    end
    if s.ARCANE_BLAST then
        -- "dealing 50 to 58 Arcane damage. Each time you cast Arcane Blast, the damage of all your other spells is
        -- increased by 10% and the mana cost of Arcane Blast is increased by 175%. Effect stacks up to 4 times and lasts
        -- 8 sec ..."
        local p = P("ARCANE_BLAST", 3, 1)
        assert(p.pct[2], "Arcane Blast: unexpected description")
        ab.arcaneBlast = A("ARCANE_BLAST", { damage = Average(p, 1), bonus = p.pct[1] / 100, stackCost = p.pct[2] / 100,
            stacks = p.plain[3], duration = p.time[1], fire = M.Bolt })
    end
    if s.ICE_LANCE then
        -- "Deals 26 to 30 Frost damage ... Deals 300% increased damage to Frozen targets."
        ab.iceLance = A("ICE_LANCE", { damage = Average(P("ICE_LANCE", 2), 1), frozen = 1 + s.ICE_LANCE.p.pct[1] / 100,
            fire = M.Bolt })
    end
    if s.ARCANE_MISSILES then
        -- "causing 25 Arcane damage each second for 3 sec": one missile a second
        local p = P("ARCANE_MISSILES", 1, 1)
        ab.missiles = A("ARCANE_MISSILES", { damage = p.plain[1], duration = p.time[1], tick = M.Missile,
            channel = { ticks = p.time[1], tick = 1 } })
    end
    if s.ARCANE_POWER then
        local p = s.ARCANE_POWER.p   -- "For the next 15 sec, your spells deal 30% more damage while costing 30% more mana"
        ab.arcanePower = A("ARCANE_POWER", { gcd = 0, duration = p.time[1], damage = p.pct[1] / 100,
            cost = 0, more = p.pct[2] / 100, fire = M.ArcanePower })
    end
    ab.presenceOfMind = A("PRESENCE_OF_MIND", { gcd = 0, cdKey = TALENT_DPS, fire = M.PresenceOfMind })
    ab.combustion = A("COMBUSTION", { gcd = 0, cdKey = TALENT_DPS, crit = s.COMBUSTION and s.COMBUSTION.p.pct[1],
        fire = M.Combustion })
    -- the filler of the spec
    ab.filler = c.spec == "FIRE" and (ab.fireball or ab.frostbolt) or c.spec == "FROST" and (ab.frostbolt or ab.fireball)
        or (ab.arcaneBlast or ab.frostbolt or ab.fireball)
    assert(ab.filler, "no damage spell")
    c.ab = ab
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- The talents' damage of a school (Arcane Instability, Fire Power, Piercing Ice), Arcane Blast's stacks on the other
-- spells but Arcane Missiles (the class mask of its buff's damage, SpellEffect 400573 #1: 12718707/4096, lacks the
-- missiles' bit, SpellClassOptions 7268 ...: 2097152), Arcane Power, Improved Scorch.
local function Mult(F, ab)
    local c = F.char
    local m = 1 + Talent(c, "ARCANE_INSTABILITY", "pct", 1) / 100
    if ab.school == "fire" then
        m = m * (1 + Talent(c, "FIRE_POWER", "pct") / 100)
        local scorch = F:Debuff("IMPROVED_SCORCH")
        if scorch then m = m * (1 + scorch.stacks * scorch.value) end
    elseif ab.school == "frost" then
        m = m * (1 + Talent(c, "PIERCING_ICE", "pct") / 100)
    end
    local blast = F:Buff("ARCANE_BLAST")
    if blast and ab.key ~= "ARCANE_BLAST" and ab.key ~= "ARCANE_MISSILES" then
        m = m * (1 + blast.stacks * blast.value)
    end
    local power = F:Buff("ARCANE_POWER")
    if power then m = m * (1 + power.value) end
    return m
end

-- The talents' hit with the spells of a school (Arcane Focus, Elemental Precision).
function M.SpellHit(c, school)
    return Talent(c, school == "arcane" and "ARCANE_FOCUS" or "ELEMENTAL_PRECISION", "pct")
end

-- The schools of the spells the fights cast, the main one first (the simulator window shows them): the filler's (the
-- spec's other spells are of its school), Arcane for the missiles of Missile Barrage while Arcane Blast is not known.
function M.Schools(c)
    local ab = c.ab
    local school = ab.filler.school
    if school ~= "arcane" and ab.missiles and not ab.arcaneBlast and c.talents.MISSILE_BARRAGE then
        return { school, "arcane" }
    end
    return { school }
end

-- The talents' hit and crit of a spell, and its crit damage (Ice Shards, Arcane Mind: more of the crit bonus).
local function Opts(F, ab, frozen)
    local c = F.char
    local hit = M.SpellHit(c, ab.school)
    local crit, bonus
    if ab.school == "arcane" then
        crit = Talent(c, "ARCANE_IMPACT", "pct")
        bonus = Talent(c, "ARCANE_MIND", "pct", 2)
    elseif ab.school == "fire" then
        bonus = 0
        crit = Talent(c, "CRITICAL_MASS", "pct")
        local combustion = F:Buff("COMBUSTION")
        if combustion then crit = crit + combustion.stacks * combustion.value end
    else
        crit = 0
        bonus = Talent(c, "ICE_SHARDS", "pct")
    end
    if ab.key == "FIRE_BLAST" or ab.key == "SCORCH" or ab.key == "ICE_LANCE" or ab.key == "ARCANE_BLAST" then
        crit = crit + Talent(c, "INCINERATION", "pct")
    end
    if ab.key == "FROSTBOLT" or ab.key == "ICE_LANCE" then
        local chill = F:Debuff("WINTERS_CHILL")
        if chill then crit = crit + chill.stacks * chill.value end
    end
    if frozen then crit = crit + Talent(c, "SHATTER", "pct") end
    return { hit = hit, crit = crit, critMult = 1 + 0.5 * (1 + bonus / 100) }
end

-- Ignite: a fire crit burns for a share of its damage over 4 seconds; what is left of the last one rolls into it. Its
-- burn does not crit (SpellMisc 412538: no "periodic can crit" flag).
local function Ignite(F, damage)
    local c = F.char
    if not c.talents.IGNITE then return end
    local ticks = Talent(c, "IGNITE", "time") / IGNITE_TICK
    local old = F:Debuff("IGNITE")
    local left = old and old.value * old.ticksLeft or 0
    F:Dot("IGNITE", (left + damage * Talent(c, "IGNITE", "pct") / 100) / ticks, ticks, IGNITE_TICK)
end

-- The effect of Presence of Mind or Combustion (ab) ends: the shared cooldown starts (TALENT_DPS).
local function EffectEnds(F, ab)
    F:RemoveBuff(ab.key)
    F:Cooldown(TALENT_DPS, ab.cooldown)
end

-- After a damage spell hit: Arcane Concentration (CONCENTRATION_COOLDOWN), Master of Elements, Winter's Chill, Fingers
-- of Frost, Frostbite, Missile Barrage, Heating Up, Combustion.
local function AfterHit(F, ab, result)
    local c = F.char
    if c.talents.ARCANE_CONCENTRATION and F:Ready("ARCANE_CONCENTRATION")
        and F:Roll() * 100 < Talent(c, "ARCANE_CONCENTRATION", "pct") then
        F:AddBuff("CLEARCASTING", F.len)
        F:Cooldown("ARCANE_CONCENTRATION", CONCENTRATION_COOLDOWN)
    end
    if result == Sim.CRIT and (ab.school == "fire" or ab.school == "frost") and c.talents.MASTER_OF_ELEMENTS then
        F:GainMana(ab.cost * Talent(c, "MASTER_OF_ELEMENTS", "pct") / 100)
    end
    if ab.school == "frost" and c.talents.WINTERS_CHILL and F:Roll() * 100 < Talent(c, "WINTERS_CHILL", "pct", 1) then
        F:AddDebuff("WINTERS_CHILL", Talent(c, "WINTERS_CHILL", "time"), Talent(c, "WINTERS_CHILL", "pct", 2),
            Talent(c, "WINTERS_CHILL", "plain"))
    end
    if CHILL_SPELLS[ab.key] and c.talents.FINGERS_OF_FROST and F:Roll() * 100 < Talent(c, "FINGERS_OF_FROST", "pct") then
        F:AddBuff("FINGERS_OF_FROST", Talent(c, "FINGERS_OF_FROST", "time")).stacks = Talent(c, "FINGERS_OF_FROST", "plain")
    end
    -- Frostbite: "Gives your Chill effects a 5% chance to Freeze the target for 5 sec." (damage does not break it:
    -- CMaNGOS spell_template 12494 has no aura interrupt flags)
    if CHILL_SPELLS[ab.key] and c.talents.FROSTBITE and F:Roll() * 100 < Talent(c, "FROSTBITE", "pct") then
        F:AddDebuff("FROSTBITE", Talent(c, "FROSTBITE", "time"))
    end
    if c.talents.MISSILE_BARRAGE and c.ab.missiles then
        -- "Gives your Arcane Blast spell a 40% chance, and your Fireball, Frostbolt, and Frostfire Bolt spells a 20%
        -- chance ..."
        local chance = ab.key == "ARCANE_BLAST" and Talent(c, "MISSILE_BARRAGE", "pct", 1)
            or (ab.key == "FIREBALL" or ab.key == "FROSTBOLT") and Talent(c, "MISSILE_BARRAGE", "pct", 2) or 0
        if F:Roll() * 100 < chance then F:AddBuff("MISSILE_BARRAGE", F.len) end
    end
    if result == Sim.CRIT and c.talents.HEATING_UP and (ab.key == "FIREBALL" or ab.key == "FIRE_BLAST" or ab.key == "SCORCH") then
        F:AddBuff("HEATING_UP", Talent(c, "HEATING_UP", "time"), Talent(c, "HEATING_UP", "pct") / 100,
            Talent(c, "HEATING_UP", "plain"))
    end
    local combustion = F:Buff("COMBUSTION")
    if combustion and ab.school == "fire" then
        combustion.stacks = combustion.stacks + 1
        if result == Sim.CRIT then
            combustion.crits = combustion.crits + 1
            if combustion.crits >= COMBUSTION_CRITS then EffectEnds(F, c.ab.combustion) end
        end
    end
end

-- A bolt (any direct damage spell, with its damage over time); the target counts as frozen with Fingers of Frost or
-- while Frostbite holds it.
function M.Bolt(F, ab)
    local c = F.char
    local fof = F:Buff("FINGERS_OF_FROST")
    local frozen = fof ~= nil or F:Debuff("FROSTBITE") ~= nil
    if fof then
        fof.stacks = fof.stacks - 1
        if fof.stacks <= 0 then F:RemoveBuff("FINGERS_OF_FROST") end
    end
    local mult = Mult(F, ab)
    local amount = (ab.damage + ab.coef * c.sp[ab.school]) * mult * (frozen and ab.frozen or 1)
    local result, damage = F:SpellHit(ab.key, ab.school, amount, Opts(F, ab, frozen))
    if ab.key ~= "ARCANE_BLAST" then F:RemoveBuff("ARCANE_BLAST") end
    if result == Sim.MISS then return end
    if ab.dot and ab.dot > 0 then
        local tick = ab.key == "PYROBLAST" and PYROBLAST_TICK or FIREBALL_TICK
        local ticks = ab.dotTime / tick
        -- the burn of Fireball or Pyroblast crits: every rank has SpellMisc Attributes[8] 0x200 ("periodic can crit"),
        -- a magic one (SpellCategories DefenseType 1). Its chance: the Fire spell crit with the talents of the spell
        -- (Opts): Critical Mass and Combustion's buff reach it (their class masks, SpellEffect 11115 and 28682:
        -- 12582935/4096, have the bits of Fireball, SpellClassOptions 133 ...: 1073741825, and of Pyroblast, 11366
        -- ...: 1077936128), at 150 % (no crit damage talent reaches them); Shatter's frozen target not (a dummy aura
        -- without a class mask: not proven for a tick). A tick's crit triggers no Ignite, Master of Elements, Heating
        -- Up nor Combustion's count (SpellAuraOptions ProcTypeMask 65536 of each: no periodic bit 0x40000).
        local burn = Opts(F, ab)
        F:Dot(ab.key .. "_DOT", (ab.dot / ticks + ab.dotCoef * c.sp[ab.school]) * mult * F:Resist(), ticks, tick,
            { crit = c.spellCrit[ab.school] + burn.crit, critMult = burn.critMult })
    end
    if ab.key == "ARCANE_BLAST" then F:AddBuff("ARCANE_BLAST", ab.duration, ab.bonus, ab.stacks) end
    if ab.key == "SCORCH" and c.talents.IMPROVED_SCORCH and F:Roll() * 100 < Talent(c, "IMPROVED_SCORCH", "pct", 1) then
        F:AddDebuff("IMPROVED_SCORCH", Talent(c, "IMPROVED_SCORCH", "time"), Talent(c, "IMPROVED_SCORCH", "pct", 2) / 100,
            Talent(c, "IMPROVED_SCORCH", "plain"))
    end
    if ab.key == "PYROBLAST" then F:RemoveBuff("HEATING_UP") end
    if result == Sim.CRIT and ab.school == "fire" then Ignite(F, damage) end
    AfterHit(F, ab, result)
end

-- One missile of Arcane Missiles (the first spends Arcane Blast's stacks when the channel ends); the target counts as
-- frozen while Frostbite holds it.
function M.Missile(F, ab, n)
    local c = F.char
    local amount = (ab.damage + ab.coef * c.sp.arcane) * Mult(F, ab)
    local result = F:SpellHit("ARCANE_MISSILES", "arcane", amount, Opts(F, ab, F:Debuff("FROSTBITE") ~= nil))
    if result ~= Sim.MISS and n == 1 then AfterHit(F, ab, result) end
    if n == F.channel.ticks then F:RemoveBuff("ARCANE_BLAST") end
end

function M.ArcanePower(F, ab) F:AddBuff("ARCANE_POWER", ab.duration, ab.damage).more = ab.more end

-- Presence of Mind and Combustion: the effect lasts until it is used up (EffectEnds); till then neither of the two is
-- used again (the cooldown F:Use started waits for that end: TALENT_DPS).
function M.PresenceOfMind(F)
    F:AddBuff("PRESENCE_OF_MIND", F.len)
    F:Cooldown(TALENT_DPS, F.len)
end

function M.Combustion(F, ab)
    local buff = F:AddBuff("COMBUSTION", F.len, ab.crit)
    buff.stacks, buff.crits = 0, 0
    F:Cooldown(TALENT_DPS, F.len)
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
-- The cost of a cast now: Clearcasting makes it free, Arcane Blast's stacks and Arcane Power make it dearer.
local function Cost(F, ab)
    if F:Buff("CLEARCASTING") then return 0 end
    local cost = ab.cost
    local blast = F:Buff("ARCANE_BLAST")
    if ab.key == "ARCANE_BLAST" and blast then cost = cost * (1 + blast.stacks * ab.stackCost) end
    local power = F:Buff("ARCANE_POWER")
    if power then cost = cost * (1 + power.more) end
    return cost
end

-- Casts a spell: Clearcasting and Presence of Mind are used up; Heating Up shortens Pyroblast; Missile Barrage makes
-- Arcane Missiles free and quick.
local function Cast(F, ab)
    local cost = Cost(F, ab)
    if not F:Can(ab, cost) then return false end
    F:RemoveBuff("CLEARCASTING")
    if ab.channel then
        local barrage = F:Buff("MISSILE_BARRAGE")
        ab.channel = { ticks = ab.duration, tick = barrage and 0.5 or 1 }
        if barrage then
            cost = 0
            F:RemoveBuff("MISSILE_BARRAGE")
        end
        F:Use(ab, cost)
        return true
    end
    local cast = ab.cast
    local heating = ab.key == "PYROBLAST" and F:Buff("HEATING_UP")
    if heating then cast = cast * (1 - heating.stacks * heating.value) end
    if cast > 0 and F:Buff("PRESENCE_OF_MIND") then
        cast = 0
        EffectEnds(F, F.char.ab.presenceOfMind)
    end
    F:Use(ab, cost, cast)
    return true
end

function M.Act(F)
    local c = F.char
    local ab = c.ab
    if F:Can(ab.arcanePower) then F:Use(ab.arcanePower) end
    -- one cooldown for both (TALENT_DPS): Fire's Combustion first, the others' Presence of Mind
    local first, second = ab.presenceOfMind, ab.combustion
    if c.spec == "FIRE" then first, second = second, first end
    if F:Can(first) then F:Use(first) end
    if F:Can(second) then F:Use(second) end
    if ab.missiles and F:Buff("MISSILE_BARRAGE") and (not ab.arcaneBlast or F:Buff("ARCANE_BLAST")) then
        if Cast(F, ab.missiles) then return end
    end
    if c.spec == "FIRE" then
        local scorch = F:Debuff("IMPROVED_SCORCH")
        if ab.scorch and c.talents.IMPROVED_SCORCH and (not scorch
            or scorch.stacks < Talent(c, "IMPROVED_SCORCH", "plain") or scorch.ends - F.t < SCORCH_REFRESH) then
            if Cast(F, ab.scorch) then return end
        end
        local heating = F:Buff("HEATING_UP")
        if ab.pyroblast and heating and heating.stacks >= Talent(c, "HEATING_UP", "plain") and Cast(F, ab.pyroblast) then
            return
        end
        if ab.fireBlast and Cast(F, ab.fireBlast) then return end
    elseif c.spec == "FROST" then
        local frozen = F:Buff("FINGERS_OF_FROST") or F:Debuff("FROSTBITE")
        if ab.iceLance and frozen and Cast(F, ab.iceLance) then return end
    elseif ab.arcaneBlast and ab.missiles then
        local blast = F:Buff("ARCANE_BLAST")
        if blast and blast.stacks >= ab.arcaneBlast.stacks and Cast(F, ab.missiles) then return end
    end
    if Cast(F, ab.filler) then return end
    -- short of mana: the mana ticks ask again
    local function At(a) return a and F:ReadyAt(a.cdKey or a.key) end
    return F:Next(At(ab.fireBlast), At(ab.arcanePower), At(ab.presenceOfMind), At(ab.combustion))
end
