-- Lootified - simulator model of the Arms, the Fury and the Protection Warrior in WoW: Forever. The fight opens with
-- Charge's rage; Execute in the last fifth of the fight, Heroic Strike on the next swing with the rage left over.
-- Arms: Overpower when it lights up (a dodge or Bloodthrill), Mortal Strike, Rend kept up, Slam and Spearing Strike on
-- cooldown. Fury (in Berserker Stance once it has it, read in it: Charge's rage through the change of stance, Tactical
-- Mastery): Death Wish, Recklessness, Bloodthirst and Whirlwind (both weapons) on cooldown, Bloodrage and (with its
-- talent) Berserker Rage for rage. Protection (in Defensive Stance with a shield, against the target dummy as every
-- spec; no Execute in the stance, Charge only with Vanguard): Bloodrage on cooldown, Shield Slam, Sunder Armor up to its
-- stacks and kept up, Heroic Strike with the rage above Shield Slam's cost.
-- Talents: Deep Wounds, Impale, Improved Rend, Improved Overpower, Anger Management, Unbridled Wrath, Bloodthrill,
-- Weaponmaster, Improved Slam, Two-Handed Weapon Specialization, Flurry, Dual Wield Specialization, Furious Precision,
-- Improved Berserker Rage, Improved Charge, Improved Bloodrage, Vanguard (Improved Tactical Mastery: in Tactical
-- Mastery's text).
-- Numbers from the game's descriptions, costs, cast times and cooldowns from the game; rules below (beta build
-- 1.60.1.70205, dev notes of October 1: crits of white hits give double rage, Unbridled Wrath gives 1 rage with every
-- weapon, Bloodthrill procs from main-hand attacks).
local _, LJ = ...

local Sim = LJ.Sim
local Talent = Sim.Talent

local M = { class = "WARRIOR", specs = { ARMS = true, FURY = true, PROT = true }, hands = { "mh", "oh" } }
Sim.models.WARRIOR = M

local max, min = math.max, math.min

M.spells = {
    HEROIC_STRIKE = 78, REND = 772, OVERPOWER = 7384, SLAM = 1464, EXECUTE = 5308, MORTAL_STRIKE = 12294,
    CHARGE = 100, SPEARING_STRIKE = 1310222, BLOODTHIRST = 23881, WHIRLWIND = 1680, BLOODRAGE = 2687,
    BERSERKER_RAGE = 18499, DEATH_WISH = 12328, RECKLESSNESS = 1719, DEFENSIVE_STANCE = 71, SHIELD_SLAM = 23922,
    SUNDER_ARMOR = 7386, BERSERKER_STANCE = 2458, TACTICAL_MASTERY = 1310185,
}
M.talents = {
    DEEP_WOUNDS = 12834, IMPALE = 16493, IMPROVED_REND = 12286, IMPROVED_OVERPOWER = 12290, ANGER_MANAGEMENT = 12296,
    UNBRIDLED_WRATH = 12322, BLOODTHRILL = 1289682, WEAPONMASTER = 1290261, IMPROVED_SLAM = 12862, TWO_HANDED = 12163,
    FLURRY = 12319, DUAL_WIELD = 23584, FURIOUS_PRECISION = 1323963, IMPROVED_BERSERKER_RAGE = 20500,
    IMPROVED_CHARGE = 12285, IMPROVED_BLOODRAGE = 12301, VANGUARD = 1310317,
}
-- The tank spec and what only it plays (Arms and Fury list these as "only when you tank").
M.tankSpec = "PROT"
M.tankSpells = { DEFENSIVE_STANCE = true, SHIELD_SLAM = true, SUNDER_ARMOR = true, VANGUARD = true }

local OVERPOWER_WINDOW = 5
local REND_TICK, DEEP_WOUNDS_TICK = 3, 3
local EXECUTE_PHASE = 0.8              -- the target is below 20 % health for the last fifth of the fight
local OFF_HAND = 0.5                   -- off-hand weapon damage
local FLURRY_SWINGS = 3
local DEFENSIVE_STANCE = 18            -- GetShapeshiftFormID() in Defensive Stance (CMaNGOS spell_template 71: form 18)
local BERSERKER_STANCE = 19            -- in Berserker Stance (spell 2458: form 19, CMaNGOS and the game's SpellEffect)
local DEFENSIVE_STANCE_LEVEL = 10      -- warriors learn Defensive Stance at level 10 (CMaNGOS spell_template 71: SpellLevel)

local AXES = { [0] = true, [1] = true, [6] = true }     -- axes and polearms
local MACES = { [4] = true, [5] = true, [10] = true }   -- maces and staves
local SWORDS = { [7] = true, [8] = true }

function M.Setup(c)
    assert(c.mh, "no weapon")
    local ab, s = {}, c.spells
    local fury, prot = c.spec == "FURY", c.spec == "PROT"
    if prot then
        assert(c.form == DEFENSIVE_STANCE,
            c.level < DEFENSIVE_STANCE_LEVEL and "no defensive stance at this level" or "not in defensive stance")
        assert(c.shield, "no shield")
    end
    -- Fury fights in Berserker Stance once it has it: read in it, the stance's crit is in the character sheet then
    if fury and s.BERSERKER_STANCE then assert(c.form == BERSERKER_STANCE, "not in berserker stance") end
    -- the description of an ability with at least that many plain numbers, times and percentages (nil when the
    -- character does not know it)
    local function P(key, plain, time, pct)
        local spell = s[key]
        if not spell then return nil end
        local p = spell.p
        assert(#p.plain >= plain and #p.time >= (time or 0) and #p.pct >= (pct or 0), spell.name .. ": unexpected description")
        return p
    end
    local p = P("HEROIC_STRIKE", 1); if p then ab.heroicStrike = Sim.Ability(s.HEROIC_STRIKE, { extra = p.plain[1] }) end
    p = P("EXECUTE", 2)   -- "causing 450 damage and converting each extra point of rage into 12 additional damage"
    if p then ab.execute = Sim.Ability(s.EXECUTE, { base = p.plain[1], perRage = p.plain[2], fire = M.Execute }) end
    -- "generate 12 Rage"; Improved Charge: "Increases the Rage generated by your Charge ability by 3."
    p = P("CHARGE", 1); c.rageStart = p and p.plain[1] + Talent(c, "IMPROVED_CHARGE", "plain") or 0
    if fury and s.BERSERKER_STANCE then
        -- Fury fights in Berserker Stance, Charge "Requires Battle Stance": its rage goes through a change of stance,
        -- which keeps Tactical Mastery's "You retain up to 10 Rage when you change Stances." (the game's text has
        -- Improved Tactical Mastery's rage in it: "$?s12295[${$m1+$12295m1}][$m1]"); without Tactical Mastery none
        -- (what its text implies; not proven on its own)
        p = P("TACTICAL_MASTERY", 1)
        c.rageStart = min(c.rageStart, p and p.plain[1] or 0)
    end
    if fury or prot then
        p = P("BLOODRAGE", 2, 1)   -- "Generates 10 rage ..., and then generates an additional 10 rage over 10 sec."
        if p then
            -- Improved Bloodrage: "Increases all the Rage generated by your Bloodrage ability by 25%."
            local more = 1 + Talent(c, "IMPROVED_BLOODRAGE", "pct") / 100
            ab.bloodrage = Sim.Ability(s.BLOODRAGE, { now = p.plain[1] * more, later = p.plain[2] * more,
                over = p.time[1], gcd = 0, fire = M.Bloodrage })
        end
    end
    if fury then
        p = P("BLOODTHIRST", 1, 0, 1)   -- "damage equal to 45% of your Attack Power plus 30"
        if p then ab.bloodthirst = Sim.Ability(s.BLOODTHIRST, { ap = p.pct[1] / 100, extra = p.plain[1], fire = M.Bloodthirst }) end
        ab.whirlwind = Sim.Ability(s.WHIRLWIND, { fire = M.Whirlwind })
        if c.talents.IMPROVED_BERSERKER_RAGE then
            ab.berserkerRage = Sim.Ability(s.BERSERKER_RAGE, { fire = M.BerserkerRage })
        end
        p = P("DEATH_WISH", 0, 1, 1)   -- "increases your Physical damage done by 20% ... Lasts 30 sec."
        if p then ab.deathWish = Sim.Ability(s.DEATH_WISH, { pct = p.pct[1] / 100, duration = p.time[1], fire = M.DeathWish }) end
        -- Recklessness needs Berserker Stance, as Whirlwind and Berserker Rage: "gain 100% increased critical strike
        -- chance ... for the next 15 sec"
        p = P("RECKLESSNESS", 0, 1, 1)
        if p then
            ab.recklessness = Sim.Ability(s.RECKLESSNESS, { crit = p.pct[1], duration = p.time[1], fire = M.Recklessness })
        end
    elseif prot then
        -- (Defensive Stance's "damage caused by 10%" less is in the character sheet's damage modifier)
        -- no Execute in the stance ("Requires Battle Stance, Berserker Stance"), no Charge ("Requires Battle Stance") but
        -- with Vanguard: "Your Charge ability is now usable while in Defensive Stance."
        ab.execute = nil
        if not c.talents.VANGUARD then c.rageStart = 0 end
        p = P("SHIELD_SLAM", 2)   -- "causing 421 to 439 damage, increased by your Block Value"
        if p then ab.shieldSlam = Sim.Ability(s.SHIELD_SLAM, { lo = p.plain[1], hi = p.plain[2], fire = M.ShieldSlam }) end
        -- "reducing it by 90 per Sunder Armor ... Can be applied up to 5 times.  Lasts 30 sec."
        p = P("SUNDER_ARMOR", 2, 1)
        if p then
            ab.sunder = Sim.Ability(s.SUNDER_ARMOR, { armor = p.plain[1], stacks = p.plain[2], duration = p.time[1],
                fire = M.Sunder })
        end
    else
        p = P("REND", 1, 1)   -- "15 damage over 9 sec"
        if p then ab.rend = Sim.Ability(s.REND, { total = p.plain[1], duration = p.time[1], fire = M.Rend }) end
        p = P("OVERPOWER", 1)   -- "weapon damage plus 5"
        if p then ab.overpower = Sim.Ability(s.OVERPOWER, { extra = p.plain[1], fire = M.Overpower }) end
        p = P("SLAM", 1)
        if p then
            -- Improved Slam: a shorter global cooldown (the cast time and cooldown are the game's)
            ab.slam = Sim.Ability(s.SLAM, { extra = p.plain[1], gcd = 1.5 - Talent(c, "IMPROVED_SLAM", "time", 1),
                fire = M.Slam, onCastStart = M.SlamCastStart })
        end
        p = P("MORTAL_STRIKE", 1); if p then ab.mortalStrike = Sim.Ability(s.MORTAL_STRIKE, { extra = p.plain[1], fire = M.MortalStrike }) end
        p = P("SPEARING_STRIKE", 0, 0, 1)   -- "deals 40% weapon damage"
        if p then ab.spearingStrike = Sim.Ability(s.SPEARING_STRIKE, { pct = p.pct[1] / 100, fire = M.SpearingStrike }) end
    end
    c.ab = ab
end

-- Two-hand specialization; Weaponmaster: crit with axes and polearms, ignored armor with maces and staves; Furious
-- Precision: the off hand's hit.
function M.WeaponMods(c, w, hand)
    return {
        pct = w.twoHand and 1 + Talent(c, "TWO_HANDED", "pct") / 100 or 1,
        crit = AXES[w.subclass] and Talent(c, "WEAPONMASTER", "pct", 1) or 0,
        armorIgnore = MACES[w.subclass] and Talent(c, "WEAPONMASTER", "pct", 2) / 100 or 0,
        hit = hand == "oh" and Talent(c, "FURIOUS_PRECISION", "pct") or 0,
    }
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
local function AbilityCrit(c) return 2 + Talent(c, "IMPALE", "pct") / 100 end

local function Mult(F)
    local dw = F:Buff("DEATH_WISH")
    return dw and 1 + dw.value or 1
end

-- The attacker of the attack rolls: while Recklessness lasts the warrior with its crit (M.Recklessness), else nil
-- (the character).
local function Attacker(F)
    local reckless = F:Buff("RECKLESSNESS")
    return reckless and reckless.who
end

-- After any melee crit: Deep Wounds bleeds a share of the main hand's average damage over 12 seconds (put on anew);
-- its ticks cannot crit (the talent's 12162 is a dummy, the bleed of its text, 412609 "Deep Wound", a periodic dummy,
-- aura 226, and 412613 "Deep Wound" a direct damage: none has SpellMisc Attributes[8] 0x200). Flurry hastes the next
-- swings.
local function OnCrit(F)
    local c = F.char
    if c.talents.DEEP_WOUNDS then
        local duration = Talent(c, "DEEP_WOUNDS", "time")
        local ticks = duration / DEEP_WOUNDS_TICK
        local total = Talent(c, "DEEP_WOUNDS", "pct") / 100 * F:WeaponAverage(c.mh, c.ap) * Mult(F)
        F:Dot("DEEP_WOUNDS", total / ticks, ticks, DEEP_WOUNDS_TICK)
    end
    if c.talents.FLURRY then F:AddBuff("FLURRY", F.len, Talent(c, "FLURRY", "pct") / 100).stacks = FLURRY_SWINGS end
end

-- After a weapon hit: Bloodthrill (main hand, the target bleeding from Rend).
local function OnWeaponHit(F, mainHand)
    local c = F.char
    if mainHand and c.talents.BLOODTHRILL and F:Debuff("REND") and F:Roll() * 100 < Talent(c, "BLOODTHRILL", "pct") then
        F:AddBuff("OVERPOWER", Talent(c, "BLOODTHRILL", "time"))
    end
end

-- The off hand's damage share and its rage (Dual Wield Specialization).
local function OffHand(c, rage)
    return rage and 1 + Talent(c, "DUAL_WIELD", "pct", 2) / 100 or OFF_HAND * (1 + Talent(c, "DUAL_WIELD", "pct", 1) / 100)
end

-- A melee ability: miss/dodge, crit (Impale), armor. extra: flat damage on top of the weapon, pct: weapon damage share,
-- normalized: normalized weapon speed; the character sheet's damage modifier counts for both. opts.hand "oh": a strike
-- of the off-hand weapon (its own rolls with its skill, hit and crit; its damage share as its white hits': OffHand).
local function Strike(F, key, extra, pct, opts)
    local hand = opts and opts.hand or "mh"
    local c, w = F.char, F.char[hand]
    local result = F:SpecialResult(w, opts and opts.crit, opts and opts.noDodge, Attacker(F))
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = (pct or 1) * F:WeaponRoll(w, c.ap, opts and opts.normalized) + (extra or 0) * w.pct
        if hand == "oh" then damage = damage * OffHand(c) end
        if result == Sim.CRIT then damage = damage * AbilityCrit(c) end
        damage = F:AfterArmor(damage) * Mult(F)
    end
    F:Record(key, damage, result)
    if result == Sim.DODGE then F:AddBuff("OVERPOWER", OVERPOWER_WINDOW) end
    if damage > 0 then OnWeaponHit(F, hand == "mh") end
    if result == Sim.CRIT then OnCrit(F) end
    return result
end

-- A white swing (rage from its damage, double for a crit).
local function White(F, hand)
    local c, w = F.char, F.char[hand]
    local oh = hand == "oh"
    local result = F:WhiteResult(w, c.oh ~= nil, Attacker(F))
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = F:WeaponRoll(w, c.ap, false) * (oh and OffHand(c) or 1)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * 2
        end
        damage = F:AfterArmor(damage) * Mult(F)
        F:GainRage(Sim.RageFromDamage(damage, c.level) * (result == Sim.CRIT and 2 or 1) * (oh and OffHand(c, true) or 1))
    end
    F:Record("MELEE", damage, result)
    if result == Sim.DODGE then F:AddBuff("OVERPOWER", OVERPOWER_WINDOW) end
    if damage > 0 then
        -- Unbridled Wrath's rage: from white hits only (SpellAuraOptions 12322: ProcTypeMask 4, melee auto attacks)
        if c.talents.UNBRIDLED_WRATH and F:Roll() * 100 < Talent(c, "UNBRIDLED_WRATH", "pct") then F:GainRage(1) end
        OnWeaponHit(F, hand == "mh")
        -- Weaponmaster with a sword: a chance of an extra attack
        if SWORDS[w.subclass] and c.talents.WEAPONMASTER and F:Roll() * 100 < Talent(c, "WEAPONMASTER", "pct", 3) then
            White(F, hand)
        end
    end
    if result == Sim.CRIT then OnCrit(F) end
    return result
end

---------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------
-- Rend: its ticks can crit (SpellMisc Attributes[8] 0x200 on every rank), as a melee attack (SpellCategories
-- DefenseType 2): with the crit of the main hand's abilities (Sim.WeaponCrit, Weaponmaster's with an axe or polearm in
-- it) as Rend is put on, for the abilities' crit damage, Impale's in it (AbilityCrit: its class mask has Rend's bit,
-- 0x20). A tick's crit triggers neither Deep Wounds nor Flurry (their ProcTypeMask, 69972 and 87380, lacks the
-- periodic bit 0x40000).
function M.Rend(F, ab)
    local c = F.char
    local result = F:SpecialResult(c.mh)
    if result == Sim.HIT or result == Sim.CRIT then
        local ticks = ab.duration / REND_TICK
        F:Dot("REND", ab.total * (1 + Talent(c, "IMPROVED_REND", "pct") / 100) * Mult(F) / ticks, ticks, REND_TICK,
            { crit = Sim.WeaponCrit(c.crit + (c.mh.critBonus or 0), F.target.defense, c.mh.skill),
                critMult = AbilityCrit(c) })
    else
        F:Record("REND", 0, result)
        if result == Sim.DODGE then F:AddBuff("OVERPOWER", OVERPOWER_WINDOW) end
    end
end

-- Overpower, Mortal Strike, Whirlwind and Spearing Strike strike with normalized weapon damage, the others with the
-- weapon's own speed (the game's SpellEffect: NORMALIZED_WEAPON_DMG; Heroic Strike's and Slam's is
-- WEAPON_DAMAGE_NOSCHOOL).
function M.Overpower(F, ab)
    F:RemoveBuff("OVERPOWER")
    Strike(F, "OVERPOWER", ab.extra, 1, { crit = Talent(F.char, "IMPROVED_OVERPOWER", "pct"), noDodge = true,
        normalized = true })
end

function M.MortalStrike(F, ab) Strike(F, "MORTAL_STRIKE", ab.extra, 1, { normalized = true }) end

function M.SpearingStrike(F, ab) Strike(F, "SPEARING_STRIKE", 0, ab.pct, { normalized = true }) end

function M.Slam(F, ab) Strike(F, "SLAM", ab.extra) end

-- Without Improved Slam the cast holds the swing: it starts again when Slam lands.
function M.SlamCastStart(F, _, cast)
    if F.char.talents.IMPROVED_SLAM then return end
    F:SetSwing("mh", F.t + cast + F.char.mh.swing / F:Haste("mh"))
end

function M.Execute(F, ab)
    local extra = F.rage
    F.rage = 0
    Strike(F, "EXECUTE", ab.base + extra * ab.perRage, 0)
end

-- Bloodthirst: a share of attack power plus a flat amount (no weapon damage, so the weapon's modifier stays out).
function M.Bloodthirst(F, ab)
    local c = F.char
    local result = F:SpecialResult(c.mh, nil, nil, Attacker(F))
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = c.ap * ab.ap + ab.extra
        if result == Sim.CRIT then damage = damage * AbilityCrit(c) end
        damage = F:AfterArmor(damage) * Mult(F)
    end
    F:Record("BLOODTHIRST", damage, result)
    if damage > 0 then OnWeaponHit(F, true) end
    if result == Sim.CRIT then OnCrit(F) end
end

-- Whirlwind: "causing weapon damage from both melee weapons to each enemy": the main hand's normalized weapon damage
-- and, with a weapon in the off hand, the off hand's, normalized too. The text gives no share for the off hand: it
-- hits with the share of its white hits (OffHand: half, Dual Wield Specialization's more; not proven for Whirlwind).
-- Nor does it say whether the two weapons roll to hit together: each weapon's hit rolls on its own (not proven either).
function M.Whirlwind(F)
    Strike(F, "WHIRLWIND", 0, 1, { normalized = true })
    if F.char.oh then Strike(F, "WHIRLWIND", 0, 1, { normalized = true, hand = "oh" }) end
end

local function RageOverTime(F, left)
    local ab = F.char.ab.bloodrage
    F:GainRage(ab.later / ab.over)
    if left > 1 then F:At(F.t + 1, RageOverTime, left - 1) end
    F:Free()
end

function M.Bloodrage(F, ab)
    F:GainRage(ab.now)
    -- the rest in equal ticks, one a second (CMaNGOS spell_template 29131: the period of its periodic energize)
    F:At(F.t + 1, RageOverTime, ab.over)
end

function M.BerserkerRage(F) F:GainRage(Talent(F.char, "IMPROVED_BERSERKER_RAGE", "plain")) end

function M.DeathWish(F, ab) F:AddBuff("DEATH_WISH", ab.duration, ab.pct) end

-- Recklessness: while it lasts the attack rolls see the warrior with its percent added to the crit chance (CMaNGOS
-- spell_template 1719: a flat crit chance aura), as the attacker the engine's rolls read ({ level, hit, crit,
-- dodgeReduce }).
function M.Recklessness(F, ab)
    local c = F.char
    F:AddBuff("RECKLESSNESS", ab.duration).who = { level = c.level, hit = c.hit, crit = c.crit + ab.crit,
        dodgeReduce = c.dodgeReduce }
end

-- Shield Slam: a range of damage plus the shield's block value (no weapon damage: the character sheet's damage
-- modifier on it, as on the flat damage of the others).
function M.ShieldSlam(F, ab)
    Strike(F, "SHIELD_SLAM", ab.lo + (ab.hi - ab.lo) * F:Roll() + F.char.blockValue, 0)
end

-- Sunder Armor ran out (unless one since made it last longer): the target's armor is whole again.
local function SunderEnds(F)
    if not F:Debuff("SUNDER_ARMOR") then F.armorCut = 0 end
end

-- Sunder Armor: a stack more (up to its most) for its time, the target's armor lower by its number per stack while it
-- lasts (F.armorCut); no damage.
function M.Sunder(F, ab)
    local result = F:SpecialResult(F.char.mh)
    if result == Sim.CRIT then result = Sim.HIT end   -- (no damage to crit)
    if result == Sim.HIT then
        local sunder = F:AddDebuff("SUNDER_ARMOR", ab.duration, nil, ab.stacks)
        F.armorCut = sunder.stacks * ab.armor
        F:At(sunder.ends, SunderEnds)
    end
    F:Record("SUNDER_ARMOR", 0, result)
end

local function HeroicStrike(F)
    local ab = F.char.ab.heroicStrike
    F.rage = F.rage - ab.cost
    return Strike(F, "HEROIC_STRIKE", ab.extra)
end

local function ExecutePhase(F) return F.t >= F.len * EXECUTE_PHASE end

-- Rage kept for the next abilities before Heroic Strike takes a swing.
local function WantHeroicStrike(F)
    local ab = F.char.ab
    if not ab.heroicStrike or ExecutePhase(F) and ab.execute then return false end
    local reserve = 0
    for _, key in ipairs({ "mortalStrike", "slam", "bloodthirst", "whirlwind" }) do
        if ab[key] then reserve = max(reserve, ab[key].cost) end
    end
    if ab.overpower then reserve = reserve + ab.overpower.cost end
    -- Protection: Shield Slam's (a shield in hand)
    if ab.shieldSlam and F.char.shield then reserve = reserve + ab.shieldSlam.cost end
    return F.rage >= ab.heroicStrike.cost + reserve
end

function M.Swing(F, hand)
    local result
    if hand == "mh" and WantHeroicStrike(F) then result = HeroicStrike(F) else result = White(F, hand) end
    -- Flurry: every swing after the crit uses one of its swings
    local flurry = F:Buff("FLURRY")
    if flurry and result ~= Sim.CRIT then
        flurry.stacks = flurry.stacks - 1
        if flurry.stacks <= 0 then F:RemoveBuff("FLURRY") end
    end
end

function M.Haste(F)
    local flurry = F:Buff("FLURRY")
    return flurry and 1 + flurry.value or 1
end

local function AngerTick(F)
    F:GainRage(Talent(F.char, "ANGER_MANAGEMENT", "plain"))
    F:At(F.t + Talent(F.char, "ANGER_MANAGEMENT", "time"), AngerTick)
    F:Free()
end

function M.Start(F)
    local c = F.char
    if c.talents.ANGER_MANAGEMENT then F:At(Talent(c, "ANGER_MANAGEMENT", "time"), AngerTick) end
end

local function Try(F, ab, cost)
    if F:Can(ab, cost) then
        F:Use(ab, cost)
        return true
    end
end

function M.Act(F)
    local ab = F.char.ab
    -- rage cooldowns without a global cooldown first
    if ab.bloodrage and Try(F, ab.bloodrage) and F.t + 1e-6 < F.gcd then return end
    if ExecutePhase(F) and ab.execute and Try(F, ab.execute) then return end
    if ab.deathWish and Try(F, ab.deathWish) then return end
    if ab.recklessness and Try(F, ab.recklessness) then return end
    if ab.overpower and F:Buff("OVERPOWER") and Try(F, ab.overpower) then return end
    if ab.mortalStrike and Try(F, ab.mortalStrike) then return end
    if ab.bloodthirst and Try(F, ab.bloodthirst) then return end
    if ab.whirlwind and Try(F, ab.whirlwind) then return end
    local rend = F:Debuff("REND")
    if ab.rend and not rend and F.len - F.t > ab.rend.duration / 2 and Try(F, ab.rend) then return end
    if ab.slam and Try(F, ab.slam) then return end
    if ab.spearingStrike and Try(F, ab.spearingStrike) then return end
    if ab.berserkerRage and F.rage < 50 and Try(F, ab.berserkerRage) then return end
    -- Protection: Sunder Armor in its last global cooldown (before Shield Slam: else its stacks are lost), Shield Slam
    -- with a shield in hand, Sunder Armor up to its stacks
    local sunder = F:Debuff("SUNDER_ARMOR")
    local refresh = sunder and sunder.ends - ab.sunder.gcd
    if refresh and refresh <= F.t + 1e-6 and Try(F, ab.sunder) then return end
    if ab.shieldSlam and F.char.shield and Try(F, ab.shieldSlam) then return end
    if ab.sunder and (not sunder or sunder.stacks < ab.sunder.stacks) and Try(F, ab.sunder) then return end
    -- rage arrives with the swings (they ask again); cooldowns and the execute phase are looked at when they come
    local function At(a) return a and F:ReadyAt(a.key) end
    return F:Next(ab.execute and F.len * EXECUTE_PHASE, At(ab.mortalStrike), At(ab.slam), At(ab.spearingStrike),
        At(ab.bloodthirst), At(ab.whirlwind), At(ab.deathWish), At(ab.recklessness), At(ab.bloodrage),
        At(ab.berserkerRage), F:Buff("OVERPOWER") and At(ab.overpower), rend and rend.ends, At(ab.shieldSlam), refresh)
end
