-- Lootified - simulator model of the Elemental and the Enhancement Shaman in WoW: Forever (the Restoration shaman plays
-- Elemental's rotation with what it knows: its damage with its gear). Elemental keeps Flame Shock
-- up, casts Lava Burst and Chain Lightning on cooldown, Earth Shock or Frost Shock when the shock is ready again and
-- Lightning Bolt in between (Lightning Overload adds half bolts). Enhancement fights in melee with the imbues on its
-- weapons (Windfury, Flametongue: read from the game), Stormstrike on cooldown, Earth Shock or Frost Shock after it and
-- Rage of the Farseer on cooldown. The fights play each of the two shocks and keep the one that does more
-- (M.Variants). Talents: Concussion, Call of Flame, Elemental Focus, Call of Thunder, Lightning Overload, Elemental
-- Fury, Elemental Devastation, Mental Dexterity, Elemental Weapons, Flurry, Mental Quickness. Numbers from the game's
-- descriptions, costs, cast times and cooldowns from the game; spell power shares from the game's own tables
-- (Sim.SpellPower); rules below (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent, Average = Sim.Talent, Sim.Average

local M = { class = "SHAMAN", specs = { ELE = true, ENH = true, RESTO = true }, hands = { "mh", "oh" } }
Sim.models.SHAMAN = M

local min, max = math.min, math.max

M.spells = {
    LIGHTNING_BOLT = 403, CHAIN_LIGHTNING = 421, EARTH_SHOCK = 8042, FLAME_SHOCK = 8050, LAVA_BURST = 408490,
    STORMSTRIKE = 17364, RAGE_OF_THE_FARSEER = 425336, FROST_SHOCK = 8056,
}
M.talents = {
    CONCUSSION = 16035, CALL_OF_FLAME = 16038, ELEMENTAL_FOCUS = 16164, CALL_OF_THUNDER = 16120,
    LIGHTNING_OVERLOAD = 408438, ELEMENTAL_FURY = 16089, MENTAL_DEXTERITY = 415140, ELEMENTAL_WEAPONS = 16266,
    FLURRY = 16256, MENTAL_QUICKNESS = 30812, ELEMENTAL_DEVASTATION = 30160,
    ANCESTRAL_KNOWLEDGE = 17485,
}

-- The imbues by the enchantment they put on a weapon (CMaNGOS spell_template: the imbue spells, effect 54).
local IMBUES = {
    [283] = { "WINDFURY", 8232 }, [284] = { "WINDFURY", 8235 }, [525] = { "WINDFURY", 10486 },
    [1669] = { "WINDFURY", 16362 },
    [5] = { "FLAMETONGUE", 8024 }, [4] = { "FLAMETONGUE", 8027 }, [3] = { "FLAMETONGUE", 8030 },
    [523] = { "FLAMETONGUE", 16339 }, [1665] = { "FLAMETONGUE", 16341 }, [1666] = { "FLAMETONGUE", 16342 },
}
-- The first rank of each imbue (the simulator window names an imbue's damage by it).
M.weaponSpells = { WINDFURY = 8232, FLAMETONGUE = 8024 }
-- The damage that rides on the hits (Flametongue's; Windfury's are attacks): no attacks of their own (the simulator
-- window's summary).
M.procs = { FLAMETONGUE = true }

local SCHOOL = { LIGHTNING_BOLT = "nature", CHAIN_LIGHTNING = "nature", EARTH_SHOCK = "nature", FLAME_SHOCK = "fire",
    LAVA_BURST = "fire", FROST_SHOCK = "frost" }
local CONCUSSION = { LIGHTNING_BOLT = true, CHAIN_LIGHTNING = true, EARTH_SHOCK = true }
local CALL_OF_FLAME = { FLAME_SHOCK = true, FLAME_SHOCK_DOT = true, LAVA_BURST = true }
local STORMSTRIKE = { LIGHTNING_BOLT = true, CHAIN_LIGHTNING = true, EARTH_SHOCK = true }
local OVERLOAD = { LIGHTNING_BOLT = true, CHAIN_LIGHTNING = true }
local FLAME_SHOCK_TICK = 3
local OFF_HAND = 0.5
local FLURRY_SWINGS = 3
local FLAMETONGUE_SPEED = 4            -- Flametongue's top damage at a weapon speed of 4 (slower weapons, more fire)
-- Flametongue's share of spell power: its damage spell's, the one the imbue's text adds to its damage (rank 1:
-- Flametongue Attack 29469, rank 2: 29470, ranks 3 to 6: 10444; SpellEffect, 0.1 each)
local SP_FLAMETONGUE = 0.1
-- Windfury's proc cooldown: the aura the imbue's enchantments put on (SpellItemEnchantment 283, 284, 525, 1669: 439431)
-- procs at most every 1.5 sec (SpellAuraOptions 439431: ProcCategoryRecovery 1500 ms), each weapon's its own
local WINDFURY_COOLDOWN = 1.5

-- Ancestral Knowledge raises Intellect by a percent, an item's too (Character.WithStats): "Increases your Intellect by
-- 10%." (SpellEffect 17485: aura 137 MOD_TOTAL_STAT_PERCENTAGE, EffectMiscValue[1] the stat mask: 8 Intellect).
function M.StatMods(c) return { str = 1, agi = 1, int = 1 + Talent(c, "ANCESTRAL_KNOWLEDGE", "pct") / 100 } end

function M.Setup(c)
    local ab, s = {}, c.spells
    local caster = c.spec ~= "ENH"   -- Elemental, Restoration
    if caster then c.hands = {} else assert(c.mh, "no weapon") end
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
    if s.LIGHTNING_BOLT then ab.bolt = A("LIGHTNING_BOLT", { damage = Average(P("LIGHTNING_BOLT", 2), 1), fire = M.Bolt }) end
    if s.CHAIN_LIGHTNING then
        ab.chain = A("CHAIN_LIGHTNING", { damage = Average(P("CHAIN_LIGHTNING", 2), 1), fire = M.Bolt })
    end
    if s.EARTH_SHOCK then ab.earthShock = A("EARTH_SHOCK", { cdKey = "SHOCK", damage = Average(P("EARTH_SHOCK", 2), 1),
        fire = M.Bolt }) end
    -- "causing 64 to 68 Frost damage and slowing movement speed by 50%"
    if s.FROST_SHOCK then ab.frostShock = A("FROST_SHOCK", { cdKey = "SHOCK", damage = Average(P("FROST_SHOCK", 2), 1),
        fire = M.Bolt }) end
    if s.FLAME_SHOCK then
        -- "causing 24 Fire damage immediately and 28 Fire damage over 12 sec"
        local p = P("FLAME_SHOCK", 2, 1)
        ab.flameShock = A("FLAME_SHOCK", { cdKey = "SHOCK", damage = p.plain[1], dot = p.plain[2],
            ticks = p.time[1] / FLAME_SHOCK_TICK, fire = M.Bolt })
    end
    if s.LAVA_BURST then
        -- "dealing 143 to 185 Fire damage. If your Flame Shock is on the target, Lava Burst deals 20% increased damage."
        local p = P("LAVA_BURST", 2)
        ab.lavaBurst = A("LAVA_BURST", { damage = Average(p, 1), shocked = p.pct[1] / 100, fire = M.Bolt })
    end
    if not caster then
        if s.STORMSTRIKE then
            -- "... increase the damage you deal ... with your next Lightning Bolt, Chain Lightning, or Earth Shock spell by
            -- 20% for 12 sec"
            local p = s.STORMSTRIKE.p
            ab.stormstrike = A("STORMSTRIKE", { bonus = p.pct[1] / 100, duration = p.time[1], fire = M.Stormstrike })
        end
        if s.RAGE_OF_THE_FARSEER and not s.RAGE_OF_THE_FARSEER.passive then
            -- "Increases your attack speed by 30% for 25 sec.", no global cooldown (SpellCooldowns 425336:
            -- StartRecoveryTime 0)
            local p = s.RAGE_OF_THE_FARSEER.p
            ab.farseer = A("RAGE_OF_THE_FARSEER", { haste = p.pct[1] / 100, duration = p.time[1], gcd = 0,
                fire = M.Farseer })
        end
    end
    assert(not caster or ab.bolt, "no damage spell")
    -- the imbues on the weapons
    c.imbues, c.weaponSpells = {}, {}
    for hand, list in pairs(c.enchants) do
        local imbue
        for _, enchant in ipairs(list) do imbue = imbue or IMBUES[enchant] end
        if imbue and c[hand] and not caster then
            local d = Sim.Character.Describe(imbue[2])
            local p = d.p
            assert(p.plain[2], d.name .. ": unexpected description")
            if imbue[1] == "WINDFURY" then
                -- "Each hit has a 20% chance of granting you 2 extra attacks with 333 extra melee attack power."
                assert(p.pct[1], d.name .. ": unexpected description")
                c.imbues[hand] = { key = "WINDFURY", chance = p.pct[1], attacks = p.plain[1], ap = p.plain[2] }
            else
                -- "Each hit causes 31 to 100 additional Fire damage, based on the speed of the weapon."
                c.imbues[hand] = { key = "FLAMETONGUE", low = p.plain[1], high = p.plain[2] }
            end
            c.weaponSpells[imbue[1]] = imbue[2]
        end
    end
    c.ab = ab
end

-- The schools of the spells the fights cast (the simulator window shows them): Elemental's bolts and shocks (Fire once
-- it has Flame Shock or Lava Burst), Enhancement's Earth Shock; Frost for Frost Shock (a way to play, M.Variants).
function M.Schools(c)
    local ab = c.ab
    local schools
    if c.spec == "ENH" then
        schools = ab.earthShock and { "nature" } or {}
    else
        schools = (ab.flameShock or ab.lavaBurst) and { "nature", "fire" } or { "nature" }
    end
    if ab.frostShock then schools[#schools + 1] = "frost" end
    return schools
end

-- The ways the fights play the character: the shock it casts besides Flame Shock, each of Earth Shock and Frost Shock
-- it has ("EARTH_SHOCK", "FROST_SHOCK"; Sim.Jobs.Fights fights each way and keeps the one that does more): they differ
-- in damage and cost, and only Earth Shock has Concussion and Stormstrike. None without a shock yet (one way).
local SHOCKS = { EARTH_SHOCK = "earthShock", FROST_SHOCK = "frostShock" }
function M.Variants(c)
    local list = {}
    for _, key in ipairs({ "EARTH_SHOCK", "FROST_SHOCK" }) do
        if c.ab[SHOCKS[key]] then list[#list + 1] = key end
    end
    return list[1] and list or nil
end

-- Mental Dexterity and Mental Quickness: shares of Intellect as attack power and spell power.
function M.WithIntellect(c, int)
    c.ap = c.ap + int * Talent(c, "MENTAL_DEXTERITY", "pct") / 100
    for school, sp in pairs(c.sp) do c.sp[school] = sp + int * Talent(c, "MENTAL_QUICKNESS", "pct") / 100 end
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local function Mult(F, ab, key)
    local c = F.char
    key = key or ab.key
    local m = 1
    if CONCUSSION[key] then m = m * (1 + Talent(c, "CONCUSSION", "pct") / 100) end
    if CALL_OF_FLAME[key] then m = m * (1 + Talent(c, "CALL_OF_FLAME", "pct") / 100) end
    return m
end

local function Opts(c, ab)
    local crit = OVERLOAD[ab.key] and Talent(c, "CALL_OF_THUNDER", "pct") or 0
    return { crit = crit, critMult = 1 + 0.5 * (1 + Talent(c, "ELEMENTAL_FURY", "pct") / 100) }
end

function M.Bolt(F, ab)
    local c = F.char
    local mult = Mult(F, ab)
    if ab.key == "LAVA_BURST" and F:Debuff("FLAME_SHOCK_DOT") then mult = mult * (1 + ab.shocked) end
    local storm = STORMSTRIKE[ab.key] and F:Debuff("STORMSTRIKE")
    if storm then
        mult = mult * (1 + storm.value)
        F.debuffs.STORMSTRIKE = nil
    end
    local amount = (ab.damage + ab.coef * c.sp[ab.school]) * mult
    local opts = Opts(c, ab)
    local result = F:SpellHit(ab.key, ab.school, amount, opts)
    -- Elemental Devastation: "Your offensive spell critical strikes will increase your chance to get a critical strike
    -- with melee attacks by 3% for 10 sec."
    if result == Sim.CRIT and c.talents.ELEMENTAL_DEVASTATION then
        F:AddBuff("ELEMENTAL_DEVASTATION", Talent(c, "ELEMENTAL_DEVASTATION", "time"),
            Talent(c, "ELEMENTAL_DEVASTATION", "pct"))
    end
    -- Elemental Focus: a free next spell
    if c.talents.ELEMENTAL_FOCUS and F:Roll() * 100 < Talent(c, "ELEMENTAL_FOCUS", "pct") then
        F:AddBuff("CLEARCASTING", F.len)
    end
    if result == Sim.MISS then return end
    if ab.dot then
        -- the burn's ticks crit (SpellMisc Attributes[8] 0x200 "periodic can crit" on every rank of Flame Shock, a
        -- magic spell: SpellCategories DefenseType 1) as its hit: the fire spell crit, Elemental Fury's crit damage
        -- bonus (its class mask reaches Flame Shock: SpellEffect 16089 -785382397/4096/0/1073741824, SpellClassOptions
        -- 8050 ...: 268435456/0/0/0; Call of Thunder's crit does not: 3/0/0/0); a tick's crit gives no Elemental
        -- Devastation (SpellAuraOptions 30160: ProcTypeMask 65536, without the periodic bit 0x40000)
        local perTick = (ab.dot / ab.ticks + ab.dotCoef * c.sp.fire) * Mult(F, ab, "FLAME_SHOCK_DOT") * F:Resist()
        F:Dot("FLAME_SHOCK_DOT", perTick, ab.ticks, FLAME_SHOCK_TICK,
            { crit = c.spellCrit.fire + opts.crit, critMult = opts.critMult })
    end
    -- Lightning Overload: a second bolt of half the damage
    if OVERLOAD[ab.key] and c.talents.LIGHTNING_OVERLOAD and F:Roll() * 100 < Talent(c, "LIGHTNING_OVERLOAD", "pct") then
        F:SpellHit(ab.key, ab.school, amount / 2, Opts(c, ab))
    end
end

---------------------------------------------------------------------------
-- Melee
---------------------------------------------------------------------------
local function OnCrit(F)
    local c = F.char
    if c.talents.FLURRY then F:AddBuff("FLURRY", F.len, Talent(c, "FLURRY", "pct") / 100).stacks = FLURRY_SWINGS end
end

-- Flametongue: fire damage by the weapon's speed and spell power (Elemental Weapons on both), a spell's hit and crit.
local function Flametongue(F, w, imbue)
    local c = F.char
    local bySpeed = max(imbue.low, min(imbue.high, imbue.high * w.speed / FLAMETONGUE_SPEED))
    local damage = (bySpeed + SP_FLAMETONGUE * c.sp.fire) * (1 + Talent(c, "ELEMENTAL_WEAPONS", "pct", 3) / 100)
    F:SpellHit("FLAMETONGUE", "fire", damage, Opts(c, {}))
end

-- The shaman as the attacker of a melee hit (Fight:WhiteResult, Fight:SpecialResult): Elemental Devastation's crit
-- while it lasts.
local function Attacker(F)
    local c, devastation = F.char, F:Buff("ELEMENTAL_DEVASTATION")
    if not devastation then return c end
    return { level = c.level, hit = c.hit, crit = c.crit + devastation.value, dodgeReduce = c.dodgeReduce }
end

-- A melee hit of a hand: white (glancing, the dual-wield miss) or an ability; ap: extra attack power (Windfury);
-- normalized: normalized weapon speed (Stormstrike: SpellEffect 17364, NORMALIZED_WEAPON_DMG). Returns the result.
local function Melee(F, key, hand, white, ap, normalized)
    local c, w = F.char, F.char[hand]
    local who = Attacker(F)
    local result = white and F:WhiteResult(w, c.oh ~= nil, who) or F:SpecialResult(w, 0, false, who)
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = F:WeaponRoll(w, c.ap + (ap or 0), normalized) * (hand == "oh" and OFF_HAND or 1)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * 2
        end
        damage = F:AfterArmor(damage)
        local imbue = c.imbues[hand]
        if imbue and imbue.key == "FLAMETONGUE" then Flametongue(F, w, imbue) end
    end
    F:Record(key, damage, result)
    if result == Sim.CRIT then OnCrit(F) end
    return result
end

-- Windfury: a hit may grant extra attacks of its hand with more attack power (Elemental Weapons); those attacks do not
-- grant more, nor does a hit of that hand within WINDFURY_COOLDOWN of the last ones.
local function Windfury(F, hand)
    local c = F.char
    local imbue = c.imbues[hand]
    local cooldown = "WINDFURY_" .. hand
    if not (imbue and imbue.key == "WINDFURY" and F:Ready(cooldown)) or F:Roll() * 100 >= imbue.chance then return end
    F:Cooldown(cooldown, WINDFURY_COOLDOWN)
    local ap = imbue.ap * (1 + Talent(c, "ELEMENTAL_WEAPONS", "pct", 2) / 100)
    for _ = 1, imbue.attacks do Melee(F, "WINDFURY", hand, true, ap) end
end

function M.Swing(F, hand)
    local result = Melee(F, "MELEE", hand, true)
    if result ~= Sim.MISS and result ~= Sim.DODGE then Windfury(F, hand) end
    local flurry = F:Buff("FLURRY")
    if flurry and result ~= Sim.CRIT then
        flurry.stacks = flurry.stacks - 1
        if flurry.stacks <= 0 then F:RemoveBuff("FLURRY") end
    end
end

function M.Haste(F)
    local h = 1
    local flurry = F:Buff("FLURRY")
    if flurry then h = h * (1 + flurry.value) end
    local farseer = F:Buff("RAGE_OF_THE_FARSEER")
    if farseer then h = h * (1 + farseer.value) end
    return h
end

function M.Stormstrike(F, ab)
    local result = Melee(F, "STORMSTRIKE", "mh", false, nil, true)
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        Windfury(F, "mh")
        F:AddDebuff("STORMSTRIKE", ab.duration, ab.bonus)
    end
end

function M.Farseer(F, ab) F:AddBuff("RAGE_OF_THE_FARSEER", ab.duration, ab.haste) end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
local function Cast(F, ab)
    if not ab then return false end
    -- Clearcasting: the next damage spell is free
    local free = ab.school and F:Buff("CLEARCASTING")
    local cost = free and 0 or nil
    if not F:Can(ab, cost) then return false end
    if free then F:RemoveBuff("CLEARCASTING") end
    F:Use(ab, cost)
    return true
end

-- The shock of the way the fight plays (M.Variants; none without a way).
function M.Start(F)
    F.shock = F.opts.variant and F.char.ab[SHOCKS[Sim.VariantKeys(F.opts.variant)[1]]]
end

function M.Act(F)
    local ab = F.char.ab
    if F.char.spec == "ENH" then
        -- (no global cooldown: the next ability at once)
        Cast(F, ab.farseer)
        if Cast(F, ab.stormstrike) then return end
        if Cast(F, F.shock) then return end
    else
        if not F:Debuff("FLAME_SHOCK_DOT") and Cast(F, ab.flameShock) then return end
        if Cast(F, ab.lavaBurst) then return end
        if Cast(F, ab.chain) then return end
        if F:Debuff("FLAME_SHOCK_DOT") or not ab.flameShock then
            if Cast(F, F.shock) then return end
        end
        if Cast(F, ab.bolt) then return end
    end
    local function At(a) return a and F:ReadyAt(a.cdKey or a.key) end
    return F:Next(At(ab.stormstrike), At(F.shock), At(ab.flameShock), At(ab.lavaBurst), At(ab.chain), At(ab.farseer))
end
