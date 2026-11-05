"""MMT_QoL's No flash: FlashClientIcon wrapped at file load (an addon's own copy taken
after that is wrapped too), straight through while the feature is off, each source
stopped unless ticked, ticked ones only on the FTL leader / every character / nowhere,
a stack that says nothing decided one frame later from the events around it."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
FLASHES, PRINTS, LATER, STACK, NOW, LEADER = 0, {}, {}, "", 1000, nil
function FlashClientIcon() FLASHES = FLASHES + 1 end
function debugstack() return "Interface/AddOns/MMT_QoL/NoFlash.lua:1: in function <x>\n" .. STACK end
function GetTime() return NOW end
C_Timer = { After = function(_, fn) LATER[#LATER + 1] = fn end }
function RUN_LATER() local t = LATER; LATER = {} for _, fn in ipairs(t) do fn() end end
SlashCmdList = {}
MMT = { CopyTable = copy, IsSecret = function() return false end, UI = {}, ConfigHelpers = {} }
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function MMT.FTLLeader() return LEADER end
function MMT.IsSelf(k) return k == "Anna-Smith" end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  function M:On() end
  function M:Listen() end
  function M:Debug() end
  return M
end
'''

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute('ORIGINAL = FlashClientIcon')
mod = lua.eval('{}')
for f in ["Module.lua", "NoFlash.lua"]:
    src = open('MMT_QoL/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)

def run(code):
    print(lua.eval(code)(mod))

run(r'''function(m)
  assert(FlashClientIcon ~= ORIGINAL and m.nf.wrapped, "not wrapped at load")
  RXP_COPY = FlashClientIcon   -- like RXPGuides' local copy, taken after us
  local f
  for _, x in ipairs(m.features) do if x.key == "noflash" then f = x end end
  assert(f and f.addon == nil and not f.sendOnly, "not a local feature")
  assert(m.M.defaults.noflash == false and m.M.db.noflash == false, "on by default")
  F = f
  STACK = "Interface/FrameXML/ReadyCheck.lua:10: in function <ShowReadyCheck>"
  FlashClientIcon()
  assert(FLASHES == 1 and m.nf.passed == 1, "feature off: the flash didn't go through")
  m.M.db.noflash = true
  assert(m.Active(f), "local feature not active")
  m.M.enabled = false; FlashClientIcon(); m.M.enabled = true
  assert(FLASHES == 2, "module off: the flash didn't go through")
  return "wrapped at load; off (feature or module): straight through"
end''')

run(r'''function(m)
  FLASHES = 0
  FlashClientIcon(); assert(FLASHES == 0 and m.nf.blocked.ready == 1, "ready check not stopped")
  m.M.db.nfReady = true
  FlashClientIcon(); assert(FLASHES == 1 and m.nf.allowed.ready == 1, "ticked + solo: not let through")
  LEADER = "Bob-Stone"; FlashClientIcon(); assert(FLASHES == 1, "flashed on a follower")
  LEADER = "Anna-Smith"; FlashClientIcon(); assert(FLASHES == 2, "not on the FTL leader")
  LEADER = "Bob-Stone"; m.M.db.nfWhere = "ALL"; FlashClientIcon(); assert(FLASHES == 3, "Every character: not here")
  m.M.db.nfWhere = "OFF"; LEADER = "Anna-Smith"; FlashClientIcon(); assert(FLASHES == 3, "No character: flashed")
  m.M.db.nfWhere = "LEADER"; LEADER = nil
  return "ready check: stopped, ticked -> only on the FTL leader / every character / nowhere"
end''')

run(r'''function(m)
  FLASHES = 0
  -- an addon's own copy (RXPGuides), its folder in the stack
  STACK = "Interface/AddOns/RXPGuides/Targeting.lua:348: in function <Interface/AddOns/RXPGuides/Targeting.lua:340>"
  RXP_COPY(); assert(FLASHES == 0 and m.nf.blocked.addons == 1, "addon flash not stopped")
  m.M.db.nfAddons = true; RXP_COPY(); assert(FLASHES == 1, "ticked addon flash stopped")
  assert(m.nf.last:find("RXPGuides", 1, true), "who: " .. tostring(m.nf.last))
  -- Blizzard's own AddOns folders are Blizzard: the chat frame = whisper
  STACK = "Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrame.lua:99: in function <ChatFrame_MessageEventHandler>"
  FlashClientIcon(); assert(FLASHES == 1 and m.nf.blocked.whisper == 1, "whisper: " .. tostring(m.nf.last))
  return "addons (their own copy too) and Blizzard_ folders told apart"
end''')

run(r'''function(m)
  FLASHES = 0
  -- UIParent_OnEvent says nothing: the invite event (reaching us after the flash) decides, one frame later
  STACK = "Interface/FrameXML/UIParent.lua:1200: in function <UIParent_OnEvent>"
  FlashClientIcon(); assert(FLASHES == 0 and #LATER == 1, "not deferred")
  NOW = NOW + 0.02; m.NoFlashSeen("PARTY_INVITE_REQUEST"); RUN_LATER()
  assert(FLASHES == 0 and m.nf.blocked.group == 1, "invite: " .. tostring(m.nf.last))
  m.M.db.nfGroup = true
  NOW = NOW + 5; m.NoFlashSeen("PARTY_INVITE_REQUEST"); FlashClientIcon(); RUN_LATER()
  assert(FLASHES == 1 and m.nf.allowed.group == 1, "ticked invite stopped")
  -- nothing around it: "Anything else"
  NOW = NOW + 5; FlashClientIcon(); RUN_LATER()
  assert(FLASHES == 1 and m.nf.blocked.other == 1, "other: " .. tostring(m.nf.last))
  m.M.db.nfOther = true; FlashClientIcon(); RUN_LATER(); assert(FLASHES == 2, "ticked other stopped")
  return "a silent stack: decided from the events around it, else Anything else"
end''')

run(r'''function(m)
  m.M.db.nfLog = true; PRINTS = {}
  STACK = "Interface/FrameXML/ReadyCheck.lua:10: in function <ShowReadyCheck>"; m.M.db.nfReady = false
  FlashClientIcon(); assert(PRINTS[1] and PRINTS[1]:find("stopped ready", 1, true), tostring(PRINTS[1]))
  local lines = {}
  F.Report(function(s) lines[#lines + 1] = s end)
  assert(lines[1]:find("wrapped=true", 1, true) and lines[1]:find("ready 4/3", 1, true), lines[1])
  local rows = {}
  local ui = { Cycle = function(t) rows[#rows + 1] = t end, Check = function(t) rows[#rows + 1] = t end, Note = function() end }
  F.Page(ui)
  assert(#rows == 9, "page rows: " .. #rows)
  return "chat line per flash, report: " .. lines[1]
end''')
