"""MMT_Whispers: two clients. Anna (group leader) is the receiver, Bob the alt.
Bob's whispers reach Anna's chat window, Anna's whispers to Bob are passed on."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
EVENTS, LISTEN, ADDON, CHAT, LINES, REPLY = {}, {}, {}, {}, {}, nil
LEADER = "Anna-Smith"
local TEAM = { ["Anna-Smith"] = { name = "Anna", last = "Smith", roles = { Main = true } },
               ["Bob-Stone"] = { name = "Bob", last = "Stone", roles = {} } }
local function norm(s) return ((s or ""):lower():gsub("[^%w\128-\255]", "")) end
MMT = {
  CopyTable = copy, NormKey = norm,
  IsSecret = function(v) return type(v) == "table" and v.secret end,
  Print = function() end, ToggleConfig = function() end,
  UI = {}, ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 },
}
function MMT.Safe(fn, ...) local ok, a, b, c = pcall(fn, ...) if ok then return a, b, c end end
function MMT.StripRealm(s) return (s:gsub("%-Realm$", "")) end
function MMT.PlayerFull() return ME end
function MMT.IsSelf(k) return type(k) == "string" and norm(MMT.StripRealm(k)) == norm(ME) end
function MMT.Resolve(name)
  if type(name) ~= "string" then return nil end
  for key, m in pairs(TEAM) do
    if norm(key) == norm(MMT.StripRealm(name)) or norm(m.name) == norm(name) then return key end
  end
end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone" } end
function MMT.SortedRoleNames() return { "Main" } end
function MMT.MemberRoleList(key) local t = {} for r in pairs(TEAM[key].roles) do t[#t + 1] = r end return t end
function MMT.IsOnline() return true end
function MMT.WhisperTarget(key) return TEAM[key].name .. " " .. TEAM[key].last end
function MMT.FirstName(key) return (key:match("^[^-]+")) end
function MMT.FullDisplay(key) return (key:gsub("-", " ")) end
function MMT.SplitUnit(u) return nil, nil, u == "party1" and OTHER or ME end
function MMT.SendAddon(msg, channel, target) ADDON[#ADDON + 1] = { msg = msg, to = target } end
function MMT.Ago() return "1 s" end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  function M:Listen(ev, fn) LISTEN[ev] = fn end
  function M:Debug() end
  return M
end
function FIRE(ev, ...) for _, fn in ipairs(EVENTS[ev] or {}) do fn(...) end end
function DELIVER(fromKey, fromName, msg) LISTEN.TEAM_MESSAGE(fromKey, fromName, msg) end

function IsInGroup() return true end
function IsInRaid() return false end
function UnitExists(u) return u == "player" or u == "party1" end
function UnitIsUnit(a, b) return a == b end
function UnitIsGroupLeader(u) return (u == "player" and ME == LEADER) or (u == "party1" and OTHER == LEADER) end
function UnitName() return (ME:match("^[^-]+")) end
ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 1 } end })
ChatFrame1 = { AddMessage = function(_, text) LINES[#LINES + 1] = text end }
DEFAULT_CHAT_FRAME = ChatFrame1
ChatFrameUtil = { SetLastTellTarget = function(name) REPLY = name end }
C_ChatInfo = { SendChatMessage = function(msg, kind, _, target) CHAT[#CHAT + 1] = { msg = msg, kind = kind, to = target } end }
SOUNDKIT = { TELL_MESSAGE = 3081 }
function PlaySound() end
SlashCmdList = {}
date, time = os.date, os.time
'''

def client(me, other):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"; OTHER = "%s"' % (me, other))
    lua.execute(STUBS)
    mod = lua.eval('{}')
    toc = [l.strip() for l in open('MMT_Whispers/MMT_Whispers.toc', encoding='utf-8') if l.strip().endswith('.lua')]
    for f in toc:
        src = open('MMT_Whispers/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_Whispers/' + f, mod)
    return lua, mod

A, amod = client("Anna-Smith", "Bob-Stone")
B, bmod = client("Bob-Stone", "Anna-Smith")

def take(lua):
    msgs = lua.eval('function() local t = {} for i, a in ipairs(ADDON) do t[i] = a.msg end ADDON = {} return t end')()
    return [msgs[i] for i in range(1, len(msgs) + 1)]

def deliver(msgs, lua, fromKey, fromName):
    for m in msgs: lua.eval('DELIVER')(fromKey, fromName, m)

# who receives: Anna leads the group, so she does; Bob forwards
print("A:", A.eval(r'''function(m)
  assert(m.IAmReceiver(), "the leader isn't the receiver")
  m.M.db.to = "ROLE:Main"; assert(m.IAmReceiver(), "role receiver")
  m.M.db.to = "CHAR:Bob-Stone"; assert(not m.IAmReceiver(), "char receiver")
  m.M.db.to = "LEADER"
  return "receivers ok"
end''')(amod))

# a whisper to Bob reaches Anna's chat, R goes to Bob
print("B:", B.eval(r'''function(m)
  assert(not m.IAmReceiver(), "the alt thinks it receives")
  FIRE("CHAT_MSG_WHISPER", "hello there, got a sec?", "Stranger-Realm", "", "", "", "")
  assert(#ADDON == 1 and ADDON[1].to == "Anna Smith" and ADDON[1].msg:find("^MWF:%d+:1:1:W::Stranger%-Realm:hello"), "not forwarded: " .. tostring(ADDON[1] and ADDON[1].msg))
  return "forwarded"
end''')(bmod))
deliver(take(B), A, "Bob-Stone", "Bob Stone")
print("A:", A.eval(r'''function(m)
  local l = LINES[#LINES]
  assert(l and l:find("|Hplayer:Stranger%-Realm|h%[Stranger%]|h to |Hplayer:Bob Stone|h%[Bob%]|h: hello there", 1), "line: " .. tostring(l))
  assert(REPLY == "Bob Stone", "reply target " .. tostring(REPLY))
  return "shown + reply ok"
end''')(amod))

# a long whisper (several parts), a GM, automatic answers, ignored words, secret texts
print("B:", B.eval(r'''function(m)
  FIRE("CHAT_MSG_WHISPER", string.rep("x", 300) .. " end", "Gm-Realm", "", "", "", "GM")
  assert(#ADDON == 2, "parts " .. #ADDON)
  return "long whisper sent in " .. #ADDON .. " parts"
end''')(bmod))
deliver(take(B), A, "Bob-Stone", "Bob Stone")
print("A:", A.eval(r'''function(m)
  local l = LINES[#LINES]
  assert(l:find("<GM> ", 1, true) and l:find(string.rep("x", 300) .. " end", 1, true), "long / GM line")
  return "long + GM ok"
end''')(amod))
print("B:", B.eval(r'''function(m)
  m.M.db.ignore = "wts, Boost"
  FIRE("CHAT_MSG_WHISPER", "<DBM> Bob is busy fighting", "Stranger-Realm", "", "", "", "")
  FIRE("CHAT_MSG_WHISPER", "cheap BOOST runs", "Spam-Realm", "", "", "", "")
  FIRE("CHAT_MSG_WHISPER", { secret = true }, "Stranger-Realm", "", "", "", "")
  assert(#ADDON == 0, "skipped whisper forwarded")
  -- the receiver doesn't forward its own whispers
  return "skips ok"
end''')(bmod))
print("A:", A.eval(r'''function(m)
  FIRE("CHAT_MSG_WHISPER", "hi Anna", "Stranger-Realm", "", "", "", "")
  assert(#ADDON == 0, "the receiver forwarded")
  return "receiver keeps its own"
end''')(amod))

# Anna whispers Bob: Bob passes it on to the last sender; "@name" picks another
print("B:", B.eval(r'''function(m)
  FIRE("CHAT_MSG_WHISPER", "sure, what's up?", "Anna Smith", "", "", "", "")
  assert(#CHAT == 1 and CHAT[1].to == "Gm-Realm" and CHAT[1].msg == "sure, what's up?", "not passed on: " .. tostring(CHAT[1] and CHAT[1].to))
  FIRE("CHAT_MSG_WHISPER", "@stran yes", "Anna Smith", "", "", "", "")
  assert(CHAT[2].to == "Stranger-Realm" and CHAT[2].msg == "yes", "@name: " .. tostring(CHAT[2] and CHAT[2].to))
  FIRE("CHAT_MSG_WHISPER", "@Other Guy: see you", "Anna Smith", "", "", "", "")
  assert(CHAT[3].to == "Other Guy" and CHAT[3].msg == "see you", "@First Last:")
  -- what Bob whispered is shown on Anna too
  FIRE("CHAT_MSG_WHISPER_INFORM", "yes", "Stranger-Realm")
  assert(#ADDON == 1 and ADDON[1].msg:find(":I::Stranger%-Realm:yes$"), "inform not forwarded")
  -- nobody to pass it on to
  m.recentSenders = {}
  FIRE("CHAT_MSG_WHISPER", "anyone?", "Anna Smith", "", "", "", "")
  assert(#CHAT == 3 and #ADDON == 2 and ADDON[2].msg:find(":N:"), "no note")
  return "pass on ok"
end''')(bmod))
deliver(take(B), A, "Bob-Stone", "Bob Stone")
print("A:", A.eval(r'''function(m)
  assert(LINES[#LINES - 1]:find("|Hplayer:Bob Stone|h%[Bob%]|h to |Hplayer:Stranger%-Realm|h%[Stranger%]|h: yes"), "inform line: " .. LINES[#LINES - 1])
  assert(LINES[#LINES]:find("Nobody has whispered me yet", 1, true), "note line")
  -- reply straight to the sender instead
  m.M.db.reply = "DIRECT"
  m.Show("Bob-Stone", "Bob Stone", "W", "", "Stranger-Realm", "again")
  assert(REPLY == "Stranger-Realm", "direct reply")
  local n = 0
  m.M.Report(m.M, function() n = n + 1 end)
  assert(n >= 2, "report")
  return "inform + note + direct reply ok"
end''')(amod))
