"""MMT_BuffTimers/OnlyFor.lua: who a buff is for ("Only for": classes, specs, MMT roles; Buff
Timers' own player roles are gone since 0.22 - old ones are ignored and dropped), the own talent
tree (Specs.lua: classic tabs, Forever's trait groups or bands), a feral druid with an MMT tank
role, and Casters.lua."""
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
  m.M = { enabled = true, db = {} }
  function m.M:Heartbeat(k, fn) HEARTBEAT = fn end
  function m.M:Listen(ev, fn) LISTENERS[ev] = fn end
  m.SpellInfo = function(id) return SPELLS[id] end
  m.ClassOf = function(key) return TEAM[key] and TEAM[key].class end
  m.ListLabel = function(c) return c:sub(1, 1) .. c:sub(2):lower() end
  m.Refresh = function() REFRESHED = (REFRESHED or 0) + 1 end
  return m
end''')()
lua.eval('function(src, m) assert(loadstring(src, "Specs.lua"))("x", m) end')(
    open('MMT_BuffTimers/Specs.lua', encoding='utf-8').read(), mod)
lua.eval('function(src, m) assert(loadstring(src, "OnlyFor.lua"))("x", m) end')(
    open('MMT_BuffTimers/OnlyFor.lua', encoding='utf-8').read(), mod)

print(lua.eval(r'''function(m)
  -- own talents, classic tabs (name, icon, points): Feral has the most
  GetNumTalentTabs = function() return 3 end
  GetTalentTabInfo = function(t) return "Tree" .. t, "icon", ({ 5, 31, 15 })[t] end
  assert(m.OwnTree() == 2, "classic tabs")
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
  assert(m.OwnTree() == 3, "trait bands: " .. tostring(m.OwnTree()))
  -- Forever: the classic tabs exist but read 0; the trait groups (orderIndex
  -- order) have the points, like a paladin's Holy 0 / Protection 32 / Retribution 19
  GetNumTalentTabs = function() return 3 end
  GetTalentTabInfo = function(t) return "Tree" .. t, "icon", 0 end
  C_Traits.GetGroupDisplayInfoByTreeID = function() return { { groupID = 12, orderIndex = 3 },
    { groupID = 10, orderIndex = 1 }, { groupID = 11, orderIndex = 2 } } end
  C_Traits.GetGroupCurrencyInfo = function(config, ids)
    assert(config == 7, "config")
    return { { currencyInfos = { { spent = ({ [10] = 0, [11] = 32, [12] = 19 })[ids[1]] } } } }
  end
  NOW = NOW + 20
  local p = m.TreePoints()
  assert(p and p[1] == 0 and p[2] == 32 and p[3] == 19, "trait groups: " .. tostring(p and table.concat(p, "/")))
  assert(m.OwnTree() == 2, "own tree from the trait groups")
  -- a read before the trait config is ready isn't kept: known on the next call
  C_ClassTalents.GetActiveConfigID = function() return nil end
  NOW = NOW + 20
  assert(m.OwnTree() == nil, "no config yet")
  C_ClassTalents.GetActiveConfigID = function() return 7 end
  assert(m.OwnTree() == 2, "an empty read was cached")
  local lines = {}
  m.SpecReport(function(l) lines[#lines + 1] = l end)
  assert(#lines == 2 and lines[2]:find("0/32/19 from trait groups", 1, true) and lines[2]:find("tabs 0/0/0", 1, true), "spec report: " .. tostring(lines[2]))
  -- groups and tabs all 0: the node column bands still count
  C_Traits.GetGroupCurrencyInfo = function() return { { currencyInfos = { { spent = 0 } } } } end
  p = m.TreePoints()
  assert(p[1] == 5 and p[2] == 0 and p[3] == 21, "bands after zero groups / tabs")
  NOW = NOW + 20
  assert(m.OwnTree() == 3, "bands after zero groups / tabs: tree")
  GetNumTalentTabs, GetTalentTabInfo = nil, nil
  C_Traits.GetGroupDisplayInfoByTreeID, C_Traits.GetGroupCurrencyInfo = nil, nil
  -- no player roles any more: nothing about them is sent or kept
  assert(m.PlayerRole == nil and m.OwnTalentRole == nil, "player roles still there")
  -- a feral druid tanks as a bear with an MMT role named like a tank
  TEAM["Cid-Ray"].roles = { ["Main tank"] = true }
  assert(m.IsTank("Cid-Ray") and m.IsTank("Bob-Stone") and not m.IsTank("Dee-Kay"), "MMT tank roles")
  TEAM["Cid-Ray"].roles = {}

  -- "Only for": nothing = everyone; any match counts
  local might = { id = 19740 }
  assert(m.Applies(might, "Dee-Kay") and not m.HasFilter(might), "no filter")
  -- an old filter with only (removed) player roles: for everyone
  might.only = { roles = { MELEE = true, TANK = true } }
  assert(not m.HasFilter(might) and m.Applies(might, "Dee-Kay"), "old player roles still filter")
  might.only = { classes = { WARRIOR = true }, roles = { CASTER = true } }
  assert(m.Applies(might, "Bob-Stone") and not m.Applies(might, "Dee-Kay"), "classes with an old roles part")
  local wisdom = { id = 19742, only = { classes = { MAGE = true }, mmt = { Tank = true } } }
  assert(m.Applies(wisdom, "Dee-Kay") and m.Applies(wisdom, "Bob-Stone") and not m.Applies(wisdom, "Cid-Ray"), "class / MMT role")
  assert(m.FilterText(wisdom) == "Mage, Tank (MMT role)", m.FilterText(wisdom))
  assert(m.FilterText(might) == "Warrior", m.FilterText(might))
  -- imported / synced filters are cleaned: old player roles dropped
  local c = m.CleanFilter({ roles = { MELEE = true }, classes = { ALL = true, MAGE = true, BOGUS = true }, mmt = { [""] = true, Healer = true } })
  assert(c and c.roles == nil and c.classes.MAGE and not c.classes.ALL and not c.classes.BOGUS and c.mmt.Healer and not c.mmt[""], "clean")
  assert(m.CleanFilter({ roles = { TANK = true } }) == nil and m.CleanFilter("x") == nil, "empty filter")
  return "only for ok"
end''')(mod))

# "Hide buffs nobody here can cast" (Casters.lua)
lua.execute(r'''
SPELLS[1243] = "Power Word: Fortitude"; SPELLS[21562] = "Prayer of Fortitude"; SPELLS[1126] = "Mark of the Wild"
SPELLS[22888] = "Rallying Cry of the Dragonslayer"; SPELLS[1459] = "Arcane Intellect"
GROUP = {}   -- unit -> class
function IsInRaid() return false end
function UnitExists(u) return u == "player" or GROUP[u] ~= nil end
function UnitClass(u) if u == "player" then return "x", CLASS end return "x", GROUP[u] end
ONLINE = {}
function MMT.IsOnline(k) return ONLINE[k] == true end
function MMT.SortedMembers() return { "Me-Self", "Bob-Stone", "Cid-Ray", "Dee-Kay" } end
''')
lua.eval('''function(m)
  m.Canonical = function(n) return n == "Prayer of Fortitude" and "Power Word: Fortitude" or n end
  m.BuffName = function(e) local n = SPELLS[e.id] return n and m.Canonical(n) end
  m.M.db.hideNoCaster = true
  m.PreviewTeam = function() return MMT.SortedMembers() end   -- ListKeys.lua in the game
end''')(mod)
lua.eval('function(src, m) assert(loadstring(src, "Casters.lua"))("x", m) end')(
    open('MMT_BuffTimers/Casters.lua', encoding='utf-8').read(), mod)
print(lua.eval(r'''function(m)
  CLASS = "WARRIOR"; TEAM["Me-Self"].class = "WARRIOR"
  local fort, motw, ony, ai = { id = 1243 }, { id = 1126 }, { id = 22888 }, { id = 1459 }
  assert(m.CasterClass(fort) == "PRIEST" and m.CasterClass(motw) == "DRUID" and m.CasterClass(ony) == nil, "caster classes")
  assert(not m.Castable(fort) and not m.Castable(motw), "shown without a priest / druid")
  assert(m.Castable(ony), "a world buff hidden")
  -- a priest joins the group: Fortitude shows (also as Prayer of Fortitude)
  GROUP.party1 = "PRIEST"
  NOW = NOW + 1
  assert(m.Castable(fort) and m.Castable({ id = 21562 }), "priest in the group")
  assert(not m.Castable(motw), "Mark without a druid")
  -- a druid of the team online (not grouped)
  GROUP.party1 = nil
  ONLINE["Cid-Ray"] = true
  NOW = NOW + 1
  assert(m.Castable(motw) and not m.Castable(fort), "online druid of the team")
  -- the mage of the team offline: no Arcane Intellect
  assert(not m.Castable(ai), "offline mage counted")
  -- preview: the team's classes (real or mixed) count as here
  m.preview = "REAL"
  assert(not m.Castable(fort), "preview: priest buff without a priest in the team")
  m.ClassOf = function(key) return key == "Me-Self" and "WARRIOR" or "PRIEST" end   -- as the mixed preview would
  m.preview = "MIXED"
  assert(m.Castable(fort), "mixed preview: the made-up priest doesn't count")
  m.ClassOf = function(key) return TEAM[key] and TEAM[key].class end
  m.preview = nil
  -- option off: everything shows
  m.M.db.hideNoCaster = false
  assert(m.Castable(fort) and m.Castable(ai), "option off")
  return "casters ok"
end''')(mod))
