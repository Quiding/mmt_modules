-- MMT module: Disenchant Loot.
--
-- What a green (optionally also a blue) weapon or armour piece is worth:
--   disenchant  = the materials it gives on average x their last scanned
--                 auction prices (Value.lua, prices from Auctionator)
--   vendor      = the item's sell price
-- It is "worth disenchanting" when disenchant >= vendor x M.db.pct % and
-- disenchant >= M.db.minSilver silver. Without a disenchant value (no
-- Auctionator, materials never scanned) the item is left alone everywhere.
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

mod.VERSION = "0.1.4"

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

-- "DE" (worth disenchanting) | "JUNK" (not) | nil (doesn't count / no value),
-- the disenchant value, the vendor price (copper); with nil: why, materials without a price
function mod.Verdict(link)
    if not link then return nil end
    local _, _, quality, level, _, _, _, _, _, _, sell, classID = Info(link)
    if not quality then return nil, nil, nil, "item not loaded" end
    if not QualityCounts(quality) then return nil, nil, nil, "quality" end
    if classID ~= WEAPON and classID ~= ARMOR then return nil, nil, nil, "not weapon or armour" end
    if not mod.HasPrices() then return nil, nil, sell, "Auctionator isn't loaded" end
    local de, why, missing = mod.DisenchantValue(link, classID, quality, level)
    if not de then return nil, nil, sell, why, missing end
    sell = sell or 0
    local worth = de >= sell * (M.db.pct or 100) / 100 and de >= (M.db.minSilver or 0) * 100
    return worth and "DE" or "JUNK", de, sell
end

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
    local verdict, de, sell, why, missing = mod.Verdict(link)
    if not verdict then
        local names = {}
        for _, id in ipairs(missing or {}) do names[#names + 1] = (Info(id)) or ("item " .. id) end
        MMT.Print("Disenchant Loot: %s - %s%s.", link, tostring(why),
            #names > 0 and (": " .. table.concat(names, ", ") .. " (scan the auction house)") or "")
        return
    end
    MMT.Print("Disenchant Loot: %s - disenchant %s, vendor %s: %s.", link, mod.Money(de), mod.Money(sell),
        verdict == "DE" and ("to " .. mod.EnchanterText()) or "junk")
    for _, e in ipairs(mod.Breakdown(link) or {}) do
        MMT.Print("  %.1f%%  %s %s  (%s each)", e.chance, e.min == e.max and e.min or (e.min .. "-" .. e.max),
            mod.MatName(e.id), e.price and mod.Money(e.price) or "no price")
    end
end
