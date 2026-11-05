-- Lootified - the damage simulator's engine: one fight of a character against a target dummy, played out event by
-- event (swings, casts, channels, cooldowns, auras, damage over time, rage, energy, combo points and mana) and
-- repeated many times. Every fight number i throws the same dice in every setup, so two setups compared with each
-- other get the same luck and the difference shows even after few fights. The class models (Sim/<Class>.lua) say
-- what the character does, Sim/Character.lua reads the character from the game, Sim/Pet.lua plays the pet,
-- Sim/Jobs.lua runs the fights a little every frame.
--
-- Combat rules: Classic's, as the CMaNGOS server reproduces them (attack table, glancing blows, armor, rage, spell
-- hit, crit and the target's resistance from its level), with the glancing blow damage of the Forever client's own
-- weapon skill panel. The target stands still, never fights back and is hit from behind (no parry, no block).
local _, LJ = ...

local Sim = { models = {} }
LJ.Sim = Sim

local floor, min, max = math.floor, math.min, math.max
local EPS = 1e-6

---------------------------------------------------------------------------
-- Dice: Park-Miller "minimal standard" generator (exact in Lua's numbers: 16807 * (2^31 - 1) < 2^53)
---------------------------------------------------------------------------
function Sim.NewDice(seed)
    local s = floor(seed) % 2147483646 + 1
    return function()
        s = (16807 * s) % 2147483647
        return (s - 1) / 2147483646
    end
end

---------------------------------------------------------------------------
-- Event queue: a binary heap in parallel arrays (no table per event); equal times keep their order
---------------------------------------------------------------------------
local function QueueNew()
    return { n = 0, seq = 0, t = {}, f = {}, a = {}, s = {} }
end

local function Before(q, i, j)
    local ti, tj = q.t[i], q.t[j]
    return ti < tj or (ti == tj and q.s[i] < q.s[j])
end

local function Swap(q, i, j)
    local t, f, a, s = q.t, q.f, q.a, q.s
    t[i], t[j] = t[j], t[i]
    f[i], f[j] = f[j], f[i]
    a[i], a[j] = a[j], a[i]
    s[i], s[j] = s[j], s[i]
end

local function QueuePush(q, time, fn, arg)
    local n = q.n + 1
    q.n, q.seq = n, q.seq + 1
    q.t[n], q.f[n], q.a[n], q.s[n] = time, fn, arg, q.seq
    while n > 1 do
        local p = floor(n / 2)
        if not Before(q, n, p) then break end
        Swap(q, n, p)
        n = p
    end
end

local function QueuePop(q)
    local n = q.n
    local time, fn, arg = q.t[1], q.f[1], q.a[1]
    Swap(q, 1, n)
    q.t[n], q.f[n], q.a[n], q.s[n] = nil, nil, nil, nil
    n = n - 1
    q.n = n
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= n and Before(q, l, m) then m = l end
        if r <= n and Before(q, r, m) then m = r end
        if m == i then break end
        Swap(q, i, m)
        i = m
    end
    return time, fn, arg
end

---------------------------------------------------------------------------
-- The target: a mob of the chosen level with the armor Classic gives a normal mob of that level (CMaNGOS
-- creature_template_classlevelstats, warrior mobs, levels 1-63)
---------------------------------------------------------------------------
Sim.MOB_ARMOR = {
    15, 16, 41, 76, 120, 174, 239, 316, 406, 512, 538, 573, 608, 642, 677, 713, 748, 782, 817, 852, 888, 922, 957,
    992, 1026, 1061, 1097, 1130, 1165, 1200, 1234, 1270, 1304, 1340, 1373, 1480, 1593, 1709, 1834, 1964, 2101, 2246,
    2397, 2557, 2725, 2780, 2835, 2888, 2944, 2999, 3052, 3108, 3163, 3216, 3271, 3327, 3380, 3435, 3489, 3791, 4091,
    4391, 4691,
}

---------------------------------------------------------------------------
-- Attack table
---------------------------------------------------------------------------
-- Results
local HIT, CRIT, GLANCE, MISS, DODGE = "hit", "crit", "glance", "miss", "dodge"
Sim.HIT, Sim.CRIT, Sim.GLANCE, Sim.MISS, Sim.DODGE = HIT, CRIT, GLANCE, MISS, DODGE

-- Chance to miss (%) with a weapon skill against the target's defense (5 per level), CMaNGOS
-- Unit::CalculateEffectiveMissChance: 0.04 per point below, 0.1 per point above, 0.6 per point beyond 10 above.
function Sim.MissChance(defense, skill, hit, dualWield)
    local diff = defense - skill
    local chance = 5 + (dualWield and 19 or 0)
    if diff > 10 then
        chance = chance + 1 + (diff - 10) * 0.6
    elseif diff > 0 then
        chance = chance + diff * 0.1
    else
        chance = chance + diff * 0.04
    end
    return max(0, chance - hit)
end

-- Chance (%) that the target dodges: 5 % plus 0.1 per point of skill below its defense (0.04 per point above).
function Sim.DodgeChance(defense, skill)
    local diff = defense - skill
    return max(0, 5 + diff * (diff > 0 and 0.1 or 0.04))
end

-- Chance (%) of a glancing blow (white melee hits of a player on a mob): 10 % plus 2 per point of the weapon skill
-- (capped at 5 x the player's level) below the target's defense.
function Sim.GlanceChance(defense, skill, level)
    return max(0, min(100, 10 + (defense - min(skill, level * 5)) * 2))
end

-- The damage range of a glancing blow, as the Forever client's weapon skill panel computes it
-- (Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua GetGlancingBlowPenalty).
function Sim.GlanceRange(defense, skill)
    local diff = defense - skill
    local low = 1.30 - 0.05 * diff
    local high = 1.20 - 0.03 * diff
    if diff > 10 then
        low, high = low + 0.1, high + 0.1
    end
    return max(0.01, min(low, 0.91)), max(0.20, min(high, 0.99))
end

-- Crit chance (%) of a weapon attack: the character's crit plus 0.2 per point of weapon skill above the target's
-- defense (minus 0.2 per point below: 1 % per level of a higher target).
function Sim.WeaponCrit(crit, defense, skill)
    return crit + (skill - defense) * 0.2
end

-- Chance (%) that a spell misses a mob: 4 % at the same level, +1 per level up to 2 levels, then +11 per level;
-- at least 1 % (CMaNGOS Unit::CalculateSpellMissChance).
function Sim.SpellMissChance(levelDiff, hit)
    local chance = 4
    if levelDiff > 2 then
        chance = chance + 2 + (levelDiff - 2) * 11
    else
        chance = chance + levelDiff
    end
    return max(1, chance - hit)
end

-- Spell damage left after the resistance a mob has from being higher level than the caster: 0.4 % per point of the
-- skill difference, 2 % per level (CMaNGOS, Holy damage too).
function Sim.LevelResist(levelDiff)
    return 1 - 0.02 * max(0, levelDiff)
end

-- Damage left after the target's armor (Classic: armor / (armor + 400 + 85 x attacker level), at most 75 %).
function Sim.ArmorFactor(armor, level)
    if armor <= 0 then return 1 end
    return 1 - min(0.75, armor / (armor + 400 + 85 * level))
end

-- Rage from dealing damage with a white hit (CMaNGOS Player::RewardRage).
function Sim.RageFromDamage(damage, level)
    local conversion = 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
    return damage / conversion * 7.5
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------
local Fight = {}
Fight.__index = Fight
Sim.Fight = Fight

-- The target of a character's fights (opts.levelOffset levels above it): { level, defense (5 per level), armor }.
function Sim.Target(char, opts)
    local level = char.level + opts.levelOffset
    return { level = level, defense = level * 5, armor = Sim.MOB_ARMOR[min(level, #Sim.MOB_ARMOR)] }
end

-- char: the character (Sim/Character.lua), model: the spec model, opts = { length (s), levelOffset }, seed: the
-- number of the fight (the same number throws the same dice).
function Sim.NewFight(char, model, opts, seed)
    local F = setmetatable({
        char = char, model = model, opts = opts,
        dice = Sim.NewDice(seed * 7919 + 17),
        -- the ticks' crits roll their own dice: a tick lands at a time that differs between two compared setups, and
        -- a die of the fight's dice taken there would shift every later roll (the paired fights' dice part)
        tickDice = Sim.NewDice(seed * 7919 + 18),
        q = QueueNew(),
        t = 0, len = opts.length,
        target = Sim.Target(char, opts),
        buffs = {}, debuffs = {},   -- [key] = { ends, stacks, value }
        cd = {},                    -- [key] = time the cooldown ends
        gcd = 0, casting = nil,     -- casting = ability (a cast or a channel)
        mana = char.mana, rage = char.rageStart or 0, energy = char.energyMax or 0, cp = 0,
        armorCut = 0,               -- armor taken off the target (Sunder Armor)
        lastSpend = -10,
        out = {},                   -- [source] = { damage, count, crits, misses }
        swingAt = {},               -- [hand] = time of the next swing
        thinkAt = nil,
    }, Fight)
    return F
end

function Fight:At(time, fn, arg)
    if time < self.len + EPS then QueuePush(self.q, time, fn, arg) end
end

function Fight:Roll() return self.dice() end

-- A die for a tick's crit (a damage over time's or a channel's).
function Fight:TickRoll() return self.tickDice() end

-- The tally of a damage source (an ability, a proc, a dot, white hits ...).
function Fight:Source(key)
    local s = self.out[key]
    if not s then
        s = { damage = 0, count = 0, crits = 0, misses = 0 }
        self.out[key] = s
    end
    return s
end

-- periodic: a tick of a damage over time (not an attack: left out of the hit and crit rates).
function Fight:Record(key, damage, result, periodic)
    local s = self:Source(key)
    if periodic then s.periodic = true end
    if result == MISS or result == DODGE then
        s.misses = s.misses + 1
        s.count = s.count + 1
        return
    end
    s.damage = s.damage + damage
    s.count = s.count + 1
    if result == CRIT then s.crits = s.crits + 1 end
end

---------------------------------------------------------------------------
-- Auras (buffs on the character, debuffs on the target): ends, stacks and a value; an expired aura is gone
---------------------------------------------------------------------------
local function AuraGet(list, key, t)
    local a = list[key]
    if a and a.ends > t + EPS then return a end
end

function Fight:Buff(key) return AuraGet(self.buffs, key, self.t) end
function Fight:Debuff(key) return AuraGet(self.debuffs, key, self.t) end

-- Puts on (or refreshes) an aura; maxStacks adds a stack up to the maximum. Returns the aura.
local function AuraApply(list, key, t, duration, value, maxStacks)
    local a = list[key]
    if a and a.ends > t + EPS then
        a.ends = t + duration
        if maxStacks then a.stacks = min(maxStacks, a.stacks + 1) end
        if value then a.value = value end
        return a
    end
    a = { ends = t + duration, stacks = 1, value = value }
    list[key] = a
    return a
end

function Fight:AddBuff(key, duration, value, maxStacks)
    return AuraApply(self.buffs, key, self.t, duration, value, maxStacks)
end

function Fight:AddDebuff(key, duration, value, maxStacks)
    return AuraApply(self.debuffs, key, self.t, duration, value, maxStacks)
end

function Fight:RemoveBuff(key) self.buffs[key] = nil end

---------------------------------------------------------------------------
-- Cooldowns and resources
---------------------------------------------------------------------------
function Fight:Ready(key) return (self.cd[key] or 0) <= self.t + EPS end
function Fight:ReadyAt(key) return self.cd[key] or 0 end
function Fight:Cooldown(key, seconds) self.cd[key] = self.t + seconds end

function Fight:SpendMana(cost)
    if cost > 0 then
        self.mana = self.mana - cost
        self.lastSpend = self.t
    end
end

function Fight:GainMana(amount)
    self.mana = min(self.char.manaMax, self.mana + amount)
end

function Fight:GainRage(amount)
    self.rage = min(self.char.rageMax, self.rage + amount)
end

function Fight:GainEnergy(amount)
    self.energy = min(self.char.energyMax, self.energy + amount)
end

-- Pays a cost in a power ("mana", "rage" or "energy").
function Fight:Spend(power, amount)
    if amount <= 0 then return end
    if power == "mana" then
        self:SpendMana(amount)
    else
        assert(power == "rage" or power == "energy", "unknown power")
        self[power] = self[power] - amount
    end
end

-- Mana every 2 seconds: the regeneration while casting within 5 seconds of spending mana, the full one after.
local function ManaTick(F)
    local perSecond = (F.t - F.lastSpend < 5) and F.char.manaRegenCasting or F.char.manaRegen
    F:GainMana(perSecond * 2)
    F:At(F.t + 2, ManaTick)
    F:Free()
end

-- Energy every 2 seconds: 20 (CMaNGOS), times the model's rate (Adrenaline Rush ...).
local function EnergyTick(F)
    F:GainEnergy(20 * (F.model.EnergyRate and F.model.EnergyRate(F) or 1))
    F:At(F.t + 2, EnergyTick)
    F:Free()
end

---------------------------------------------------------------------------
-- Weapon attacks
---------------------------------------------------------------------------
-- A weapon's damage roll with attack power (non-normalized: the weapon's speed; normalized: 3.3 two-handed, 2.4
-- one-handed, 1.7 daggers, 2.8 ranged), with the character sheet's flat bonus and damage modifier of that weapon.
-- weapon = { min, max, speed, normSpeed, bonus, pct } (Sim/Character.lua), ap: attack power.
function Fight:WeaponRoll(weapon, ap, normalized)
    local roll = weapon.min + (weapon.max - weapon.min) * self:Roll()
    local speed = normalized and weapon.normSpeed or weapon.speed
    return (roll + ap / 14 * speed + weapon.bonus) * weapon.pct
end

-- Average of the same (Deep Wounds' "average damage").
function Fight:WeaponAverage(weapon, ap)
    return ((weapon.min + weapon.max) / 2 + ap / 14 * weapon.speed + weapon.bonus) * weapon.pct
end

-- Physical damage after the target's armor (less what is cut off it: F.armorCut, Sunder Armor; minus the ignored part,
-- e.g. Weaponmaster with a mace). who: the attacker (the character, or its pet: Sim/Pet.lua).
function Fight:AfterArmor(damage, who)
    who = who or self.char
    local armor = max(0, self.target.armor - self.armorCut) * (1 - (who.armorIgnore or 0))
    return damage * Sim.ArmorFactor(armor, who.level)
end

-- One roll of a white melee swing: miss, dodge, glancing, crit or hit. weapon.hitBonus, weapon.critBonus: the hit and
-- crit of that weapon only (talents). who: the attacker { level, hit, crit, dodgeReduce (% the target dodges less) }
-- (the character, or its pet).
function Fight:WhiteResult(weapon, dualWield, who)
    local tgt, c = self.target, who or self.char
    local miss = Sim.MissChance(tgt.defense, weapon.skill, c.hit + (weapon.hitBonus or 0), dualWield)
    local dodge = max(0, Sim.DodgeChance(tgt.defense, weapon.skill) - (c.dodgeReduce or 0))
    local glance = Sim.GlanceChance(tgt.defense, weapon.skill, c.level)
    local crit = Sim.WeaponCrit(c.crit + (weapon.critBonus or 0), tgt.defense, weapon.skill)
    local r = self:Roll() * 100
    if r < miss then return MISS end
    r = r - miss
    if r < dodge then return DODGE end
    r = r - dodge
    if r < glance then return GLANCE end
    r = r - glance
    if r < crit then return CRIT end
    return HIT
end

-- Two rolls of a melee ability: miss or dodge, then crit (extraCrit: e.g. Improved Overpower). noDodge: cannot be
-- dodged (Overpower). who: the attacker (the character, or its pet).
function Fight:SpecialResult(weapon, extraCrit, noDodge, who)
    local tgt, c = self.target, who or self.char
    local miss = Sim.MissChance(tgt.defense, weapon.skill, c.hit + (weapon.hitBonus or 0), false)
    local dodge = noDodge and 0 or max(0, Sim.DodgeChance(tgt.defense, weapon.skill) - (c.dodgeReduce or 0))
    local r = self:Roll() * 100
    if r < miss then return MISS end
    if r < miss + dodge then return DODGE end
    local crit = Sim.WeaponCrit(c.crit + (weapon.critBonus or 0) + (extraCrit or 0), tgt.defense, weapon.skill)
    if self:Roll() * 100 < crit then return CRIT end
    return HIT
end

-- Two rolls of a ranged attack (Auto Shot and the shots): miss, then crit. Ranged attacks cannot be dodged.
function Fight:RangedResult(weapon, extraCrit)
    local tgt, c = self.target, self.char
    local miss = Sim.MissChance(tgt.defense, weapon.skill, c.rangedHit, false)
    if self:Roll() * 100 < miss then return MISS end
    local crit = Sim.WeaponCrit(c.rangedCrit + (extraCrit or 0), tgt.defense, weapon.skill)
    if self:Roll() * 100 < crit then return CRIT end
    return HIT
end

-- Two rolls of a spell of a school ("holy", "fire", "nature", "frost", "shadow", "arcane"): miss, then crit (the
-- spell crit of that school). extraHit, extraCrit: talents of that spell. who: the caster { level, spellHit,
-- spellCrit = { [school] = % } } (the character, or its pet).
function Fight:SpellResult(school, extraHit, extraCrit, who)
    local c = who or self.char
    local miss = Sim.SpellMissChance(self.target.level - c.level, c.spellHit + (extraHit or 0))
    if self:Roll() * 100 < miss then return MISS end
    if self:Roll() * 100 < c.spellCrit[school] + (extraCrit or 0) then return CRIT end
    return HIT
end

-- The share of spell damage the target lets through (its resistance from being higher level).
function Fight:Resist(who)
    return Sim.LevelResist(self.target.level - (who or self.char).level)
end

-- A spell's direct damage: miss or crit, the target's resistance. amount: the damage of a hit with every modifier;
-- opts = { hit, crit (extra %), critMult (1.5 without), who (the caster) }. Records the damage under key and
-- returns the result and the damage.
function Fight:SpellHit(key, school, amount, opts)
    opts = opts or {}
    local result = self:SpellResult(school, opts.hit, opts.crit, opts.who)
    local damage = 0
    if result ~= MISS then
        damage = amount * self:Resist(opts.who)
        if result == CRIT then damage = damage * (opts.critMult or 1.5) end
    end
    self:Record(key, damage, result)
    return result, damage
end

---------------------------------------------------------------------------
-- Damage over time: a debuff on the target that ticks a number of times
---------------------------------------------------------------------------
local function DotTick(F, d)
    if F.debuffs[d.key] ~= d then return end   -- put on again since: the new one ticks
    d.ticksLeft = d.ticksLeft - 1
    local damage, result = d.value * d.stacks * (d.tickMult and d.tickMult(F, d) or 1), HIT
    if d.crit and F:TickRoll() * 100 < d.crit then
        damage, result = damage * d.critMult, CRIT
    end
    F:Record(d.key, damage, result, true)
    if d.onTick then d.onTick(F, d) end
    if d.ticksLeft > 0 then
        d.nextTick = F.t + d.tick
        F:At(d.nextTick, DotTick, d)
    end
end

-- Puts a damage over time on the target: ticks times perTick (every modifier and the target's resistance in it),
-- one tick every tick seconds; it shows as a debuff (key) until its last tick. A new one replaces the old one (its
-- ticks left are lost, as in Classic). opts = { maxStacks (the same one stacks: every stack ticks perTick, the
-- duration starts again, the tick timer goes on), crit (% chance of a tick to crit), critMult, onTick(F, dot),
-- tickMult(F, dot) (a modifier of each tick while it lasts: a debuff on the target that raises the damage it takes) }.
-- Returns the debuff.
function Fight:Dot(key, perTick, ticks, tick, opts)
    opts = opts or {}
    ticks = max(1, floor(ticks + 0.5))
    local old = self.debuffs[key]
    if opts.maxStacks and old and old.ticksLeft > 0 and old.ends > self.t + EPS then
        old.stacks = min(opts.maxStacks, old.stacks + 1)
        old.value, old.ticksLeft = perTick, ticks
        old.ends = old.nextTick + (ticks - 1) * tick + 1e-5
        return old
    end
    -- ends a moment after the last tick: the debuff is up while that tick lands
    local d = { key = key, value = perTick, stacks = 1, ticksLeft = ticks, tick = tick, nextTick = self.t + tick,
        ends = self.t + ticks * tick + 1e-5, crit = opts.crit, critMult = opts.critMult or 1.5, onTick = opts.onTick,
        tickMult = opts.tickMult }
    self.debuffs[key] = d
    self:At(d.nextTick, DotTick, d)
    return d
end

---------------------------------------------------------------------------
-- Acting: the spec model's Act(F) is asked whenever the character is free (no global cooldown, no cast)
---------------------------------------------------------------------------
local Think

local function ScheduleThink(F, time)
    if F.thinkAt and F.thinkAt <= time + EPS and F.thinkAt > F.t + EPS then return end
    F.thinkAt = time
    F:At(time, Think)
end

local function CastDone(F, ability)
    F.casting = nil
    ability.fire(F, ability)
    F:Free()
end

-- One tick of a channel (ch = { ability, ticks, tick, n }); the character is free after the last.
local function ChannelTick(F, ch)
    if F.channel ~= ch then return end
    ch.n = ch.n + 1
    ch.ability.tick(F, ch.ability, ch.n)
    if ch.n < ch.ticks then
        F:At(F.t + ch.tick, ChannelTick, ch)
    else
        F.casting, F.channel = nil, nil
        F:Free()
    end
end

-- The character is free: the model picks an action, or names the next time worth another look. During the global
-- cooldown the look comes when it ends: a look set for earlier (ScheduleThink keeps the earliest) or the end of a cast
-- shorter than the global cooldown would otherwise leave the character idle until something else asks.
function Fight:Free()
    if self.casting then return end
    if self.t + EPS < self.gcd then
        ScheduleThink(self, self.gcd)
        return
    end
    local wake = self.model.Act(self)
    if self.casting then return end
    if self.t + EPS < self.gcd then
        ScheduleThink(self, self.gcd)
    elseif wake and wake > self.t + EPS then
        ScheduleThink(self, wake)
    end
end

Think = function(F)
    F.thinkAt = nil
    F:Free()
end

-- Uses an ability = { key, power ("mana" | "rage" | "energy"), cost, gcd (s), cast (s, 0 instant), cooldown (s),
-- cdKey (shared cooldown), fire(F, ability) } or a channel (channel = { ticks, tick (s) }, tick(F, ability, n) at
-- every tick): cost and cooldown first, the effect at the end of the cast. cost, cast: this use's own (a talent's
-- proc ...). The model checks costs and readiness before (Fight:Can).
function Fight:Use(ability, cost, cast)
    self:Spend(ability.power or "mana", cost or ability.cost or 0)
    if ability.cooldown and ability.cooldown > 0 then self:Cooldown(ability.cdKey or ability.key, ability.cooldown) end
    if ability.gcd and ability.gcd > 0 then self.gcd = self.t + ability.gcd end
    if ability.channel then
        local ch = { ability = ability, ticks = ability.channel.ticks, tick = ability.channel.tick, n = 0 }
        self.casting, self.channel = ability, ch
        self:At(self.t + ch.tick, ChannelTick, ch)
        return
    end
    cast = cast or ability.cast or 0
    if cast > 0 then
        self.casting = ability
        self:At(self.t + cast, CastDone, ability)
        if ability.onCastStart then ability.onCastStart(self, ability, cast) end
    else
        ability.fire(self, ability)
    end
end

-- An ability from a spell of the character (Sim/Character.lua Character.Spell): its power, cost, cast time and
-- cooldown as the game states them, a global cooldown of 1.5 s, and the model's fields (gcd, fire, channel ...). nil
-- when the character does not know the spell.
function Sim.Ability(spell, fields)
    if not spell then return nil end
    local ab = { key = spell.key, spell = spell, power = spell.power, cost = spell.cost, cast = spell.cast,
        cooldown = spell.cooldown, gcd = 1.5 }
    for k, v in pairs(fields or {}) do ab[k] = v end
    return ab
end

-- A way to play a character (model.Variants, opts.variant) names the model's spells it is played with, joined by "+"
-- ("SEAL_OF_COMMAND+CONSECRATION"): its spell keys in that order, and whether it has one.
function Sim.VariantKeys(variant)
    local keys = {}
    for key in variant:gmatch("[^+]+") do keys[#keys + 1] = key end
    return keys
end
function Sim.VariantHas(variant, key)
    return ("+" .. variant .. "+"):find("+" .. key .. "+", 1, true) ~= nil
end

-- The player's aura of a spell (C_UnitAuras.GetPlayerAuraBySpellID), nil without it: the class models' Setup asks
-- through here, so that /lf export records the answers (Sim/Export.lua).
function Sim.PlayerAura(id)
    return C_UnitAuras.GetPlayerAuraBySpellID(id)
end

-- The ability is ready (its cooldown over) and the character has its cost (or that cost).
function Fight:Can(ability, cost)
    return ability ~= nil and self:Ready(ability.cdKey or ability.key)
        and self[ability.power or "mana"] >= (cost or ability.cost or 0)
end

-- The earliest of the times given that lies ahead, or the end of the fight: when the model wants another look.
function Fight:Next(...)
    local wake = self.len
    for i = 1, select("#", ...) do
        local time = select(i, ...)
        if time and time > self.t + EPS and time < wake then wake = time end
    end
    return wake
end

---------------------------------------------------------------------------
-- Auto attacks: each hand swings on its own timer (haste: the timer of the next swing)
---------------------------------------------------------------------------
local function Swing(F, hand)
    if F.swingAt[hand] > F.t + EPS then return end   -- the timer was pushed back (e.g. by a cast)
    local weapon = F.char[hand]
    F.model.Swing(F, hand)
    F:SetSwing(hand, F.t + weapon.swing / F:Haste(hand))
    F:Free()
end

function Fight:SetSwing(hand, time)
    self.swingAt[hand] = time
    self:At(time, Swing, hand)
end

-- The attack speed multiplier of a hand (the character's own haste is in the weapon's speed already).
function Fight:Haste(hand)
    return self.model.Haste and self.model.Haste(self, hand) or 1
end

---------------------------------------------------------------------------
-- One fight
---------------------------------------------------------------------------
-- Plays one fight and returns its tally { [source] = { damage, count, crits, misses } }.
function Sim.RunFight(char, model, opts, seed)
    local F = Sim.NewFight(char, model, opts, seed)
    if model.Start then model.Start(F) end
    -- the hands that swing: the character's (a spec of the model that fights otherwise) or the model's
    for _, hand in ipairs(char.hands or model.hands) do
        if char[hand] then F:SetSwing(hand, 0) end
    end
    if char.manaMax and char.manaMax > 0 then F:At(2 * F:Roll(), ManaTick) end
    if char.energyMax and char.energyMax > 0 then F:At(2 * F:Roll(), EnergyTick) end
    F:Free()
    local q = F.q
    while q.n > 0 do
        local time, fn, arg = QueuePop(q)
        F.t = time
        fn(F, arg)
    end
    return F.out, F
end

---------------------------------------------------------------------------
-- Many fights: the mean damage per second, its error, and the damage of every source
---------------------------------------------------------------------------
-- A running tally of many fights. Add(out) after each fight; Result() at the end.
function Sim.NewTally(length)
    return { n = 0, sum = 0, sumSq = 0, length = length, sources = {} }
end

function Sim.TallyAdd(tally, out)
    local total = 0
    for key, s in pairs(out) do
        local t = tally.sources[key]
        if not t then
            t = { damage = 0, count = 0, crits = 0, misses = 0 }
            tally.sources[key] = t
        end
        t.damage = t.damage + s.damage
        t.count = t.count + s.count
        t.crits = t.crits + s.crits
        t.misses = t.misses + s.misses
        t.periodic = t.periodic or s.periodic
        total = total + s.damage
    end
    local dps = total / tally.length
    tally.last = dps
    tally.n = tally.n + 1
    tally.sum = tally.sum + dps
    tally.sumSq = tally.sumSq + dps * dps
end

-- { dps, error (standard error of the mean), fights, sources = { { key, dps, share, count, crits, misses, periodic } } }
-- with the sources by damage, biggest first.
function Sim.TallyResult(tally)
    local n = tally.n
    assert(n > 0, "no fights")
    local mean = tally.sum / n
    local var = n > 1 and max(0, (tally.sumSq - n * mean * mean) / (n - 1)) or 0
    local sources, total = {}, 0
    for _, s in pairs(tally.sources) do total = total + s.damage end
    for key, s in pairs(tally.sources) do
        sources[#sources + 1] = {
            key = key, dps = s.damage / n / tally.length, share = total > 0 and s.damage / total or 0,
            count = s.count / n, crits = s.crits / n, misses = s.misses / n, periodic = s.periodic,
        }
    end
    table.sort(sources, function(a, b)
        if a.dps ~= b.dps then return a.dps > b.dps end
        return a.key < b.key
    end)
    return { dps = mean, error = math.sqrt(var / n), fights = n, sources = sources }
end
