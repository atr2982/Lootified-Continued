-- Lootified - simulator model of the Warlock in WoW: Forever. Every spec keeps its damage over time up: a Bane (Bane
-- of Doom while the fight lasts a minute more and it does more, else Bane of Agony), Corruption, Immolate and Siphon
-- Life; Life Tap when the mana does not pay for the next spell. In between it casts a filler: the fights play each
-- filler of the spec the character has and keep the one that does more (M.Variants). Affliction channels Wrack or
-- Drain Life or casts Shadow Bolt (Nightfall makes one instant); Demonology casts Shadow Bolt or Searing Pain and, with
-- Decimation, a quick Soul Fire when the target is low (it keeps the mana for one); Destruction casts Conflagrate and
-- (with Shadow and Flame) Shadowburn on cooldown and Incinerate, Shadow Bolt or Searing Pain in between. The ticks of
-- the damage over time and of the channels crit, Siphon Life's not. The demon that is out fights along (Sim/Pet.lua);
-- a sacrificed one counts (Demonic Sacrifice). Talents: Improved Life Tap, Improved Corruption, Malediction, Improved
-- Drains, Improved Bane of Agony, Pandemic, Malevolence, Nightfall, Soul Siphon, Shadow Mastery, Improved Imp,
-- Improved Sayaad, Demonic Sacrifice, Decimation, Soul Link, Master Demonologist, Demonic Brand, Improved Shadow Bolt,
-- Aftermath, Ruin, Agonizing Flames, Fire and Brimstone, Shadow and Flame (Unholy Power is in the demon's own numbers
-- and in the texts of its spells and of Demonic Brand). Numbers from the game's descriptions, costs, cast times and
-- cooldowns from the game; spell power shares from the game's own tables (Sim.SpellPower); rules below (beta build
-- 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent, Average = Sim.Talent, Sim.Average

local M = { class = "WARLOCK", specs = { AFFLI = true, DEMO = true, DESTRO = true }, hands = {} }
Sim.models.WARLOCK = M

M.spells = {
    SHADOW_BOLT = 686, CORRUPTION = 172, BANE_OF_AGONY = 980, BANE_OF_DOOM = 603, IMMOLATE = 348, LIFE_TAP = 1454,
    SIPHON_LIFE = 18265, WRACK = 1316697, CONFLAGRATE = 1293817, SHADOWBURN = 17877, INCINERATE = 412758,
    SOUL_FIRE = 6353, DRAIN_LIFE = 689, SEARING_PAIN = 5676,
}
M.talents = {
    IMPROVED_LIFE_TAP = 18182, IMPROVED_CORRUPTION = 17810, MALEDICTION = 1225177, IMPROVED_DRAINS = 403511,
    IMPROVED_BANE_OF_AGONY = 18827, PANDEMIC = 427712, MALEVOLENCE = 1310949, NIGHTFALL = 18094, SOUL_SIPHON = 17804,
    SHADOW_MASTERY = 18271, IMPROVED_IMP = 18694, IMPROVED_SAYAAD = 18754, DEMONIC_SACRIFICE = 18788,
    DECIMATION = 440870, SOUL_LINK = 19028, MASTER_DEMONOLOGIST = 23785, DEMONIC_BRAND = 1293695,
    IMPROVED_SHADOW_BOLT = 17793, AFTERMATH = 18119, RUIN = 17959, AGONIZING_FLAMES = 17927,
    FIRE_AND_BRIMSTONE = 412751, SHADOW_AND_FLAME = 426316,
}
M.petSpells = { FIREBOLT = 3110, LASH_OF_PAIN = 7814 }
-- The damage that rides on the demon's attacks (Demonic Brand's): no attacks of their own (the simulator window's
-- summary).
M.procs = { DEMONIC_BRAND = true }

local TICK = { CORRUPTION = 3, BANE_OF_AGONY = 2, IMMOLATE = 3, SIPHON_LIFE = 3 }
local SCHOOL = { SHADOW_BOLT = "shadow", CORRUPTION = "shadow", BANE_OF_AGONY = "shadow", BANE_OF_DOOM = "shadow",
    IMMOLATE = "fire", SIPHON_LIFE = "shadow", WRACK = "shadow", CONFLAGRATE = "fire", SHADOWBURN = "shadow",
    INCINERATE = "fire", SOUL_FIRE = "fire", DRAIN_LIFE = "shadow", SEARING_PAIN = "fire" }
-- Destruction's spells (Ruin, Agonizing Flames)
local DESTRUCTION = { SHADOW_BOLT = true, IMMOLATE = true, IMMOLATE_DOT = true, CONFLAGRATE = true, SHADOWBURN = true,
    INCINERATE = true, SOUL_FIRE = true, SEARING_PAIN = true }
-- the spells whose crit damage bonus Pandemic raises (its class mask, SpellEffect 427712: 17418/262147, has their
-- bits), and Affliction's effects for Soul Siphon
local PANDEMIC = { CORRUPTION = true, BANE_OF_AGONY = true, BANE_OF_DOOM = true, SIPHON_LIFE = true, WRACK = true,
    DRAIN_LIFE = true }
local AFFLICTION = { "CORRUPTION", "BANE_OF_AGONY", "BANE_OF_DOOM", "SIPHON_LIFE" }
-- Whether the ticks of a damage over time or channel crit: true where every rank of the spell has SpellMisc
-- Attributes[8] 0x200 ("periodic can crit"), all magic ones (SpellCategories DefenseType 1); Siphon Life's ranks
-- (18265 ...) have no flag. They crit without Pandemic, which raises their crit damage bonus (its text; the owner's
-- research, answer 7).
local PERIODIC_CRIT = { CORRUPTION = true, BANE_OF_AGONY = true, BANE_OF_DOOM = true, IMMOLATE = true, WRACK = true,
    DRAIN_LIFE = true, SIPHON_LIFE = false }
-- the damage over time Wrack's debuff raises: its effect's class mask (SpellEffect 1316697 #2: 1026) has the bits of
-- Corruption (SpellClassOptions: 2) and Bane of Agony (1024), not those of Bane of Doom, Siphon Life or Drain Life
local WRACKED = { CORRUPTION = true, BANE_OF_AGONY = true }
local NIGHTFALL = { CORRUPTION = true, WRACK = true, DRAIN_LIFE = true }
local DECIMATION_PHASE = 0.65          -- the target is below 35 % health for the last 35 % of the fight
local DECIMATION_TIME = 10
-- Demonic Sacrifice: the effect of each sacrificed demon (Forever: the imp's grows Shadow, the succubus' Fire damage)
-- and where the text has its number ("Imp: Increases your Shadow damage by 15%. Voidwalker: Restores 2% of your total
-- Mana ... Succubus/Incubus: Increases your Fire damage by 15%. ...": the first percent and the third)
local SACRIFICE = { [18789] = { school = "shadow", pct = 1 }, [18791] = { school = "fire", pct = 3 } }
-- The fillers of each spec, the base way first (M.Variants), and their abilities
local FILLERS = { AFFLI = { "WRACK", "SHADOW_BOLT", "DRAIN_LIFE" }, DEMO = { "SHADOW_BOLT", "SEARING_PAIN" },
    DESTRO = { "INCINERATE", "SHADOW_BOLT", "SEARING_PAIN" } }
local FILLER = { WRACK = "wrack", SHADOW_BOLT = "shadowBolt", DRAIN_LIFE = "drainLife", INCINERATE = "incinerate",
    SEARING_PAIN = "searingPain" }

-- The fillers of the spec that the character has (ab: its abilities).
local function Fillers(spec, ab)
    local list = {}
    for _, key in ipairs(FILLERS[spec]) do
        if ab[FILLER[key]] then list[#list + 1] = key end
    end
    return list
end

-- The middle of Demonic Brand's damage before its factors, at a level and spell power (SpellDescriptionVariables 1016:
-- "$minDam=${((($pl-26)*1.5)+14+(0.078*$<which>))*$<mult>}", $maxDam with 17, $<which> the higher of Fire and Shadow
-- spell power, $<mult> Unholy Power's and Master Demonologist's factors).
local function BrandBase(level, sp)
    return (level - 26) * 1.5 + (14 + 17) / 2 + 0.078 * math.max(sp.fire, sp.shadow)
end


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
    local function Dot(key, fire)
        if not s[key] then return nil end
        local p = P(key, 1, 1)   -- "causing 132 Shadow damage over 18 sec"
        return A(key, { total = p.plain[1], ticks = p.time[1] / TICK[key], tick = TICK[key], fire = fire or M.Dot })
    end
    ab.corruption = Dot("CORRUPTION")
    ab.agony = Dot("BANE_OF_AGONY")
    if s.SIPHON_LIFE then
        -- "Transfers 11 health from the target to the caster every 3 sec. Lasts 30 sec."
        local p = P("SIPHON_LIFE", 1, 2)
        local ticks = p.time[2] / p.time[1]
        ab.siphonLife = A("SIPHON_LIFE", { total = p.plain[1] * ticks, ticks = ticks, tick = p.time[1], fire = M.Dot })
    end
    if s.BANE_OF_DOOM then
        -- "causing 1,742 Shadow damage after 1 min"
        local p = P("BANE_OF_DOOM", 1, 1)
        ab.doom = A("BANE_OF_DOOM", { total = p.plain[1], ticks = 1, tick = p.time[1], fire = M.Dot })
    end
    if s.IMMOLATE then
        -- "Burns the enemy for 21 Fire damage and then an additional 30 Fire damage over 15 sec."
        local p = P("IMMOLATE", 2, 1)
        ab.immolate = A("IMMOLATE", { damage = p.plain[1], total = p.plain[2], ticks = p.time[1] / TICK.IMMOLATE,
            tick = TICK.IMMOLATE, fire = M.Immolate })
    end
    if s.SHADOW_BOLT then ab.shadowBolt = A("SHADOW_BOLT", { damage = Average(P("SHADOW_BOLT", 2), 1), fire = M.Bolt }) end
    -- "causing 22 to 27 Fire damage"
    if s.SEARING_PAIN then ab.searingPain = A("SEARING_PAIN", { damage = Average(P("SEARING_PAIN", 2), 1),
        fire = M.Bolt }) end
    if s.INCINERATE then
        -- "Deals 90 to 104 Fire damage to your target and an additional 25% damage if the target is afflicted by Immolate."
        local p = P("INCINERATE", 2)
        ab.incinerate = A("INCINERATE", { damage = Average(p, 1), immolated = p.pct[1] / 100, fire = M.Bolt })
    end
    if s.CONFLAGRATE then ab.conflagrate = A("CONFLAGRATE", { damage = Average(P("CONFLAGRATE", 2), 1), fire = M.Bolt }) end
    if s.SHADOWBURN and c.talents.SHADOW_AND_FLAME then
        ab.shadowburn = A("SHADOWBURN", { damage = Average(P("SHADOWBURN", 2), 1), fire = M.Bolt })
    end
    if s.SOUL_FIRE and c.talents.DECIMATION then
        -- quick: the share of its cast time left in Decimation ("for the next 10 sec your Soul Fire spell has its cast
        -- time reduced by 20%", rank 2: 40%; the text's fourth percent)
        ab.soulFire = A("SOUL_FIRE", { damage = Average(P("SOUL_FIRE", 2), 1), fire = M.Bolt,
            quick = 1 - Talent(c, "DECIMATION", "pct", 4) / 100 })
    end
    if s.WRACK and c.spec == "AFFLI" then
        -- "inflicting 36 Shadow damage every 1 sec and increasing the damage they take from your other Shadow damage
        -- over time effects by 10% for 6 sec": a channel
        local p = P("WRACK", 1, 2)
        ab.wrack = A("WRACK", { damage = p.plain[1], dots = p.pct[1] / 100, duration = p.time[2],
            channel = { ticks = p.time[2] / p.time[1], tick = p.time[1] }, tick = M.ChannelTick })
    end
    if s.DRAIN_LIFE then
        -- "Transfers 22 health every 1 second from the target to the caster. Lasts 5 sec.": a channel
        local p = P("DRAIN_LIFE", 1, 2)
        ab.drainLife = A("DRAIN_LIFE", { damage = p.plain[1],
            channel = { ticks = p.time[2] / p.time[1], tick = p.time[1] }, tick = M.ChannelTick })
    end
    if s.LIFE_TAP then
        -- "Converts 119 Health into 119 Mana for you. Spirit increases the amount converted." (by how much the game
        -- does not say: left out)
        ab.lifeTap = A("LIFE_TAP", { mana = P("LIFE_TAP", 2).plain[2], fire = M.LifeTap })
    end
    -- the fillers: the fights play each (M.Variants)
    assert(Fillers(c.spec, ab)[1], "no damage spell")
    -- the bane: Doom when it does more per second than Agony
    if ab.doom and ab.agony then
        local doom = (ab.doom.total + ab.doom.dotCoef * c.sp.shadow) / ab.doom.tick
        local agony = (ab.agony.total + ab.agony.dotCoef * ab.agony.ticks * c.sp.shadow) / (ab.agony.ticks * ab.agony.tick)
            * (1 + Talent(c, "IMPROVED_BANE_OF_AGONY", "pct") / 100)
        if agony >= doom then ab.doom = nil end
    end
    -- Demonic Sacrifice: the effect of the demon sacrificed
    c.sacrifice = {}
    if c.talents.DEMONIC_SACRIFICE then
        for id, effect in pairs(SACRIFICE) do
            if Sim.PlayerAura(id) then
                c.sacrifice[effect.school] = Talent(c, "DEMONIC_SACRIFICE", "pct", effect.pct) / 100
            end
        end
    end
    -- Demonic Brand while a demon is out: "Your Searing Pain ... brands the target for 10 sec. Your pet's next 2
    -- attacks against the target generate high threat and deal 5 to 8 Fire or Shadow damage based on the pet."
    -- (rank 3: 6 attacks; M.OnPetAttack); base: its damage before its factors with the spell power the text has
    c.brand = nil
    local brand = c.talents.DEMONIC_BRAND
    if brand and c.pet and ab.searingPain then
        local p = brand.p
        assert(p.time[1] and p.plain[3], "Demonic Brand: unexpected description")
        c.brand = { time = p.time[1], attacks = p.plain[1], damage = Average(p, 2), base = BrandBase(c.level, c.sp) }
        assert(c.brand.base > 0, "Demonic Brand: no damage at this level")
    end
    c.ab = ab
end

-- The schools of the spells the fights cast (the simulator window shows them): Shadow and Fire (every spec keeps
-- Immolate up).
function M.Schools() return { "shadow", "fire" } end

-- The ways the fights play the character: each filler of its spec it has ("WRACK", "SHADOW_BOLT", "DRAIN_LIFE" ...;
-- Sim.Jobs.Fights fights each way and keeps the one that does more). They replace an estimate of the damage per second
-- of casting, which left out what comes with a filler (its crits, Nightfall, Decimation, the mana).
function M.Variants(c) return Fillers(c.spec, c.ab) end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- Master Demonologist's % on a school's damage, the warlock's and the demon's, with the demon that is out: "Imp -
-- Increases Fire damage done by 2%. Voidwalker - Reduces Physical damage taken by 2%. Succubus/Incubus - Increases
-- Shadow damage done by 2%. ..." (the imp's is the text's first percent, the succubus' the third); 0 for the others.
local function MasterDemonologist(c, school)
    local spells = c.pet.spells
    if spells.FIREBOLT and school == "fire" then return Talent(c, "MASTER_DEMONOLOGIST", "pct", 1) end
    if spells.LASH_OF_PAIN and school == "shadow" then return Talent(c, "MASTER_DEMONOLOGIST", "pct", 3) end
    return 0
end

-- What the character has on a school's damage all the time: Shadow Mastery, Demonic Sacrifice, Master Demonologist
-- and Soul Link with the demon out.
function M.SchoolMult(c, school)
    local m = 1 + (c.sacrifice and c.sacrifice[school] or 0)
    if school == "shadow" then m = m * (1 + Talent(c, "SHADOW_MASTERY", "pct") / 100) end
    if c.pet then
        if c.talents.SOUL_LINK then m = m * (1 + Talent(c, "SOUL_LINK", "pct", 2) / 100) end
        m = m * (1 + MasterDemonologist(c, school) / 100)
    end
    return m
end

-- What the warlock's own effects add to a spell's damage: its school's (M.SchoolMult), Agonizing Flames on the
-- Destruction spells, Shadow and Flame's buff (the target's debuffs: Taken).
local function Mult(F, ab, key)
    local c = F.char
    key = key or ab.key
    local m = M.SchoolMult(c, ab.school)
    if DESTRUCTION[key] then m = m * (1 + Talent(c, "AGONIZING_FLAMES", "pct", 2) / 100) end
    local sf = F:Buff(ab.school == "shadow" and "SHADOW_AND_FLAME_SHADOW" or "SHADOW_AND_FLAME_FIRE")
    if sf then m = m * (1 + sf.value) end
    return m
end

-- What the target's debuffs add to the damage of a Shadow spell (key) while they are on it, so a damage over time
-- (periodic) has them at each tick (Fight:Dot's tickMult), not as they were when it was put on: Improved Shadow Bolt
-- ("Your Shadow Bolt critical strikes increase Shadow damage taken by the target from your attacks by 20% for 12 sec")
-- and, on Corruption and Bane of Agony (WRACKED), Wrack ("increasing the damage they take from your other Shadow damage
-- over time effects by 10% for 6 sec").
local function Taken(F, key, periodic)
    if SCHOOL[key] ~= "shadow" then return 1 end
    local m = 1
    local isb = F:Debuff("IMPROVED_SHADOW_BOLT")
    if isb then m = m * (1 + isb.value) end
    local wrack = F:Debuff("WRACK")
    if periodic and wrack and WRACKED[key] then m = m * (1 + wrack.value) end
    return m
end

-- The same at a tick of a damage over time (Fight:Dot's tickMult).
local function TickTaken(F, d) return Taken(F, d.key, true) end

-- The hit, crit and crit damage of a spell (Malevolence, Fire and Brimstone, Agonizing Flames; Ruin, Pandemic). Their
-- class masks (SpellEffect 1310949, 17959, 427712) reach the damage over time of the spell too: Malevolence's the
-- Shadow ones, Ruin's Immolate (one spell: SpellClassOptions 348 ...: 4).
local function Opts(F, ab)
    local c = F.char
    local crit, bonus = 0, 0
    if ab.school == "shadow" then crit = Talent(c, "MALEVOLENCE", "pct") end
    if ab.key == "CONFLAGRATE" then crit = crit + Talent(c, "FIRE_AND_BRIMSTONE", "pct") end
    if ab.key == "SEARING_PAIN" then crit = crit + Talent(c, "AGONIZING_FLAMES", "pct", 1) end
    if DESTRUCTION[ab.key] then bonus = Talent(c, "RUIN", "pct") end
    if PANDEMIC[ab.key] then bonus = Talent(c, "PANDEMIC", "pct") end
    return { crit = crit, critMult = 1 + 0.5 * (1 + bonus / 100) }
end

-- The crit chance (%) and size of a tick of a damage over time or channel (nil: its ticks do not crit,
-- PERIODIC_CRIT): the spell crit of its school with the talents of the spell (Opts). A tick's crit triggers no
-- Improved Shadow Bolt (Shadow Bolt's only; SpellAuraOptions 17793 ProcTypeMask 87376: no periodic bit 0x40000).
local function TickCrit(F, ab)
    local crits = PERIODIC_CRIT[ab.key]
    assert(crits ~= nil, ab.key .. ": no rule for its ticks' crits")
    if not crits then return nil, nil end
    local opts = Opts(F, ab)
    return F.char.spellCrit[ab.school] + opts.crit, opts.critMult
end

-- Malediction ("Increases all periodic damage done by your Warlock spells by 1%"): on all of its damage over time.
local function DotMult(F) return 1 + Talent(F.char, "MALEDICTION", "pct") / 100 end

-- Nightfall: a tick of Corruption, Wrack or Drain Life may make the next Shadow Bolt instant.
local function Nightfall(F, key)
    local c = F.char
    if NIGHTFALL[key] and c.talents.NIGHTFALL and F:Roll() * 100 < Talent(c, "NIGHTFALL", "pct") then
        F:AddBuff("SHADOW_TRANCE", F.len)
    end
end

local function OnTick(F, d) Nightfall(F, d.key) end

-- A damage over time: the description's damage over its ticks (Improved Corruption, Improved Bane of Agony), its ticks'
-- crits (TickCrit), the target's debuffs at each tick (Taken).
function M.Dot(F, ab)
    local c = F.char
    if F:SpellResult(ab.school) == Sim.MISS then
        F:Record(ab.key, 0, Sim.MISS)
        return
    end
    local mult = Mult(F, ab) * DotMult(F)
    if ab.key == "CORRUPTION" then mult = mult * (1 + Talent(c, "IMPROVED_CORRUPTION", "pct") / 100) end
    if ab.key == "BANE_OF_AGONY" then mult = mult * (1 + Talent(c, "IMPROVED_BANE_OF_AGONY", "pct") / 100) end
    local perTick = (ab.total / ab.ticks + ab.dotCoef * c.sp[ab.school]) * mult * F:Resist()
    local crit, critMult = TickCrit(F, ab)
    F:Dot(ab.key, perTick, ab.ticks, ab.tick, { crit = crit, critMult = critMult, onTick = OnTick,
        tickMult = TickTaken })
end

-- Immolate: a hit (Aftermath) and its damage over time, whose ticks crit (TickCrit) as the hit: Ruin's bonus too.
function M.Immolate(F, ab)
    local c = F.char
    local mult = Mult(F, ab)
    local amount = (ab.damage + ab.coef * c.sp.fire) * mult * (1 + Talent(c, "AFTERMATH", "pct", 1) / 100)
    local result = F:SpellHit("IMMOLATE", "fire", amount, Opts(F, ab))
    if result == Sim.MISS then return end
    local perTick = (ab.total / ab.ticks + ab.dotCoef * c.sp.fire) * mult * DotMult(F) * F:Resist()
    local crit, critMult = TickCrit(F, ab)
    F:Dot("IMMOLATE_DOT", perTick, ab.ticks, ab.tick, { crit = crit, critMult = critMult })
end

-- The target is below 35 % health (Decimation): the last part of the fight (DECIMATION_PHASE).
local function Below35(F) return F.t >= F.len * DECIMATION_PHASE end

-- A direct damage spell.
function M.Bolt(F, ab)
    local c = F.char
    local mult = Mult(F, ab) * Taken(F, ab.key)
    if ab.key == "INCINERATE" and F:Debuff("IMMOLATE_DOT") then mult = mult * (1 + ab.immolated) end
    -- Decimation: "When you cast Shadow Bolt or Searing Pain on an enemy below 35% health, they deal 3% increased
    -- damage" (rank 2: 6%; the text's third percent)
    local filler = ab.key == "SHADOW_BOLT" or ab.key == "SEARING_PAIN"
    if filler and Below35(F) then mult = mult * (1 + Talent(c, "DECIMATION", "pct", 3) / 100) end
    local result = F:SpellHit(ab.key, ab.school, (ab.damage + ab.coef * c.sp[ab.school]) * mult, Opts(F, ab))
    if result == Sim.MISS then return end
    -- Shadow and Flame: "Hitting an enemy with Conflagrate increases all Shadow damage you deal by 2% for 20 sec, and
    -- hitting an enemy with Shadowburn increases all Fire damage you deal by 2% for 20 sec. In addition, Conflagrate
    -- has a 20% chance not to consume Immolate ..." (Conflagrate's numbers come first, Shadowburn's second)
    local sf = c.talents.SHADOW_AND_FLAME
    if ab.key == "CONFLAGRATE" then
        -- consumes Immolate, unless Shadow and Flame keeps it
        if not (sf and F:Roll() * 100 < Talent(c, "SHADOW_AND_FLAME", "pct", 3)) then F.debuffs.IMMOLATE_DOT = nil end
        if sf then
            F:AddBuff("SHADOW_AND_FLAME_SHADOW", Talent(c, "SHADOW_AND_FLAME", "time", 1),
                Talent(c, "SHADOW_AND_FLAME", "pct", 1) / 100)
        end
    elseif ab.key == "SHADOWBURN" and sf then
        F:AddBuff("SHADOW_AND_FLAME_FIRE", Talent(c, "SHADOW_AND_FLAME", "time", 2),
            Talent(c, "SHADOW_AND_FLAME", "pct", 2) / 100)
    elseif filler then
        if ab.key == "SHADOW_BOLT" and result == Sim.CRIT and c.talents.IMPROVED_SHADOW_BOLT then
            F:AddDebuff("IMPROVED_SHADOW_BOLT", Talent(c, "IMPROVED_SHADOW_BOLT", "time"),
                Talent(c, "IMPROVED_SHADOW_BOLT", "pct") / 100)
        end
        -- Decimation: "... and for the next 10 sec your Soul Fire spell has its cast time reduced by 20%"
        if c.talents.DECIMATION and Below35(F) then F:AddBuff("DECIMATION", DECIMATION_TIME) end
        -- Demonic Brand: the next attacks of the demon (M.OnPetAttack)
        if ab.key == "SEARING_PAIN" and c.brand then F:AddDebuff("DEMONIC_BRAND", c.brand.time, c.brand.attacks) end
    end
end

-- The start of a channel of Wrack or Drain Life: it hits or misses, every tick with it. Wrack's debuff ("... and
-- increasing the damage they take from your other Shadow damage over time effects by 10% for 6 sec") is on the target
-- from then while it is channeled (its 6 sec).
function M.ChannelStart(F, ab)
    F.channelMissed = F:SpellResult("shadow") == Sim.MISS
    if F.channelMissed then
        F:Record(ab.key, 0, Sim.MISS)
    elseif ab.key == "WRACK" then
        F:AddDebuff("WRACK", ab.duration, ab.dots)
    end
end

-- One second of Wrack or Drain Life (a channel that hit: M.ChannelStart): more for every other Affliction effect on the
-- target (Soul Siphon), Improved Drains, the target's debuffs (Taken: Improved Shadow Bolt; not Wrack's); it crits
-- (TickCrit).
function M.ChannelTick(F, ab)
    local c = F.char
    if F.channelMissed then return end
    local others = 0
    for _, key in ipairs(AFFLICTION) do if F:Debuff(key) then others = others + 1 end end
    local siphon = math.min(Talent(c, "SOUL_SIPHON", "pct", 2), others * Talent(c, "SOUL_SIPHON", "pct", 1))
    local mult = Mult(F, ab) * DotMult(F) * Taken(F, ab.key, true) * (1 + Talent(c, "IMPROVED_DRAINS", "pct") / 100)
        * (1 + siphon / 100)
    local damage, result = (ab.damage + ab.dotCoef * c.sp.shadow) * mult * F:Resist(), Sim.HIT
    local crit, critMult = TickCrit(F, ab)
    if crit and F:TickRoll() * 100 < crit then
        damage, result = damage * critMult, Sim.CRIT
    end
    F:Record(ab.key, damage, result, true)
    Nightfall(F, ab.key)
end

-- Life Tap: mana for health (Improved Life Tap).
function M.LifeTap(F, ab)
    F:GainMana(ab.mana * (1 + Talent(F.char, "IMPROVED_LIFE_TAP", "pct") / 100))
end

---------------------------------------------------------------------------
-- The demon: Improved Imp and Improved Sayaad on its spells, Master Demonologist, Soul Link, Malevolence on Lash of
-- Pain; Demonic Brand. Unholy Power is in the numbers of its swings, in the texts of its spells and of Demonic Brand.
---------------------------------------------------------------------------
-- key: the demon's ability, "DEMONIC_BRAND" for Demonic Brand's damage, nil for its swings. The texts of Firebolt and
-- Lash of Pain give their damage with Unholy Power whenever the warlock knows it (Firebolt: "Deals
-- $?s18769[${$m1*($18769m1/100+1)} to ${$M1*($18769m1/100+1)}][$s1] Fire damage"), Demonic Brand's text too (its
-- $<mult>: BrandBase): not again here.
function M.PetMult(F, key)
    local c = F.char
    local m = 1
    if c.talents.SOUL_LINK then m = m * (1 + Talent(c, "SOUL_LINK", "pct", 2) / 100) end
    if key == "FIREBOLT" then
        m = m * (1 + Talent(c, "IMPROVED_IMP", "pct", 1) / 100) * (1 + MasterDemonologist(c, "fire") / 100)
    elseif key == "LASH_OF_PAIN" then
        m = m * (1 + Talent(c, "IMPROVED_SAYAAD", "pct", 1) / 100) * (1 + MasterDemonologist(c, "shadow") / 100)
    end
    return m
end

-- The crit the warlock's talents add to one of the demon's spells: Malevolence to Lash of Pain (its effect's class
-- mask, SpellEffect 1310949: 550027/262147/0/4325376, has the bit of Lash of Pain, SpellClassOptions 7814 ...: 8192;
-- the warlock's modifiers reach the demon's spells as Improved Sayaad's damage does).
function M.PetSpellCrit(F, key)
    return key == "LASH_OF_PAIN" and Talent(F.char, "MALEVOLENCE", "pct") or 0
end

-- Demonic Brand (Sim/Pet.lua asks after every attack of the demon, a swing or an ability): "Your Searing Pain ...
-- brands the target for 10 sec. Your pet's next 2 attacks against the target generate high threat and deal 5 to 8 Fire
-- or Shadow damage based on the pet." Each attack while the brand is on is one of the next ones (the text counts
-- attacks: one that misses too); one that lands deals the middle of the damage, with the spell power of this
-- character (the text has the one it was read with: BrandBase), Soul Link (M.PetMult; the text has Unholy Power and
-- Master Demonologist) and the target's resistance from its level, as the demon's spells. Not proven, left out: which
-- school each demon deals (so no other school's modifier), whether the damage misses or crits on its own.
function M.OnPetAttack(F, result)
    local brand = F:Debuff("DEMONIC_BRAND")
    if not brand then return end
    brand.value = brand.value - 1
    if brand.value <= 0 then F.debuffs.DEMONIC_BRAND = nil end
    if result == Sim.MISS or result == Sim.DODGE then return end
    local c = F.char
    local damage = c.brand.damage * BrandBase(c.level, c.sp) / c.brand.base
    F:Record("DEMONIC_BRAND", damage * M.PetMult(F, "DEMONIC_BRAND") * F:Resist(F.pet.who), Sim.HIT)
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
-- The filler of the way the fight plays (M.Variants); the demon that is out.
function M.Start(F)
    F.filler = F.char.ab[FILLER[Sim.VariantKeys(F.opts.variant)[1]]]
    assert(F.filler, "no filler to play")
    if F.char.pet then Sim.Pet.Start(F) end
end

-- Life Tap when the spell the rotation wants now is ready, the mana does not pay for it and the tap adds mana; with
-- Decimation every other spell leaves the mana of a Soul Fire (it does far more for its mana). The warlock taps only
-- then: it keeps no other mana back, and more mana never makes it tap where it would cast. True when it tapped.
local function Tap(F, ab)
    local c = F.char
    local soulFire = c.ab.soulFire
    local need = ab.cost + (soulFire and ab ~= soulFire and soulFire.cost or 0)
    if c.ab.lifeTap and F:Ready(ab.key) and F.mana < need and F.mana < c.manaMax then
        F:Use(c.ab.lifeTap)
        return true
    end
end

local function Cast(F, ab, cast)
    if Tap(F, ab) then return true end
    if F:Can(ab) then
        F:Use(ab, nil, cast)
        if ab.channel then M.ChannelStart(F, ab) end
        return true
    end
end

-- A damage over time is worth putting on while it can tick at least half of its time.
local function Keep(F, ab, key)
    return ab and not F:Debuff(key or ab.key) and F.len - F.t > ab.ticks * ab.tick / 2
end

function M.Act(F)
    local ab = F.char.ab
    if F:Buff("SHADOW_TRANCE") and ab.shadowBolt then
        if Tap(F, ab.shadowBolt) then return end
        if F:Can(ab.shadowBolt) then
            F:RemoveBuff("SHADOW_TRANCE")
            F:Use(ab.shadowBolt, nil, 0)
            return
        end
    end
    -- one bane: Doom while it can still land, else Agony
    local doom = ab.doom and F.len - F.t >= ab.doom.tick
    if doom and not F:Debuff("BANE_OF_AGONY") and Keep(F, ab.doom) and Cast(F, ab.doom) then return end
    if not doom and not F:Debuff("BANE_OF_DOOM") and Keep(F, ab.agony) and Cast(F, ab.agony) then return end
    if Keep(F, ab.corruption) and Cast(F, ab.corruption) then return end
    if Keep(F, ab.siphonLife) and Cast(F, ab.siphonLife) then return end
    if Keep(F, ab.immolate, "IMMOLATE_DOT") and Cast(F, ab.immolate) then return end
    if ab.conflagrate and F:Debuff("IMMOLATE_DOT") and Cast(F, ab.conflagrate) then return end
    if ab.shadowburn and Cast(F, ab.shadowburn) then return end
    -- Decimation: a quick Soul Fire
    if ab.soulFire and F:Buff("DECIMATION") and Cast(F, ab.soulFire, ab.soulFire.cast * ab.soulFire.quick) then return end
    if Cast(F, F.filler) then return end
    local function At(a) return a and F:ReadyAt(a.key) end
    return F:Next(At(ab.conflagrate), At(ab.shadowburn), At(ab.soulFire))
end
