"""MMT_Buffs: the All bar's counter (how many members have a buff, in its own
corner) - the whole module loaded with test_settings' stand-in API."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
mod = lua.eval('{}')
folder = 'MMT_Buffs'
for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, mod)

print(lua.eval(r'''function(m)
  ORIG_STATE = m.State
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone", "Cid-Ray" } end
  MMT.status = {}
  MMT.IsOnline = function() return true end
  local c = m.M.db
  c.hideNoCaster = false
  c.allBar = true
  c.lists.ALL = { { id = 19740 } }   -- Blessing of Might
  HAVE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true }
  m.State = function(key, e) if HAVE[key] then return "buff", 100, 300, 1 end return "missing" end
  local function AllIcon()
    for _, row in ipairs(m.window.def.rows()) do
      if row.label == "All" then return row.icons[1] end
    end
  end
  -- 2 of 3 have it: "2" in the bottom left, white, size 12 (defaults)
  local i = AllIcon()
  assert(i.state == "missing" and i.tally == 2 and i.tallyPos == "BOTTOMLEFT" and i.tallySize == 12, "counter: " .. tostring(i.tally))
  assert(i.count == nil, "the missing count still shows next to the counter")
  assert(i.tip:find("2 have it", 1, true), "tooltip")
  -- one has it: no counter
  HAVE = { ["Anna-Smith"] = true }
  i = AllIcon()
  assert(i.tally == nil, "counter shown for one")
  -- everyone: "3", the corner and size from the settings
  HAVE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true, ["Cid-Ray"] = true }
  c.allCount, c.allCountSize = "TOPRIGHT", 16
  i = AllIcon()
  assert(i.state == "buff" and i.tally == 3 and i.tallyPos == "TOPRIGHT" and i.tallySize == 16, "counter everyone")
  -- off
  c.allCount = "OFF"
  i = AllIcon()
  assert(i.tally == nil, "counter while off")
  return "All bar counter ok"
end''')(mod))

# "All classes" preview: made-up characters, one of every class, in their class colours
print(lua.eval(r"""function(m)
  m.State = ORIG_STATE
  RAID_CLASS_COLORS = {}
  for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    RAID_CLASS_COLORS[c] = { r = #c / 10, g = 0.5, b = 0.5 }
  end
  m.M.db.lists.WARRIOR = { { id = 6673 } }
  m.M.db.lists.PRIEST = { { id = 588 } }
  m.SetPreview("ALL")
  local rows, byKey = m.window.def.rows(), {}
  for _, r in ipairs(rows) do if r.key then byKey[r.key] = r end end
  local n = 0
  for _ in pairs(byKey) do n = n + 1 end
  assert(n == 9, "made-up rows: " .. n)
  local w = byKey["Brakka-Preview"]
  assert(w and m.ClassOf("Brakka-Preview") == "WARRIOR" and w.color and w.color[1] == 0.7, "warrior row / colour")
  assert(#w.icons >= 1, "warrior list not shown for the made-up warrior")
  assert(m.ClassOf("Lirael-Preview") == "PRIEST", "priest")
  assert(MMT.FirstName("Brakka-Preview") == "Brakka", "made-up name")
  m.SetPreview(nil)
  rows = m.window.def.rows()
  for _, r in ipairs(rows) do assert(r.key ~= "Brakka-Preview", "made-up row after the preview") end
  return "All classes preview ok"
end""")(mod))
