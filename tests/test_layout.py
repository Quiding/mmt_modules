"""Settings page layout: builds every module's settings page (all tabs) with test_settings'
stand-ins, but the columns add up the real heights of MMT's widgets (MMT/Widgets.lua:
Header 28, Check 22, Slider 36, Cycle / Button / Color 24, Note by its text, Add(f, h)
h, Space h). Fails when
  - something is placed on a line that a widget added with height 0 is still using
    (L:Add(test, 0) is fine for a button with another one beside it by SetPoint, but the
    next column widget then lands on top of it: the Arrange icons button did), or
  - a column runs past the bottom of its page (564 px) or tab panel (564 - 30 tabs -
    50 for the status line and share bar = 484 px).
Notes are estimated (about 5.5 px per character, 12 px a line): close calls are printed."""
import math, os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

MEASURE = r'''
-- frames remember their size (tab panels are sized from the page)
local U = getmetatable(STUB())
local index = U.__index
U.__index = function(t, k)
  if k == "SetSize" then return function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end end
  if k == "SetHeight" then return function(self, h) rawset(self, "_h", h) end end
  if k == "GetHeight" then return function(self) return rawget(self, "_h") or 564 end end
  return index(t, k)
end

PROBLEMS, COLUMNS = {}, {}
local ROW = 22
local function Note(text, width)
  local chars = #(tostring(text or ""))
  local lines = 0
  for part in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + math.max(1, math.ceil(#part * 5.5 / width))
  end
  return math.max(ROW, lines * 12 + 8)
end
UI.Column = function(parent, x, y, width)
  local col = STUB()
  local c = { y = y or 0, top = y or 0, zero = nil, parent = parent, x = x, width = width, name = CURRENT }
  COLUMNS[#COLUMNS + 1] = c
  local function place(what, h)
    if c.zero then
      PROBLEMS[#PROBLEMS + 1] = ("%s: %s placed on the line of a 0-height %s (column x=%d, y=%d)"):format(c.name, what, c.zero, x or 0, -c.y)
    end
    c.zero = (h == 0) and what or nil
    c.y = c.y - h
  end
  local function W(f) return f or STUB() end
  rawset(col, "Header", function(_, text) c.zero = nil; c.first = c.first or text; c.y = c.y - 28; return STUB() end)
  rawset(col, "Note", function(_, text) place("Note", Note(text, width or 248)); return STUB() end)
  rawset(col, "Space", function(_, h) c.zero = nil; c.y = c.y - (h or 8) end)
  rawset(col, "Add", function(_, f, h) place("Add", h == nil and ROW or h); return W(f) end)
  rawset(col, "Check", function() place("Check", ROW); return STUB() end)
  rawset(col, "Slider", function() place("Slider", 36); return STUB() end)
  rawset(col, "Cycle", function() place("Cycle", ROW + 2); return STUB() end)
  rawset(col, "Dropdown", function() place("Cycle", ROW + 2); return STUB() end)
  rawset(col, "Button", function() place("Button", ROW + 2); return STUB() end)
  rawset(col, "Color", function() place("Color", ROW + 2); return STUB() end)
  return col
end
'''

failed = False

# the check itself: a widget on the line of a 0-height one is caught (the Arrange icons bug)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(MEASURE)
lua.execute('CURRENT = "self-check"')
assert lua.eval(r"""function()
  local L = UI.Column(STUB(), 0, 0, 248)
  L:Add(STUB(), 0)        -- Test (10 s), with Reset position beside it by SetPoint
  L:Add(STUB(), 24)       -- Arrange icons: on top of both
  return #PROBLEMS == 1
end""")(), "the layout check doesn't catch a 0-height overlap"
for folder in ["MMT_PawnCompare", "MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems", "MMT_Whispers", "MMT_TeamGear", "MMT_TeamInventory", "MMT_QoL", "MMT_qStyles"]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(MEASURE)
    lua.execute('CURRENT = "%s"' % folder)
    toc = [l.strip() for l in open(os.path.join(folder, folder + ".toc"), encoding="utf-8") if l.strip().endswith(".lua")]
    mod = lua.eval("{}")
    for f in toc:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding="utf-8").read(), folder + "/" + f, mod)
    result = lua.eval(r'''function(m)
      local page = STUB()
      rawset(page, "_h", 564)
      m.M.Page(m.M, page)
      local out, worst = {}, 0
      for _, c in ipairs(COLUMNS) do
        local used = c.top - c.y
        local limit = (rawget(c.parent, "_h") or 564)
        if used > limit then
          PROBLEMS[#PROBLEMS + 1] = ("%s: column \"%s\" (x=%d) is %d px high, the room is %d px"):format(c.name, tostring(c.first), c.x or 0, used, limit)
        elseif used > limit - 20 then
          out[#out + 1] = ("close: \"%s\" %d of %d px"):format(tostring(c.first), used, limit)
        end
        worst = math.max(worst, used / limit)
      end
      return table.concat(PROBLEMS, "\n"), table.concat(out, "; "), #COLUMNS, worst
    end''')(mod)
    problems, close, n, worst = result
    if problems:
        failed = True
        print("FAIL " + problems)
    print("%s: %d columns, fullest %d%%%s" % (folder, n, round(worst * 100), (" (" + close + ")") if close else ""))
if failed:
    sys.exit(1)
