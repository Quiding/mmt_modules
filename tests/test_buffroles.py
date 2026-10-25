"""MMT_Buffs/Roles.lua: who a buff is for ("Only for": player roles, classes, MMT
roles) and each member's player role (set by hand > druid form > a fresh BPR
message > heartbeat > own talents (classic tabs or Forever's trait bands) > class)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
SENT, LISTENERS, EVENTS = {}, {}, {}
NOW = 100
function GetTime() return NOW end
C_Timer = { After = function(_, f) f() end }
function CreateFrame() return { RegisterEvent = function(self, ev) EVENTS[ev] = true end,
  SetScript = function(self, _, fn) TALENT_EVENT = fn end } end
CLASS = "DRUID"
function UnitClass() return "x", CLASS end
TEAM = { ["Me-Self"] = { class = "DRUID", roles = {} }, ["Bob-Stone"] = { class = "WARRIOR", roles = { Tank = true } },
  ["Cid-Ray"] = { class = "DRUID", roles = {} }, ["Dee-Kay"] = { class = "MAGE", roles = { Healer = true } } }
MMT = { CopyTable = copy, status = {} }
function MMT.IsSecret() return false end
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
function MMT.IsSelf(k) return k == "Me-Self" end
function MMT.PlayerFull() return "Me-Self" end
function MMT.MemberRoleList(key) local t = {} for r in pairs(TEAM[key].roles) do t[#t + 1] = r end table.sort(t) return t end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = msg end
SPELLS = { [768] = "Cat Form", [5487] = "Bear Form", [9634] = "Dire Bear Form", [24858] = "Moonkin Form", [33891] = "Tree of Life" }
''')
mod = lua.eval('''function()
  local m = { CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "ALL" }, auras = {} }
  m.M = { enabled = true, db = { playerRoles = {} } }
  function m.M:Heartbeat(k, fn) HEARTBEAT = fn end
  function m.M:Listen(ev, fn) LISTENERS[ev] = fn end
  m.SpellInfo = function(id) return SPELLS[id] end
  m.ClassOf = function(key) return TEAM[key] and TEAM[key].class end
  m.ListLabel = function(c) return c:sub(1, 1) .. c:sub(2):lower() end
  m.Refresh = function() REFRESHED = (REFRESHED or 0) + 1 end
  return m
end''')()
lua.eval('function(src, m) assert(loadstring(src, "Roles.lua"))("x", m) end')(
    open('MMT_Buffs/Roles.lua', encoding='utf-8').read(), mod)

print(lua.eval(r'''function(m)
  -- own talents, classic tabs (name, icon, points): Feral has the most
  GetNumTalentTabs = function() return 3 end
  GetTalentTabInfo = function(t) return "Tree" .. t, "icon", ({ 5, 31, 15 })[t] end
  assert(m.OwnTalentRole() == "MELEE", "classic tabs")
  assert(HEARTBEAT() == "M", "heartbeat " .. tostring(HEARTBEAT()))
  assert(m.PlayerRole("Me-Self") == "MELEE", "own role from talents")
  -- Forever: one trait tree, three bands of node columns
  GetNumTalentTabs = nil
  NOW = NOW + 20
  local nodes = {}
  C_ClassTalents = { GetActiveConfigID = function() return 7 end }
  C_Traits = { GetConfigInfo = function() return { treeIDs = { 99 } } end,
    GetTreeNodes = function() local t = {} for id in pairs(nodes) do t[#t + 1] = id end return t end,
    GetNodeInfo = function(_, id) return nodes[id] end }
  -- columns 1-4 (Balance), 8-11 (Feral), 15-18 (Resto): 5 / 0 / 21 points
  local id = 0
  for _, col in ipairs({ 1, 2, 3, 4, 8, 9, 10, 11, 15, 16, 17, 18 }) do
    id = id + 1
    local pts = (col <= 4 and col == 2 and 5) or (col >= 15 and col <= 17 and 7) or 0
    nodes[id] = { posX = col * 100, ranksPurchased = pts }
  end
  assert(m.OwnTalentRole() == "HEALER", "trait bands: " .. tostring(m.OwnTalentRole()))
  -- a respec: one BPR message at once, not again for the same role
  SENT = {}
  m.OwnRoleSent()
  nodes[1].ranksPurchased = 40   -- now Balance
  TALENT_EVENT()
  assert(#SENT == 1 and SENT[1] == "BPR:C", "BPR on respec: " .. tostring(SENT[1]))
  TALENT_EVENT()
  assert(#SENT == 1, "BPR sent twice for the same role")
  assert(EVENTS.TRAIT_CONFIG_UPDATED, "talent events not registered")

  -- others: class default, heartbeat, a fresh BPR, a druid's form, set by hand
  assert(m.PlayerRole("Bob-Stone") == "MELEE", "class default")
  MMT.status["Bob-Stone"] = { ext = { bpr = "T" } }
  assert(m.PlayerRole("Bob-Stone") == "TANK", "heartbeat")
  LISTENERS.TEAM_MESSAGE("Bob-Stone", "Bob", "BPR:M")
  assert(m.PlayerRole("Bob-Stone") == "MELEE", "fresh BPR beats the heartbeat")
  NOW = NOW + 60
  assert(m.PlayerRole("Bob-Stone") == "TANK", "after 40 s the heartbeat (which carries it by then) counts again")
  MMT.status["Cid-Ray"] = { ext = { bpr = "H" } }
  assert(m.PlayerRole("Cid-Ray") == "HEALER", "resto druid out of form")
  m.auras["Cid-Ray"] = { ["Cat Form"] = {} }
  local r, src = m.PlayerRole("Cid-Ray")
  assert(r == "MELEE" and src == "form", "cat form")
  m.auras["Cid-Ray"] = { ["Dire Bear Form"] = {} }
  assert(m.PlayerRole("Cid-Ray") == "TANK", "bear form")
  m.auras["Cid-Ray"] = { ["Mark of the Wild"] = {} }
  assert(m.PlayerRole("Cid-Ray") == "HEALER", "out of form: talents again")
  m.auras["Bob-Stone"] = { ["Cat Form"] = {} }
  assert(m.PlayerRole("Bob-Stone") == "TANK", "a form only counts for druids")
  m.M.db.playerRoles["Cid-Ray"] = "CASTER"
  assert(select(2, m.PlayerRole("Cid-Ray")) == "set" and m.PlayerRole("Cid-Ray") == "CASTER", "set by hand")
  m.M.db.playerRoles["Cid-Ray"] = nil

  -- "Only for": nothing = everyone; any match counts
  local might = { id = 19740 }
  assert(m.Applies(might, "Dee-Kay") and not m.HasFilter(might), "no filter")
  might.only = { roles = { MELEE = true, TANK = true } }
  assert(m.Applies(might, "Bob-Stone"), "tank gets Might")
  assert(not m.Applies(might, "Dee-Kay"), "mage gets Might")
  assert(not m.Applies(might, "Cid-Ray"), "resto druid gets Might")
  m.auras["Cid-Ray"] = { ["Cat Form"] = {} }
  assert(m.Applies(might, "Cid-Ray"), "cat druid doesn't get Might")
  local wisdom = { id = 19742, only = { classes = { MAGE = true }, mmt = { Tank = true } } }
  assert(m.Applies(wisdom, "Dee-Kay") and m.Applies(wisdom, "Bob-Stone") and not m.Applies(wisdom, "Cid-Ray"), "class / MMT role")
  assert(m.FilterText(wisdom) == "Mage, Tank (MMT role)", m.FilterText(wisdom))
  assert(m.FilterText(might) == "Tank, Melee", m.FilterText(might))
  -- imported / synced filters are cleaned
  local c = m.CleanFilter({ roles = { MELEE = true, BOGUS = true, CASTER = false }, classes = { ALL = true }, mmt = { [""] = true } })
  assert(c and c.roles.MELEE and not c.roles.BOGUS and not c.roles.CASTER and not c.classes and not c.mmt, "clean")
  assert(m.CleanFilter({ roles = {} }) == nil and m.CleanFilter("x") == nil, "empty filter")
  return "buff roles ok"
end''')(mod))
