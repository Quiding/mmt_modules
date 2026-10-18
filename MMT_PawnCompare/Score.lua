-- MMT Pawn Compare: item stats and scale values.
--
-- With Pawn loaded, the item's stats come from Pawn itself (same parsing as
-- Pawn's own tooltips: weapon DPS/speed, armor types, ...). Without Pawn we
-- fall back to the game's GetItemStats, mapped to Pawn's stat names; that is
-- close but not exact, and the tooltip says so.
--
-- The value calculation follows PawnGetItemValue: sum of stat * weight,
-- speed minus SpeedBaseline, a stat weighted "unusable" makes the item
-- unusable, and the total is normalized like Pawn does when the scale has a
-- normalization factor. Sockets are ignored.

local _, mod = ...
local MMT = MMT

local UNUSABLE = -1000000  -- PawnIgnoreStatValue

local SPEED_STATS = { Speed = true, MeleeSpeed = true, MainHandSpeed = true, OffHandSpeed = true,
    OneHandSpeed = true, TwoHandSpeed = true, RangedSpeed = true }
local SOCKET_STATS = { PrismaticSocket = true, RedSocket = true, YellowSocket = true, BlueSocket = true,
    MetaSocket = true, MetaSocketEffect = true, CogwheelSocket = true, ShaTouchedSocket = true }

-- GetItemStats keys -> Pawn stat names (fallback without Pawn)
local GAME_STATS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina", ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_ATTACK_POWER_SHORT = "Ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Rap",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FeralAp",
    ITEM_MOD_SPELL_POWER_SHORT = "SpellPower", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing",
    ITEM_MOD_CRIT_RATING_SHORT = "CritRating", ITEM_MOD_HIT_RATING_SHORT = "HitRating",
    ITEM_MOD_HASTE_RATING_SHORT = "HasteRating", ITEM_MOD_EXPERTISE_RATING_SHORT = "ExpertiseRating",
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = "SpellCritRating", ITEM_MOD_SPELL_HIT_RATING_SHORT = "SpellHitRating",
    ITEM_MOD_DODGE_RATING_SHORT = "DodgeRating", ITEM_MOD_PARRY_RATING_SHORT = "ParryRating",
    ITEM_MOD_BLOCK_RATING_SHORT = "BlockRating", ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DefenseRating",
    ITEM_MOD_MANA_REGENERATION_SHORT = "Mp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "Hp5",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "SpellPenetration",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Dps",
    RESISTANCE2_NAME = "FireResist", RESISTANCE3_NAME = "NatureResist", RESISTANCE4_NAME = "FrostResist",
    RESISTANCE5_NAME = "ShadowResist", RESISTANCE6_NAME = "ArcaneResist",
}

-- returns stats (Pawn stat names), exact (true when Pawn parsed them); nil while the item isn't loaded
function mod.ItemStats(link)
    if not link then return nil end
    if mod.PawnReady() and PawnGetItemData then
        local ok, item = pcall(PawnGetItemData, link)
        if ok and item and item.Stats then return item.Stats, true end
        if ok and item then return {}, true end  -- Pawn knows the item, it just has no stats
    end
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    local raw = fn and fn(link)
    if not raw then return nil end
    local stats = {}
    for k, v in pairs(raw) do
        local stat = GAME_STATS[k]
        if stat then stats[stat] = (stats[stat] or 0) + v end
    end
    return stats, false
end

-- value of an item's stats for one scale ({ values, norm }); returns value, unusable
function mod.Value(stats, scale)
    local w = scale.values
    local total = 0
    for stat, qty in pairs(stats) do
        local weight = w[stat]
        if weight and weight <= UNUSABLE then return 0, true end
        if weight and not SOCKET_STATS[stat] and type(qty) == "number" then
            if w.SpeedBaseline and SPEED_STATS[stat] then qty = qty - w.SpeedBaseline end
            total = total + qty * weight
        end
    end
    if scale.norm and scale.norm > 0 then
        local sum = 0
        for stat, weight in pairs(w) do
            if weight > 0 and not SOCKET_STATS[stat] then sum = sum + weight end
        end
        if sum > 0 then total = scale.norm * total / sum end
    end
    return total, false
end

---------------------------------------------------------------------------
-- What a member wears
---------------------------------------------------------------------------
-- own items from the game, other members' from Item Compare's stored equipment
-- (read only: MMTDB.moduleData.ItemCompare.equipment[key] = { items = {[slot] = itemString} })
function mod.HasEquipment(key)
    if MMT.IsSelf(key) then return true end
    local data = MMTDB and MMTDB.moduleData and MMTDB.moduleData.ItemCompare
    return data and data.equipment and data.equipment[key] and true or false
end

function mod.EquippedLink(key, slot)
    if MMT.IsSelf(key) then return GetInventoryItemLink("player", slot) end
    local data = MMTDB and MMTDB.moduleData and MMTDB.moduleData.ItemCompare
    local rec = data and data.equipment and data.equipment[key]
    local s = rec and rec.items and rec.items[slot]
    return s and ("item:" .. s) or nil
end
