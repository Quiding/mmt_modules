-- MMT Cooldowns: presets for the tracked lists, from Wowhead's WoW: Forever
-- data (October 2026: Forever cooldowns, new spells and talents, racials).
-- Pick one in the list editor and add it to a list or replace the list with it.
--   mod.PRESETS = { { key, group = class token | "RACE" | "ALL", name, entries }, ... }
-- An entry is { t = "s" | "i", id, cd = seconds, off = true|nil }. Casts are
-- matched by NAME, so any rank works. The default lists of a new profile are
-- built from them at the end (racials switched off).

local _, mod = ...

local function S(id, cd) return { t = "s", id = id, cd = cd } end
local function I(id, cd) return { t = "i", id = id, cd = cd } end

-- per class: big cooldowns (on in "recommended") and utility / control (off there)
local CLASS = {
    WARRIOR = {
        major = { S(1719, 1800), S(871, 900), S(20230, 900), S(12328, 180), S(12975, 180), S(1161, 600) },
        utility = { S(5246, 180), S(694, 120), S(676, 60), S(2687, 60), S(12809, 45), S(20252, 30), S(18499, 30),
                    S(12292, 30), S(1310222, 20), S(100, 15), S(72, 12), S(6552, 10) },
    },
    PALADIN = {
        major = { S(633, 1200), S(642, 300), S(498, 300), S(1022, 300), S(1311015, 300), S(1310897, 180), S(20216, 120) },
        utility = { S(853, 60), S(2812, 60), S(20066, 60), S(1310994, 60), S(2878, 30), S(1044, 20), S(879, 15),
                    S(20473, 10), S(20925, 10) },
    },
    HUNTER = {
        major = { S(3045, 300), S(23989, 300), S(19263, 300), S(19574, 120) },
        utility = { S(19577, 60), S(5384, 30), S(1499, 30), S(13809, 30), S(13795, 30), S(13813, 30), S(19503, 30),
                    S(1513, 30), S(19801, 20), S(1310687, 15), S(1543, 15), S(3034, 15), S(5116, 12) },
    },
    ROGUE = {
        major = { S(14185, 600), S(1856, 300), S(5277, 300), S(2983, 300), S(13750, 300), S(2094, 300),
                  S(14177, 180), S(13877, 120), S(14183, 120) },
        utility = { S(1725, 30), S(408, 20), S(14278, 20), S(1766, 10), S(1776, 10), S(1966, 10) },
    },
    PRIEST = {
        major = { S(10060, 180), S(14751, 180), S(6346, 180), S(13908, 600) },
        utility = { S(724, 600), S(1277324, 600), S(1277370, 600), S(1277462, 600), S(2651, 300), S(13896, 180),
                    S(1277455, 120), S(1277331, 120), S(15487, 45), S(8122, 30), S(586, 30), S(15286, 30),
                    S(10797, 30), S(2944, 24), S(402174, 12) },
    },
    SHAMAN = {
        major = { S(16190, 300), S(16166, 180), S(16188, 180) },
        utility = { S(556, 900), S(437009, 60), S(5730, 30), S(2484, 15), S(8177, 15), S(408490, 10),
                    S(408341, 10), S(17364, 8), S(8042, 6) },
    },
    MAGE = {
        major = { S(12472, 600), S(12051, 480), S(11958, 300), S(11129, 180), S(12042, 180), S(12043, 180) },
        utility = { S(11113, 45), S(2139, 30), S(11426, 30), S(543, 30), S(6143, 30), S(122, 25), S(1953, 15), S(120, 10) },
    },
    WARLOCK = {
        major = { S(18708, 300), S(18288, 180), S(6789, 120) },
        utility = { S(603, 60), S(6353, 60), S(5484, 40), S(6229, 30), S(17877, 15), S(17962, 10) },
    },
    DRUID = {
        major = { S(20484, 1800), S(5209, 600), S(29166, 360), S(740, 300), S(1850, 300), S(17116, 180),
                  S(22842, 180), S(22812, 60) },
        utility = { S(5211, 60), S(5229, 60), S(16689, 60), S(5217, 30), S(1322605, 16), S(16979, 15), S(18562, 15) },
    },
}

-- WoW: Forever racials with a cooldown (both Skyborne races share Walk on Air)
local RACIALS = {
    { "Human", "Human", { S(1259718, 180), S(20600, 180) } },             -- Will to Survive, Perception
    { "Dwarf", "Dwarf", { S(20594, 180) } },                               -- Stoneform
    { "NightElf", "Night Elf", { S(1259799, 180), S(20580, 10) } },       -- Elune's Light, Shadowmeld
    { "Gnome", "Gnome", { S(20589, 120), S(1259812, 120) } },             -- Escape Artist, Eureka!
    { "Orc", "Orc", { S(20572, 180), S(1299026, 180) } },                 -- Blood Fury, Shatter Curse
    { "Scourge", "Undead", { S(7744, 120), S(20577, 120) } },             -- Will of the Forsaken, Cannibalize
    { "Tauren", "Tauren", { S(20549, 90), S(20552, 900) } },              -- War Stomp, Cultivation
    { "Troll", "Troll", { S(20554, 180), S(1260270, 180) } },             -- Berserking, Rapid Regeneration
    { "HighOrderSkyborne", "High Order Skyborne", { S(1259416, 90), S(1259705, 120) } },  -- Walk on Air, Read Leyline
    { "WindshaperSkyborne", "Windshaper Skyborne", { S(1259416, 90), S(1259686, 120) } }, -- Walk on Air, Skysight
}

-- every class: potions and runes share Classic's 2 min potion / rune cooldowns
local CONSUMABLES = { I(13446, 120), I(13444, 120), I(20520, 120), I(12662, 120) }

local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

local function Copy(list, off)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = { t = e.t, id = e.id, cd = e.cd, off = off or nil } end
    return out
end
local function Join(a, b)
    local out = {}
    for _, e in ipairs(a) do out[#out + 1] = e end
    for _, e in ipairs(b) do out[#out + 1] = e end
    return out
end

mod.PRESETS = {}
for _, class in ipairs(mod.CLASSES) do
    local c = CLASS[class]
    if c then
        local n = CLASS_NAMES[class]
        table.insert(mod.PRESETS, { key = class .. ":REC", group = class, name = n .. ": recommended (utility off)",
            entries = Join(Copy(c.major), Copy(c.utility, true)) })
        table.insert(mod.PRESETS, { key = class .. ":MAJOR", group = class, name = n .. ": major cooldowns only",
            entries = Copy(c.major) })
        table.insert(mod.PRESETS, { key = class .. ":ALL", group = class, name = n .. ": everything on",
            entries = Join(Copy(c.major), Copy(c.utility)) })
    end
end
for _, r in ipairs(RACIALS) do
    table.insert(mod.PRESETS, { key = "RACE:" .. r[1], group = "RACE", race = r[1], name = "Racials: " .. r[2], entries = Copy(r[3]) })
end
table.insert(mod.PRESETS, { key = "ALL:CONSUMABLES", group = "ALL", name = "Potions & runes", entries = Copy(CONSUMABLES) })

-- default lists of a new profile: "recommended" per class, racials (off) per race
mod.DEFAULT_LISTS = { ALL = {} }
for _, p in ipairs(mod.PRESETS) do
    if p.key:find(":REC$") then mod.DEFAULT_LISTS[p.group] = Copy(p.entries)
        for i, e in ipairs(p.entries) do mod.DEFAULT_LISTS[p.group][i].off = e.off end
    elseif p.group == "RACE" then mod.DEFAULT_LISTS["RACE:" .. p.race] = Copy(p.entries, true) end
end
