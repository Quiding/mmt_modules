-- MMT Buffs: presets for the tracked lists, from Wowhead's WoW: Forever data
-- (October 2026; many buffs are raid-wide in Forever: Battle Shout, Trueshot
-- Aura, Leader of the Pack, Moonkin Aura, the totems; Salvation is its own buff).
-- Pick one in the list editor and add it to a list or replace the list with it.
--   mod.PRESETS = { { key, group = class token | "ALL", name, entries }, ... }
-- An entry is { id, off = true|nil }; buffs match by NAME (any rank, and group
-- versions like Prayer of Fortitude count, see Lists.lua).

local _, mod = ...

local function B(id) return { id = id } end
local function O(id) return { id = id, off = true } end

mod.PRESETS = {
    -- every member ------------------------------------------------------------
    { key = "ALL:RAID", group = "ALL", name = "Raid buffs (Fortitude, Mark, Kings on)", entries = {
        B(1243), B(1126), B(20217),                       -- Fortitude, Mark of the Wild, Kings
        O(1459), O(14752), O(976),                        -- Arcane Intellect, Divine Spirit, Shadow Protection
        O(19740), O(19742), O(1038),                      -- Might, Wisdom, Salvation
        O(6673), O(19506), O(17007), O(24907),            -- Battle Shout, Trueshot Aura, Leader of the Pack, Moonkin Aura
    } },
    { key = "ALL:WORLD", group = "ALL", name = "World buffs", entries = {
        B(22888), B(24425), B(16609), B(15366),           -- Rallying Cry, Spirit of Zandalar, Warchief's Blessing, Songflower
        B(22817), B(22818), B(22820), B(23768),           -- Fengus', Mol'dar's, Slip'kik's, Sayge's (Darkmoon)
    } },
    { key = "ALL:FLASKS", group = "ALL", name = "Flasks & elixirs", entries = {
        B(17626), B(17628), B(17627),                     -- Flask of the Titans / Supreme Power / Distilled Wisdom
        B(17538), B(11405), B(17539), B(3593),            -- Mongoose, Giants, Greater Arcane, Fortitude
    } },
    -- per class (the buffs that member keeps up on themselves) ---------------
    { key = "WARRIOR:REC", group = "WARRIOR", name = "Warrior: Battle Shout", entries = { B(6673) } },
    { key = "PALADIN:REC", group = "PALADIN", name = "Paladin: tank (Righteous Fury)", entries = { B(25780) } },
    { key = "PALADIN:AURAS", group = "PALADIN", name = "Paladin: auras (pick one on)", entries = { O(465), O(7294), O(19746) } },
    { key = "HUNTER:REC", group = "HUNTER", name = "Hunter: Aspect of the Hawk, Trueshot Aura", entries = { B(13165), O(19506), O(20043) } },
    { key = "PRIEST:REC", group = "PRIEST", name = "Priest: Inner Fire (Shadowform, Fear Ward off)", entries = { B(588), O(15473), O(6346), B(1459) } },
    { key = "MAGE:ICE", group = "MAGE", name = "Mage: Ice Armor", entries = { B(7302), B(1459) } },
    { key = "MAGE:MAGE", group = "MAGE", name = "Mage: Mage Armor", entries = { B(6117), B(1459) } },
    { key = "WARLOCK:REC", group = "WARLOCK", name = "Warlock: Demon Armor", entries = { B(706), O(687), B(1459) } },
    { key = "DRUID:REC", group = "DRUID", name = "Druid: Omen of Clarity (Thorns off)", entries = { B(16864), O(467), B(1459) } },
    { key = "DRUID:MOONKIN", group = "DRUID", name = "Druid: Moonkin", entries = { B(24858), B(24907), B(1459) } },
    { key = "SHAMAN:REC", group = "SHAMAN", name = "Shaman: Water Shield (Lightning Shield off)", entries = { B(408510), O(324), B(1459) } },
    { key = "ROGUE:REC", group = "ROGUE", name = "Rogue: Battle Shout", entries = { B(6673) } },
}

-- default lists of a new profile: Fortitude + Mark for everyone, the first
-- preset of each class (with Arcane Intellect for mana users)
mod.DEFAULT_LISTS = { ALL = { B(1243), B(1126) } }
for _, p in ipairs(mod.PRESETS) do
    if p.group ~= "ALL" and not mod.DEFAULT_LISTS[p.group] then
        local list = {}
        for _, e in ipairs(p.entries) do list[#list + 1] = { id = e.id, off = e.off } end
        mod.DEFAULT_LISTS[p.group] = list
    end
end
