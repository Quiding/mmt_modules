-- MMT Buffs: who can cast a buff. With "Hide buffs nobody here can cast" (Bars
-- tab, M.db.hideNoCaster) a tracked buff only shows when someone of its class
-- is in your group or online in your team - Fortitude needs a priest, Mark of
-- the Wild a druid. Buffs not in this table (world buffs, flasks, food, items)
-- always show. Matched by the buff's name, so every rank and the group
-- versions (Prayer of Fortitude, Greater Blessings) count.

local _, mod = ...
local MMT = MMT
local M = mod.M

-- only buffs cast on OTHERS: a self-buff (Inner Fire, Righteous Fury, Aspect of the
-- Hawk, armors, forms) is always "castable" by whoever has it, so it isn't listed
local CASTERS = {
    PRIEST = { 1243, 21562, 14752, 27681, 976, 27683, 6346, 10060 },
        -- Fortitude, Prayer of Fortitude, Divine Spirit, Prayer of Spirit, Shadow Protection,
        -- Prayer of Shadow Protection, Fear Ward, Power Infusion
    DRUID = { 1126, 21849, 467, 17007, 24907 },
        -- Mark / Gift of the Wild, Thorns, Leader of the Pack, Moonkin Aura
    MAGE = { 1459, 23028, 604, 1008 },
        -- Arcane Intellect / Brilliance, Dampen / Amplify Magic
    PALADIN = { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890, 20911, 25899,
        465, 7294, 19746, 19876, 19888, 19891, 20218 },
        -- Blessings and Greater Blessings (Might, Wisdom, Kings, Salvation, Light, Sanctuary),
        -- Devotion / Retribution / Concentration / Shadow / Frost / Fire Resistance Aura, Sanctity Aura
    WARRIOR = { 6673 },               -- Battle Shout
    HUNTER = { 19506, 20043 },        -- Trueshot Aura, Aspect of the Wild
    WARLOCK = { 6307 },               -- Blood Pact (imp)
}

local byName, complete   -- [buff name] = class
local function Names()
    if complete then return byName end
    byName, complete = {}, true
    for class, ids in pairs(CASTERS) do
        for _, id in ipairs(ids) do
            local name = mod.SpellInfo(id)
            if name then byName[mod.Canonical(name)] = class else complete = false end
        end
    end
    return byName
end

-- the class that casts buff entry e, or nil (anyone / unknown)
function mod.CasterClass(e)
    local name = mod.BuffName(e)
    return name and Names()[name] or nil
end

-- classes present: your group, plus team members who are online (worked out
-- once per redraw: kept for half a second)
local here, hereTime
function mod.ClassesHere()
    if here and GetTime() - hereTime < 0.5 then return here end
    local t = {}
    local units = { "player" }
    if IsInRaid() then for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else for i = 1, 4 do units[#units + 1] = "party" .. i end end
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local _, class = MMT.Safe(UnitClass, u)
            if class then t[class] = true end
        end
    end
    for _, key in ipairs(MMT.SortedMembers()) do
        if MMT.IsSelf(key) or MMT.IsOnline(key) then
            local class = mod.ClassOf(key)
            if class then t[class] = true end
        end
    end
    here, hereTime = t, GetTime()
    return t
end

-- false when the option is on and nobody here can cast e
function mod.Castable(e)
    if not M.db.hideNoCaster or mod.preview then return true end
    local class = mod.CasterClass(e)
    if not class then return true end
    return mod.ClassesHere()[class] == true
end
