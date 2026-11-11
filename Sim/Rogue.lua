-- Lootified - simulator model of the Rogue in WoW: Forever. The fight opens from Stealth (Ambush with a dagger in the
-- main hand, or Garrote: the fights play each opener the character has and keep the one that does more, M.Variants)
-- with full energy; Slice and Dice is kept up from 2 combo points on, the other finishers wait for 5. A finisher a way
-- keeps up (Expose Armor, Subtlety's Rupture: the fights play each opener with and without each) comes first: while it
-- is off the target, the combo points wait for it.
-- Assassination builds with Mutilate (daggers) or Backstab, keeps Venom up and spends with Eviscerate (Cold Blood
-- before it); Combat builds with Sinister Strike (Backstab with a dagger), Blade Flurry and Adrenaline Rush on
-- cooldown; Subtlety builds with Hemorrhage, Ghostly Strike on cooldown, Premeditation from Stealth, keeps Rupture up
-- (its first way) and spends the rest with Eviscerate. The poisons on the weapons strike (Instant, Deadly;
-- Sim/Character.lua reads them). Talents: Malice (character sheet), Ruthlessness, Relentless Strikes, Lethality, Vile
-- Poisons, Cold Blood, Improved Poisons, Mutilate, Seal Fate, Venom, Improved Eviscerate, Puncturing Wounds, Dual Wield
-- Specialization, Hack and Slash, Weapon Expertise, Aggression, Opportunity, Serrated Blades, Quietus, Improved Ambush,
-- Thousand Cuts, Initiative, Improved Expose Armor (Improved Slice and Dice: in Slice and Dice's text). Numbers from
-- the game's descriptions, costs and cooldowns from the game; rules below (beta build 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent = Sim.Talent

local M = { class = "ROGUE", specs = { ASSA = true, COMBAT = true, SUB = true }, hands = { "mh", "oh" } }
Sim.models.ROGUE = M

local min = math.min

M.spells = {
    SINISTER_STRIKE = 1752, BACKSTAB = 53, AMBUSH = 8676, EVISCERATE = 2098, SLICE_AND_DICE = 5171, RUPTURE = 1943,
    MUTILATE = 1310707, VENOM = 1310703, GHOSTLY_STRIKE = 14278, HEMORRHAGE = 16511, BLADE_FLURRY = 13877,
    ADRENALINE_RUSH = 13750, COLD_BLOOD = 14177, PREMEDITATION = 14183, GARROTE = 703, EXPOSE_ARMOR = 8647,
}
M.talents = {
    RUTHLESSNESS = 14156, RELENTLESS_STRIKES = 14179, LETHALITY = 14128,
    VILE_POISONS = 16513, IMPROVED_POISONS = 14113, SEAL_FATE = 14186, IMPROVED_EVISCERATE = 14162,
    PUNCTURING_WOUNDS = 1224716, DUAL_WIELD = 13715, HACK_AND_SLASH = 13960, WEAPON_EXPERTISE = 30919,
    AGGRESSION = 18427, OPPORTUNITY = 14057, SERRATED_BLADES = 14171, QUIETUS = 1310728, MALICE = 14138,
    IMPROVED_AMBUSH = 14079, THOUSAND_CUTS = 1310721, INITIATIVE = 13976, IMPROVED_EXPOSE_ARMOR = 14168,
}

-- The poisons by the enchantment they put on a weapon (CMaNGOS spell_template: the item spells with effect 54), and
-- their spell, whose description gives the chance and damage.
local POISONS = {
    [323] = { "INSTANT_POISON", 8679 }, [324] = { "INSTANT_POISON", 8686 }, [325] = { "INSTANT_POISON", 8688 },
    [623] = { "INSTANT_POISON", 11338 }, [624] = { "INSTANT_POISON", 11339 }, [625] = { "INSTANT_POISON", 11340 },
    [7] = { "DEADLY_POISON", 2823 }, [8] = { "DEADLY_POISON", 2824 }, [626] = { "DEADLY_POISON", 11355 },
    [627] = { "DEADLY_POISON", 11356 }, [2630] = { "DEADLY_POISON", 25351 },
}
-- The first rank of each poison (the simulator window names a poison's damage by it).
M.weaponSpells = { INSTANT_POISON = 8679, DEADLY_POISON = 2823 }
-- The damage that rides on the hits (the poisons'): no attacks of their own (the simulator window's summary).
M.procs = { INSTANT_POISON = true, DEADLY_POISON = true }

local GCD = 1.0                        -- the rogue's global cooldown
local OFF_HAND = 0.5
local MAX_CP = 5
local RUPTURE_TICK, POISON_TICK = 2, 3
local GARROTE_TICK = 3                 -- a tick every 3 seconds (CMaNGOS spell_template 703: EffectAmplitude1 3000)
local GARROTE_AP = 0.03                -- attack power per tick (CMaNGOS spell_bonus_data 703)
local DEADLY_STACKS = 5
local RELENTLESS_ENERGY = 25
local QUIETUS_PHASE = 0.65             -- the target is below 35 % health for the last 35 % of the fight
local HACK_AND_SLASH_RECOVERY = 0.2    -- its ProcCategoryRecovery (SpellAuraOptions 13960: 200 ms)
local DAGGER, FIST = 15, 13
local AXES_SWORDS = { [0] = true, [1] = true, [7] = true, [8] = true }
local MACES = { [4] = true, [5] = true }

local PerPoint = Sim.PerPoint

function M.Setup(c)
    assert(c.mh, "no weapon")
    local ab, s = {}, c.spells
    local dagger = c.mh.subclass == DAGGER
    local function A(key, fields)
        if not s[key] then return nil end
        fields.gcd = fields.gcd or GCD
        return Sim.Ability(s[key], fields)
    end
    local function Pct(key, i)
        local v = s[key].p.pct[i or 1]
        assert(v, s[key].name .. ": unexpected description")
        return v / 100
    end
    local function Plain(key, i)
        local v = s[key].p.plain[i or 1]
        assert(v, s[key].name .. ": unexpected description")
        return v
    end
    -- builders: weapon damage share, flat damage, combo points; normalized weapon damage where the game's SpellEffect
    -- has NORMALIZED_WEAPON_DMG (Sinister Strike, Backstab, Ambush, Hemorrhage, Mutilate's strikes; Ghostly Strike's is
    -- WEAPON_PERCENT_DAMAGE alone)
    if s.SINISTER_STRIKE then ab.sinisterStrike = A("SINISTER_STRIKE", { pct = 1, extra = Plain("SINISTER_STRIKE"),
        normalized = true, fire = M.Builder }) end
    if s.BACKSTAB and dagger then ab.backstab = A("BACKSTAB", { pct = Pct("BACKSTAB"), extra = Plain("BACKSTAB"),
        normalized = true, fire = M.Builder }) end
    -- (Ambush and Garrote cannot be dodged: SpellMisc Attributes[0] 0x200000 on every rank)
    if s.AMBUSH and dagger then ab.ambush = A("AMBUSH", { pct = Pct("AMBUSH"), extra = Plain("AMBUSH"), normalized = true,
        noDodge = true, fire = M.Builder }) end
    if s.GARROTE then
        -- "causing 144 damage over 18 sec, increased by your Attack Power. ... Awards 1 combo point."
        ab.garrote = A("GARROTE", { total = Plain("GARROTE", 1), duration = s.GARROTE.p.time[1],
            cp = Plain("GARROTE", 2), fire = M.Garrote })
        assert(ab.garrote.duration, "Garrote: unexpected description")
    end
    if s.GHOSTLY_STRIKE then ab.ghostlyStrike = A("GHOSTLY_STRIKE", { pct = Pct("GHOSTLY_STRIKE", dagger and 2 or 1),
        extra = 0, fire = M.Builder }) end
    if s.HEMORRHAGE then
        -- "100% weapon damage (145% if a Dagger is equipped) and causes the target to take 15% increased Rupture
        -- damage ... Lasts 15 sec."
        ab.hemorrhage = A("HEMORRHAGE", { pct = Pct("HEMORRHAGE", dagger and 2 or 1), extra = 0, normalized = true,
            rupture = Pct("HEMORRHAGE", 3), duration = s.HEMORRHAGE.p.time[1], fire = M.Builder })
        assert(ab.hemorrhage.duration, "Hemorrhage: unexpected description")
    end
    if s.MUTILATE and dagger and c.oh and c.oh.subclass == DAGGER then
        -- "both weapons for 75% weapon damage plus an additional 13 with each weapon. Damage increased by 20% against
        -- Poisoned targets. Awards 2 Combo Points." The text's flat damage is "${$1310706m1*$1310706m2/100}", and the
        -- game's $m1 of a weapon strike has its weapon percent in it already (its texts: Backstab's "plus $s1" is 150 %
        -- of the base points, Claw's 110 %): the text has the 75 % twice (the strike's 23 x 75 % = 17.25 shows as 13),
        -- once is taken off
        local pct = Pct("MUTILATE", 1)
        ab.mutilate = A("MUTILATE", { pct = pct, extra = Plain("MUTILATE", 1) / pct,
            poisoned = Pct("MUTILATE", 2), cp = Plain("MUTILATE", 2), fire = M.Mutilate })
    end
    -- finishers
    if s.EVISCERATE then
        -- "1 point  : 6-10 damage ... 5 points: 26-30 damage": each line is ${$m1+(points*$b1*$<mult>)}, $<mult> the
        -- Improved Eviscerate and Aggression the character has (SpellDescriptionVariables 1014): taken off the points'
        -- part here, M.Eviscerate multiplies the whole damage by them
        local ranges = PerPoint(s.EVISCERATE, "plain", 2)
        local mult = (1 + Talent(c, "IMPROVED_EVISCERATE", "pct") / 100) * (1 + Talent(c, "AGGRESSION", "pct") / 100)
        local step = (ranges[MAX_CP][1] - ranges[1][1]) / (MAX_CP - 1)   -- a point's part: $b1 x $<mult>
        for cp, range in ipairs(ranges) do
            local cut = cp * step * (1 - 1 / mult)
            ranges[cp] = { range[1] - cut, range[2] - cut }
        end
        ab.eviscerate = A("EVISCERATE", { ranges = ranges, fire = M.Eviscerate })
    end
    if s.SLICE_AND_DICE then ab.sliceAndDice = A("SLICE_AND_DICE", { haste = Pct("SLICE_AND_DICE"),
        times = PerPoint(s.SLICE_AND_DICE, "time"), fire = M.SliceAndDice }) end
    -- (lasts: a finisher's time at 5 points: a way keeps it up while that fits in the fight, M.Act)
    if s.RUPTURE and c.spec == "SUB" then
        local per = PerPoint(s.RUPTURE, "plain", 1)
        local times = PerPoint(s.RUPTURE, "time")
        ab.rupture = A("RUPTURE", { totals = per, times = times, lasts = times[MAX_CP][1], fire = M.Rupture })
    end
    if s.EXPOSE_ARMOR then
        -- "exposes the target for 30 sec, reducing Armor per combo point: ... 5 points: 2,250 Armor"
        ab.exposeArmor = A("EXPOSE_ARMOR", { armor = PerPoint(s.EXPOSE_ARMOR, "plain", 1),
            lasts = s.EXPOSE_ARMOR.p.time[1], fire = M.ExposeArmor })
        assert(ab.exposeArmor.lasts, "Expose Armor: unexpected description")
    end
    if s.VENOM then ab.venom = A("VENOM", { pct = Pct("VENOM", 1), chance = Pct("VENOM", 2) * 100,
        times = PerPoint(s.VENOM, "time"), fire = M.Venom }) end
    -- cooldowns
    if s.BLADE_FLURRY then ab.bladeFlurry = A("BLADE_FLURRY", { haste = Pct("BLADE_FLURRY"),
        duration = s.BLADE_FLURRY.p.time[1], fire = M.BladeFlurry }) end
    if s.ADRENALINE_RUSH then ab.adrenalineRush = A("ADRENALINE_RUSH", { rate = Pct("ADRENALINE_RUSH"),
        duration = s.ADRENALINE_RUSH.p.time[1], fire = M.AdrenalineRush }) end
    ab.coldBlood = A("COLD_BLOOD", { gcd = 0, fire = M.ColdBlood })
    if s.PREMEDITATION then ab.premeditation = A("PREMEDITATION", { gcd = 0, cp = Plain("PREMEDITATION"),
        fire = M.Premeditation }) end
    -- the builder the spec uses
    if c.spec == "ASSA" then
        ab.builder = ab.mutilate or ab.backstab or ab.sinisterStrike
    elseif c.spec == "SUB" then
        ab.builder = ab.hemorrhage or ab.backstab or ab.sinisterStrike
    else
        ab.builder = ab.backstab or ab.sinisterStrike
    end
    assert(ab.builder, "no builder")
    -- the poisons on the weapons
    c.poisons, c.weaponSpells = {}, {}
    for hand, list in pairs(c.enchants) do
        local poison
        for _, enchant in ipairs(list) do poison = poison or POISONS[enchant] end
        if poison and c[hand] then
            local d = Sim.Character.Describe(poison[2])
            local p = d.p
            assert(p.pct[1] and p.plain[1], d.name .. ": unexpected description")
            if poison[1] == "INSTANT_POISON" then
                -- "Each strike has a 20% chance of poisoning the enemy which instantly inflicts 76 to 100 Nature damage."
                c.poisons[hand] = { key = "INSTANT_POISON", chance = p.pct[1], damage = (p.plain[1] + p.plain[2]) / 2 }
            else
                -- "Each strike has a 30% chance of poisoning the enemy for 36 Nature damage over 12 sec."
                local duration = p.time[#p.time]
                c.poisons[hand] = { key = "DEADLY_POISON", chance = p.pct[1], total = p.plain[1], duration = duration }
            end
            c.weaponSpells[poison[1]] = poison[2]
        end
    end
    c.dodgeReduce = Talent(c, "WEAPON_EXPERTISE", "pct")
    c.ab = ab
end

-- Hack and Slash by the weapon (axes and swords: extra attacks; daggers and fist weapons: crit; maces: armor), Serrated
-- Blades: armor.
function M.WeaponMods(c, w)
    local hs = c.talents.HACK_AND_SLASH
    return {
        pct = 1,
        crit = hs and (w.subclass == DAGGER or w.subclass == FIST) and Talent(c, "HACK_AND_SLASH", "pct", 2) or 0,
        armorIgnore = (hs and MACES[w.subclass] and Talent(c, "HACK_AND_SLASH", "pct", 3) / 100 or 0)
            + Talent(c, "SERRATED_BLADES", "pct", 1) / 100,
    }
end

-- The ways the fights play the character (Sim.Jobs.Fights fights each way and keeps the one that does more, as a player
-- would): each opener from Stealth it has ("AMBUSH", "GARROTE"), each with and without each finisher it can keep up
-- first: Subtlety's Rupture (with it first: its rotation keeps it up), Expose Armor ("AMBUSH+RUPTURE", "AMBUSH",
-- "AMBUSH+RUPTURE+EXPOSE_ARMOR", "AMBUSH+EXPOSE_ARMOR", "GARROTE+RUPTURE" ...). Neither is sure to do more than the
-- Slice and Dice and Eviscerate its combo points go to otherwise (Slice and Dice's worth grows with the white hits,
-- Rupture's with its rank and attack power, Expose Armor's with the physical damage it lets through). None for a
-- character with nothing to choose (one way); without an opener the way without either has no name ("").
local OPENERS = { AMBUSH = "ambush", GARROTE = "garrote" }
function M.Variants(c)
    local ab = c.ab
    local openers = {}
    for _, key in ipairs({ "AMBUSH", "GARROTE" }) do
        if ab[OPENERS[key]] then openers[#openers + 1] = key end
    end
    if not openers[1] then openers[1] = "" end
    local kept = ab.rupture and { "+RUPTURE", "" } or { "" }
    if ab.exposeArmor then
        for i = 1, #kept do kept[#kept + 1] = kept[i] .. "+EXPOSE_ARMOR" end
    end
    local list = {}
    for _, opener in ipairs(openers) do
        for _, finishers in ipairs(kept) do list[#list + 1] = ((opener .. finishers):gsub("^%+", "")) end
    end
    return list[2] and list or (list[1] ~= "" and list or nil)
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
local function AddCp(F, n) F.cp = min(MAX_CP, F.cp + n) end

-- A poison strikes from a weapon hit (Improved Poisons, Venom: the chance; Vile Poisons, Venom: the damage). Poisons
-- roll a spell's hit; they crit with the rogue's spell crit and Malice, Instant Poison's hit and Deadly Poison's ticks
-- alike: the periodic damage of Deadly Poison's damage spells (its texts' "$2818o1 Nature damage over $2818d": 2818,
-- 2819, 11353, 11354, 25349) can crit (SpellMisc Attributes[8] 0x200), as a spell (SpellCategories DefenseType 1), for
-- one and a half times the damage (no crit damage talent reaches it: Lethality's class mask lacks its bit, 0x10000).
local function Poison(F, hand)
    local c = F.char
    local poison = c.poisons[hand]
    if not poison then return end
    local venom = F:Buff("VENOM")
    local chance = poison.chance + Talent(c, "IMPROVED_POISONS", "pct") + (venom and venom.chance or 0)
    if F:Roll() * 100 >= chance then return end
    local mult = (1 + Talent(c, "VILE_POISONS", "pct") / 100) * (venom and 1 + venom.value or 1)
    if poison.key == "INSTANT_POISON" then
        F:SpellHit("INSTANT_POISON", "nature", poison.damage * mult, { crit = Talent(c, "MALICE", "pct") })
        return
    end
    if F:SpellResult("nature") == Sim.MISS then
        F:Record("DEADLY_POISON", 0, Sim.MISS)
        return
    end
    local ticks = poison.duration / POISON_TICK
    F:Dot("DEADLY_POISON", poison.total / ticks * mult * F:Resist(), ticks, POISON_TICK, { maxStacks = DEADLY_STACKS,
        crit = c.spellCrit.nature + Talent(c, "MALICE", "pct"), critMult = 1.5 })
end

local function OffHand(c) return OFF_HAND * (1 + Talent(c, "DUAL_WIELD", "pct") / 100) end

-- Hack and Slash with an axe or a sword in the hand that hit: a chance of an extra attack of that hand after a white
-- hit or an ability's (SpellAuraOptions 13960: ProcTypeMask 20, melee auto attacks and melee abilities), at most one
-- in its ProcCategoryRecovery (the extra attack it gives does not give another).
local White
local function HackAndSlash(F, hand)
    local c = F.char
    if not (c.talents.HACK_AND_SLASH and AXES_SWORDS[c[hand].subclass]) then return end
    if F.hackAndSlashAt and F.t + 1e-6 < F.hackAndSlashAt + HACK_AND_SLASH_RECOVERY then return end
    if F:Roll() * 100 < Talent(c, "HACK_AND_SLASH", "pct", 1) then
        F.hackAndSlashAt = F.t
        White(F, hand)
    end
end

-- A melee ability of a hand: miss or dodge (none with opts.noDodge), crit (opts.crit), armor. pct: weapon damage share,
-- extra: flat damage (the weapon's modifier counts for both), mult: talents. Returns the result and the damage.
local function Strike(F, key, hand, pct, extra, mult, opts)
    local c, w = F.char, F.char[hand]
    local result = F:SpecialResult(w, opts.crit, opts.noDodge)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = (pct * F:WeaponRoll(w, c.ap, opts.normalized) + extra * w.pct) * mult * (hand == "oh" and OffHand(c) or 1)
        if result == Sim.CRIT then damage = damage * (opts.critMult or 2) end
        damage = F:AfterArmor(damage)
        Poison(F, hand)
    end
    F:Record(key, damage, result)
    if damage > 0 then HackAndSlash(F, hand) end
    return result, damage
end

White = function(F, hand)
    local c, w = F.char, F.char[hand]
    local result = F:WhiteResult(w, c.oh ~= nil)
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = F:WeaponRoll(w, c.ap, false) * (hand == "oh" and OffHand(c) or 1)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * 2
        end
        damage = F:AfterArmor(damage)
        Poison(F, hand)
    end
    F:Record("MELEE", damage, result)
    if damage > 0 then HackAndSlash(F, hand) end
end

function M.Swing(F, hand) White(F, hand) end

function M.Haste(F)
    local h = 1
    local snd = F:Buff("SLICE_AND_DICE")
    if snd then h = h * (1 + snd.value) end
    local bf = F:Buff("BLADE_FLURRY")
    if bf then h = h * (1 + bf.value) end
    return h
end

function M.EnergyRate(F)
    local ar = F:Buff("ADRENALINE_RUSH")
    return ar and 1 + ar.value or 1
end

---------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------
-- The talents of a builder: its crit (Cold Blood, Puncturing Wounds, Improved Ambush), its crit damage (Lethality), its
-- damage (Aggression, Opportunity, Quietus).
local CRIT_BONUS = { SINISTER_STRIKE = true, BACKSTAB = true, MUTILATE = true, GHOSTLY_STRIKE = true, HEMORRHAGE = true }
local AGGRESSION = { SINISTER_STRIKE = true, BACKSTAB = true, EVISCERATE = true }
local OPPORTUNITY = { BACKSTAB = true, AMBUSH = true, MUTILATE = true, GARROTE = true }
local QUIETUS = { SINISTER_STRIKE = true, GHOSTLY_STRIKE = true, HEMORRHAGE = true }
local COLD_BLOOD = { SINISTER_STRIKE = true, BACKSTAB = true, AMBUSH = true, EVISCERATE = true, MUTILATE = true }

local function Opts(F, key)
    local c = F.char
    local crit = 0
    if COLD_BLOOD[key] and F:Buff("COLD_BLOOD") then
        crit = 100
        F:RemoveBuff("COLD_BLOOD")
    end
    if key == "BACKSTAB" then crit = crit + Talent(c, "PUNCTURING_WOUNDS", "pct", 1) end
    if key == "MUTILATE" then crit = crit + Talent(c, "PUNCTURING_WOUNDS", "pct", 2) end
    if key == "AMBUSH" then crit = crit + Talent(c, "IMPROVED_AMBUSH", "pct") end
    local critMult = 2 + (CRIT_BONUS[key] and Talent(c, "LETHALITY", "pct") / 100 or 0)
    return { crit = crit, critMult = critMult }
end

local function Mult(F, key)
    local c = F.char
    local m = 1
    if AGGRESSION[key] then m = m * (1 + Talent(c, "AGGRESSION", "pct") / 100) end
    if OPPORTUNITY[key] then m = m * (1 + Talent(c, "OPPORTUNITY", "pct") / 100) end
    if QUIETUS[key] and F.t >= F.len * QUIETUS_PHASE then m = m * (1 + Talent(c, "QUIETUS", "pct") / 100) end
    return m
end

-- Seal Fate: a builder's crit adds another combo point.
local function OnBuilderCrit(F)
    local c = F.char
    if c.talents.SEAL_FATE and F:Roll() * 100 < Talent(c, "SEAL_FATE", "pct") then AddCp(F, 1) end
end

-- Initiative: "a 33% chance to add an additional combo point to your target when using your Ambush, Garrote, or Cheap
-- Shot ability": with the point of an Ambush or a Garrote that lands (CMaNGOS spell_template 13976: aura 109 casts
-- 13977, a combo point, on the target the opener hits); Cheap Shot is not played.
local function Initiative(F)
    local c = F.char
    if c.talents.INITIATIVE and F:Roll() * 100 < Talent(c, "INITIATIVE", "pct") then AddCp(F, 1) end
end

function M.Builder(F, ab)
    local opts = Opts(F, ab.key)
    opts.normalized, opts.noDodge = ab.normalized, ab.noDodge
    local result = Strike(F, ab.key, "mh", ab.pct, ab.extra, Mult(F, ab.key), opts)
    if result == Sim.HIT or result == Sim.CRIT then
        AddCp(F, 1)
        if ab.key == "AMBUSH" then Initiative(F) end
        if ab.key == "BACKSTAB" and F:Roll() * 100 < Talent(F.char, "PUNCTURING_WOUNDS", "pct", 3) then AddCp(F, 1) end
        if ab.rupture then F:AddDebuff("HEMORRHAGE", ab.duration, ab.rupture) end
        if result == Sim.CRIT then OnBuilderCrit(F) end
    end
end

-- Mutilate: both weapons at once (one roll to land, a crit roll each), normalized weapon damage (its strikes'
-- SpellEffect: NORMALIZED_WEAPON_DMG), more against a poisoned target.
function M.Mutilate(F, ab)
    local c = F.char
    local opts = Opts(F, "MUTILATE")
    local mult = Mult(F, "MUTILATE") * (F:Debuff("DEADLY_POISON") and 1 + ab.poisoned or 1)
    local result = F:SpecialResult(c.mh)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("MUTILATE", 0, result)
        return
    end
    local crit = false
    for _, hand in ipairs({ "mh", "oh" }) do
        local w = c[hand]
        local damage = (ab.pct * F:WeaponRoll(w, c.ap, true) + ab.extra * w.pct) * mult
        local r = Sim.HIT
        if F:Roll() * 100 < Sim.WeaponCrit(c.crit + (w.critBonus or 0) + opts.crit, F.target.defense, w.skill) then
            damage, r, crit = damage * opts.critMult, Sim.CRIT, true
        end
        F:Record("MUTILATE", F:AfterArmor(damage), r)
        Poison(F, hand)
    end
    AddCp(F, ab.cp)
    if crit then OnBuilderCrit(F) end
end

-- The ticks of the bleeds, Garrote and Rupture: their periodic damage can crit (SpellMisc Attributes[8] 0x200 on every
-- rank), as melee attacks (SpellCategories DefenseType 2): with the crit of the main hand's abilities (Sim.WeaponCrit,
-- Hack and Slash's with a dagger or fist weapon in it) as the bleed is put on, for double damage (no crit damage
-- talent reaches them: Lethality's class mask lacks their bits, 0x100 and 0x100000). A tick's crit adds no combo
-- point (Seal Fate's ProcTypeMask, 87376, lacks the periodic bit 0x40000); every tick of Rupture is one for Thousand
-- Cuts (262144: that bit).
local function BleedCrit(F)
    local c = F.char
    return { crit = Sim.WeaponCrit(c.crit + (c.mh.critBonus or 0), F.target.defense, c.mh.skill), critMult = 2 }
end

-- Garrote: the damage of its description over its time, one tick every 3 seconds, plus attack power per tick;
-- Opportunity adds to it; a bleed ignores armor; its ticks crit (BleedCrit). It cannot be dodged (M.Setup).
function M.Garrote(F, ab)
    local c = F.char
    local result = F:SpecialResult(c.mh, nil, true)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("GARROTE", 0, result)
        return
    end
    local ticks = ab.duration / GARROTE_TICK
    F:Dot("GARROTE", (ab.total / ticks + c.ap * GARROTE_AP) * Mult(F, "GARROTE"), ticks, GARROTE_TICK, BleedCrit(F))
    AddCp(F, ab.cp)
    Initiative(F)
end

-- A finisher landed: Relentless Strikes and Ruthlessness, the combo points used.
local function Finished(F, cp)
    local c = F.char
    F.cp = 0
    if c.talents.RELENTLESS_STRIKES and F:Roll() * 100 < Talent(c, "RELENTLESS_STRIKES", "pct") * cp then
        F:GainEnergy(RELENTLESS_ENERGY)
    end
    if c.talents.RUTHLESSNESS and F:Roll() * 100 < Talent(c, "RUTHLESSNESS", "pct") then AddCp(F, 1) end
end

-- Eviscerate: the range of its combo points plus 3 % of attack power per point (CMaNGOS Spell::EffectSchoolDMG); a
-- melee ability (Hack and Slash).
function M.Eviscerate(F, ab)
    local c = F.char
    local cp = F.cp
    local range = ab.ranges[cp]
    local opts = Opts(F, "EVISCERATE")
    local result = F:SpecialResult(c.mh, opts.crit)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = (range[1] + (range[2] - range[1]) * F:Roll() + c.ap * 0.03 * cp)
            * (1 + Talent(c, "IMPROVED_EVISCERATE", "pct") / 100) * Mult(F, "EVISCERATE")
        if result == Sim.CRIT then damage = damage * opts.critMult end
        damage = F:AfterArmor(damage)
        Poison(F, "mh")
        Finished(F, cp)
    end
    F:Record("EVISCERATE", damage, result)
    if damage > 0 then HackAndSlash(F, "mh") end
end

-- Slice and Dice: the time of its combo points' line (the game's text has Improved Slice and Dice in it: "${9*$<mult>}
-- seconds", SpellDescriptionVariables 960).
function M.SliceAndDice(F, ab)
    local cp = F.cp
    F:AddBuff("SLICE_AND_DICE", ab.times[cp][1], ab.haste)
    Finished(F, cp)
end

function M.Venom(F, ab)
    local cp = F.cp
    F:AddBuff("VENOM", ab.times[cp][1], ab.pct).chance = ab.chance
    Finished(F, cp)
end

-- Thousand Cuts: every tick of Rupture adds a stack (up to its most) that takes Energy off the next Hemorrhage or
-- Backstab.
local function ThousandCuts(F)
    local c = F.char
    if c.talents.THOUSAND_CUTS then
        F:AddBuff("THOUSAND_CUTS", Talent(c, "THOUSAND_CUTS", "time"), Talent(c, "THOUSAND_CUTS", "plain", 1),
            Talent(c, "THOUSAND_CUTS", "plain", 2))
    end
end

-- Rupture: the damage of its combo points over their time, one tick every 2 seconds, plus attack power per tick
-- (CMaNGOS: 1 % per point, at most 3 %); Serrated Blades and Hemorrhage add to it; a bleed ignores armor; its ticks
-- crit (BleedCrit).
function M.Rupture(F, ab)
    local c = F.char
    local cp = F.cp
    local result = F:SpecialResult(c.mh)
    if result ~= Sim.HIT and result ~= Sim.CRIT then
        F:Record("RUPTURE", 0, result)
        return
    end
    local ticks = ab.times[cp][1] / RUPTURE_TICK
    local hemo = F:Debuff("HEMORRHAGE")
    local perTick = (ab.totals[cp][1] / ticks + c.ap * min(cp, 3) / 100)
        * (1 + Talent(c, "SERRATED_BLADES", "pct", 2) / 100) * (hemo and 1 + hemo.value or 1)
    local opts = BleedCrit(F)
    opts.onTick = ThousandCuts
    F:Dot("RUPTURE", perTick, ticks, RUPTURE_TICK, opts)
    Finished(F, cp)
end

-- Expose Armor ran out (unless one since made it last longer): the target's armor is whole again.
local function ExposeEnds(F)
    if not F:Debuff("EXPOSE_ARMOR") then F.armorCut = 0 end
end

-- Expose Armor: for its time ("exposes the target for 30 sec") the target's armor is lower by its combo points' line
-- ("5 points: 2,250 Armor"), through the fight's armorCut as Sunder Armor's (Sim/Warrior.lua); no damage. It rolls as
-- a melee attack (CMaNGOS spell_template 8647: DmgClass 2; no damage to crit); one that misses keeps the points, as
-- Rupture and Eviscerate. Improved Expose Armor: "refunds 2 Combo Points when cast with 5 Combo Points" (its lower
-- Energy cost is in the game's cost).
function M.ExposeArmor(F, ab)
    local c = F.char
    local cp = F.cp
    local result = F:SpecialResult(c.mh)
    if result == Sim.CRIT then result = Sim.HIT end
    F:Record("EXPOSE_ARMOR", 0, result)
    if result ~= Sim.HIT then return end
    F.armorCut = ab.armor[cp][1]
    F:At(F:AddDebuff("EXPOSE_ARMOR", ab.lasts).ends, ExposeEnds)
    Finished(F, cp)
    if cp == MAX_CP then AddCp(F, Talent(c, "IMPROVED_EXPOSE_ARMOR", "plain", 2)) end
end

function M.BladeFlurry(F, ab) F:AddBuff("BLADE_FLURRY", ab.duration, ab.haste) end

function M.AdrenalineRush(F, ab) F:AddBuff("ADRENALINE_RUSH", ab.duration, ab.rate) end

function M.ColdBlood(F) F:AddBuff("COLD_BLOOD", F.len) end

function M.Premeditation(F, ab) AddCp(F, ab.cp) end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
function M.Start(F)
    local ab = F.char.ab
    -- from Stealth: Premeditation, then the way's opener (Ambush or Garrote; none without a way)
    local opener = F.opts.variant and ab[OPENERS[Sim.VariantKeys(F.opts.variant)[1]]]
    if ab.premeditation and F.char.spec == "SUB" then F:Use(ab.premeditation) end
    if opener and F:Can(opener) then F:Use(opener) end
end

-- The Energy an ability costs: Thousand Cuts' stacks take some off a Hemorrhage or Backstab.
local CUTS = { HEMORRHAGE = true, BACKSTAB = true }
local function Cost(F, ab)
    local cuts = CUTS[ab.key] and F:Buff("THOUSAND_CUTS")
    if not cuts then return ab.cost end
    return ab.cost - cuts.value * cuts.stacks
end

local function Try(F, ab)
    local cost = Cost(F, ab)
    if F:Can(ab, cost) then
        -- the next Hemorrhage or Backstab uses Thousand Cuts up
        if CUTS[ab.key] then F:RemoveBuff("THOUSAND_CUTS") end
        F:Use(ab, cost)
        return true
    end
end

-- The finishers the way keeps up (M.Variants), in the order they take the combo points when both are off the target:
-- Expose Armor (its armor counts for every hit after it), then Rupture; that order is not proven. None without a way.
local function Kept(F)
    if not F.kept then
        local variant, ab = F.opts.variant, F.char.ab
        F.kept = {}
        if variant and Sim.VariantHas(variant, "EXPOSE_ARMOR") then F.kept[#F.kept + 1] = ab.exposeArmor end
        if variant and Sim.VariantHas(variant, "RUPTURE") then F.kept[#F.kept + 1] = ab.rupture end
    end
    return F.kept
end

function M.Act(F)
    local c = F.char
    local ab = c.ab
    local left = F.len - F.t
    if ab.adrenalineRush then Try(F, ab.adrenalineRush) end
    if F.t + 1e-6 < F.gcd then return end
    if ab.bladeFlurry and Try(F, ab.bladeFlurry) then return end
    local snd = F:Buff("SLICE_AND_DICE")
    -- a finisher the way keeps up that is off the target while its time at 5 points still fits in the fight takes the
    -- combo points at 5; Slice and Dice, Venom and Eviscerate only take them while none waits (else Slice and Dice,
    -- from 2 points, takes them before the fifth whenever it runs out first, and Rupture is never kept up)
    local due
    for _, kept in ipairs(Kept(F)) do
        if not F:Debuff(kept.key) and left > kept.lasts then
            due = kept
            break
        end
    end
    if due then
        if F.cp == MAX_CP and Try(F, due) then return end
    else
        if ab.sliceAndDice and not snd and F.cp >= 2 and left > 6 and Try(F, ab.sliceAndDice) then return end
        if ab.venom and not F:Buff("VENOM") and F.cp >= 3 and left > 6 and Try(F, ab.venom) then return end
        -- spend at 5 points (or what there is when the fight ends)
        if ab.eviscerate and (F.cp == MAX_CP or F.cp > 0 and left < 3) then
            if ab.coldBlood and F:Can(ab.coldBlood) then F:Use(ab.coldBlood) end
            if Try(F, ab.eviscerate) then return end
        end
    end
    if ab.ghostlyStrike and F.cp < MAX_CP and Try(F, ab.ghostlyStrike) then return end
    if F.cp < MAX_CP and Try(F, ab.builder) then return end
    -- energy comes with its ticks (they ask again)
    local function At(a) return a and F:ReadyAt(a.key) end
    local rupture, exposed = F:Debuff("RUPTURE"), F:Debuff("EXPOSE_ARMOR")
    return F:Next(At(ab.ghostlyStrike), At(ab.bladeFlurry), At(ab.adrenalineRush), snd and snd.ends,
        rupture and rupture.ends, exposed and exposed.ends)
end
