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
C_Timer = { After = function(_, f) f() end }
function UnitClass() return "Priest", "PRIEST" end
''')

def load(path, mod):
    f = lua.eval('function(src, name) return assert(loadstring(src, name)) end')(open(path, encoding='utf-8').read(), path)
    f("x", mod)

for folder, entry_id, lists_src in [
    ('MMT_Cooldowns', 'function(e) return e.t .. e.id end',
     r'''{ PRIEST = { {t="s",id=10060,cd=180} }, ALL = { {t="i",id=19950,cd=120} },
          ["ROLE:Healer"] = { {t="s",id=10060,cd=180}, {t="s",id=724,cd=600} },
          ["ROLE:Raid Lead|x"] = { {t="s",id=1,cd=5} },
          ["CHAR:Anna-Smith"] = { {t="s",id=586,cd=30} } }'''),
    ('MMT_Buffs', 'function(e) return "b" .. e.id end',
     r'''{ PRIEST = { {id=1459} }, ALL = { {id=1243} },
          ["ROLE:Healer"] = { {id=1459}, {id=14752} },
          ["ROLE:Raid Lead|x"] = { {id=6673} },
          ["CHAR:Anna-Smith"] = { {id=976} } }''')]:
    mod = lua.eval('function(lists) local m = { CLASSES = {"WARRIOR","PRIEST","ALL"} } '
                   'm.M = { db = { lists = lists }, Debug = function() end, '
                   'Listen = function(_, ev, fn) LISTENERS[ev] = fn end } return m end')(lua.eval(lists_src))
    lua.eval('function(m, id) m.EntryKey = id; m.BuffName = id; m.BuildIndex = function() end; '
             'm.Refresh = function() end; m.ScanGroup = function() end end')(mod, lua.eval(entry_id))
    load('MMT_Cooldowns/ListKeys.lua', mod)
    load(folder + '/Sync.lua', mod)
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
      assert(headers == 3, "headers " .. headers)
      assert(table.concat(values, ",") == "WARRIOR,PRIEST,ALL,ROLE:Healer,ROLE:Raid Lead|x,ROLE:Tank,CHAR:Anna-Smith,CHAR:Bob-Stone", table.concat(values, ","))
      -- send lists to team, receive on another client
      local before = MMT.CopyTable(m.M.db.lists)
      SENT = {}
      m.SendLists()
      m.M.db.lists = { PRIEST = {} }
      MMT.IsSelf = function() return false end
      for _, msg in ipairs(SENT) do LISTENERS.TEAM_MESSAGE("Bob-Stone", "Bob", msg) end
      local after = m.M.db.lists
      local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
      end
      for k, v in pairs(before) do assert(same(v, after[k]), "sync lost " .. k) end
      return folder .. ": list keys, dropdown and sync ok (" .. #SENT .. " message(s))"
    end''')(mod, lua.eval(entry_id), folder))
