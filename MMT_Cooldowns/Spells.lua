-- MMT Cooldowns: tracked spell / item lists and lookups.
--
-- An entry is { t = "s" (spell) | "i" (item), id = number, cd = seconds, off = true|nil }.
-- Lists are per class, race, MMT role or character plus ALL (ListKeys.lua),
-- stored in the profile (M.db.lists). Casts are matched by spell NAME, so any rank works;
-- items match by the name of their use spell (GetItemSpell).

local _, mod = ...

mod.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }

local function S(id, cd) return { t = "s", id = id, cd = cd } end
-- in the preset, but switched off until you turn it on
local function O(id, cd) return { t = "s", id = id, cd = cd, off = true } end

-- the preset of each list: the important cooldowns on, more of them off (switch
-- them on in the list editor), and every race's cooldown racials (off).
-- New profiles start with it; "Add preset entries" adds what a list misses.
mod.DEFAULT_LISTS = {
    WARRIOR = { S(871, 1800), S(1719, 1800), S(20230, 1800), S(12292, 180), S(5246, 180),
                O(12975, 600), O(18499, 30), O(2687, 60), O(1161, 600), O(676, 60), O(6552, 10),
                O(72, 12), O(100, 15), O(20252, 30) },
    PALADIN = { S(642, 300), S(633, 3600), S(1022, 300), S(853, 60), S(20216, 120),
                O(498, 300), O(1044, 20), O(20066, 60), O(20473, 30), O(2878, 30) },
    HUNTER  = { S(3045, 300), S(19574, 120), S(5384, 30), S(19263, 300),
                O(19503, 30), O(19386, 120), O(1499, 15), O(19577, 60), O(5116, 12), O(19434, 6), O(19306, 5) },
    ROGUE   = { S(13750, 300), S(13877, 120), S(5277, 300), S(1856, 300), S(1766, 10),
                O(2983, 300), O(14177, 180), O(14185, 600), O(2094, 300), O(408, 20), O(1776, 10),
                O(14183, 120), O(14278, 20), O(1725, 30) },
    PRIEST  = { S(10060, 180), S(14751, 180), S(8122, 30), S(586, 30),
                O(13908, 600), O(15487, 45), O(724, 600), O(8092, 8) },
    SHAMAN  = { S(16166, 180), S(16188, 180), S(16190, 300), S(8042, 6), S(8177, 15),
                O(20608, 3600), O(17364, 20), O(421, 6), O(8056, 6), O(8050, 6) },
    MAGE    = { S(12051, 480), S(11958, 300), S(12043, 180), S(12042, 180), S(11129, 180), S(2139, 30),
                O(12472, 600), O(11426, 30), O(122, 25), O(1953, 15), O(2136, 8), O(120, 10), O(11113, 45) },
    WARLOCK = { S(6789, 120), S(5484, 40), S(18708, 900), S(18288, 180),
                O(17877, 15), O(17962, 10), O(1122, 3600), O(603, 60) },
    DRUID   = { S(29166, 360), S(17116, 180), S(20484, 1800), S(22812, 60), S(740, 300),
                O(5211, 60), O(1850, 300), O(22842, 180), O(5209, 600), O(16914, 60), O(18562, 15), O(5229, 60) },
    ALL     = {},
    -- cooldown racials (Classic); other races (e.g. WoW: Forever's own): add them to your race's list
    ["RACE:Human"]    = { O(20600, 180) },               -- Perception
    ["RACE:Dwarf"]    = { O(20594, 180) },               -- Stoneform
    ["RACE:NightElf"] = { O(20580, 10) },                -- Shadowmeld
    ["RACE:Gnome"]    = { O(20589, 60) },                -- Escape Artist
    ["RACE:Orc"]      = { O(20572, 120) },               -- Blood Fury
    ["RACE:Scourge"]  = { O(7744, 120), O(20577, 120) }, -- Will of the Forsaken, Cannibalize
    ["RACE:Tauren"]   = { O(20549, 120) },               -- War Stomp
    ["RACE:Troll"]    = { O(20554, 180) },               -- Berserking
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
