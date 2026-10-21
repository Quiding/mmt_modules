"""MMT_TeamInventory: two clients (Anna, Bob). Counting bags / bank / mail /
equipped, the heartbeat hash, snapshot and change messages, and the tooltip
lines (alone and next to Syndicator)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
EVENTS, LISTEN, SENT = {}, {}, {}
NOW = 1000
function GetTime() return NOW end
time = os.time
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
  CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 } }
BAGS = { [0] = { { itemID = 13446, stackCount = 4 }, { itemID = 2589, stackCount = 20 } }, [1] = { { itemID = 13446, stackCount = 1 } } }
BANKBAGS = { [6] = { { itemID = 2589, stackCount = 40 } } }
EQUIP = { [16] = 5000 }
MAIL = { { 13446, 2 } }
MAILOPEN = false
C_Container = {
  GetContainerNumSlots = function(bag) local b = BAGS[bag] or BANKBAGS[bag] return b and #b or 0 end,
  GetContainerItemInfo = function(bag, slot) local b = BAGS[bag] or BANKBAGS[bag] return b and b[slot] end,
}
function GetInventoryItemID(_, slot) return EQUIP[slot] end
function GetInboxNumItems() return MAILOPEN and #MAIL or 0 end
function GetInboxItem(i, a) if a == 1 and MAIL[i] then return "x", MAIL[i][1], 1, MAIL[i][2] end end
MailFrame = { IsShown = function() return MAILOPEN end }
C_Timer = { After = function(_, f) f() end }
function IsLoggedIn() return false end
FRAMES = {}
function CreateFrame()
  local f = { RegisterEvent = function() end, UnregisterAllEvents = function() end }
  function f:SetScript(ev, fn) self[ev] = fn end
  FRAMES[#FRAMES + 1] = f
  return f
end
function TICK() for _, f in ipairs(FRAMES) do if f.OnUpdate then f.OnUpdate(f, 1) end end end
-- trade window: our 6 slots, the cursor
TRADE, CURSOR = {}, nil
ERR_TRADE_COMPLETE = "Trade complete."
function GetTradePlayerItemLink(s) local t = TRADE[s] return t and ("|Hitem:" .. t.id .. ":0|h[x]|h") end
function GetTradePlayerItemInfo(s) local t = TRADE[s] if t then return "x", 1, t.n end end
function ClickTradeButton(s) if CURSOR and not TRADE[s] then TRADE[s] = CURSOR; CURSOR = nil end end
function CursorHasItem() return CURSOR ~= nil end
TARGET, MONEY, TMONEY, ACCEPTED = {}, 0, 0, 0
function GetTradeTargetItemLink(s) local t = TARGET[s] return t and ("|Hitem:" .. t.id .. ":0|h[x]|h") end
function GetTradeTargetItemInfo(s) local t = TARGET[s] if t then return "x", 1, t.n end end
function GetPlayerTradeMoney() return MONEY end
function GetTargetTradeMoney() return TMONEY end
function AcceptTrade() ACCEPTED = ACCEPTED + 1 end
function ClearCursor() CURSOR = nil end
function UnitFullName(u) if u == "NPC" then return PARTNER end end
-- like the core: first, last, team key ("First-Last"); UNITS[unit] = team key
UNITS = {}
function MMT_SPLIT(u)
  if u == "NPC" then return PARTNER, nil, PARTNER end
  local k = UNITS[u]
  if k then local f, l = k:match("^([^-]+)%-?(.*)$") return f, l ~= "" and l or nil, k end
end
function GetServerTime() return SERVERTIME end
SERVERTIME = 5000
function UnitClass() if ME == "Bob-Stone" then return "Warrior", "WARRIOR" end return "Shaman", "SHAMAN" end
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
SlashCmdList = {}
MMT = { CopyTable = copy, UI = {}, ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }, status = {} }
function MMT.IsSecret() return false end
-- like the core: only the first 7 values (a longer read needs its own pcall)
function MMT.Safe(fn, ...) local ok, a, b, c, d, e, f, g = pcall(fn, ...) if ok then return a, b, c, d, e, f, g end end
function MMT.PlayerFull() return ME end
function MMT.IsSelf(k) return k == ME end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Ago() return "1 min ago" end
function MMT.Print() end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = { msg = msg } end
function MMT.SendAddon(msg, _, to) SENT[#SENT + 1] = { msg = msg, to = to } end
function MMT.SendLong(text, to) SENT[#SENT + 1] = { msg = text, to = to, long = true } end
function MMT.SplitUnit(u) return MMT_SPLIT(u) end
function MMT.Resolve(name) if name == "Anna" then return "Anna-Smith" elseif name == "Bob" then return "Bob-Stone" end end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  -- every listener of a callback runs (like the core); LISTEN.X(...) calls them all
  function M:Listen(ev, fn)
    LISTEN[ev] = LISTEN[ev] or setmetatable({}, { __call = function(t, ...) for _, f in ipairs(t) do f(...) end end })
    table.insert(LISTEN[ev], fn)
  end
  function M:Heartbeat(k, fn) HEARTBEAT = fn end
  return M
end
function FIRE(ev, ...) for _, fn in ipairs(EVENTS[ev] or {}) do fn(...) end end
function DELIVER(fromKey, msg) LISTEN.TEAM_MESSAGE(fromKey, fromKey, msg) end
'''

def client(me):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"' % me)
    lua.execute(STUBS)
    mod = lua.eval('{}')
    for f in [l.strip() for l in open('MMT_TeamInventory/MMT_TeamInventory.toc', encoding='utf-8') if l.strip().endswith('.lua')]:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open('MMT_TeamInventory/' + f, encoding='utf-8').read(), f, mod)
    return lua, mod

A, amod = client("Anna-Smith")
B, bmod = client("Bob-Stone")

def take(lua):
    t = lua.eval('function() local t = {} for i, s in ipairs(SENT) do t[i] = s.msg end SENT = {} return t end')()
    return [t[i] for i in range(1, len(t) + 1)]

# Bob counts his bags and equipped items (bank and mail aren't open)
print("B:", B.eval(r'''function(m)
  m.M.OnEnable(m.M)
  local rec = m.Own()
  assert(rec.b[13446] == 5 and rec.b[2589] == 20 and rec.e[5000] == 1, "bags / equipped")
  assert(next(rec.k) == nil and next(rec.m) == nil, "bank / mail read while closed")
  assert(m.Mine()["Bob-Stone"], "own character not marked as this account's")
  -- the bank: only while open, kept after closing
  FIRE("BANKFRAME_OPENED")
  assert(rec.k[2589] == 40, "bank not counted")
  FIRE("BANKFRAME_CLOSED")
  BANKBAGS = {}
  FIRE("BAG_UPDATE_DELAYED")
  assert(rec.k[2589] == 40, "bank lost after closing")
  -- mail: only with the mailbox open
  FIRE("MAIL_INBOX_UPDATE")
  assert(next(rec.m) == nil, "mail read without the mailbox")
  MAILOPEN = true
  FIRE("MAIL_INBOX_UPDATE")
  assert(rec.m[13446] == 2, "mail")
  MAILOPEN = false
  FIRE("MAIL_CLOSED")
  assert(HEARTBEAT() == rec.hash and rec.hash == m.Hash(rec), "heartbeat hash")
  SENT = {}
  return "counting ok"
end''')(bmod))

# Anna sees a different hash on Bob's heartbeat: asks; Bob answers with everything
hb = B.eval('function() return tostring(HEARTBEAT()) end')()
print("A:", A.eval(r'''function(m, hb)
  m.M.OnEnable(m.M)
  SENT = {}
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tiv = hb } })
  assert(#SENT == 1 and SENT[1].msg == "TIVREQ" and SENT[1].to == "Bob", "no request")
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tiv = hb } })
  assert(#SENT == 1, "asked twice within a minute")
  SENT = {}
  return "request ok"
end''')(amod, hb))
print("B:", B.eval(r'''function(m)
  DELIVER("Anna-Smith", "TIVREQ")
  assert(#SENT == 1 and SENT[1].long and SENT[1].to == "Anna-Smith" and SENT[1].msg:find("^TIVS:"), "no snapshot")
  return "snapshot sent"
end''')(bmod))
for msg in take(B): A.eval('DELIVER')("Bob-Stone", msg)
print("A:", A.eval(r'''function(m, hb)
  local rec = m.Chars()["Bob-Stone"]
  assert(rec and rec.b[13446] == 5 and rec.k[2589] == 40 and rec.m[13446] == 2, "snapshot not stored")
  assert(rec.class == "WARRIOR", "class not sent along: " .. tostring(rec.class))
  assert(tostring(rec.hash) == hb and tostring(m.Hash(rec)) == hb, "hash")
  -- the tooltip: Anna's own items + Bob's, Bob's class colour, places
  local lines = m.TooltipLines(13446)
  assert(lines and lines[1][1] == "Team inventory" and lines[1][2]:find("12", 1, true), "total: " .. tostring(lines and lines[1][2]))
  local bob
  for _, l in ipairs(lines) do if l[1]:find("Bob Stone", 1, true) then bob = l end end
  assert(bob and bob[1]:find("|cffc79c6e", 1, true) and bob[2]:find("bags", 1, true) and bob[2]:find("mail", 1, true), "Bob's line")
  assert(m.TooltipLines(99999) == nil, "lines for an item nobody has")
  -- equipped items can be left out
  m.M.db.equipped = false
  assert(m.TooltipLines(5000) == nil, "equipped counted while off")
  m.M.db.equipped = true
  -- next to Syndicator: only other accounts' characters, the total counts everyone
  Syndicator = { API = { GetInventoryInfoByItemID = function() end } }
  lines = m.TooltipLines(13446)
  assert(lines[1][1] == "Team (other accounts)" and #lines == 2 and lines[2][1]:find("Bob", 1, true), "Syndicator: others only")
  assert(lines[1][2]:find("12", 1, true), "Syndicator: total")
  m.M.db.withSyndicator = "OFF"
  assert(m.TooltipLines(13446) == nil, "Syndicator OFF")
  m.M.db.withSyndicator = "ALL"
  assert(#m.TooltipLines(13446) == 3, "Syndicator ALL")
  Syndicator = nil
  m.M.db.withSyndicator = "OTHERS"
  return "snapshot + tooltip ok"
end''')(amod, hb))

# Bob uses a potion: only the change goes out; Anna applies it
print("B:", B.eval(r'''function(m)
  BAGS[0][1].stackCount = 3
  FIRE("BAG_UPDATE_DELAYED")
  assert(#SENT == 1 and SENT[1].msg:find("^TIVD:%d+#b13446=4$"), "change: " .. tostring(SENT[1] and SENT[1].msg))
  return "change sent"
end''')(bmod))
for msg in take(B): A.eval('DELIVER')("Bob-Stone", msg)
print("A:", A.eval(r'''function(m)
  local rec = m.Chars()["Bob-Stone"]
  assert(rec.b[13446] == 4 and #SENT == 0, "change not applied / hash mismatch")
  -- a change that doesn't add up (missed message): ask for everything again
  NOW = NOW + 120
  DELIVER("Bob-Stone", "TIVD:12345#b13446=9")
  assert(#SENT == 1 and SENT[1].msg == "TIVREQ", "no request after a hash mismatch")
  local n = 0
  m.M.Report(m.M, function() n = n + 1 end)
  assert(n >= 3, "report")
  return "changes ok"
end''')(amod))

# planned gifts: Anna drags 15 of Bob's 20 Linen Cloth onto herself in the team bags
print("A:", A.eval(r"""function(m)
  SENT = {}
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 15)
  assert(#SENT == 1 and SENT[1].msg == "TIVG:2589:15:5000:Bob-Stone:Anna-Smith", "plan message: " .. tostring(SENT[1] and SENT[1].msg))
  assert(m.PlannedOut("Bob-Stone", 2589) == 15 and m.PlannedIn("Anna-Smith")[1].n == 15, "plan not stored")
  return "gift planned"
end""")(amod))
for msg in take(A): B.eval('DELIVER')("Anna-Smith", msg)
print("B:", B.eval(r"""function(m)
  assert(m.PlannedOut("Bob-Stone", 2589) == 15, "plan didn't reach the giver")
  -- a trade with someone else: nothing goes in
  PARTNER = "Wally"
  FIRE("TRADE_SHOW")
  assert(next(TRADE) == nil, "items put into a trade with someone else")
  FIRE("TRADE_CLOSED")
  -- the core (or Bob) already put 5 linen in: only 10 more, split off the stack of 20
  PARTNER = "Anna"
  TRADE = { [1] = { id = 2589, n = 5 } }
  C_Container.SplitContainerItem = function(bag, slot, n) CURSOR = { id = BAGS[bag][slot].itemID, n = n, split = true } end
  C_Container.PickupContainerItem = function(bag, slot) CURSOR = { id = BAGS[bag][slot].itemID, n = BAGS[bag][slot].stackCount } end
  FIRE("TRADE_SHOW")
  assert(TRADE[2] and TRADE[2].id == 2589 and TRADE[2].n == 10 and TRADE[2].split, "not split into the trade: " .. tostring(TRADE[2] and TRADE[2].n))
  assert(not TRADE[3], "too much put in")
  -- the button under the trade window again: it counts what's already in, adds nothing
  assert(m.FillTrade(true) == 0 and not TRADE[3], "filled twice")
  -- the trade completes: 15 handed over, the plan is done and the team told
  TICK()
  SENT = {}
  SERVERTIME = 5100
  FIRE("TRADE_CLOSED")
  FIRE("UI_INFO_MESSAGE", 0, "Trade complete.")
  assert(m.PlannedOut("Bob-Stone", 2589) == 0, "plan not done after the trade")
  assert(#SENT == 1 and SENT[1].msg == "TIVG:2589:0:5100:Bob-Stone:Anna-Smith", "done message: " .. tostring(SENT[1] and SENT[1].msg))
  TRADE = {}
  -- soulbound stacks are left alone
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 5)
  BAGS[0][2].isBound = true
  FIRE("TRADE_SHOW")
  assert(next(TRADE) == nil, "a soulbound stack went into the trade")
  BAGS[0][2].isBound = nil
  -- a cancelled trade ("Trade cancelled" is not "Trade complete") changes nothing
  FIRE("TRADE_CLOSED")
  FIRE("UI_INFO_MESSAGE", 0, "Trade cancelled.")
  assert(m.PlannedOut("Bob-Stone", 2589) == 5, "cancelled trade changed the plan")
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 0)
  return "trade filled + plan done"
end""")(bmod))
for msg in take(B): A.eval('DELIVER')("Bob-Stone", msg)
print("A:", A.eval(r"""function(m)
  assert(m.PlannedOut("Bob-Stone", 2589) == 0 and #m.PlannedIn("Anna-Smith") == 0, "done not applied")
  -- an older copy (a client that was offline) can't bring it back
  DELIVER("Wally-Warrior", "TIVG:2589:15:5000:Bob-Stone:Anna-Smith")
  assert(m.PlannedOut("Bob-Stone", 2589) == 0, "old plan came back")
  -- a member seen online for the first time gets the plans they're in, whispered
  -- (only the plans Wally gives or gets; Bob was seen before, he got his by the team message)
  m.SetGive("Anna-Smith", "Wally-Warrior", 13446, 2)
  SENT = {}
  LISTEN.XP_RECEIVED("Wally-Warrior", "Wally", {})
  local n = 0
  for _, s in ipairs(SENT) do if s.msg:find("^TIVG:") and s.to == "Wally" then n = n + 1 end end
  assert(n == 1, "plans whispered on first sight: " .. n)
  SENT = {}
  LISTEN.XP_RECEIVED("Wally-Warrior", "Wally", {})
  for _, s in ipairs(SENT) do assert(not s.msg:find("^TIVG:"), "whispered again") end
  return "gift sync ok"
end""")(amod))

# "Trade now": Anna asks; Bob's client (the giver) opens the trade with her
print("A:", A.eval(r"""function(m)
  SENT = {}
  m.RequestTrade("Bob-Stone", "Anna-Smith")
  assert(#SENT == 1 and SENT[1].msg == "TIVT:Bob-Stone:Anna-Smith", "trade request: " .. tostring(SENT[1] and SENT[1].msg))
  return "trade asked"
end""")(amod))
print("B:", B.eval(r"""function(m)
  local traded
  function InitiateTrade(u) traded = u end
  -- grouped: Anna is party2; party1 is another "Anna" (same first name, other last name)
  UNITS = { party1 = "Anna-Jones", party2 = "Anna-Smith" }
  SENT = {}
  DELIVER("Anna-Smith", "TIVT:Bob-Stone:Anna-Smith")
  assert(traded == "party2" and #SENT == 0, "group trade: " .. tostring(traded))
  -- not grouped: her nameplate
  traded, UNITS = nil, { nameplate7 = "Anna-Smith" }
  C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate7" } } end }
  DELIVER("Anna-Smith", "TIVT:Bob-Stone:Anna-Smith")
  assert(traded == "nameplate7", "nameplate trade: " .. tostring(traded))
  -- a request for another giver: not us
  traded = nil
  DELIVER("Anna-Smith", "TIVT:Wally-Warrior:Anna-Smith")
  assert(traded == nil and #SENT == 0, "acted on someone else's request")
  -- nowhere to be found: tell the one who asked
  UNITS, C_NamePlate = {}, nil
  DELIVER("Anna-Smith", "TIVT:Bob-Stone:Anna-Smith")
  assert(traded == nil and #SENT == 1 and SENT[1].msg == "TIVN:Bob-Stone:Anna-Smith" and SENT[1].to == "Anna-Smith", "no not-found answer")
  return "trade opened"
end""")(bmod))
print("A:", A.eval(r"""function(m)
  local said
  MMT.Print = function(fmt, ...) said = select("#", ...) > 0 and fmt:format(...) or fmt end
  function MMT.FirstName(k) return (k:match("^[^-]+")) end
  DELIVER("Bob-Stone", "TIVN:Bob-Stone:Anna-Smith")
  assert(said and said:find("can't find Anna", 1, true), "not-found not shown: " .. tostring(said))
  MMT.Print = function() end
  return "not found shown"
end""")(amod))

# auto-accept: a trade of nothing but planned gifts, on both sides
print("B:", B.eval(r"""function(m)
  SENT, TRADE, TARGET, ACCEPTED = {}, {}, {}, 0
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 10)
  PARTNER = "Anna"
  FIRE("TRADE_SHOW")
  assert(TRADE[1] and TRADE[1].n == 10, "not filled")
  TICK()
  assert(ACCEPTED == 0, "accepted before the trade was steady")
  NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "giver didn't accept a trade of planned items")
  NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "accepted twice without a change")
  -- the partner adds gold: changed, not accepted again
  TMONEY = 100
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "accepted with gold in the trade")
  TMONEY = 0
  -- the partner puts an item in: not ours to accept
  TARGET = { [1] = { id = 13446, n = 1 } }
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "accepted with an unplanned item from the partner")
  TARGET = {}
  -- something unplanned on our side
  TRADE[2] = { id = 13446, n = 1 }
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "accepted with an unplanned item of ours")
  TRADE[2] = nil
  -- back to only the plan: accepted again; setting off: never
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 2, "not accepted again after the trade went back to the plan")
  FIRE("TRADE_CLOSED")
  m.M.db.autoAccept = false
  TRADE = {}
  FIRE("TRADE_SHOW")
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 2, "accepted with the setting off")
  m.M.db.autoAccept = true
  FIRE("TRADE_CLOSED")
  -- not all of it in yet (another stack still to add): wait
  TRADE = { [1] = { id = 2589, n = 4 } }
  m.M.db.giveTrade = false
  FIRE("TRADE_SHOW")
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 2, "accepted before everything planned was in")
  m.M.db.giveTrade = true
  FIRE("TRADE_CLOSED")
  TRADE = {}
  return "giver auto-accept ok"
end""")(bmod))
for msg in take(B): A.eval('DELIVER')("Bob-Stone", msg)
print("A:", A.eval(r"""function(m)
  TRADE, TARGET, ACCEPTED = {}, {}, 0
  PARTNER = "Bob"
  -- Bob gives the planned 10: Anna accepts
  TARGET = { [1] = { id = 2589, n = 10 } }
  FIRE("TRADE_SHOW")
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "receiver didn't accept planned gifts")
  -- more than planned: no
  TARGET = { [1] = { id = 2589, n = 11 } }
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "receiver accepted more than planned")
  FIRE("TRADE_CLOSED")
  -- someone without a plan: no
  PARTNER = "Wally"
  TARGET = { [1] = { id = 2589, n = 10 } }
  FIRE("TRADE_SHOW")
  TICK(); NOW = NOW + 2; TICK()
  assert(ACCEPTED == 1, "accepted a trade from someone without a plan")
  FIRE("TRADE_CLOSED")
  TARGET = {}
  return "receiver auto-accept ok"
end""")(amod))

# a gift "from __ALL__" saved by 0.4.1 is removed the first time the plans are read
C, cmod = client("Cara-Sun")
print("C:", C.eval(r"""function(m)
  m.M.store.gives = { __ALL__ = { ["Bob-Stone"] = { [2589] = { n = 1, t = 1 } } },
    ["Anna-Smith"] = { __BYCHAR__ = { [2589] = { n = 2, t = 1 } }, ["Bob-Stone"] = { [6948] = { n = 1, t = 1 } } } }
  assert(#m.PlannedIn("Bob-Stone") == 1 and m.PlannedIn("Bob-Stone")[1].from == "Anna-Smith", "old view gift still there")
  assert(m.Gives().__ALL__ == nil and m.Gives()["Anna-Smith"].__BYCHAR__ == nil, "not cleaned")
  return "old view gifts cleaned"
end""")(cmod))

# the owner's client counts soulbound stacks in its bags (s) and sends them; the hash stays the same
print("B:", B.eval(r"""function(m)
  SENT = {}
  local before = m.Own().hash
  BAGS[1][1].isBound = true          -- the potion in bag 1 became soulbound
  FIRE("BAG_UPDATE_DELAYED")
  local rec = m.Own()
  assert(rec.s[13446] == 1, "soulbound not counted")
  assert(rec.hash == before, "soulbound changed the hash")
  assert(#SENT == 1 and SENT[1].msg:find("s13446=1", 1, true), "soulbound change not sent: " .. tostring(SENT[1] and SENT[1].msg))
  return "soulbound counted"
end""")(bmod))
for msg in take(B): A.eval('DELIVER')("Bob-Stone", msg)
print("A:", A.eval(r"""function(m)
  local rec = m.Chars()["Bob-Stone"]
  assert(rec.s and rec.s[13446] == 1, "soulbound count not stored")
  -- and it comes along in a full copy too
  local copy = m.Decode(m.Encode(rec))
  assert(copy.s[13446] == 1 and copy.b[13446] == rec.b[13446], "soulbound not in the snapshot")
  return "soulbound shared"
end""")(amod))

# AcceptTrade missing on the client: the Trade button instead; neither: one note, never "accepted"
print("A:", A.eval(r"""function(m)
  local said = {}
  MMT.Print = function(fmt, ...) said[#said + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
  local real = AcceptTrade
  AcceptTrade = nil
  local clicked = 0
  TradeFrameTradeButton = { Click = function() clicked = clicked + 1 end }
  assert(m.AcceptTrade() == true and clicked == 1, "button not clicked")
  TradeFrameTradeButton = nil
  assert(m.AcceptTrade() == false and m.AcceptTrade() == false, "accepted without a way to")
  local notes = 0
  for _, t in ipairs(said) do if t:find("couldn't accept", 1, true) then notes = notes + 1 end end
  assert(notes == 1, "note not shown once: " .. notes)
  -- the watcher: no "accepted" message when it didn't work
  said = {}
  PARTNER, TARGET = "Bob", { [1] = { id = 2589, n = 10 } }
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 10)
  FIRE("TRADE_SHOW")
  TICK(); NOW = NOW + 2; TICK()
  for _, t in ipairs(said) do assert(not t:find("accepted", 1, true), "said accepted: " .. t) end
  FIRE("TRADE_CLOSED")
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 0)
  TARGET, AcceptTrade, MMT.Print = {}, real, function() end
  return "accept fallback ok"
end""")(amod))

# gold: own from GetMoney (and on PLAYER_MONEY), others from the core's heartbeat; kept when the items are re-sent
print("A:", A.eval(r"""function(m)
  MONEY_ME = 25000
  GetMoney = function() return MONEY_ME end
  FIRE("PLAYER_MONEY")
  assert(m.Gold("Anna-Smith") == 25000, "own gold")
  MONEY_ME = 30000
  FIRE("PLAYER_MONEY")
  assert(m.Gold("Anna-Smith") == 30000, "own gold after a change")
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { money = 777777 })
  assert(m.Gold("Bob-Stone") == 777777, "Bob's gold from the heartbeat")
  -- a full copy of Bob's items replaces the record: the gold stays
  DELIVER("Bob-Stone", "TIVS:1:WARRIOR#b=2589x1")
  assert(m.Gold("Bob-Stone") == 777777, "gold lost with a snapshot")
  return "gold ok"
end""")(amod))
