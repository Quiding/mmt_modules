-- MMT Disenchant Loot: settings page and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers

local function Opt(key, after)
    return function() return M.db[key] end, function(v)
        M.db[key] = v
        mod.RefreshBags()
        if after then after() end
    end
end

local function Check(col, text, key, tip)
    local g, s = Opt(key)
    return col:Check(text, g, s, tip)
end

-- "Give them to": a role or a character
local function TargetChoices()
    local t = {}
    local roles = MMT.SortedRoleNames and MMT.SortedRoleNames() or {}
    if #roles > 0 then
        t[#t + 1] = { header = true, text = "Everyone with the role" }
        for _, r in ipairs(roles) do t[#t + 1] = { value = "ROLE:" .. r, text = r } end
    end
    t[#t + 1] = { header = true, text = "Character" }
    for _, key in ipairs(MMT.SortedMembers()) do t[#t + 1] = { value = "CHAR:" .. key, text = MMT.FullDisplay(key) } end
    local cur, found = M.db.to, false
    for _, c in ipairs(t) do if c.value == cur then found = true end end
    if not found and cur then table.insert(t, 1, { value = cur, text = (cur:gsub("^%u+:", "")) .. " (missing)" }) end
    return t
end

local function ResetButton(page)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        mod.RefreshBags()
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", M.sync and -(176 + 8) or 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Puts every setting of this module back to the default of a new profile. Click twice.")
    return b
end

local function FitRow(row)
    local h = 0
    for _, r in ipairs(row) do h = math.max(h, -(tonumber(r[2].y) or -290) + 10) end
    for _, r in ipairs(row) do r[1]:SetHeight(h) end
    return h
end

local function StatusText()
    if not mod.HasPrices() then return "Auctionator isn't loaded: no disenchant values, nothing is done." end
    local plugin = mod.PluginActive()
    local bag = plugin == nil and "" or plugin and " Baganator shows the junk." or
        " Baganator: pick \"Dejunk + Disenchant Loot\" as junk plugin to see it there."
    return "Enchanter: " .. mod.EnchanterText() .. "." .. bag .. " " .. mod.AgeText() .. "."
end

local SHOW = {
    { value = "ALWAYS", text = "Always" },
    { value = "SHIFT", text = "While Shift is held" },
    { value = "CTRL", text = "While Ctrl is held" },
    { value = "ALT", text = "While Alt is held" },
    { value = "NEVER", text = "Never" },
}

M.Page = function(_, page)
    if mod.TypedSliders then mod.TypedSliders(page) end   -- click a slider's value to type it
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    ResetButton(page)

    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local TOP = H.Intro(page, "Greens go to your enchanter when disenchanting pays most, stay for the auction house when that does, else they're junk and sold. Prices from Auctionator.")

    -- Worth disenchanting ----------------------------------------------------------------------------
    local lt, L = Tile(page, 0, TOP, TILE_W, 300, "Worth Disenchanting", "Interface\\Icons\\INV_Enchant_DustStrange")
    local gq, sq = Opt("quality")
    L:Cycle("Items", {
        { value = "GREEN", text = "Green (uncommon)" },
        { value = "GREEN_BLUE", text = "Green and blue" },
    }, gq, sq)
    local gp, sp = Opt("pct")
    L:Slider("Disenchant value at least (% of vendor)", 0, 500, 10, gp, sp)
    local gm, sm = Opt("minSilver")
    L:Slider("... and at least (silver)", 0, 500, 5, gm, sm)
    Check(L, "Sell it on the auction house when that pays more", "ahOn",
        "The item's own auction price (Quality of life's \"Loot by price\" sources when that module is on, else Auctionator's) counts too: when it beats both disenchanting and the vendor by the % below, the item is neither given to the enchanter nor junk. Quality of life's \"Valuable loot to a role\" can then put it on your bank character's role.")
    local ga, sa = Opt("ahPct")
    L:Slider("... auction price at least (% of the better one)", 100, 300, 5, ga, sa)
    L:Note("Weapons and armour: their average materials at Auctionator prices.")

    -- Master loot ----------------------------------------------------------------------------------------
    local rt, R = Tile(page, X2, TOP, TILE_W, 300, "Master Loot", "Interface\\Icons\\INV_Misc_Coin_02")
    Check(R, "Give them to the enchanter", "lootOn",
        "As master looter (Loot Distribution), an item worth disenchanting goes to the enchanter below. Pawn Compare's upgrade pick comes first. When the enchanter can't take it (away, bags full), the usual rules decide.")
    local gt, st = Opt("to", function() status.Show_(StatusText()) end)
    R:Cycle("Enchanter", TargetChoices, gt, st)
    R:Note("A role: its first member in team order who can take the item.")
    local h = FitRow({ { lt, L }, { rt, R } })

    -- Junk -------------------------------------------------------------------------------------------------
    local y2 = TOP - h - 4
    local jt, J = Tile(page, 0, y2, H.PAGE_W, 120, "The Others Are Junk", "Interface\\Icons\\INV_Misc_Bag_10")
    Check(J, "Mark them as junk (Baganator)", "junkOn",
        "On every character: unbound items of the kinds above that are NOT worth disenchanting are junk - unless they are an upgrade for anyone on the team (Pawn Compare: every member's Pawn scale and gear; without Pawn Compare only this character's Pawn). Baganator shows them as junk with the junk plugin \"Dejunk + Disenchant Loot\" (Dejunk's junk plus these): choose it in Baganator's settings.")
    Check(J, "Also junk when the vendor pays more than the auction house", "vendorJunk",
        "Items of the chosen quality without a disenchant value - not weapons or armour (recipes, trade goods, ...), or their materials never scanned - are junk too when their auction price is below the vendor price. Without an auction price they are left alone.")
    Check(J, "Sell them at a vendor", "sellOn", "When a merchant window opens, these junk items are sold (Dejunk sells its own junk as before).")
    local h2 = FitRow({ { jt, J } })

    -- Tooltip / old prices ---------------------------------------------------------------------------------
    local y3 = y2 - h2 - 4
    local tt, T = Tile(page, 0, y3, TILE_W, 200, "Tooltip", "Interface\Icons\INV_Misc_Note_01")
    local gs, ss = Opt("tipShow")
    T:Cycle("Value and where it goes", SHOW, gs, ss)
    local gms, sms = Opt("matsShow")
    T:Cycle("What it disenchants into", SHOW, gms, sms)
    UI.Tooltip(T:Cycle("Money", {
        { value = "SHORT", text = "Short (1g 13s 22c)" },
        { value = "COINS", text = "Coin icons" },
        { value = "MMT", text = "Like MMT's money" },
    }, Opt("money")), "Money", "How gold amounts look in the tooltip lines and chat messages of this module.")
    local at, A = Tile(page, X2, y3, TILE_W, 200, "Old Prices", "Interface\Icons\INV_Misc_PocketWatch_01")
    Check(A, "Remind me when prices are old", "staleOn",
        "When Auctionator's newest prices (your scans, or prices taken from the team by Quality of life) are older than below: a chat line on login and at most once an hour (on the group leader only, or solo), and a red line on the item tooltips.")
    local gh, sh = Opt("staleHours", function() status.Show_(StatusText()) end)
    A:Slider("Older than (hours)", 1, 48, 1, gh, sh)
    FitRow({ { tt, T }, { at, A } })

    page.OnRefresh = function() status.Show_(StatusText()) end
end

M.Report = function(_, add)
    local d = M.db
    add(("-- Disenchant Loot %s: loot=%s active=%s to=%s quality=%s pct=%s minSilver=%s junk=%s sell=%s tip=%s/%s money=%s stale=%s/%sh ah=%s/%s%% vendorJunk=%s auctionator=%s plugin=%s"):format(
        mod.VERSION, tostring(d.lootOn), tostring(mod.LootActive()), tostring(d.to), tostring(d.quality), tostring(d.pct),
        tostring(d.minSilver), tostring(d.junkOn), tostring(d.sellOn), tostring(d.tipShow), tostring(d.matsShow), tostring(d.money),
        tostring(d.staleOn), tostring(d.staleHours), tostring(d.ahOn), tostring(d.ahPct), tostring(d.vendorJunk), tostring(mod.HasPrices()), tostring(mod.PluginActive())))
    add("enchanter: " .. mod.EnchanterText())
    add(mod.AgeText() .. (" (price time %s)"):format(mod.PriceTime() and date("%Y-%m-%d %H:%M", mod.PriceTime()) or "-"))
    local s = mod.lastSale
    if s then add(("last sale %s ago: %d items, %s"):format(MMT.Ago and MMT.Ago(s.time) or "?", s.count, mod.Money(s.value))) end
end
