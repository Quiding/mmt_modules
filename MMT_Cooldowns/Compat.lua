-- Spell, cooldown and aura calls for both API generations. WoW: Forever runs
-- on the modern client: GetSpellInfo / GetSpellCooldown / UnitBuff don't
-- exist there (C_Spell / C_UnitAuras do), and some values are "secret"
-- (unreadable for addons, e.g. cooldowns in combat). MMT_Cooldowns and
-- MMT_Buffs ship the same copy of this file (KEEP BOTH IDENTICAL).

local _, mod = ...
local MMT = MMT

local function Clean(v)
    if v == nil or MMT.IsSecret(v) then return nil end
    return v
end

-- spell ID or name -> name, icon, spellID (nil if unknown)
function mod.SpellInfo(spell)
    if spell == nil then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, i = pcall(C_Spell.GetSpellInfo, spell)
        if ok and type(i) == "table" then return Clean(i.name), Clean(i.iconID), Clean(i.spellID) end
        return nil
    end
    if GetSpellInfo then
        local name, _, icon, _, _, _, id = GetSpellInfo(spell)
        return name, icon, id
    end
end

function mod.SpellIcon(spell)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spell)
        if ok and Clean(t) then return t end
    end
    if GetSpellTexture then return GetSpellTexture(spell) end
    return (select(2, mod.SpellInfo(spell)))
end

-- the generic WoW-logo icon of "Teaches <spell>" trainer spells (they share the
-- real spell's name, e.g. 864 "Seal of Righteousness"): no real icon
mod.GENERIC_ICON = 136235

-- an icon even when the game has none for that spell ID (some ranks / variants show
-- the "?" placeholder, trainer spells the WoW logo): by the spell's name, which finds
-- any rank the character knows. Returns icon, or nil and the generic one as second value
function mod.SpellIconAny(spell)
    local icon = mod.SpellIcon(spell)
    if icon and icon ~= mod.GENERIC_ICON then return icon end
    local name = mod.SpellInfo(spell)
    local byName = name and mod.SpellIcon(name)
    if byName and byName ~= mod.GENERIC_ICON then return byName end
    return nil, icon or byName
end

-- start, duration, enabled for a spell the player knows; nil if not known;
-- the string "secret" when the game hides the values right now
function mod.SpellCooldown(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, c = pcall(C_Spell.GetSpellCooldown, spell)
        if not ok or type(c) ~= "table" then return nil end
        if MMT.IsSecret(c.startTime) or MMT.IsSecret(c.duration) or MMT.IsSecret(c.isEnabled) then return "secret" end
        return c.startTime, c.duration, c.isEnabled
    end
    if GetSpellCooldown then return GetSpellCooldown(spell) end
end

-- i-th buff of a unit: name, icon, count, duration, expirationTime;
-- nil after the last one; the string "secret" when the game hides it
function mod.Buff(unit, i)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
        if not ok or type(a) ~= "table" then return nil end
        if MMT.IsSecret(a.name) then return "secret" end
        return a.name, Clean(a.icon), Clean(a.applications), Clean(a.duration), Clean(a.expirationTime)
    end
    if UnitBuff then
        local name, icon, count, _, duration, expiration = UnitBuff(unit, i)
        return name, icon, count, duration, expiration
    end
end

-- the same for harmful auras (some self buffs are debuffs, e.g. Death Wish)
function mod.Debuff(unit, i)
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        local ok, a = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, i)
        if not ok or type(a) ~= "table" then return nil end
        if MMT.IsSecret(a.name) then return "secret" end
        return a.name, Clean(a.icon), Clean(a.applications), Clean(a.duration), Clean(a.expirationTime)
    end
    if UnitDebuff then
        local name, icon, count, _, duration, expiration = UnitDebuff(unit, i)
        return name, icon, count, duration, expiration
    end
end

-- item ID -> name and ID of its use spell
function mod.ItemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if fn then return fn(id) end
end
