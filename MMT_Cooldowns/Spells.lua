-- MMT Cooldowns: tracked spell / item lists and lookups.
--
-- An entry is { t = "s" (spell) | "i" (item), id = number, cd = seconds }.
-- Lists are per class (class token) plus ALL for every class, stored in the
-- profile (M.db.lists). Casts are matched by spell NAME, so any rank works;
-- items match by the name of their use spell (GetItemSpell).

local _, mod = ...

mod.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }

local function S(id, cd) return { t = "s", id = id, cd = cd } end

mod.DEFAULT_LISTS = {
    WARRIOR = { S(871, 1800), S(1719, 1800), S(20230, 1800), S(12292, 180), S(5246, 180) },
    PALADIN = { S(642, 300), S(633, 3600), S(1022, 300), S(853, 60), S(20216, 120) },
    HUNTER  = { S(3045, 300), S(19574, 120), S(5384, 30), S(19263, 300) },
    ROGUE   = { S(13750, 300), S(13877, 120), S(5277, 300), S(1856, 300), S(1766, 10) },
    PRIEST  = { S(10060, 180), S(14751, 180), S(8122, 30), S(586, 30) },
    SHAMAN  = { S(16166, 180), S(16188, 180), S(16190, 300), S(8042, 6), S(8177, 15) },
    MAGE    = { S(12051, 480), S(11958, 300), S(12043, 180), S(12042, 180), S(11129, 180), S(2139, 30) },
    WARLOCK = { S(6789, 120), S(5484, 40), S(18708, 900), S(18288, 180) },
    DRUID   = { S(29166, 360), S(17116, 180), S(20484, 1800), S(22812, 60), S(740, 300) },
    ALL     = {},
}

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
