"""(harness from test_qol_roleloot) MMT_QoL RoleLoot.lua: valuable loot onto a role, and the Baganator category "MMT Role Items".
A looted green (or blue) whose auction price is at least rvPct % of its vendor price goes on the
chosen role (through the Role items path, mod.MailAdd); left alone: Bind on Pickup, too cheap,
quality, a role already wants it, a team upgrade (Pawn Compare), Disenchant Loot's verdict DE / JUNK.
The category: made through Baganator's import with the role's items, then both ways - into the
category = onto the role, out of it = off the role, and the same from the role's side."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
ON, LISTEN, PRINTS, SENT, TIMERS, TICKERS, NOW, CLOCK = {}, {}, {}, {}, {}, {}, 0, 1800000000
SlashCmdList = {}
function GetTime() return NOW end
function time() return CLOCK end
function date() return "12:00" end
C_Timer = { After = function(d, fn) TIMERS[#TIMERS + 1] = fn end,
  NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.off = true end }; TICKERS[#TICKERS + 1] = t; return t end }
function RUN_TIMERS() for n = 1, 50 do local due = TIMERS; TIMERS = {}; if #due == 0 then return end; for _, fn in ipairs(due) do fn() end end end
LOADED = {}
C_AddOns = { IsAddOnLoaded = function(n) return LOADED[n] == true end, GetAddOnInfo = function(n) return n, n, "", false, "MISSING" end }
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Horde" end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."

-- items: id = { quality, sell, bindType }  (bindType 1 = Bind on Pickup, 2 = Bind on Equip)
ITEMS = {
  [100] = { 2, 100, 2 }, [101] = { 2, 100, 2 }, [102] = { 2, 100, 1 }, [103] = { 3, 100, 2 },
  [104] = { 2, 100, 2 }, [105] = { 2, 100, 2 }, [106] = { 2, 100, 2 }, [107] = { 1, 100, 0 },
  [108] = { 2, 0, 2 }, [109] = { 2, 100, 2 }, [200] = { 2, 50, 2 }, [300] = { 2, 50, 2 },
}
AH = { [100] = 400, [101] = 250, [102] = 900, [103] = 900, [104] = 900, [105] = 900, [106] = 900, [107] = 900, [108] = 900, [109] = 900 }
function ID(link) return tonumber(tostring(link):match("item:(%d+)")) end
function LINK(id) return "|cff1eff00|Hitem:" .. id .. "::|h[Item " .. id .. "]|h|r" end
function GetItemInfo(x)
  local id = tonumber(x) or ID(x)
  local i = ITEMS[id]
  if not i or HIDDEN == id then return nil end
  return "Item " .. id, LINK(id), i[1], 20, 1, "", "", 1, "", 1, i[2], 4, 1, i[3]
end
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link) return AH[ID(link)] end } } }

-- MMT core: roles and their rules
MMT = { IsSecret = function() return false end, UI = {}, db = { team = { ["Anna-R"] = {}, ["Bank-R"] = {} },
  roles = { Bank = { rules = {} }, Main = { rules = { { type = "item", itemID = 105 } } } } } }
MEMBER_ROLES = { ["Anna-R"] = { "Main" }, ["Bank-R"] = { "Bank" } }
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function MMT.FullDisplay(k) return (k:match("^[^-]+")) end
function MMT.IsSelf(k) return k == "Anna-R" end
function MMT.IsOnline() return true end
function MMT.SortedMembers() return { "Anna-R", "Bank-R" } end
function MMT.GuildMode() return true end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = msg end
function MMT.SendLong(msg) SENT[#SENT + 1] = msg end
function MMT.ItemInfo(x) return GetItemInfo(x) end
function MMT.SortedRoleNames() local t = {}; for r in pairs(MMT.db.roles) do t[#t + 1] = r end; table.sort(t); return t end
function MMT.MemberRoleList(k) return MEMBER_ROLES[k] or {} end
function MMT.HasRole(k, r) for _, x in ipairs(MEMBER_ROLES[k] or {}) do if x == r then return true end end return false end
function MMT.Fire() end
function MMT.AddRule(role, rule)
  local r = MMT.db.roles[role]; if not r then return false, "no role" end
  for _, e in ipairs(r.rules) do if e.type == rule.type and e.itemID == rule.itemID then return false, "already" end end
  table.insert(r.rules, rule); return true
end
function MMT.RemoveRule(role, i) table.remove(MMT.db.roles[role].rules, i) end
function MMT.MembersForItem(link)
  local id, keys = ID(link), {}
  for _, k in ipairs(MMT.SortedMembers()) do
    for _, role in ipairs(MEMBER_ROLES[k]) do
      for _, rule in ipairs(MMT.db.roles[role].rules) do if rule.itemID == id then keys[#keys + 1] = k end end
    end
  end
  return keys
end
TEAMUP, DE = {}, {}
MMT.modules = {
  PawnCompare = { enabled = true, TeamUpgrades = function(link) return TEAMUP[ID(link)] or {} end },
  DisenchantLoot = { enabled = true, Verdict = function(link) local v = DE[ID(link)]; if v then return v[1], v[2] end end },
}
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = {} for k, v in pairs(def.defaults) do M.db[k] = v end
  for _, k in ipairs({ "dejunk", "baganator", "mlist", "ahshare", "fjshare", "auras", "eui", "smartbuff", "nx" }) do M.db[k] = true end  -- the features under test: switched on (they start off)
  M.store = {}
  function M:On(e, fn) ON[e] = fn end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  return M
end

-- Baganator: the profile and an import that makes the category (as its CategoriesImport does)
BAGANATOR_CURRENT_PROFILE = "Default"
BAGANATOR_CONFIG = { Profiles = { Default = { custom_categories = { ["1"] = { name = "Gear", search = "" } },
  category_modifications = { ["1"] = { addedItems = { ["i:300"] = true } } }, category_display_order = { "1" } } } }
REFRESHES, IMPORTS = 0, 0
C_EncodingUtil = { SerializeCBOR = function(t) LASTEXPORT = t; return "cbor" end, CompressString = function(s) return s end,
  EncodeBase64 = function(s) return s end }
Baganator = { API = {
  RequestLayoutUpdate = function() REFRESHES = REFRESHES + 1 end, RequestItemButtonsRefresh = function() end,
  ImportString = function(text, name)
    assert(text == "BGR!1!cbor", text)
    IMPORTS = IMPORTS + 1
    local p = BAGANATOR_CONFIG.Profiles.Default
    local c = LASTEXPORT.categories[1]
    p.custom_categories["7"] = { name = c.name, search = c.search }
    local added = {}
    for _, id in ipairs(LASTEXPORT.modifications[1].items or {}) do added["i:" .. id] = true end
    p.category_modifications["7"] = { addedItems = added }
    table.insert(p.category_display_order, 1, "7")
  end } }
''')

mod = lua.eval('{}')
for f in ('Module.lua', 'Ask.lua', 'Bulk.lua', 'Baganator.lua', 'MailList.lua', 'LootPrice.lua', 'RoleLoot.lua', 'MageScrolls.lua', 'Offer.lua'):
    src = open('MMT_QoL/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)

print(lua.eval(r"""function(m)
  local db, out = m.M.db, {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  local function On(role, id)
    for _, r in ipairs((MMT.db.roles[role] or { rules = {} }).rules) do if r.itemID == id then return true end end
    return false
  end
  local function SLINK(id, name) return "|cffffffff|Hitem:" .. id .. "::|h[" .. name .. "]|h|r" end
  BAGS = {}
  C_Container = { GetContainerNumSlots = function(b) return b == 0 and #BAGS or 0 end,
    GetContainerItemInfo = function(b, s) local l = BAGS[s]; return l and { hyperlink = l } end }
  LOOT = {}
  function GetNumLootItems() return #LOOT end
  function GetLootSlotLink(i) return LOOT[i] and LOOT[i][1] end
  function GetLootSlotInfo(i) return "icon", LOOT[i] and LOOT[i][2] end

  check("off by default", db.mscroll, false)
  check("role by default", db.scRole, "Mage scrolls")
  check("recognised by the link", m.IsMageScroll(SLINK(1, "Scroll: CWAL")), true)
  check("not a stat scroll", m.IsMageScroll(SLINK(2, "Scroll of Intellect")), false)
  check("off: nothing", m.ScrollBags(), 0)
  db.mscroll = true
  m.M.OnEnable(m.M)
  check("no such role yet: nothing", m.ScrollSeed(), 0)
  MMT.db.roles["Mage scrolls"] = { rules = {} }
  local n = m.ScrollSeed()
  check("the known scrolls go on", n, 12)
  check("one of them", On("Mage scrolls", 211787), true)
  check("sent to the team (Role items path)", #SENT > 0 or #TIMERS > 0, true)
  check("again: nothing new", m.ScrollSeed(), 0)
  -- on Dejunk's junk list: taken off, also when it's on the role already
  local OFF = {}
  local real = m.DejunkFromHere
  m.DejunkFromHere = function(sign, item) if sign == "-" and (item == "211780" or item == "211785") then OFF[#OFF + 1] = item; return true end return false end
  m.ScrollSeed()
  check("both junk-listed scrolls taken off", #OFF, 2)
  check("as item ID strings", OFF[1] .. "," .. OFF[2], "211780,211785")
  db.scDejunk = false; OFF = {}; m.ScrollSeed()
  check("option off: left on", #OFF, 0)
  db.scDejunk = true; m.DejunkFromHere = real
  -- a new one in the loot window, before Loot Distribution hands it out
  LOOT = { { SLINK(299001, "Scroll: NEW WORDS"), "Scroll: NEW WORDS" }, { LINK(100), "Item 100" } }
  ON.LOOT_READY()
  check("new scroll from the loot window", On("Mage scrolls", 299001), true)
  check("other loot left alone", On("Mage scrolls", 100), false)
  -- and one in the bags
  BAGS = { SLINK(299002, "Scroll: BAG ONE"), SLINK(2, "Scroll of Intellect") }
  ON.BAG_UPDATE_DELAYED(); RUN_TIMERS()
  check("new scroll from the bags", On("Mage scrolls", 299002), true)
  check("stat scroll not", On("Mage scrolls", 2), false)
  check("chat line", table.concat(PRINTS, " / "):find("mage scroll") ~= nil, true)
  db.scRole = "Bank"
  LOOT = { { SLINK(299003, "Scroll: OTHER"), "Scroll: OTHER" } }
  ON.LOOT_READY()
  check("another role picked: goes there", On("Bank", 299003), true)
  return #out .. " checks ok"
end""")(mod))
