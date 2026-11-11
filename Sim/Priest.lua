-- Lootified - simulator model of the Shadow Priest in WoW: Forever, in Shadowform (taken when the priest has it); the
-- Discipline and the Holy priest play the same rotation with what they know (their damage with their gear), so do
-- Discipline (Damage) and Holy (Damage), their trees played for damage.
-- Rotation: Power Infusion on cooldown, Shadow Word: Pain and Devouring Plague kept up, Mind Blast (Inner Focus before
-- it) and Shadow Word: Death on cooldown, Mind Flay in between (Smite before it is learned); the fights play it with and
-- without Holy Fire kept on the target, with and without Penance and with and without Starshards on cooldown and keep
-- the way that does more (M.Variants; Shadowform forbids only healing spells). Talents: Shadow Focus, Improved Shadow
-- Word: Pain, Improved Mind Flay, Shadow Weaving, Early Demise, Darkness, Shadowform, Twin Disciplines, Holy Precision,
-- Holy Specialization, Power in Light, Searing Light. Numbers from the game's descriptions, costs, cast times and cooldowns from the game;
-- spell power shares from the game's own tables (Sim.SpellPower); rules below (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent, Average = Sim.Talent, Sim.Average

local M = { class = "PRIEST", specs = { SHADOW = true, DISC = true, HOLY = true, DISC_DMG = true, HOLY_DMG = true },
    hands = {} }
Sim.models.PRIEST = M

M.spells = {
    SHADOW_WORD_PAIN = 589, MIND_BLAST = 8092, MIND_FLAY = 15407, SHADOW_WORD_DEATH = 1309595,
    DEVOURING_PLAGUE = 1219275, INNER_FOCUS = 14751, SMITE = 585, HOLY_FIRE = 14914, STARSHARDS = 10797,
    PENANCE = 402174, POWER_INFUSION = 10060,
}
M.talents = {
    SHADOW_FOCUS = 15260, IMPROVED_SHADOW_WORD_PAIN = 15275, IMPROVED_MIND_FLAY = 1225139, SHADOW_WEAVING = 15257,
    EARLY_DEMISE = 1310076, DARKNESS = 15259, SHADOWFORM = 15473, TWIN_DISCIPLINES = 1225132,
    HOLY_PRECISION = 1309957, POWER_IN_LIGHT = 1309969, SEARING_LIGHT = 14909,
    MENTAL_STRENGTH = 18551, HOLY_SPECIALIZATION = 14889,
}

local SCHOOL = { SHADOW_WORD_PAIN = "shadow", MIND_BLAST = "shadow", MIND_FLAY = "shadow", SHADOW_WORD_DEATH = "shadow",
    DEVOURING_PLAGUE = "shadow", SMITE = "holy", HOLY_FIRE = "holy", STARSHARDS = "arcane", PENANCE = "holy" }
-- the instant spells Twin Disciplines reaches: its class masks (SpellEffect 1225132) name Shadow Word: Pain and
-- Devouring Plague (effect 2, periodic damage), not Shadow Word: Death (SpellClassOptions 1309595, 1309633, 1309635,
-- 1309636: 0/2/0/0)
local INSTANT = { SHADOW_WORD_PAIN = true, DEVOURING_PLAGUE = true }
local DOT_TICK = 3
local HOLY_FIRE_TICK = 2               -- its burn ticks every 2 sec (CMaNGOS spell_template 14914: period 2000 ms)
local STARSHARDS_TICK = 1              -- a tick a second (CMaNGOS spell_template 10797: period 1000 ms)
local EXECUTE_PHASE = 0.8              -- the target is at 20 % health or less for the last fifth of the fight

-- Mental Strength raises Intellect by a percent, an item's too (Character.WithStats): "Increases your total Intellect
-- by 15%." (SpellEffect 18551: aura 137 MOD_TOTAL_STAT_PERCENTAGE, EffectMiscValue[1] the stat mask: 8 Intellect).
function M.StatMods(c) return { str = 1, agi = 1, int = 1 + Talent(c, "MENTAL_STRENGTH", "pct") / 100 } end

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
    if s.SHADOW_WORD_PAIN then
        -- "causes 582 Shadow damage over 18 sec"; Improved Shadow Word: Pain makes it last longer, every tick alike
        local p = P("SHADOW_WORD_PAIN", 1, 1)
        local ticks = p.time[1] / DOT_TICK
        ab.pain = A("SHADOW_WORD_PAIN", { perTick = p.plain[1] / ticks,
            ticks = ticks + Talent(c, "IMPROVED_SHADOW_WORD_PAIN", "time") / DOT_TICK, fire = M.Dot })
    end
    if s.DEVOURING_PLAGUE then
        local p = P("DEVOURING_PLAGUE", 1, 1)   -- "causes 152 Shadow damage over 24 sec"
        local ticks = p.time[1] / DOT_TICK
        ab.plague = A("DEVOURING_PLAGUE", { perTick = p.plain[1] / ticks, ticks = ticks, fire = M.Dot })
    end
    if s.MIND_BLAST then ab.mindBlast = A("MIND_BLAST", { damage = Average(P("MIND_BLAST", 2), 1), fire = M.Bolt }) end
    if s.SHADOW_WORD_DEATH then
        ab.death = A("SHADOW_WORD_DEATH", { damage = Average(P("SHADOW_WORD_DEATH", 2), 1), fire = M.Bolt })
    end
    if s.SMITE then ab.smite = A("SMITE", { damage = Average(P("SMITE", 2), 1), fire = M.Bolt }) end
    if s.HOLY_FIRE then
        -- "cause 71 to 89 Holy damage and an additional 30 Holy damage over 10 sec"
        local p = P("HOLY_FIRE", 3, 1)
        local ticks = p.time[1] / HOLY_FIRE_TICK
        ab.holyFire = A("HOLY_FIRE", { damage = Average(p, 1), perTick = p.plain[3] / ticks, ticks = ticks,
            fire = M.HolyFire })
    end
    if s.STARSHARDS then
        -- "causing 528 Arcane damage over 6 sec": a channel
        local p = P("STARSHARDS", 1, 1)
        local ticks = p.time[1] / STARSHARDS_TICK
        ab.starshards = A("STARSHARDS", { perTick = p.plain[1] / ticks,
            channel = { ticks = ticks, tick = STARSHARDS_TICK }, tick = M.StarshardsTick })
    end
    if s.PENANCE then
        -- "Launches a volley of holy light at the target, causing 81 Holy damage to an enemy, or 184 healing to an
        -- ally, instantly and every 1 sec for 2 sec.": three bolts, the first at once (M.Act), the others the ticks of
        -- a channel a second apart; each a Holy spell's hit of its own (the text names three hits, not one roll)
        local p = s.PENANCE.p
        assert(#p.plain == 2 and #p.time == 2, "Penance: unexpected description")
        ab.penance = A("PENANCE", { damage = p.plain[1], channel = { ticks = p.time[2] / p.time[1], tick = p.time[1] },
            tick = M.Bolt })
    end
    if s.POWER_INFUSION then
        -- "Infuses the target with power, increasing their spell damage and healing done by 20% for 15 sec." (cast on
        -- the priest); no global cooldown (CMaNGOS spell_template 10060: StartRecoveryTime 0)
        local p = s.POWER_INFUSION.p
        assert(p.pct[1] and p.time[1], "Power Infusion: unexpected description")
        ab.powerInfusion = A("POWER_INFUSION", { gcd = 0, value = p.pct[1] / 100, duration = p.time[1],
            fire = M.PowerInfusion })
    end
    if s.MIND_FLAY then
        -- "causing 63 Shadow damage over 3 sec": a channel of one tick a second
        local p = P("MIND_FLAY", 1, 1)
        ab.mindFlay = A("MIND_FLAY", { perTick = p.plain[1] / p.time[1], channel = { ticks = p.time[1], tick = 1 },
            tick = M.FlayTick })
    end
    ab.innerFocus = A("INNER_FOCUS", { gcd = 0, crit = s.INNER_FOCUS and s.INNER_FOCUS.p.pct[2], fire = M.InnerFocus })
    -- Shadowform makes Shadow spells cheaper: the game's costs have it only while the priest is in the form (before
    -- ab.filler, which names one of the abilities a second time: that one would get the cut twice)
    if c.talents.SHADOWFORM and not Sim.PlayerAura(M.talents.SHADOWFORM) then
        local cut = 1 - Talent(c, "SHADOWFORM", "pct", 2) / 100
        for _, a in pairs(ab) do
            if a.school == "shadow" then a.cost = a.cost * cut end
        end
    end
    ab.filler = ab.mindFlay or ab.smite
    assert(ab.filler, "no damage spell")
    c.ab = ab
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- Shadow damage: Darkness, Shadowform; Holy damage: Searing Light (its other part, a free Holy Nova, hits groups),
-- Power in Light ("Your Smite and Penance spells deal 2% increased damage to targets afflicted with your Holy Fire.")
-- while Holy Fire burns the target; Twin Disciplines on the instant spells it reaches (INSTANT; the channels, Mind
-- Flay, Penance and Starshards, are not); Power Infusion on every spell while it lasts (a damage over time keeps what
-- it was put on with, as with the other modifiers here: not proven). Shadow Weaving's stacks are on the target: Taken.
local function Mult(F, ab)
    local c = F.char
    local m = 1
    if ab.school == "shadow" then
        m = (1 + Talent(c, "DARKNESS", "pct") / 100) * (1 + Talent(c, "SHADOWFORM", "pct", 1) / 100)
    elseif ab.school == "holy" then
        m = 1 + Talent(c, "SEARING_LIGHT", "pct", 1) / 100
        if (ab.key == "SMITE" or ab.key == "PENANCE") and F:Debuff("HOLY_FIRE_DOT") then
            m = m * (1 + Talent(c, "POWER_IN_LIGHT", "pct") / 100)
        end
    end
    if INSTANT[ab.key] then m = m * (1 + Talent(c, "TWIN_DISCIPLINES", "pct") / 100) end
    local infusion = F:Buff("POWER_INFUSION")
    if infusion then m = m * (1 + infusion.value) end
    return m
end

-- Shadow Weaving's debuff on the target: "Taking 2% increased Shadow damage from the caster" a stack (SpellEffect
-- 15258: aura 270, misc 32 Shadow; 5 stacks, 15 sec) on the Shadow damage while it is on, so a damage over time counts
-- the stacks it finds at each tick (Fight:Dot's tickMult; the owner's research: no snapshot), as the warlock's Improved
-- Shadow Bolt and Wrack.
local function Taken(F, school)
    local weaving = school == "shadow" and F:Debuff("SHADOW_WEAVING")
    return weaving and 1 + weaving.stacks * weaving.value or 1
end

-- The same at a tick of a damage over time (Fight:Dot's tickMult).
local function TickTaken(F, d) return Taken(F, SCHOOL[d.key]) end

-- The talents' hit with the spells of a school (Shadow Focus, Holy Precision).
function M.SpellHit(c, school)
    if school == "holy" then return Talent(c, "HOLY_PRECISION", "pct") end
    return school == "shadow" and Talent(c, "SHADOW_FOCUS", "pct") or 0
end

-- The schools of the spells the fights cast, the main one first (the simulator window shows them): the filler's, Shadow
-- for the other spells while Smite fills in (before Mind Flay), Holy for Holy Fire and Penance (Smite's school already)
-- and Arcane for Starshards (the ways with them).
function M.Schools(c)
    local ab = c.ab
    local list = { ab.filler.school }
    if ab.filler == ab.smite and (ab.pain or ab.plague or ab.mindBlast or ab.death) then list[#list + 1] = "shadow" end
    if (ab.holyFire or ab.penance) and ab.filler ~= ab.smite then list[#list + 1] = "holy" end
    if ab.starshards then list[#list + 1] = "arcane" end
    return list
end

-- A crit's damage: 1.5 x, with Shadowform's crit damage bonus on the Shadow spells of its class mask (SpellEffect 15473
-- effect 5: 41984016/0/0/0, which has Shadow Word: Pain, Mind Blast, Mind Flay and Devouring Plague: SpellClassOptions
-- 32768, 8192, 8388608, 33554432/0/0/16), not Shadow Word: Death (SpellClassOptions 1309595, 1309633, 1309635,
-- 1309636: 0/2/0/0)
local function CritMult(c, ab)
    local bonus = ab.school == "shadow" and ab.key ~= "SHADOW_WORD_DEATH" and Talent(c, "SHADOWFORM", "pct", 3) or 0
    return 1 + 0.5 * (1 + bonus / 100)
end

-- Holy Specialization: "Increases the critical effect chance of your Holy spells by 5%." on the spells of its class mask
-- (SpellEffect 14889: 156507840/98340/0/0): Smite, Holy Fire (its hit and its burn) and Penance's bolts
-- (SpellClassOptions 585 ...: 128, 14914 ...: 1048576, 402284 ...: 0/32768), not Starshards (2097152).
local HOLY_SPECIALIZATION = { SMITE = true, HOLY_FIRE = true, PENANCE = true }
local function HolySpecialization(c, ab)
    return HOLY_SPECIALIZATION[ab.key] and Talent(c, "HOLY_SPECIALIZATION", "pct") or 0
end

local function Opts(F, ab)
    local c = F.char
    local crit = HolySpecialization(c, ab)
    -- Early Demise: "... on targets at or below 20% health by 30%"
    if ab.key == "SHADOW_WORD_DEATH" and F.t >= F.len * EXECUTE_PHASE then crit = Talent(c, "EARLY_DEMISE", "pct", 2) end
    local focus = F:Buff("INNER_FOCUS")
    if focus then
        crit = crit + focus.value
        F:RemoveBuff("INNER_FOCUS")
    end
    return { hit = M.SpellHit(c, ab.school), crit = crit, critMult = CritMult(c, ab) }
end

-- Shadow Weaving: every Shadow damage spell may add a stack of its debuff on the target (Taken).
local function Weave(F)
    local c = F.char
    if c.talents.SHADOW_WEAVING and F:Roll() * 100 < Talent(c, "SHADOW_WEAVING", "pct", 1) then
        F:AddDebuff("SHADOW_WEAVING", Talent(c, "SHADOW_WEAVING", "time"), Talent(c, "SHADOW_WEAVING", "pct", 2) / 100,
            Talent(c, "SHADOW_WEAVING", "plain"))
    end
end

-- The ticks of Shadow Word: Pain, Devouring Plague, Holy Fire's burn, Mind Flay and Starshards crit: SpellMisc
-- Attributes[8] 0x200 "periodic can crit" on every rank, magic spells (SpellCategories DefenseType 1): the school's
-- spell crit with Holy Specialization on Holy Fire's burn (Inner Focus' is for a non-periodic spell, its text) and
-- CritMult. Penance's bolts are direct damage spells (402284 ...: SCHOOL_DAMAGE): M.Bolt.
local function TickCrit(c, ab)
    return { crit = c.spellCrit[ab.school] + HolySpecialization(c, ab), critMult = CritMult(c, ab) }
end

-- A tick of a channel that hit (Mind Flay, Starshards): its crit (TickCrit), recorded.
local function ChannelTick(F, ab, damage)
    local opts, result = TickCrit(F.char, ab), Sim.HIT
    if F:TickRoll() * 100 < opts.crit then damage, result = damage * opts.critMult, Sim.CRIT end
    F:Record(ab.key, damage, result, true)
end

function M.Bolt(F, ab)
    local c = F.char
    local opts = Opts(F, ab)
    local amount = (ab.damage + ab.coef * c.sp[ab.school]) * Mult(F, ab) * Taken(F, ab.school)
    local result = F:SpellHit(ab.key, ab.school, amount, opts)
    if result ~= Sim.MISS and ab.school == "shadow" then Weave(F) end
end

-- Shadow Word: Pain, Devouring Plague: the priest's modifiers as it is put on, Shadow Weaving's stacks at each tick,
-- the ticks' crit (TickCrit).
function M.Dot(F, ab)
    local c = F.char
    if F:SpellResult(ab.school, M.SpellHit(c, ab.school)) == Sim.MISS then
        F:Record(ab.key, 0, Sim.MISS)
        return
    end
    local opts = TickCrit(c, ab)
    opts.tickMult = TickTaken
    F:Dot(ab.key, (ab.perTick + ab.dotCoef * c.sp.shadow) * Mult(F, ab) * F:Resist(), ab.ticks, DOT_TICK, opts)
    Weave(F)
end

-- Holy Fire: a hit, then its burn (one hit roll for both).
function M.HolyFire(F, ab)
    local c = F.char
    local mult = Mult(F, ab)
    local result = F:SpellHit("HOLY_FIRE", "holy", (ab.damage + ab.coef * c.sp.holy) * mult, Opts(F, ab))
    if result == Sim.MISS then return end
    F:Dot("HOLY_FIRE_DOT", (ab.perTick + ab.dotCoef * c.sp.holy) * mult * F:Resist(), ab.ticks, HOLY_FIRE_TICK,
        TickCrit(c, ab))
end

-- One second of Mind Flay (the hit rolled with the first; Improved Mind Flay; Shadow Weaving's stacks at each tick).
function M.FlayTick(F, ab, n)
    local c = F.char
    if n == 1 then
        F.flayMissed = F:SpellResult("shadow", M.SpellHit(c, "shadow")) == Sim.MISS
        if F.flayMissed then
            F:Record("MIND_FLAY", 0, Sim.MISS)
            return
        end
        Weave(F)
    end
    if F.flayMissed then return end
    local damage = (ab.perTick + ab.dotCoef * c.sp.shadow) * Mult(F, ab) * Taken(F, "shadow")
        * (1 + Talent(c, "IMPROVED_MIND_FLAY", "pct", 1) / 100)
    ChannelTick(F, ab, damage * F:Resist())
end

-- One second of Starshards (the hit rolled with the first).
function M.StarshardsTick(F, ab, n)
    local c = F.char
    if n == 1 then
        F.starshardsMissed = F:SpellResult("arcane", M.SpellHit(c, "arcane")) == Sim.MISS
        if F.starshardsMissed then
            F:Record("STARSHARDS", 0, Sim.MISS)
            return
        end
    end
    if F.starshardsMissed then return end
    ChannelTick(F, ab, (ab.perTick + ab.dotCoef * c.sp.arcane) * Mult(F, ab) * F:Resist())
end

function M.InnerFocus(F, ab) F:AddBuff("INNER_FOCUS", F.len, ab.crit) end

function M.PowerInfusion(F, ab) F:AddBuff("POWER_INFUSION", ab.duration, ab.value) end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
-- The ways the fights play the character (Sim.Jobs.Fights fights each and keeps the one that does more): its filler
-- alone and with every mix of Holy Fire, Starshards and Penance it knows ("MIND_FLAY", "MIND_FLAY+HOLY_FIRE",
-- "MIND_FLAY+STARSHARDS", "MIND_FLAY+HOLY_FIRE+STARSHARDS", "MIND_FLAY+PENANCE" ...).
local OPTIONAL = { { "HOLY_FIRE", "holyFire" }, { "STARSHARDS", "starshards" }, { "PENANCE", "penance" } }
function M.Variants(c)
    local ab = c.ab
    local list = { ab.filler.key }
    for _, o in ipairs(OPTIONAL) do
        if ab[o[2]] then
            for i = 1, #list do list[#list + 1] = list[i] .. "+" .. o[1] end
        end
    end
    return list
end

function M.Start(F)
    F.holyFire = Sim.VariantHas(F.opts.variant, "HOLY_FIRE")
    F.starshards = Sim.VariantHas(F.opts.variant, "STARSHARDS")
    F.penance = Sim.VariantHas(F.opts.variant, "PENANCE")
end

local function Cast(F, ab, cost)
    if F:Can(ab, cost) then
        F:Use(ab, cost)
        return true
    end
end

function M.Act(F)
    local ab = F.char.ab
    local left = F.len - F.t
    -- Power Infusion when it is ready (no global cooldown: a spell follows at once)
    if F:Can(ab.powerInfusion) then F:Use(ab.powerInfusion) end
    if ab.pain and not F:Debuff("SHADOW_WORD_PAIN") and left > ab.pain.ticks * DOT_TICK / 2 and Cast(F, ab.pain) then return end
    if ab.plague and not F:Debuff("DEVOURING_PLAGUE") and left > ab.plague.ticks * DOT_TICK / 2 and Cast(F, ab.plague) then
        return
    end
    if F.holyFire and not F:Debuff("HOLY_FIRE_DOT") and left > ab.holyFire.ticks * HOLY_FIRE_TICK / 2
        and Cast(F, ab.holyFire) then return end
    if ab.mindBlast and F:Can(ab.mindBlast, 0) then
        -- Inner Focus makes it free and likelier to crit
        if F:Can(ab.innerFocus) then F:Use(ab.innerFocus) end
        if Cast(F, ab.mindBlast, F:Buff("INNER_FOCUS") and 0 or nil) then return end
    end
    if ab.death and Cast(F, ab.death) then return end
    if F.penance and F:Can(ab.penance) then
        -- its first bolt at once ("instantly"), the channel's ticks the others
        F:Use(ab.penance)
        M.Bolt(F, ab.penance)
        return
    end
    if F.starshards and Cast(F, ab.starshards) then return end
    if Cast(F, ab.filler) then return end
    local function At(a) return a and F:ReadyAt(a.key) end
    return F:Next(At(ab.mindBlast), At(ab.death), At(ab.plague), F.starshards and At(ab.starshards),
        F.penance and At(ab.penance), At(ab.powerInfusion))
end
