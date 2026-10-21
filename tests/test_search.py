"""Search.lua (Cooldowns / Buffs): the spell name index, ranking, exact names,
own items, and the popup under the add box (stand-in frames)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local U = {}
local function new() return setmetatable({}, U) end
U.__index = function(t, k)
  if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
  if k == "GetText" then return function(self) return rawget(self, "_text") end end
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
  if k == "SetScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
  if k == "HookScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
  if k == "GetWidth" or k == "GetEffectiveScale" then return function() return 1 end end
  return function() return new() end
end
STUB = new
function CreateFrame() return new() end
UIParent = new()
SPELLS = { [2825] = "Bloodlust", [6673] = "Battle Shout", [5242] = "Battle Shout", [1259416] = "Walk on Air",
  [1719] = "Recklessness", [12345] = "Blood Fury", [400100] = "Shout of the Blood" }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end, GetSpellTexture = function() return 136000 end }
C_Item = { GetItemNameByID = function(id) return ({ [13446] = "Major Healing Potion", [11122] = "Carrot on a Stick" })[id] end,
  GetItemIconByID = function() return 134400 end }
function GetInventoryItemID(_, slot) if slot == 13 then return 11122 end end
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
  GetContainerItemID = function(bag, slot) if slot == 1 then return 13446 end end }
TICKS = 0
C_Timer = {
  After = function(_, f) end,
  NewTicker = function(_, f) local t = { stop = false }; function t:Cancel() self.stop = true end
    while not t.stop do f(t); TICKS = TICKS + 1 end; return t end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
MMT = { IsSecret = function() return false end, UI = setmetatable({}, { __index = function() return function() return new() end end }) }
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
GameTooltip = new()
''')
mod = lua.eval('{}')
lua.execute(r'''function SETUP(m)
  m.PRESETS = { { entries = { { t = "s", id = 6673 } } } }   -- the preset's rank wins
  m.SpellInfo = function(id) return SPELLS[id] end
  m.SpellIcon = function() return 136000 end
end''')
lua.eval('SETUP')(mod)
lua.eval('function(src, m) assert(loadstring(src, "Search.lua"))("x", m) end')(
    open('MMT_Cooldowns/Search.lua', encoding='utf-8').read(), mod)

print(lua.eval(r'''function(m)
  -- nothing before the index is built (only own items)
  assert(#m.Search("bl", false) == 0, "results before the index")
  assert(m.FindByName("Bloodlust") == nil, "exact name before the index")
  -- the popup starts the index
  -- a plain edit box (unset fields really are nil, as in the game)
  local box = { _text = "" }
  function box:GetText() return self._text end
  function box:SetText(v) self._text = v end
  function box:HasFocus() return true end
  function box:HookScript(ev, fn) self["_" .. ev] = fn end
  function box:GetWidth() return 150 end
  function box:GetEffectiveScale() return 1 end
  local picked
  local p = m.AttachSearch(box, { items = true, onPick = function(t, id, name) picked = { t, id, name } end })
  box._text = "blood"
  box._OnTextChanged(box, true)
  assert(TICKS > 10, "index not built in steps")
  -- ranking: names starting with the text first, shorter first; then the ones containing it
  local r = m.Search("blood", false)
  local names = {}
  for _, e in ipairs(r) do names[#names + 1] = e.name end
  assert(table.concat(names, ",") == "Bloodlust,Blood Fury,Shout of the Blood", table.concat(names, ","))
  -- duplicate names: the preset's ID wins
  assert(select(2, m.FindByName("battle shout")) == 6673, "preset rank")
  assert(select(2, m.FindByName("  Walk on Air ")) == 1259416, "Forever ID range")
  -- items you carry or wear
  local t, id = m.FindByName("major healing potion", true)
  assert(t == "i" and id == 13446, "bag item")
  assert(m.FindByName("major healing potion", false) == nil, "items when not asked for")
  local items = m.Search("carrot", true)
  assert(#items == 1 and items[1].t == "i" and items[1].id == 11122, "equipped item")
  assert(#m.Search("b", false) == 0, "one letter searched")
  -- the popup: rows for the matches, a click fills the box and remembers the pick
  assert(p:IsShown() and p.rows[1].entry.name == "Bloodlust", "popup rows")
  p.rows[1]._OnClick(p.rows[1])
  assert(box._text == "Bloodlust" and box.picked.id == 2825 and picked[2] == 2825, "pick")
  assert(not p:IsShown(), "popup still open after the pick")
  -- typing again forgets the pick
  box._text = "Bloodlus"
  box._OnTextChanged(box, true)
  assert(box.picked == nil and p:IsShown(), "pick kept after typing")
  -- nothing found: a note row
  box._text = "zzzz"
  box._OnTextChanged(box, true)
  assert(rawget(p.rows[1], "entry") == nil and p.rows[1].text._text:find("Nothing found", 1, true), "no-match note")
  return "search ok (" .. TICKS .. " steps)"
end''')(mod))

# bug: "Seal of Righteousness" picked spell 864, the trainer spell "Teaches Seal of
# Righteousness" (generic WoW-logo icon): a real spell of the same name wins over it
SPELLS2 = {864: "Seal of Righteousness", 20154: "Seal of Righteousness", 3694: "Seal of Reckoning"}
lua.execute('SPELLS = {}; C_Spell.GetSpellName = function(id) return SPELLS[id] end')
for k, v in SPELLS2.items():
    lua.eval('function(k, v) SPELLS[k] = v end')(k, v)
mod2 = lua.eval('{}')
lua.eval(r'''function(m)
  m.PRESETS = {}
  m.GENERIC_ICON = 136235
  m.SpellInfo = function(id) return SPELLS[id] end
  m.SpellIcon = function(id) if id == 864 then return 136235 end return SPELLS[id] and 135960 end
end''')(mod2)
lua.eval('function(src, m) assert(loadstring(src, "Search.lua"))("x", m) end')(
    open('MMT_Cooldowns/Search.lua', encoding='utf-8').read(), mod2)
print(lua.eval(r'''function(m)
  local box = { _text = "" }
  function box:GetText() return self._text end
  function box:SetText(v) self._text = v end
  function box:HasFocus() return true end
  function box:HookScript(ev, fn) self["_" .. ev] = fn end
  function box:GetWidth() return 150 end
  function box:GetEffectiveScale() return 1 end
  m.AttachSearch(box, { onPick = function() end })
  box._text = "seal of r"
  box._OnTextChanged(box, true)       -- builds the index
  local t, id = m.FindByName("Seal of Righteousness")
  assert(t == "s" and id == 20154, "the trainer spell won: " .. tostring(id))
  return "trainer spells lose ok"
end''')(mod2))
