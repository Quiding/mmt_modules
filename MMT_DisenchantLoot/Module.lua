-- MMT module: Disenchant Loot.
--
-- What a green (optionally also a blue) weapon or armour piece is worth:
--   disenchant  = the materials it gives on average x their last scanned
--                 auction prices (Value.lua, prices from Auctionator)
--   vendor      = the item's sell price
-- It is "worth disenchanting" when disenchant >= vendor x M.db.pct % and
-- disenchant >= M.db.minSilver silver. Without a disenchant value (no
-- Auctionator, materials never scanned) the item is left alone everywhere.
--   auction     = the item's own auction price (Quality of life's "Loot by price"
--                 sources and max age when that module is on, else Auctionator's).
-- When that is at least M.db.ahPct % of the better of the two (ahOn), the item
-- is worth more on the auction house: "AH" - not to the enchanter, not junk
-- (Quality of life's "Valuable loot to a role" can put it on the bank's role).
-- Items without a disenchant value - not weapon or armour (recipes, trade goods), or
-- materials never scanned - are junk when their auction price is below the vendor
-- price (vendorJunk): the vendor pays the most.
--
--   Module.lua   the value check and the master loot part: Loot Distribution's
--                MMT.RegisterLootChooser hook gives items worth disenchanting
--                to the enchanter (a character or the first member of a role
--                that can take it). Other items go by the usual rules (roles,
--                round robin). Pawn Compare's upgrade pick comes first
--                (OptionalDeps: it registers before us).
--   Junk.lua     every character: unbound items in the bags that are NOT worth
--                disenchanting are junk - shown by Baganator through the junk
--                plugin "Dejunk + Disenchant Loot" (Dejunk's junk plus these)
--                and sold at a vendor. Never an upgrade Pawn sees.
--   Settings.lua settings page, debug report

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.1.8"

local M = MMT.NewModule({
    name = "DisenchantLoot",
    title = "Disenchant Loot",
    description = "Greens worth more as disenchant materials go to your enchanter; the others become junk and are sold. Prices from Auctionator.",
    sync = true,
    defaults = {
        lootOn    = true,              -- master looter: items worth disenchanting to the enchanter
        to        = "ROLE:Enchanter",  -- CHAR:<team key> | ROLE:<role name>
        quality   = "GREEN",           -- GREEN | GREEN_BLUE
        pct       = 100,               -- disenchant value >= vendor price x pct %
        minSilver = 0,                 -- ... and >= this many silver
        junkOn    = true,              -- the others are junk (Baganator plugin)
        sellOn    = true,              -- ... and sold at a vendor
        tipShow   = "ALWAYS",          -- tooltip value line: ALWAYS | SHIFT | CTRL | ALT | NEVER
        matsShow  = "SHIFT",           -- tooltip materials (chance, count, price): same choices
        money     = "SHORT",           -- SHORT (1g 13s 22c) | COINS (coin icons) | MMT (MMT's money format)
        staleOn   = true,              -- remind when Auctionator's prices are old (chat + tooltip)
        staleHours = 8,
        ahOn      = true,              -- the item's own auction price counts too: sell it there when that's best
        ahPct     = 110,               -- ... when it is at least this % of disenchant / vendor (the auction house takes 5%)
        vendorJunk = true,             -- no disenchant value (not gear, ...): junk when the auction price is below the vendor price
    },
})
mod.M = M

local WEAPON, ARMOR = 2, 4

local function Info(link)
    local getInfo = MMT.ItemInfo or GetItemInfo
    return getInfo(link)
end

-- the item's quality counts?
local function QualityCounts(quality)
    if quality == 2 then return true end
    return quality == 3 and M.db.quality == "GREEN_BLUE"
end

-- the item's own auction price (copper) or nil: Quality of life's (its sources, order and
-- max age) when that module is on, else Auctionator's
function mod.AuctionValue(link)
    local q = MMT.modules and MMT.modules.QoL
    if q and q.enabled and type(q.AuctionPrice) == "function" then
        local ok, p = pcall(q.AuctionPrice, link)
        if ok then return type(p) == "number" and p > 0 and p or nil end
    end
    local A = rawget(_G, "Auctionator")
    local api = A and A.API and A.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, p = pcall(api.GetAuctionPriceByItemLink, "MMT Disenchant Loot", link)
    if ok and type(p) == "number" and p > 0 then return p end
end

-- "DE" (worth disenchanting) | "JUNK" (not) | "AH" (worth more on the auction house) |
-- nil (doesn't count / no value), the disenchant value, the vendor price (copper);
-- with nil: why, materials without a price; last the auction price (or nil)
function mod.Verdict(link)
    if not link then return nil end
    local _, _, quality, level, _, _, _, _, _, _, sell, classID = Info(link)
    if not quality then return nil, nil, nil, "item not loaded" end
    if not QualityCounts(quality) then return nil, nil, nil, "quality" end
    sell = sell or 0
    local gear = classID == WEAPON or classID == ARMOR
    local de, why, missing
    if not gear then why = "not weapon or armour"
    elseif not mod.HasPrices() then why = "Auctionator isn't loaded"
    else de, why, missing = mod.DisenchantValue(link, classID, quality, level) end
    if not de then
        -- no disenchant value: the vendor against the auction house
        local ah = M.db.vendorJunk and sell > 0 and mod.AuctionValue(link) or nil
        if ah and ah < sell then return "JUNK", nil, sell, nil, nil, ah end
        return nil, nil, sell, why, missing, ah
    end
    local ah = M.db.ahOn and mod.AuctionValue(link) or nil
    if ah and ah * 100 >= math.max(de, sell) * (M.db.ahPct or 110) then return "AH", de, sell, nil, nil, ah end
    local worth = de >= sell * (M.db.pct or 100) / 100 and de >= (M.db.minSilver or 0) * 100
    return worth and "DE" or "JUNK", de, sell, nil, nil, ah
end
-- for other modules (Quality of life's "Valuable loot to a role")
M.Verdict = function(link) return mod.Verdict(link) end

function mod.Money(copper)
    copper = math.floor(copper or 0)
    local how = M.db.money
    if how == "COINS" and GetCoinTextureString then return GetCoinTextureString(copper) end
    if how == "MMT" and MMT.FormatMoney then return MMT.FormatMoney(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = ("%d|cffffd700g|r"):format(g) end
    if s > 0 or (g > 0 and c > 0) then parts[#parts + 1] = ("%d|cffc7c7cfs|r"):format(s) end
    if c > 0 or #parts == 0 then parts[#parts + 1] = ("%d|cffeda55fc|r"):format(c) end
    return table.concat(parts, " ")
end

-- "Disenchant 1g / vendor 50s / auction 1g 20s" (the ones known; lower = "disenchant ...")
function mod.ValuesText(de, sell, ah, lower)
    local t = {}
    if de then t[#t + 1] = "disenchant " .. mod.Money(de) end
    if sell then t[#t + 1] = "vendor " .. mod.Money(sell) end
    if ah then t[#t + 1] = "auction " .. mod.Money(ah) end
    local s = table.concat(t, lower and ", " or " / ")
    return lower and s or (s:gsub("^%l", string.upper))
end

-- where the item goes, for texts: "to Enchanter role (...)" / "junk" / "auction house"
function mod.WhereText(verdict, plain)
    local t, c
    if verdict == "DE" then t, c = "to " .. mod.EnchanterText(), "66ccff"
    elseif verdict == "AH" then t, c = "auction house", "66ff66"
    else t, c = "junk", "999999" end
    return plain and t or ("|cff%s%s|r"):format(c, t)
end

---------------------------------------------------------------------------
-- The enchanter
---------------------------------------------------------------------------
local function HasRole(key, role)
    for _, r in ipairs(MMT.MemberRoleList and MMT.MemberRoleList(key) or {}) do
        if r == role then return true end
    end
    return false
end

-- the enchanter among candidates (team order), nil when none can take it
function mod.Enchanter(candidates)
    local to = M.db.to or ""
    local char = to:match("^CHAR:(.+)$")
    local role = to:match("^ROLE:(.+)$")
    for _, key in ipairs(candidates) do
        if (char and key == char) or (role and HasRole(key, role)) then return key end
    end
    return nil
end

-- who the setting names, for texts: "Calashan" / "Enchanter role (Calashan, ...)"
function mod.EnchanterText()
    local to = M.db.to or ""
    local char = to:match("^CHAR:(.+)$")
    if char then return MMT.FirstName(char) end
    local role = to:match("^ROLE:(.+)$")
    if not role then return "nobody" end
    local names = {}
    for _, key in ipairs(MMT.SortedMembers()) do
        if HasRole(key, role) then names[#names + 1] = MMT.FirstName(key) end
    end
    return ("%s role (%s)"):format(role, #names > 0 and table.concat(names, ", ") or "nobody has it")
end

---------------------------------------------------------------------------
-- Loot Distribution's hook
---------------------------------------------------------------------------
function mod.LootActive()
    return M.enabled and M.db.lootOn and mod.HasPrices() or false
end

function mod.Choose(link, candidates, info)
    if info and info.isQuest then return nil end
    local verdict, de, sell, why = mod.Verdict(link)
    if verdict ~= "DE" then
        M:Debug("loot %s: %s", tostring(link), verdict and "not worth disenchanting" or tostring(why))
        return nil
    end
    local key = mod.Enchanter(candidates)
    if not key then
        M:Debug("loot %s: worth disenchanting, but no enchanter can take it now", tostring(link))
        return nil
    end
    return key, ("Disenchant: %s mats vs %s vendor"):format(mod.Money(de), mod.Money(sell))
end

local registered = false
function mod.RegisterLoot()
    if registered then return true end
    if type(MMT.RegisterLootChooser) ~= "function" then return false end
    MMT.RegisterLootChooser({
        name = "DisenchantLoot",
        title = "Disenchant Loot (to the enchanter)",
        active = mod.LootActive,
        choose = mod.Choose,
    })
    registered = true
    return true
end
mod.RegisterLoot()

SLASH_MMTDISENCHANT1 = "/mmtde"
SlashCmdList.MMTDISENCHANT = function(msg)
    local link = msg and msg:match("|Hitem:.-|h.-|h") and msg:match("(|c%x+|Hitem:.-|h|r)") or (msg ~= "" and msg) or nil
    if not link then
        MMT.Print("Disenchant Loot: /mmtde <shift-click an item> shows what it is worth. Settings: /mmt > Disenchant Loot.")
        MMT.ToggleConfig("DisenchantLoot")
        return
    end
    local verdict, de, sell, why, missing, ah = mod.Verdict(link)
    if not verdict then
        local names = {}
        for _, id in ipairs(missing or {}) do names[#names + 1] = (Info(id)) or ("item " .. id) end
        MMT.Print("Disenchant Loot: %s - %s%s.", link, tostring(why),
            #names > 0 and (": " .. table.concat(names, ", ") .. " (scan the auction house)") or "")
        return
    end
    MMT.Print("Disenchant Loot: %s - %s: %s.", link, mod.ValuesText(de, sell, ah, true), mod.WhereText(verdict, true))
    for _, e in ipairs(mod.Breakdown(link) or {}) do
        MMT.Print("  %.1f%%  %s %s  (%s each)", e.chance, e.min == e.max and e.min or (e.min .. "-" .. e.max),
            mod.MatName(e.id), e.price and mod.Money(e.price) or "no price")
    end
end
