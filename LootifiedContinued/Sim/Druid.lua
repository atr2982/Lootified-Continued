-- Lootified - simulator model of the Balance, the Feral (Cat) and the Feral (Bear) Druid in WoW: Forever (the
-- Restoration druid plays Balance's rotation with what it knows: its damage with its gear).
-- Balance keeps Moonfire and Insect Swarm up and casts Starfire and Wrath (with Eclipse: Wrath, then the quicker
-- Starfires it makes; without: whichever does more per second of casting).
-- Cat (read in Cat Form: the simulator takes the cat's numbers from the character sheet) opens from Prowl with Ravage
-- or Pounce (the fights play each opener the cat has and keep the one that does more: M.Variants), builds combo points
-- with Shred (Claw before it is learned), keeps Rake up, finishes at 5 points with Rip while the fight lasts long
-- enough and Ferocious Bite otherwise; Berserk, Tiger's Fury and Shifting Power on cooldown.
-- Bear (read in Bear or Dire Bear Form, the bear's numbers from the character sheet; against the target dummy as every
-- spec): it shifts at the pull (Furor's rage, the shift's global cooldown), uses Berserk and Enrage on cooldown, Primal
-- Bite on cooldown (none while Berserk lasts) and Maul on the next swing with the rage left above Primal Bite's cost.
-- Talents: Genesis, Improved Moonfire, Nature's Splendor, Vengeance, Nature's Grace, Eclipse, Moonfury, Naturalist,
-- Savage Fury, Blood Frenzy, Predatory Instincts, Rend and Tear, Furor. Numbers from the game's descriptions, costs,
-- cast times and cooldowns from the game; spell power shares from the game's own tables (Sim.SpellPower); rules below
-- (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent, Average, PerPoint = Sim.Talent, Sim.Average, Sim.PerPoint

local M = { class = "DRUID", specs = { BALANCE = true, CAT = true, BEAR = true, RESTO = true }, hands = { "mh" } }
Sim.models.DRUID = M

local min = math.min

M.spells = {
    WRATH = 5176, STARFIRE = 2912, MOONFIRE = 8921, INSECT_SWARM = 5570, CLAW = 1082, SHRED = 5221, RAKE = 1822,
    RIP = 1079, FEROCIOUS_BITE = 22568, RAVAGE = 6785, BERSERK = 417141, SHIFTING_POWER = 1322605, POUNCE = 9005,
    MAUL = 6807, PRIMAL_BITE = 407995, ENRAGE = 5229, TIGERS_FURY = 5217,
}
M.talents = {
    GENESIS = 1223081, IMPROVED_MOONFIRE = 16821, NATURES_SPLENDOR = 1223083, VENGEANCE = 16909, NATURES_GRACE = 16880,
    ECLIPSE = 408248, MOONFURY = 16896, NATURALIST = 17069, SAVAGE_FURY = 16998, BLOOD_FRENZY = 16958,
    PREDATORY_INSTINCTS = 1223242, REND_AND_TEAR = 1223246, FUROR = 17056,
    HEART_OF_THE_WILD = 17003,
}
-- The tank spec, and the spells and talents only it plays (the other specs list them as "only when you tank").
M.tankSpec = "BEAR"
M.tankSpells = { MAUL = true, PRIMAL_BITE = true, ENRAGE = true, FUROR = true }

-- Attack power shares of Rake (CMaNGOS spell_bonus_data) and of Rip and Ferocious Bite (CMaNGOS spell scripts: 1 % per
-- point per tick of Rip up to 4 points, 3 % per point for the bite).
local SCHOOL = { WRATH = "nature", STARFIRE = "arcane", MOONFIRE = "arcane", INSECT_SWARM = "nature" }
local RAKE_AP, RAKE_AP_DOT = 0.01, 0.02
local MOONFIRE_TICK, SWARM_TICK, RAKE_TICK, RIP_TICK = 3, 2, 3, 2
local POUNCE_TICK = 3                  -- a tick every 3 seconds (CMaNGOS spell_template 9007: EffectAmplitude1 3000)
local POUNCE_AP_DOT = 0.03             -- attack power per tick (CMaNGOS spell_bonus_data 9007, Pounce Bleed)
local POUNCE_BLEED_CRIT = 2            -- a tick's crit: a melee crit's double damage, no talent (M.Pounce)
local CAT_FORM = 1
local CAT_FORM_LEVEL = 20              -- the trainer teaches Cat Form from level 20 (CMaNGOS)
local GCD_CAT = 1.0
local MAX_CP = 5
local SAVAGE_FURY = { CLAW = true, RAKE = true, SHRED = true }
local SHRED_TYPED_PCT = 2.25           -- the weapon percent Shred's typed-in flat damage was written for
-- Bear and Dire Bear Form (CMaNGOS spell_template 5487, 9634: the form of their shapeshift aura, EffectMiscValue1)
local BEAR_FORM, DIRE_BEAR_FORM = 5, 8
-- druids learn Bear Form at level 10 (CMaNGOS quest_template 6001, 6002 "Body and Heart": MinLevel 10)
local BEAR_FORM_LEVEL = 10
-- the global cooldown of the shift into Bear or Dire Bear Form (SpellCooldowns 5487, 9634: StartRecoveryTime 1500)
local SHIFT_GCD = 1.5
-- Enrage's rage over time comes in a tick every second (CMaNGOS spell_template 5229: EffectAmplitude1 1000)
local ENRAGE_TICK = 1

-- Heart of the Wild raises Intellect by a percent, in Cat Form Strength too, an item's as well (Character.WithStats):
-- "Increases your Intellect by 10%.  In addition, while in Bear Form or Dire Bear Form your Stamina is increased by 20%
-- and while in Cat Form your Strength is increased by 10%." (SpellEffect 17003: aura 137 MOD_TOTAL_STAT_PERCENTAGE,
-- EffectMiscValue[1] the stat mask: 8 Intellect; the cat's 24900: 1 Strength; the bear's Stamina changes no damage).
function M.StatMods(c)
    local cat = c.form == CAT_FORM and Talent(c, "HEART_OF_THE_WILD", "pct", 3) or 0
    return { str = 1 + cat / 100, agi = 1, int = 1 + Talent(c, "HEART_OF_THE_WILD", "pct") / 100 }
end

function M.Setup(c)
    local ab, s = {}, c.spells
    local cat, bear = c.spec == "CAT", c.spec == "BEAR"
    local function A(key, fields)
        if not s[key] then return nil end
        -- a damage spell: its school and its shares of spell power (coef on a hit, dotCoef on a tick)
        if SCHOOL[key] then fields.school, fields.coef, fields.dotCoef = SCHOOL[key], Sim.SpellPower(s[key]) end
        if cat then fields.gcd = fields.gcd or GCD_CAT end
        return Sim.Ability(s[key], fields)
    end
    local function P(key, plain, time, pct)
        local p = s[key].p
        assert(#p.plain >= plain and #p.time >= (time or 0) and #p.pct >= (pct or 0), s[key].name .. ": unexpected description")
        return p
    end
    if cat then
        assert(c.form == CAT_FORM, c.level < CAT_FORM_LEVEL and "no cat form at this level" or "not in cat form")
        -- "Claw the enemy for 110% normal damage plus 126", "causing 155% damage plus 180", "350% damage plus 273": the
        -- flat damage with the weapon percent in it (the game's texts: Claw's "plus $s1" is 110 % of its base points)
        for key, field in pairs({ CLAW = "claw", SHRED = "shred", RAVAGE = "ravage" }) do
            if s[key] then
                local p = P(key, 1, 0, 1)
                ab[field] = A(key, { pct = p.pct[1] / 100, extra = p.plain[1], fire = M.Builder })
            end
        end
        if ab.shred then
            -- Shred's text has its flat damage typed in from when it dealt 225 % (54, 72, 99, 144, 180: its base points
            -- 24, 32, 44, 64, 80 in the game's SpellEffect, x 2.25); it deals 155 % now: its base points times that
            local base = ab.shred.extra / SHRED_TYPED_PCT
            assert(base == math.floor(base), "Shred: unexpected description")
            ab.shred.extra = base * ab.shred.pct
        end
        if s.RAKE then
            local p = P("RAKE", 2, 1)   -- "Rake the target for 61 damage and an additional 102 damage over 9 sec."
            ab.rake = A("RAKE", { damage = p.plain[1], total = p.plain[2], ticks = p.time[1] / RAKE_TICK, fire = M.Rake })
        end
        if s.POUNCE then
            -- "stunning the target for 2 sec and causing 90 damage over 18 sec. ... Awards 1 combo point."
            local p = P("POUNCE", 2, 2)
            ab.pounce = A("POUNCE", { total = p.plain[1], ticks = p.time[2] / POUNCE_TICK, cp = p.plain[2],
                fire = M.Pounce })
        end
        if s.RIP then
            -- per point: "X damage over 12 sec"
            ab.rip = A("RIP", { totals = PerPoint(s.RIP, "plain", 1), times = PerPoint(s.RIP, "time"), fire = M.Rip })
        end
        if s.FEROCIOUS_BITE then
            -- "converts each extra point of energy into 2.7 additional damage" (the rank's rate: the first plain
            -- number, before the 15 of the per-point lines)
            local p = P("FEROCIOUS_BITE", 16)
            ab.bite = A("FEROCIOUS_BITE", { ranges = PerPoint(s.FEROCIOUS_BITE, "plain", 2), perEnergy = p.plain[1],
                fire = M.Bite })
        end
        if s.TIGERS_FURY then
            -- "Increases Physical damage done by 15% for 6 sec."; no cost (the game names none), its cooldown the
            -- game's (30 sec), no global cooldown (CMaNGOS spell_template 5217: StartRecoveryTime 0)
            local p = P("TIGERS_FURY", 0, 1, 1)
            ab.tigersFury = A("TIGERS_FURY", { gcd = 0, pct = p.pct[1] / 100, duration = p.time[1],
                fire = M.TigersFury })
        end
        if s.BERSERK then
            local p = P("BERSERK", 0, 1, 1)   -- "... increases the critical strike chance of your Combo Point-generating abilities by 100% ... Lasts 15 sec."
            ab.berserk = A("BERSERK", { gcd = 0, crit = p.pct[#p.pct], duration = p.time[1], fire = M.Berserk })
        end
        if s.SHIFTING_POWER then
            -- "Instantly convert 227 Mana into 40 Energy."; the cat's global cooldown (SpellCooldowns 1322605:
            -- StartRecoveryTime 1000)
            local p = P("SHIFTING_POWER", 2)
            ab.shifting = A("SHIFTING_POWER", { energy = p.plain[2], fire = M.ShiftingPower })
        end
        ab.builder = ab.shred or ab.claw
        assert(ab.builder, "no builder")
    elseif bear then
        assert(c.form == BEAR_FORM or c.form == DIRE_BEAR_FORM,
            c.level < BEAR_FORM_LEVEL and "no bear form at this level" or "not in bear form")
        if s.MAUL then
            -- "Increases the druid's next attack by 18 damage."
            ab.maul = A("MAUL", { extra = P("MAUL", 1).plain[1] })
        end
        if s.PRIMAL_BITE then
            -- "Bite the target, dealing 100% normal damage plus 26 and generating a high amount of threat."
            local p = P("PRIMAL_BITE", 1, 0, 1)
            ab.primalBite = A("PRIMAL_BITE", { pct = p.pct[1] / 100, extra = p.plain[1], fire = M.PrimalBite })
        end
        if s.ENRAGE then
            -- "Instantly generates 10 Rage and another 20 Rage over 10 sec, but reduces base armor by 27% in Bear Form
            -- and 16% in Dire Bear Form."; no global cooldown (CMaNGOS spell_template 5229: StartRecoveryTime 0)
            local p = P("ENRAGE", 2, 1)
            ab.enrage = A("ENRAGE", { gcd = 0, now = p.plain[1], later = p.plain[2], over = p.time[1], fire = M.Enrage })
        end
        if s.BERSERK then
            -- "Causes your Primal Bite ability to strike up to 3 targets, removes its cooldown, ... Lasts 15 sec."
            ab.berserk = A("BERSERK", { gcd = 0, duration = P("BERSERK", 0, 1).time[1], fire = M.BearBerserk })
        end
    else
        c.hands = {}
        if s.WRATH then ab.wrath = A("WRATH", { damage = Average(P("WRATH", 2), 1), fire = M.Bolt }) end
        if s.STARFIRE then ab.starfire = A("STARFIRE", { damage = Average(P("STARFIRE", 2), 1), fire = M.Bolt }) end
        if s.MOONFIRE then
            -- "Burns the enemy for 102 to 120 Arcane damage and then an additional 196 Arcane damage over 12 sec."
            local p = P("MOONFIRE", 3, 1)
            local ticks = (p.time[1] + Talent(c, "NATURES_SPLENDOR", "time", 1)) / MOONFIRE_TICK
            ab.moonfire = A("MOONFIRE", { damage = Average(p, 1), perTick = p.plain[3] / (p.time[1] / MOONFIRE_TICK),
                ticks = ticks, tick = MOONFIRE_TICK, fire = M.Bolt })
        end
        if s.INSECT_SWARM then
            -- "... causing 48 Nature damage over 12 sec."
            local p = P("INSECT_SWARM", 1, 1)
            -- Nature's Splendor: "... Moonfire and Rejuvenation spells by 3 sec, your Regrowth spell by 6 sec, and your
            -- Insect Swarm spell by 2 sec." (the owner's research, answer 15: +3 sec Moonfire, +2 sec Insect Swarm),
            -- added to the description's time: whether the game's text (a plain $d) already has it is open (in-game)
            local ticks = (p.time[1] + Talent(c, "NATURES_SPLENDOR", "time", 3)) / SWARM_TICK
            ab.swarm = A("INSECT_SWARM", { perTick = p.plain[#p.plain] / (p.time[1] / SWARM_TICK), ticks = ticks,
                tick = SWARM_TICK, fire = M.Swarm })
        end
        -- the filler: whichever bolt does more per second of casting (Eclipse alternates them)
        local function PerSecond(a)
            return a and (a.damage + a.coef * c.sp[a.school]) / math.max(1.5, a.cast) or 0
        end
        ab.filler = PerSecond(ab.starfire) > PerSecond(ab.wrath) and ab.starfire or ab.wrath
        assert(ab.filler, "no damage spell")
    end
    c.ab = ab
end

-- The schools of the spells the fights cast (the simulator window shows them): Balance's (and Restoration's) Nature
-- (Wrath, Insect Swarm) and Arcane (Moonfire, Starfire); a cat or a bear casts none.
function M.Schools(c)
    if c.spec == "CAT" or c.spec == "BEAR" then return {} end
    return (c.ab.moonfire or c.ab.starfire) and { "nature", "arcane" } or { "nature" }
end

-- The ways the fights play the character: a cat opens from Prowl with each opener it has ("RAVAGE", "POUNCE";
-- Sim.Jobs.Fights fights each way and keeps the one that does more, as a player would); none for Balance and for a cat
-- without an opener (one way).
local OPENERS = { RAVAGE = "ravage", POUNCE = "pounce" }
function M.Variants(c)
    if c.spec ~= "CAT" then return nil end
    local list = {}
    for _, key in ipairs({ "RAVAGE", "POUNCE" }) do
        if c.ab[OPENERS[key]] then list[#list + 1] = key end
    end
    return list[1] and list or nil
end

-- Genesis: "Increases the periodic damage and healing done by your spells and abilities by 1%" a rank: Balance's damage
-- over time and the cat's bleeds (Rake's, Rip's and Pounce's ticks).
local function Genesis(c) return 1 + Talent(c, "GENESIS", "pct") / 100 end

---------------------------------------------------------------------------
-- Balance
---------------------------------------------------------------------------
-- Moonfury, Naturalist, Improved Moonfire; Genesis on damage over time.
local function SpellMult(F, ab, periodic)
    local c = F.char
    local m = (1 + Talent(c, "MOONFURY", "pct") / 100) * (1 + Talent(c, "NATURALIST", "pct") / 100)
    if ab.key == "MOONFIRE" then m = m * (1 + Talent(c, "IMPROVED_MOONFIRE", "pct") / 100) end
    if periodic then m = m * Genesis(c) end
    return m
end

local function Opts(F, ab)
    local c = F.char
    return { crit = ab.key == "MOONFIRE" and Talent(c, "IMPROVED_MOONFIRE", "pct") or 0,
        critMult = 1 + 0.5 * (1 + Talent(c, "VENGEANCE", "pct") / 100) }
end

-- A tick of Moonfire or Insect Swarm can crit (SpellMisc Attributes[8] 0x200 "periodic can crit" on every rank;
-- SpellCategories DefenseType 1, magic): the school's spell crit plus Improved Moonfire's (aura 107 misc 7, its class
-- mask names Moonfire only), a spell crit's size with Vengeance (aura 108 misc 15, its class mask names both): Opts.
-- Nature's Grace stays with the spells' own crits ("All non-periodic spell criticals"; SpellAuraOptions 16880:
-- ProcTypeMask 0x14000, no periodic bit 0x40000).
local function DotOpts(F, ab)
    local opts = Opts(F, ab)
    return { crit = F.char.spellCrit[ab.school] + opts.crit, critMult = opts.critMult }
end

function M.Bolt(F, ab)
    local c = F.char
    local result = F:SpellHit(ab.key, ab.school, (ab.damage + ab.coef * c.sp[ab.school]) * SpellMult(F, ab), Opts(F, ab))
    if result == Sim.MISS then return end
    if result == Sim.CRIT and c.talents.NATURES_GRACE then
        F:AddBuff("NATURES_GRACE", Talent(c, "NATURES_GRACE", "time"), Talent(c, "NATURES_GRACE", "pct") / 100)
    end
    if ab.perTick then
        local perTick = (ab.perTick + ab.dotCoef * c.sp.arcane) * SpellMult(F, ab, true) * F:Resist()
        F:Dot("MOONFIRE_DOT", perTick, ab.ticks, ab.tick, DotOpts(F, ab))
    end
    -- Eclipse: Wrath makes the next Starfires quicker
    if ab.key == "WRATH" and c.talents.ECLIPSE then
        -- "reduces the cast time of your next 2 Starfire spells by 0.50 sec. Stores up to 4 charges. Lasts 15 sec."
        local eclipse = F:AddBuff("ECLIPSE", Talent(c, "ECLIPSE", "time", 2), Talent(c, "ECLIPSE", "time", 1))
        eclipse.charges = min(Talent(c, "ECLIPSE", "plain", 2), (eclipse.charges or 0) + Talent(c, "ECLIPSE", "plain", 1))
    end
end

function M.Swarm(F, ab)
    local c = F.char
    if F:SpellResult("nature") == Sim.MISS then
        F:Record("INSECT_SWARM", 0, Sim.MISS)
        return
    end
    F:Dot("INSECT_SWARM", (ab.perTick + ab.dotCoef * c.sp.nature) * SpellMult(F, ab, true) * F:Resist(), ab.ticks,
        ab.tick, DotOpts(F, ab))
end

---------------------------------------------------------------------------
-- Cat
---------------------------------------------------------------------------
local function AddCp(F, n) F.cp = min(MAX_CP, F.cp + n) end

-- Tiger's Fury: "Increases Physical damage done by 15% for 6 sec." Every damage of the cat is Physical (its white
-- swings; CMaNGOS spell_template School 0 of Claw, Shred, Ravage, Rake, Rip, Ferocious Bite and Pounce Bleed): its
-- swings and abilities while it lasts. A bleed put on while it lasts keeps it for all of its ticks, as the cat's other
-- modifiers (CatMult: a damage over time keeps what it was put on with; Fight:Dot's tickMult is for the target's
-- debuffs); whether Forever's bleeds keep it so is not proven.
local function Fury(F)
    local fury = F:Buff("TIGERS_FURY")
    return fury and 1 + fury.value or 1
end

-- The cat's abilities: Savage Fury, Rend and Tear (a bleeding target), Tiger's Fury, the paws' damage modifier on flat
-- damage.
local function CatMult(F, key)
    local c = F.char
    local m = Fury(F)
    if SAVAGE_FURY[key] then m = m * (1 + Talent(c, "SAVAGE_FURY", "pct") / 100) end
    if F:Debuff("RAKE") or F:Debuff("RIP") or F:Debuff("POUNCE") then
        m = m * (1 + Talent(c, "REND_AND_TEAR", "pct") / 100)
    end
    return m
end

local function CritMult(c) return 2 + Talent(c, "PREDATORY_INSTINCTS", "pct") / 100 end

-- A tick of a bleed can crit (Rake, Rip, Pounce Bleed: SpellMisc Attributes[8] 0x200 "periodic can crit" on every
-- rank; SpellCategories DefenseType 2, melee): the paws' crit with the weapon skill rule, as Fight:SpecialResult counts
-- it for an ability, plus extra (Berserk's on Rake: aura 107 misc 7, its class mask names Rake, not Rip); critMult: a
-- melee crit's size with Predatory Instincts where its class mask reaches the bleed (CritMult: aura 108 misc 15, Rake
-- and Rip). A tick's crit adds no Blood Frenzy point ("non-periodic critical strikes"; SpellAuraOptions 16958:
-- ProcTypeMask 0x14, no periodic bit 0x40000).
local function BleedOpts(F, critMult, extra)
    local c, w = F.char, F.char.mh
    return { crit = Sim.WeaponCrit(c.crit + (w.critBonus or 0) + (extra or 0), F.target.defense, w.skill),
        critMult = critMult }
end

-- Blood Frenzy on a crit of a combo point builder: "your non-periodic critical strikes from Cat Form abilities that
-- generate Combo Points have a 50% chance to add an additional Combo Point" (the text's second chance; its first is the
-- bear's rage).
local function BloodFrenzyPoint(F)
    local c = F.char
    if c.talents.BLOOD_FRENZY and F:Roll() * 100 < Talent(c, "BLOOD_FRENZY", "pct", 2) then AddCp(F, 1) end
end

-- A combo point builder: a share of the paws' damage plus a flat amount; Blood Frenzy adds a point on a crit,
-- Berserk makes it crit.
function M.Builder(F, ab)
    local c, w = F.char, F.char.mh
    local berserk = F:Buff("BERSERK")
    local result = F:SpecialResult(w, berserk and berserk.value or 0)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = (ab.pct * F:WeaponRoll(w, c.ap, false) + ab.extra * w.pct) * CatMult(F, ab.key)
        if result == Sim.CRIT then damage = damage * CritMult(c) end
        damage = F:AfterArmor(damage)
        AddCp(F, 1)
        if result == Sim.CRIT then BloodFrenzyPoint(F) end
    end
    F:Record(ab.key, damage, result)
end

-- Rake: a hit and a bleed, with attack power (CMaNGOS spell_bonus_data); a bleed ignores armor. A bleed put on while
-- Berserk lasts keeps its crit for all of its ticks, as the bleeds keep the cat's other modifiers (whether the game
-- reads it at each tick instead is not proven).
function M.Rake(F, ab)
    local c, w = F.char, F.char.mh
    local berserk = F:Buff("BERSERK")
    local result = F:SpecialResult(w, berserk and berserk.value or 0)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("RAKE", 0, result)
        return
    end
    local mult = CatMult(F, "RAKE") * w.pct
    local damage = (ab.damage + RAKE_AP * c.ap) * mult
    if result == Sim.CRIT then damage = damage * CritMult(c) end
    F:Record("RAKE", F:AfterArmor(damage), result)
    F:Dot("RAKE", (ab.total / ab.ticks + RAKE_AP_DOT * c.ap) * mult * Genesis(c), ab.ticks, RAKE_TICK,
        BleedOpts(F, CritMult(c), berserk and berserk.value))
    AddCp(F, 1)
    if result == Sim.CRIT then BloodFrenzyPoint(F) end
end

-- Pounce: a stun and a bleed, the damage of its description over its time, one tick every 3 seconds, plus attack power
-- per tick (CMaNGOS spell_bonus_data); a bleed ignores armor. A tick's crit is a melee crit's double damage: Pounce
-- Bleed (9007, 9824, 9826) has no SpellClassOptions row, so no talent's class mask reaches it (Predatory Instincts'
-- names Pounce, 9005 ...).
function M.Pounce(F, ab)
    local c, w = F.char, F.char.mh
    local result = F:SpecialResult(w)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("POUNCE", 0, result)
        return
    end
    F:Dot("POUNCE", (ab.total / ab.ticks + POUNCE_AP_DOT * c.ap) * CatMult(F, "POUNCE") * w.pct * Genesis(c), ab.ticks,
        POUNCE_TICK, BleedOpts(F, POUNCE_BLEED_CRIT))
    AddCp(F, ab.cp)
end

-- Rip: the damage of its points over their time, one tick every 2 seconds, plus attack power per tick.
function M.Rip(F, ab)
    local c, w = F.char, F.char.mh
    local cp = F.cp
    local result = F:SpecialResult(w)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("RIP", 0, result)
        return
    end
    local ticks = ab.times[cp][1] / RIP_TICK
    F:Dot("RIP", (ab.totals[cp][1] / ticks + c.ap * min(cp, 4) / 100) * CatMult(F, "RIP") * w.pct * Genesis(c), ticks,
        RIP_TICK, BleedOpts(F, CritMult(c)))
    F.cp = 0
end

-- Ferocious Bite: the range of its points plus 3 % of attack power per point, and the energy left after its cost:
-- "converts each extra point of energy into 2.7 additional damage" (all of it). A miss or a dodge converts none (the
-- text names it as damage; what the game does with that energy then is not proven).
function M.Bite(F, ab)
    local c, w = F.char, F.char.mh
    local cp = F.cp
    local result = F:SpecialResult(w)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        local range = ab.ranges[cp]
        local extra = F.energy
        F.energy = 0
        damage = (range[1] + (range[2] - range[1]) * F:Roll() + c.ap * 0.03 * cp + extra * ab.perEnergy)
            * CatMult(F, "FEROCIOUS_BITE") * w.pct
        if result == Sim.CRIT then damage = damage * CritMult(c) end
        damage = F:AfterArmor(damage)
        F.cp = 0
    end
    F:Record("FEROCIOUS_BITE", damage, result)
end

function M.Berserk(F, ab) F:AddBuff("BERSERK", ab.duration, ab.crit) end

function M.TigersFury(F, ab) F:AddBuff("TIGERS_FURY", ab.duration, ab.pct) end

function M.ShiftingPower(F, ab) F:GainEnergy(ab.energy) end

---------------------------------------------------------------------------
-- Bear
---------------------------------------------------------------------------
-- Blood Frenzy: "a 50% chance to gain an additional 5 Rage any time you get a critical strike while in Bear Form".
local function BloodFrenzyRage(F)
    local c = F.char
    if c.talents.BLOOD_FRENZY and F:Roll() * 100 < Talent(c, "BLOOD_FRENZY", "pct") then
        F:GainRage(Talent(c, "BLOOD_FRENZY", "plain"))
    end
end

-- Maul takes the next swing when the rage left above Primal Bite's cost pays for it.
local function WantMaul(F)
    local ab = F.char.ab
    return ab.maul ~= nil and F.rage >= ab.maul.cost + (ab.primalBite and ab.primalBite.cost or 0)
end

-- Maul: the swing with more damage (Savage Fury; Predatory Instincts on a crit); no rage from that swing.
local function Maul(F)
    local c, w, ab = F.char, F.char.mh, F.char.ab.maul
    F.rage = F.rage - ab.cost
    local result = F:SpecialResult(w)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = (F:WeaponRoll(w, c.ap, false) + ab.extra * w.pct) * (1 + Talent(c, "SAVAGE_FURY", "pct") / 100)
        if result == Sim.CRIT then damage = damage * CritMult(c) end
        damage = F:AfterArmor(damage)
    end
    F:Record("MAUL", damage, result)
    if result == Sim.CRIT then BloodFrenzyRage(F) end
end

-- Primal Bite: a share of the paws' damage plus a flat amount (Predatory Instincts on a crit); no cooldown while
-- Berserk lasts.
function M.PrimalBite(F, ab)
    local c, w = F.char, F.char.mh
    if F:Buff("BERSERK") then F:Cooldown(ab.key, 0) end
    local result = F:SpecialResult(w)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = ab.pct * F:WeaponRoll(w, c.ap, false) + ab.extra * w.pct
        if result == Sim.CRIT then damage = damage * CritMult(c) end
        damage = F:AfterArmor(damage)
    end
    F:Record("PRIMAL_BITE", damage, result)
    if result == Sim.CRIT then BloodFrenzyRage(F) end
end

-- Enrage: rage now, the rest in equal ticks.
local function EnrageTick(F, left)
    local ab = F.char.ab.enrage
    F:GainRage(ab.later / (ab.over / ENRAGE_TICK))
    if left > 1 then F:At(F.t + ENRAGE_TICK, EnrageTick, left - 1) end
    F:Free()
end

function M.Enrage(F, ab)
    F:GainRage(ab.now)
    F:At(F.t + ENRAGE_TICK, EnrageTick, ab.over / ENRAGE_TICK)
end

-- Berserk in Bear Form: Primal Bite has no cooldown while it lasts (M.PrimalBite); a running one ends.
function M.BearBerserk(F, ab)
    F:AddBuff("BERSERK", ab.duration)
    F:Cooldown("PRIMAL_BITE", 0)
end

-- The paws' white swing (a cat's or a bear's), with Tiger's Fury while it lasts (a cat's). A bear's makes way for Maul
-- (WantMaul) and gives rage from its damage (Sim.RageFromDamage, CMaNGOS Player::RewardRage), Blood Frenzy's too on a
-- crit.
function M.Swing(F, hand)
    local c, w = F.char, F.char[hand]
    local bear = c.spec == "BEAR"
    if bear and WantMaul(F) then
        Maul(F)
        return
    end
    local result = F:WhiteResult(w, false)
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = F:WeaponRoll(w, c.ap, false) * Fury(F)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * 2
        end
        damage = F:AfterArmor(damage)
        if bear then
            F:GainRage(Sim.RageFromDamage(damage, c.level))
            if result == Sim.CRIT then BloodFrenzyRage(F) end
        end
    end
    F:Record("MELEE", damage, result)
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
function M.Start(F)
    local ab = F.char.ab
    -- from Prowl: the way's opener (Ravage or Pounce; none without a way)
    local opener = F.opts.variant and ab[OPENERS[Sim.VariantKeys(F.opts.variant)[1]]]
    if opener and F:Can(opener) then F:Use(opener) end
    -- a bear shifts into Bear Form at the pull: the shift's global cooldown (Primal Bite waits for its end, and so do
    -- Berserk and Enrage: a running one holds them), Furor's "20% chance to gain 10 Rage"
    local c = F.char
    if c.spec == "BEAR" then
        F.gcd = F.t + SHIFT_GCD
        if c.talents.FUROR and F:Roll() * 100 < Talent(c, "FUROR", "pct") then
            F:GainRage(Talent(c, "FUROR", "plain"))
        end
    end
end

local function Cast(F, ab, cast)
    if F:Can(ab) then
        F:Use(ab, nil, cast)
        return true
    end
end

-- Nature's Grace (faster casting while it lasts) and Eclipse shorten a cast.
local function CastTime(F, ab)
    local cast = ab.cast
    local eclipse = ab.key == "STARFIRE" and F:Buff("ECLIPSE")
    if eclipse and eclipse.charges > 0 then cast = cast - eclipse.value end
    local grace = F:Buff("NATURES_GRACE")
    if grace then cast = cast / (1 + grace.value) end
    return cast
end

-- A Balance spell. Nature's Grace up when it starts shortens its global cooldown too: "increasing your spellcasting
-- speed and reducing your global cooldown by 10% for 3 sec" (1.5 sec x 0.9; the spell's own crit puts it on after the
-- start).
local function CastSpell(F, ab, cast)
    if not F:Can(ab) then return false end
    local grace = F:Buff("NATURES_GRACE")
    F:Use(ab, nil, cast)
    if grace then F.gcd = F.t + ab.gcd * (1 - grace.value) end
    return true
end

local function CastBolt(F, ab)
    if not F:Can(ab) then return false end
    local cast = CastTime(F, ab)
    local eclipse = ab.key == "STARFIRE" and F:Buff("ECLIPSE")
    if eclipse and eclipse.charges > 0 then eclipse.charges = eclipse.charges - 1 end
    return CastSpell(F, ab, cast)
end

function M.Act(F)
    local c = F.char
    local ab = c.ab
    local left = F.len - F.t
    if c.spec == "CAT" then
        -- Berserk and Tiger's Fury take no global cooldown (Tiger's Fury no energy either: a sure gain on cooldown);
        -- the cat goes on in the same moment. Both come at the first look after the opener: that either keeps Prowl,
        -- so that it could come before the opener, is not proven.
        if ab.berserk then Cast(F, ab.berserk) end
        if ab.tigersFury then Cast(F, ab.tigersFury) end
        if F.t + 1e-6 < F.gcd then return end
        -- Shifting Power below 40 energy takes the global cooldown: the cat's next ability waits for its end
        if ab.shifting and F.energy < 40 and Cast(F, ab.shifting) then return end
        if F.cp == MAX_CP then
            if ab.rip and not F:Debuff("RIP") and left > ab.rip.times[MAX_CP][1] and Cast(F, ab.rip) then return end
            if ab.bite and Cast(F, ab.bite) then return end
        end
        if ab.rake and not F:Debuff("RAKE") and left > ab.rake.ticks * RAKE_TICK / 2 and F.cp < MAX_CP
            and Cast(F, ab.rake) then return end
        if F.cp < MAX_CP and Cast(F, ab.builder) then return end
        local function At(a) return a and F:ReadyAt(a.key) end
        return F:Next(At(ab.berserk), At(ab.tigersFury), At(ab.shifting))
    end
    if c.spec == "BEAR" then
        -- Berserk and Enrage take no global cooldown; Maul goes with the swings (M.Swing)
        if ab.berserk then Cast(F, ab.berserk) end
        if ab.enrage then Cast(F, ab.enrage) end
        if ab.primalBite and Cast(F, ab.primalBite) then return end
        -- rage arrives with the swings and Enrage's ticks (they ask again)
        local function At(a) return a and F:ReadyAt(a.key) end
        return F:Next(At(ab.berserk), At(ab.enrage), At(ab.primalBite))
    end
    if ab.moonfire and not F:Debuff("MOONFIRE_DOT") and left > ab.moonfire.ticks * MOONFIRE_TICK / 2
        and CastSpell(F, ab.moonfire) then return end
    if ab.swarm and not F:Debuff("INSECT_SWARM") and left > ab.swarm.ticks * SWARM_TICK / 2
        and CastSpell(F, ab.swarm) then return end
    if c.talents.ECLIPSE and ab.wrath and ab.starfire then
        local eclipse = F:Buff("ECLIPSE")
        if eclipse and eclipse.charges > 0 then
            if CastBolt(F, ab.starfire) then return end
        elseif CastBolt(F, ab.wrath) then
            return
        end
    elseif CastBolt(F, ab.filler) then
        return
    end
    -- short of mana: the mana ticks ask again
    return nil
end
