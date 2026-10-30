"""Moving icons between Cooldown Timers' and Buff Timers' bars (IconBars v16 guests, ListKeys PlaceIcon):
arrange mode is shared by both bars; a buff dragged onto a member's cooldown row stays on the Cooldowns
bars (entry.host, entry.after = the cooldown it follows), can be dragged anywhere in that row, and back
home onto a buff row (next to its own list's icons); a cooldown can go onto the buff bars the same way;
a guest whose cooldown isn't shown follows the nearest shown one before it; attached ("Where" on the
Cooldowns bars) every buff can be placed anywhere and detaching brings them all home; a hidden host
sends the icons home; export / import keep the placement. Both modules in one Lua state, on
test_bardrag's frames (positions from TOPLEFT offsets inside the row)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]
bd = open('tests/test_bardrag.py', encoding='utf-8').read()
FRAMES = bd.split("FRAMES = r'''", 1)[1].split("'''", 1)[0]

COMMON = r'''
NAMEW = 56
MMT.status = {}
MMT.SortedMembers = function() return { "Bob-Stone" } end
MMT.IsSelf = function(k) return k == "Anna-Smith" end
MMT.ModuleActive = function() return true end
MMT.db.team["Bob-Stone"] = { class = "SHAMAN" }
function Check(cond, msg) if not cond then error(msg, 2) end end
function Between(j) CX, CY = NAMEW + j * 30 - 1, -14 end
function Driver()
  for _, f in ipairs(FRAMES) do
    if rawget(f, "parent") == nil and f.scripts.OnUpdate and f.shown then return f end
  end
end
function Ids(row)
  local t = {}
  for _, b in ipairs(row.icons) do if b.shown and b.data then t[#t + 1] = b.data.spell end end
  return table.concat(t, ",")
end
function RowOf(w, key)
  if not w.frame.shown then return nil end
  for _, r in ipairs(w.rows) do if r.shown and r.key == key then return r end end
end
-- the row the cursor is over (other bars are only hit while HOVER is them)
HOVER = nil
function Hoverable(w)
  for _, r in ipairs(w.rows) do
    rawset(r, "GetLeft", function(self) return HOVER == self and -1e6 or nil end)
    rawset(r, "GetRight", function(self) return HOVER == self and 1e6 or nil end)
    rawset(r, "GetTop", function(self) return HOVER == self and 1e6 or nil end)
    rawset(r, "GetBottom", function(self) return HOVER == self and -1e6 or nil end)
  end
end
-- drag icon j of row to the gap after icon `to` of row `onto` (default: its own row)
function Drag(row, j, to, onto)
  local b = row.icons[j]
  assert(b and b.shown, "no icon " .. j)
  b.scripts.OnDragStart(b)
  HOVER = onto
  Between(to)
  local d = Driver()
  if d then d.scripts.OnUpdate(d) end
  b.scripts.OnDragStop(b)
  HOVER = nil
end
function Find(list, id) for _, e in ipairs(list) do if e.id == id then return e end end end
function ListIds(l) local t = {} for _, e in ipairs(l) do t[#t + 1] = e.id end return table.concat(t, ",") end
'''

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(FRAMES)
lua.execute(COMMON)
mods = {}
for folder in ['MMT_BuffTimers', 'MMT_CooldownTimers']:   # the game's load order (alphabetical)
    m = lua.eval('{}')
    for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, m)
    mods[folder] = m

print(lua.eval(r'''function(cd, bf)
  local CM, BM = cd.M, bf.M
  local cw, bw = cd.window, bf.window
  cd.State = function() return "ready" end
  CM.db.showBuffs, CM.db.hideReady = false, false
  CM.db.lists = { SHAMAN = { { t = "s", id = 1, cd = 60 }, { t = "s", id = 2, cd = 60 }, { t = "s", id = 3, cd = 60 } }, ALL = {} }
  bf.State = function() return "missing" end
  bf.Castable = function() return true end
  BM.db.hideUnlearned, BM.db.allBar, BM.db.attach = false, false, "OFF"
  BM.db.lists = { SHAMAN = { { id = 11 }, { id = 12 } }, ALL = {} }
  local function Redraw() bf.Apply(); cw:Refresh(); bw:Refresh(); Hoverable(cw); Hoverable(bw) end
  Redraw()
  local function Rows() return RowOf(cw, "Bob-Stone"), RowOf(bw, "Bob-Stone") end
  local cr, br = Rows()
  Check(Ids(cr) == "1,2,3" and Ids(br) == "11,12", "start: " .. Ids(cr) .. " / " .. Ids(br))

  -- arrange mode covers both bars
  cd.ToggleArrange()
  Check(MMTIconBars.Arranging("MMTCooldowns") and MMTIconBars.Arranging("MMTBuffs"), "arrange not shared")
  Redraw(); cr, br = Rows()
  Check(cr.icons[1].data.drag and br.icons[1].data.drag, "no drag on one of the bars")

  -- buff 12 onto Bob's cooldown row, after cooldown 1
  Drag(br, 2, 1, cr)
  local b12 = Find(BM.db.lists.SHAMAN, 12)
  Check(b12.host == "MMTCooldowns" and b12.after == "c:s1", ("buff 12: host %s after %s"):format(tostring(b12.host), tostring(b12.after)))
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "1,12,2,3" and Ids(br) == "11", "after the drop: " .. Ids(cr) .. " / " .. Ids(br))
  Check(cr.icons[2].data.guest, "the buff isn't a guest on the cooldown row")

  -- anywhere in that row: to the end, then first
  Drag(cr, 2, 4)   -- past the last icon as shown (the dragged one still in its place)
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "1,2,3,12" and b12.after == "c:s3", "to the end: " .. Ids(cr) .. " after " .. tostring(b12.after))
  Drag(cr, 4, 0)
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "12,1,2,3" and b12.after == "^", "first: " .. Ids(cr) .. " after " .. tostring(b12.after))
  -- dropped on its own spot: nothing changes
  Drag(cr, 1, 0)
  Check(b12.after == "^", "moved without moving")

  -- back home, before buff 11: its list order changes too
  Redraw(); cr, br = Rows()
  Drag(cr, 1, 0, br)
  Check(b12.host == nil and b12.after == nil, "buff 12 not home")
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "1,2,3" and Ids(br) == "12,11" and ListIds(BM.db.lists.SHAMAN) == "12,11", "home: " .. Ids(cr) .. " / " .. Ids(br))

  -- a cooldown onto the buff row, first
  Drag(cr, 3, 0, br)
  local c3 = CM.db.lists.SHAMAN[3]
  Check(c3.host == "MMTBuffs" and c3.after == "^", "cooldown 3 not on the buff bar")
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "1,2" and Ids(br) == "3,12,11", "cooldown on the buff row: " .. Ids(cr) .. " / " .. Ids(br))
  -- the Buffs window hidden: it comes back home
  BM.db.shown = false
  Redraw(); cr = RowOf(cw, "Bob-Stone")
  Check(Ids(cr) == "1,2,3", "hidden host: " .. Ids(cr))
  BM.db.shown = true
  c3.host, c3.after = nil, nil

  -- not arranging, hide ready: buff 12 after cooldown 2, which is ready (hidden) -> after 1
  cd.ToggleArrange()
  Check(not MMTIconBars.Arranging("MMTBuffs"), "arrange off not shared")
  b12.host, b12.after = "MMTCooldowns", "c:s2"
  CM.db.hideReady = true
  cd.State = function(key, e) if e.id == 2 then return "ready" end return "cd", GetTime() - 1, 60 end
  Redraw(); cr = RowOf(cw, "Bob-Stone")
  Check(Ids(cr) == "1,12,3", "hidden anchor: " .. Ids(cr))
  CM.db.hideReady = false
  cd.State = function() return "ready" end

  -- attached: every buff on the cooldown row; placing one keeps host empty, detaching brings it home
  b12.host, b12.after = nil, nil
  BM.db.attach = "RIGHT"
  bf.ToggleArrange()
  Redraw(); cr = RowOf(cw, "Bob-Stone")
  Check(Ids(cr) == "1,2,3,12,11", "attached: " .. Ids(cr))
  Check(not RowOf(bw, "Bob-Stone"), "attached: a member row in the Buffs window")
  Drag(cr, 5, 1)
  local b11 = Find(BM.db.lists.SHAMAN, 11)
  Check(b11.host == nil and b11.after == "c:s1", "attached place: host " .. tostring(b11.host) .. " after " .. tostring(b11.after))
  Redraw(); cr = RowOf(cw, "Bob-Stone")
  Check(Ids(cr) == "1,11,2,3,12", "attached, moved: " .. Ids(cr))
  BM.db.attach = "OFF"
  Redraw(); cr, br = Rows()
  Check(Ids(cr) == "1,2,3" and Ids(br) == "12,11", "detached: " .. Ids(cr) .. " / " .. Ids(br))
  bf.ToggleArrange()

  -- export / import keep the placement, drop nonsense
  b12.host, b12.after = "MMTCooldowns", "c:s2"
  local def = bf.TransferDef()
  local lists = def.sections[1].get()
  lists.SHAMAN[2].host, lists.SHAMAN[2].after = "Elsewhere", ("x"):rep(200)
  Check(def.sections[1].set(lists), "import failed")
  local e1, e2 = BM.db.lists.SHAMAN[1], BM.db.lists.SHAMAN[2]
  Check(e1.id == 12 and e1.host == "MMTCooldowns" and e1.after == "c:s2", "import lost the placement")
  Check(e2.host == nil and e2.after == nil, "import kept a bad placement")
  local cdef = cd.TransferDef()
  CM.db.lists.SHAMAN[1].host, CM.db.lists.SHAMAN[1].after = "MMTBuffs", "b:12"
  local cl = cdef.sections[1].get()
  Check(cdef.sections[1].set(cl) and CM.db.lists.SHAMAN[1].host == "MMTBuffs" and CM.db.lists.SHAMAN[1].after == "b:12", "cooldown import lost the placement")
  return "icon moves between bars ok"
end''')(mods['MMT_CooldownTimers'], mods['MMT_BuffTimers']))
