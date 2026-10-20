"""MMT_PawnCompare/Proficiency.lua: classes that can never use an item get no Pawn value."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
ITEMS = {  -- id = classID, subclassID
  [1] = { 2, 2 },   -- bow
  [2] = { 2, 4 },   -- 1H mace
  [3] = { 4, 4 },   -- plate
  [4] = { 4, 3 },   -- mail
  [5] = { 4, 0 },   -- ring
  [6] = { 2, 19 },  -- wand
  [7] = { 4, 6 },   -- shield
  [8] = { 0, 0 },   -- potion
}
C_Item = { GetItemInfoInstant = function(link)
  local i = ITEMS[tonumber(link:match("item:(%d+)"))]
  return 1, "", "", "", 1, i[1], i[2]
end }
function UnitClass() return "Shaman", "SHAMAN" end
MMT = { IsSecret = function() return false end, IsSelf = function(k) return k == "Me" end,
  status = { Mage = { class = "MAGE" } }, db = { team = { Warr = { class = "WARRIOR" } } } }
''')
mod = lua.eval('{}')
lua.eval('function(src, m) assert(loadstring(src, "Proficiency.lua"))("x", m) end')(
    open('MMT_PawnCompare/Proficiency.lua', encoding='utf-8').read(), mod)
print(lua.eval(r'''function(m)
  local function can(key, id) return m.CanUse(key, "item:" .. id) end
  assert(not can("Me", 1) and can("Me", 2) and not can("Me", 3) and can("Me", 4), "shaman: bow / mace / plate / mail")
  assert(can("Me", 5) and not can("Me", 6) and can("Me", 7) and can("Me", 8), "shaman: ring / wand / shield / potion")
  assert(not can("Mage", 4) and can("Mage", 6) and not can("Mage", 7), "mage (class from the status)")
  assert(can("Warr", 1) and can("Warr", 3) and not can("Warr", 6), "warrior (class from the team)")
  assert(can("Nobody", 1), "unknown class: shown")
  return "proficiency ok"
end''')(mod))
