"""MMT_QoL FojjiShare.lua: FojjiCore Professions' auction scan to the team. Two clients, Anna
and Bob, each with FojjiCore's auction store (FOJJI_REAL = path to FojjiCore_Professions/
Auctions.lua runs FojjiCore's own code; otherwise a stand-in with the same data shape and
OnChange / Scanning / Store). Anna's scan finishing sends that scan's items (not older ones);
Bob's FojjiCore takes them where his are older, and his Auctionator too. Refused: Bob's own
scan newer, another realm/faction, taking off. A taken scan isn't sent on again."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])
REAL = os.environ.get("FOJJI_REAL")

STUBS = r'''
LISTEN, PRINTS, SENT, TICKERS, NOW, CLOCK = {}, {}, {}, {}, 0, 1800000000
SlashCmdList = {}
function GetTime() return NOW end
function time() return CLOCK end
function date() return "12:00" end
function debugprofilestop() return 0 end
TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS + 1] = fn end,
  NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.off = true end }; TICKERS[#TICKERS + 1] = t; return t end }
function FRAMES() for n = 1, 2000 do
  local any = false
  local due = TIMERS; TIMERS = {}
  for _, fn in ipairs(due) do any = true; fn() end
  for _, t in ipairs(TICKERS) do if not t.off then any = true; t.fn() end end
  for _, f in ipairs(UPDATES) do local s = f.scripts.OnUpdate if s and f.shown then any = true; s(f, 0.016) end end
  NOW = NOW + 0.016
  if not any then return n end end end
UPDATES = {}
function CreateFrame()
  local f = { scripts = {}, events = {}, shown = true }
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:Hide() self.shown = false end
  function f:Show() self.shown = true end
  UPDATES[#UPDATES + 1] = f
  return f
end
function FIRE_EVENT(e) for _, f in ipairs(UPDATES) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e) end end end
LOADED = { FojjiCore_Professions = true }
C_AddOns = { IsAddOnLoaded = function(n) return LOADED[n] == true end, GetAddOnInfo = function(n) return n, n, "", false, "MISSING" end }
REALM, FACTION = "Realm", "Horde"
function GetRealmName() return REALM end
function UnitFactionGroup() return FACTION end
MMT = { IsSecret = function() return false end, UI = {}, db = { team = {} } }
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function MMT.FullDisplay(k) return (k:match("^[^-]+")) end
function MMT.IsSelf(k) return k == ME end
function MMT.IsOnline() return true end
function MMT.SortedMembers() return { "Anna-R", "Bob-R" } end
function MMT.GuildMode() return true end
function MMT.SendToTeam(msg) assert(#msg <= 250, "too long: " .. #msg); SENT[#SENT + 1] = msg end
function MMT.SendLong(msg) SENT[#SENT + 1] = msg end
function MMT.Pack(s) return "Z1:" .. s:reverse() end
function MMT.Unpack(s) return s:sub(4):reverse() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = {} for k, v in pairs(def.defaults) do M.db[k] = v end
  M.store = {}
  function M:On() end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  return M
end
function DELIVER(from, msg) for _, fn in ipairs(LISTEN.TEAM_MESSAGE) do fn(from, from, msg) end end
-- Auctionator (taking only)
ASETS = {}
Auctionator = { Database = { db = {}, SetPrice = function(self, k, p, a) ASETS[k] = { p, a } end } }
FojjiCoreNS = { IsForever = true, Print = function(m) PRINTS[#PRINTS + 1] = "FOJJI: " .. m end }
'''

# a stand-in for FojjiCore's Auctions.lua: same store, same stamping, same callbacks
STANDIN = r'''
local AH = {}
FojjiCoreNS.Auctions = AH
local function store()
  FojjiCoreDB = FojjiCoreDB or {}
  FojjiCoreDB.auctions = FojjiCoreDB.auctions or {}
  local key = GetRealmName() .. "-" .. UnitFactionGroup("player")
  FojjiCoreDB.auctions[key] = FojjiCoreDB.auctions[key] or { items = {}, scanned = 0, fullAt = 0 }
  return FojjiCoreDB.auctions[key]
end
AH.Store = store
local listeners, busy = {}, false
function AH.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed() for _, fn in ipairs(listeners) do pcall(fn) end end
function AH.Scanning() return busy end
-- SCAN(rows): rows = { {itemID, unit price, count}, ... }; done over a few frames like the real one
function SCAN(rows)
  busy = true; changed()
  C_Timer.After(0, function()
    local s, now, day = store(), time(), math.floor(time() / 86400)
    for _, r in ipairs(rows) do
      local e = s.items[r[1]] or {}; s.items[r[1]] = e
      e.min, e.n, e.t = r[2], r[3], now
      e.days = e.days or {}; e.days[day] = r[2]
    end
    s.scanned = now
    busy = false; changed()
  end)
end
'''

# the real one: its Scan() over the modern API, the server answering with these rows
REALSCAN = r'''
ROWS = {}
C_AuctionHouse = { ReplicateItems = function() end, GetNumReplicateItems = function() return #ROWS end,
  GetReplicateItemInfo = function(i) local r = ROWS[i + 1]
    return "Item" .. r[1], nil, r[3], nil, nil, nil, nil, nil, nil, r[2] * r[3], nil, nil, nil, nil, nil, nil, r[1], true end }
function SCAN(rows)
  ROWS = rows
  FojjiCoreDB.auctions[GetRealmName() .. "-" .. UnitFactionGroup("player")].fullAt = 0
  assert(FojjiCoreNS.Auctions.Scan(), "scan started")
  FIRE_EVENT("REPLICATE_ITEM_LIST_UPDATE")
end
'''

def client(me):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"' % me)
    lua.execute(STUBS)
    if REAL:
        src = open(REAL, encoding='utf-8').read()
        lua.eval('function(src) assert(loadstring(src, "Auctions.lua"))() end')(src)
        lua.execute('FojjiCoreNS.Auctions.Store()')
        lua.execute(REALSCAN)
    else:
        lua.execute(STANDIN)
    mod = lua.eval('{}')
    for f in ('Module.lua', 'Bulk.lua', 'FojjiShare.lua'):
        src = open('MMT_QoL/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)
    lua.eval('function(m) m.M.OnEnable(m.M) end')(mod)
    return lua, mod

A, amod = client("Anna-R")
B, bmod = client("Bob-R")

def take(lua):
    msgs = lua.eval('function() local t = SENT; SENT = {} return t end')()
    return [msgs[i] for i in range(1, len(msgs) + 1)]

def run(lua, mod, code):
    print(lua.eval(code)(mod))

# Anna: an older item from yesterday, then a scan of 1500 items
run(A, amod, r'''function(m)
  assert(m.fj.hooked, "hooked into FojjiCore")
  local s = FojjiCoreNS.Auctions.Store()
  s.items[99999] = { min = 5, n = 1, t = CLOCK - 86400 }
  local rows = {}
  for id = 1, 1500 do rows[id] = { id, id * 10 + 0.5, 3 } end
  SCAN(rows)
  FRAMES()
  assert(m.fj.seen == 1, "scan seen: " .. m.fj.seen)
  local _, n = m.FojjiPayload()
  assert(n == 1500, "that scan's items only: " .. n)
  return "anna scanned 1500"
end''')
sent = take(A)
assert sent[0].startswith('QFPH:') and len(sent) >= 2, sent[:1]
print('anna sent %d messages' % len(sent))

# Bob: his 42 is newer than Anna's scan (kept); his Auctionator gets the rest
B.execute('CLOCK = CLOCK + 60')
run(B, bmod, r'''function(m)
  local s = FojjiCoreNS.Auctions.Store()
  s.items[42] = { min = 1, n = 9, t = CLOCK }
  return ""
end''')
for msg in sent: B.eval('DELIVER')('Anna-R', msg)
run(B, bmod, r'''function(m)
  FRAMES()
  local s = FojjiCoreNS.Auctions.Store()
  assert(s.items[1234].min == 12340.5 and s.items[1234].n == 3, "taken: " .. tostring(s.items[1234] and s.items[1234].min))
  assert(s.items[42].min == 1, "his newer price kept")
  assert(s.items[99999] == nil, "Anna's older item not sent")
  assert(ASETS["1234"][1] == 12341 and ASETS["1234"][2] == 3 and ASETS["42"] == nil, "into Auctionator too")
  assert(PRINTS[#PRINTS]:find("took 1,499 FojjiCore prices from Anna"), PRINTS[#PRINTS])
  assert(#SENT == 0 and m.fj.seen == 0, "taking isn't a scan of his: not sent on")
  return "bob took 1499, kept his newer one"
end''')

# refused: Bob's own scan newer / other faction / taking off
run(B, bmod, r'''function(m)
  local s = FojjiCoreNS.Auctions.Store()
  for id in pairs(s.items) do s.items[id] = nil end
  s.scanned = CLOCK + 100
  PRINTS = {}
  return ""
end''')
for msg in sent: B.eval('DELIVER')('Anna-R', msg)
run(B, bmod, r'''function(m)
  FRAMES()
  assert(next(FojjiCoreNS.Auctions.Store().items) == nil and PRINTS[1]:find("your own scan is newer"), tostring(PRINTS[1]))
  FojjiCoreNS.Auctions.Store().scanned = 0
  FACTION = "Alliance"; PRINTS = {}
  return "own newer scan kept"
end''')
for msg in sent: B.eval('DELIVER')('Anna-R', msg)
run(B, bmod, r'''function(m)
  FRAMES()
  assert(PRINTS[1]:find("another faction"), tostring(PRINTS[1]))
  FACTION = "Horde"; m.M.db.fjTake = false; PRINTS = {}
  return "other faction kept"
end''')
for msg in sent: B.eval('DELIVER')('Anna-R', msg)
run(B, bmod, r'''function(m)
  FRAMES()
  assert(PRINTS[1]:find("off") and next(FojjiCoreNS.Auctions.Store().items) == nil, tostring(PRINTS[1]))
  return "taking off kept"
end''')

# Anna: auto off -> nothing; the command still sends; the status line
run(A, amod, r'''function(m)
  m.M.db.fjAuto = false
  CLOCK = CLOCK + 3600
  SCAN({ { 7, 70, 1 } })
  FRAMES()
  assert(#SENT == 0 and m.fj.lastSkip == "auto-send off", tostring(m.fj.lastSkip))
  local ok, text = m.FojjiSend()
  assert(ok and #SENT >= 2, text)
  local st = m.FojjiStatus()
  assert(st:find("hooked=true") and st:find("items=1 ") and st:find("seen=2"), st)
  return "auto off; send by hand; " .. st:sub(1, 60)
end''')
print('fojji share ok')
