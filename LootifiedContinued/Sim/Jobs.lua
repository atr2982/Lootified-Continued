-- Lootified - runs the simulator without freezing the game: a job's fights go on a few milliseconds every frame (an
-- OnUpdate that exists only while a job runs; in combat it waits), the result arrives in a callback. The jobs: the
-- character's own damage with what one more point of each stat is worth, the comparison of items for one equipment
-- slot or all of them (also in two passes: every item briefly, the best ones exactly), and whole sets. Every job's
-- start fires SIM_JOB_STARTED, its end (done, failed or cancelled) SIM_JOB_ENDED (UI/SimProgress.lua shows them).
local _, LJ = ...

local Sim = LJ.Sim
local Character = Sim.Character
local Jobs = {}
Sim.Jobs = Jobs

-- Milliseconds of work per frame by the sim speed the player picked (LJ.db.sim.speed, UI/SimSpeed.lua asks at the
-- first press): more is done sooner and leaves less of every frame to the game.
Jobs.BUDGET = { smooth = 5, fast = 10, turbo = 20 }
Jobs.FIGHTS = 300                    -- fights per setup

local frame, current

local function Now() return debugprofilestop() end   -- milliseconds

-- Cancels the running job: its onDone is not called, its onCancel is.
function Jobs.Cancel()
    local job = current
    current = nil
    if frame then frame:SetScript("OnUpdate", nil) end
    if not job then return end
    if job.onCancel then job.onCancel() end
    LJ:Fire("SIM_JOB_ENDED")
end

-- The running job's share done (0-1), nil when none runs.
function Jobs.Progress()
    return current and current.done / current.total
end

-- The job ended by itself: no more frames for it.
local function Ended()
    current = nil
    frame:SetScript("OnUpdate", nil)
end

local function Resume(job)
    job.sliceStart = Now()
    local ok, result = coroutine.resume(job.co, job)
    if job ~= current then return end   -- cancelled while it ran
    if not ok then
        Ended()
        LJ:Debug("sim failed: %s", tostring(result))
        job.onDone(nil, result)
        LJ:Fire("SIM_JOB_ENDED")
    elseif coroutine.status(job.co) == "dead" then
        Ended()
        job.onDone(result)
        LJ:Fire("SIM_JOB_ENDED")
    elseif job.onProgress then
        job.onProgress(job.done / job.total)
    end
end

-- Starts a job (a running one is cancelled): work(job) runs in a coroutine, sets job.total (fights) and calls
-- job:Fight() after every fight. onProgress(0-1) after every frame's share, onDone(result) or onDone(nil, error);
-- onCancel() when it is cancelled. Its share of every frame: the sim speed picked when it starts. quiet: the job shows
-- its progress itself (a few seconds; UI/SimProgress.lua leaves it out). Returns the job.
function Jobs.Start(work, onProgress, onDone, onCancel, quiet)
    Jobs.Cancel()
    local budget = Jobs.BUDGET[LJ.db.sim.speed]
    assert(budget, "no sim speed picked")
    local job = { done = 0, total = 1, budget = budget, onProgress = onProgress, onDone = onDone, onCancel = onCancel,
        quiet = quiet }
    function job.Fight(j)
        j.done = j.done + 1
        if Now() - j.sliceStart > j.budget then coroutine.yield() end
    end
    job.co = coroutine.create(work)
    current = job
    frame = frame or CreateFrame("Frame")
    -- no fights in combat: the frames belong to the fight
    frame:SetScript("OnUpdate", function()
        if not InCombatLockdown() then Resume(current) end
    end)
    LJ:Fire("SIM_JOB_STARTED", job)
    return job
end

-- Runs the job to its end at once (tests, and the debug command).
function Jobs.Finish()
    while current do Resume(current) end
end

---------------------------------------------------------------------------
-- Fights
---------------------------------------------------------------------------
-- n fights of a character played one way (opts.variant): the tally's result plus the damage per second of every
-- fight (list) and the mana left at the end (share of the maximum, averaged).
local function FightsOneWay(job, char, model, opts, n)
    local tally = Sim.NewTally(opts.length)
    local list, manaLeft = {}, 0
    for i = 1, n do
        local out, F = Sim.RunFight(char, model, opts, i)
        Sim.TallyAdd(tally, out)
        list[i] = tally.last
        if char.manaMax > 0 then manaLeft = manaLeft + math.max(0, F.mana) / char.manaMax end
        job:Fight()
    end
    local result = Sim.TallyResult(tally)
    result.list = list
    result.manaLeft = char.manaMax > 0 and manaLeft / n or nil
    return result
end

-- The fights each of a setup's ways gets of its n: n / ways, rounded up (Alen's pick for 1.0.8: fewer fights per way,
-- so a character played several ways takes about as long as one played one way; its numbers vary more).
local function Share(n, ways) return math.ceil(n / ways) end

-- n fights of a character (FightsOneWay). A model that plays a character more than one way (model.Variants(char): the
-- ways, nil for a character it plays one way only: a paladin's seals, a rogue's openers) shares the n fights among
-- the ways (Share) and keeps the way that does more, as a player would (result.variant; result.ways = { [variant] =
-- run } every way's); with opts.variant it plays that way only, n fights.
function Jobs.Fights(job, char, model, opts, n)
    local variants = not opts.variant and model.Variants and model.Variants(char)
    if not variants then return FightsOneWay(job, char, model, opts, n) end
    local per = Share(n, #variants)
    local best, ways = nil, {}
    for _, variant in ipairs(variants) do
        local run = FightsOneWay(job, char, model, { length = opts.length, levelOffset = opts.levelOffset, variant = variant }, per)
        run.variant = variant
        ways[variant] = run
        if not best or run.dps > best.dps then best = run end
    end
    best.ways = ways
    return best
end

-- The number of ways a model plays a character.
function Jobs.Ways(char, model)
    local variants = model.Variants and model.Variants(char)
    return variants and #variants or 1
end

-- The fights each way of the character gets of n (Share).
function Jobs.PerWay(char, model, n) return Share(n, Jobs.Ways(char, model)) end

-- The fights Jobs.Fights runs for n without opts.variant: every way's share.
function Jobs.FightCount(char, model, n) return Jobs.PerWay(char, model, n) * Jobs.Ways(char, model) end

-- The difference of two runs with the same fights: mean and its standard error (the same dice make it small).
function Jobs.Difference(a, b)
    local n = #a.list
    local sum, sumSq = 0, 0
    for i = 1, n do
        local d = b.list[i] - a.list[i]
        sum, sumSq = sum + d, sumSq + d * d
    end
    local mean = sum / n
    local var = n > 1 and math.max(0, (sumSq - n * mean * mean) / (n - 1)) or 0
    return mean, math.sqrt(var / n)
end

-- The damage per second of each source in b minus a: { [key] = difference }.
function Jobs.SourceDifference(a, b)
    local diff = {}
    for _, s in ipairs(b.sources) do diff[s.key] = s.dps end
    for _, s in ipairs(a.sources) do diff[s.key] = (diff[s.key] or 0) - s.dps end
    return diff
end

---------------------------------------------------------------------------
-- The character's own damage and what one more point of each stat is worth
---------------------------------------------------------------------------
-- The stats each spec is shown, by class and spec (PROT is a spec of two classes), with the step the simulator adds
-- (per point = difference / step).
local MELEE = { { "Strength", 20 }, { "Agility", 20 }, { "AttackPower", 40 }, { "CritPct", 2 }, { "HitPct", 2 } }
local RANGED = { { "Agility", 20 }, { "RangedAttackPower", 40 }, { "CritPct", 2 }, { "HitPct", 2 }, { "Intellect", 30 } }
local CASTER = { { "SpellPowerAll", 30 }, { "Intellect", 30 }, { "SpellCritPct", 2 }, { "SpellHitPct", 2 } }
local function With(list, ...)
    local all = { unpack(list) }
    for _, s in ipairs({ ... }) do all[#all + 1] = s end
    return all
end
local PALADIN = With(MELEE, { "SpellPowerAll", 30 }, { "Intellect", 30 })
Jobs.STATS = {
    -- (Shield Slam's damage grows with the shield's block value)
    WARRIOR = { ARMS = MELEE, FURY = MELEE, PROT = With(MELEE, { "BlockValue", 20 }) },
    PALADIN = { RET = PALADIN, PROT = PALADIN, HOLY = PALADIN, HOLY_DMG = PALADIN },
    HUNTER = { BM = RANGED, MM = RANGED, SV = { { "Agility", 20 }, { "AttackPower", 40 }, { "CritPct", 2 }, { "HitPct", 2 } } },
    ROGUE = { ASSA = MELEE, COMBAT = MELEE, SUB = MELEE },
    PRIEST = { SHADOW = CASTER, DISC = CASTER, HOLY = CASTER, DISC_DMG = CASTER, HOLY_DMG = CASTER },
    SHAMAN = { ELE = CASTER, ENH = With(MELEE, { "Intellect", 30 }), RESTO = CASTER },
    MAGE = { ARCANE = CASTER, FIRE = CASTER, FROST = CASTER },
    WARLOCK = { AFFLI = CASTER, DEMO = CASTER, DESTRO = CASTER },
    DRUID = { CAT = MELEE, BEAR = MELEE, BALANCE = CASTER, RESTO = CASTER },
}

-- Result: { base = run, stats = { { key, perPoint, error } } }.
function Jobs.OwnDamage(char, model, opts, n)
    return function(job)
        local stats = Jobs.STATS[char.class][char.spec]
        job.total = Jobs.FightCount(char, model, n) * (1 + #stats)
        local base = Jobs.Fights(job, char, model, opts, n)
        local out = {}
        for i, s in ipairs(stats) do
            local more = Character.WithStats(char, { [s[1]] = s[2] }, model)
            local run = Jobs.Fights(job, more, model, opts, n)
            local mean, err = Jobs.Difference(base, run)
            out[i] = { key = s[1], perPoint = mean / s[2], error = err / s[2] }
        end
        return { base = base, stats = out }
    end
end

---------------------------------------------------------------------------
-- Items for one equipment slot or many
---------------------------------------------------------------------------
-- Every item of picks in its slot against what is worn, n fights each, the same fights for all (job.total is the
-- caller's). picks = { { slot (equipment slot), ids = { item IDs } } }. Result: { base = run, slots = { { slot, rows =
-- { { id, run, delta, err, sources (differences), ways } or { id, failed = message } } } } } with the rows
-- of each slot by gain, biggest first; ways = { [variant] = { delta, err } } the gain played each way (a model with
-- more than one way, all of them played).
local function Compare(job, char, model, opts, n, picks)
    local base = Jobs.Fights(job, char, model, opts, n)
    local fights = opts.variant and n or Jobs.FightCount(char, model, n)
    local slots = {}
    for i, pick in ipairs(picks) do
        local rows = {}
        for _, id in ipairs(pick.ids) do
            local ok, other = pcall(Character.WithItem, char, pick.slot, id, model)
            if ok then
                local run = Jobs.Fights(job, other, model, opts, n)
                local mean, err = Jobs.Difference(base, run)
                local row = { id = id, run = run, delta = mean, err = err, sources = Jobs.SourceDifference(base, run) }
                if base.ways then
                    row.ways = {}
                    for variant, b in pairs(base.ways) do
                        local d, e = Jobs.Difference(b, run.ways[variant])
                        row.ways[variant] = { delta = d, err = e }
                    end
                end
                rows[#rows + 1] = row
            else
                job.done = job.done + fights
                rows[#rows + 1] = { id = id, failed = tostring(other) }
            end
        end
        table.sort(rows, function(a, b)
            if (a.failed == nil) ~= (b.failed == nil) then return a.failed == nil end
            return (a.delta or 0) > (b.delta or 0) or (a.delta == b.delta and a.id < b.id)
        end)
        slots[i] = { slot = pick.slot, rows = rows }
    end
    return { base = base, slots = slots }
end

-- The best set of many items in two passes: every item of picks with quick fights, then per slot the best ones and the
-- kept ones (picks[i].keep: item IDs that are simmed exactly anyway, e.g. an item to look at) with n fights; then the
-- set of each slot's best (setOf(slots, picks) = { { slot, id } }, SimBiS.SetOf) worn as a whole. A model that plays a
-- character more than one way (a paladin's seals: items with spell power are worth more together, once they make the
-- other seal do more) gets an exact pass and a set for each way, the items ranked by their gain played that way; the
-- set that does more wins. picks = { { slot, ids, keep } }. Result as Compare (the winning way's exact pass), plus
-- tested (the items of the quick pass), variant (the winning way) and gain (the set against what is worn, each played
-- its best way, damage per second).
function Jobs.BestItems(char, model, opts, quick, n, best, picks, setOf)
    return function(job)
        Character.AssertGear(char)
        local variants = model.Variants and model.Variants(char) or { false }
        -- each way's exact pass gets that way's share of n (Jobs.PerWay), as the ways of Jobs.Fights do
        local exactN = Jobs.PerWay(char, model, n)
        local count, exact = 0, 0
        for _, pick in ipairs(picks) do
            count = count + #pick.ids
            exact = exact + math.min(best, #pick.ids) + #pick.keep
        end
        -- the quick pass (every way), the exact pass of each way (that way), the set of each way (every way)
        job.total = Jobs.FightCount(char, model, quick) * (1 + count) + exactN * (1 + exact) * #variants
            + Jobs.FightCount(char, model, n) * #variants
        local first = Compare(job, char, model, opts, quick, picks)
        local passes = {}
        for _, variant in ipairs(variants) do
            local function Gain(row) return variant and row.ways[variant].delta or row.delta end
            local second, needed = {}, exactN
            for i, pick in ipairs(picks) do
                local rows = {}
                for _, row in ipairs(first.slots[i].rows) do
                    if not row.failed then rows[#rows + 1] = row end
                end
                table.sort(rows, function(a, b)
                    local ga, gb = Gain(a), Gain(b)
                    if ga ~= gb then return ga > gb end
                    return a.id < b.id
                end)
                local ids, seen = {}, {}
                local function Add(id)
                    if not seen[id] then
                        seen[id] = true
                        ids[#ids + 1] = id
                    end
                end
                for _, id in ipairs(pick.keep) do Add(id) end
                for j = 1, math.min(best, #rows) do Add(rows[j].id) end
                second[i] = { slot = pick.slot, ids = ids }
                needed = needed + exactN * #ids
            end
            -- the share the exact pass was given but does not need (fewer items than planned) counts as done
            job.done = job.done + math.max(0, exactN * (1 + exact) - needed)
            local o = variant and { length = opts.length, levelOffset = opts.levelOffset, variant = variant } or opts
            passes[#passes + 1] = { variant = variant, result = Compare(job, char, model, o, exactN, second) }
        end
        local winner, now
        for _, pass in ipairs(passes) do
            local c = char
            for _, it in ipairs(setOf(pass.result.slots, picks)) do c = Character.WithItem(c, it.slot, it.id, model) end
            pass.set = Jobs.Fights(job, c, model, opts, n)
            if not winner or pass.set.dps > winner.set.dps then winner = pass end
            if not now or pass.result.base.dps > now.dps then now = pass.result.base end
        end
        local result = winner.result
        result.tested, result.variant, result.gain = count, winner.variant or nil, winner.set.dps - now.dps
        return result
    end
end

-- One item against what is worn in each of its equipment slots (slots; stats: the item's own, from its link: a random
-- suffix counts), n fights each, the same fights for all. Result: { base = run, rows = { { delta, err } or { failed =
-- message } } } in the order of slots.
function Jobs.ItemGain(char, model, opts, n, itemID, stats, slots)
    return function(job)
        Character.AssertGear(char)
        local fights = Jobs.FightCount(char, model, n)
        job.total = fights * (1 + #slots)
        local base = Jobs.Fights(job, char, model, opts, n)
        local rows = {}
        for i, slot in ipairs(slots) do
            local ok, other = pcall(Character.WithItem, char, slot, itemID, model, stats)
            if ok then
                local mean, err = Jobs.Difference(base, Jobs.Fights(job, other, model, opts, n))
                rows[i] = { delta = mean, err = err }
            else
                job.done = job.done + fights
                rows[i] = { failed = tostring(other) }
            end
        end
        return { base = base, rows = rows }
    end
end

---------------------------------------------------------------------------
-- Whole sets
---------------------------------------------------------------------------
-- The character wearing a set: set.items = { { slot (equipment slot), id } } one after the other over what is worn (id
-- nil: that slot emptied). Returns the character, or nil and why it cannot wear them.
local function SetCharacter(char, model, set)
    local c = char
    for _, it in ipairs(set.items) do
        local ok, other
        if it.id then
            ok, other = pcall(Character.WithItem, c, it.slot, it.id, model)
        else
            ok, other = pcall(Character.WithoutItem, c, it.slot, model)
        end
        if not ok then return nil, tostring(other) end
        c = other
    end
    return c
end

-- sets = { { key, items } }: each set worn at once (SetCharacter) against what is worn, the same fights for all.
-- Result: { base = run, sets = { [key] = { run, delta, err, sources } or { failed = message } } }; a set without items
-- is what is worn.
function Jobs.CompareSets(char, model, opts, n, sets)
    return function(job)
        Character.AssertGear(char)
        local fights = Jobs.FightCount(char, model, n)
        job.total = fights * (1 + #sets)
        local base = Jobs.Fights(job, char, model, opts, n)
        local out = {}
        for _, set in ipairs(sets) do
            local c, failed = SetCharacter(char, model, set)
            if failed then
                job.done = job.done + fights
                out[set.key] = { failed = failed }
            else
                local run = Jobs.Fights(job, c, model, opts, n)
                local mean, err = Jobs.Difference(base, run)
                out[set.key] = { run = run, delta = mean, err = err, sources = Jobs.SourceDifference(base, run) }
            end
        end
        return { base = base, sets = out }
    end
end

-- One set on its own (the planner): n fights of the character wearing it (SetCharacter). Result: { run } or
-- { failed = message }.
function Jobs.SetDamage(char, model, opts, n, set)
    return function(job)
        Character.AssertGear(char)
        job.total = Jobs.FightCount(char, model, n)
        local c, failed = SetCharacter(char, model, set)
        if failed then return { failed = failed } end
        return { run = Jobs.Fights(job, c, model, opts, n) }
    end
end
