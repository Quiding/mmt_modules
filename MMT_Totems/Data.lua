-- MMT Totems: totem data (from EMA Totems, plus Mana Tide Totem).
-- Elements, the totems of each element (spell IDs, any rank: casting is by
-- name) and how long a totem lasts (for totems we only see being cast).

local _, mod = ...

-- order of the slots on a bar (as in EMA Totems)
mod.ELEMENTS = { "Fire", "Air", "Water", "Earth" }
-- GetTotemInfo() slot of each element
mod.TOTEM_SLOT = { Fire = 1, Earth = 2, Water = 3, Air = 4 }
mod.SLOT_ELEMENT = { "Fire", "Earth", "Water", "Air" }
-- the item each element needs in the bags (Classic)
mod.TOTEM_ITEM = { Earth = 5175, Fire = 5176, Water = 5177, Air = 5178 }

mod.TOTEMS = {
    Fire  = { 3599, 8190, 1535, 8227, 8181, 30706, 2894 },
    Air   = { 8512, 8835, 10595, 15107, 25908, 8177, 6495, 3738 },
    Water = { 5394, 5675, 16190, 8184, 8166, 8170 },
    Earth = { 8075, 8071, 2484, 5730, 8143, 2062 },
}

-- seconds, by totem name (English names; other clients fall back to 120)
local DURATION = {
    ["Searing Totem"] = 55, ["Magma Totem"] = 20, ["Fire Nova Totem"] = 5, ["Flametongue Totem"] = 120,
    ["Frost Resistance Totem"] = 120, ["Totem of Wrath"] = 120, ["Fire Elemental Totem"] = 120,
    ["Strength of Earth Totem"] = 120, ["Stoneskin Totem"] = 120, ["Earthbind Totem"] = 45,
    ["Stoneclaw Totem"] = 15, ["Earth Elemental Totem"] = 120, ["Tremor Totem"] = 120,
    ["Healing Stream Totem"] = 120, ["Mana Spring Totem"] = 120, ["Mana Tide Totem"] = 12,
    ["Fire Resistance Totem"] = 120, ["Poison Cleansing Totem"] = 120, ["Disease Cleansing Totem"] = 120,
    ["Windfury Totem"] = 120, ["Grace of Air Totem"] = 120, ["Wrath of Air Totem"] = 120,
    ["Nature Resistance Totem"] = 120, ["Windwall Totem"] = 120, ["Grounding Totem"] = 45,
    ["Sentry Totem"] = 300, ["Tranquil Air Totem"] = 120,
}

mod.RECALL = { ["Totemic Recall"] = true, ["Totemic Call"] = true }
mod.DEFAULT_SEQUENCE = "Fire, Air, Water, Earth"
mod.PRESET_ICON = "Interface\\Icons\\Spell_Totem_WardOfDraining"

-- spell data is lazy on this client: names of spells this character never used can be
-- nil until asked for (a warrior's client then had no totems to choose for a shaman).
-- mod.LoadTotemData() asks for every totem; SPELL_DATA_LOAD_RESULT rebuilds the lookup.
local isTotem = {}
for _, list in pairs(mod.TOTEMS) do for _, id in ipairs(list) do isTotem[id] = true end end

function mod.LoadTotemData()
    if not (C_Spell and C_Spell.RequestLoadSpellData) then return 0 end
    local n = 0
    for id in pairs(isTotem) do
        if not mod.SpellInfo(id) then pcall(C_Spell.RequestLoadSpellData, id); n = n + 1 end
    end
    return n
end

-- name -> { id, element }, built when the spell names are available
local byName
local reloadQueued = false
function mod.TotemDataArrived(id, ok)
    if not isTotem[tonumber(id) or 0] or ok == false then return end
    byName = nil
    if reloadQueued then return end
    reloadQueued = true
    C_Timer.After(0.5, function()
        reloadQueued = false
        if mod.M.enabled then mod.Refresh() end
    end)
end

local function Names()
    if not byName then
        byName = {}
        for element, list in pairs(mod.TOTEMS) do
            for _, id in ipairs(list) do
                local name = mod.SpellInfo(id)
                if name then byName[name] = { id = id, element = element } end
            end
        end
    end
    return byName
end

-- totem name -> spell ID, element (nil if not a totem)
function mod.TotemByName(name)
    local t = name and Names()[name]
    if t then return t.id, t.element end
end

function mod.TotemDuration(name) return DURATION[name] or 120 end

function mod.TotemName(id) return id and id ~= 0 and (mod.SpellInfo(id)) or nil end

function mod.TotemIcon(id) return id and id ~= 0 and mod.SpellIcon(id) or nil end

-- totems of an element that exist in this game version: { id, ... }; with a
-- key only those that member has learned (Known.lua), plus keep (the current
-- choice) even if not learned
function mod.ElementTotems(element, key, keep)
    local out = {}
    for _, id in ipairs(mod.TOTEMS[element] or {}) do
        if mod.SpellInfo(id) and (not key or id == keep or mod.KnowsTotem(key, id)) then out[#out + 1] = id end
    end
    return out
end

-- for the sequence editor: all four elements, the sequence's first, then the
-- ones left out of it; used[element] = true for those in the sequence
function mod.SequenceOrder(text)
    local order, used = {}, {}
    for _, el in ipairs(mod.ParseSequence(text)) do order[#order + 1] = el; used[el] = true end
    for _, el in ipairs(mod.ELEMENTS) do if not used[el] then order[#order + 1] = el end end
    return order, used
end

-- back to text: the used elements in order (all left out -> the default)
function mod.SequenceText(order, used)
    local t = {}
    for _, el in ipairs(order) do if used[el] then t[#t + 1] = el end end
    return #t > 0 and table.concat(t, ", ") or mod.DEFAULT_SEQUENCE
end

-- "Fire, Air, Water, Earth" -> { "Fire", "Air", ... } (unknown words skipped)
function mod.ParseSequence(text)
    local out, seen = {}, {}
    for word in (text or ""):gmatch("[^,%s]+") do
        local el = word:sub(1, 1):upper() .. word:sub(2):lower()
        if mod.TOTEMS[el] and not seen[el] then seen[el] = true; out[#out + 1] = el end
    end
    return out
end
