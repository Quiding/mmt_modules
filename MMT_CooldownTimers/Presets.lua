-- MMT Cooldown Timers: presets for the tracked lists, one per spec, from
-- Wowhead's WoW: Forever class guides (the "<spec> abilities" pages, October
-- 2026) and the cooldowns in Wowhead Forever's tooltips; talent cooldowns the
-- ability pages leave out (Adrenaline Rush, Presence of Mind, Last Stand, ...)
-- added from the talent data. Max-rank spell IDs; casts are matched by NAME, so
-- any rank works.
-- Pick one in the list editor and add it to a list or replace the list with it.
--   mod.PRESETS = { { key, group = class token | "RACE" | "ALL", name, entries }, ... }
-- An entry is { t = "s" | "i", id, cd = seconds, off = true|nil }.
-- Per spec: the big cooldowns, defensives and crowd control ON, the rotation and
-- short utility in the list but OFF. A class's default list (new profiles) is
-- every spec's entries together, on when on in any spec ("Hide what you don't
-- have" leaves out what a character hasn't learned); racials switched off.

local _, mod = ...

local function S(id, cd) return { t = "s", id = id, cd = cd } end
local function I(id, cd) return { t = "i", id = id, cd = cd } end

-- [class] = { { key, name, on = {...}, off = {...} }, ... } in talent tree order
local SPECS = {
    WARRIOR = {
        { "ARMS", "Arms", on = { S(1719, 1800), S(871, 900), S(20230, 900), S(1161, 600), S(5246, 180), S(12292, 30) },
          off = { S(21553, 6), S(11585, 5), S(1310222, 20), S(2687, 60), S(676, 60), S(18499, 30), S(20616, 30),
                  S(402927, 30), S(11578, 15), S(6554, 10), S(1680, 10), S(7400, 120), S(355, 8) } },
        { "FURY", "Fury", on = { S(1719, 1800), S(12328, 180), S(871, 900), S(20230, 900), S(1161, 600), S(5246, 180) },
          off = { S(23894, 6), S(1680, 10), S(2687, 60), S(18499, 30), S(20617, 30), S(6554, 10), S(676, 60),
                  S(402927, 30), S(11578, 15), S(20560, 120), S(355, 8) } },
        { "PROT", "Protection", on = { S(871, 900), S(12975, 180), S(1161, 600), S(694, 120) },
          off = { S(2565, 5), S(23923, 6), S(25288, 5), S(355, 8), S(12809, 45), S(72, 12), S(676, 60), S(2687, 60),
                  S(5246, 180), S(20230, 900), S(1719, 1800), S(20252, 30), S(100, 15) } },
    },
    PALADIN = {
        { "HOLY", "Holy", on = { S(10310, 1200), S(1020, 300), S(5573, 300), S(10278, 300), S(20216, 120),
                  S(1310897, 180), S(19752, 3600) },
          off = { S(20930, 10), S(1311595, 6), S(10308, 60), S(1044, 20), S(26573, 8), S(10318, 60), S(10326, 30) } },
        { "PROT", "Protection", on = { S(10310, 1200), S(1020, 300), S(10278, 300), S(1311015, 300), S(10308, 60),
                  S(19752, 3600) },
          off = { S(20928, 10), S(20924, 8), S(20271, 10), S(10314, 15), S(10318, 60), S(1044, 20), S(24239, 6),
                  S(10326, 30) } },
        { "RET", "Retribution", on = { S(10310, 1200), S(1020, 300), S(5573, 300), S(10278, 300), S(10308, 60),
                  S(20066, 60), S(19752, 3600) },
          off = { S(10318, 60), S(10326, 30), S(1044, 20), S(10314, 15), S(10333, 10), S(20271, 10), S(20924, 8),
                  S(24239, 6) } },
    },
    HUNTER = {
        { "BM", "Beast Mastery", on = { S(3045, 300), S(19574, 120), S(19577, 60) },
          off = { S(5384, 30), S(14311, 30), S(13809, 30), S(14317, 30), S(14305, 30), S(19801, 20), S(2643, 6),
                  S(14287, 6), S(5116, 12), S(14273, 5), S(1543, 15), S(14280, 15) } },
        { "MM", "Marksmanship", on = { S(3045, 300) },
          off = { S(1310786, 15), S(20904, 6), S(2643, 6), S(14287, 6), S(5384, 30), S(14311, 30), S(13809, 30),
                  S(14317, 30), S(19801, 20), S(5116, 12), S(14273, 5), S(1543, 15), S(14280, 15) } },
        { "SURV", "Survival", on = { S(3045, 300), S(19263, 300) },
          off = { S(1317257, 8), S(19306, 5), S(14271, 5), S(415343, 6), S(5384, 30), S(14311, 30), S(13809, 30),
                  S(14317, 30), S(19801, 20), S(2643, 6), S(14287, 6), S(14273, 5), S(1543, 15) } },
    },
    ROGUE = {
        { "ASSA", "Assassination", on = { S(14177, 180), S(1856, 300), S(5277, 300), S(2983, 300), S(2094, 300) },
          off = { S(1766, 10), S(408, 20), S(1776, 10), S(1966, 10), S(1725, 30), S(1784, 10) } },
        { "COMBAT", "Combat", on = { S(13750, 300), S(13877, 120), S(1856, 300), S(5277, 300), S(2983, 300), S(2094, 300) },
          off = { S(1766, 10), S(408, 20), S(1776, 10), S(1966, 10), S(1725, 30), S(1784, 10) } },
        { "SUB", "Subtlety", on = { S(14185, 600), S(1856, 300), S(5277, 300), S(2983, 300), S(2094, 300) },
          off = { S(14183, 120), S(14278, 20), S(1766, 10), S(408, 20), S(1776, 10), S(1966, 10), S(1725, 30), S(1784, 10) } },
    },
    PRIEST = {
        { "DISC", "Discipline", on = { S(10060, 180), S(14751, 180), S(13908, 600), S(6346, 180) },
          off = { S(402174, 12), S(8122, 30), S(586, 30), S(13896, 180), S(1277335, 120), S(1277455, 120),
                  S(1309636, 18), S(10947, 8) } },
        { "HOLY", "Holy", on = { S(724, 600), S(14751, 180), S(13908, 600), S(6346, 180) },
          off = { S(1240827, 10), S(8122, 30), S(586, 30), S(13896, 180), S(1277335, 120), S(1277455, 120),
                  S(1309636, 18) } },
        { "SHADOW", "Shadow", on = { S(15487, 45), S(13908, 600), S(6346, 180) },
          off = { S(15286, 30), S(8122, 30), S(586, 30), S(8092, 8), S(1309595, 18), S(2944, 24), S(13896, 180),
                  S(1277331, 120), S(1277455, 120) } },
    },
    SHAMAN = {
        { "ELE", "Elemental", on = { S(16166, 180), S(20608, 3600) },
          off = { S(1238300, 10), S(437009, 60), S(8177, 15), S(10414, 6), S(10605, 6), S(10428, 30), S(2484, 15) } },
        { "ENH", "Enhancement", on = { S(425336, 180), S(20608, 3600) },
          off = { S(17364, 8), S(10414, 6), S(29228, 6), S(8177, 15), S(437009, 60), S(10428, 30), S(2484, 15) } },
        { "RESTO", "Restoration", on = { S(16188, 180), S(16190, 300), S(20608, 3600) },
          off = { S(1239243, 6), S(8177, 15), S(437009, 60), S(10414, 6), S(10428, 30), S(2484, 15) } },
    },
    MAGE = {
        { "ARCANE", "Arcane", on = { S(12042, 180), S(12043, 180), S(12051, 480), S(11958, 300) },
          off = { S(2139, 30), S(1953, 15), S(10230, 25), S(10225, 30), S(28609, 30), S(10161, 10), S(10199, 8) } },
        { "FIRE", "Fire", on = { S(11129, 180), S(12051, 480), S(11958, 300) },
          off = { S(11113, 45), S(2139, 30), S(1953, 15), S(10230, 25), S(10225, 30), S(28609, 30), S(10199, 8) } },
        { "FROST", "Frost", on = { S(11958, 300), S(12472, 600), S(12051, 480) },
          off = { S(11426, 30), S(2139, 30), S(1953, 15), S(10230, 25), S(10161, 10), S(28609, 30), S(10199, 8) } },
    },
    WARLOCK = {
        { "AFF", "Affliction", on = { S(18288, 180), S(17926, 120), S(1122, 3600) },
          off = { S(17928, 40), S(19647, 30), S(28610, 30), S(603, 60), S(18540, 3600) } },
        { "DEMO", "Demonology", on = { S(18708, 300), S(17926, 120), S(1122, 3600) },
          off = { S(17924, 60), S(17928, 40), S(19647, 30), S(28610, 30), S(603, 60), S(18540, 3600) } },
        { "DESTRO", "Destruction", on = { S(17926, 120), S(1122, 3600) },
          off = { S(18932, 10), S(18871, 15), S(17924, 60), S(17928, 40), S(19647, 30), S(28610, 30), S(603, 60),
                  S(18540, 3600) } },
    },
    DRUID = {
        { "BALANCE", "Balance", on = { S(29166, 360), S(20748, 1800), S(9863, 300), S(22812, 60) },
          off = { S(16689, 60), S(8983, 60), S(5209, 600), S(22842, 180) } },
        { "FERAL", "Feral (cat)", on = { S(417141, 180), S(29166, 360), S(20748, 1800), S(22812, 60) },
          off = { S(5217, 30), S(9821, 300), S(8983, 60), S(22842, 180), S(16689, 60), S(5229, 60) } },
        { "BEAR", "Feral (bear tank)", on = { S(417141, 180), S(22842, 180), S(5209, 600), S(22812, 60), S(29166, 360),
                  S(20748, 1800) },
          off = { S(5229, 60), S(8983, 60), S(6795, 8), S(16979, 15), S(16689, 60), S(9863, 300) } },
        { "RESTO", "Restoration", on = { S(17116, 180), S(29166, 360), S(20748, 1800), S(9863, 300), S(22812, 60) },
          off = { S(18562, 15), S(1238215, 6), S(16689, 60), S(8983, 60) } },
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

mod.PRESETS = {}
mod.DEFAULT_LISTS = { ALL = {} }
for _, class in ipairs(mod.CLASSES) do
    local specs = SPECS[class]
    if specs then
        -- the class default: every spec's entries once, on when on in any spec
        local default, at = {}, {}
        for _, sp in ipairs(specs) do
            local entries = {}
            for _, e in ipairs(Copy(sp.on)) do entries[#entries + 1] = e end
            for _, e in ipairs(Copy(sp.off, true)) do entries[#entries + 1] = e end
            table.insert(mod.PRESETS, { key = class .. ":" .. sp[1], group = class,
                name = CLASS_NAMES[class] .. ": " .. sp[2], entries = entries })
            for _, e in ipairs(entries) do
                local i = at[e.id]
                if not i then
                    default[#default + 1] = { t = e.t, id = e.id, cd = e.cd, off = e.off }
                    at[e.id] = #default
                elseif not e.off then
                    default[i].off = nil
                end
            end
        end
        mod.DEFAULT_LISTS[class] = default
    end
end
for _, r in ipairs(RACIALS) do
    table.insert(mod.PRESETS, { key = "RACE:" .. r[1], group = "RACE", race = r[1], name = "Racials: " .. r[2], entries = Copy(r[3]) })
    mod.DEFAULT_LISTS["RACE:" .. r[1]] = Copy(r[3], true)
end
table.insert(mod.PRESETS, { key = "ALL:CONSUMABLES", group = "ALL", name = "Potions & runes", entries = Copy(CONSUMABLES) })
