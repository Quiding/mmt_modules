-- MMT Cooldowns: tracked spell / item lists and lookups.
--
-- An entry is { t = "s" (spell) | "i" (item), id = number, cd = seconds, off = true|nil }.
-- Lists are per class, race, MMT role or character plus ALL (ListKeys.lua),
-- stored in the profile (M.db.lists). Casts are matched by spell NAME, so any rank works;
-- items match by the name of their use spell (GetItemSpell).

local _, mod = ...

mod.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }

-- the presets and the default lists are in Presets.lua

-- spells whose cooldown starts when their buff is used up, not on the cast
local AFTER_BUFF_IDS = { 16188, 17116, 16166, 12043, 14751 }

function mod.EntryKey(e) return e.t .. e.id end

function mod.SpellName(id)
    local name = mod.SpellInfo(id)
    return name
end

function mod.ItemName(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return fn and (fn(id)) or nil
end

-- name of the spell an entry casts, nil if not cached yet
function mod.CastName(e)
    if e.t == "s" then return mod.SpellName(e.id) end
    return (mod.ItemSpell(e.id))
end

function mod.EntryName(e)
    if e.t == "s" then return mod.SpellName(e.id) or ("Spell " .. e.id) end
    return mod.ItemName(e.id) or ("Item " .. e.id)
end

function mod.EntryIcon(e)
    if e.t == "s" then
        return mod.SpellIcon(e.id) or 134400
    end
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local icon = fn and fn(e.id)
    if not icon then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        icon = inst and select(5, inst(e.id))
    end
    return icon or 134400
end

local afterBuff
function mod.IsAfterBuff(name)
    if not afterBuff then
        afterBuff = {}
        for _, id in ipairs(AFTER_BUFF_IDS) do
            local n = mod.SpellName(id)
            if n then afterBuff[n] = true end
        end
    end
    return name and afterBuff[name] or false
end

-- base cooldown in seconds of a spell or of an item's use spell, or nil
function mod.BaseCooldown(t, id)
    local spellID = id
    if t == "i" then
        local _, sid = mod.ItemSpell(id)
        spellID = sid
    end
    if spellID and GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(spellID)
        if ms and ms > 0 then return ms / 1000 end
    end
end

-- text typed or linked into the add box -> t, id (or nil)
function mod.ParseEntry(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = text:match("|Hspell:(%d+)") or text:match("^spell:(%d+)")
    if id then return "s", tonumber(id) end
    id = text:match("|Hitem:(%d+)") or text:match("^item:(%d+)")
    if id then return "i", tonumber(id) end
    local n = tonumber(text)
    if n then
        if mod.SpellInfo(n) then return "s", n end
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if inst and inst(n) then return "i", n end
        return nil
    end
    local _, _, spellID = mod.SpellInfo(text)
    if spellID then return "s", spellID end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link
    if fn then link = select(2, fn(text)) end
    id = link and link:match("item:(%d+)")
    if id then return "i", tonumber(id) end
    return nil
end
