-- MMT Disenchant Loot: the disenchant value of an item.
--
-- value = sum over the possible materials of chance x count x auction price.
-- Chances by item class (weapon / armour), quality and item level: Auctionator's
-- classic table (Auctionator.Constants.DisenchantingProbability) when it is
-- loaded, else the same classic data below (levels 5-65). Auctionator's own
-- disenchant API isn't used: on Forever it can run its retail code, which only
-- knows items from Warlords of Draenor on (no value for any classic item).
-- Prices: Auctionator.API.v1.GetAuctionPriceByItemID. A lesser essence counts as
-- a third of the greater one when that is cheaper (they convert 3:1).
-- A material without a price: no value (mod.DisenchantValue returns nil, and the
-- materials that miss one).

local _, mod = ...

local CALLER = "MMT Disenchant Loot"
local WEAPON, ARMOR = 2, 4

-- rows: { low, high, chance %, count, itemID, chance %, count, itemID, ... }
local GREEN_ARMOR = {
    {5,15,40,1,10940,40,2,10940,10,1,10938,10,2,10938},
    {16,20,37.5,2,10940,37.5,3,10940,10,1,10939,10,2,10939,5,1,10978},
    {21,25,25,4,10940,25,5,10940,25,6,10940,7.5,1,10998,7.5,2,10998,10,1,10978},
    {26,30,37.5,1,11083,37.5,2,11083,10,1,11082,10,2,11082,5,1,11084},
    {31,35,18.75,2,11083,18.75,3,11083,18.75,4,11083,18.75,5,11083,10,1,11134,10,2,11134,5,1,11138},
    {36,40,37.5,1,11137,37.5,2,11137,10,1,11135,10,2,11135,5,1,11139},
    {41,45,18.75,2,11137,18.75,3,11137,18.75,4,11137,18.75,5,11137,10,1,11174,10,2,11174,5,1,11177},
    {46,50,37.5,1,11176,37.5,2,11176,10,1,11175,10,2,11175,5,1,11178},
    {51,55,18.75,2,11176,18.75,3,11176,18.75,4,11176,18.75,5,11176,10,1,16202,10,2,16202,5,1,14343},
    {56,60,37.5,1,16204,37.5,2,16204,10,1,16203,10,2,16203,5,1,14344},
    {61,65,18.75,2,16204,18.75,3,16204,18.75,4,16204,18.75,5,16204,10,2,16203,10,3,16203,5,1,14344},
}
local GREEN_WEAPON = {
    {6,15,10,1,10940,10,2,10940,40,1,10938,40,2,10938},
    {16,20,10,2,10940,10,3,10940,37.5,1,10939,37.5,2,10939,5,1,10978},
    {21,25,5,4,10940,5,5,10940,5,6,10940,37.5,1,10939,37.5,2,10939,10,1,10978},
    {26,30,10,1,11083,10,2,11083,37.5,1,10939,37.5,2,10939,5,1,11084},
    {31,35,5,2,11083,5,3,11083,5,4,11083,5,5,11083,37.5,1,11134,37.5,2,11134,5,1,11138},
    {36,40,10,1,11137,10,2,11137,37.5,1,11135,37.5,2,11135,5,1,11139},
    {41,45,5,2,11137,5,3,11137,5,4,11137,5,5,11137,37.5,1,11174,37.5,2,11174,5,1,11177},
    {46,50,10,1,11176,10,2,11176,37.5,1,11175,37.5,2,11175,5,1,11178},
    {51,55,5.5,2,11176,5.5,3,11176,5.5,4,11176,5.5,5,11176,37.5,1,16202,37.5,2,16202,5,1,14343},
    {56,60,11,1,16204,11,2,16204,37.5,1,16203,37.5,2,16203,5,1,14344},
    {61,65,5.5,2,16204,5.5,3,16204,5.5,4,16204,5.5,5,16204,37.5,2,16203,37.5,3,16203,5,1,14344},
}
local BLUE = {
    {11,25,100,1,10978}, {26,30,100,1,11084}, {31,35,100,1,11138}, {36,40,100,1,11139},
    {41,45,100,1,11177}, {46,50,100,1,11178}, {51,55,100,1,14343}, {56,65,99.5,1,14344,0.5,1,20725},
}
local BUILT_IN = {
    [ARMOR] = { [2] = GREEN_ARMOR, [3] = BLUE },
    [WEAPON] = { [2] = GREEN_WEAPON, [3] = BLUE },
}
mod.BUILT_IN = BUILT_IN

-- lesser essence -> greater (3 lesser = 1 greater)
local LESSER = { [10938] = 10939, [10998] = 11082, [11134] = 11135, [11174] = 11175, [16202] = 16203 }

local function Auctionator1()
    local A = rawget(_G, "Auctionator")
    return A and A.API and A.API.v1
end

function mod.HasPrices()
    local api = Auctionator1()
    return api and type(api.GetAuctionPriceByItemID) == "function" or false
end

local function Price(id)
    local api = Auctionator1()
    if not api then return nil end
    local ok, p = pcall(api.GetAuctionPriceByItemID, CALLER, id)
    if ok and type(p) == "number" and p > 0 then return p end
    return nil
end

local function MatPrice(id)
    local p = Price(id)
    local greater = LESSER[id]
    local g = greater and Price(greater)
    if g and (not p or g / 3 < p) then return math.floor(g / 3) end
    return p
end
mod.MatPrice = MatPrice

local function Rows(classID, quality)
    local A = rawget(_G, "Auctionator")
    local t = A and A.Constants and A.Constants.DisenchantingProbability
    local rows = t and t[classID] and t[classID][quality]
    if type(rows) == "table" and #rows > 0 then return rows end
    return BUILT_IN[classID] and BUILT_IN[classID][quality]
end

local function ItemLevel(link, fallback)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or rawget(_G, "GetDetailedItemLevelInfo")
    if f then
        local ok, lvl = pcall(f, link)
        if ok and type(lvl) == "number" and lvl > 0 then return lvl end
    end
    return fallback
end

-- value in copper, or nil, why, { itemIDs without a price }
function mod.DisenchantValue(link, classID, quality, baseLevel)
    local rows = Rows(classID, quality)
    if not rows then return nil, "can't be disenchanted" end
    local lvl = ItemLevel(link, baseLevel)
    if not lvl then return nil, "item level unknown" end
    local row
    for _, r in ipairs(rows) do
        if lvl >= r[1] and lvl <= r[2] then row = r break end
    end
    if not row then return nil, ("no disenchant data for item level %d"):format(lvl) end
    local value, missing, seen = 0, {}, {}
    for x = 3, #row, 3 do
        local chance, count, id = row[x], row[x + 1], row[x + 2]
        if chance > 0 then
            local p = MatPrice(id)
            if p then
                value = value + chance / 100 * count * p
            elseif not seen[id] then
                seen[id] = true
                missing[#missing + 1] = id
            end
        end
    end
    if #missing > 0 then return nil, "no auction price for its materials", missing end
    return math.floor(value), nil, nil, lvl
end
