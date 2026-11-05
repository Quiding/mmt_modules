"""Garbage per redraw (Buff Timers 0.30.1 / IconBars v22: micro stutters from the garbage collector, the user
saw high memory with Buff Timers on). Both modules in one Lua state on test_bardrag's frames, five members of
different classes with the default lists; the stand-in API's calls return one shared object so only the
modules' own tables count. Checks:
  - spell info is looked up once per spell (C_Spell.GetSpellInfo makes a new table on every call in game)
  - a redraw with nothing moved between the bars returns each row's own icon list (no merge tables)
  - the window / row backdrops aren't set again on every redraw
  - a Buff Timers redraw stays under a garbage budget (it was ~57 KB in this setup before 0.30.1)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]
bd = open('tests/test_bardrag.py', encoding='utf-8').read()
FRAMES = bd.split("FRAMES = r'''", 1)[1].split("'''", 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(FRAMES)
lua.execute(r'''
local U = getmetatable(STUB()); local SHARED = STUB(); U.__call = function() return SHARED end
INFO_CALLS = 0
C_Spell = { GetSpellInfo = function(id) INFO_CALLS = INFO_CALLS + 1; return { name = "Spell " .. tostring(id), iconID = 1, spellID = id } end,
  GetSpellTexture = function() return 1 end }
MMT.status = {}
TEAM = { "Anna-Smith", "Bob-Stone", "Cid-Ray", "Dee-Kay", "Eve-Lin" }
CLASSES = { ["Anna-Smith"] = "WARRIOR", ["Bob-Stone"] = "PALADIN", ["Cid-Ray"] = "PRIEST", ["Dee-Kay"] = "MAGE", ["Eve-Lin"] = "DRUID" }
MMT.SortedMembers = function() return TEAM end
MMT.IsSelf = function(k) return k == "Anna-Smith" end
MMT.ModuleActive = function() return true end
MMT.MemberRoleList = function() return {} end
for k, c in pairs(CLASSES) do MMT.db.team[k] = { class = c } end
BACKDROPS = 0
''')
mods = {}
for folder in ['MMT_BuffTimers', 'MMT_CooldownTimers']:
    m = lua.eval('{}')
    for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, m)
    mods[folder] = m

print(lua.eval(r'''function(bf, cd)
  local BM = bf.M
  BM.db.hideUnlearned, BM.db.hideNoCaster = false, false
  bf.Castable = function() return true end
  bf.State = function() return "buff", GetTime() - 5, 1800 end
  cd.State = function() return "ready" end
  bf.BuildIndex(); cd.BuildIndex()
  bf.Apply()
  local bw = bf.window
  -- count SetBackdrop on the window and its rows
  local function Count(f) local old = f.SetBackdrop; rawset(f, "SetBackdrop", function(...) BACKDROPS = BACKDROPS + 1 end) end
  bw:Refresh()
  Count(bw.frame); for _, r in ipairs(bw.rows) do Count(r) end
  -- spell info: once per spell
  INFO_CALLS = 0
  bf.SpellInfo(1243); bf.SpellInfo(1243); bf.SpellInfo(1243)
  assert(INFO_CALLS <= 1, "spell info looked up again: " .. INFO_CALLS)
  INFO_CALLS = 0
  bw:Refresh(); bw:Refresh()
  assert(INFO_CALLS == 0, "a redraw looked up spell info again: " .. INFO_CALLS)
  assert(BACKDROPS == 0, "backdrops set again on a redraw: " .. BACKDROPS)
  -- the budget: one redraw of the buff bar (was ~57 KB here before 0.30.1, ~28 KB after)
  collectgarbage("collect"); collectgarbage("stop")
  local c = collectgarbage("count")
  for _ = 1, 20 do bw:Refresh() end
  local kb = (collectgarbage("count") - c) / 20
  collectgarbage("restart")
  assert(kb < 40, ("a Buff Timers redraw makes %.1f KB of garbage"):format(kb))
  -- nothing moved between the bars: each row's icons are its own list
  local saved = bw.def.rows
  for _, r in ipairs(saved()) do
    if r.key then
      local before = r.icons
      bw.def.rows = function() return { r } end
      bw:Refresh()
      assert(r.all == before, "a row's icons were merged into a new list with nothing to merge")
      break
    end
  end
  bw.def.rows = saved
  return ("garbage checks ok (%.1f KB per redraw)"):format(kb)
end''')(mods['MMT_BuffTimers'], mods['MMT_CooldownTimers']))
