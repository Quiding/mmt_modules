"""MMT_QoL NameSwap.lua: a profile's members renamed in a copy - Class + number
placeholders, typed names, keys inside texts ("CHAR:First-Last"), first names only
as whole values, two members on one name refused, the original left alone."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
MMT = { UI = {} }
SERIALIZED = nil
function MMT.Serialize(v) SERIALIZED = v return "<data>" end
LOCALIZED_CLASS_NAMES_MALE = { PALADIN = "Paladin", DEATHKNIGHT = "Death Knight", MAGE = "Mage" }
''')
mod = lua.eval('{ M = { db = {} } }')
lua.eval('function(m) m.Feature = function(f) return f end end')(mod)
src = open('MMT_QoL/NameSwap.lua', encoding='utf-8').read()
lua.eval('function(src, m) assert(loadstring(src, "NameSwap.lua"))("x", m) end')(src, mod)

print(lua.eval(r'''function(m)
  local data = {
    team = {
      ["Anna-Smith"] = { name = "Anna", last = "Smith", class = "PALADIN", order = 1, roles = { Tank = true } },
      ["Bob-Stone"]  = { name = "Bob", last = "Stone", class = "PALADIN", order = 2 },
      ["Cara-Hill"]  = { name = "Cara", last = "Hill", class = "DEATHKNIGHT", order = 3 },
      ["Dan"]        = { name = "Dan", class = "MAGE", order = 4 },
    },
    modules = {
      BuffTimers = { specSet = { ["Anna-Smith"] = "HOLY", ["Bob-Stone"] = "RET" }, playerRoles = { Cara = "TANK" } },
      CooldownTimers = { lists = { ["CHAR:Bob-Stone"] = { { t = "s", id = 1 } } } },
      Totems = { calls = { ["Dan"] = true } },
      text = "Anna-Smith tanks, Bob-Stoneheart stays, Annabel too",
      word = "Anna",
    },
  }
  -- placeholders, team order, per class
  local ph = m.NxAnonMap(data)
  assert(ph["Anna-Smith"] == "Paladin1" and ph["Bob-Stone"] == "Paladin2" and ph["Cara-Hill"] == "DeathKnight1" and ph["Dan"] == "Mage1", "placeholders")
  local out, pname = m.NxRename(data, ph, "Anna's team")
  assert(out.team.Paladin1 and out.team.Paladin1.name == "Paladin1" and out.team.Paladin1.last == nil and out.team.Paladin1.roles.Tank, "team record")
  assert(out.team["Anna-Smith"] == nil and out.team.Mage1.class == "MAGE", "old keys gone")
  assert(out.modules.BuffTimers.specSet.Paladin1 == "HOLY" and out.modules.BuffTimers.specSet.Paladin2 == "RET", "spec keys")
  assert(out.modules.BuffTimers.playerRoles.DeathKnight1 == "TANK", "bare first name as a key")
  assert(out.modules.CooldownTimers.lists["CHAR:Paladin2"], "CHAR: key")
  assert(out.modules.Totems.calls.Mage1, "first-name-only member")
  assert(out.modules.text == "Paladin1 tanks, Bob-Stoneheart stays, Annabel too", "text: " .. out.modules.text)
  assert(out.modules.word == "Paladin1", "whole-value first name")
  assert(pname == "Anna's team", "profile name: " .. tostring(pname))
  assert(data.team["Anna-Smith"] and data.modules.BuffTimers.specSet["Anna-Smith"], "original changed")

  -- typed names (a swap between two members too), empty = kept
  out = m.NxRename(data, { ["Anna-Smith"] = "Bob Stone", ["Bob-Stone"] = "Anna-Smith", ["Cara-Hill"] = "  Zed  " })
  assert(out.team["Bob-Stone"].roles.Tank and out.team["Anna-Smith"].order == 2, "swap")
  assert(out.modules.BuffTimers.specSet["Bob-Stone"] == "HOLY" and out.modules.BuffTimers.specSet["Anna-Smith"] == "RET", "swapped specs")
  assert(out.team.Zed and out.team.Zed.name == "Zed" and out.team.Zed.last == nil and out.modules.BuffTimers.playerRoles.Zed, "first name only")
  assert(out.team.Dan and out.modules.Totems.calls.Dan, "kept")

  -- two members on one name: refused
  local ok, why = m.NxCheck(data, { ["Anna-Smith"] = "Dan" })
  assert(not ok and why:find("Dan"), "clash not caught")
  local str, why2 = m.NxExport(data, { ["Anna-Smith"] = "Dan" }, "x")
  assert(str == nil and why2, "export with a clash")
  str = m.NxExport(data, ph, "Team")
  assert(str == "MMT1:<data>" and SERIALIZED.name == "Team" and SERIALIZED.data.team.Paladin1, "export")
  assert(m.NxKey("Anna Smith") == "Anna-Smith" and m.NxKey("") == nil, "keys")
  return "names: placeholders, typed names, swap, texts, clash"
end''')(mod))

# parts left out: core settings, role items, a module; a new profile filling them from mine
print(lua.eval(r"""function(m)
  MMT.modules = { BuffTimers = { title = "Buff Timers" }, QoL = { title = "Quality of life" } }
  local data = {
    team = { ["Anna-Smith"] = { name = "Anna", last = "Smith", class = "MAGE", order = 1, roles = { Bank = true } } },
    roles = { Bank = { rules = { { type = "item", itemID = 2589 } } } },
    xp = { shown = true }, merchant = { repair = "Anna-Smith" },
    modules = { BuffTimers = { specSet = { ["Anna-Smith"] = "FIRE" } }, QoL = { mlRole = "Bank" } },
  }
  local parts = m.NxParts(data)
  local ids = {}
  for i, p in ipairs(parts) do ids[i] = p.id end
  assert(table.concat(ids, " ") == "core roleitems m:BuffTimers m:QoL", table.concat(ids, " "))
  assert(parts[3].text == "Buff Timers", "module title")

  local skip = { core = true, roleitems = true, ["m:QoL"] = true }
  assert(m.NxExport(data, { ["Anna-Smith"] = "Zed" }, "T", skip))
  local out = SERIALIZED.data
  assert(out.xp == nil and out.merchant == nil, "core left in")
  assert(out.team.Zed and out.team.Zed.roles.Bank and out.roles.Bank and #out.roles.Bank.rules == 0, "roles kept, items out")
  assert(out.modules.QoL == nil and out.modules.BuffTimers.specSet.Zed == "FIRE", "module")
  assert(data.xp and #data.roles.Bank.rules == 1 and data.modules.QoL, "original changed")

  -- a new profile: left-out parts from mine, as they are
  local mine = { team = {}, roles = { Bank = { rules = { { type = "item", itemID = 4306 } } }, Herbs = { rules = {} } },
    xp = { shown = false }, modules = { QoL = { mlRole = "Herbs" } } }
  local p = m.NxProfileData(data, { ["Anna-Smith"] = "Zed" }, skip, true, mine)
  assert(p.xp.shown == false and p.merchant == nil, "core from mine")
  assert(p.roles.Bank.rules[1].itemID == 4306 and p.roles.Herbs, "role items from mine")
  assert(p.modules.QoL.mlRole == "Herbs" and p.modules.QoL ~= mine.modules.QoL, "module from mine (a copy)")
  assert(p.modules.BuffTimers.specSet.Zed == "FIRE", "included part renamed")
  p = m.NxProfileData(data, {}, skip, false, mine)
  assert(p.xp == nil and p.modules.QoL == nil and #p.roles.Bank.rules == 0, "without keep-mine: left out")
  return "names: parts left out, filled from mine"
end""")(mod))
