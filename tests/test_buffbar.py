"""MMT_BuffTimers: the All bar's counter (how many members have a buff, in its own
corner) - the whole module loaded with test_settings' stand-in API."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
mod = lua.eval('{}')
folder = 'MMT_BuffTimers'
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

# the All bar's default and the raid presets: party buffs (no auras), with "Only for"
print(lua.eval(r"""function(m)
  local function Ids(list) local t = {} for _, e in ipairs(list) do t[e.id] = e end return t end
  local def = Ids(m.DEFAULT_LISTS.ALL)
  assert(def[1243] and def[1126] and def[20217] and not def[1243].only, "Fortitude / Mark / Kings for everyone")
  for _, e in ipairs(m.DEFAULT_LISTS.ALL) do assert(not e.only, "a default buff has Only for: " .. e.id) end
  assert(def[19740] and def[19742] and def[1459] and def[1038] and def[6673], "party buffs missing")
  assert(not def[19506] and not def[17007] and not def[24907], "auras in the default")
  local raid, auras = m.PresetByKey("ALL:RAID"), m.PresetByKey("ALL:RAIDAURAS")
  assert(raid and auras, "raid presets")
  local r, a = Ids(raid.entries), Ids(auras.entries)
  assert(not r[19506] and a[19506] and a[17007] and a[24907], "auras only in the + auras preset")
  -- a preset's tables are copied into the list, not shared with the preset
  r[19740].only = { roles = { MELEE = true } }
  m.M.db.lists.ALL = {}
  m.ApplyPreset("ALL", "ALL:RAID", true, function(e) return e.id end)
  local might
  for _, e in ipairs(m.M.db.lists.ALL) do if e.id == 19740 then might = e end end
  might.only.roles.CASTER = true
  assert(not r[19740].only.roles.CASTER, "the preset changed with the list")
  r[19740].only = nil
  return "party buff presets ok"
end""")(mod))

# buff spec presets: per class, defaults on only when every spec keeps them up
print(lua.eval(r"""function(m)
  local ret = m.PresetByKey("PALADIN:RET")
  assert(ret and ret.name == "Paladin: Retribution", "ret buff preset")
  local ids = {}
  for _, e in ipairs(ret.entries) do ids[e.id] = e end
  assert(ids[20375] and not ids[20375].off and ids[20050] and ids[21082].off, "ret buffs")
  local function Default(class)
    local t = {} for _, e in ipairs(m.DEFAULT_LISTS[class]) do t[e.id] = e end return t
  end
  local pal, rogue, priest = Default("PALADIN"), Default("ROGUE"), Default("PRIEST")
  assert(pal[20375] and pal[20375].off, "a ret-only seal on for every paladin")
  assert(rogue[5171] and not rogue[5171].off, "Slice and Dice off for rogues")
  assert(priest[588] and not priest[588].off and priest[15473].off, "priest defaults")
  for _, p in ipairs(m.PRESETS) do assert(not p.key:find(":REC$"), "old class preset " .. p.key) end
  return "buff spec presets ok"
end""")(mod))
