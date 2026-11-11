-- Lootified - the pet in the simulator's fights: a hunter's beast or a warlock's demon, as it is out now. Its damage
-- per swing and attack speed are the game's own (the pet's character sheet), its abilities come from its spell book
-- with their descriptions, costs and cooldowns. In Classic a pet's damage does not grow with its owner's gear: it adds
-- the same to every setup; the owner's talents and cooldowns that change it count (model.PetMult, model.PetCrit,
-- model.PetSpellCrit, model.PetHaste, model.OnPetCrit, model.OnPetAttack, model.PetFocusRegen). The pet attacks from
-- the first second, from behind; a beast spends focus (24 every 4 seconds, CMaNGOS Pet::Regenerate), a demon casts
-- without running out of mana.
local _, LJ = ...

local Sim = LJ.Sim
local Character = Sim.Character
local Pet = {}
Sim.Pet = Pet

local min = math.min
local EPS = 1e-6

local PET_CRIT = 5                         -- % crit of a pet's attacks and spells (the base crit of creatures)
local FOCUS_TICK, FOCUS_PER_TICK = 4, 24
-- the global cooldown after a pet's ability; the imp's Firebolt's is shorter (SpellCooldowns StartRecoveryTime 1000)
local PET_GCD, FIREBOLT_GCD = 1.5, 1
local CRIT_MULT = { physical = 2, spell = 1.5 }
-- the schools of the pets' damage spells (the rest strike with the pet's claws and teeth)
local SPELL_SCHOOLS = { FIREBOLT = "fire", LASH_OF_PAIN = "shadow" }

-- The pet that is out: { name, level, weapon (its damage per swing with everything in it, its speed), pct (its
-- damage modifier, for its abilities), focusMax (0: a demon), spells = { [key] = Character.Spell } and list (the
-- same by key) } for the abilities of model.petSpells it has.
function Pet.Read(model)
    local lo, hi, _, _, _, _, percent = UnitDamage("pet")
    local speed = UnitAttackSpeed("pet")
    local level = UnitLevel("pet")
    local book = Character.SpellBook(Enum.SpellBookSpellBank.Pet)
    local spells, list = {}, {}
    for key, id in pairs(model.petSpells) do
        spells[key] = Character.Spell(book, id, key)
        list[#list + 1] = spells[key]
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    local focus = UnitPowerType("pet") == Enum.PowerType.Focus
    return {
        name = UnitName("pet"), level = level, hit = 0, crit = PET_CRIT, spellHit = 0,
        spellCrit = { fire = PET_CRIT, shadow = PET_CRIT }, armorIgnore = 0,
        weapon = { min = lo, max = hi, speed = speed, skill = level * 5 }, pct = percent,
        focusMax = focus and UnitPowerMax("pet", Enum.PowerType.Focus) or 0, spells = spells, list = list,
        -- an imp only casts
        melee = spells.FIREBOLT == nil,
    }
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
-- The owner's talents and cooldowns on the pet's damage (key: its ability, nil for its melee swings).
local function Mult(F, key) return F.model.PetMult and F.model.PetMult(F, key) or 1 end

-- The pet as an attacker with the owner's talents on its crit.
local function Attacker(F)
    local pet = F.char.pet
    local who = F.pet.who
    who.crit = pet.crit + (F.model.PetCrit and F.model.PetCrit(F) or 0)
    who.spellCrit.fire, who.spellCrit.shadow = who.crit, who.crit
    return who
end

-- The owner's talents on the crit of one of the pet's spells (key: the ability).
local function SpellCrit(F, key)
    return F.model.PetSpellCrit and F.model.PetSpellCrit(F, key) or 0
end

local function OnCrit(F)
    if F.model.OnPetCrit then F.model.OnPetCrit(F) end
end

-- After each attack of the pet (a swing or an ability), whatever its result: the owner's effects that come with it
-- (a warlock's Demonic Brand).
local function OnAttack(F, result)
    if F.model.OnPetAttack then F.model.OnPetAttack(F, result) end
end

local function Average(p, i)
    local lo, hi = p.plain[i], p.plain[i + 1] or p.plain[i]
    return (lo + hi) / 2
end

local function Melee(F)
    local pet, who = F.char.pet, Attacker(F)
    local w = pet.weapon
    local result = F:WhiteResult(w, false, who)
    local damage = 0
    if result ~= Sim.MISS and result ~= Sim.DODGE then
        damage = w.min + (w.max - w.min) * F:Roll()
        if result == Sim.GLANCE then
            local lo, hi = Sim.GlanceRange(F.target.defense, w.skill)
            damage = damage * (lo + (hi - lo) * F:Roll())
        elseif result == Sim.CRIT then
            damage = damage * CRIT_MULT.physical
        end
        damage = F:AfterArmor(damage, who) * Mult(F)
    end
    F:Record("PET_MELEE", damage, result)
    if result == Sim.CRIT then OnCrit(F) end
    OnAttack(F, result)
end

-- A damage ability of the pet: its description's damage ("causing 22 to 30 damage", "Deals 21 to 25 Fire damage").
local function Strike(F, spell)
    local pet, who = F.char.pet, Attacker(F)
    local key = "PET_" .. spell.key
    local school = SPELL_SCHOOLS[spell.key]
    local amount = Average(spell.p, 1)
    if school then
        local opts = { who = who, crit = SpellCrit(F, spell.key) }
        local result = F:SpellHit(key, school, amount * Mult(F, spell.key), opts)
        if result == Sim.CRIT then OnCrit(F) end
        OnAttack(F, result)
        return
    end
    local result = F:SpecialResult(pet.weapon, 0, false, who)
    local damage = 0
    if result == Sim.HIT or result == Sim.CRIT then
        damage = amount * pet.pct
        if result == Sim.CRIT then damage = damage * CRIT_MULT.physical end
        damage = F:AfterArmor(damage, who) * Mult(F, spell.key)
    end
    F:Record(key, damage, result)
    if result == Sim.CRIT then OnCrit(F) end
    OnAttack(F, result)
end

---------------------------------------------------------------------------
-- Acting: abilities with a cooldown first, the others with what is left over
---------------------------------------------------------------------------
local PetFree

local function PetThink(F)
    F.pet.thinkAt = nil
    PetFree(F)
end

local function Schedule(F, time)
    local p = F.pet
    if p.thinkAt and p.thinkAt <= time + EPS and p.thinkAt > F.t + EPS then return end
    p.thinkAt = time
    F:At(time, PetThink)
end

local function CastDone(F, spell)
    F.pet.casting = nil
    Strike(F, spell)
    PetFree(F)
end

local function Ready(F, spell) return (F.pet.cd[spell.key] or 0) <= F.t + EPS end

-- The focus a beast gets every FOCUS_TICK seconds, with the owner's talents.
local function FocusPerTick(F)
    return FOCUS_PER_TICK * (F.model.PetFocusRegen and F.model.PetFocusRegen(F) or 1)
end

local function Use(F, spell)
    local p = F.pet
    if spell.power == "focus" then p.focus = p.focus - spell.cost end
    if spell.cooldown > 0 then p.cd[spell.key] = F.t + spell.cooldown end
    p.gcd = F.t + (spell.key == "FIREBOLT" and FIREBOLT_GCD or PET_GCD)
    if spell.cast > 0 then
        p.casting = spell
        F:At(F.t + spell.cast, CastDone, spell)
    else
        Strike(F, spell)
    end
end

-- The next ability: one with a cooldown when it is ready; another one when it leaves enough focus for the first by
-- the time that is ready. Returns the time worth another look.
local function Act(F)
    local p, list = F.pet, F.char.pet.list
    local focus = F.char.pet.focusMax > 0
    local held, wake = nil, F.len
    for _, spell in ipairs(list) do
        if spell.cooldown > 0 then
            local readyAt = p.cd[spell.key] or 0
            if Ready(F, spell) and (not focus or p.focus >= spell.cost) then
                Use(F, spell)
                return
            end
            -- the focus this ability needs when it is ready
            if focus and (not held or readyAt < (p.cd[held.key] or 0)) then held = spell end
            if readyAt > F.t then wake = min(wake, readyAt) end
        end
    end
    for _, spell in ipairs(list) do
        if spell.cooldown == 0 then
            if not focus then
                Use(F, spell)
                return
            end
            local left = p.focus - spell.cost
            local need = held and held.cost or 0
            local until_ = held and (p.cd[held.key] or 0) - F.t or 0
            if left >= 0 and (left >= need or left + until_ * FocusPerTick(F) / FOCUS_TICK >= need) then
                Use(F, spell)
                return
            end
        end
    end
    return wake
end

PetFree = function(F)
    local p = F.pet
    if p.casting or F.t + EPS < p.gcd then return end
    local wake = Act(F)
    if p.casting then return end
    if F.t + EPS < p.gcd then
        Schedule(F, p.gcd)
    elseif wake and wake > F.t + EPS and wake < F.len then
        Schedule(F, wake)
    end
end

local function FocusTick(F)
    local p = F.pet
    p.focus = min(F.char.pet.focusMax, p.focus + FocusPerTick(F))
    F:At(F.t + FOCUS_TICK, FocusTick)
    PetFree(F)
end

local PetSwing
local function SetSwing(F, time)
    F.pet.swingAt = time
    F:At(time, PetSwing)
end

PetSwing = function(F)
    local p = F.pet
    if p.swingAt > F.t + EPS then return end
    Melee(F)
    SetSwing(F, F.t + F.char.pet.weapon.speed / (F.model.PetHaste and F.model.PetHaste(F) or 1))
    PetFree(F)
end

-- Sends the pet in when the fight starts (the model's Start calls it while the character has a pet).
function Pet.Start(F)
    local pet = F.char.pet
    F.pet = { focus = pet.focusMax, gcd = 0, cd = {}, swingAt = 0,
        who = { level = pet.level, hit = pet.hit, crit = pet.crit, spellHit = pet.spellHit, spellCrit = {},
            armorIgnore = 0 } }
    if pet.melee then SetSwing(F, 0) end
    if pet.focusMax > 0 then F:At(FOCUS_TICK * F:Roll(), FocusTick) end
    PetFree(F)
end
