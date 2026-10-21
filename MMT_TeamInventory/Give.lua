-- MMT Team Inventory: planned gifts. In the team bags ("Whole team, by
-- character", Bags tab) drag an item from one character onto another: it
-- moves there and glows. The next time those two trade, the giver's client
-- puts it into the trade window (after the core's own role items). Trades are
-- never accepted automatically. When the trade completes, what was handed
-- over comes off the plan.
--
--   M.store.gives[from][to][itemID] = { n = count, t = server time }
--   (n = 0 is kept a while as "cancelled / done", so an older copy on a
--   client that was offline can't bring it back: the newest t wins)
--   TIVG:<itemID>:<n>:<t>:<from>:<to>   one plan, to the team; whispered to a
--                                       member the first time they're seen online

local _, mod = ...
local MMT = MMT
local M = mod.M

local KEEP_DONE = 7 * 24 * 3600   -- cancelled / done entries are forgotten after a week

local function Now() return (GetServerTime and GetServerTime()) or time() end

function mod.Gives()
    M.store.gives = M.store.gives or {}
    return M.store.gives
end

local function Get(from, to, id)
    local t = mod.Gives()[from]
    t = t and t[to]
    return t and t[id]
end

-- stores one plan if it is newer than ours; true when it changed
local function Store(from, to, id, n, t)
    local cur = Get(from, to, id)
    if cur and cur.t and cur.t > t then return false end
    local g = mod.Gives()
    g[from] = g[from] or {}
    g[from][to] = g[from][to] or {}
    g[from][to][id] = { n = n, t = t }
    return true
end

local function Encode(from, to, id, e)
    return ("TIVG:%d:%d:%d:%s:%s"):format(id, e.n, e.t, from, to)
end

-- plan (or change / cancel with n = 0) a gift and tell the team
function mod.SetGive(from, to, id, n)
    if not (from and to and id) or from == to then return end
    n = math.max(0, math.floor(tonumber(n) or 0))
    local cur = Get(from, to, id)
    -- the same second twice (drag, then cancel at once): still the newer one
    local t = math.max(Now(), (cur and cur.t or 0) + 1)
    Store(from, to, id, n, t)
    MMT.SendToTeam(Encode(from, to, id, Get(from, to, id)), true)
    if mod.RefreshBags then mod.RefreshBags() end
end

-- how many of an item a character has planned to give away (all receivers)
function mod.PlannedOut(from, id)
    local sum = 0
    for _, items in pairs(mod.Gives()[from] or {}) do
        local e = items[id]
        if e then sum = sum + e.n end
    end
    return sum
end

-- { { from, id, n }, ... } planned for a character, sorted
function mod.PlannedIn(to)
    local list = {}
    for from, tos in pairs(mod.Gives()) do
        for id, e in pairs(tos[to] or {}) do
            if e.n > 0 then list[#list + 1] = { from = from, id = id, n = e.n } end
        end
    end
    table.sort(list, function(a, b)
        if a.from ~= b.from then return a.from < b.from end
        return a.id < b.id
    end)
    return list
end

-- { { to, id, n }, ... } a character has planned to give, sorted
function mod.PlannedOutList(from)
    local list = {}
    for to, items in pairs(mod.Gives()[from] or {}) do
        for id, e in pairs(items) do
            if e.n > 0 then list[#list + 1] = { to = to, id = id, n = e.n } end
        end
    end
    table.sort(list, function(a, b)
        if a.to ~= b.to then return a.to < b.to end
        return a.id < b.id
    end)
    return list
end

-- who has to trade whom: { { from, to, items = { { id, n }, ... } }, ... }
function mod.GiftPairs()
    local list = {}
    for from, tos in pairs(mod.Gives()) do
        for to, items in pairs(tos) do
            local p = { from = from, to = to, items = {} }
            for id, e in pairs(items) do
                if e.n > 0 then p.items[#p.items + 1] = { id = id, n = e.n } end
            end
            if #p.items > 0 then
                table.sort(p.items, function(a, b) return a.id < b.id end)
                list[#list + 1] = p
            end
        end
    end
    table.sort(list, function(a, b)
        if a.from ~= b.from then return a.from < b.from end
        return a.to < b.to
    end)
    return list
end

local function Prune()
    local old = Now() - KEEP_DONE
    for from, tos in pairs(mod.Gives()) do
        for to, items in pairs(tos) do
            for id, e in pairs(items) do
                if e.n == 0 and (e.t or 0) < old then items[id] = nil end
            end
            if next(items) == nil then tos[to] = nil end
        end
        if next(tos) == nil then mod.Gives()[from] = nil end
    end
end

---------------------------------------------------------------------------
-- Team messages
---------------------------------------------------------------------------
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local id, n, t, from, to = text:match("^TIVG:(%d+):(%d+):(%d+):([^:]+):([^:]+)$")
    if not id then return end
    if Store(from, to, tonumber(id), tonumber(n), tonumber(t)) and mod.RefreshBags then mod.RefreshBags() end
end)

-- the first time a member is seen online: whisper them every plan they give or get
local told = {}
M:Listen("XP_RECEIVED", function(key, sender)
    if MMT.IsSelf(key) or told[key] then return end
    told[key] = true
    Prune()
    for from, tos in pairs(mod.Gives()) do
        for to, items in pairs(tos) do
            if from == key or to == key then
                for id, e in pairs(items) do MMT.SendAddon(Encode(from, to, id, e), "WHISPER", sender) end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Trade window
---------------------------------------------------------------------------
local C = C_Container or {}
local MAX_SLOTS = MAX_TRADABLE_ITEMS or 6
local tradeOpen, partner, token = false, nil, 0
local lastTrade   -- { partner, items = { [itemID] = n } }: what our side of the trade held

local function ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- { [itemID] = count } on our side of the trade
local function InTrade()
    local t = {}
    for s = 1, MAX_SLOTS do
        local id = ItemID(MMT.Safe(GetTradePlayerItemLink, s))
        if id then
            local _, _, n = MMT.Safe(GetTradePlayerItemInfo, s)
            t[id] = (t[id] or 0) + (tonumber(n) or 1)
        end
    end
    return t
end

local function FreeSlot()
    for s = 1, MAX_SLOTS do
        if not MMT.Safe(GetTradePlayerItemLink, s) then return s end
    end
end

-- the trade partner's team key (any way the game shows the name)
local function Partner()
    local names = {}
    local n, r = MMT.Safe(UnitFullName, "NPC")
    if n then
        if r and r ~= "" then names[#names + 1] = n .. "-" .. r end
        names[#names + 1] = n
    end
    local fs = TradeFrameRecipientNameText
    local shown = fs and fs:GetText()
    if shown and shown ~= "" then names[#names + 1] = shown end
    for _, name in ipairs(names) do
        if not MMT.IsSecret(name) then
            local key = MMT.Resolve and MMT.Resolve(name)
            if key then return key end
        end
    end
end

-- the bag stacks to hand over: { { bag, slot, split = n or nil, id }, ... }
-- also returns the counts that couldn't be found (soulbound / not in the bags)
local function Steps(plans, already)
    local steps, short = {}, {}
    for id, want in pairs(plans) do
        want = want - (already[id] or 0)
        if want > 0 then
            local stacks = {}
            for _, bag in ipairs(mod.BAG_INDEXES) do
                local num = C.GetContainerNumSlots and MMT.Safe(C.GetContainerNumSlots, bag) or 0
                for slot = 1, num do
                    local info = C.GetContainerItemInfo and MMT.Safe(C.GetContainerItemInfo, bag, slot)
                    if type(info) == "table" and info.itemID == id and not info.isBound and not info.isLocked then
                        stacks[#stacks + 1] = { bag = bag, slot = slot, n = info.stackCount or 1 }
                    end
                end
            end
            -- big stacks first: fewer trade slots
            table.sort(stacks, function(a, b) return a.n > b.n end)
            for _, s in ipairs(stacks) do
                if want <= 0 then break end
                steps[#steps + 1] = { bag = s.bag, slot = s.slot, id = id, split = (s.n > want) and want or nil }
                want = want - math.min(s.n, want)
            end
            if want > 0 then short[id] = want end
        end
    end
    table.sort(steps, function(a, b) return a.id < b.id end)
    return steps, short
end

local function ItemName(id)
    local name = MMT.Safe((C_Item and C_Item.GetItemNameByID) or GetItemInfo, id)
    return name or ("item " .. id)
end

-- puts this character's planned gifts for the partner into the trade window
function mod.FillTrade(manual)
    if not tradeOpen then return 0 end
    local own = MMT.PlayerFull()
    partner = partner or Partner()
    if not (own and partner) then
        if manual then MMT.Print("Team Inventory: the trade partner isn't in the team.") end
        return 0
    end
    local plans = {}
    for id, e in pairs((mod.Gives()[own] or {})[partner] or {}) do
        if e.n > 0 then plans[id] = e.n end
    end
    if next(plans) == nil then
        if manual then MMT.Print("Team Inventory: nothing planned for %s.", MMT.FullDisplay(partner)) end
        return 0
    end
    local steps, short = Steps(plans, InTrade())
    for id, n in pairs(short) do
        MMT.Print("Team Inventory: %d x %s for %s isn't in your bags (or is soulbound).", n, ItemName(id), MMT.FullDisplay(partner))
    end
    token = token + 1
    local mine = token
    for i, st in ipairs(steps) do
        C_Timer.After(0.3 * (i - 1), function()
            if mine ~= token or not tradeOpen then return end
            local free = FreeSlot()
            if not free then return end
            ClearCursor()
            if st.split then C.SplitContainerItem(st.bag, st.slot, st.split)
            else C.PickupContainerItem(st.bag, st.slot) end
            if CursorHasItem() then ClickTradeButton(free) end
            if CursorHasItem() then ClearCursor() end
        end)
    end
    if #steps > 0 then
        MMT.Print("Team Inventory: %d planned stack(s) for %s go into the trade.", #steps, MMT.FullDisplay(partner))
    end
    return #steps
end

-- what our side holds, read while the trade is open (it is empty again once it completed)
local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, e)
    if not tradeOpen then return end
    acc = acc + e
    if acc < 0.25 then return end
    acc = 0
    lastTrade = { partner = partner, items = InTrade() }
end)

-- a button under the trade window while something is planned for the partner:
-- fills it again (or for the first time, with the setting off)
local button
local function ShowButton()
    if not TradeFrame then return end
    if not button then
        button = MMT.UI.Button(TradeFrame, 150, "Planned items", function() mod.FillTrade(true) end)
        button:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 4, -2)
        MMT.UI.Tooltip(button, "Planned items", "Puts the items you planned for this character in the team bags into the trade window.")
    end
    local own = MMT.PlayerFull()
    local planned = false
    for _, e in pairs(((own and mod.Gives()[own]) or {})[partner or ""] or {}) do
        if e.n > 0 then planned = true end
    end
    button:SetShown(planned)
end

M:On("TRADE_SHOW", function()
    tradeOpen, partner, lastTrade, acc = true, nil, nil, 0
    partner = Partner()
    ShowButton()
    if not M.db.giveTrade then return end
    -- after the core's own trade items (it fills its slots one by one from the start)
    local core = MMT.db and MMT.db.trade and MMT.db.trade.enabled
    C_Timer.After(core and 2.2 or 0.3, function() mod.FillTrade(false) end)
end)

-- lastTrade stays as last read while open: the slots may already be empty here
M:On("TRADE_CLOSED", function()
    tradeOpen = false
    token = token + 1
end)

-- "Trade complete": what we handed over comes off the plan
M:On("UI_INFO_MESSAGE", function(_, msg)
    if not (msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE) then return end
    local done = lastTrade
    lastTrade = nil
    local own = MMT.PlayerFull()
    if not (done and done.partner and own) then return end
    local plans = (mod.Gives()[own] or {})[done.partner] or {}
    for id, n in pairs(done.items) do
        local e = plans[id]
        if e and e.n > 0 then mod.SetGive(own, done.partner, id, math.max(0, e.n - n)) end
    end
    if button then button:Hide() end
end)

-- for tests / the debug report
function mod.TradeState() return tradeOpen, partner end
