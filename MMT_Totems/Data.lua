-- MMT Totems: totem data (from EMA Totems, plus Mana Tide Totem).
-- Elements, the totems of each element (spell IDs, any rank: casting is by
-- name) and how long a totem lasts (for totems we only see being cast).

local _, mod = ...

-- order of the slots on a bar (as in EMA Totems)
mod.ELEMENTS = { "Fire", "Air", "Water", "Earth" }
-- GetTotemInfo() slot of each element
mod.TOTEM_SLOT = { Fire = 1, Earth = 2, Water = 3, Air = 4 }
mod.SLOT_ELEMENT = { "Fire", "Earth", "Water", "Air" }

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

-- name -> { id, element }, built when the spell names are available
local byName
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

-- totems of an element that exist in this game version: { id, ... }
function mod.ElementTotems(element)
    local out = {}
    for _, id in ipairs(mod.TOTEMS[element] or {}) do
        if mod.SpellInfo(id) then out[#out + 1] = id end
    end
    return out
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
