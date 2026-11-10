"""MMT_QoL AuctionatorShare.lua: two clients, Anna and Bob, each with a stand-in Auctionator
(its event bus, per-realm price database with today's day, Database:SetPrice). Anna's full
scan finishing sends today's prices (not older ones) packed in parts; Bob's Auctionator takes
them through SetPrice, a few hundred a frame. Refused: Bob's own scan is newer, another realm,
taking off. Auto-send off, nobody online, nothing scanned today."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
LISTEN, PRINTS, SENT, TICKERS, NOW, CLOCK = {}, {}, {}, {}, 0, 1800000000
SlashCmdList = {}
function GetTime() return NOW end
function time() return CLOCK end
function date(fmt, t) return "12:00" end
C_Timer = { After = function(_, fn) fn() end,
  NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.off = true end }; TICKERS[#TICKERS + 1] = t; return t end }
function FRAMES() local n = 0 repeat local any = false for _, t in ipairs(TICKERS) do if not t.off then any = true; t.fn() end end n = n + 1 until not any or n > 1000 return n end
LOADED = { Auctionator = true }
C_AddOns = { IsAddOnLoaded = function(n) return LOADED[n] == true end,
  GetAddOnInfo = function(n) return n, n, "", false, LOADED[n] == nil and "MISSING" or "DISABLED" end }
function GetRealmName() return "Realm" end
MMT = { IsSecret = function() return false end, UI = {}, db = { team = {} } }
ONLINE = { ["Anna-R"] = true, ["Bob-R"] = true }
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function MMT.FullDisplay(k) return (k:match("^[^-]+")) end
function MMT.IsSelf(k) return k == ME end
function MMT.IsOnline(k) return ONLINE[k] == true end
function MMT.SortedMembers() return { "Anna-R", "Bob-R" } end
function MMT.GuildMode() return true end
function MMT.SendToTeam(msg) assert(#msg <= 250, "too long: " .. #msg); SENT[#SENT + 1] = msg end
function MMT.SendLong(msg) SENT[#SENT + 1] = msg end
function MMT.Pack(s) return "Z1:" .. s:reverse() end
function MMT.Unpack(s) if s:sub(1, 3) ~= "Z1:" then return s end return s:sub(4):reverse() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On() end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  return M
end
function DELIVER(from, msg) for _, fn in ipairs(LISTEN.TEAM_MESSAGE) do fn(from, from, msg) end end

-- Auctionator
local listeners = {}
SETS = 0
Auctionator = {
  Constants = { SCAN_DAY_0 = CLOCK - 2000 * 86400 },
  FullScan = { Events = { ScanComplete = "scan_done" } },
  Variables = { GetConnectedRealmRoot = function() return REALM end },
  EventBus = { Register = function(self, l, evs) for _, e in ipairs(evs) do listeners[e] = listeners[e] or {}; table.insert(listeners[e], l) end end },
  Database = { db = {} },
}
REALM = "Realm"
function Auctionator.Database:SetPrice(key, price, avail)
  SETS = SETS + 1
  local d = self.db[key] or { l = {}, h = {}, a = {}, m = 0 }
  self.db[key] = d
  d.m = price; d.h["2000"] = price; if avail then d.a["2000"] = avail end
end
function FIRE(e) for _, l in ipairs(listeners[e] or {}) do l:ReceiveEvent(e) end end
PROCESSED = 0
function Auctionator.Database:ProcessScan(items, callback)
  local n = 0
  for k, v in pairs(items) do n = n + 1; self:SetPrice(k, v, 1) end
  PROCESSED = PROCESSED + 1
  if callback then callback(n) end
end
'''

def client(me):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"' % me)
    lua.execute(STUBS)
    mod = lua.eval('{}')
    for f in ('Module.lua', 'Bulk.lua', 'AuctionatorShare.lua'):
        src = open('MMT_QoL/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)
    lua.eval('function(m) m.M.OnEnable(m.M) end')(mod)
    return lua, mod

A, amod = client("Anna-R")
B, bmod = client("Bob-R")

def take(lua):
    msgs = lua.eval('function() local t = SENT; SENT = {} return t end')()
    return [msgs[i] for i in range(1, len(msgs) + 1)]

def deliver(msgs, lua, frm):
    for m in msgs: lua.eval('DELIVER')(frm, m)

def run(lua, mod, code):
    print(lua.eval(code)(mod))

# Anna's database: 3000 items seen today, one only on an older day, a gear key with ":"
run(A, amod, r'''function(m)
  assert(m.ah.hooked, "hooked into Auctionator's event bus")
  local db = Auctionator.Database.db
  for id = 1, 3000 do db[tostring(id)] = { m = id * 10, h = { ["2000"] = id * 10 }, a = { ["2000"] = 3 }, l = {} } end
  db["old"] = { m = 5, h = { ["1990"] = 5 }, l = {}, a = {} }
  db["g:123:45"] = { m = 777, h = { ["2000"] = 777 }, l = {}, a = {} }
  local text, n = m.AuctionatorPayload()
  assert(n == 3001 and not text:find("old="), "today only: " .. n)
  FIRE("scan_done")
  assert(m.M.store.ahScan == CLOCK, "scan time kept")
  return "anna scanned"
end''')
sent = take(A)
assert sent[0].startswith('QAPH:') and len(sent) >= 3, sent[:1]
assert all(len(s) < 6100 for s in sent[1:]), 'parts'
print('anna sent %d messages' % len(sent))

# Bob: an older own scan -> takes them, a few hundred per frame
B.execute('CLOCK = CLOCK + 60')
run(B, bmod, r'''function(m) m.M.store.ahScan = CLOCK - 3600; return "bob scanned an hour ago" end''')
deliver(sent, B, 'Anna-R')
run(B, bmod, r'''function(m)
  local frames = FRAMES()
  local db = Auctionator.Database.db
  assert(SETS == 3001 and db["1234"].m == 12340 and db["1234"].a["2000"] == 3 and db["g:123:45"].m == 777 and db.old == nil,
    "taken: " .. SETS)
  assert(frames >= 7, "spread over frames: " .. frames)
  assert(PRINTS[#PRINTS]:find("took 3,001 Auctionator prices from Anna"), PRINTS[#PRINTS])
  return "bob took 3001 prices over " .. frames .. " frames"
end''')

# Bob's own scan is newer: refused
run(B, bmod, r'''function(m) m.M.store.ahScan = CLOCK + 100; SETS = 0; PRINTS = {}; return "bob scans again" end''')
deliver(sent, B, 'Anna-R')
run(B, bmod, r'''function(m)
  FRAMES()
  assert(SETS == 0 and PRINTS[1]:find("your own scan is newer"), tostring(PRINTS[1]))
  return "newer own scan kept"
end''')

# another realm / taking off: refused
run(B, bmod, r'''function(m) m.M.store.ahScan = nil; REALM = "Other"; SETS = 0; PRINTS = {}; return "" end''')
deliver(sent, B, 'Anna-R')
run(B, bmod, r'''function(m)
  FRAMES()
  assert(SETS == 0 and PRINTS[1]:find("another realm"), tostring(PRINTS[1]))
  REALM = "Realm"; m.M.db.ahTake = false; PRINTS = {}
  return "other realm kept"
end''')
deliver(sent, B, 'Anna-R')
run(B, bmod, r'''function(m)
  FRAMES()
  assert(SETS == 0 and PRINTS[1]:find("off"), tostring(PRINTS[1]))
  m.M.db.ahTake = true
  return "taking off kept"
end''')

# parts out of order and a part twice: still once
run(B, bmod, r'''function(m) SETS = 0; return "" end''')
deliver([sent[0]] + list(reversed(sent[1:])) + [sent[1]], B, 'Anna-R')
run(B, bmod, r'''function(m) FRAMES(); assert(SETS == 3001, "out of order: " .. SETS); return "parts in any order" end''')

# Anna: auto off, nobody online, nothing today, command
run(A, amod, r'''function(m)
  m.M.db.ahAuto = false
  FIRE("scan_done")
  assert(#SENT == 0, "auto off: nothing sent")
  ONLINE["Bob-R"] = false
  local ok, why = m.AuctionatorSend()
  assert(not ok and why:find("online"), why)
  ONLINE["Bob-R"] = true
  Auctionator.Database.db = { x = { m = 1, h = { ["1"] = 1 } } }
  ok, why = m.AuctionatorSend()
  assert(not ok and why:find("full scan"), why)
  local F
  for _, f in ipairs(m.features) do if f.key == "ahshare" then F = f end end
  local lines = {}
  F.Report(function(l) lines[#lines + 1] = l end)
  assert(lines[1]:find("hooked=true") and lines[1]:find("sent=1"), lines[1])
  return "auto off, nobody online, nothing today"
end''')
# any kind of scan: Auctionator's database taking a big batch (its events not there)
run(A, amod, r'''function(m)
  m.M.db.ahAuto = true
  NOW = NOW + 100
  SENT = {}
  local small = {}
  for i = 1, 5 do small["s" .. i] = 1 end
  Auctionator.Database:ProcessScan(small)
  assert(#SENT == 0 and PROCESSED == 1, "a search (5 items) isn't a scan")
  local big = {}
  for i = 1, 400 do big[tostring(i)] = i end
  Auctionator.Database:ProcessScan(big, function() end)
  assert(#SENT > 0 and SENT[1]:find("^QAPH:"), "a 400-item batch counts as a scan")
  assert(m.ah.lastWhy == "database", tostring(m.ah.lastWhy))
  -- the event right after the same scan: not twice
  SENT = {}
  FIRE("scan_done")
  assert(#SENT == 0, "one scan, one send")
  return "big database batch sends; a search doesn't; once per scan"
end''')

# Auctionator not ready at login: hooked by the retry
L, lmod = None, None
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('ME = "Anna-R"')
lua.execute(STUBS)
lua.execute('SAVED_A = Auctionator; Auctionator = nil')
m = lua.eval('{}')
for f in ('Module.lua', 'Bulk.lua', 'AuctionatorShare.lua'):
    src = open('MMT_QoL/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, m)
print(lua.eval(r'''function(m)
  m.M.OnEnable(m.M)
  assert(not m.ah.hooked, "not yet")
  Auctionator = SAVED_A
  for _, t in ipairs(TICKERS) do if not t.off then t.fn() end end
  assert(m.ah.hooked and m.ah.events == "scan_done", "hooked later: " .. tostring(m.ah.events))
  return "hooked once Auctionator is ready"
end''')(m))
print('auctionator share ok')
