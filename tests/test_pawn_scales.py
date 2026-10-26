"""MMT_PawnCompare/Manage.lua: Pawn scales deleted here and on the team. Two clients
(Anna deletes, Bob is the alt) with a stand-in Pawn; Carl is offline and gets it later."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
LISTEN, SENT, DIALOG, PRINTS, ONLINE = {}, {}, nil, {}, { ["Anna-Smith"] = true, ["Bob-Stone"] = true }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
function GetTime() return 1000 end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
C_AddOns = { GetAddOnMetadata = function() return "0.4.0" end, IsAddOnLoaded = function(n) return n == "Pawn" and PAWN_ON end }
SlashCmdList = {}
local function norm(k) return k end
MMT = { UI = {}, ConfigHelpers = { COL_W = 248, COL2_X = 270 } }
function MMT.PlayerFull() return ME end
function MMT.IsSelf(k) return k == ME end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone", "Carl-Hill" } end
function MMT.IsOnline(k) return ONLINE[k] or false end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Repr(k) return tostring(k) end
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = fmt:format(...) end
function MMT.ModuleActive() return true end
function MMT.Fire(ev, ...) for _, fn in ipairs(LISTEN[ev] or {}) do fn(...) end end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = { msg = msg } end
function MMT.SendAddon(msg, _, to) SENT[#SENT + 1] = { msg = msg, to = to } end
function MMT.UI.Confirm(text, accept, onAccept, cancel, onCancel)
  if DIALOG and DIALOG.onCancel then DIALOG.onCancel() end
  DIALOG = { text = text, onAccept = onAccept, onCancel = onCancel }
end
function ACCEPT() local d = DIALOG; DIALOG = nil; d.onAccept() end
function CANCEL() local d = DIALOG; DIALOG = nil; d.onCancel() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On() end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Heartbeat() end
  function M:Debug() end
  return M
end
function DELIVER(key, msg) MMT.Fire("TEAM_MESSAGE", key, MMT.FullDisplay(key), msg) end

-- stand-in Pawn: custom scales and one read-only provider scale
PAWN_ON = true
PawnIsInitialized = true
PawnCommon = { Scales = {} }
function ADDSCALE(name, provider, visible)
  PawnCommon.Scales[name] = { Values = { Stamina = 1, Strength = 2 }, Provider = provider,
    LocalizedName = provider and ("Built-in " .. name) or nil, visible = visible ~= false }
end
function PawnIsReady() return PAWN_ON end
function PawnGetAllScalesEx()
  local t = {}
  for name, s in pairs(PawnCommon.Scales) do
    t[#t + 1] = { Name = name, LocalizedName = s.LocalizedName or name, IsVisible = s.visible, IsProvider = s.Provider ~= nil }
  end
  table.sort(t, function(a, b) return a.Name < b.Name end)
  return t
end
function PawnGetAllStatValues(name) return PawnCommon.Scales[name].Values end
function PawnDoesScaleExist(name) return PawnCommon.Scales[name] ~= nil end
function PawnScaleIsReadOnly(name) local s = PawnCommon.Scales[name]; return s and s.Provider ~= nil end
RESETS = 0
function PawnResetTooltips() RESETS = RESETS + 1 end
function PawnDeleteScale(name)
  assert(not PawnScaleIsReadOnly(name), "read-only scale deleted")
  if not PawnCommon.Scales[name] then return false end
  PawnCommon.Scales[name] = nil
  return true
end
'''

FILES = ["Module.lua", "Scales.lua", "Manage.lua"]

def client(me):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"' % me)
    lua.execute(STUBS)
    mod = lua.eval('{}')
    for f in FILES:
        src = open('MMT_PawnCompare/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_PawnCompare/' + f, mod)
    return lua, mod

A, amod = client("Anna-Smith")
B, bmod = client("Bob-Stone")

def take(lua):
    t = lua.eval('function() local t = {} for i, s in ipairs(SENT) do t[i] = { s.msg, s.to or "" } end SENT = {} return t end')()
    return [(t[i][1], t[i][2]) for i in range(1, len(t) + 1)]

def deliver(msgs, lua, fromKey):
    for m, _ in msgs: lua.eval('DELIVER')(fromKey, m)

# set up: Anna and Bob share their scales with each other
A.execute('ADDSCALE("Tank"); ADDSCALE("Old"); ADDSCALE("Arms", "Classic"); ADDSCALE("Hidden", nil, false)')
B.execute('ADDSCALE("Tank"); ADDSCALE("Old"); ADDSCALE("Bob\'s ~ scale: 1"); ADDSCALE("Arms", "Classic")')
for lua, m in ((A, amod), (B, bmod)):
    lua.eval('function(m) m.UpdateOwn(false); m.SendScales() end')(m)
deliver(take(A), B, "Anna-Smith")
deliver(take(B), A, "Bob-Stone")

print("A:", A.eval(r'''function(m)
  assert(m.M.sync == true, "no core sync")
  assert(m.M.db.askDelete == true, "askDelete default")
  local rows, by = m.ScaleRows(), {}
  for _, r in ipairs(rows) do by[r.label] = r end
  assert(by.Tank and by.Tank.own and by.Tank.deletable and by.Tank.holders[1] == "Bob-Stone", "own + team row")
  assert(by["Built-in Arms"] and not by["Built-in Arms"].deletable, "built-in scale deletable")
  assert(by["Built-in Arms"].holders[1] == "Bob-Stone", "the team's built-in (shared by display name) not merged")
  assert(by.Hidden and by.Hidden.own and not by.Hidden.own.visible, "hidden own scale missing")
  local bob = by["Bob's ~ scale: 1"]
  assert(bob and not bob.own and bob.deletable, "team-only scale")
  assert(rows[#rows] == bob, "team-only rows come last")
  return #rows .. " rows ok"
end''')(amod))

# Anna deletes "Old" and Bob's scale here and on the team: Carl is offline
print("A:", A.eval(r'''function(m)
  local names = { "Old", "Bob's ~ scale: 1", "Arms" }
  local done = m.DeleteLocal(names)
  assert(#done == 1 and done[1] == "Old" and not PawnCommon.Scales.Old, "local delete")
  assert(PawnCommon.Scales.Arms, "read-only scale gone")
  local now, later = m.SendDelete(names)
  assert(now == 1 and later == 1, "online / offline " .. now .. "/" .. later)
  assert(m.M.store.pendingDel["Carl-Hill"].names.Old, "Carl's pending")
  return "deleted here"
end''')(amod))
msgs = take(A)
assert any(m.startswith("PCMP_S:") for m, _ in msgs), "own changed scales not announced"
dels = [m for m, _ in msgs if m.startswith("PCMP_DEL:")]
assert len(dels) == 1 and "~" in dels[0] and ":" not in dels[0][len("PCMP_DEL:"):].replace("%3A", ""), dels
deliver(msgs, B, "Anna-Smith")

print("B:", B.eval(r'''function(m)
  assert(DIALOG and DIALOG.text:find("Anna Smith", 1, true), "not asked")
  assert(DIALOG.text:find("Old", 1, true) and DIALOG.text:find("Bob's ~ scale: 1", 1, true), "dialog names: " .. DIALOG.text)
  assert(not DIALOG.text:find("Arms", 1, true), "read-only scale offered")
  assert(PawnCommon.Scales.Old, "deleted before asking")
  ACCEPT()
  assert(not PawnCommon.Scales.Old and not PawnCommon.Scales["Bob's ~ scale: 1"], "not deleted")
  assert(PawnCommon.Scales.Tank and PawnCommon.Scales.Arms, "too much deleted")
  return "asked + deleted"
end''')(bmod))
deliver(take(B), A, "Bob-Stone")
print("A:", A.eval(r'''function(m)
  for _, r in ipairs(m.ScaleRows()) do
    assert(r.label ~= "Bob's ~ scale: 1" and r.label ~= "Old", "stale row " .. r.label)
  end
  return "Bob's new scales arrived"
end''')(amod))

# "Keep" leaves them; a second request while the dialog is up joins it; askDelete off deletes at once
B.execute('ADDSCALE("One"); ADDSCALE("Two"); ADDSCALE("Three")')
print("B:", B.eval(r'''function(m)
  DELIVER("Anna-Smith", "PCMP_DEL:One")
  DELIVER("Anna-Smith", "PCMP_DEL:Two")
  assert(DIALOG.text:find("One", 1, true), "first dialog")
  CANCEL()
  -- the second request waited for the first dialog
  assert(DIALOG and DIALOG.text:find("Two", 1, true), "second dialog")
  CANCEL()
  assert(PawnCommon.Scales.One and PawnCommon.Scales.Two, "Keep deleted")
  assert(m.DeleteWaiting() == 0, "queue " .. m.DeleteWaiting())
  DELIVER("Anna-Smith", "PCMP_DEL:Nope~Arms")
  assert(not DIALOG, "asked about scales it can't delete")
  m.M.db.askDelete = false
  DELIVER("Anna-Smith", "PCMP_DEL:Three")
  assert(not DIALOG and not PawnCommon.Scales.Three, "askDelete off")
  -- own messages are ignored
  DELIVER("Bob-Stone", "PCMP_DEL:One")
  assert(PawnCommon.Scales.One, "own message applied")
  m.M.db.askDelete = true
  return "keep / join / no-ask ok"
end''')(bmod))
take(B)

# Carl comes online: the pending delete is whispered once
print("A:", A.eval(r'''function(m)
  MMT.Fire("XP_RECEIVED", "Carl-Hill", "Carl Hill", { ext = {} })
  local found
  for _, s in ipairs(SENT) do if s.msg:find("^PCMP_DEL:") then found = s end end
  assert(found and found.to == "Carl Hill" and found.msg:find("Old", 1, true), "pending not whispered")
  assert(not m.M.store.pendingDel["Carl-Hill"], "pending kept")
  SENT = {}
  MMT.Fire("XP_RECEIVED", "Carl-Hill", "Carl Hill", { ext = {} })
  for _, s in ipairs(SENT) do assert(not s.msg:find("^PCMP_DEL:"), "whispered twice") end
  return "pending ok"
end''')(amod))

# long lists are split below the message limit
print("A:", A.eval(r'''function(m)
  local names = {}
  for i = 1, 40 do names[i] = ("A rather long scale name number %d"):format(i) end
  local msgs = m.DeleteMessages(names)
  assert(#msgs > 1, "not split")
  local n = 0
  for _, msg in ipairs(msgs) do
    assert(#msg <= 240, "too long " .. #msg)
    for part in msg:sub(10):gmatch("[^~]+") do n = n + 1 end
  end
  assert(n == 40, "names lost " .. n)
  return #msgs .. " messages"
end''')(amod))

# without Pawn: only the team's scales, nothing deleted here; sync received redraws
print("A:", A.eval(r'''function(m)
  PAWN_ON = false
  for _, r in ipairs(m.ScaleRows()) do assert(not r.own, "own row without Pawn") end
  assert(#m.DeleteLocal({ "Tank" }) == 0 and PawnCommon.Scales.Tank, "deleted without Pawn")
  DELIVER("Bob-Stone", "PCMP_DEL:Tank")
  assert(not DIALOG and PawnCommon.Scales.Tank, "asked without Pawn")
  PAWN_ON = true
  local before = RESETS
  m.M.OnSyncReceived(m.M, "Bob-Stone")
  assert(RESETS == before + 1, "sync didn't redraw Pawn's tooltips")
  return "no Pawn ok"
end''')(amod))
print("pawn scales: all ok")
