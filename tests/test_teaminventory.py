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
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end, UnregisterAllEvents = function() end } end
function UnitClass() if ME == "Bob-Stone" then return "Warrior", "WARRIOR" end return "Shaman", "SHAMAN" end
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
SlashCmdList = {}
MMT = { CopyTable = copy, UI = {}, ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }, status = {} }
function MMT.IsSecret() return false end
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
function MMT.PlayerFull() return ME end
function MMT.IsSelf(k) return k == ME end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Ago() return "1 min ago" end
function MMT.Print() end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = { msg = msg } end
function MMT.SendAddon(msg, _, to) SENT[#SENT + 1] = { msg = msg, to = to } end
function MMT.SendLong(text, to) SENT[#SENT + 1] = { msg = text, to = to, long = true } end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  function M:Listen(ev, fn) LISTEN[ev] = fn end
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
