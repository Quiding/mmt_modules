-- MMT Quality of life: Auctionator prices to the team after a full scan.
-- When this character's Auctionator finishes a full scan of the auction house
-- (its event bus: FullScan.Events.ScanComplete, also IncrementalScan's on the
-- modern AH), the prices it saw today go to the online team. Each member's
-- Auctionator takes them through its own Database:SetPrice - the same as its own
-- scan would - so tooltips, price history and posting all know them.
--
-- Only today's lowest price and how many were listed, per Auctionator key
-- ("2589", "g:<id>:<ilvl>", "p:<pet>"), not its whole history: about 12 bytes an
-- item before compressing (MMT.Pack). A busy auction house of 20,000 items is
-- ~100 KB compressed: 1-2 minutes at MMT's rate, once to the guild channel (every
-- member at once) or whispered to each member without a guild.
--   QAPH:<batch>:<parts>:<count>:<bytes>:<scan time>:<realm>   first, small
--   QAP:<batch>:<i>:<n>:<part>          the packed payload in parts (MMT.SendLong)
--   payload = <key>=<price>,<available>;...   (keys %XX escaped)
-- A member whose own scan is newer, or on another ruleset (PvE, PvP, ...), keeps its own prices.

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local CHUNK = 6000          -- packed bytes per SendLong (~28 core parts: well inside its limits)
local RATE = 800            -- the core's data rate (bytes / s), for the time estimate
local FORGET = 600          -- an unfinished transfer is dropped after 10 minutes without a part
local STEP = 400            -- prices written into Auctionator per frame
local ah = { sent = 0, sentItems = 0, got = 0, taken = 0, skipped = 0, hooked = false, lastSend = nil, lastFrom = nil }
-- ah.events = the Auctionator events listened to, ah.wrapped = its Database whose ProcessScan we wrap
mod.ah = ah
local incoming = {}         -- ["<key>:<batch>"] = { from, n, parts, got, count, bytes, time, realm, last }

local function Esc(s) return (tostring(s):gsub("[%%;=,|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function A()
    local a = rawget(_G, "Auctionator")
    if type(a) == "table" and type(a.Database) == "table" and type(a.Database.db) == "table"
        and type(a.Database.SetPrice) == "function" then return a end
end

-- Auctionator's day number (its price history is kept per day)
local function Today()
    local a = A()
    local day0 = a and a.Constants and a.Constants.SCAN_DAY_0
    if not day0 then return nil end
    return tostring(math.floor((time() - day0) / 86400))
end

local function Realm()
    local a = A()
    local v = a and a.Variables
    if v and type(v.GetConnectedRealmRoot) == "function" then
        local ok, r = pcall(v.GetConnectedRealmRoot)
        if ok and type(r) == "string" then return r end
    end
    return GetRealmName and GetRealmName() or "?"
end

local function Duration(sec)
    sec = math.max(1, math.ceil(sec))
    if sec < 60 then return sec .. " s" end
    return ("%d min"):format(math.ceil(sec / 60))
end

local function Number(n)
    local s = tostring(n)
    while true do
        local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end

-- today's prices in this character's Auctionator: payload text, count
function mod.AuctionatorPayload()
    local a, day = A(), Today()
    if not a or not day then return nil, 0 end
    local parts, n = {}, 0
    for key, d in pairs(a.Database.db) do
        if type(key) == "string" and type(d) == "table" and type(d.m) == "number" and d.m > 0
            and type(d.h) == "table" and d.h[day] then
            local avail = type(d.a) == "table" and tonumber(d.a[day]) or nil
            n = n + 1
            parts[n] = Esc(key) .. "=" .. math.floor(d.m) .. (avail and ("," .. math.floor(avail)) or "")
        end
    end
    table.sort(parts)   -- similar keys next to each other: packs smaller
    return table.concat(parts, ";"), n
end

-- send today's prices to the online team: true, text | false, why
function mod.AuctionatorSend(auto)
    if not A() then return false, "Auctionator isn't loaded." end
    local others = mod.OnlineOthers()
    if #others == 0 then return false, "nobody of the team is online." end
    local payload, count = mod.AuctionatorPayload()
    if not payload or count == 0 then return false, "no prices from today - do a full scan at the auction house first." end
    local packed = MMT.Pack and MMT.Pack(payload) or payload
    local n = math.max(1, math.ceil(#packed / CHUNK))
    local batch = tostring(math.random(100000, 999999))
    local scanTime = M.store.ahScan or time()
    MMT.SendToTeam(("QAPH:%s:%d:%d:%d:%d:%s"):format(batch, n, count, #packed, scanTime, Esc(Realm())), true)
    for i = 1, n do
        MMT.SendLong(("QAP:%s:%d:%d:%s"):format(batch, i, n, packed:sub((i - 1) * CHUNK + 1, i * CHUNK)))
    end
    ah.sent, ah.sentItems, ah.lastSend = ah.sent + 1, count, time()
    -- in a guild one send reaches everybody; without one each member is whispered
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

-- into Auctionator, STEP a frame (a big scan would stall one frame)
local function Apply(t, entries)
    local a = A()
    if not a then return end
    local i, n = 1, #entries
    local function Run()
        local db = a.Database
        for j = i, math.min(i + STEP - 1, n) do
            local e = entries[j]
            pcall(db.SetPrice, db, e[1], e[2], e[3])
        end
        i = i + STEP
        return i > n
    end
    local function Done()
        ah.taken, ah.lastFrom = ah.taken + n, t.from
        if M.db.ahChat then
            MMT.Print("Quality of life: took %s Auctionator prices from %s's scan (%s).", Number(n), MMT.FullDisplay(t.from),
                date("%H:%M", t.time or time()))
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
        MMT.Print("Quality of life: Auctionator prices from %s couldn't be unpacked here.", MMT.FullDisplay(t.from))
        return
    end
    local entries = {}
    for item in text:gmatch("[^;]+") do
        local key, price, avail = item:match("^([^=]+)=(%d+),?(%d*)$")
        if key then entries[#entries + 1] = { Unesc(key), tonumber(price), tonumber(avail) } end
    end
    Apply(t, entries)
end

-- may this transfer go into our Auctionator? nil = yes, else why not
local function Refuse(t)
    if not M.db.ahTake then return "taking the team's prices is off" end
    if not A() then return "Auctionator isn't loaded" end
    -- realms of one ruleset share the auction house
    if t.realm and t.realm ~= Realm() and mod.Ruleset(t.realm) ~= mod.Ruleset(Realm()) then return "another ruleset's auction house" end
    if t.time and M.store.ahScan and M.store.ahScan > t.time then return "your own scan is newer" end
end

local function OnHead(key, _, body)
    local batch, n, count, bytes, scanTime, realm = body:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(.*)$")
    if not batch then return end
    local t = Buffer(key, batch)
    t.n, t.count, t.bytes, t.time, t.realm = tonumber(n), tonumber(count), tonumber(bytes), tonumber(scanTime), Unesc(realm)
    ah.got = ah.got + 1
    local why = Refuse(t)
    if why then
        t.refused = why
        ah.skipped = ah.skipped + 1
        if M.db.ahChat then MMT.Print("Quality of life: not taking Auctionator prices from %s: %s.", MMT.FullDisplay(key), why) end
    elseif M.db.ahChat then
        MMT.Print("Quality of life: %s is sending Auctionator prices (%s items, %s).", MMT.FullDisplay(key), Number(t.count), mod.KB(t.bytes))
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
-- Auctionator's scan finished
---------------------------------------------------------------------------
local BIG = 300             -- a price batch of at least this many items counts as a scan (a search is a few)
local lastScan = -100

local function OnScan(why)
    ah.seen = (ah.seen or 0) + 1
    ah.lastSeen = why
    if not mod.Active(F) then ah.lastSkip = "feature off or Auctionator not loaded"; return end
    -- the event and the database hook both see one scan: once
    if GetTime() - lastScan < 30 then ah.lastSkip = "same scan"; return end
    ah.lastSkip = nil
    lastScan = GetTime()
    ah.lastWhy = why
    M.store.ahScan = time()
    if not M.db.ahAuto then ah.lastSkip = "auto-send off"; return end
    -- a moment later: the database is written by then
    C_Timer.After(2, function()
        if not mod.Active(F) then return end
        local ok, text = mod.AuctionatorSend(true)
        if not ok then ah.lastSkip = text end
        if M.db.ahChat or not ok then MMT.Print("Quality of life: Auctionator: %s", text) end
    end)
end

-- an error in here must not reach Auctionator; kept for /mmtqol ah status
local function Try(why)
    local ok, err = pcall(OnScan, why)
    if not ok then ah.lastError = tostring(err) end
end

-- 1) Auctionator's own "scan complete" events (full scan; the modern AH's incremental scan)
local function HookEvents(a)
    if ah.events then return end
    local bus = a.EventBus
    if not (bus and type(bus.Register) == "function") then return end
    local events = {}
    if a.FullScan and a.FullScan.Events and a.FullScan.Events.ScanComplete then events[#events + 1] = a.FullScan.Events.ScanComplete end
    if a.IncrementalScan and a.IncrementalScan.Events and a.IncrementalScan.Events.ScanComplete then
        events[#events + 1] = a.IncrementalScan.Events.ScanComplete
    end
    if #events == 0 then return end
    if pcall(bus.Register, bus, { ReceiveEvent = function(_, e) Try("event " .. tostring(e)) end }, events) then
        ah.events = table.concat(events, ",")
    end
end

-- 2) whatever scan it was: Auctionator's database taking a big batch of prices
-- (Database:ProcessScan, called by every kind of scan; its callback runs once all are written)
local function HookDatabase(a)
    local db = a.Database
    if ah.wrapped == db or type(db.ProcessScan) ~= "function" then return end
    local orig = db.ProcessScan
    db.ProcessScan = function(self, itemIndexes, callback, ...)
        local n = 0
        if type(itemIndexes) == "table" then for _ in pairs(itemIndexes) do n = n + 1; if n >= BIG then break end end end
        ah.batches = (ah.batches or 0) + 1
        ah.lastBatch = n
        if n >= BIG then
            local inner = callback
            callback = function(...)
                if inner then inner(...) end
                Try("database")
            end
        end
        return orig(self, itemIndexes, callback, ...)
    end
    ah.wrapped = db
end

local function Hook()
    ah.tries = (ah.tries or 0) + 1
    local a = A()
    if not a then ah.notReady = true; return false end
    ah.notReady = nil
    HookEvents(a)
    HookDatabase(a)
    ah.hooked = (ah.events ~= nil or ah.wrapped ~= nil)
    return ah.hooked
end
mod.AuctionatorHook = Hook

F = mod.Feature({
    key = "ahshare", icon = "INV_Misc_Coin_02", slash = "ah", addon = "Auctionator", title = "Auctionator prices", tabText = "Auctionator",
    checkText = "Share Auctionator prices with the team",
    tip = "After a full Auctionator scan at the auction house, the prices go to the online team; theirs come into your Auctionator the same way.",
    notes = {
        "When your Auctionator finishes a full scan, today's prices (lowest price and how many were listed, per item) go to the online team. Their Auctionator takes them like its own scan: tooltips, price history and posting know them.",
        "Only today's prices, not Auctionator's whole history: about 25-35 KB for 5,000 items, ~100 KB for a busy auction house of 20,000 - one or two minutes in the background. In a guild it goes out once for everybody; without one, once per team member.",
        "A team member whose own scan is newer, or who is on another ruleset (PvE, PvP, ...), keeps its own prices. Every character needs this module and Auctionator to take them.",
    },
    tags = { QAPH = OnHead, QAP = OnPart },
    commands = {
        status = function() MMT.Print("Quality of life: %s", mod.AuctionatorStatus()) end,
        send = function()
            local ok, text = mod.AuctionatorSend(false)
            MMT.Print("Quality of life: Auctionator: %s", text)
        end,
    },
    OnEnable = function()
        -- Auctionator may not be ready yet: again until it is (and whenever the auction house opens)
        if Hook() or not (C_Timer and C_Timer.NewTicker) then return end
        local tries = 0
        local t
        t = C_Timer.NewTicker(5, function()
            tries = tries + 1
            if Hook() or tries >= 24 then t:Cancel() end
        end)
    end,
    Page = function(ui)
        ui.Check("Send after a full scan", "ahAuto", "When your full scan at the auction house is done, today's prices go to the online team by themselves.")
        ui.Check("Take the team's prices", "ahTake", "Prices a team member sends come into your Auctionator (unless your own scan is newer).")
        ui.Check("Chat lines", "ahChat", "Says what was sent and taken.")
        ui.Button("Send today's prices now", function() F.commands.send() end, "Today's prices from your Auctionator to the online team (also /mmtqol ah send).")
    end,
    Report = function(add)
        local _, count = mod.AuctionatorPayload()
        add(mod.AuctionatorStatus())
        add(("Auctionator: hooked=%s events=%s dbHook=%s lastTrigger=%s realm=%s today=%d auto=%s take=%s lastScan=%s sent=%d (%d items) got=%d taken=%d skipped=%d lastFrom=%s incoming=%d"):format(
            tostring(ah.hooked), tostring(ah.events), tostring(ah.wrapped ~= nil and ah.wrapped == (A() and A().Database)), tostring(ah.lastWhy),
            tostring(A() and Realm() or "-"), count or 0, tostring(M.db.ahAuto), tostring(M.db.ahTake),
            M.store.ahScan and date("%H:%M", M.store.ahScan) or "-", ah.sent, ah.sentItems, ah.got, ah.taken, ah.skipped,
            tostring(ah.lastFrom), (function() local c = 0 for _ in pairs(incoming) do c = c + 1 end return c end)()))
    end,
})

-- the auction house opened: Auctionator is surely set up by now
M:On("AUCTION_HOUSE_SHOW", function()
    ah.ahOpened = (ah.ahOpened or 0) + 1
    if mod.Active(F) then Hook() end
end)
-- also when the game has loaded: not only through the module's start
M:On("PLAYER_ENTERING_WORLD", function() if mod.Active(F) then Hook() end end)

-- when Auctionator itself last started a full scan (its saved state), "HH:MM, N min ago"
local function AhScanTime()
    local a = rawget(_G, "Auctionator")
    local st = type(a) == "table" and type(a.SavedState) == "table" and a.SavedState
    local t = st and math.max(st.TimeOfLastReplicateScan or 0, st.TimeOfLastGetAllScan or 0, st.TimeOfLastBrowseScan or 0)
    if t == 0 then t = nil end
    if type(t) ~= "number" then return "-" end
    return ("%s (%d min ago)"):format(date("%H:%M", t), math.floor((time() - t) / 60))
end

-- where Auctionator's own scan is (its Scan button: the summary scan, or the replicate scan)
local function ScanState()
    local a = rawget(_G, "Auctionator")
    local s = type(a) == "table" and type(a.State) == "table" and a.State
    if not s then return "" end
    local parts = {}
    local inc = s.IncrementalScanFrameRef
    if type(inc) == "table" then
        local n = 0
        if type(inc.rawScan) == "table" then n = #inc.rawScan end
        parts[#parts + 1] = ("summaryScanning=%s summaryItems=%d"):format(tostring(inc.doingFullScan), n)
    end
    local full = s.FullScanFrameRef
    if type(full) == "table" then
        parts[#parts + 1] = ("replicateScanning=%s waiting=%s"):format(tostring(full.inProgress), tostring(full.waitingForData))
    end
    local ahApi = rawget(_G, "C_AuctionHouse")
    if type(ahApi) == "table" and type(ahApi.HasFullBrowseResults) == "function" then
        local ok, v = pcall(ahApi.HasFullBrowseResults)
        parts[#parts + 1] = "allPages=" .. tostring(ok and v)
    end
    local cfg = a.Config
    if type(cfg) == "table" and type(cfg.Get) == "function" and cfg.Options and cfg.Options.REPLICATE_SCAN then
        local ok, v = pcall(cfg.Get, cfg.Options.REPLICATE_SCAN)
        parts[#parts + 1] = "replicateMode=" .. tostring(ok and v)
    end
    return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
end

-- one line saying where auto-send stands (/mmtqol ah status)
function mod.AuctionatorStatus()
    local a = A()
    local active, why = mod.Active(F), nil
    if not active then
        if not M.enabled then why = "QoL module off"
        elseif not M.db.ahshare then why = "feature unticked"
        else local _, w = mod.AddonState("Auctionator"); why = w or "Auctionator not loaded" end
    end
    return ("Auctionator auto-send: active=%s%s auto=%s ready=%s hooked=%s events=%s dbHook=%s tries=%d ahOpened=%d batches=%d lastBatch=%s seen=%d lastSeen=%s lastSkip=%s lastError=%s startError=%s sent=%d auctionatorLastScan=%s"):format(
        tostring(active), why and (" (" .. why .. ")") or "", tostring(M.db.ahAuto), tostring(a ~= nil),
        tostring(ah.hooked), tostring(ah.events), tostring(ah.wrapped ~= nil and a ~= nil and ah.wrapped == a.Database),
        ah.tries or 0, ah.ahOpened or 0, ah.batches or 0, tostring(ah.lastBatch), ah.seen or 0, tostring(ah.lastSeen),
        tostring(ah.lastSkip), tostring(ah.lastError), tostring(F.startError), ah.sent, AhScanTime()) .. ScanState()
end
