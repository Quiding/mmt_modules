"""Icons beside the party / raid frames (IconBars v14, "Party frames" tab of Cooldown Timers and
Buff Timers): each member's row is placed at their unit frame's screen position (EllesmereUI's
party header + self button, its raid group headers, Blizzard's compact party frames), follows a
re-sort (EUI_NameSort swaps the units of the header's buttons), a member who leaves the group goes
back to the window (or is hidden), rows of both modules on one side line up (Cooldowns nearest the
frame), Buff icons attached to the Cooldowns bars come along, and the All bar sits above the top
frame. Both modules load into one Lua state (one shared MMTIconBars), on test_settings' stand-ins
with frames that keep their size, points and shown state."""
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
  rawset(f, "drop", false)
  rawset(f, "SetScript", function(self, k, fn) scripts[k] = fn end)
  rawset(f, "GetScript", function(self, k) return scripts[k] end)
  rawset(f, "HookScript", function(self, k, fn) local old = scripts[k]; scripts[k] = function(...) if old then old(...) end fn(...) end end)
  rawset(f, "GetParent", function(self) return rawget(self, "parent") end)
  rawset(f, "Show", function(self) self.shown = true end)
  rawset(f, "Hide", function(self) self.shown = false end)
  rawset(f, "SetShown", function(self, v) self.shown = v and true or false end)
  rawset(f, "IsShown", function(self) return self.shown end)
  rawset(f, "IsVisible", function(self) return self.shown end)
  rawset(f, "CreateTexture", function() return Frame() end)
  rawset(f, "SetSize", function(self, w, h) self.w, self.h = w, h end)
  rawset(f, "SetPoint", function(self, ...) self.pt = { ... } end)
  rawset(f, "ClearAllPoints", function(self) self.pt = nil end)
  rawset(f, "GetPoint", function() return "CENTER", nil, "CENTER", 0, 0 end)
  rawset(f, "GetEffectiveScale", function() return 1 end)
  for _, k in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom" }) do rawset(f, k, function() return nil end) end
  FRAMES[#FRAMES + 1] = f
  return f
end
function CreateFrame(kind, name, parent)
  local f = Frame(parent)
  if name then rawset(_G, name, f) end
  return f
end
UIParent = Frame()

-- a unit frame at (left, bottom), 80 x 36; unit by attribute (secure button) or field (Blizzard compact)
function UnitButton(name, unit, l, b, byField)
  local f = Frame()
  rawset(f, "l", l); rawset(f, "b", b)
  rawset(f, "u", unit)
  rawset(f, "GetRect", function(self) return self.l, self.b, 80, 36 end)
  rawset(f, "GetLeft", function(self) return self.l end)
  rawset(f, "GetHeight", function() return 36 end)
  rawset(f, "GetTop", function(self) return self.b + 36 end)
  if byField then
    rawset(f, "unit", unit)
    rawset(f, "GetAttribute", function() return nil end)
  else
    rawset(f, "GetAttribute", function(self, k) if k == "unit" then return self.u end end)
  end
  if name then rawset(_G, name, f) end
  return f
end
function Header(name, buttons)
  local h = Frame()
  for i, b in ipairs(buttons) do rawset(h, i, b) end
  rawset(h, "GetAttribute", function() return nil end)
  rawset(_G, name, h)
  return h
end

-- units: who they are (stays the same in this test, so the lib's unit cache is right)
NAMES = { player = "Anna", party1 = "Bob", party2 = "Cid", raid1 = "Anna", raid2 = "Bob", raid3 = "Cid", raid4 = "Eve" }
function UnitExists(u) return NAMES[u] ~= nil end
function UnitIsPlayer(u) return NAMES[u] ~= nil end
function UnitInParty() return false end
function UnitInRaid() return false end
'''

COMMON = r'''
MMT.status = {}
MMT.SplitUnit = function(u) local n = NAMES[u]; if n then return n, "Stone", n .. "-Stone" end end
MMT.Resolve = function(k) return k end
MMT.IsSelf = function(k) return k == "Anna-Stone" end
MMT.PlayerFull = function() return "Anna-Stone" end
MMT.SortedMembers = function() return { "Anna-Stone", "Bob-Stone", "Cid-Stone", "Dan-Stone" } end
MMT.ModuleActive = function() return true end
for _, k in ipairs({ "Anna-Stone", "Bob-Stone", "Cid-Stone", "Dan-Stone", "Eve-Stone" }) do MMT.db.team[k] = { class = "SHAMAN" } end

-- the frame row of a member (or label) in a window, nil if none shown
function FRow(w, key)
  for _, r in ipairs(w.frows) do if r.shown and r.key == key then return r end end
end
function WRow(w, key)
  if not w.frame.shown then return nil end
  for _, r in ipairs(w.rows) do if r.shown and r.key == key then return r end end
end
function XY(r) return r.pt[4], r.pt[5] end
function Check(cond, msg) if not cond then error(msg, 2) end end
'''

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(FRAMES)
lua.execute(COMMON)
mods = {}
for folder in ['MMT_CooldownTimers', 'MMT_BuffTimers']:
    m = lua.eval('{}')
    for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, m)
    mods[folder] = m

print(lua.eval(r'''function(cd, bf)
  local CM, BM = cd.M, bf.M
  assert(MMTIconBars.version == 18, "IconBars version " .. tostring(MMTIconBars.version))
  -- Cooldowns: three ready spells for everyone; Buffs: off for now
  cd.State = function() return "ready" end
  CM.db.showBuffs, CM.db.hideReady = false, false
  CM.db.lists = { SHAMAN = { { t = "s", id = 1, cd = 60 }, { t = "s", id = 2, cd = 60 }, { t = "s", id = 3, cd = 60 } }, ALL = {} }
  BM.db.shown = false
  bf.Apply()
  local w = cd.window

  -- EllesmereUI party: self button (Show Self First) + header with Bob and Cid; Dan isn't in the group
  local self = UnitButton("ERFPartySelfButton", "player", 100, 500)
  local b1 = UnitButton(nil, "party1", 100, 460)
  local b2 = UnitButton(nil, "party2", 100, 420)
  local hdr = Header("ERFPartyHeader", { b1, b2 })
  local byKey, top, count = MMTIconBars.UnitFrames()
  Check(byKey["Anna-Stone"] == self and byKey["Bob-Stone"] == b1 and byKey["Cid-Stone"] == b2, "frames not found by unit")
  Check(top == self and count.EllesmereUI == 3, "top frame / count")
  Check(cd.FramesFound() == "EllesmereUI (3)", "found text: " .. cd.FramesFound())

  -- on the frames, right side, 20 px icons: x = 100 + 80 + 2, y centred on the 36 px frame
  CM.db.onFrames, CM.db.framesSide, CM.db.framesIconSize = true, "RIGHT", 20
  w:Refresh()
  local bob = FRow(w, "Bob-Stone")
  Check(bob and bob.unitFrame == b1, "Bob's row not on his frame")
  local x, y = XY(bob)
  Check(x == 182 and y == 468, ("Bob's row at %s, %s"):format(tostring(x), tostring(y)))
  Check(bob.w == 3 * 20 + 2 * 2 and bob.h == 20 and bob.icons[1].w == 20, "row / icon size")
  Check(bob.pt[1] == "BOTTOMLEFT" and bob.pt[2] == UIParent, "not placed on UIParent")
  Check(FRow(w, "Anna-Stone") and FRow(w, "Cid-Stone"), "Anna / Cid not on frames")
  -- Dan has no frame: in the window, alone
  Check(WRow(w, "Dan-Stone") and not WRow(w, "Bob-Stone"), "Dan not (alone) in the window")
  CM.db.framesOthers = "HIDE"
  w:Refresh()
  Check(not w.frame.shown, "HIDE: window still shown")
  CM.db.framesOthers = "WINDOW"
  w:Refresh()
  -- icons as high as the frame (36 px), centred on it
  CM.db.framesFit = true
  w:Refresh()
  bob = FRow(w, "Bob-Stone")
  x, y = XY(bob)
  Check(bob.h == 36 and bob.icons[1].w == 36 and bob.w == 3 * 36 + 2 * 2 and y == 460, "framesFit: size / place")
  CM.db.framesFit = false
  w:Refresh()

  -- other sides and offsets
  CM.db.framesSide, CM.db.framesX, CM.db.framesY = "LEFT", -3, 5
  w:Refresh()
  x, y = XY(FRow(w, "Bob-Stone"))
  Check(x == 100 - 2 - 64 - 3 and y == 468 + 5, ("LEFT at %s, %s"):format(x, y))
  CM.db.framesSide, CM.db.framesX, CM.db.framesY = "TOP", 0, 0
  w:Refresh()
  x, y = XY(FRow(w, "Bob-Stone"))
  Check(x == 100 and y == 460 + 36 + 2, ("TOP at %s, %s"):format(x, y))
  CM.db.framesSide = "BOTTOM"
  w:Refresh()
  x, y = XY(FRow(w, "Bob-Stone"))
  Check(x == 100 and y == 460 - 2 - 20, ("BOTTOM at %s, %s"):format(x, y))
  CM.db.framesSide = "RIGHT"
  w:Refresh()

  -- re-sort (EUI_NameSort / EllesmereUI's own sort): the buttons swap units
  b1.u, b2.u = "party2", "party1"
  MMTIconBars.CheckFrames()
  bob = FRow(w, "Bob-Stone")
  Check(bob.unitFrame == b2 and select(2, XY(bob)) == 428, "Bob's row didn't follow the re-sort")
  Check(FRow(w, "Cid-Stone").unitFrame == b1, "Cid's row didn't follow")
  -- the frames move (EllesmereUI's mover): the next poll follows
  b2.b = 300
  MMTIconBars.CheckFrames()
  Check(select(2, XY(FRow(w, "Bob-Stone"))) == 308, "row didn't follow a moved frame")

  -- Bob leaves the group: his button hides, his row goes back to the window
  b2.shown = false
  MMTIconBars.CheckFrames()
  Check(not FRow(w, "Bob-Stone") and WRow(w, "Bob-Stone"), "Bob not back in the window")
  b2.shown = true
  MMTIconBars.CheckFrames()
  Check(FRow(w, "Bob-Stone"), "Bob not back on his frame")

  -- Buff Timers on the frames too, same side: after the cooldown row (Cooldowns nearest the frame)
  bf.State = function() return "missing" end
  bf.Castable = function() return true end
  BM.db.lists = { SHAMAN = { { id = 11 }, { id = 12 } }, ALL = { { id = 21 } } }
  BM.db.shown, BM.db.hideUnlearned, BM.db.allBar = true, false, true
  BM.db.attach, BM.db.onFrames, BM.db.framesSide, BM.db.framesIconSize = "OFF", true, "RIGHT", 20
  bf.Apply()
  local bw = bf.window
  local brow = FRow(bw, "Cid-Stone")
  Check(brow and brow.unitFrame == b1, "Cid's buff row not on his frame")
  x = XY(brow)
  Check(x == 182 + 64 + 2, "buff row not after the cooldown row: x = " .. tostring(x))
  -- All bar free: in the window, alone
  Check(WRow(bw, "All") and not WRow(bw, "Cid-Stone"), "All bar not in the window")
  -- All bar above the party frames: above the top frame (Anna's self button)
  BM.db.allOnFrames = true
  bf.Apply()
  local all = FRow(bw, "All")
  Check(all and all.unitFrame == self and all.label, "All bar not on the top frame")
  x, y = XY(all)
  Check(x == 100 and y == 500 + 36 + 2, ("All bar at %s, %s"):format(x, y))
  Check(not WRow(bw, "All") and WRow(bw, "Dan-Stone"), "Buffs window: only Dan (no frame) should be left")
  BM.db.framesOthers = "HIDE"
  bf.Apply()
  Check(not bw.frame.shown, "Buffs window still shown with everyone on frames or hidden")
  -- buffs above the frames too: the All bar goes above Anna's buff row
  BM.db.framesSide = "TOP"
  bf.Apply()
  Check(select(2, XY(FRow(bw, "Anna-Stone"))) == 538, "Anna's buff row above her frame")
  Check(select(2, XY(FRow(bw, "All"))) == 538 + 20 + 2, "All bar not above the buff row")
  BM.db.allX, BM.db.allY = 4, 6
  bf.Apply()
  x, y = XY(FRow(bw, "All"))
  Check(x == 104 and y == 566, "All bar offsets")

  -- attached to the Cooldowns bars: the buff icons ride on the cooldown rows beside the frames
  BM.db.attach, BM.db.onFrames = "RIGHT", false
  bf.Apply()
  Check(not FRow(bw, "Cid-Stone"), "own buff rows while attached")
  local cid = FRow(w, "Cid-Stone")
  Check(cid.icons[4].shown and cid.icons[4].data.spell == 11 and cid.w == 5 * 20 + 4 * 2, "buffs not on the cooldown row")
  Check(FRow(bw, "All"), "All bar left the frames while attached")

  -- hidden / switched off: no frame rows
  CM.db.shown = false
  w:Refresh()
  Check(not FRow(w, "Cid-Stone"), "frame rows while hidden")
  CM.db.shown = true
  w:Refresh()
  CM.OnDisable()
  Check(not FRow(w, "Cid-Stone") and not w.onFrames, "frame rows after OnDisable")
  w:Refresh()
  -- the settings tab's "Where": back to the window
  BM.db.attach, BM.db.onFrames = "OFF", false
  CM.db.onFrames = false
  w:Refresh(); bf.Apply()
  Check(not FRow(w, "Cid-Stone") and WRow(w, "Cid-Stone"), "Cooldowns back in the window")
  CM.db.onFrames = true
  w:Refresh()

  -- Blizzard's compact party frames (no EllesmereUI): unit as a field
  rawset(_G, "ERFPartySelfButton", nil); rawset(_G, "ERFPartyHeader", nil)
  local c1 = UnitButton("CompactPartyFrameMember1", "player", 10, 200, true)
  local c2 = UnitButton("CompactPartyFrameMember2", "party1", 10, 160, true)
  MMTIconBars.CheckFrames()
  Check(FRow(w, "Bob-Stone").unitFrame == c2 and FRow(w, "Anna-Stone").unitFrame == c1, "Blizzard compact frames not used")
  Check(cd.FramesFound() == "Blizzard raid frames (2)", "found: " .. cd.FramesFound())
  Check(WRow(w, "Cid-Stone"), "Cid (no frame now) not in the window")

  -- EllesmereUI raid: group headers with raid units; EllesmereUI wins over Blizzard's
  local r1 = UnitButton(nil, "raid1", 400, 600)
  local r2 = UnitButton(nil, "raid3", 400, 560)
  local r3 = UnitButton(nil, "raid2", 490, 600)
  Header("ERFGroupHeader1", { r1, r2 })
  Header("ERFGroupHeader2", { r3 })
  MMTIconBars.CheckFrames()
  Check(FRow(w, "Anna-Stone").unitFrame == r1 and FRow(w, "Cid-Stone").unitFrame == r2 and FRow(w, "Bob-Stone").unitFrame == r3,
    "raid group headers not used first")
  local _, topNow = MMTIconBars.UnitFrames()
  Check(topNow == r1, "top frame of the raid: highest, then leftmost")
  return "party frames ok"
end''')(mods['MMT_CooldownTimers'], mods['MMT_BuffTimers']))
