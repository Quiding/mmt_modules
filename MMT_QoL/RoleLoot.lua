-- MMT Quality of life: valuable loot onto a role, and a Baganator category for it.
--
-- 1) An item this character loots or is traded (green, or green and blue) whose auction price is at
--    least the chosen % of its vendor price goes on a role's items - e.g. "Bank" on the
--    bank alt - through the Role items panel's own path (mod.MailAdd: shared with the
--    team), so MMT's "Mail to team" mails it there at the next mailbox, and Loot
--    Distribution hands that item to the role from then on. The auction price is the
--    one "Loot by price" uses (Auctionator / FojjiCore, its order and max age).
--    Weapons and armour with Disenchant Loot on: its verdict decides instead of the % - the
--    best of disenchanting, the vendor and the auction house (its own % for that) wins.
--    Left alone: soulbound (Bind on Pickup) items, items a role of the team already
--    wants, upgrades for someone on the team (Pawn Compare; unknown counts as an
--    upgrade), and items Disenchant Loot doesn't call worth the auction house
--    (disenchant / vendor / auction compared there: it gives them the enchanter, or junk).
-- 2) A Baganator category "MMT Role Items" holds that role's items, both ways: an item
--    put on the role shows in the category, an item put into the category (Baganator's
--    own drag or "add to category") goes on the role, and taking it out of either takes
--    it off the other. The category is made once through Baganator's own import; what
--    was in sync is remembered (M.store.rvSnap) so a change while away still counts.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CATEGORY = "MMT Role Items"
local F
local rv = { added = 0, checked = 0, toBag = 0, fromBag = 0, offBag = 0, offRole = 0 }
mod.rv = rv

local function ItemID(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

local function Info(link)
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, name, _, quality, _, _, _, _, _, _, _, sell, _, _, bind = pcall(GetInfo, link)
    if not ok or not name then return nil end
    return quality, sell or 0, bind
end

-- the role it goes on (the saved one while it exists)
function mod.RoleLootRole()
    local roles = MMT.SortedRoleNames and MMT.SortedRoleNames() or {}
    for _, r in ipairs(roles) do if r == M.db.rvRole then return r end end
    return nil
end

-- the role that has this very item on its list (by item ID, or an exact item name), or nil.
-- Broad rules (all green items, all Bind on Equip, an "All" role, ...) don't count: those
-- would take every green
local function OnAnyRole(link)
    local roles = MMT.db and MMT.db.roles
    local id = ItemID(link)
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name = GetInfo(link)
    name = type(name) == "string" and name:lower() or nil
    for role, r in pairs(type(roles) == "table" and roles or {}) do
        for _, rule in ipairs(type(r) == "table" and type(r.rules) == "table" and r.rules or {}) do
            if rule.type == "item" and ((rule.itemID and rule.itemID == id)
                or (not rule.itemID and name and type(rule.name) == "string" and rule.name:lower() == name)) then
                return role
            end
        end
    end
    return nil
end

local function TeamUpgrade(link)
    local pc = MMT.modules and MMT.modules.PawnCompare
    if not (pc and pc.enabled and type(pc.TeamUpgrades) == "function") then return false end
    local ok, keys = pcall(pc.TeamUpgrades, link)
    if not ok or keys == nil then return true end   -- can't tell: maybe someone's upgrade
    return #keys > 0
end

-- Disenchant Loot's verdict: it weighs disenchanting, the vendor and the auction house
-- (with its own % for the auction house) and the best one decides. "AH" = ours, no % of
-- our own on top; "DE" / "JUNK" = not ours (the enchanter, or junk); nil (no disenchant
-- value: not weapon or armour, materials never scanned; or Disenchant Loot off) = our %
local function DisenchantSays(link)
    local de = MMT.modules and MMT.modules.DisenchantLoot
    if not (de and de.enabled and type(de.Verdict) == "function") then return nil end
    local ok, verdict, value = pcall(de.Verdict, link)
    if not ok then return nil end
    if verdict == "DE" then return "DE", ("disenchanting is worth more (%s, Disenchant Loot)"):format(mod.Money(value or 0)) end
    if verdict == "JUNK" then return "JUNK", "the vendor pays more (Disenchant Loot)" end
    if verdict == "AH" then return "AH", ("the auction house pays most (disenchant %s, Disenchant Loot)"):format(mod.Money(value or 0)) end
end

-- does this item go on the role? true, why | false, why
function mod.RoleLootCheck(link)
    local role = mod.RoleLootRole()
    if not role then return false, "no role chosen" end
    if not ItemID(link) then return false, "not an item" end
    local quality, sell, bind = Info(link)
    if not quality then return nil, "item not loaded yet" end
    local maxQ = M.db.rvQuality == "GREEN_BLUE" and 3 or 2
    if quality < 2 or quality > maxQ then return false, "quality" end
    if bind == 1 then return false, "Bind on Pickup" end
    if sell <= 0 then return false, "no vendor price" end
    local price = mod.AuctionPrice and mod.AuctionPrice(link)
    if not price then return false, "no auction price" end
    local verdict, why = DisenchantSays(link)
    if verdict == "DE" or verdict == "JUNK" then return false, why end
    local pct = tonumber(M.db.rvPct) or 300
    if verdict ~= "AH" and price * 100 < sell * pct then
        return false, ("auction %s is below %d%% of vendor %s"):format(mod.Money(price), pct, mod.Money(sell))
    end
    local onRole = OnAnyRole(link)
    if onRole then return false, "already on the role " .. onRole end
    if TeamUpgrade(link) then return false, "an upgrade for someone on the team" end
    local text = ("auction %s = %d%% of vendor %s"):format(mod.Money(price), math.floor(price * 100 / sell), mod.Money(sell))
    if verdict == "AH" then text = text .. ", " .. why end
    return true, text, role
end

local function Consider(link, tries)
    if not mod.Active(F) then return end
    rv.checked = rv.checked + 1
    local ok, why, role = mod.RoleLootCheck(link)
    if ok == nil then
        -- item data not here yet: again in a moment
        if (tries or 0) < 5 then C_Timer.After(1, function() Consider(link, (tries or 0) + 1) end) end
        return
    end
    rv.lastLink, rv.lastWhy = link, why
    if not ok then return end
    local added = mod.MailAdd(role, link)
    if added then
        rv.added = rv.added + 1
        if M.db.rvChat then MMT.Print("Quality of life: %s goes on the role %s (%s).", link, role, why) end
        if mod.RoleBagSync then mod.RoleBagSync() end
    end
end
mod.RoleLootConsider = Consider

-- "You receive loot: %s." / "... %sx%d." -> patterns
local loots
local function LootPatterns()
    if loots then return loots end
    loots = {}
    for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE" }) do
        local s = rawget(_G, g)
        if type(s) == "string" then
            local p = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
            loots[#loots + 1] = "^" .. p .. "$"
        end
    end
    return loots
end

function mod.RoleLootChat(text)
    for _, p in ipairs(LootPatterns()) do
        local link = tostring(text):match(p)
        if link and link:find("|Hitem:") then return link end
    end
end

M:On("CHAT_MSG_LOOT", function(text)
    if not mod.Active(F) then return end
    local link = mod.RoleLootChat(text)
    if link then Consider(link) end
end)

-- items a trade gives us: no loot message for those. What the other side puts in is read
-- while the window is open (its slots are empty again by "Trade complete"); slot 7 is
-- "will not be traded"
local tradeIn = {}
local function ReadTrade()
    if not mod.Active(F) or type(GetTradeTargetItemLink) ~= "function" then return end
    tradeIn = {}
    for i = 1, 6 do
        local ok, link = pcall(GetTradeTargetItemLink, i)
        if ok and type(link) == "string" then tradeIn[#tradeIn + 1] = link end
    end
end
M:On("TRADE_SHOW", function() tradeIn = {} end)
M:On("TRADE_TARGET_ITEM_CHANGED", ReadTrade)
M:On("TRADE_ACCEPT_UPDATE", ReadTrade)
M:On("UI_INFO_MESSAGE", function(_, msg)
    if not (msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE) then return end
    local got = tradeIn
    tradeIn = {}
    if not mod.Active(F) then return end
    rv.traded = (rv.traded or 0) + #got
    for _, link in ipairs(got) do Consider(link) end
end)

---------------------------------------------------------------------------
-- Baganator category <-> the role's items
---------------------------------------------------------------------------
local function Profile() return mod.BaganatorProfile and mod.BaganatorProfile() end

local function CategorySrc(p)
    for src, c in pairs(type(p.custom_categories) == "table" and p.custom_categories or {}) do
        if type(c) == "table" and c.name == CATEGORY then return src end
    end
end

local function Refresh()
    local api = rawget(_G, "Baganator") and Baganator.API
    if not api then return end
    if api.RequestLayoutUpdate then pcall(api.RequestLayoutUpdate) end
    if api.RequestItemButtonsRefresh then pcall(api.RequestItemButtonsRefresh) end
end

-- make the category through Baganator's own import (it puts it first in the bags)
local function MakeCategory(items)
    local api = rawget(_G, "Baganator") and Baganator.API
    local E = C_EncodingUtil
    if not (api and api.ImportString and E and E.SerializeCBOR and E.CompressString and E.EncodeBase64) then return false end
    local export = { version = 3, addon = "Baganator", kind = "categories",
        categories = { { name = CATEGORY, search = "", source = "mmt_roleitems" } },
        modifications = { { source = "mmt_roleitems", items = #items > 0 and items or nil } } }
    local ok, s = pcall(function() return "BGR!1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(export))) end)
    if not ok then return false end
    rv.made = (rv.made or 0) + 1
    return pcall(api.ImportString, s, CATEGORY)
end

-- the role's item rules: [itemID] = rule index
local function RoleItems(role)
    local t = {}
    local r = role and MMT.db and type(MMT.db.roles) == "table" and MMT.db.roles[role]
    for i, rule in ipairs(type(r) == "table" and type(r.rules) == "table" and r.rules or {}) do
        if rule.type == "item" and rule.itemID then t[rule.itemID] = i end
    end
    return t
end

local function CategoryItems(p, src)
    local t = {}
    local m = type(p.category_modifications) == "table" and p.category_modifications[src]
    for k in pairs(type(m) == "table" and type(m.addedItems) == "table" and m.addedItems or {}) do
        local id = tonumber(tostring(k):match("^i:(%d+)$"))
        if id then t[id] = true end
    end
    return t
end

-- one pass: true when something changed
function mod.RoleBagSync()
    if not (mod.Active(F) and M.db.rvBag) then return false end
    local role = mod.RoleLootRole()
    local p = Profile()
    if not (role and p) then return false end
    local src = CategorySrc(p)
    local inRole = RoleItems(role)
    if not src then
        local items = {}
        for id in pairs(inRole) do items[#items + 1] = id end
        table.sort(items)
        MakeCategory(items)
        p = Profile()
        src = p and CategorySrc(p)
        if not src then rv.lastSkip = "Baganator didn't make the category"; return false end
        M.store.rvSnap = {}
        for _, id in ipairs(items) do M.store.rvSnap[id] = true end
        M.store.rvSnapRole = role
        Refresh()
        return true
    end
    local inBag = CategoryItems(p, src)
    local changed = false
    -- the category's side
    local mods = p.category_modifications
    if type(mods) ~= "table" then mods = {}; p.category_modifications = mods end
    local m = mods[src]
    if type(m) ~= "table" then m = {}; mods[src] = m end
    if type(m.addedItems) ~= "table" then m.addedItems = {} end
    local function PutInBag(id)
        -- out of any other category it was put into, so it shows in ours
        for other, om in pairs(mods) do
            if other ~= src and type(om) == "table" and type(om.addedItems) == "table" then om.addedItems["i:" .. id] = nil end
        end
        m.addedItems["i:" .. id] = true
    end
    -- another role chosen since: the category shows that role's items (no role changes)
    if M.store.rvSnapRole and M.store.rvSnapRole ~= role then
        for id in pairs(inBag) do if not inRole[id] then m.addedItems["i:" .. id] = nil end end
        for id in pairs(inRole) do if not inBag[id] then PutInBag(id) end end
        M.store.rvSnap, M.store.rvSnapRole = {}, role
        for id in pairs(inRole) do M.store.rvSnap[id] = true end
        Refresh()
        return true
    end
    -- nothing remembered yet (the category was already there): both sides joined, nothing taken off
    local first = M.store.rvSnap == nil
    local snap = M.store.rvSnap or {}
    for id in pairs(inBag) do
        if not inRole[id] then
            if snap[id] and not first then
                m.addedItems["i:" .. id] = nil        -- taken off the role: out of the category
                rv.offBag = rv.offBag + 1
            elseif mod.MailAdd(role, id) then         -- put into the category: onto the role
                rv.fromBag = rv.fromBag + 1
            end
            changed = true
        end
    end
    for id in pairs(inRole) do
        if not inBag[id] then
            if snap[id] and not first then
                local i = RoleItems(role)[id]         -- taken out of the category: off the role
                if i then mod.MailRemove(role, i); rv.offRole = rv.offRole + 1 end
            else
                PutInBag(id)                          -- put on the role: into the category
                rv.toBag = rv.toBag + 1
            end
            changed = true
        end
    end
    -- what's in sync now
    local now = {}
    local roleNow, bagNow = RoleItems(role), CategoryItems(p, src)
    for id in pairs(roleNow) do if bagNow[id] then now[id] = true end end
    M.store.rvSnap, M.store.rvSnapRole = now, role
    if changed then Refresh() end
    return changed
end

local ticker
local function Tick()
    local ok, err = pcall(mod.RoleBagSync)
    if not ok then rv.lastError = tostring(err) end
end

local function RoleChoices()
    local t = { { value = "", text = "(choose a role)" } }
    for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do t[#t + 1] = { value = r, text = r } end
    -- a saved role that's gone shows as missing
    local cur = M.db.rvRole
    if cur and cur ~= "" and not mod.RoleLootRole() then t[#t + 1] = { value = cur, text = cur .. " (missing)" } end
    return t
end

F = mod.Feature({
    key = "rvOn", icon = "INV_Misc_Coin_17", slash = "valuable", title = "Valuable loot to a role", tabText = "Valuable loot",
    checkText = "Put valuable loot on a role",
    tip = "Greens (or greens and blues) you loot that sell well at the auction house go on a role's items - e.g. your bank character's - so \"Mail to team\" sends them there.",
    notes = {
        "When this character loots or is traded a green (or blue) item whose auction price is at least the % below of its vendor price, it goes on the role you pick - the same as dropping it on the Role items panel, so the team gets the change too. At the next mailbox MMT's \"Mail to team\" mails it to whoever has the role, and Loot Distribution hands that item to the role from then on.",
        "The auction price is the one \"Loot by price\" uses (Auctionator and/or FojjiCore, in its order, with its max age). Weapons and armour with Disenchant Loot on: whichever pays most decides instead of the % - disenchanting (the enchanter), the vendor (junk) or the auction house (this role), by Disenchant Loot's own %. Left alone: Bind on Pickup items, items a role already wants, upgrades for someone on the team (Pawn Compare), and - with Disenchant Loot on - weapons and armour it doesn't call worth the auction house (it compares disenchanting, the vendor and the auction price, and shows all three on the tooltip).",
        "Baganator category: \"MMT Role Items\" shows the role's items in your bags, and works both ways - put an item into the category in Baganator and it goes on the role; take it out and it comes off the role (and the other way round). Made once, at the top of your categories; move it where you like.",
    },
    commands = {
        -- the bags now: what goes on the role, and why the others don't
        bags = function()
            if not mod.Active(F) then MMT.Print("Quality of life: Valuable loot is off.") return end
            local added, left, n = 0, {}, 0
            for bag = 0, (MMT.BAGS or 4) do
                for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local link = info and info.hyperlink
                    local q = info and info.quality
                    if link and not info.isBound and (q == 2 or q == 3) then
                        n = n + 1
                        local ok, why, role = mod.RoleLootCheck(link)
                        if ok and mod.MailAdd(role, link) then
                            added = added + 1
                            MMT.Print("  + %s on %s (%s)", link, role, why)
                        elseif not ok then
                            left[#left + 1] = ("  - %s: %s"):format(link, tostring(why))
                        end
                    end
                end
            end
            for i = 1, math.min(#left, 15) do MMT.Print(left[i]) end
            if #left > 15 then MMT.Print("  ... and %d more", #left - 15) end
            MMT.Print("Quality of life: %d green/blue unbound item(s) in the bags, %d put on the role.", n, added)
            if added > 0 then mod.RoleBagSync() end
        end,
        sync = function() MMT.Print("Quality of life: Baganator category %s.", mod.RoleBagSync() and "updated" or "already in sync (or off)") end,
    },
    OnEnable = function()
        if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(2, Tick) end
    end,
    OnDisable = function()
        if ticker then ticker:Cancel(); ticker = nil end
    end,
    Page = function(ui)
        ui.Cycle("Role", RoleChoices, "rvRole")
        ui.Cycle("Items", { { value = "GREEN", text = "Green (uncommon)" }, { value = "GREEN_BLUE", text = "Green and blue" } }, "rvQuality")
        ui.Slider("Auction price at least (% of vendor)", 100, 1000, 25, "rvPct")
        ui.Check("Baganator category \"MMT Role Items\"", "rvBag", "The role's items in a Baganator category of their own, both ways: putting an item into it puts it on the role, taking it out takes it off (and the same from the role's side). Needs Baganator.")
        ui.Check("Chat line for each item", "rvChat", "Says which looted item went on the role, and why.")
        ui.Note("Prices: the \"Loot by price\" tab's sources and max age. /mmtqol valuable bags checks your bags now and says why each item stays.")
    end,
    Report = function(add)
        add(("Valuable loot: on=%s role=%s quality=%s pct=%s bag=%s checked=%d traded=%d added=%d last=%s (%s) bag: made=%d toBag=%d fromBag=%d offBag=%d offRole=%d skip=%s error=%s"):format(
            tostring(M.db.rvOn), tostring(mod.RoleLootRole()), tostring(M.db.rvQuality), tostring(M.db.rvPct), tostring(M.db.rvBag),
            rv.checked, rv.traded or 0, rv.added, tostring(rv.lastLink), tostring(rv.lastWhy), rv.made or 0, rv.toBag, rv.fromBag, rv.offBag, rv.offRole,
            tostring(rv.lastSkip), tostring(rv.lastError)))
    end,
})
mod.RoleLootFeature = F

M:Listen("ROLES_CHANGED", function() if C_Timer then C_Timer.After(0.5, Tick) end end)
