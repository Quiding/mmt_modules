-- MMT Quality of life: Dejunk's junk lists and Baganator junk on Loot
-- Distribution's "Never Loot" tab (MMT.RegisterLootSkip). As master looter,
-- items they call junk are left on the corpse.
--
-- Dejunk and Baganator only say "junk" for an item in your bags (bag + slot),
-- so their saved settings are read instead (the master looter's own):
--   * Dejunk: the junk lists ("Inclusions") of this character's profile and the
--     global ones; its "not junk" lists win, profile before global, as in
--     Dejunk. Its other rules (item level, price, ...) need the bag item.
--   * Baganator: items put into its Junk category by hand, and grey items with
--     a sell price (its own junk rule) unless put into another category by
--     hand. When Baganator takes its junk from Dejunk, Dejunk's lists decide
--     first. Only items, not pets.
-- One table lookup or two per item: no loot time.

local _, mod = ...
local MMT = MMT
local M = mod.M

local function ItemID(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

-- true / false when Dejunk's lists decide, nil when the item isn't on them
function mod.DejunkJunk(id)
    local lists = mod.DejunkState and mod.DejunkState()
    if not lists or not id then return nil end
    id = tostring(id)
    local function On(k) return lists[k] ~= nil and lists[k][id] == true end
    if On("PE") then return false end
    if On("PI") then return true end
    if On("GE") then return false end
    if On("GI") then return true end
    return nil
end

function mod.BaganatorJunk(link)
    local id = ItemID(link)
    local p = id and mod.BaganatorProfile and mod.BaganatorProfile()
    if not p then return false end
    local item = "i:" .. id
    local mods = type(p.category_modifications) == "table" and p.category_modifications or {}
    for src, m in pairs(mods) do
        if type(m) == "table" and type(m.addedItems) == "table" and m.addedItems[item] then
            return src == "default_junk"   -- put into a category by hand: that one decides
        end
    end
    if p.junk_plugin == "dejunk" and (mod.AddonState("Dejunk")) then
        local dj = mod.DejunkJunk(id)
        if dj ~= nil then return dj end
    end
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, quality, _, _, _, _, _, _, _, price = pcall(GetInfo, link)
    return ok and quality == 0 and type(price) == "number" and price > 0 or false
end

local function Usable(addon)
    return function()
        if not M.enabled then return false, "Quality of life is switched off (/mmt modules)." end
        local ok, why = mod.AddonState(addon)
        if not ok then return false, why end
        return true
    end
end
local dejunkUsable, baganatorUsable = Usable("Dejunk"), Usable("Baganator")

-- installed (switched off counts: shown greyed out with the reason); not installed: not on the tab
local function Installed(addon)
    return function()
        local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
        local ok, _, _, _, _, reason = pcall(GetInfo, addon)
        return not (ok and reason == "MISSING")
    end
end

function mod.LootSkipReason(link)
    if not M.enabled then return nil end
    if M.db.lsDejunk and dejunkUsable() and mod.DejunkJunk(ItemID(link)) then return "Dejunk junk list" end
    if M.db.lsBaganator and baganatorUsable() and mod.BaganatorJunk(link) then return "Baganator junk" end
    if M.db.lsPrice and mod.PriceSkipReason then return mod.PriceSkipReason(link) end   -- LootPrice.lua
    return nil
end

if MMT.RegisterLootSkip then
    MMT.RegisterLootSkip({
        name = "QoL",
        title = "Quality of life: junk",
        skip = mod.LootSkipReason,
        options = {
            { text = "Include Dejunk's junk lists",
              tip = "Items on Dejunk's junk lists (this character's profile and the global list) are never looted; Dejunk's \"not junk\" lists win, as in Dejunk. Its other rules (item level, price, ...) only work on items in your bags, so they don't count here.\nThe master looter's own lists are used.",
              get = function() return M.db.lsDejunk end, set = function(v) M.db.lsDejunk = v end,
              usable = dejunkUsable, shown = Installed("Dejunk") },
            { text = "Include Baganator junk",
              tip = "What Baganator puts into Junk: items put there by hand, and grey items with a sell price (unless put into another category by hand). When Baganator takes its junk from Dejunk, Dejunk's lists decide first.\nThe master looter's own settings are used.",
              get = function() return M.db.lsBaganator end, set = function(v) M.db.lsBaganator = v end,
              usable = baganatorUsable, shown = Installed("Baganator") },
            { text = "Items worth too little at the auction house",
              tip = "Items whose Auctionator / FojjiCore price is below the amount set in Quality of life > Loot by price (also the quality, the fallback without a price, and more). Items a role of the team wants are looted.\nThe master looter's own prices and settings are used.",
              get = function() return M.db.lsPrice end, set = function(v) M.db.lsPrice = v end,
              usable = function()
                  if not M.enabled then return false, "Quality of life is switched off (/mmt modules)." end
                  return true
              end },
        },
    })
end
