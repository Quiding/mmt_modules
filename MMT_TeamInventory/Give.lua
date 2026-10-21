-- MMT Team Inventory: planned gifts. In the team bags ("Whole team, by
-- character", Bags tab) drag an item from one character onto another: it
-- moves there and glows. The next time those two trade, the giver's client
-- puts it into the trade window (after the core's own role items). With
-- autoAccept, both sides accept a trade that holds nothing but planned gifts.
-- When the trade completes, what was handed over comes off the plan.
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

-- only real characters give or get ("__ALL__" etc. are views of the team bags)
local function Real(key) return type(key) == "string" and key ~= "" and key:sub(1, 2) ~= "__" end
local cleaned = false

function mod.Gives()
    M.store.gives = M.store.gives or {}
    local g = M.store.gives
    if not cleaned then   -- 0.4.1 could store a gift "from" the whole team view
        cleaned = true
        for from, tos in pairs(g) do
            if type(tos) == "table" then
                if not Real(from) then g[from] = nil
                else for to in pairs(tos) do if not Real(to) then tos[to] = nil end end end
            end
        end
    end
    return g
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
    if not (Real(from) and Real(to) and id) or from == to then return end
    n = math.max(0, math.floor(tonumber(n) or 0))
    local cur = Get(from, to, id)
    -- the same second twice (drag, then cancel at once): still the newer one
    local t = math.max(Now(), (cur and cur.t or 0) + 1)
    Store(from, to, id, n, t)
    MMT.SendToTeam(Encode(from, to, id, Get(from, to, id)), true)
    if mod.RefreshBags then mod.RefreshBags() end
end

-- Tradeable or not: Bind on Pickup and quest items never are (bind type from
-- the item info, any client); a Bind on Equip one is once its character
-- equipped it - only that client sees it, it sends the count with its bags (s)
-- every value of the item info (MMT.Safe passes only the first 7: the bind
-- type is the 14th, "crafting reagent" the 17th); nil while not cached / secret
function mod.ItemInfo(id)
    local r = { pcall((C_Item and C_Item.GetItemInfo) or GetItemInfo, id) }
    if not r[1] or r[2] == nil or MMT.IsSecret(r[2]) then return nil end
    return unpack(r, 2, 18)
end

function mod.NeverTradeable(id)
    local bind = select(14, mod.ItemInfo(id))
    return bind == 1 or bind == 4   -- 1 Bind on Pickup, 4 quest item
end

-- how many of an item a character can still give: in the bags, not soulbound, not promised
function mod.Tradeable(key, id)
    if mod.NeverTradeable(id) then return 0 end
    local rec = mod.Chars()[key]
    if not rec then return 0 end
    local n = (rec.b and rec.b[id] or 0) - (rec.s and rec.s[id] or 0) - mod.PlannedOut(key, id)
    return math.max(0, n)
end

-- cancels every gift from one character to another
function mod.CancelGifts(from, to)
    for id, e in pairs((mod.Gives()[from] or {})[to] or {}) do
        if e.n > 0 then mod.SetGive(from, to, id, 0) end
    end
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
    if not id or not (Real(from) and Real(to)) then return end
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
-- "Trade now": the giver's client opens the trade with the receiver
--   TIVT:<from>:<to>   to the team; the client of <from> calls InitiateTrade
--   TIVN:<from>:<to>   whispered back: <to> wasn't found (no group, no nameplate)
-- InitiateTrade works from an addon message on this client (tested in game
-- with party1); it needs a unit, so the receiver must be in the group (name
-- or partyN / raidN) or have a nameplate shown (friendly nameplates).
---------------------------------------------------------------------------
-- the unit of a team character near us, or nil
function mod.UnitOf(key)
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(MMT.Safe(C_NamePlate.GetNamePlates) or {}) do
            local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if u then units[#units + 1] = u end
        end
    end
    -- by the full "First-Last" key (the core's SplitUnit: the last name comes in the
    -- realm field), so characters with the same first name aren't mixed up
    for _, u in ipairs(units) do
        local _, _, k = MMT.SplitUnit(u)
        if k and not MMT.IsSecret(k) and (k == key or (MMT.Resolve and MMT.Resolve(k) == key)) then return u end
    end
end

-- on the giver: open the trade; false when the receiver can't be found
function mod.StartTrade(to)
    local unit = mod.UnitOf(to)
    if not unit then return false end
    InitiateTrade(unit)
    return true
end

local function NotFound(from, to)
    return ("Team Inventory: %s can't find %s - put them in a group, or turn on friendly nameplates and stand next to each other."):format(
        MMT.FirstName(from), MMT.FirstName(to))
end

-- the "Trade" button: here when we are the giver, else ask the giver's client
function mod.RequestTrade(from, to)
    if MMT.IsSelf(from) then
        if not mod.StartTrade(to) then MMT.Print(NotFound(from, to)) end
        return
    end
    if MMT.IsOnline and not MMT.IsOnline(from) then
        MMT.Print("Team Inventory: %s is offline.", MMT.FirstName(from))
        return
    end
    MMT.SendToTeam(("TIVT:%s:%s"):format(from, to), true)
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local from, to = text:match("^TIVT:([^:]+):([^:]+)$")
    if from then
        if MMT.IsSelf(from) and not mod.StartTrade(to) then
            MMT.SendAddon(("TIVN:%s:%s"):format(from, to), "WHISPER", sender)
        end
        return
    end
    from, to = text:match("^TIVN:([^:]+):([^:]+)$")
    if from then MMT.Print(NotFound(from, to)) end
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
    local _, _, k = MMT.SplitUnit("NPC")
    if k then names[#names + 1] = k end
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
            -- drop it at once: right after a split the cursor doesn't show the item yet
            -- (CursorHasItem is false), but the click still places it (like EllesmereUI Bags)
            ClickTradeButton(free)
            C_Timer.After(0.2, function() if CursorHasItem() then ClearCursor() end end)
        end)
    end
    if #steps > 0 then
        MMT.Print("Team Inventory: %d planned stack(s) for %s go into the trade.", #steps, MMT.FullDisplay(partner))
    end
    return #steps
end

---------------------------------------------------------------------------
-- Accepting by itself (setting autoAccept): only when the trade is nothing but
-- planned gifts between these two - the giver's side holds everything it can
-- hand over and nothing else, the receiver's side nothing at all, no gold, no
-- item in the "will not be traded" slot - and it hasn't changed for a moment.
-- Any change in the trade takes both accepts back; it is checked again then.
-- An extra confirmation popup of the game (e.g. soulbound) stays a click.
---------------------------------------------------------------------------
local STEADY = 1.5   -- seconds the trade must stay unchanged
local signature, changedAt, accepted = nil, 0, false
local toldFor          -- the trade state the "not accepting" note was given for

-- { [itemID] = count } on the partner's side
local function InTarget()
    local t = {}
    for s = 1, MAX_SLOTS do
        local id = ItemID(MMT.Safe(GetTradeTargetItemLink, s))
        if id then
            local _, _, n = MMT.Safe(GetTradeTargetItemInfo, s)
            t[id] = (t[id] or 0) + (tonumber(n) or 1)
        end
    end
    return t
end

local function Plans(from, to)
    local t = {}
    for id, e in pairs((mod.Gives()[from] or {})[to] or {}) do
        if e.n > 0 then t[id] = e.n end
    end
    return t
end

-- every item on that side is planned, and no more of it than planned
local function OnlyPlanned(items, plans)
    for id, n in pairs(items) do
        if not plans[id] or n > plans[id] then return false end
    end
    return true
end

local function Signature(mine, theirs)
    local parts = {}
    for id, n in pairs(mine) do parts[#parts + 1] = "m" .. id .. "x" .. n end
    for id, n in pairs(theirs) do parts[#parts + 1] = "t" .. id .. "x" .. n end
    table.sort(parts)
    parts[#parts + 1] = tostring(MMT.Safe(GetPlayerTradeMoney)) .. "/" .. tostring(MMT.Safe(GetTargetTradeMoney))
    return table.concat(parts, ";")
end

-- the first item on a side that isn't planned (or more than planned): text for chat
local function NotPlanned(items, plans, side)
    for id, n in pairs(items) do
        if not plans[id] then return ("%s %s isn't a planned gift"):format(side, ItemName(id)) end
        if n > plans[id] then return ("%s %d %s, %d planned"):format(side, n, ItemName(id), plans[id]) end
    end
end

-- true when this trade may be accepted by itself; else false and why (nil: nothing to say)
function mod.TradeIsPlanned()
    local own = MMT.PlayerFull()
    if not (tradeOpen and own) then return false end
    if not partner then return false end   -- not in the team: no gifts with them (debug dump shows the partner)
    local give, get = Plans(own, partner), Plans(partner, own)
    if next(give) == nil and next(get) == nil then return false end   -- no gifts between these two
    if (tonumber(MMT.Safe(GetPlayerTradeMoney)) or 0) ~= 0 or (tonumber(MMT.Safe(GetTargetTradeMoney)) or 0) ~= 0 then
        return false, "there's gold in the trade"
    end
    local extra = MAX_SLOTS + 1   -- "will not be traded" (enchanting)
    if MMT.Safe(GetTradePlayerItemLink, extra) or MMT.Safe(GetTradeTargetItemLink, extra) then
        return false, "something is in the \"will not be traded\" slot"
    end
    local mine, theirs = InTrade(), InTarget()
    if next(mine) == nil and next(theirs) == nil then return false end
    local why = NotPlanned(mine, give, "your side has") or NotPlanned(theirs, get, MMT.FirstName(partner) .. "'s side has")
    if why then return false, why end
    -- the giver: nothing it could still add
    if next(give) ~= nil and #(Steps(give, mine)) > 0 then return false, "not all planned items are in yet" end
    return true
end

-- accepts the open trade: the game's AcceptTrade, else a click on the trade
-- window's Trade button; false (and a note, once) when neither is there / works
local warned = false
function mod.AcceptTrade()
    local ok = false
    if type(AcceptTrade) == "function" then
        ok = pcall(AcceptTrade)
    elseif TradeFrameTradeButton and TradeFrameTradeButton.Click then
        ok = pcall(TradeFrameTradeButton.Click, TradeFrameTradeButton)
    end
    if not ok and not warned then
        warned = true
        MMT.Print("Team Inventory: couldn't accept the trade by itself on this client - click Trade. (/mmt debug dump says more)")
    end
    if M.Debug then M:Debug("AcceptTrade: %s (AcceptTrade=%s button=%s)", tostring(ok), type(AcceptTrade), tostring(TradeFrameTradeButton ~= nil)) end
    return ok
end

-- what our side holds, read while the trade is open (it is empty again once
-- it completed), and the auto-accept check
local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, e)
    if not tradeOpen then return end
    acc = acc + e
    if acc < 0.25 then return end
    acc = 0
    local mine = InTrade()
    lastTrade = { partner = partner, items = mine }
    local sig = Signature(mine, InTarget())
    if sig ~= signature then signature, changedAt, accepted = sig, GetTime(), false end
    if M.db.autoAccept and not accepted and GetTime() - changedAt >= STEADY then
        local ok, why = mod.TradeIsPlanned()
        if ok then
            accepted = true
            if mod.AcceptTrade() then
                MMT.Print("Team Inventory: trade with %s accepted (only planned items).", MMT.FullDisplay(partner))
            end
        elseif why and toldFor ~= signature then
            -- once per state of the trade: why it waits for you
            toldFor = signature
            MMT.Print("Team Inventory: not accepting by itself - %s.", why)
        end
    end
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
    signature, changedAt, accepted = nil, GetTime(), false
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
