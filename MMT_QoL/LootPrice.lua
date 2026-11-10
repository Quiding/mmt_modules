-- MMT Quality of life: never loot what's worth too little at the auction house.
--
-- One more rule on Loot Distribution's Never Loot tab (with Dejunk / Baganator junk,
-- LootSkip.lua): as master looter, an item whose auction price is below the amount you pick
-- is left on the corpse. The price: Auctionator's (its API, the master looter's own data -
-- with Quality of life's Auctionator prices that is the team's last scan) and FojjiCore
-- Professions' last scan, in the order you choose; a price older than "max age" doesn't count.
-- No price (never on the auction house, soulbound, too old): the fallback decides - loot it,
-- go by the vendor price, or leave it.
-- Never left: items above the quality you pick, items a role of the team wants (MMT's role
-- items), and anything Loot Distribution's own "loot anyway when worth at least" keeps.

local _, mod = ...
local MMT = MMT
local M = mod.M
local CALLER = "MMT Quality of life"

local function ItemID(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

-- "1g 20s", "45s", "8c"
function mod.Money(c)
    c = math.floor(tonumber(c) or 0)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. "g" end
    if s > 0 then t[#t + 1] = s .. "s" end
    if cp > 0 or #t == 0 then t[#t + 1] = cp .. "c" end
    return table.concat(t, " ")
end

-- "1g 20s 5c", "50s", "1g20s", "2.5g", "75c" -> copper; a plain number is gold ("2" = 2g, "0.5" = 50s).
-- nil when it can't be read
function mod.ParseMoney(text)
    local t = tostring(text or ""):lower():gsub(",", "."):match("^%s*(.-)%s*$")
    if t == "" then return nil end
    local plain = tonumber(t)
    if plain then return plain >= 0 and math.floor(plain * 10000 + 0.5) or nil end
    local total, n = 0, 0
    local rest = t:gsub("(%d+%.?%d*)%s*([gsc])", function(num, unit)
        n = n + 1
        total = total + tonumber(num) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        return ""
    end)
    if n == 0 or rest:find("%S") then return nil end
    return math.floor(total + 0.5)
end

-- Auctionator: price (copper), age (days; nil = unknown)
function mod.AuctionatorPrice(link)
    local a = rawget(_G, "Auctionator")
    local api = type(a) == "table" and a.API and a.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
    if not ok or type(price) ~= "number" or price <= 0 then return nil end
    local age
    if api.GetAuctionAgeByItemLink then
        local ok2, d = pcall(api.GetAuctionAgeByItemLink, CALLER, link)
        if ok2 and type(d) == "number" then age = d end
    end
    return price, age
end

-- FojjiCore Professions' scan: price (copper), age (days)
function mod.FojjiPrice(link)
    local ns = rawget(_G, "FojjiCoreNS")
    local a = type(ns) == "table" and ns.Auctions
    if not (type(a) == "table" and type(a.Store) == "function") then return nil end
    local ok, s = pcall(a.Store)
    local id = ItemID(link)
    local e = ok and type(s) == "table" and type(s.items) == "table" and id and s.items[id]
    if type(e) ~= "table" or type(e.min) ~= "number" or e.min <= 0 then return nil end
    local age = tonumber(e.t) and math.max(0, (time() - e.t) / 86400) or nil
    return e.min, age
end

local SOURCES = {
    AUCTIONATOR = { { "lpAuctionator", mod.AuctionatorPrice, "Auctionator" }, { "lpFojji", mod.FojjiPrice, "FojjiCore" } },
    FOJJI = { { "lpFojji", mod.FojjiPrice, "FojjiCore" }, { "lpAuctionator", mod.AuctionatorPrice, "Auctionator" } },
}

-- the item's auction price by the settings: copper, where from; nil when there is none
function mod.AuctionPrice(link)
    local maxAge = tonumber(M.db.lpAge) or 0
    local found = {}
    for _, src in ipairs(SOURCES[M.db.lpOrder] or SOURCES.AUCTIONATOR) do
        if M.db[src[1]] then
            local price, age = src[2](link)
            if price and not (maxAge > 0 and age and age > maxAge) then
                found[#found + 1] = { price = price, age = age, from = src[3] }
            end
        end
    end
    if #found == 0 then return nil end
    if M.db.lpOrder == "NEWEST" then
        table.sort(found, function(a, b) return (a.age or 999) < (b.age or 999) end)
    end
    return found[1].price, found[1].from
end
SOURCES.NEWEST = SOURCES.AUCTIONATOR

local function VendorPrice(link)
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(GetInfo, link)
    if ok and type(price) == "number" then return price end
end

-- how many make a full stack (1 for items that don't stack)
local function StackSize(link)
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, _, _, _, _, _, stack = pcall(GetInfo, link)
    if ok and type(stack) == "number" and stack > 1 then return stack end
    return 1
end

local function Quality(link)
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, q = pcall(GetInfo, link)
    if ok and type(q) == "number" then return q end
end

-- a reason to leave the item, or nil
function mod.PriceSkipReason(link)
    if not (M.enabled and M.db.lsPrice) or not ItemID(link) then return nil end
    local q = Quality(link)
    if q == nil or q > (tonumber(M.db.lpQuality) or 1) then return nil end   -- unknown yet / better: looted
    if M.db.lpRoles and MMT.MembersForItem then
        local ok, keys = pcall(MMT.MembersForItem, link)
        if ok and type(keys) == "table" and #keys > 0 then return nil end     -- a role of the team wants it
    end
    local min = tonumber(M.db.lpMin) or 0
    -- stackable items: a full stack's worth against the amount
    local n = M.db.lpStack and StackSize(link) or 1
    local each = n > 1 and (" for a stack of %d"):format(n) or ""
    local price, from = mod.AuctionPrice(link)
    if price then
        if price * n < min then return ("worth %s%s at the auction house (%s), below %s"):format(mod.Money(price * n), each, from, mod.Money(min)) end
        return nil
    end
    local fb = M.db.lpFallback
    if fb == "LEAVE" then return "no auction price" end
    if fb == "VENDOR" then
        local v = VendorPrice(link)
        if v and v * n < min then return ("no auction price, vendor %s%s below %s"):format(mod.Money(v * n), each, mod.Money(min)) end
    end
    return nil
end

local amountBox
local F = mod.Feature({
    key = "lsPrice", icon = "INV_Misc_Coin_04", title = "Never loot by auction price", tabText = "Loot by price",
    checkText = "Never loot items worth too little",
    tip = "As master looter, items whose auction price is below the amount are left on the corpse (Loot Distribution's Never Loot tab). Prices from Auctionator and FojjiCore Professions.",
    notes = {
        "One more rule on Loot Distribution's Never Loot tab, next to Dejunk and Baganator junk. It works when you are the master looter (your prices are used).",
        "The price: Auctionator's (with \"Auctionator prices\" on, the team's last scan) and FojjiCore Professions' last scan, in the order you pick. Newest: whichever was seen on the auction house more recently.",
        "No price (never seen on the auction house, soulbound, older than the max age): the fallback decides - loot it, go by the vendor price, or leave it.",
        "Never left: items above the quality you pick, items one of the team's roles wants (MMT's role items), and items Loot Distribution's \"Loot anyway when worth at least\" keeps.",
        "Hold the mouse over an item: Loot Distribution's tooltip line says when the team never loots it, and why.",
    },
    Refresh = function()
        if amountBox and not amountBox:HasFocus() then amountBox:SetText(mod.Money(M.db.lpMin)) end
    end,
    Page = function(ui)
        -- the amount: any gold / silver / copper
        local col = ui.col
        local label = MMT.UI.Label(col.parent, "Leave items worth less than")
        col:Add(label, 16)
        local function Take(box)
            local c = mod.ParseMoney(box:GetText())
            if c then
                M.db.lpMin = c
                if ui.status then ui.status.Show_(("Loot by price: items worth less than %s are left."):format(mod.Money(c))) end
            elseif ui.status then
                ui.status.Show_("Loot by price: write the amount like 1g 20s, 50s, 75c or 2.5g.", true)
            end
            box:SetText(mod.Money(M.db.lpMin))
        end
        amountBox = MMT.UI.EditBox(col.parent, col.width, "e.g. 1g 20s", function(_, box) Take(box); box:ClearFocus() end)
        amountBox:HookScript("OnEditFocusLost", function(box) Take(box) end)
        amountBox:SetText(mod.Money(M.db.lpMin))
        MMT.UI.Tooltip(amountBox, "Leave items worth less than",
            "One item's auction price below this: left on the corpse. Gold, silver and copper: 1g 20s, 50s, 75c, 1g20s5c - or a plain number of gold (2.5 = 2g 50s). Enter or click away to keep it.")
        col:Add(amountBox, MMT.UI.ROW + 4)
        ui.Cycle("Only for", {
            { value = 0, text = "Poor (grey) items" }, { value = 1, text = "Up to Common (white)" },
            { value = 2, text = "Up to Uncommon (green)" }, { value = 3, text = "Up to Rare (blue)" },
        }, "lpQuality")
        ui.Check("Auctionator prices", "lpAuctionator", "The price Auctionator has for the item (its last scan, or the team's with Quality of life's Auctionator prices).")
        ui.Check("FojjiCore Professions prices", "lpFojji", "The price of FojjiCore Professions' last auction scan.")
        ui.Cycle("When both have one", {
            { value = "AUCTIONATOR", text = "Auctionator first" }, { value = "FOJJI", text = "FojjiCore first" },
            { value = "NEWEST", text = "The newest" },
        }, "lpOrder")
        ui.Cycle("Prices count for", {
            { value = 0, text = "Any age" }, { value = 3, text = "3 days" }, { value = 7, text = "7 days" },
            { value = 14, text = "14 days" }, { value = 30, text = "30 days" },
        }, "lpAge")
        ui.Cycle("No auction price", {
            { value = "LOOT", text = "Loot it" }, { value = "VENDOR", text = "Go by the vendor price" },
            { value = "LEAVE", text = "Leave it" },
        }, "lpFallback")
        ui.Check("Stackable items: a full stack's price", "lpStack", "Items that stack (cloth, herbs, ...) count a full stack's worth (the price x the stack size, e.g. 20) against the amount, not one item's - like Loot Distribution's own \"a full stack's price\" for its \"Loot anyway\" amount.")
        ui.Check("Loot anyway when a role wants it", "lpRoles", "Items on a role of the team (MMT's role items, the Role items panel) are always looted.")
    end,
    Report = function(add)
        add(("Loot by price: on=%s stack=%s min=%s quality<=%s auctionator=%s fojji=%s order=%s age=%s fallback=%s roles=%s"):format(
            tostring(M.db.lsPrice), tostring(M.db.lpStack), mod.Money(M.db.lpMin), tostring(M.db.lpQuality), tostring(M.db.lpAuctionator),
            tostring(M.db.lpFojji), tostring(M.db.lpOrder), tostring(M.db.lpAge), tostring(M.db.lpFallback), tostring(M.db.lpRoles)))
    end,
})
mod.PriceFeature = F
