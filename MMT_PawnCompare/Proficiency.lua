-- MMT Pawn Compare: which classes can use an item at all (weapon and armor
-- skills a class can learn, as in Classic). Members who never can (a bow
-- for a shaman, plate for a mage) get no Pawn value. Mail and plate count as
-- usable for the classes that learn them at 40, also before that.

local _, mod = ...
local MMT = MMT

local WEAPON, ARMOR = 2, 4   -- Enum.ItemClass

-- weapon subclasses: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST  = { 4, 10, 15, 19 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID   = { 4, 5, 10, 13, 15 },
}
-- armor subclasses: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem
-- (0 = rings, necks, trinkets, off-hand items: everyone)
local ARMORS = {
    WARRIOR = { 1, 2, 3, 4, 6 },
    PALADIN = { 1, 2, 3, 4, 6, 7 },
    HUNTER  = { 1, 2, 3 },
    ROGUE   = { 1, 2 },
    PRIEST  = { 1 },
    SHAMAN  = { 1, 2, 3, 6, 9 },
    MAGE    = { 1 },
    WARLOCK = { 1 },
    DRUID   = { 1, 2, 8 },
}
local WEAPON_SET, ARMOR_SET = {}, {}
for class, list in pairs(WEAPONS) do
    WEAPON_SET[class] = {}
    for _, s in ipairs(list) do WEAPON_SET[class][s] = true end
end
for class, list in pairs(ARMORS) do
    ARMOR_SET[class] = { [0] = true }
    for _, s in ipairs(list) do ARMOR_SET[class][s] = true end
end
local EVERYONE_WEAPON = { [14] = true, [20] = true }   -- miscellaneous, fishing poles

-- class token of a team member (or nil)
function mod.ClassOf(key)
    if MMT.IsSelf(key) then
        local _, class = UnitClass("player")
        return class
    end
    local s = MMT.status and MMT.status[key]
    if s and s.class then return s.class end
    local m = MMT.db and MMT.db.team and MMT.db.team[key]
    return m and m.class
end

-- false when key's class can never use the item; true otherwise (also when unknown)
function mod.CanUse(key, link)
    local class = mod.ClassOf(key)
    if not class or not WEAPON_SET[class] then return true end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn or type(link) ~= "string" then return true end
    local ok, _, _, _, _, _, classID, subID = pcall(fn, link)
    if not ok or MMT.IsSecret(classID) then return true end
    if classID == WEAPON then return EVERYONE_WEAPON[subID] or WEAPON_SET[class][subID] or false end
    if classID == ARMOR then return ARMOR_SET[class][subID] or false end
    return true
end

---------------------------------------------------------------------------
-- Gear a member wouldn't wear (setting specFit): their class can, but
--   - not yet: mail for hunters / shamans and plate for warriors / paladins before 40;
--   - not with the spec of the scale (by its name): no shield for Enhancement, Fury,
--     Arms or Retribution, no two-hander for Fury or Protection.
---------------------------------------------------------------------------
local MAIL, PLATE, SHIELD = 3, 4, 6
local LATE_ARMOR = { HUNTER = MAIL, SHAMAN = MAIL, WARRIOR = PLATE, PALADIN = PLATE }
local LATE_LEVEL = 40

local function Info(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn or type(link) ~= "string" then return nil end
    local ok, _, _, _, loc, _, classID, subID = pcall(fn, link)
    if not ok or MMT.IsSecret(classID) then return nil end
    return classID, subID, loc
end

local function LevelOf(key)
    if MMT.IsSelf(key) then return UnitLevel("player") end
    local s = MMT.status and MMT.status[key]
    return s and tonumber(s.level)
end

-- false (and why) when the member can't wear it at their level yet; true otherwise / unknown
function mod.CanWearNow(key, link)
    local late = LATE_ARMOR[mod.ClassOf(key) or ""]
    if not late then return true end
    local classID, subID = Info(link)
    if classID ~= ARMOR or subID ~= late then return true end
    local lvl = LevelOf(key)
    if lvl and lvl < LATE_LEVEL then
        return false, ("%s from level %d"):format(late == MAIL and "mail" or "plate", LATE_LEVEL)
    end
    return true
end

-- what each spec leaves out, by words in the scale's name ("Warrior: Fury", "Shaman: Enhancement")
local SPECS = {
    { words = { "enhance", "enh" }, shield = true },
    { words = { "fury" }, shield = true, twoHand = true },
    { words = { "arms" }, shield = true },
    { words = { "retribution", "ret" }, shield = true },
    { words = { "protection", "prot", "tank" }, twoHand = true },
}

local function SpecOf(scale)
    local name = type(scale) == "table" and scale.name or scale
    if type(name) ~= "string" then return nil end
    name = name:lower()
    for _, spec in ipairs(SPECS) do
        for _, w in ipairs(spec.words) do
            -- a whole word (or the start of one): "ret" not inside "Ferret"
            if name:find("%f[%a]" .. w) then return spec end
        end
    end
end

-- why the scale's spec wouldn't use the item (nil: it would)
function mod.SpecSkips(scale, link)
    local spec = SpecOf(scale)
    if not spec then return nil end
    local classID, subID, loc = Info(link)
    if spec.shield and classID == ARMOR and subID == SHIELD then return "no shield for this spec" end
    if spec.twoHand and loc == "INVTYPE_2HWEAPON" then return "no two-hander for this spec" end
    return nil
end

-- both together, for one member and one scale: nil, or why it is left out
function mod.WouldntWear(key, link, scale)
    local M = mod.M
    if not (M and M.db and M.db.specFit) then return nil end
    local ok, why = mod.CanWearNow(key, link)
    if not ok then return why end
    return scale and mod.SpecSkips(scale, link) or nil
end
