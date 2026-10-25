-- MMT Buffs: tracked buff lists. An entry is { id = spellID }; matching is by
-- the spell's NAME, so every rank counts. Lists are per class (the class of
-- the member who should HAVE the buff) plus ALL, stored in M.db.lists.

local _, mod = ...

-- the ALL list is the "All bar" here (ListKeys.lua names it)
mod.ALL_LABEL = "All bar"

mod.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }

-- the presets and the default lists are in Presets.lua

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

-- A name pattern entry { name = "Seal of *" } (a "*" anywhere, any text there,
-- case ignored) counts ANY buff whose name matches: the icon shows the one that
-- is up. Ordinary entries are { id = spellID }.
function mod.IsPattern(e)
    return type(e.name) == "string" and e.name:find("*", 1, true) ~= nil
end

local compiled = {}
local function Compile(text)
    local p = compiled[text]
    if not p then
        p = "^" .. text:lower():gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
        compiled[text] = p
    end
    return p
end

-- does buff name `name` match pattern entry e?
function mod.Matches(e, name)
    return type(name) == "string" and name:lower():find(Compile(e.name)) ~= nil
end

function mod.BuffName(e)
    if mod.IsPattern(e) then return e.name end
    return mod.Canonical((mod.SpellInfo(e.id)))
end

-- the entry's own name for lists and tooltips
function mod.EntryName(e)
    if mod.IsPattern(e) then return e.name end
    return (mod.SpellInfo(e.id)) or ("Spell " .. e.id)
end

-- the spell's icon, else by its name, else the icon the buff itself had when it was
-- last seen on someone (kept account-wide), else the "?" placeholder
function mod.EntryIcon(e)
    if mod.IsPattern(e) then
        -- the icon of a matching buff seen before (alphabetically first, so it stays put)
        local best
        for name, icon in pairs(mod.M.store and mod.M.store.icons or {}) do
            if mod.Matches(e, name) and (not best or name < best[1]) then best = { name, icon } end
        end
        return best and best[2] or 134400
    end
    local icon, generic = mod.SpellIconAny(e.id)
    if icon then return icon end
    local seen = mod.M.store and mod.M.store.icons
    local name = mod.SpellInfo(e.id)
    if seen and name then
        icon = seen[name] or seen[mod.Canonical(name)]
        if icon then return icon end
    end
    return generic or 134400
end

-- remembers the icon a buff has (from the auras scanned on group members)
function mod.SeeIcon(name, icon)
    if not (name and icon) or MMT.IsSecret(icon) then return end
    local M = mod.M
    M.store.icons = M.store.icons or {}
    M.store.icons[name] = icon
end

-- "Seal of *" -> the pattern (trimmed), or nil when text has no "*"
function mod.ParsePattern(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not text:find("*", 1, true) or text:gsub("[%*%s]", "") == "" or #text > 60 then return nil end
    return text
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
