import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
SENT = {}
LISTENERS = {}
MMT = {
  CopyTable = copy,
  db = { team = {
    ["Anna-Smith"] = { class = "PRIEST", roles = { Healer = true } },
    ["Bob-Stone"]  = { class = "WARRIOR", roles = { Tank = true, ["Raid Lead|x"] = true } },
  }, roles = { Healer = {}, Tank = {}, ["Raid Lead|x"] = {} } },
}
function MMT.IsSelf(k) return false end
function MMT.MemberRoleList(key)
  local t = {} for r in pairs(MMT.db.team[key].roles or {}) do t[#t+1] = r end table.sort(t) return t end
function MMT.SortedRoleNames() local t = {} for r in pairs(MMT.db.roles) do t[#t+1] = r end table.sort(t) return t end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone" } end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.SendToTeam(msg) SENT[#SENT+1] = msg end
function MMT.Print() end
function MMT.RefreshConfig() end
CONFIRMS = {}
MMT.UI = { Confirm = function(text, acceptText, onAccept) CONFIRMS[#CONFIRMS + 1] = { text = text, accept = onAccept } end }
C_Timer = { After = function(_, f) f() end }
function UnitClass() return "Priest", "PRIEST" end
''')

def load(path, mod):
    f = lua.eval('function(src, name) return assert(loadstring(src, name)) end')(open(path, encoding='utf-8').read(), path)
    f("x", mod)

for folder, entry_id, lists_src in [
    ('MMT_CooldownTimers', 'function(e) return e.t .. e.id end',
     r'''{ PRIEST = { {t="s",id=10060,cd=180} }, ALL = { {t="i",id=19950,cd=120} },
          ["ROLE:Healer"] = { {t="s",id=10060,cd=180}, {t="s",id=724,cd=600} },
          ["ROLE:Raid Lead|x"] = { {t="s",id=1,cd=5} },
          ["CHAR:Anna-Smith"] = { {t="s",id=586,cd=30} } }'''),
    ('MMT_BuffTimers', 'function(e) return "b" .. e.id end',
     r'''{ PRIEST = { {id=1459} }, ALL = { {id=1243} },
          ["ROLE:Healer"] = { {id=1459}, {id=14752} },
          ["ROLE:Raid Lead|x"] = { {id=6673} },
          ["CHAR:Anna-Smith"] = { {id=976} } }''')]:
    mod = lua.eval('function(lists) local m = { CLASSES = {"WARRIOR","PRIEST","ALL"} } '
                   'm.M = { db = { lists = lists }, Debug = function() end, '
                   'Listen = function(_, ev, fn) LISTENERS[ev] = fn end } return m end')(lua.eval(lists_src))
    lua.eval('function(m, id) m.EntryKey = id; m.BuffName = id; m.BuildIndex = function() end; '
             'm.Refresh = function() end; m.ScanGroup = function() end; m.ShareCheck = function() end; m.RequestRunning = function() end end')(mod, lua.eval(entry_id))
    load('MMT_CooldownTimers/ListKeys.lua', mod)
    print(lua.eval(r'''function(m, idf, folder)
      -- which lists apply
      local keys = table.concat(m.ListKeysFor("Anna-Smith", true), ",")
      assert(keys == "PRIEST,ALL,ROLE:Healer,CHAR:Anna-Smith", keys)
      assert(table.concat(m.ListKeysFor("Bob-Stone", false), ",") == "WARRIOR,ROLE:Raid Lead|x,ROLE:Tank,CHAR:Bob-Stone")
      -- entries: class + ALL + role + char, the role's copy of a class spell only once
      local e = m.CollectEntries("Anna-Smith", true, idf)
      assert(#e == 4, "entries " .. #e)
      local noAll = m.CollectEntries("Anna-Smith", false, idf)
      assert(#noAll == 3, "without ALL " .. #noAll)
      assert(#m.CollectEntries("Bob-Stone", true, idf) == 2, "bob")
      -- validity
      assert(m.ValidListKey("PRIEST") and m.ValidListKey("ROLE:x") and m.ValidListKey("CHAR:a-b"))
      assert(not m.ValidListKey("HACKER") and not m.ValidListKey("ROLE:") and not m.ValidListKey(5))
      -- dropdown: headers + classes + roles + characters, counts shown
      local c = m.ListChoices()
      local values, headers = {}, 0
      for _, it in ipairs(c) do if it.header then headers = headers + 1 else values[#values+1] = it.value end end
      assert(headers == 4, "headers " .. headers)
      local races = "RACE:Human,RACE:Dwarf,RACE:NightElf,RACE:Gnome,RACE:Orc,RACE:Scourge,RACE:Tauren,RACE:Troll"
      assert(table.concat(values, ",") == "WARRIOR,PRIEST,ALL," .. races .. ",ROLE:Healer,ROLE:Raid Lead|x,ROLE:Tank,CHAR:Anna-Smith,CHAR:Bob-Stone", table.concat(values, ","))
      -- a member's race (from their heartbeat) adds their race list, remembered while offline
      m.M.store = {}
      MMT.status = { ["Bob-Stone"] = { ext = { race = "Troll" } } }
      assert(table.concat(m.ListKeysFor("Bob-Stone", false), ",") == "WARRIOR,RACE:Troll,ROLE:Raid Lead|x,ROLE:Tank,CHAR:Bob-Stone", "race list missing")
      MMT.status = {}
      assert(table.concat(m.ListKeysFor("Bob-Stone", false), ",") == "WARRIOR,RACE:Troll,ROLE:Raid Lead|x,ROLE:Tank,CHAR:Bob-Stone", "race not remembered")
      assert(m.ValidListKey("RACE:Troll") and not m.ValidListKey("RACE:") and not m.ValidListKey("RACE:a b"))
      -- switched-off entries aren't tracked; a preset only adds what's missing
      m.M.db.lists["RACE:Troll"] = { { t = "s", id = 777, cd = 1, off = true } }
      local n = #m.CollectEntries("Bob-Stone", false, idf)
      m.M.db.lists["RACE:Troll"][1].off = nil
      assert(#m.CollectEntries("Bob-Stone", false, idf) == n + 1, "off entry tracked / on entry not tracked")
      local added = m.AddPreset("RACE:Troll", { { t = "s", id = 777, cd = 1 }, { t = "s", id = 888, cd = 2, off = true } }, idf)
      assert(added == 1 and #m.M.db.lists["RACE:Troll"] == 2 and m.M.db.lists["RACE:Troll"][2].off == true, "preset merge")
      m.M.db.lists["RACE:Troll"] = nil
      MMT.status = nil
      return folder .. ": list keys and dropdown ok"
    end''')(mod, lua.eval(entry_id), folder))
