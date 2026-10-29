"""Dragging icons on the bars (IconBars v13 "Dragging icons") in Cooldown Timers and
Buff Timers: unlocked bars show every tracked icon whatever the hide options say,
an icon dragged along its row reorders the list it comes from (only among icons of
that list: past them it goes to the list's nearest end), locked bars hide again and a
drag moves the window. Built on test_settings' stand-ins, with frames that keep their
scripts and a position (TOPLEFT offsets inside the row) so the drop spot can be found."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

FRAMES = r'''
FRAMES = {}
local function Frame(parent)
  local f = STUB()
  local scripts = {}
  rawset(f, "scripts", scripts)
  rawset(f, "parent", parent)
  rawset(f, "shown", true)
  rawset(f, "alpha", 1)
  rawset(f, "drop", false)   -- IconBars creates a row's drop line when it's missing (the stand-in would invent one)
  rawset(f, "SetScript", function(self, k, fn) scripts[k] = fn end)
  rawset(f, "GetScript", function(self, k) return scripts[k] end)
  rawset(f, "HookScript", function(self, k, fn)
    local old = scripts[k]
    scripts[k] = function(...) if old then old(...) end fn(...) end
  end)
  rawset(f, "GetParent", function(self) return rawget(self, "parent") end)
  rawset(f, "Show", function(self) self.shown = true end)
  rawset(f, "Hide", function(self) self.shown = false end)
  rawset(f, "SetShown", function(self, v) self.shown = v and true or false end)
  rawset(f, "IsShown", function(self) return self.shown end)
  rawset(f, "SetAlpha", function(self, a) self.alpha = a end)
  rawset(f, "CreateTexture", function() return Frame() end)
  rawset(f, "SetSize", function(self, w, h) self.w, self.h = w, h end)
  rawset(f, "SetPoint", function(self, ...) self.pt = { ... } end)
  rawset(f, "ClearAllPoints", function(self) self.pt = nil end)
  rawset(f, "GetPoint", function() return "CENTER", nil, "CENTER", 0, 0 end)
  -- a position only from SetPoint("TOPLEFT", x, y) (icons and rows, relative to their parent)
  local function xy(self) local p = self.pt if p and p[1] == "TOPLEFT" and type(p[2]) == "number" then return p[2], p[3] end end
  rawset(f, "GetLeft", function(self) local x = xy(self) return x end)
  rawset(f, "GetTop", function(self) local _, y = xy(self) return y end)
  rawset(f, "GetRight", function(self) local x = xy(self) return x and x + (self.w or 0) end)
  rawset(f, "GetBottom", function(self) local _, y = xy(self) return y and y - (self.h or 0) end)
  FRAMES[#FRAMES + 1] = f
  return f
end
function CreateFrame(kind, name, parent)
  local f = Frame(parent)
  if name then rawset(_G, name, f) end
  return f
end
CX, CY = 0, 0
function GetCursorPosition() return CX, CY end
function IsMouseButtonDown() return true end
'''

COMMON = r'''
-- icon j of a horizontal row sits at x = NAMEW + (j - 1) * 30 (28 px + 2 spacing), y = 0 .. -28
NAMEW = 56
MMT.status = {}
function Between(j) CX, CY = NAMEW + j * 30 - 1, -14 end   -- the gap after icon j (0 = before the first)
function Driver(win)
  for _, f in ipairs(FRAMES) do
    if rawget(f, "parent") == nil and f ~= win and f.scripts.OnUpdate then return f end
  end
end
function Ids(row)
  local t = {}
  for _, b in ipairs(row.icons) do if b.shown and b.data then t[#t + 1] = b.data.spell end end
  return table.concat(t, ",")
end
function ListIds(l)
  local t = {} for _, e in ipairs(l) do t[#t + 1] = e.id end return table.concat(t, ",")
end
-- drag icon j of a row to the gap after icon `to`
function Drag(w, row, j, to)
  local b = row.icons[j]
  b.scripts.OnDragStart(b)
  Between(to)
  local d = Driver(w.frame)
  if d and d.shown then d.scripts.OnUpdate(d) end
  b.scripts.OnDragStop(b)
end
'''

def load(folder):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(FRAMES)
    lua.execute(COMMON)
    mod = lua.eval('{}')
    for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, mod)
    return lua, mod

# ---------------------------------------------------------------- Cooldowns
lua, mod = load('MMT_CooldownTimers')
print(lua.eval(r'''function(m)
  local M = m.M
  MMT.SortedMembers = function() return { "Bob-Stone" } end
  MMT.IsSelf = function(k) return k == "Anna-Smith" end
  MMT.db.team["Bob-Stone"] = { class = "SHAMAN" }
  M.db.showBuffs = false
  M.db.hideReady = true          -- everything is ready: nothing shows while locked
  M.db.lists = {
    SHAMAN = { { t = "s", id = 1, cd = 60 }, { t = "s", id = 2, cd = 60 }, { t = "s", id = 3, cd = 60 } },
    ALL = { { t = "s", id = 4, cd = 60 }, { t = "s", id = 5, cd = 60 }, { t = "s", id = 6, cd = 60, off = true } },
  }
  local w = m.window
  M.db.locked = true
  w:Refresh()
  assert(not w.frame.shown or #w.rows == 0 or not w.rows[1].shown or Ids(w.rows[1]) == "", "locked: ready icons shown")
  -- unlocked: every switched-on entry, ready or not
  M.db.locked = false
  w:Refresh()
  local row = w.rows[1]
  assert(Ids(row) == "1,2,3,4,5", "unlocked icons: " .. Ids(row))
  assert(row.icons[1].data.drag and row.icons[1].data.drag.group == M.db.lists.SHAMAN, "no drag on the icons")
  -- 1 after 3 (its own list)
  Drag(w, row, 1, 3)
  assert(ListIds(M.db.lists.SHAMAN) == "2,3,1", "1 after 3: " .. ListIds(M.db.lists.SHAMAN))
  assert(Ids(row) == "2,3,1,4,5", "bar not redrawn: " .. Ids(row))
  assert(row.icons[1].alpha == (M.db.readyAlpha or 1), "an icon still dimmed")
  -- 5 (ALL) dragged to the very left: stops at the start of its own list (before 4)
  Drag(w, row, 5, 0)
  assert(ListIds(M.db.lists.ALL) == "5,4,6", "5 to the left: " .. ListIds(M.db.lists.ALL))
  assert(ListIds(M.db.lists.SHAMAN) == "2,3,1", "the class list changed")
  -- 2 (class) dragged past the end: the end of its own list (after 1)
  Drag(w, row, 1, 5)
  assert(ListIds(M.db.lists.SHAMAN) == "3,1,2", "2 past the end: " .. ListIds(M.db.lists.SHAMAN))
  -- dropped on its own spot: nothing
  Drag(w, row, 2, 1)
  Drag(w, row, 2, 2)
  assert(ListIds(M.db.lists.SHAMAN) == "3,1,2", "moved without moving: " .. ListIds(M.db.lists.SHAMAN))
  -- the line while dragging: shown between 3 and 1 ... hidden on its own spot
  local b = row.icons[3]
  b.scripts.OnDragStart(b)
  assert(b.alpha < (M.db.readyAlpha or 1), "dragged icon not dimmed")
  Between(0); Driver(w.frame).scripts.OnUpdate(Driver(w.frame))
  assert(row.drop and row.drop.shown and row.drop.pt[2] == row.icons[1], "drop line before the first icon")
  Between(2); Driver(w.frame).scripts.OnUpdate(Driver(w.frame))
  assert(not row.drop.shown, "drop line on its own spot")
  b.scripts.OnDragStop(b)
  assert(not Driver(w.frame).shown, "drag not ended")
  -- locked again: hidden again, and a drag moves the window instead
  M.db.locked = true
  w:Refresh()
  assert(not row.shown or Ids(row) == "", "locked: still everything shown")
  local moved = false
  w.frame.scripts.OnDragStart = function() moved = true end
  M.db.hideReady = false
  w:Refresh()
  row = w.rows[1]
  assert(row.icons[1].data.drag == nil, "drag on a locked bar")
  Drag(w, row, 1, 3)
  assert(moved and ListIds(M.db.lists.SHAMAN) == "3,1,2", "locked drag")
  return "Cooldowns bar drag ok"
end''')(mod))

# ---------------------------------------------------------------- Buffs
lua, mod = load('MMT_BuffTimers')
print(lua.eval(r'''function(m)
  local M = m.M
  MMT.SortedMembers = function() return { "Bob-Stone" } end
  MMT.IsSelf = function(k) return k == "Anna-Smith" end
  MMT.db.team["Bob-Stone"] = { class = "SHAMAN" }
  MMT.ModuleActive = function() return false end   -- Cooldowns off: own window
  M.db.allBar = true
  M.db.hideNoCaster = true    -- nobody can cast these: hidden while locked
  M.db.lists = {
    SHAMAN = { { id = 11 }, { id = 12 } },
    ALL = { { id = 21 }, { id = 22 }, { id = 23 } },
  }
  m.Castable = function() return false end
  local w = m.window
  M.db.locked = true
  m.Apply()
  assert(not w.frame.shown or not w.rows[1] or not w.rows[1].shown, "locked: uncastable buffs shown")
  M.db.locked = false
  m.Apply()
  local all, bob = w.rows[1], w.rows[2]
  assert(all.key == "All" and Ids(all) == "21,22,23", "All row unlocked: " .. Ids(all))
  assert(bob.key == "Bob-Stone" and Ids(bob) == "11,12", "Bob's row unlocked: " .. tostring(bob.key) .. " " .. Ids(bob))
  -- All row: 21 after 23
  Drag(w, all, 1, 3)
  assert(ListIds(M.db.lists.ALL) == "22,23,21", "All row drag: " .. ListIds(M.db.lists.ALL))
  assert(Ids(w.rows[1]) == "22,23,21", "All row not redrawn: " .. Ids(w.rows[1]))
  -- Bob's row: 12 before 11
  Drag(w, bob, 2, 0)
  assert(ListIds(M.db.lists.SHAMAN) == "12,11", "member row drag: " .. ListIds(M.db.lists.SHAMAN))
  M.db.locked = true
  m.Apply()
  assert(not w.frame.shown or not w.rows[1].shown, "locked again: still shown")
  return "Buffs bar drag ok"
end''')(mod))
