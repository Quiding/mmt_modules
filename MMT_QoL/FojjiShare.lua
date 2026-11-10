-- MMT Quality of life: FojjiCore's auction scan to the team.
-- FojjiCore Professions puts a "Scan" button on the auction house; its scan keeps
-- the lowest price and how many are up per item in FojjiCore's own data
-- (FojjiCoreDB.auctions[realm-faction].items[itemID] = { min, n, t, atLeast, days }),
-- not in Auctionator. When this character's scan is done (FojjiCore says so through
-- Auctions.OnChange: its last-scan time moves on), that scan's items go to the
-- online team; each member's FojjiCore takes them, and its Auctionator too (as
-- that day's price), so tooltips there know them as well.
--   QFPH:<batch>:<parts>:<count>:<bytes>:<scan time>:<realm-faction>   first, small
--   QFP:<batch>:<i>:<n>:<part>          the packed payload in parts (MMT.SendLong)
--   payload = <itemID>=<price>,<count>[,+];...   ("+" = at least that many: some weren't read)
-- A member whose own FojjiCore scan is newer, or on another realm or faction, keeps its own.

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local CHUNK = 6000
local RATE = 800
local FORGET = 600
local STEP = 400
local HISTORY_DAYS = 7      -- FojjiCore's own: days of price history kept
local fj = { sent = 0, sentItems = 0, got = 0, taken = 0, skipped = 0, hooked = false, seen = 0 }
mod.fj = fj
local incoming = {}

local function Esc(s) return (tostring(s):gsub("[%%:;=,|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- FojjiCore's auction part, when it's there
local function AH()
    local ns = rawget(_G, "FojjiCoreNS")
    local a = type(ns) == "table" and ns.Auctions
    if type(a) == "table" and type(a.Store) == "function" then return a end
end

local function Store()
    local a = AH()
    if not a then return nil end
    local ok, s = pcall(a.Store)
    if ok and type(s) == "table" and type(s.items) == "table" then return s end
end

-- the key FojjiCore keeps this character's prices under (realm-faction, as it builds it)
local function RealmKey()
    local realm = GetRealmName and GetRealmName() or "?"
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    return realm .. "-" .. (faction or "")
end

-- the last finished scan's time (a full one, or one with gaps)
local function LastScan(s)
    s = s or Store()
    if not s then return 0 end
    return math.max(tonumber(s.scanned) or 0, tonumber(s.partial) or 0)
end

local function Number(n)
    local s = tostring(n)
    while true do
        local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end

local function Duration(sec)
    sec = math.max(1, math.ceil(sec))
    if sec < 60 then return sec .. " s" end
    return ("%d min"):format(math.ceil(sec / 60))
end

-- the items of the last scan: payload text, count, scan time
function mod.FojjiPayload()
    local s = Store()
    local when = LastScan(s)
    if not s or when == 0 then return nil, 0, 0 end
    local parts, n = {}, 0
    for id, e in pairs(s.items) do
        -- FojjiCore stamps every item its scan priced with the scan's time
        if type(id) == "number" and type(e) == "table" and type(e.min) == "number" and e.min > 0 and e.t == when then
            n = n + 1
            local price = ("%.1f"):format(e.min):gsub("%.0$", "")
            parts[n] = ("%d=%s,%d%s"):format(id, price, tonumber(e.n) or 0, e.atLeast and ",+" or "")
        end
    end
    table.sort(parts)
    return table.concat(parts, ";"), n, when
end

function mod.FojjiSend(auto)
    if not AH() then return false, "FojjiCore Professions isn't loaded." end
    local others = mod.OnlineOthers()
    if #others == 0 then return false, "nobody of the team is online." end
    local payload, count, when = mod.FojjiPayload()
    if not payload or count == 0 then return false, "no FojjiCore scan to send - press Scan at the auction house first." end
    local packed = MMT.Pack and MMT.Pack(payload) or payload
    local n = math.max(1, math.ceil(#packed / CHUNK))
    local batch = tostring(math.random(100000, 999999))
    MMT.SendToTeam(("QFPH:%s:%d:%d:%d:%d:%s"):format(batch, n, count, #packed, when, Esc(RealmKey())), true)
    for i = 1, n do
        MMT.SendLong(("QFP:%s:%d:%d:%s"):format(batch, i, n, packed:sub((i - 1) * CHUNK + 1, i * CHUNK)))
    end
    fj.sent, fj.sentItems, fj.lastSend = fj.sent + 1, count, time()
    local times = (MMT.GuildMode and MMT.GuildMode()) and 1 or #others
    return true, ("%s%s prices (%s) to the online team (%d): about %s."):format(auto and "after your scan, sending " or "sending ",
        Number(count), mod.KB(#packed), #others, Duration(#packed * 1.2 * times / RATE))
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Buffer(key, batch)
    local now = GetTime()
    for k, t in pairs(incoming) do if now - t.last > FORGET then incoming[k] = nil end end
    local k = key .. ":" .. batch
    local t = incoming[k]
    if not t then
        t = { from = key, parts = {}, got = 0, last = now }
        incoming[k] = t
    end
    return t, k
end

-- Auctionator too, when it's loaded and its sharing takes prices: the item's price that day
local function Auctionator()
    if not (M.db.fjAuctionator and M.db.ahTake ~= false) then return nil end
    local a = rawget(_G, "Auctionator")
    local db = type(a) == "table" and a.Database
    if type(db) == "table" and type(db.SetPrice) == "function" then return db end
end

-- one item into FojjiCore's data: only when ours is older
local function Put(s, e, when, day)
    local id, price, count, atLeast = e[1], e[2], e[3], e[4]
    local mine = s.items[id]
    if mine and (tonumber(mine.t) or 0) >= when then return false end
    if not mine then mine = {}; s.items[id] = mine end
    mine.min, mine.n, mine.t = price, count, when
    if atLeast then
        if not mine.atLeast then mine.before = mine.n end
        mine.atLeast = true
    else
        mine.atLeast, mine.before = nil, nil
    end
    mine.days = mine.days or {}
    if not mine.days[day] or price < mine.days[day] then mine.days[day] = price end
    for d in pairs(mine.days) do if day - d >= HISTORY_DAYS then mine.days[d] = nil end end
    return true
end

local function Apply(t, entries)
    local s = Store()
    if not s then return end
    local day = math.floor(t.time / 86400)
    local adb = Auctionator()
    local i, n, took = 1, #entries, 0
    local function Run()
        for j = i, math.min(i + STEP - 1, n) do
            local e = entries[j]
            if Put(s, e, t.time, day) then
                took = took + 1
                if adb then pcall(adb.SetPrice, adb, tostring(e[1]), math.floor(e[2] + 0.5), e[3]) end
            end
        end
        i = i + STEP
        return i > n
    end
    local function Done()
        s.shared = math.max(tonumber(s.shared) or 0, t.time)
        fj.taken, fj.lastFrom = fj.taken + took, t.from
        if M.db.fjChat then
            MMT.Print("Quality of life: took %s FojjiCore prices from %s's scan (%s)%s.", Number(took), MMT.FullDisplay(t.from),
                date("%H:%M", t.time), adb and ", into Auctionator too" or "")
        end
    end
    if C_Timer and C_Timer.NewTicker then
        local ticker
        ticker = C_Timer.NewTicker(0, function()
            if Run() then ticker:Cancel(); Done() end
        end)
    else
        while not Run() do end
        Done()
    end
end

local function Finish(t)
    local text = MMT.Unpack and MMT.Unpack(t.packed) or t.packed
    if not text then
        MMT.Print("Quality of life: FojjiCore prices from %s couldn't be unpacked here.", MMT.FullDisplay(t.from))
        return
    end
    local entries = {}
    for item in text:gmatch("[^;]+") do
        local id, price, count, plus = item:match("^(%d+)=([%d%.]+),(%d+),?(%+?)$")
        if id and tonumber(price) then entries[#entries + 1] = { tonumber(id), tonumber(price), tonumber(count), plus == "+" } end
    end
    Apply(t, entries)
end

local function Refuse(t)
    if not M.db.fjTake then return "taking the team's prices is off" end
    if not Store() then return "FojjiCore Professions isn't loaded" end
    if t.realm and t.realm ~= RealmKey() then return "another realm or faction" end
    if t.time and LastScan() > t.time then return "your own scan is newer" end
end

local function OnHead(key, _, body)
    local batch, n, count, bytes, scanTime, realm = body:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(.*)$")
    if not batch then return end
    local t = Buffer(key, batch)
    t.n, t.count, t.bytes, t.time, t.realm = tonumber(n), tonumber(count), tonumber(bytes), tonumber(scanTime), Unesc(realm)
    fj.got = fj.got + 1
    local why = Refuse(t)
    if why then
        t.refused = why
        fj.skipped = fj.skipped + 1
        if M.db.fjChat then MMT.Print("Quality of life: not taking FojjiCore prices from %s: %s.", MMT.FullDisplay(key), why) end
    elseif M.db.fjChat then
        MMT.Print("Quality of life: %s is sending FojjiCore prices (%s items, %s).", MMT.FullDisplay(key), Number(t.count), mod.KB(t.bytes))
    end
end

local function OnPart(key, _, body)
    local batch, i, n, part = body:match("^(%d+):(%d+):(%d+):(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not batch or not i or not n or i < 1 or i > n then return end
    local t, k = Buffer(key, batch)
    t.n, t.last = n, GetTime()
    if not t.parts[i] then t.parts[i] = part; t.got = t.got + 1 end
    if t.got < n then return end
    incoming[k] = nil
    if t.refused or Refuse(t) then return end
    t.packed = table.concat(t.parts)
    Finish(t)
end

---------------------------------------------------------------------------
-- FojjiCore's scan finished: its last-scan time moved on
---------------------------------------------------------------------------
local known                 -- the last-scan time already seen (nil: not hooked yet)

local function Check()
    local a = AH()
    if not a then return end
    if type(a.Scanning) == "function" then
        local ok, busy = pcall(a.Scanning)
        if ok and busy then return end
    end
    local when = LastScan()
    if known == nil then known = when; return end
    if when <= known then return end
    known = when
    fj.seen = fj.seen + 1
    fj.lastScan = when
    if not mod.Active(F) then fj.lastSkip = "feature off"; return end
    if not M.db.fjAuto then fj.lastSkip = "auto-send off"; return end
    fj.lastSkip = nil
    C_Timer.After(1, function()
        if not mod.Active(F) then return end
        local ok, text = mod.FojjiSend(true)
        if not ok then fj.lastSkip = text end
        if M.db.fjChat or not ok then MMT.Print("Quality of life: FojjiCore: %s", text) end
    end)
end

local function Hook()
    if fj.hooked then return true end
    local a = AH()
    if not (a and type(a.OnChange) == "function") then return false end
    known = LastScan()
    local ok = pcall(a.OnChange, function()
        local ok2, err = pcall(Check)
        if not ok2 then fj.lastError = tostring(err) end
    end)
    fj.hooked = ok and true or false
    return fj.hooked
end
mod.FojjiHook = Hook

function mod.FojjiStatus()
    local a = AH()
    local s = Store()
    local last = LastScan(s)
    local _, count = mod.FojjiPayload()
    return ("FojjiCore share: active=%s auto=%s take=%s loaded=%s hooked=%s realm=%s lastScan=%s items=%d seen=%d lastSkip=%s lastError=%s sent=%d (%d items) got=%d taken=%d skipped=%d lastFrom=%s"):format(
        tostring(mod.Active(F)), tostring(M.db.fjAuto), tostring(M.db.fjTake), tostring(a ~= nil), tostring(fj.hooked),
        RealmKey(), last > 0 and date("%H:%M", last) or "-", count or 0, fj.seen, tostring(fj.lastSkip), tostring(fj.lastError),
        fj.sent, fj.sentItems, fj.got, fj.taken, fj.skipped, tostring(fj.lastFrom))
end

F = mod.Feature({
    key = "fjshare", icon = "INV_Misc_Coin_01", slash = "fojji", addon = "FojjiCore_Professions", title = "FojjiCore auction scan", tabText = "FojjiCore scan",
    checkText = "Share FojjiCore's auction scan with the team",
    tip = "After FojjiCore's Scan at the auction house is done, its prices go to the online team; theirs come into your FojjiCore (and Auctionator) the same way.",
    notes = {
        "FojjiCore Professions' \"Scan\" button at the auction house keeps the lowest price and how many are up of every item, in FojjiCore's own data (its tooltips and Professions pages). When your scan is done, those prices go to the online team.",
        "A team member's FojjiCore takes them for every item where its own price is older; with Auctionator loaded it gets them too, as that day's price (the Auctionator page's \"Take the team's prices\" decides that).",
        "About the same size as an Auctionator scan: some 25-35 KB for 5,000 items. A team member whose own scan is newer, or on another realm or faction, keeps its own prices.",
    },
    tags = { QFPH = OnHead, QFP = OnPart },
    commands = {
        send = function()
            local _, text = mod.FojjiSend(false)
            MMT.Print("Quality of life: FojjiCore: %s", text)
        end,
        status = function() MMT.Print("Quality of life: %s", mod.FojjiStatus()) end,
    },
    OnEnable = function()
        if Hook() or not (C_Timer and C_Timer.NewTicker) then return end
        local tries = 0
        local t
        t = C_Timer.NewTicker(5, function()
            tries = tries + 1
            if Hook() or tries >= 24 then t:Cancel() end
        end)
    end,
    Page = function(ui)
        ui.Check("Send after a scan", "fjAuto", "When FojjiCore's Scan at the auction house is done, its prices go to the online team by themselves.")
        ui.Check("Take the team's prices", "fjTake", "Prices a team member's scan sends come into your FojjiCore, for every item where yours are older.")
        ui.Check("Into Auctionator too", "fjAuctionator", "The prices you take also go into Auctionator (when it's loaded), as that day's price.")
        ui.Check("Chat lines", "fjChat", "Says what was sent and taken.")
        ui.Button("Send my last scan now", function() F.commands.send() end, "Your last FojjiCore scan to the online team (also /mmtqol fojji send).")
    end,
    Report = function(add) add(mod.FojjiStatus()) end,
})

M:On("AUCTION_HOUSE_SHOW", function() if mod.Active(F) then Hook() end end)
M:On("PLAYER_ENTERING_WORLD", function() if mod.Active(F) then Hook() end end)
