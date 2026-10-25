-- MMT Buffs: presets for the tracked lists, from Wowhead's WoW: Forever data
-- (October 2026; many buffs are raid-wide in Forever: Battle Shout, Trueshot
-- Aura, Leader of the Pack, Moonkin Aura, the totems; Salvation is its own buff).
-- Pick one in the list editor and add it to a list or replace the list with it.
--   mod.PRESETS = { { key, group = class token | "ALL", name, entries }, ... }
-- An entry is { id, off = true|nil } (or a name pattern / weapon, Lists.lua); buffs match by NAME (any rank, and group
-- versions like Prayer of Fortitude count, see Lists.lua).

local _, mod = ...

local function B(id) return { id = id } end
local function O(id) return { id = id, off = true } end
local function P(name, off) return { name = name, off = off or nil } end   -- a name pattern (Lists.lua)
local function W(slot, off) return { weapon = slot, off = off or nil } end  -- weapon enchant (Weapons.lua)
-- a totem's buff (pattern: the buff is "Strength of Earth", the totem "... Totem"),
-- shown only while a shaman is around (Casters.lua)
local function T(name, off) return { name = name, caster = "SHAMAN", off = off or nil } end
-- the party buffs (cast on others, no auras): the All bar's default and the "Raid buffs" preset
local function PartyBuffs()
    return {
        B(1243), B(1126), B(20217),            -- Fortitude, Mark of the Wild, Kings
        B(976), B(14752), B(1459),             -- Shadow Protection, Divine Spirit, Arcane Intellect
        B(19740), B(19742), B(1038),           -- Might, Wisdom, Salvation
        B(6673),                               -- Battle Shout
    }
end

mod.PRESETS = {
    -- every member ------------------------------------------------------------
    { key = "ALL:RAID", group = "ALL", name = "Raid buffs (party buffs, no auras)", entries = PartyBuffs() },
    { key = "ALL:RAIDAURAS", group = "ALL", name = "Raid buffs + auras (Fortitude, Mark, Kings on)", entries = {
        B(1243), B(1126), B(20217),                       -- Fortitude, Mark of the Wild, Kings
        O(1459), O(14752), O(976),                        -- Arcane Intellect, Divine Spirit, Shadow Protection
        O(19740), O(19742), O(1038),                      -- Might, Wisdom, Salvation
        O(6673), O(19506), O(17007), O(24907),            -- Battle Shout, Trueshot Aura, Leader of the Pack, Moonkin Aura
    } },
    { key = "ALL:TOTEMS", group = "ALL", name = "Shaman totems (only in the shaman's party)", entries = {
        T("Strength of Earth*"), T("Grace of Air*"), T("Windfury Totem*"),   -- melee: set "Only for" with the cog
        T("Mana Spring*"), T("Flametongue Totem*", true),
        T("Stoneskin*", true), T("Tranquil Air*", true),
    } },
    { key = "ALL:WEAPONS", group = "ALL", name = "Weapon enchants (oils, stones, poisons, imbues)", entries = {
        W("MH"), W("OH", true),
    } },
    { key = "ALL:WORLD", group = "ALL", name = "World buffs", entries = {
        B(22888), B(24425), B(16609), B(15366),           -- Rallying Cry, Spirit of Zandalar, Warchief's Blessing, Songflower
        B(22817), B(22818), B(22820), B(23768),           -- Fengus', Mol'dar's, Slip'kik's, Sayge's (Darkmoon)
    } },
    { key = "ALL:FLASKS", group = "ALL", name = "Flasks & elixirs", entries = {
        B(17626), B(17628), B(17627),                     -- Flask of the Titans / Supreme Power / Distilled Wisdom
        B(17538), B(11405), B(17539), B(3593),            -- Mongoose, Giants, Greater Arcane, Fortitude
    } },
}

-- per spec: the buffs that member keeps up on themselves (Wowhead Forever's
-- class guides, October 2026). Spec-only ones (another spec's seal, form, aura)
-- off in the class default; party buffs (Fortitude, Blessings, ...) are the All bar's.
local SPECS = {
    WARRIOR = {
        { "ARMS", "Arms", { B(6673), O(12319) } },                       -- Battle Shout, Flurry
        { "FURY", "Fury", { B(6673), B(12319) } },
        { "PROT", "Protection", { B(6673) } },
    },
    PALADIN = {
        { "HOLY", "Holy", { B(19746), P("Seal of *"), O(10293) } },  -- Concentration Aura, any seal, Devotion
        { "PROT", "Protection", { B(25780), B(10293), B(20928), P("Seal of *"), O(10301) } },
            -- Righteous Fury, Devotion Aura, Holy Shield, any seal (Seal of Fury), Retribution Aura
        { "RET", "Retribution", { P("Seal of *"), B(20050), B(20218), O(10301) } },
            -- any seal (Command / Crusader / Righteousness, swapped with Twist of Light), Vengeance, Sanctity Aura, Retribution Aura
    },
    HUNTER = {
        { "BM", "Beast Mastery", { P("Aspect of the *") } },             -- any aspect (Hawk, Monkey, Wild, ...)
        { "MM", "Marksmanship", { P("Aspect of the *"), B(19506) } },    -- + Trueshot Aura
        { "SURV", "Survival", { P("Aspect of the *") } },
    },
    ROGUE = {
        { "ASSA", "Assassination", { B(5171), W("MH"), W("OH") } },      -- Slice and Dice, poisons
        { "COMBAT", "Combat", { B(5171), W("MH"), W("OH") } },
        { "SUB", "Subtlety", { B(5171), W("MH"), W("OH") } },
    },
    PRIEST = {
        { "DISC", "Discipline", { B(588), O(6346) } },                   -- Inner Fire, Fear Ward
        { "HOLY", "Holy", { B(588), O(6346) } },
        { "SHADOW", "Shadow", { B(15473), B(588), O(6346) } },           -- Shadowform
    },
    SHAMAN = {
        { "ELE", "Elemental", { B(408510), O(324), W("MH", true) } },    -- Water Shield, Lightning Shield, imbue
        { "ENH", "Enhancement", { B(324), O(408510), W("MH"), W("OH") } },
            -- weapon imbue: Windfury Weapon (stacks with Flametongue Totem) or Flametongue Weapon (stacks
            -- with Windfury Totem) - any counts; the off hand only shows with a weapon there (dual wield)
        { "RESTO", "Restoration", { B(408510), O(324), W("MH", true) } },
    },
    MAGE = {
        { "ARCANE", "Arcane", { B(6117), O(7302) } },                    -- Mage Armor, Ice Armor
        { "FIRE", "Fire", { B(6117), O(7302) } },
        { "FROST", "Frost", { B(7302), B(11426), O(6117) } },            -- + Ice Barrier
    },
    WARLOCK = {
        { "AFF", "Affliction", { B(706) } },                             -- Demon Armor
        { "DEMO", "Demonology", { B(706), B(19028) } },                  -- + Soul Link
        { "DESTRO", "Destruction", { B(706) } },
    },
    DRUID = {
        { "BALANCE", "Balance", { B(24858), B(16864), O(467) } },        -- Moonkin Form, Omen of Clarity, Thorns
        { "FERAL", "Feral (cat)", { B(16864), B(17007), O(467) } },      -- + Leader of the Pack
        { "BEAR", "Feral (bear tank)", { B(16864), B(17007), B(467) } },
        { "RESTO", "Restoration", { B(16864), O(467) } },
    },
}
local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
for _, class in ipairs(mod.CLASSES) do
    for _, sp in ipairs(SPECS[class] or {}) do
        table.insert(mod.PRESETS, { key = class .. ":" .. sp[1], group = class,
            name = CLASS_NAMES[class] .. ": " .. sp[2], entries = sp[3] })
    end
end

-- default lists of a new profile: the party buffs in the All bar (for everyone: set
-- "Only for" with the cog; "Hide buffs nobody here can cast" leaves out the ones nobody casts);
-- per class every spec's buffs once, on only when on in every spec (a seal or form
-- of one spec stays off)
mod.DEFAULT_LISTS = { ALL = PartyBuffs() }
for class, specs in pairs(SPECS) do
    local list, at, onIn = {}, {}, {}
    for _, sp in ipairs(specs) do
        for _, e in ipairs(sp[3]) do
            local k = mod.EntryKey(e)
            if not at[k] then
                local c = {} for f, v in pairs(e) do if f ~= "off" then c[f] = v end end
                list[#list + 1] = c; at[k] = #list
            end
            if not e.off then onIn[k] = (onIn[k] or 0) + 1 end
        end
    end
    for _, e in ipairs(list) do
        if (onIn[mod.EntryKey(e)] or 0) < #specs then e.off = true end
    end
    mod.DEFAULT_LISTS[class] = list
end
