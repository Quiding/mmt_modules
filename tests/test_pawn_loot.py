"""MMT_PawnCompare/Loot.lua: master loot to the member an item is the biggest upgrade for, by the
Pawn scale chosen per character (Loot Distribution's MMT.RegisterLootChooser hook)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- items: id = { equipLoc, classID, subClassID, minLevel, stats }
ITEMS = {
  [100] = { "INVTYPE_CHEST", 4, 1, 1, { Intellect = 10 } },     -- cloth chest
  [101] = { "INVTYPE_CHEST", 4, 1, 1, { Intellect = 5 } },
  [102] = { "INVTYPE_CHEST", 4, 1, 1, { Intellect = 8 } },
  [103] = { "INVTYPE_CHEST", 4, 1, 1, { Intellect = 5.1 } },    -- +2% over 101
  [110] = { "INVTYPE_CHEST", 4, 4, 1, { Strength = 20 } },      -- plate chest
  [111] = { "INVTYPE_CHEST", 4, 4, 1, { Strength = 10, Stamina = 4 } },
  [120] = { "INVTYPE_FINGER", 4, 0, 40, { Intellect = 6, Strength = 6 } },  -- ring, level 40
  [121] = { "INVTYPE_FINGER", 4, 0, 1, { Intellect = 3 } },
  [122] = { "INVTYPE_FINGER", 4, 0, 1, { Intellect = 4 } },
  [130] = { "INVTYPE_CHEST", 4, 1, 1, { Spirit = 10 } },         -- nobody values Spirit
  [200] = { nil, 7, 0, 1, { } },                                  -- trade good
}
local function Item(link) return ITEMS[tonumber(tostring(link):match("item:(%d+)"))] end
C_Item = { GetItemInfoInstant = function(link)
  local i = Item(link); if not i then return nil end
  return 1, "", "", i[1], 1, i[2], i[3]
end }
function GetItemInfo(link) local i = Item(link); if i then return "x", link, 3, 30, i[4] end end
function UnitLevel() return 60 end

EQUIP = {}
MMTDB = { moduleData = { ItemCompare = { equipment = EQUIP } } }
MMT = { IsSecret = function() return false end, IsSelf = function() return false end,
  status = {}, db = { team = {} } }
MEMBERS = { "Mage-A", "Warr-B", "Priest-C" }
function MMT.SortedMembers() return MEMBERS end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.Repr(k) return tostring(k) end
function MMT.Print() end
CHOOSERS = {}
function MMT.RegisterLootChooser(c) CHOOSERS[#CHOOSERS + 1] = c end
''')

mod = lua.eval(r'''function()
  local m = {}
  m.M = { enabled = true, db = { lootByUpgrade = true, lootMinGain = 1, lootScale = {} }, store = {}, Debug = function() end }
  m.PawnReady = function() return true end
  SCALES = {}
  m.ScalesOf = function(key) return SCALES[key] end
  return m
end''')()
for f in ["Score.lua", "Proficiency.lua", "Loot.lua"]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open('MMT_PawnCompare/' + f, encoding='utf-8').read(), f, mod)

print(lua.eval(r'''function(m)
  -- item stats from the table above (Pawn's parsing is not part of this test)
  m.ItemStats = function(link) local i = ITEMS[tonumber(tostring(link):match("item:(%d+)"))]; return i and i[5], true end
  local db = m.M.db
  local function wear(key, items) local t = {}; for slot, id in pairs(items) do t[slot] = tostring(id) end; EQUIP[key] = { items = t } end
  local function reset()
    MMT.status = { ["Mage-A"] = { class = "MAGE", level = 60 }, ["Warr-B"] = { class = "WARRIOR", level = 60 },
      ["Priest-C"] = { class = "PRIEST", level = 60 } }
    SCALES["Mage-A"] = { scales = { { name = "Frost", values = { Intellect = 1 } } } }
    SCALES["Warr-B"] = { scales = { { name = "Arms", values = { Strength = 1 } }, { name = "Tank", values = { Stamina = 2, Strength = 0.5 } } } }
    SCALES["Priest-C"] = { scales = { { name = "Holy", values = { Intellect = 1 } } } }
    wear("Mage-A", { [5] = 101, [11] = 121, [12] = 122 })   -- chest Int 5, rings Int 3 / 4
    wear("Warr-B", { [5] = 111 })
    wear("Priest-C", { [5] = 102, [11] = 122, [12] = 122 }) -- chest Int 8
    db.lootByUpgrade, db.lootMinGain, db.lootScale = true, 1, {}
  end
  local function best(id, cands) return m.BestLootRecipient("item:" .. id, cands or MEMBERS) end
  local out = {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end

  reset()
  -- biggest upgrade in percent: Mage +100% (5 -> 10) beats Priest +25% (8 -> 10)
  local key, reason = best(100)
  check("biggest % upgrade", key, "Mage-A")
  check("reason names % and scale", reason, "Pawn: +100% Frost")
  -- only the candidates Loot Distribution offers (Mage too far away / bags full)
  check("only candidates", best(100, { "Warr-B", "Priest-C" }), "Priest-C")
  -- an empty slot beats any percentage
  EQUIP["Priest-C"].items[5] = nil
  check("empty slot first", best(100), "Priest-C")
  -- no equipment known for a member: left out
  EQUIP["Priest-C"] = nil
  check("unknown equipment left out", best(100), "Mage-A")

  reset()
  -- class can't use plate: the warrior gets it, even though the mage's scale ignores it
  check("plate to the warrior", best(110), "Warr-B")
  -- per-character scale: with "Tank" the warrior's old chest (10 Str, 4 Sta = 13) vs 20 Str (10) is a downgrade
  db.lootScale["Warr-B"] = "Tank"
  local k, why = best(110)
  check("chosen scale counts", k, nil)
  check("upgrade for nobody", why, "an upgrade for nobody")
  -- a scale name that no longer exists: back to the first scale
  db.lootScale["Warr-B"] = "Gone"
  check("missing scale falls back to the first", best(110), "Warr-B")

  reset()
  -- minimum gain: +2% is not enough with 5%, enough with 1%
  db.lootMinGain = 5
  check("below minimum gain", best(103, { "Mage-A" }), nil)
  db.lootMinGain = 1
  check("above minimum gain", best(103, { "Mage-A" }), "Mage-A")

  reset()
  -- ring: compared against the weaker ring; level 40 needed
  -- Mage: weaker ring Int 3 -> 6 = +100%; Priest: rings Int 4 -> 6 = +50%; Warrior: no rings = empty slot
  check("empty ring slot first", best(120), "Warr-B")
  MMT.status["Warr-B"].level = 30
  check("below required level left out", best(120), "Mage-A")

  reset()
  -- ties: team order (Priest first in this team order)
  wear("Mage-A", { [5] = 102 })
  MEMBERS = { "Priest-C", "Mage-A", "Warr-B" }
  check("tie: team order", best(100), "Priest-C")
  MEMBERS = { "Mage-A", "Warr-B", "Priest-C" }
  check("tie: team order (other order)", best(100), "Mage-A")

  reset()
  check("nobody values it", best(130), nil)
  local k2, why2 = best(200)
  check("not equippable", k2, nil)
  check("not equippable reason", why2, "not equippable")

  -- ranking for /mmtpc loot: best first, the warrior (plate only? no: cloth is fine) and reasons
  local list, skipped = m.LootRanking("item:110", MEMBERS)
  check("ranking: warrior first", list[1].key, "Warr-B")
  check("ranking: mage left out", skipped["Mage-A"], "class can't use it")

  -- the hook in Loot Distribution
  check("registered once", #CHOOSERS, 1)
  local c = CHOOSERS[1]
  check("chooser name", c.name, "PawnCompare")
  check("active while on", c.active(), true)
  check("choose picks", (c.choose("item:100", { "Mage-A", "Priest-C" }, { isQuest = false })), "Mage-A")
  check("quest items left to the rules", (c.choose("item:100", MEMBERS, { isQuest = true })), nil)
  db.lootByUpgrade = false
  check("off: not active", c.active(), false)
  db.lootByUpgrade = true
  m.PawnReady = function() return false end
  check("no Pawn: not active", c.active(), false)
  m.RegisterLoot()
  check("RegisterLoot again does nothing", #CHOOSERS, 1)
  return ("pawn loot: %d checks ok"):format(#out)
end''')(mod))
