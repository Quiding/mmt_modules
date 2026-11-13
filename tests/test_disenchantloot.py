"""MMT_DisenchantLoot: worth disenchanting (Auctionator value vs vendor price), master loot to the
enchanter (Loot Distribution's chooser hook), the others junk (Baganator plugin with Dejunk) and sold."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- items: id = { quality, sell, classID, disenchant value }
ITEMS = {
  [1] = { 2, 100, 4, 300 },     -- green armour, mats 3x vendor
  [2] = { 2, 500, 2, 200 },     -- green weapon, vendor beats mats
  [3] = { 3, 100, 4, 900 },     -- blue
  [4] = { 2, 50, 7, 500 },      -- green trade good: not weapon/armour
  [5] = { 2, 100, 4, nil },     -- no disenchant price
  [6] = { 1, 10, 4, 50 },       -- white
}
local function Item(link) return ITEMS[tonumber(tostring(link):match("item:(%d+)"))] end
function GetItemInfo(link) local i = Item(link); if i then return "x", link, i[1], 10, 1, "", "", 1, "", 1, i[2], i[3] end end
Auctionator = { API = { v1 = { GetDisenchantPriceByItemLink = function(caller, link)
  assert(type(caller) == "string")
  local i = Item(link); return i and i[4]
end } } }
MMT = { IsSelf = function() return false end }
ROLES = { ["Cal-A"] = { "Main" }, ["Der-B"] = { "Enchanter", "Bank" }, ["Sla-C"] = {} }
MEMBERS = { "Cal-A", "Der-B", "Sla-C" }
function MMT.SortedMembers() return MEMBERS end
function MMT.MemberRoleList(k) return ROLES[k] or {} end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FormatMoney(c) return tostring(c) .. "c" end
function MMT.Print(...) PRINTED = string.format(...) end
CHOOSERS = {}
function MMT.RegisterLootChooser(c) CHOOSERS[#CHOOSERS + 1] = c end
EVENTS = {}
BAGS = {}   -- [bag][slot] = { itemID, isBound }
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local s = BAGS[bag] and BAGS[bag][slot]; if not s or s.sold then return nil end
    return { itemID = s[1], isBound = s[2], hyperlink = "|cff1eff00|Hitem:" .. s[1] .. "::|h[x]|h|r", stackCount = 1 }
  end,
  UseContainerItem = function(bag, slot) BAGS[bag][slot].sold = true end,
}
C_Timer = { After = function(_, f) f() end }
function GetTime() return 1 end
SlashCmdList = {}
UPGRADES = {}
function PawnGetItemData(link) return { link = link } end
function PawnIsItemAnUpgrade(item) return UPGRADES[tonumber(item.link:match("item:(%d+)"))] end
DJ = {}
DejunkApi = { Events = { BagsUpdated = "B" }, IsJunk = function(_, bag, slot) return DJ[bag .. ":" .. slot] or false end,
  AddListener = function() end }
PLUGINS = {}
Baganator = { API = { RegisterJunkPlugin = function(label, id, fn) PLUGINS[id] = fn end,
  RequestItemButtonsRefresh = function() end, IsJunkPluginActive = function() return true end } }
''')

mod = lua.eval(r'''function()
  local m = {}
  local M = { enabled = true, db = {}, Debug = function() end }
  function M:On(e, fn) EVENTS[e] = fn end
  MMT.NewModule = function(def) for k, v in pairs(def.defaults) do M.db[k] = v end; M.defaults = def.defaults; return M end
  return m
end''')()
for f in ["Module.lua", "Junk.lua"]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open('MMT_DisenchantLoot/' + f, encoding='utf-8').read(), f, mod)

print(lua.eval(r'''function(m)
  local db, out = m.M.db, {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  local function L(id) return "|cff1eff00|Hitem:" .. id .. "::|h[x]|h|r" end

  -- the value check
  check("green armour worth it", (m.Verdict(L(1))), "DE")
  check("vendor beats mats", (m.Verdict(L(2))), "JUNK")
  check("blue left out", (m.Verdict(L(3))), nil)
  db.quality = "GREEN_BLUE"; check("blue with GREEN_BLUE", (m.Verdict(L(3))), "DE"); db.quality = "GREEN"
  check("trade good", (m.Verdict(L(4))), nil)
  check("no price", (m.Verdict(L(5))), nil)
  check("white", (m.Verdict(L(6))), nil)
  db.pct = 400; check("pct 400: 3x is not enough", (m.Verdict(L(1))), "JUNK"); db.pct = 100
  db.minSilver = 5; check("min 5 silver", (m.Verdict(L(1))), "JUNK"); db.minSilver = 0

  -- master loot: registered, Enchanter role by default
  check("chooser registered", #CHOOSERS, 1)
  local c = CHOOSERS[1]
  check("active", c.active(), true)
  check("to the enchanter", (c.choose(L(1), MEMBERS, {})), "Der-B")
  check("enchanter can't take it", (c.choose(L(1), { "Cal-A", "Sla-C" }, {})), nil)
  check("not worth it: rules", (c.choose(L(2), MEMBERS, {})), nil)
  check("quest items untouched", (c.choose(L(1), MEMBERS, { isQuest = true })), nil)
  db.to = "CHAR:Sla-C"; check("a character", (c.choose(L(1), MEMBERS, {})), "Sla-C"); db.to = "ROLE:Enchanter"
  db.lootOn = false; check("loot off", c.active(), false); db.lootOn = true
  local A = Auctionator; Auctionator = nil; check("no Auctionator: inactive", c.active(), false); Auctionator = A

  -- junk: unbound, not worth it, not an upgrade
  BAGS[0] = { { 2, false }, { 2, true }, { 1, false }, { 5, false } }
  check("junk", m.IsJunk(0, 1), true)
  check("bound: never", m.IsJunk(0, 2), false)
  check("worth it: not junk", m.IsJunk(0, 3), false)
  check("no price: not junk", m.IsJunk(0, 4), false)
  UPGRADES[2] = true; check("Pawn upgrade: not junk", m.IsJunk(0, 1), false); UPGRADES[2] = nil
  db.junkOn = false; check("junk off", m.IsJunk(0, 1), false); db.junkOn = true

  -- Baganator plugin = Dejunk's junk plus ours
  local p = PLUGINS[m.PLUGIN_ID]
  check("plugin registered", type(p), "function")
  check("plugin: ours", p(0, 1), true)
  check("plugin: neither", p(0, 3), false)
  DJ["0:3"] = true; check("plugin: Dejunk's", p(0, 3), true); DJ["0:3"] = nil

  -- sold at a vendor, only ours
  EVENTS.MERCHANT_SHOW()
  check("sold the junk", BAGS[0][1].sold, true)
  check("kept the rest", BAGS[0][3].sold, nil)
  check("sale line", PRINTED, "Disenchant Loot: sold 1 item for 500c.")
  return table.concat(out, ", ")
end''')(mod))
print("PASS")
