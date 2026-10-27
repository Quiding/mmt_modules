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

mod.CASTERS = CASTERS

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
    if type(e.caster) == "string" then return e.caster end   -- a pattern's class (totem presets)
    local name = mod.BuffName(e)
    return name and Names()[name] or nil
end

-- classes present: your group, plus team members who are online (worked out
-- once per redraw: kept for half a second). who[class] = { team keys, stranger =
-- true when someone of that class who isn't in the team is in the group }
local here, who, hereTime
function mod.ClassesHere()
    -- preview: the whole team counts as here, with the classes the preview shows
    if mod.preview then
        local t = {}
        for _, key in ipairs(mod.PreviewTeam()) do t[mod.ClassOf(key) or ""] = true end
        return t, {}
    end
    if here and GetTime() - hereTime < 0.5 then return here, who end
    local t, w = {}, {}
    local function Add(class, key)
        t[class] = true
        w[class] = w[class] or {}
        if key then
            for _, k in ipairs(w[class]) do if k == key then return end end
            table.insert(w[class], key)
        else
            w[class].stranger = true
        end
    end
    local inTeam = {}
    for _, key in ipairs(MMT.SortedMembers()) do inTeam[key] = true end
    local own = MMT.PlayerFull and MMT.PlayerFull()
    if own then inTeam[own] = true end
    local units = { "player" }
    if IsInRaid() then for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else for i = 1, 4 do units[#units + 1] = "party" .. i end end
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local _, class = MMT.Safe(UnitClass, u)
            if class then
                local key = (u == "player") and own or (MMT.SplitUnit and select(3, MMT.SplitUnit(u)))
                key = key and MMT.Resolve and MMT.Resolve(key) or key
                Add(class, (key and inTeam[key]) and key or nil)
            end
        end
    end
    for _, key in ipairs(MMT.SortedMembers()) do
        if MMT.IsSelf(key) or MMT.IsOnline(key) then
            local class = mod.ClassOf(key)
            if class then Add(class, key) end
        end
    end
    here, who, hereTime = t, w, GetTime()
    return t, w
end

-- false when nobody here can cast e: no one of its class (hideNoCaster), or only ones
-- who haven't learned it (hideUnlearned, Known.lua; someone outside the team counts as able)
function mod.Castable(e)
    if not (M.db.hideNoCaster or M.db.hideUnlearned) then return true end
    local class = mod.CasterClass(e)
    if not class then return true end
    local present, w = mod.ClassesHere()
    if not present[class] then return not M.db.hideNoCaster end
    if not M.db.hideUnlearned or mod.preview or not mod.Unlearned then return true end
    local cast = w[class]
    if not cast or cast.stranger then return true end
    for _, key in ipairs(cast) do
        if not mod.Unlearned(key, e) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Blessings: one per paladin. A member can have one blessing from each paladin, so
-- with one paladin in the group only one of the blessings tracked for them can be up.
-- With "One blessing per paladin" (M.db.blessingLimit) a missing blessing doesn't
-- count while the member already has as many blessings as there are paladins here.
---------------------------------------------------------------------------
-- Might, Wisdom, Kings, Light, Sanctuary. NOT Salvation: on Forever it's its own buff ("Salvation",
-- group version "Mass Salvation"), without the one-blessing-per-paladin rule, so it stacks with them
local BLESSINGS = { 19740, 19742, 20217, 19977, 20911 }
local blessingNames, blessingsComplete
local function Blessings()
    if blessingsComplete then return blessingNames end
    blessingNames, blessingsComplete = {}, true
    for _, id in ipairs(BLESSINGS) do
        local name = mod.SpellInfo(id)
        if name then blessingNames[mod.Canonical(name)] = true else blessingsComplete = false end
    end
    return blessingNames
end
function mod.BlessingsReset() blessingNames, blessingsComplete = nil, nil end   -- KnownReset
function mod.IsBlessing(e) return e.id ~= nil and Blessings()[mod.BuffName(e) or ""] == true end

-- paladins in your group (they can only bless who they're grouped with); the preview counts its team
local paladins, paladinsTime
function mod.PaladinsHere()
    if mod.preview then
        local n = 0
        for _, key in ipairs(mod.PreviewTeam()) do if mod.ClassOf(key) == "PALADIN" then n = n + 1 end end
        return n
    end
    if paladins and GetTime() - paladinsTime < 0.5 then return paladins end
    local n = 0
    local units = { "player" }
    if IsInRaid() then for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else for i = 1, 4 do units[#units + 1] = "party" .. i end end
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local _, class = MMT.Safe(UnitClass, u)
            if class == "PALADIN" then n = n + 1 end
        end
    end
    paladins, paladinsTime = n, GetTime()
    return n
end

-- is missing blessing e on member key not expected, because they already have one from each
-- paladin here? Blessings from someone outside the group (a random) don't use up a slot.
function mod.BlessingCovered(key, e)
    if not M.db.blessingLimit or mod.preview or not mod.IsBlessing(e) then return false end
    local n = mod.PaladinsHere()
    if n < 1 then return false end
    local auras = mod.auras and mod.auras[key]
    if not auras then return false end
    local have, set = 0, Blessings()
    for name, a in pairs(auras) do if set[name] and a.group then have = have + 1 end end
    return have >= n
end
