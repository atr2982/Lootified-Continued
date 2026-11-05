-- Lootified - simulator model of the Hunter in WoW: Forever. Hunter's Mark is on the target before the pull (and put
-- on again when it runs out, where it counts) and Rapid Fire goes off when the fight starts.
-- Marksmanship and Beast Mastery shoot: Serpent Sting kept up, Aimed Shot (Multi-Shot before it is learned; they share
-- a cooldown), Sniper Shot and Arcane Shot on cooldown; Auto Shot keeps firing while the hunter casts (Forever); Beast
-- Mastery sends the pet into Bestial Wrath on cooldown. Survival fights in melee: Raptor Strike on the next swing,
-- Strider Kick on cooldown, Mongoose Bite when Expose Prey lets it.
-- The pet that is out fights along (Sim/Pet.lua; Beast Mastery needs one); with it Focused Fire counts, without one
-- Lone Wolf. Talents: Mortal Shots, Improved Stings, Improved Serpent Sting, Barrage, Ranged Weapon Specialization,
-- Deadly Aspects (Aspect of the Hawk assumed when shooting, of the Beast in melee), Lone Wolf, Focused Fire, Careful
-- Aim, Ferocity, Frenzy, Bestial Discipline, Savage Strikes, Predator's Edge, Expose Prey, Lacerating Strikes (the
-- pet's own numbers have Unleashed Fury).
-- Numbers from the game's descriptions, costs, cast times and cooldowns from the game; rules below (beta build
-- 1.60.1.70205).
local _, LJ = ...

local Sim = LJ.Sim
local Talent = Sim.Talent

local M = { class = "HUNTER", specs = { BM = true, MM = true, SV = true }, hands = { "ranged" } }
Sim.models.HUNTER = M

M.spells = {
    ARCANE_SHOT = 3044, SERPENT_STING = 1978, AIMED_SHOT = 19434, MULTI_SHOT = 2643, SNIPER_SHOT = 1310687,
    HUNTERS_MARK = 1130, RAPID_FIRE = 3045, BESTIAL_WRATH = 19574, RAPTOR_STRIKE = 2973, MONGOOSE_BITE = 1495,
    STRIDER_KICK = 1317257, AUTO_SHOT = 75,
}
M.talents = {
    MORTAL_SHOTS = 19485, IMPROVED_STINGS = 1310661, BARRAGE = 19461, DEADLY_ASPECTS = 19552, LONE_WOLF = 415370,
    CAREFUL_AIM = 1223984, FEROCITY = 19598, FRENZY = 19621, SAVAGE_STRIKES = 19159, PREDATORS_EDGE = 1310627,
    EXPOSE_PREY = 1310532, LACERATING_STRIKES = 1310533, IMPROVED_SERPENT_STING = 19464,
    RANGED_WEAPON_SPECIALIZATION = 19507, FOCUSED_FIRE = 1223755, BESTIAL_DISCIPLINE = 19590,
    LIGHTNING_REFLEXES = 19168,
}
M.petSpells = { CLAW = 16827, BITE = 17253 }

local STING_TICK, LACERATE_TICK = 3, 3
local OFF_HAND = 0.5
local MONGOOSE_WINDOW = 5
local PET_LEVEL = 10                   -- the first pet: the quest "Taming the Beast" (from level 10) teaches Tame Beast and Call Pet (CMaNGOS)
local RANGED_WEAPONS = { [2] = true, [3] = true, [18] = true }   -- bows, guns and crossbows (CMaNGOS spell_template 19507)

-- Lightning Reflexes raises Agility by a percent, an item's too (Character.WithStats): "Increases your Agility by 10%."
-- (SpellEffect 19168: aura 137 MOD_TOTAL_STAT_PERCENTAGE, EffectMiscValue[1] the stat mask: 2 Agility).
function M.StatMods(c) return { str = 1, agi = 1 + Talent(c, "LIGHTNING_REFLEXES", "pct") / 100, int = 1 } end

function M.Setup(c)
    local ab, s = {}, c.spells
    local melee = c.spec == "SV"
    if melee then
        assert(c.mh, "no weapon")
        c.hands = { "mh", "oh" }
    else
        assert(c.ranged, "no ranged weapon")
    end
    assert(c.spec ~= "BM" or c.pet, c.level < PET_LEVEL and "no pet at this level" or "no pet")
    -- the description of an ability with at least that many plain numbers, times and percentages (nil when the
    -- character does not know it)
    local function P(key, plain, time, pct)
        local spell = s[key]
        if not spell then return nil end
        local p = spell.p
        assert(#p.plain >= plain and #p.time >= (time or 0) and #p.pct >= (pct or 0), spell.name .. ": unexpected description")
        return p
    end
    -- "... against that target by 26. ... Lasts for 2 min."; kept up where it counts: the shots' attack power, Expose
    -- Prey
    local p = P("HUNTERS_MARK", 1, 1)
    if p then ab.mark = Sim.Ability(s.HUNTERS_MARK, { rap = p.plain[1], duration = p.time[1],
        keep = not melee or c.talents.EXPOSE_PREY ~= nil, fire = M.Mark }) end
    p = P("RAPID_FIRE", 0, 1, 1)   -- "Increases ranged and melee attack speed by 40% for 15 sec."
    if p then ab.rapidFire = Sim.Ability(s.RAPID_FIRE, { haste = p.pct[1] / 100, duration = p.time[1], gcd = 0, fire = M.RapidFire }) end
    if melee then
        p = P("RAPTOR_STRIKE", 1); if p then ab.raptorStrike = Sim.Ability(s.RAPTOR_STRIKE, { extra = p.plain[1] }) end
        p = P("MONGOOSE_BITE", 1)   -- "Counterattack the enemy for melee weapon damage plus 57."
        if p then ab.mongooseBite = Sim.Ability(s.MONGOOSE_BITE, { extra = p.plain[1], fire = M.MongooseBite }) end
        p = P("STRIDER_KICK", 0, 0, 1)   -- "deals 100% melee weapon damage"
        if p then ab.striderKick = Sim.Ability(s.STRIDER_KICK, { pct = p.pct[1] / 100, fire = M.StriderKick }) end
    else
        p = P("ARCANE_SHOT", 1); if p then ab.arcaneShot = Sim.Ability(s.ARCANE_SHOT, { damage = p.plain[1], fire = M.ArcaneShot }) end
        p = P("SERPENT_STING", 1, 1)   -- "causing 415 Nature damage over 15 sec"
        if p then ab.serpentSting = Sim.Ability(s.SERPENT_STING, { total = p.plain[1], duration = p.time[1], fire = M.SerpentSting }) end
        p = P("AIMED_SHOT", 1)   -- "increases ranged damage by 55"
        if p then ab.aimedShot = Sim.Ability(s.AIMED_SHOT, { cdKey = "SHOT", extra = p.plain[1], fire = M.AimedShot }) end
        -- "Fires several missiles, hitting 3 targets."
        if not ab.aimedShot then ab.multiShot = Sim.Ability(s.MULTI_SHOT, { cdKey = "SHOT", extra = 0, fire = M.MultiShot }) end
        p = P("SNIPER_SHOT", 1)   -- "deals ranged damage plus 160"
        if p then ab.sniperShot = Sim.Ability(s.SNIPER_SHOT, { extra = p.plain[1], fire = M.SniperShot }) end
        p = P("BESTIAL_WRATH", 0, 1, 1)   -- "causing 50% additional damage for 18 sec"
        if p and c.pet then ab.bestialWrath = Sim.Ability(s.BESTIAL_WRATH, { pct = p.pct[1] / 100, duration = p.time[1],
            gcd = 0, fire = M.BestialWrath }) end
    end
    c.ab = ab
end

-- Ranged Weapon Specialization: the damage done with a bow, gun or crossbow, of every school (CMaNGOS spell_template
-- 19507): the character sheet's weapon damage has it (model.WeaponMods), Arcane and Nature damage not.
local function RangedWeaponSpec(c, w)
    return RANGED_WEAPONS[w.subclass] and 1 + Talent(c, "RANGED_WEAPON_SPECIALIZATION", "pct") / 100 or 1
end

function M.WeaponMods(c, w) return { pct = RangedWeaponSpec(c, w), crit = 0, armorIgnore = 0 } end

-- Careful Aim: a share of Intellect as attack power.
function M.WithIntellect(c, int)
    local ap = int * Talent(c, "CAREFUL_AIM", "pct") / 100
    c.ap, c.rap = c.ap + ap, c.rap + ap
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- Lone Wolf (no pet): the character sheet's weapon damage has it already; Arcane and Nature damage not.
local function LoneWolf(F, physical)
    local c = F.char
    if physical or c.petOut or not c.talents.LONE_WOLF then return 1 end
    return 1 + Talent(c, "LONE_WOLF", "pct") / 100
end

-- Focused Fire (the pet out): the character sheet's weapon damage has it already (read with the pet out), the pet's
-- numbers its share; Arcane and Nature damage not.
local function FocusedFire(F)
    local c = F.char
    return c.petOut and 1 + Talent(c, "FOCUSED_FIRE", "pct") / 100 or 1
end

-- Mortal Shots: the critical strike damage bonus of the shots its class mask names (SpellEffect 19485, effect 1,
-- against their SpellClassOptions): Auto Shot, Aimed Shot, Multi-Shot, Arcane Shot and Serpent Sting (its ticks), not
-- Sniper Shot.
local MORTAL_SHOTS = { AUTO_SHOT = true, AIMED_SHOT = true, MULTI_SHOT = true, ARCANE_SHOT = true,
    SERPENT_STING = true }
local function RangedCrit(c, key) return 2 + (MORTAL_SHOTS[key] and Talent(c, "MORTAL_SHOTS", "pct") / 100 or 0) end
-- Predator's Edge: "Increases your melee critical strike damage by 30%" is the modifier of Mortal Shots' "critical
-- strike damage bonus" (SpellEffect 1310627 and 19485, effect 1: aura 108, misc 15) on the melee abilities its class
-- mask names (Raptor Strike, Mongoose Bite, Strider Kick; Lacerating Strikes' bleed); a white swing is no ability: its
-- crit stays double.
local function MeleeCrit(c) return 2 + Talent(c, "PREDATORS_EDGE", "pct", 1) / 100 end

local function Rap(F)
    local mark = F:Debuff("HUNTERS_MARK")
    return F.char.rap + (mark and mark.value or 0)
end

-- Expose Prey: an attack on the marked target may open Mongoose Bite.
local function OnAttack(F)
    local c = F.char
    if c.talents.EXPOSE_PREY and F:Debuff("HUNTERS_MARK") and F:Roll() * 100 < Talent(c, "EXPOSE_PREY", "pct") then
        F:AddBuff("MONGOOSE_BITE", MONGOOSE_WINDOW)
    end
end

-- A shot with the ranged weapon: miss or crit, armor. bonus: flat damage, normalized: normalized weapon speed,
-- pct: talent multiplier (Barrage).
local function Shot(F, key, bonus, normalized, pct)
    local c, w = F.char, F.char.ranged
    local result = F:RangedResult(w)
    local damage = 0
    if result ~= Sim.MISS then
        damage = (F:WeaponRoll(w, Rap(F), normalized) + bonus * w.pct) * (pct or 1)
        if result == Sim.CRIT then damage = damage * RangedCrit(c, key) end
        damage = F:AfterArmor(damage)
    end
    F:Record(key, damage, result)
    return result
end

-- A melee hit (white or an ability) of the hand: miss, dodge, glancing (white), crit, armor. normalized: normalized
-- weapon speed (Mongoose Bite and Strider Kick: SpellEffect 1495 ... and 1317257, NORMALIZED_WEAPON_DMG).
local function Melee(F, key, hand, extra, pct, white, normalized)
    local c, w = F.char, F.char[hand]
    local result
    if white then
        result = F:WhiteResult(w, c.oh ~= nil)
    else
        result = F:SpecialResult(w, Talent(c, "SAVAGE_STRIKES", "pct"))
    end
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = ((pct or 1) * F:WeaponRoll(w, c.ap, normalized) + (extra or 0) * w.pct)
            * (hand == "oh" and OFF_HAND * (1 + Talent(c, "PREDATORS_EDGE", "pct", 2) / 100) or 1)
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * (white and 2 or MeleeCrit(c))
        end
        damage = F:AfterArmor(damage)
    end
    F:Record(key, damage, result)
    OnAttack(F)
    return result, damage
end

-- Deadly Aspects: an auto attack may speed up the next ones.
local function DeadlyAspects(F)
    local c = F.char
    if c.talents.DEADLY_ASPECTS and F:Roll() * 100 < Talent(c, "DEADLY_ASPECTS", "pct", 1) then
        F:AddBuff("DEADLY_ASPECTS", Talent(c, "DEADLY_ASPECTS", "time"), Talent(c, "DEADLY_ASPECTS", "pct", 2) / 100)
    end
end

function M.Swing(F, hand)
    local c = F.char
    if hand == "ranged" then
        if Shot(F, "AUTO_SHOT", 0, false) ~= Sim.MISS then DeadlyAspects(F) end
        OnAttack(F)
        return
    end
    -- Raptor Strike takes the main hand's swing when it is ready
    local raptor = c.ab.raptorStrike
    if hand == "mh" and F:Can(raptor) then
        F:Spend("mana", raptor.cost)
        F:Cooldown(raptor.key, raptor.cooldown)
        Melee(F, "RAPTOR_STRIKE", "mh", raptor.extra, 1, false)
        return
    end
    local result = Melee(F, "MELEE", hand, 0, 1, true)
    if result ~= Sim.MISS and result ~= Sim.DODGE then DeadlyAspects(F) end
end

function M.Haste(F)
    local h = 1
    local rf = F:Buff("RAPID_FIRE")
    if rf then h = h * (1 + rf.value) end
    local da = F:Buff("DEADLY_ASPECTS")
    if da then h = h * (1 + da.value) end
    return h
end

---------------------------------------------------------------------------
-- The pet: Ferocity, Frenzy, Bestial Wrath, Bestial Discipline (Unleashed Fury and Focused Fire are in the pet's own
-- numbers: its swings and the damage modifier of its abilities, Sim/Pet.lua)
---------------------------------------------------------------------------
function M.PetCrit(F) return Talent(F.char, "FEROCITY", "pct") end

function M.OnPetCrit(F)
    local c = F.char
    if c.talents.FRENZY and F:Roll() * 100 < Talent(c, "FRENZY", "pct", 1) then
        F:AddBuff("FRENZY", Talent(c, "FRENZY", "time"), Talent(c, "FRENZY", "pct", 2) / 100)
    end
end

function M.PetHaste(F)
    local frenzy = F:Buff("FRENZY")
    return frenzy and 1 + frenzy.value or 1
end

-- Bestial Wrath on all the pet does. Unleashed Fury raises the pet's own damage modifier (CMaNGOS spell_template 19616
-- changes the pet's passive 8875, a damage aura on the pet), which its swings and abilities have already; Focused Fire
-- taken alike.
function M.PetMult(F)
    local bw = F:Buff("BESTIAL_WRATH")
    return bw and 1 + bw.value or 1
end

-- Bestial Discipline: the pet's focus regeneration (CMaNGOS spell_template 19590 on the pet's passive 19589); its mana
-- part is in the game's mana regeneration while casting (GetManaRegen).
function M.PetFocusRegen(F) return 1 + Talent(F.char, "BESTIAL_DISCIPLINE", "pct", 1) / 100 end

---------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------
function M.AimedShot(F, ab) Shot(F, "AIMED_SHOT", ab.extra, true, 1 + Talent(F.char, "BARRAGE", "pct") / 100) end

function M.MultiShot(F, ab) Shot(F, "MULTI_SHOT", ab.extra, true, 1 + Talent(F.char, "BARRAGE", "pct") / 100) end

function M.SniperShot(F, ab) Shot(F, "SNIPER_SHOT", ab.extra, true) end

function M.ArcaneShot(F, ab)
    local c = F.char
    local result = F:RangedResult(c.ranged)
    local damage = 0
    if result ~= Sim.MISS then
        damage = ab.damage * RangedWeaponSpec(c, c.ranged) * LoneWolf(F, false) * FocusedFire(F) * F:Resist()
        if result == Sim.CRIT then damage = damage * RangedCrit(c, "ARCANE_SHOT") end
    end
    F:Record("ARCANE_SHOT", damage, result)
end

-- Serpent Sting: a tick can crit (SpellMisc Attributes[8] 0x200 "periodic can crit" on every rank; SpellCategories
-- DefenseType 3, ranged): the ranged crit with the weapon skill rule, as Fight:RangedResult counts it for a shot (no
-- crit chance talent's class mask names the sting), a ranged crit's size with Mortal Shots (RangedCrit).
function M.SerpentSting(F, ab)
    local c = F.char
    if F:RangedResult(c.ranged) == Sim.MISS then
        F:Record("SERPENT_STING", 0, Sim.MISS)
        return
    end
    local ticks = ab.duration / STING_TICK
    local total = ab.total * (1 + Talent(c, "IMPROVED_STINGS", "pct") / 100)
        * (1 + Talent(c, "IMPROVED_SERPENT_STING", "pct") / 100) * RangedWeaponSpec(c, c.ranged) * LoneWolf(F, false)
        * FocusedFire(F) * F:Resist()
    F:Dot("SERPENT_STING", total / ticks, ticks, STING_TICK, { critMult = RangedCrit(c, "SERPENT_STING"),
        crit = Sim.WeaponCrit(c.rangedCrit, F.target.defense, c.ranged.skill) })
end

function M.Mark(F, ab) F:AddDebuff("HUNTERS_MARK", ab.duration, ab.rap) end

function M.RapidFire(F, ab) F:AddBuff("RAPID_FIRE", ab.duration, ab.haste) end

function M.BestialWrath(F, ab) F:AddBuff("BESTIAL_WRATH", ab.duration, ab.pct) end

-- Lacerating Strikes: Mongoose Bite bleeds a share of its damage over 21 seconds. A tick can crit (1310536: SpellMisc
-- Attributes[8] 0x200 "periodic can crit"; SpellCategories DefenseType 2, melee): the main hand's crit with the weapon
-- skill rule and Savage Strikes, as Fight:SpecialResult counts it for the melee abilities (Melee), a melee ability's
-- crit size with Predator's Edge (MeleeCrit); both talents' class masks name the bleed (SpellClassOptions 1310536).
function M.MongooseBite(F, ab)
    local c, w = F.char, F.char.mh
    F:RemoveBuff("MONGOOSE_BITE")
    local _, damage = Melee(F, "MONGOOSE_BITE", "mh", ab.extra, 1, false, true)
    if damage > 0 and c.talents.LACERATING_STRIKES then
        local duration = Talent(c, "LACERATING_STRIKES", "time")
        local ticks = duration / LACERATE_TICK
        local crit = c.crit + (w.critBonus or 0) + Talent(c, "SAVAGE_STRIKES", "pct")
        F:Dot("LACERATING_STRIKES", damage * Talent(c, "LACERATING_STRIKES", "pct") / 100 / ticks, ticks, LACERATE_TICK,
            { crit = Sim.WeaponCrit(crit, F.target.defense, w.skill), critMult = MeleeCrit(c) })
    end
end

function M.StriderKick(F, ab) Melee(F, "STRIDER_KICK", "mh", 0, ab.pct, false, true) end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
function M.Start(F)
    local c = F.char
    -- Hunter's Mark is put on before the pull
    if c.ab.mark then
        F:SpendMana(c.ab.mark.cost)
        M.Mark(F, c.ab.mark)
    end
    if c.pet then Sim.Pet.Start(F) end
end

local function Try(F, ab)
    if F:Can(ab) then
        F:Use(ab)
        return true
    end
end

function M.Act(F)
    local ab = F.char.ab
    if ab.rapidFire then Try(F, ab.rapidFire) end
    if ab.bestialWrath then Try(F, ab.bestialWrath) end
    -- Hunter's Mark again when it has run out
    local mark = F:Debuff("HUNTERS_MARK")
    if ab.mark and ab.mark.keep and not mark and Try(F, ab.mark) then return end
    if ab.mongooseBite and F:Buff("MONGOOSE_BITE") and Try(F, ab.mongooseBite) then return end
    if ab.striderKick and Try(F, ab.striderKick) then return end
    local sting = F:Debuff("SERPENT_STING")
    if ab.serpentSting and not sting and F.len - F.t > ab.serpentSting.duration / 2 and Try(F, ab.serpentSting) then
        return
    end
    if ab.aimedShot and Try(F, ab.aimedShot) then return end
    if ab.multiShot and Try(F, ab.multiShot) then return end
    if ab.sniperShot and Try(F, ab.sniperShot) then return end
    if ab.arcaneShot and Try(F, ab.arcaneShot) then return end
    -- look again when a cooldown, the sting or the mark runs out (short of mana: the mana ticks ask again; Mongoose
    -- Bite opens with a swing, which asks again)
    local function At(a) return a and F:ReadyAt(a.cdKey or a.key) end
    return F:Next(At(ab.arcaneShot), At(ab.aimedShot), At(ab.multiShot), At(ab.sniperShot), At(ab.striderKick),
        At(ab.bestialWrath), At(ab.rapidFire), sting and sting.ends, mark and mark.ends)
end
