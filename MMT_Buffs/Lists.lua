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

function mod.BuffName(e) return (mod.SpellInfo(e.id)) end

function mod.EntryName(e) return mod.BuffName(e) or ("Spell " .. e.id) end

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
