"""Drag to reorder (SettingsKit mod.DragReorder) in the Buff Timers list editor: the
settings page is built with test_settings' stand-ins, but the list is a copy of the
core's ConfigHelpers.List made of frames that keep their scripts, so a drag can be
played: OnDragStart on a row, the cursor moves (OnUpdate), OnDragStop."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(r'''
-- frames that keep scripts, alpha and shown state
local function Frame()
  local f = STUB()
  local scripts = {}
  rawset(f, "scripts", scripts)
  rawset(f, "shown", true)
  rawset(f, "alpha", 1)
  rawset(f, "SetScript", function(self, k, fn) scripts[k] = fn end)
  rawset(f, "GetScript", function(self, k) return scripts[k] end)
  rawset(f, "HookScript", function(self, k, fn)
    local old = scripts[k]
    scripts[k] = function(...) if old then old(...) end fn(...) end
  end)
  rawset(f, "Show", function(self) self.shown = true end)
  rawset(f, "Hide", function(self) self.shown = false end)
  rawset(f, "SetShown", function(self, v) self.shown = v and true or false end)
  rawset(f, "IsShown", function(self) return self.shown end)
  rawset(f, "SetAlpha", function(self, a) self.alpha = a end)
  rawset(f, "CreateTexture", function() return Frame() end)
  rawset(f, "SetColorTexture", function(self, ...) self.color = { ... } end)
  -- not placed on screen (IconBars' PointAt then leaves the window alone)
  for _, k in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom" }) do rawset(f, k, function() return nil end) end
  return f
end
FRAME = Frame
CURSOR_Y = 0
function GetCursorPosition() return 0, CURSOR_Y end
NOW = 1000
function GetTime() return NOW end
-- the core's List (MMT/ConfigPages.lua), on these frames; the list's top edge is at y = 500
MMT.ConfigHelpers.List = function(parent, width, rows, rowHeight, makeRow, fillRow)
  local list = Frame()
  rawset(list, "GetHeight", function() return rows * rowHeight end)
  rawset(list, "GetTop", function() return 500 end)
  list.offset = 0
  list.rows = {}
  for i = 1, rows do list.rows[i] = makeRow(list, i) end
  function list:Render(data)
    self.data = data
    self.offset = math.max(0, math.min(self.offset, #data - rows))
    for i, row in ipairs(self.rows) do
      local index = i + self.offset
      if data[index] then fillRow(row, data[index], index); row:Show() else row:Hide() end
    end
  end
  list:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta
    self:Render(self.data or {})
  end)
  LIST = list
  return list
end
function CreateFrame(kind, name, parent) return Frame() end
''')
mod = lua.eval('{}')
folder = 'MMT_BuffTimers'
for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, mod)

# MoveEntry on its own
print(lua.eval(r'''function(m)
  local function L() return { "a", "b", "c", "d" } end
  local function S(t) return table.concat(t) end
  local t = L(); assert(m.MoveEntry(t, 1, 3) == 2 and S(t) == "bacd", "down one: " .. S(t))
  t = L(); assert(m.MoveEntry(t, 4, 1) == 1 and S(t) == "dabc", "last to first: " .. S(t))
  t = L(); assert(m.MoveEntry(t, 1, 5) == 4 and S(t) == "bcda", "first to the end: " .. S(t))
  t = L(); assert(m.MoveEntry(t, 2, 2) == nil and m.MoveEntry(t, 2, 3) == nil and S(t) == "abcd", "no move")
  t = L(); assert(m.MoveEntry(t, 2, 9) == nil and m.MoveEntry(t, 7, 1) == nil and S(t) == "abcd", "out of range")
  return "MoveEntry ok"
end''')(mod))

# a drag in the settings page's Buffs tab
print(lua.eval(r'''function(m)
  local M = m.M
  local class = m.OwnListKey()
  local l = {}
  for i = 1, 20 do l[i] = { id = 1000 + i } end
  M.db.lists[class] = l
  local page = STUB()
  M.Page(M, page)
  page.OnRefresh()
  local list = LIST
  assert(list and list.rows[1].index == 1, "list not drawn")
  local rows = list.rows
  -- the dotted handle, lit while the cursor is on the row
  local dot = rows[1].grip.dots[1]
  rows[1].scripts.OnEnter(rows[1])
  assert(dot.color[4] > 0.5, "grip not lit on hover")
  rows[1].scripts.OnLeave(rows[1])
  assert(dot.color[4] < 0.5, "grip still lit")
  -- no up / down buttons any more
  assert(rawget(rows[1], "up") == nil and rawget(rows[1], "down") == nil, "up / down buttons still there")
  local function Ids()
    local t = {} for i, e in ipairs(M.db.lists[class]) do t[i] = e.id - 1000 end return table.concat(t, ",")
  end
  local function At(gap) CURSOR_Y = 500 - gap * 22 - 3 end   -- just below the gap above visible row gap+1
  -- drag the 2nd buff below the 5th: lands 5th, the others move up
  rows[2].scripts.OnDragStart(rows[2])
  assert(rows[2].alpha < 1 and rows[1].alpha == 1, "dragged row not dimmed")
  At(5); list.scripts.OnUpdate(list)
  rows[2].scripts.OnDragStop(rows[2])
  assert(Ids():sub(1, 14) == "1,3,4,5,2,6,7,", "2 below 5: " .. Ids())
  assert(rows[2].alpha == 1 and list.scripts.OnUpdate == nil, "drag not ended")
  assert(list.rows[5].entry.id == 1002, "list not redrawn")
  -- dropped where it was: nothing changes
  rows[3].scripts.OnDragStart(rows[3])
  At(3); list.scripts.OnUpdate(list)
  rows[3].scripts.OnDragStop(rows[3])
  assert(Ids():sub(1, 14) == "1,3,4,5,2,6,7,", "moved without moving: " .. Ids())
  -- to the top
  rows[4].scripts.OnDragStart(rows[4])
  At(-0.4); rows[4].scripts.OnDragStop(rows[4])
  assert(Ids():sub(1, 12) == "5,1,3,4,2,6,", "to the top: " .. Ids())
  -- held below the list: it scrolls (once per 0.15 s), then dropped at the very end
  rows[1].scripts.OnDragStart(rows[1])   -- buff 5
  CURSOR_Y = 500 - 14 * 22 - 30
  for i = 1, 10 do NOW = NOW + 0.2; list.scripts.OnUpdate(list) end
  assert(list.offset == 6, "didn't scroll: offset " .. list.offset)
  assert(rows[1].alpha == 1, "another entry dimmed after the scroll")
  rows[1].scripts.OnDragStop(rows[1])
  local ids = Ids()
  assert(ids:sub(1, 8) == "1,3,4,2," and ids:sub(-5) == ",20,5", "to the end after scrolling: " .. ids)
  assert(#M.db.lists[class] == 20, "entries lost")
  -- the window closes mid-drag: nothing moves, the drag ends
  rows[2].scripts.OnDragStart(rows[2])
  list.scripts.OnHide(list)
  assert(list.scripts.OnUpdate == nil and rows[2].alpha == 1, "drag kept after OnHide")
  return "Buffs list drag to reorder ok"
end''')(mod))
