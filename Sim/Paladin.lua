-- Lootified - simulator model of the Retribution, the Protection and the Holy Paladin in WoW: Forever (all against the
-- target dummy, each with its talents, the same rotation: the Holy paladin's damage with its gear; Holy (Damage), the
-- Holy tree played for damage, is the same). Rotation: keep a seal up (Seal of Command, Seal of Righteousness
-- or Seal of Fury), Hammer of Wrath when the target is low, Holy Strike and Judgement on cooldown (in Forever, Judgement
-- leaves the seal in place), Holy Shock (Divine Favor before it) whenever it is ready, Consecration with the mana the rest
-- does not need (Consecrate); the fights play each seal with and without Consecration and with and without Holy Shock
-- and keep the way that does more (M.Variants). Talents: Vengeance, Sacred Arbiter, Improved Seals, Two-Handed and
-- One-Handed Weapon Specialization, Champion of the Light, Sanctified Judgement, Holy Power. The numbers of the
-- abilities and talents come from their descriptions in the game, costs, cast times and cooldowns from the game, the
-- shares of spell power from the game's own tables
-- (Sim.SpellPower, the seals' below); proc rates and formulas are below (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent = Sim.Talent

local M = { class = "PALADIN", specs = { RET = true, PROT = true, HOLY = true, HOLY_DMG = true }, hands = { "mh" } }
Sim.models.PALADIN = M

local min = math.min

-- Any rank of each ability (the spell book has the best rank) and the talents' spells.
M.spells = {
    HOLY_STRIKE = 679, SEAL_OF_RIGHTEOUSNESS = 20154, SEAL_OF_COMMAND = 20375, JUDGEMENT = 20271,
    HAMMER_OF_WRATH = 24275, CONSECRATION = 26573, SEAL_OF_FURY = 1311649, HOLY_SHOCK = 1311606, DIVINE_FAVOR = 20216,
}
M.talents = {
    VENGEANCE = 20049, SACRED_ARBITER = 1311087, IMPROVED_SEALS = 20224, TWO_HANDED = 20111,
    CHAMPION_OF_THE_LIGHT = 1311084, ONE_HANDED = 20196, SANCTIFIED_JUDGEMENT = 1311074, HOLY_POWER = 5923,
    DIVINE_STRENGTH = 20262, DIVINE_INTELLECT = 20257,
}
-- The damage that rides on the swings (the seals'): no attacks of their own (the simulator window's summary).
M.procs = { SEAL_OF_RIGHTEOUSNESS = true, SEAL_OF_COMMAND = true, SEAL_OF_FURY = true }

local SOC_PPM = 7                     -- Seal of Command: 7 procs per minute (CMaNGOS spell_proc_event 20375)
-- Spell power shares the game's own tables (SpellEffect) give the seals' damage and Holy Strike's, the same for every
-- rank (Sim.SpellPower reads a spell's own damage only): Holy Strike's Holy damage (679 ...: 0.429), Seal of Command's
-- proc (20424: 0.29), Judgement of Command (20467 ...: 0.429), Judgement of Righteousness (20187 ...: 0.5), Seal of
-- Fury's Holy damage on a swing (1311647, 1311654: 0.1) and its judgement (1311650, 1311655: 0.45).
local SP_HOLY_STRIKE, SP_SOC, SP_JOC, SP_JOR, SP_SOF, SP_JOF = 0.429, 0.29, 0.429, 0.5, 0.1, 0.45
local CONSECRATION_TICK = 1           -- a tick a second (CMaNGOS: its area aura's period)
-- Holy Power: "Increases the critical strike chance of your Holy Shock and Holy Strike spells by $m2%, and all other
-- spells by $m1%." The game shows no numbers in its rank texts; its own tables have them a rank (trait definition
-- 134816, TraitDefinitionEffectPoints: curves 110324 and 82962). "All other spells" are the ones its masks name
-- (SpellClassOptions): of what the fights cast, Seal of Command's proc, the judgements, Hammer of Wrath, Consecration
-- (it does not crit) and the Holy damage of Seal of Righteousness and Seal of Fury on the swings (SealHit).
local HOLY_POWER_SHOCK = { 3, 6, 9, 12, 15 }   -- Holy Shock and Holy Strike
local HOLY_POWER_OTHER = { 1, 2, 3, 4, 5 }
local EXECUTE_PHASE = 0.8             -- the target is below 20 % health for the last fifth of the fight

-- Holy Power's extra crit (%) on Holy Shock and Holy Strike (list HOLY_POWER_SHOCK) or the other spells.
local function HolyPower(c, list)
    local t = c.talents.HOLY_POWER
    if not t then return 0 end
    return assert(list[t.rank], "Holy Power: unexpected rank")
end

local function Average(list, from, to)
    local sum, n = 0, 0
    for i = from, min(to, #list) do sum, n = sum + list[i], n + 1 end
    return n > 0 and sum / n or 0
end

-- The talents that raise a stat by a percent, an item's too (Character.WithStats): Divine Strength "Increases your
-- Strength by 10%." and Divine Intellect "Increases your total Intellect by 10%." (SpellEffect 20262, 20257: aura 137
-- MOD_TOTAL_STAT_PERCENTAGE, EffectMiscValue[1] the stat mask: 1 Strength, 8 Intellect).
function M.StatMods(c)
    return { str = 1 + Talent(c, "DIVINE_STRENGTH", "pct") / 100, agi = 1,
        int = 1 + Talent(c, "DIVINE_INTELLECT", "pct") / 100 }
end

-- The numbers the fights need, from the descriptions (c.ab: the abilities).
function M.Setup(c)
    assert(c.mh, "no weapon")
    local ab, s = {}, c.spells
    if s.HOLY_STRIKE then
        -- "An instant strike that causes 25% weapon damage plus an additional 11 to 14 as Holy damage."
        local p = s.HOLY_STRIKE.p
        assert(p.pct[1] and p.plain[1], "Holy Strike: unexpected description")
        ab.holyStrike = Sim.Ability(s.HOLY_STRIKE, { pct = p.pct[1] / 100, flat = Average(p.plain, 1, 2),
            fire = M.HolyStrike })
    end
    if s.SEAL_OF_RIGHTEOUSNESS then
        -- "... for 30 sec, granting each melee attack an additional 2.5 to 8.6 Holy damage. ... Unleashing this Seal's
        -- energy will cause 25 to 27 Holy damage to an enemy." The per-swing range is the spell's points / 87 to
        -- points / 25 (fast to slow weapons); rank 1 cannot be judged.
        local p = s.SEAL_OF_RIGHTEOUSNESS.p
        assert(p.time[1] and p.plain[2], "Seal of Righteousness: unexpected description")
        ab.sor = Sim.Ability(s.SEAL_OF_RIGHTEOUSNESS, { duration = p.time[1], points = p.plain[2] * 25,
            judgement = Average(p.plain, 3, 4), fire = M.Seal })
    end
    if s.SEAL_OF_COMMAND then
        -- "... equal to 70% of normal weapon damage. ... Lasts 30 sec. Unleashing this Seal's energy will judge an enemy,
        -- instantly causing 46 to 51 Holy damage, 93 to 101 if the target is stunned or incapacitated." (its first
        -- range: the damage against a target that is not stunned, as the target dummy)
        local p = s.SEAL_OF_COMMAND.p
        assert(p.pct[1] and p.time[1] and p.plain[2], "Seal of Command: unexpected description")
        ab.soc = Sim.Ability(s.SEAL_OF_COMMAND, { pct = p.pct[1] / 100, duration = p.time[1],
            judgement = Average(p.plain, 1, 2), fire = M.Seal })
    end
    if s.SEAL_OF_FURY then
        -- "Fills you with divine fury for 30 sec, causing melee attacks to deal an additional 6 Holy damage. While a
        -- shield is equipped, each attack also grants an absorb shield equal to 50% of the Holy damage dealt. ...
        -- Unleashing this Seal's energy inflicts32 to 35 Holy damage to an enemy and taunts the target to attack you
        -- for 4 sec." (the shield and the taunt do no damage; spell power: SP_SOF, SP_JOF)
        local p = s.SEAL_OF_FURY.p
        assert(p.time[1] and #p.plain == 3, "Seal of Fury: unexpected description")
        ab.sof = Sim.Ability(s.SEAL_OF_FURY, { duration = p.time[1], perHit = p.plain[1],
            judgement = Average(p.plain, 2, 3), fire = M.Seal })
    end
    assert(ab.sor or ab.soc or ab.sof, "no seal")
    -- no global cooldown (SpellCooldowns 20271: StartRecoveryTime 0)
    ab.judgement = Sim.Ability(s.JUDGEMENT, { gcd = 0, fire = M.Judgement })
    if s.HAMMER_OF_WRATH then
        -- "Hurls a hammer that strikes an enemy for 316 to 348 Holy damage. Only usable on enemies that have 20% or
        -- less health." A global cooldown of 1 sec (SpellCooldowns 24275, 24274, 24239: StartRecoveryTime 1000)
        local p = s.HAMMER_OF_WRATH.p
        assert(p.plain[2], "Hammer of Wrath: unexpected description")
        ab.hammer = Sim.Ability(s.HAMMER_OF_WRATH, { damage = Average(p.plain, 1, 2),
            coef = Sim.SpellPower(s.HAMMER_OF_WRATH), gcd = 1, fire = M.Hammer })
    end
    if s.CONSECRATION then
        -- "doing 24 Holy damage over 8 sec to enemies who enter the area. The first 4 enemies who enter the area will
        -- take an additional 56 damage over 8 sec.": the target takes both (a text without the second sentence: the
        -- first damage only); each second a hit of its damage spell (Sim.SpellPower: that spell's share)
        local p = s.CONSECRATION.p
        assert(p.time[1] and (#p.plain == 1 or #p.plain == 3), "Consecration: unexpected description")
        local ticks = p.time[1] / CONSECRATION_TICK
        ab.consecration = Sim.Ability(s.CONSECRATION, { perTick = (p.plain[1] + (p.plain[3] or 0)) / ticks,
            ticks = ticks, coef = Sim.SpellPower(s.CONSECRATION), fire = M.Consecration })
    end
    if s.HOLY_SHOCK then
        -- "Blasts the target with Holy energy, causing 129 to 139 Holy damage to an enemy, or 110 to 118 healing to an
        -- ally." (its first range; spell power: its damage spell's, Sim.SpellPower)
        local p = s.HOLY_SHOCK.p
        assert(#p.plain == 4, "Holy Shock: unexpected description")
        ab.holyShock = Sim.Ability(s.HOLY_SHOCK, { damage = Average(p.plain, 1, 2), coef = Sim.SpellPower(s.HOLY_SHOCK),
            fire = M.HolyShock })
        if s.DIVINE_FAVOR then
            -- "When activated, gives your next Flash of Light, Holy Light, or Holy Shock spell a 100% critical effect
            -- chance.": used only before Holy Shock; no global cooldown (CMaNGOS spell_template 20216:
            -- StartRecoveryTime 0)
            local q = s.DIVINE_FAVOR.p
            assert(q.pct[1], "Divine Favor: unexpected description")
            ab.divineFavor = Sim.Ability(s.DIVINE_FAVOR, { gcd = 0, crit = q.pct[1], fire = M.DivineFavor })
        end
    end
    c.ab = ab
end

-- Two-Handed Weapon Specialization for two-handers, One-Handed Weapon Specialization for the others.
function M.WeaponMods(c, w)
    local talent = w.twoHand and "TWO_HANDED" or "ONE_HANDED"
    return { pct = 1 + Talent(c, talent, "pct") / 100, crit = 0, armorIgnore = 0 }
end

-- The schools of the spells the fights cast (the simulator window shows them): the Holy damage of the seals, Holy
-- Strike, the judgements and Holy Shock.
function M.Schools() return { "holy" } end

-- Champion of the Light: a share of Intellect as spell damage.
function M.WithIntellect(c, int)
    c.sp.holy = c.sp.holy + int * Talent(c, "CHAMPION_OF_THE_LIGHT", "pct") / 100
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- Vengeance: physical and holy damage up by its percent per stack.
local function Vengeance(F)
    local v = F:Buff("VENGEANCE")
    return v and 1 + v.stacks * v.value or 1
end

-- Improved Seals: the seals' and judgements' damage.
local function Seals(c) return 1 + Talent(c, "IMPROVED_SEALS", "pct") / 100 end

local function OnCrit(F)
    local c = F.char
    if c.talents.VENGEANCE then
        F:AddBuff("VENGEANCE", Talent(c, "VENGEANCE", "time"), Talent(c, "VENGEANCE", "pct") / 100,
            Talent(c, "VENGEANCE", "plain"))
    end
end

-- Seal of Righteousness per swing (CMaNGOS Unit::HandleDummyAuraProc): two-handers get 1.2 x, one-handers 0.85 x the
-- spell's points scaled by the weapon's speed, plus 3 % of the average weapon damage and a speed-scaled share of
-- spell power.
function M.SealOfRighteousnessHit(c, w)
    local points, speed = c.ab.sor.points, w.speed
    local base
    if w.twoHand then
        base = 1.2 * points * 1.2 * 1.03 * speed / 100 + 1
    else
        base = 0.85 * math.ceil(points * 1.2 * 1.03 * speed / 100) - 1
    end
    local sp = c.sp.holy * (w.twoHand and 0.108 or 0.092) * speed
    return base + 0.03 * (w.min + w.max) / 2 + 1 + sp
end

-- The ways the fights play the character: each seal it has, with Consecration too when it has it, and each of those
-- with Holy Shock too when it has it ("SEAL_OF_COMMAND", "SEAL_OF_COMMAND+CONSECRATION", "SEAL_OF_COMMAND+HOLY_SHOCK",
-- "SEAL_OF_COMMAND+CONSECRATION+HOLY_SHOCK" ...; Sim.Jobs.Fights fights each way and keeps the one that does more, as
-- a player would: Holy Shock's mana can cost a seal later). An estimate of the seals' damage picked the weaker one for
-- some characters (it kept Seal of Command up to 8 spell power too long): items with spell power were worth very
-- different amounts.
local SEALS = { SEAL_OF_COMMAND = "soc", SEAL_OF_RIGHTEOUSNESS = "sor", SEAL_OF_FURY = "sof" }
function M.Variants(c)
    local list = {}
    for _, key in ipairs({ "SEAL_OF_COMMAND", "SEAL_OF_RIGHTEOUSNESS", "SEAL_OF_FURY" }) do
        if c.ab[SEALS[key]] then
            local ways = { key }
            if c.ab.consecration then ways[2] = key .. "+CONSECRATION" end
            if c.ab.holyShock then
                for i = 1, #ways do ways[#ways + 1] = ways[i] .. "+HOLY_SHOCK" end
            end
            for _, way in ipairs(ways) do list[#list + 1] = way end
        end
    end
    return list
end

-- White swings: miss, dodge, glancing, crit or hit, then the seal.
function M.Swing(F, hand)
    local c, w = F.char, F.char[hand]
    local result = F:WhiteResult(w, false)
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = F:WeaponRoll(w, c.ap, false)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * 2
        end
        damage = F:AfterArmor(damage) * Vengeance(F)
    end
    F:Record("MELEE", damage, result)
    if result == Sim.CRIT then OnCrit(F) end
    if damage > 0 then M.SealProc(F, w) end
end

-- The Holy damage of Seal of Righteousness or Seal of Fury on a swing that landed (amount: a hit's). Their damage
-- spells (Seal of Righteousness 25742, 25741, 25740, 25739, 25738, 25737, 25736, 25735, 25713; Seal of Fury 1311647,
-- 1311654, 20231, 20415-20418) are melee attacks (SpellCategories DefenseType 2) without "cannot crit" (SpellMisc
-- Attributes[2] 0x20000000; the owner's research: Seal of Righteousness crits in player tests): no roll to hit or dodge
-- of their own, as before (SpellMisc Attributes[3] 0x40000 as Judgement of Command's damage spell, Attributes[0]
-- 0x200000), the main hand's crit with Holy Power's (its first effect's class mask, 33612840/538970752/8256/67108864,
-- reaches both: SpellClassOptions 0/536870912/0/0 and 0/2048/0/0), double damage (the 200 % is not measured); a crit
-- is a non-periodic critical strike for Vengeance, as Seal of Command's.
local function SealHit(F, w, key, amount)
    local c = F.char
    local damage, result = amount * Seals(c) * Vengeance(F), Sim.HIT
    local crit = Sim.WeaponCrit(c.crit + w.critBonus + HolyPower(c, HOLY_POWER_OTHER), F.target.defense, w.skill)
    if F:Roll() * 100 < crit then damage, result = damage * 2, Sim.CRIT end
    F:Record(key, damage, result)
    if result == Sim.CRIT then OnCrit(F) end
end

function M.SealProc(F, w)
    local c = F.char
    if F:Buff("SEAL_OF_COMMAND") then
        if F:Roll() < w.speed * SOC_PPM / 60 then
            local result = F:SpecialResult(w, HolyPower(c, HOLY_POWER_OTHER))
            local damage = 0
            if result == Sim.HIT or result == Sim.CRIT then
                damage = (c.ab.soc.pct * F:WeaponRoll(w, c.ap, false) + SP_SOC * c.sp.holy) * Seals(c) * Vengeance(F)
                if result == Sim.CRIT then damage = damage * 2 end
            end
            F:Record("SEAL_OF_COMMAND", damage, result)
            if result == Sim.CRIT then OnCrit(F) end
        end
    elseif F:Buff("SEAL_OF_RIGHTEOUSNESS") then
        SealHit(F, w, "SEAL_OF_RIGHTEOUSNESS", M.SealOfRighteousnessHit(c, w))
    elseif F:Buff("SEAL_OF_FURY") then
        -- the text's Holy damage on every swing that lands, as Seal of Righteousness's (the classic seals proc on
        -- melee auto attacks, CMaNGOS spell_template 20154, 20375: ProcFlags 4; whether Seal of Fury's "melee attacks"
        -- take in Holy Strike too is not proven: left out)
        SealHit(F, w, "SEAL_OF_FURY", c.ab.sof.perHit + SP_SOF * c.sp.holy)
    end
end

---------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------
function M.HolyStrike(F, ab)
    local c, w = F.char, F.char.mh
    local result = F:SpecialResult(w, HolyPower(c, HOLY_POWER_SHOCK))
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = ab.pct * F:WeaponRoll(w, c.ap, true) + ab.flat + SP_HOLY_STRIKE * c.sp.holy
        damage = damage * (1 + Talent(c, "SACRED_ARBITER", "pct") / 100) * Vengeance(F)
        if result == Sim.CRIT then damage = damage * 2 end
    end
    F:Record("HOLY_STRIKE", damage, result)
    if result == Sim.CRIT then OnCrit(F) end
end

-- Judgement: the judged seal's damage spell, a melee attack of Holy damage (SpellCategories DefenseType 2: Judgement
-- of Righteousness 20187, 20280-20286, of Command 20467, 20963-20966, of Fury 1311650, 1311655, 20183, 20411-20414)
-- that cannot be dodged, parried or blocked (SpellMisc Attributes[0] 0x200000): the melee miss (Judgement of Command's
-- damage spell cannot miss, Attributes[3] 0x40000, the spell that casts it can: 20425, 20962, 20961, 20967, 20968,
-- DefenseType 2, Attributes[0] 0x200000 too), the melee crit, double damage on a crit; the target's resistance as
-- before.
function M.Judgement(F)
    local c = F.char
    -- Sanctified Judgement: a chance to get back a share of the judged seal's cost
    if c.talents.SANCTIFIED_JUDGEMENT and F:Roll() * 100 < Talent(c, "SANCTIFIED_JUDGEMENT", "pct", 1) then
        F:GainMana(F.seal.cost * Talent(c, "SANCTIFIED_JUDGEMENT", "pct", 2) / 100)
    end
    local damage
    if F:Buff("SEAL_OF_COMMAND") then
        -- the text's range against a target that is not stunned; of the spell power half its share, as against such a
        -- target before (not proven)
        damage = c.ab.soc.judgement + SP_JOC * c.sp.holy / 2
    elseif F:Buff("SEAL_OF_FURY") then
        damage = c.ab.sof.judgement + SP_JOF * c.sp.holy
    else
        damage = c.ab.sor.judgement + SP_JOR * c.sp.holy
    end
    local result = F:SpecialResult(c.mh, HolyPower(c, HOLY_POWER_OTHER), true)
    local hit = 0
    if result == Sim.HIT or result == Sim.CRIT then
        hit = damage * Seals(c) * Vengeance(F) * F:Resist()
        if result == Sim.CRIT then hit = hit * 2 end
    end
    F:Record("JUDGEMENT", hit, result)
    if result == Sim.CRIT then OnCrit(F) end
end

-- Hammer of Wrath: a ranged attack of Holy damage (CMaNGOS damage class ranged: ranged hit and crit, double damage on
-- a crit), resisted like a spell.
function M.Hammer(F, ab)
    local c = F.char
    local skill = c.level * 5
    local damage, result = 0, Sim.HIT
    if F:Roll() * 100 < Sim.MissChance(F.target.defense, skill, c.rangedHit, false) then
        result = Sim.MISS
    else
        damage = (ab.damage + ab.coef * c.sp.holy) * F:Resist() * Vengeance(F)
        if F:Roll() * 100 < Sim.WeaponCrit(c.rangedCrit + HolyPower(c, HOLY_POWER_OTHER), F.target.defense, skill) then
            damage, result = damage * 2, Sim.CRIT
        end
    end
    F:Record("HAMMER_OF_WRATH", damage, result)
    if result == Sim.CRIT then OnCrit(F) end
end

-- Holy Shock: a Holy spell's hit and crit (its classic damage spells are magic ones, CMaNGOS spell_template 25912:
-- DmgClass 1); Divine Favor's crit goes with it.
function M.HolyShock(F, ab)
    local favor = F:Buff("DIVINE_FAVOR")
    F:RemoveBuff("DIVINE_FAVOR")
    local damage = (ab.damage + ab.coef * F.char.sp.holy) * Vengeance(F)
    local crit = (favor and favor.value or 0) + HolyPower(F.char, HOLY_POWER_SHOCK)
    local result = F:SpellHit("HOLY_SHOCK", "holy", damage, { crit = crit })
    if result == Sim.CRIT then OnCrit(F) end
end

function M.DivineFavor(F, ab) F:AddBuff("DIVINE_FAVOR", F.len, ab.crit) end

-- Consecration: the ground under the target burns it every second (one hit roll, as the other damage over time). Its
-- ticks do not crit: neither its periodic aura (226, a periodic dummy) nor its damage spell (1280345-1280349) has
-- SpellMisc Attributes[8] 0x200 "periodic can crit".
function M.Consecration(F, ab)
    local c = F.char
    if F:SpellResult("holy") == Sim.MISS then
        F:Record("CONSECRATION", 0, Sim.MISS)
        return
    end
    F:Dot("CONSECRATION", (ab.perTick + ab.coef * c.sp.holy) * F:Resist() * Vengeance(F), ab.ticks, CONSECRATION_TICK)
end

-- "Only one Seal can be active on the Paladin at any one time."
function M.Seal(F, ab)
    for key in pairs(SEALS) do F:RemoveBuff(key) end
    F:AddBuff(ab.key, ab.duration)
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
function M.Start(F)
    local c = F.char
    F.seal = c.ab[SEALS[Sim.VariantKeys(F.opts.variant)[1]]]
    assert(F.seal, "no seal to play")
    F.consecrate = Sim.VariantHas(F.opts.variant, "CONSECRATION")
    F.holyShock = Sim.VariantHas(F.opts.variant, "HOLY_SHOCK")
    -- the seal is up when the fight starts (put on before the pull)
    F:SpendMana(F.seal.cost)
    F:AddBuff(F.seal.key, F.seal.duration)
end

-- The mana the rotation needs from now to the end of the fight for what comes before Consecration (the seal renewed 3
-- seconds before it ends, Judgement, Holy Strike, Hammer of Wrath, Holy Shock in its way), each as often as it is ready,
-- less what the regeneration while casting brings by then. Consecration only with the mana beyond that, as a player
-- plays it: cast whenever ready, its mana ran out within the minute and Judgement and Holy Strike came less often (a
-- level 20 Retribution paladin with Consecration rank 1 and 702 mana: as much damage lost as Consecration did).
local function ManaNeeded(F)
    local ab = F.char.ab
    local function Uses(from, cooldown)
        assert(cooldown > 0, "Consecration's mana: an ability without a cooldown")
        if from >= F.len then return 0 end
        return 1 + math.floor((F.len - from) / cooldown)
    end
    local seal = F:Buff(F.seal.key)
    local need = Uses(math.max(F.t, (seal and seal.ends or F.t) - 3), F.seal.duration - 3) * F.seal.cost
    if F.seal.judgement > 0 then
        need = need + Uses(math.max(F.t, F:ReadyAt("JUDGEMENT")), ab.judgement.cooldown) * ab.judgement.cost
    end
    if ab.holyStrike then
        need = need + Uses(math.max(F.t, F:ReadyAt("HOLY_STRIKE")), ab.holyStrike.cooldown) * ab.holyStrike.cost
    end
    if ab.hammer then
        need = need + Uses(math.max(F.t, F.len * EXECUTE_PHASE, F:ReadyAt("HAMMER_OF_WRATH")), ab.hammer.cooldown)
            * ab.hammer.cost
    end
    if F.holyShock then
        need = need + Uses(math.max(F.t, F:ReadyAt("HOLY_SHOCK")), ab.holyShock.cooldown) * ab.holyShock.cost
    end
    return need - F.char.manaRegenCasting * (F.len - F.t)
end

-- Consecration now: with the mana beyond what comes before it needs until the end (ManaNeeded), and not when Holy
-- Strike comes ready within its global cooldown: Holy Strike would wait for it (the level 20 paladin above lost 0.7 of
-- Holy Strike's 6.4 damage per second that way; waiting for Hammer of Wrath the same way changed nothing).
local function Consecrate(F)
    local ab = F.char.ab
    local cons = ab.consecration
    return F:Can(cons, cons.cost + math.max(0, ManaNeeded(F)))
        and not (ab.holyStrike and F:ReadyAt("HOLY_STRIKE") < F.t + cons.gcd)
end

function M.Act(F)
    local ab = F.char.ab
    local seal = F:Buff(F.seal.key)
    if not seal then
        if F:Can(F.seal) then F:Use(F.seal) end
        return
    end
    -- a seal without a judgement in its text (rank 1 of Seal of Righteousness) cannot be judged; Judgement has no
    -- global cooldown: the next ability follows at once
    local judgeable = F.seal.judgement > 0
    if judgeable and F:Can(ab.judgement) then F:Use(ab.judgement) end
    local execute = F.t >= F.len * EXECUTE_PHASE
    if execute and F:Can(ab.hammer) then
        F:Use(ab.hammer)
        return
    end
    if F:Can(ab.holyStrike) then
        F:Use(ab.holyStrike)
        return
    end
    if seal.ends - F.t < 3 and F:Can(F.seal) then
        F:Use(F.seal)
        return
    end
    if F.holyShock and F:Can(ab.holyShock) then
        -- Divine Favor first when it is ready and the mana pays for both
        local favor = ab.divineFavor
        if favor and F:Can(favor, favor.cost + ab.holyShock.cost) then F:Use(favor) end
        F:Use(ab.holyShock)
        return
    end
    if F.consecrate and Consecrate(F) then
        F:Use(ab.consecration)
        return
    end
    -- nothing to do: look again when the next ability is ready or the seal runs low (short of mana: the mana ticks
    -- ask again)
    return F:Next(seal.ends - 3, ab.hammer and math.max(F.len * EXECUTE_PHASE, F:ReadyAt("HAMMER_OF_WRATH")),
        ab.holyStrike and F:ReadyAt("HOLY_STRIKE"), judgeable and F:ReadyAt("JUDGEMENT"),
        F.holyShock and F:ReadyAt("HOLY_SHOCK"), F.consecrate and F:ReadyAt("CONSECRATION"))
end
