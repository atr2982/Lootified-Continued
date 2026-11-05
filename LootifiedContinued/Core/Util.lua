-- Lootified - shared helpers (textures, colors, classes, formatting).
local _, LJ = ...
local L = LJ.L

local Util = {}
LJ.Util = Util

Util.WHITE = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- Texture / atlas availability
-- The Forever client ships most retail art, but not everything. Before using
-- an optional Blizzard texture we check that the file is really present.
---------------------------------------------------------------------------
local fileCache = {}

function Util.FileExists(path)
    if not path then return false end
    local cached = fileCache[path]
    if cached ~= nil then return cached end
    local id = GetFileIDFromPath(path) or GetFileIDFromPath(path .. ".blp")
    local result = id ~= nil and id ~= 0
    fileCache[path] = result
    return result
end

function Util.AtlasExists(atlas)
    return C_Texture.GetAtlasInfo(atlas) ~= nil
end

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------
Util.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

Util.CLASS_ICON_FILE = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- Class name in the addon's language: the game's own name when the addon uses the language of the client, the
-- addon's translation otherwise (German addon on an English client, English addon on a German client).
function Util.ClassName(class)
    local client = GetLocale()
    local addon = (LJ.Locale and LJ.Locale.active) or "enUS"
    local sameLanguage = addon == client or (addon == "enUS" and client:sub(1, 2) == "en")
    local localized = sameLanguage and LOCALIZED_CLASS_NAMES_MALE[class]
    return localized or L(CLASS_NAMES[class]) or class
end

function Util.ClassColor(class)
    local c = RAID_CLASS_COLORS[class]
    return c.r, c.g, c.b
end

function Util.ClassColorCode(class)
    local r, g, b = Util.ClassColor(class)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function Util.SetClassIcon(texture, class)
    local coords = CLASS_ICON_TCOORDS[class]
    texture:SetTexture(Util.CLASS_ICON_FILE)
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

---------------------------------------------------------------------------
-- Item quality colors
---------------------------------------------------------------------------
function Util.QualityColor(quality)
    local r, g, b = C_Item.GetItemQualityColor(quality or 1)
    return r, g, b
end

function Util.ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255, tostring(text))
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------
function Util.LevelRange(minLevel, maxLevel)
    if not minLevel then return "" end
    if not maxLevel or maxLevel == minLevel then
        return tostring(minLevel)
    end
    return string.format("%d-%d", minLevel, maxLevel)
end

-- A drop chance for display: "100%", "25%", "2.5%", "0.03%" (two decimals below 1%, so tiny chances do not
-- round to 0); nil without a chance.
function Util.FormatChance(c)
    if not c or c <= 0 then return nil end
    if c >= 99.5 then return "100%" end
    if c >= 10 then return string.format("%d%%", math.floor(c + 0.5)) end
    if c >= 1 then return (string.format("%.1f", c):gsub("%.0$", "")) .. "%" end
    return (string.format("%.2f", c):gsub("0$", "")) .. "%"
end

function Util.IsSecret(value)
    return issecretvalue(value)
end

function Util.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Lower-case, accent-agnostic key for searching ("Rath'mael" -> "rathmael").
-- Cyrillic letters in UTF-8 (string.upper and lower only know ASCII): а-п D0 B0-BF, р-я D1 80-8F, ё D1 91;
-- А-П D0 90-9F, Р-Я D0 A0-AF, Ё D0 81
local CYRILLIC_UPPER, CYRILLIC_LOWER = {}, {}
for i = 0, 15 do
    local lowA, upA = "\208" .. string.char(0xB0 + i), "\208" .. string.char(0x90 + i)
    local lowR, upR = "\209" .. string.char(0x80 + i), "\208" .. string.char(0xA0 + i)
    CYRILLIC_UPPER[lowA], CYRILLIC_UPPER[lowR] = upA, upR
    CYRILLIC_LOWER[upA], CYRILLIC_LOWER[upR] = lowA, lowR
end
CYRILLIC_UPPER["\209\145"], CYRILLIC_LOWER["\208\129"] = "\208\129", "\209\145"
local CYRILLIC = "[\208\209][\128-\191]"
-- Latin-1 letters with accents and umlauts (French, Spanish, Portuguese, German): the capital is the small letter's
-- second byte - 32 (× and ÷ are no letters, ß and ÿ have no Latin-1 capital)
local function Latin1Upper(b) return "\195" .. string.char(b:byte() - 32) end
local function Latin1Lower(b) return "\195" .. string.char(b:byte() + 32) end
-- the small Latin-1 letters by their second byte -> the plain letters (searches find "Défias" by "defias")
local LATIN1_PLAIN = { [159] = "ss", [166] = "ae", [167] = "c", [176] = "d", [177] = "n", [184] = "o", [189] = "y",
    [190] = "th", [191] = "y" }
for b = 160, 165 do LATIN1_PLAIN[b] = "a" end
for b = 168, 171 do LATIN1_PLAIN[b] = "e" end
for b = 172, 175 do LATIN1_PLAIN[b] = "i" end
for b = 178, 182 do LATIN1_PLAIN[b] = "o" end
for b = 185, 188 do LATIN1_PLAIN[b] = "u" end
local function Latin1Plain(b) return LATIN1_PLAIN[b:byte()] end

function Util.SearchKey(s)
    s = tostring(s or ""):lower()
    -- the Latin-1 letters (lower() only knows ASCII) and œ without accents: Ä É ñ ç œ ... -> a e n c oe ...
    s = s:gsub("\195([\128-\150\152-\158])", Latin1Lower):gsub("\195([\159-\182\184-\191])", Latin1Plain)
    s = s:gsub("\197[\146\147]", "oe")
    -- Cyrillic capitals, and ё as е (Russian is often typed without ё)
    s = s:gsub(CYRILLIC, CYRILLIC_LOWER):gsub("\209\145", "\208\181")
    -- drop apostrophes (ASCII and the typographic U+2019), treat punctuation as spaces
    s = s:gsub("\226\128\153", ""):gsub("'", ""):gsub("[%-:,%.%(%)]", " "):gsub("%s+", " ")
    return Util.Trim(s)
end

-- A GlobalStrings format ("Classes: %s", "Requires %s (%d)") as a Lua pattern that captures its %s and %d parts.
function Util.FormatPattern(format)
    local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
    return "^" .. escaped:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
end

-- The letters of search words: spaces and punctuation do not count, a letter like "ä" counts once; a Korean or
-- Chinese character (three bytes in UTF-8) counts three: one is a syllable or a word, enough to search.
function Util.LetterCount(tokens)
    local n = 0
    for i = 1, #tokens do
        local word = tokens[i]
        n = n + #word - select(2, word:gsub("[\128-\191]", ""))   -- UTF-8 follow-up bytes are not letters
            + 2 * select(2, word:gsub("[\224-\239]", ""))
    end
    return n
end

-- The word for a count: "boss" or "bosses" (both forms translated: German plurals are not "+s"). Russian takes the
-- singular for 1, 21, 31 ... and a third form for 2-4, 22-24 ... (LJ.uiFew: the plural's third form).
function Util.PluralWord(n, singular, plural)
    plural = plural or (singular .. "s")
    local few = LJ.uiFew
    if few then
        local tens, hundreds = n % 10, n % 100
        if tens == 1 and hundreds ~= 11 then return LJ.L(singular) end
        if tens >= 2 and tens <= 4 and (hundreds < 12 or hundreds > 14) then return few[plural] or LJ.L(plural) end
        return LJ.L(plural)
    end
    return LJ.L(n == 1 and singular or plural)
end

-- "1 boss", "3 bosses"
function Util.Plural(n, singular, plural)
    return string.format("%d %s", n, Util.PluralWord(n, singular, plural))
end

-- Upper case that also knows the German umlauts and ß (as "SS") and Cyrillic (string.upper only knows ASCII)
function Util.Upper(s)
    s = tostring(s or ""):upper()
    s = s:gsub("\195([\160-\182\184-\190])", Latin1Upper):gsub("\195\159", "SS")
    return (s:gsub(CYRILLIC, CYRILLIC_UPPER))
end

function Util.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

function Util.PlaySound(kit)
    PlaySound(SOUNDKIT[kit])
end
