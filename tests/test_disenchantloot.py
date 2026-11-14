"""MMT_DisenchantLoot: worth disenchanting (Auctionator value vs vendor price), master loot to the
enchanter (Loot Distribution's chooser hook), the others junk (Baganator plugin with Dejunk) and sold.
The item's own auction price: when it beats both, "AH" (neither enchanter nor junk)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- items: id = { quality, sell, classID, item level }
ITEMS = {
  [1] = { 2, 100, 4, 10 },      -- green armour 10: 1.2 x dust + 0.3 x lesser magic = 150
  [2] = { 2, 500, 2, 10 },      -- green weapon 10: 0.3 x dust + 1.2 x lesser magic = 150 < vendor
  [3] = { 3, 100, 4, 20 },      -- blue 20: a small glimmering shard = 900
  [4] = { 2, 50, 7, 10 },       -- green trade good: not weapon/armour
  [5] = { 2, 100, 4, 30 },      -- green armour 30: soul dust never scanned
  [6] = { 1, 10, 4, 10 },       -- white
}
local function Item(link) return ITEMS[tonumber(tostring(link):match("item:(%d+)"))] end
function GetItemInfo(link)
  if type(link) == "number" then return nil end
  local i = Item(link); if i then return "x", link, i[1], i[4], 1, "", "", 1, "", 1, i[2], i[3] end
end
PRICES = { [10940] = 100, [10938] = 100, [10978] = 900, [11082] = 300, [11084] = 1000 }
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
  assert(type(caller) == "string")
  return PRICES[id]
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
NOW, CLOCK = 1, 100000
function GetTime() return NOW end
function time() return CLOCK end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
INGROUP, LEADER = false, false
function IsInGroup() return INGROUP end
function UnitIsGroupLeader() return LEADER end
TEAMUP = {}
MMT_MODULES = { PawnCompare = { enabled = true, TeamUpgrades = function(link) return TEAMUP[tonumber(link:match("item:(%d+)"))] or {} end } }
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
  M.store = { priceTime = CLOCK }   -- fresh prices
  MMT.modules = MMT_MODULES
  return m
end''')()
for f in ["Module.lua", "Value.lua", "Age.lua", "Junk.lua"]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open('MMT_DisenchantLoot/' + f, encoding='utf-8').read(), f, mod)

print(lua.eval(r'''function(m)
  local db, out = m.M.db, {}
  db.money = "MMT"
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
  local v, de, sell, why, missing = m.Verdict(L(5))
  check("no price", v, nil)
  check("no price: soul dust named", missing and missing[1], 11083)
  check("armour value", select(2, m.Verdict(L(1))), 150)
  PRICES[10939] = 150   -- greater magic essence: a third (50) is cheaper than a lesser one (100)
  check("lesser essence from the greater", select(2, m.Verdict(L(1))), 135)
  PRICES[10939] = nil
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
  TEAMUP[2] = { "Sla-C" }; check("an upgrade for a teammate: not junk", m.IsJunk(0, 1), false); TEAMUP[2] = nil
  local pcUp = MMT_MODULES.PawnCompare.TeamUpgrades
  MMT_MODULES.PawnCompare.TeamUpgrades = function() return nil end
  check("Pawn Compare can't tell: not junk", m.IsJunk(0, 1), false)
  MMT_MODULES.PawnCompare.TeamUpgrades = pcUp
  UPGRADES[2] = true; check("own Pawn upgrade with Pawn Compare on: not junk", m.IsJunk(0, 1), false)
  MMT_MODULES.PawnCompare.enabled = false
  check("Pawn Compare off: own Pawn upgrade not junk", m.IsJunk(0, 1), false)
  MMT_MODULES.PawnCompare.enabled = true; UPGRADES[2] = nil
  db.junkOn = false; check("junk off", m.IsJunk(0, 1), false); db.junkOn = true

  -- Baganator plugin = Dejunk's junk plus ours
  local p = PLUGINS[m.PLUGIN_ID]
  check("plugin registered", type(p), "function")
  check("plugin: ours", p(0, 1), true)
  check("plugin: neither", p(0, 3), false)
  DJ["0:3"] = true; check("plugin: Dejunk's", p(0, 3), true); DJ["0:3"] = nil

  -- what it disenchants into
  local list = m.Breakdown(L(1))
  check("breakdown entries", #list, 2)
  check("dust chance", list[1].chance, 80)
  check("dust counts", list[1].min .. "-" .. list[1].max, "1-2")
  check("dust price", list[1].price, 100)
  check("essence chance", list[2].chance, 20)
  LINES = {}
  local tt = { GetItem = function() return "x", L(5) end,
    AddLine = function(_, t) LINES[#LINES + 1] = t end, AddDoubleLine = function(_, l, r) LINES[#LINES + 1] = l .. " | " .. r end }
  SHIFT = true
  m.TipLine(tt)
  check("tooltip: header without a value", LINES[1], "Disenchants into:")
  check("tooltip: soul dust, no price", LINES[2], "  75%  1-2 Soul Dust | |cff888888no price|r")
  LINES = {}; tt.GetItem = function() return "x", L(1) end; m.TipLine(tt)
  check("tooltip: value line first", LINES[1]:match("^Disenchant 150c / vendor 100c") ~= nil, true)
  check("tooltip: materials", LINES[2], "  80%  1-2 Strange Dust | 100c")
  SHIFT = false; LINES = {}; m.TipLine(tt)
  check("Shift up: value and a hint", #LINES, 2)
  check("hint", LINES[2], "  Hold Shift: what it disenchants into")
  db.matsShow = "ALWAYS"; LINES = {}; m.TipLine(tt); check("materials always", #LINES, 3)
  db.tipShow = "CTRL"; LINES = {}; m.TipLine(tt); check("value only with Ctrl", LINES[1], "Disenchants into:")
  db.tipShow, db.matsShow = "NEVER", "NEVER"; LINES = {}; m.TipLine(tt); check("never", #LINES, 0)
  db.tipShow, db.matsShow = "ALWAYS", "SHIFT"
  -- Shift redraws the hover tooltip and a clicked chat link's tooltip
  local set, refreshed
  ItemRefTooltip = { IsShown = function() return true end, GetItem = function() return "x", L(1) end,
    SetHyperlink = function(_, l) set = l end }
  GameTooltip = { IsShown = function() return true end, GetItem = function() return "x", L(2) end,
    RefreshData = function() refreshed = true end }
  EVENTS.MODIFIER_STATE_CHANGED()
  check("chat link tooltip set again", set, L(1))
  check("hover tooltip refreshed", refreshed, true)
  ItemRefTooltip, GameTooltip = nil, nil

  -- old prices
  check("fresh: not stale", m.Stale(), false)
  m.M.store.priceTime = CLOCK - 9 * 3600
  check("9 h: stale", m.Stale(), true)
  check("age text", m.AgeText(), "Auctionator prices are 9 h old - scan the auction house")
  LINES = {}; m.TipLine(tt); check("tooltip warning", LINES[#LINES], "  Auctionator prices are 9 h old - scan the auction house")
  INGROUP = true; check("not the leader: no reminder", m.Remind(), false)
  LEADER = true; check("leader: reminder", m.Remind(), true)
  check("reminder text", PRINTED, "Disenchant Loot: Auctionator prices are 9 h old - scan the auction house for fresh disenchant values.")
  check("once an hour", m.Remind(), false)
  NOW = NOW + 3601; check("an hour later", m.Remind(), true)
  db.staleHours = 12; check("12 h setting: fine", m.Stale(), false); db.staleHours = 8
  db.staleOn = false; check("reminder off", m.Stale(), false); db.staleOn = true
  m.M.store.priceTime = nil; check("no scan time: stale", m.Stale(), true)
  MMT_MODULES.QoL = { store = { ahTaken = CLOCK - 3600 } }
  check("QoL's taken prices count", m.Stale(), false)
  m.M.store.priceTime = CLOCK; MMT_MODULES.QoL = nil; INGROUP, LEADER = false, false

  -- sold at a vendor, only ours
  EVENTS.MERCHANT_SHOW()
  check("sold the junk", BAGS[0][1].sold, true)
  check("kept the rest", BAGS[0][3].sold, nil)
  check("sale line", PRINTED, "Disenchant Loot: sold 1 item for 500c.")
  return table.concat(out, ", ")
end''')(mod))

# the auction house as the third choice
print(lua.eval(r'''function(m)
  local db, out = m.M.db, {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  local function L(id) return "|cff1eff00|Hitem:" .. id .. "::|h[x]|h|r" end
  ITEMAH = {}
  Auctionator.API.v1.GetAuctionPriceByItemLink = function(caller, link) return ITEMAH[tonumber(link:match("item:(%d+)"))] end
  check("no auction price: as before", (m.Verdict(L(1))), "DE")
  ITEMAH[1] = 160; check("160 < 110% of 150: still disenchant", (m.Verdict(L(1))), "DE")
  ITEMAH[1] = 170
  local v, de, sell, _, _, ah = m.Verdict(L(1))
  check("170 >= 165: auction house", v, "AH"); check("auction price returned", ah, 170)
  check("not to the enchanter", m.Choose(L(1), { "Der-B" }, {}), nil)
  ITEMAH[2] = 600; check("vendor 500 x 110% = 550 < 600: auction house", (m.Verdict(L(2))), "AH")
  BAGS = { [0] = { { 2, false } } }
  check("not junk", m.IsJunk(0, 1), false)
  ITEMAH[2] = 540; check("540 < 550: junk again", (m.Verdict(L(2))), "JUNK")
  db.ahPct = 100; check("pct 100: 540 >= 500", (m.Verdict(L(2))), "AH"); db.ahPct = 110
  db.ahOn = false; check("off", (m.Verdict(L(1))), "DE"); db.ahOn = true
  MMT_MODULES.QoL = { enabled = true, AuctionPrice = function() return 10 end }
  check("Quality of life's price wins", (m.Verdict(L(1))), "DE")
  MMT_MODULES.QoL.AuctionPrice = function() return 9999 end
  check("... and counts", (m.Verdict(L(1))), "AH")
  check("other modules see it", (m.M.Verdict(L(1))), "AH")
  MMT_MODULES.QoL = nil
  LINES = {}
  local tt = { GetItem = function() return "x", L(1) end,
    AddLine = function(_, t) LINES[#LINES + 1] = t end, AddDoubleLine = function(_, l, r) LINES[#LINES + 1] = l .. " | " .. r end }
  db.tipShow = "ALWAYS"
  m.TipLine(tt)
  check("tooltip: all three", LINES[1], "Disenchant 150c / vendor 100c / auction 170c: |cff66ff66auction house|r")
  -- the vendor pays most: items without a disenchant value
  check("trade good, no auction price: left", (m.Verdict(L(4))), nil)
  ITEMAH[4] = 30
  local v4, de4, sell4, _, _, ah4 = m.Verdict(L(4))
  check("trade good, auction 30 < vendor 50: junk", v4, "JUNK"); check("no disenchant value", de4, nil); check("auction", ah4, 30)
  BAGS = { [0] = { { 4, false } } }
  check("in the bags: junk", m.IsJunk(0, 1), true)
  check("no enchanter for it", m.Choose(L(4), { "Der-B" }, {}), nil)
  ITEMAH[4] = 80; check("auction 80 > vendor 50: left", (m.Verdict(L(4))), nil)
  ITEMAH[4] = 30; db.vendorJunk = false; check("option off: left", (m.Verdict(L(4))), nil); db.vendorJunk = true
  ITEMAH[5] = 50; check("materials never scanned, auction below vendor: junk", (m.Verdict(L(5))), "JUNK")
  LINES = {}; tt.GetItem = function() return "x", L(4) end; m.TipLine(tt)
  check("tooltip without a disenchant value", LINES[1], "Vendor 50c / auction 30c: |cff999999junk|r")
  return table.concat(out, ", ")
end''')(mod))
print("PASS")
