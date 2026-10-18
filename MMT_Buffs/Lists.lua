-- MMT Buffs: tracked buff lists. An entry is { id = spellID }; matching is by
-- the spell's NAME, so every rank counts. Lists are per class (the class of
-- the member who should HAVE the buff) plus ALL, stored in M.db.lists.

local _, mod = ...

mod.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }

local function B(id) return { id = id } end
local AI, BS = 1459, 6673   -- Arcane Intellect, Battle Shout

mod.DEFAULT_LISTS = {
    WARRIOR = { B(BS) }, ROGUE = { B(BS) },
    PALADIN = { B(AI) }, HUNTER = { B(AI) }, PRIEST = { B(AI) }, SHAMAN = { B(AI) },
    MAGE = { B(AI) }, WARLOCK = { B(AI) }, DRUID = { B(AI) },
    ALL = { B(1243), B(1126) },   -- Power Word: Fortitude, Mark of the Wild
}

-- group versions count as the single-target buff (and the other way round):
-- group spell ID -> single spell ID
local GROUP = {
    [21562] = 1243,   -- Prayer of Fortitude -> Power Word: Fortitude
    [21849] = 1126,   -- Gift of the Wild -> Mark of the Wild
    [23028] = 1459,   -- Arcane Brilliance -> Arcane Intellect
    [27681] = 14752,  -- Prayer of Spirit -> Divine Spirit
    [27683] = 976,    -- Prayer of Shadow Protection -> Shadow Protection
    [25782] = 19740,  -- Greater Blessing of Might
    [25894] = 19742,  -- Greater Blessing of Wisdom
    [25898] = 20217,  -- Greater Blessing of Kings
    [25895] = 1038,   -- Greater Blessing of Salvation
    [25890] = 19977,  -- Greater Blessing of Light
    [25899] = 20911,  -- Greater Blessing of Sanctuary
}

local alias, complete   -- [group buff name] = single buff name
local function Aliases()
    if not complete then
        alias, complete = {}, true
        for group, single in pairs(GROUP) do
            local g, s = mod.SpellInfo(group), mod.SpellInfo(single)
            if g and s then alias[g] = s else complete = false end
        end
    end
    return alias
end

-- the name a buff is tracked under (group versions map to the single one)
function mod.Canonical(name)
    if not name then return nil end
    return Aliases()[name] or name
end

function mod.BuffName(e) return mod.Canonical((mod.SpellInfo(e.id))) end

-- the entry's own name for lists and tooltips
function mod.EntryName(e) return (mod.SpellInfo(e.id)) or ("Spell " .. e.id) end

function mod.EntryIcon(e)
    return mod.SpellIcon(e.id) or 134400
end

-- name, ID or spell link -> spell ID (or nil)
function mod.ParseEntry(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = tonumber(text:match("|Hspell:(%d+)") or text:match("^spell:(%d+)") or text)
    if id then return mod.SpellInfo(id) and id or nil end
    local _, _, spellID = mod.SpellInfo(text)
    return spellID
end
