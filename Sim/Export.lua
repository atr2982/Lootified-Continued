-- Lootified - /lf export: the character for Lootified's web simulator, which runs this addon's own simulator (the same
-- Lua) in the browser. The text is "LF1:" and the Base64 of the zlib-compressed JSON (C_EncodingUtil) of
-- { lf = 1 (the format), char = the character, settings = { length, target } (the simulator window's) }. The character
-- is the one Character.ReadRaw reads (the web runs Character.Finish on it) with the stats of what is worn (slotStats),
-- the weapon skills (weaponSkills), what the model's Setup asks the game (auras, spellTexts: Export.Asked) and how the
-- game converts stats (conv: Character.Conversions). Every key in it is a string (Export.Pack). No name, no realm.
local _, LJ = ...

local Sim = LJ.Sim
local Character = Sim.Character
local Export = {}
Sim.Export = Export

Export.PREFIX = "LF1:"
Export.FORMAT = 1

-- t with every key a string, for JSON: an integer key as "#<n>" (a string key never starts with "#"); values are
-- numbers, strings, booleans and tables. Anything else (a function) stops it. A table used twice comes out twice.
function Export.Pack(t, path)
    path = path or "char"
    local out = {}
    for k, v in pairs(t) do
        local key = k
        if type(k) == "number" then
            assert(k == math.floor(k), path .. ": key " .. k .. " is no integer")
            key = ("#%d"):format(k)
        else
            assert(type(k) == "string" and k:sub(1, 1) ~= "#", path .. ": key " .. tostring(k) .. " cannot be packed")
        end
        local at, kind = path .. "." .. key, type(v)
        if kind == "table" then
            out[key] = Export.Pack(v, at)
        else
            assert(kind == "string" or kind == "boolean" or (kind == "number" and v == v and v ~= math.huge
                and v ~= -math.huge), at .. ": " .. tostring(v) .. " cannot be packed")
            out[key] = v
        end
    end
    return out
end

-- A copy of t and of every table in it (a table used twice stays one table).
local function DeepCopy(t, copies)
    copies = copies or {}
    if copies[t] then return copies[t] end
    local c = {}
    copies[t] = c
    for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v, copies) or v end
    return c
end

-- What the model's Setup asks the game: Character.Finish runs on a copy of the character while Sim.PlayerAura and
-- Character.Describe write down their answers (both are put back after it). auras = { [spell ID] = true } (the ones
-- the player has), spellTexts = { [spell ID] = { name, text, p } } (p: Character.Parse in the client's language, which
-- the web cannot parse again).
function Export.Asked(c, model)
    local auras, texts = {}, {}
    local playerAura, describe = Sim.PlayerAura, Character.Describe
    Sim.PlayerAura = function(id)
        local aura = playerAura(id)
        if aura then auras[id] = true end
        return aura
    end
    Character.Describe = function(id)
        local d = describe(id)
        texts[id] = { name = d.name, text = d.text, p = d.p }
        return d
    end
    local ok, err = pcall(Character.Finish, DeepCopy(c), model)
    Sim.PlayerAura, Character.Describe = playerAura, describe
    if not ok then error(err, 0) end
    return auras, texts
end

-- The character of the export (spec: the one the simulator plays, model: its class model, gear: the stats of what is
-- worn, SimBiS.WhenGearRead). Errors as Character.Read does.
function Export.Record(model, spec, gear)
    local c = Character.ReadRaw(model, spec.key)
    c.slotStats, c.weaponSkills = gear, Character.WeaponSkills()
    c.auras, c.spellTexts = Export.Asked(c, model)
    c.conv = Character.Conversions(c)
    return c
end

-- The text of a character (Export.Record) with the simulator window's fight length and target.
function Export.Text(c)
    local db = LJ.db.sim
    local envelope = { lf = Export.FORMAT, char = Export.Pack(c), settings = { length = db.length, target = db.target } }
    local E = C_EncodingUtil
    return Export.PREFIX .. E.EncodeBase64(E.CompressString(E.SerializeJSON(envelope), Enum.CompressionMethod.Zlib))
end

-- /lf export: reads the character of the spec the simulator plays once the game has the data of what is worn and shows
-- the text to copy (UI/ExportBox.lua); what keeps it from reading the character goes to the chat.
function Export.Start()
    local spec = LJ.Player:GetActiveSpec()
    local model = LJ.UI.Sim.Model(spec)
    assert(model, "the simulator plays the specs of the player's class")
    LJ.SimBiS.WhenGearRead(function(gear)
        local ok, text = pcall(function() return Export.Text(Export.Record(model, spec, gear)) end)
        if not ok then
            LJ:Print(LJ.UI.Sim.ProblemText(text))
            return
        end
        LJ.UI.ExportBox:Show(text)
    end)
end
