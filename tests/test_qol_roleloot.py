"""MMT_QoL RoleLoot.lua: valuable loot onto a role, and the Baganator category "MMT Role Items".
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
for f in ('Module.lua', 'Ask.lua', 'Bulk.lua', 'Baganator.lua', 'MailList.lua', 'LootPrice.lua', 'RoleLoot.lua', 'Offer.lua'):
    src = open('MMT_QoL/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)

print(lua.eval(r'''function(m)
  local db, out = m.M.db, {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  local function OnBank(id)
    for _, r in ipairs(MMT.db.roles.Bank.rules) do if r.itemID == id then return true end end
    return false
  end
  local function Loot(id) ON.CHAT_MSG_LOOT(LOOT_ITEM_SELF:format(LINK(id))); RUN_TIMERS() end

  for _, f in ipairs(m.features) do check("feature " .. f.key .. " off by default", m.M.defaults[f.key], false) end
  check("off by default", db.rvOn, false)
  check("no role yet", (m.RoleLootCheck(LINK(100))), false)
  db.rvOn, db.rvRole, db.rvBag = true, "Bank", false
  m.M.OnEnable(m.M)

  -- the loot rule
  Loot(100); check("400 = 400% of vendor: on the role", OnBank(100), true)
  check("chat line", table.concat(PRINTS, " / "):find("goes on the role Bank") ~= nil, true)
  Loot(101); check("250 < 300%: left", OnBank(101), false)
  Loot(102); check("Bind on Pickup: left", OnBank(102), false)
  Loot(103); check("blue with greens only: left", OnBank(103), false)
  db.rvQuality = "GREEN_BLUE"; Loot(103); check("blue with green and blue", OnBank(103), true); db.rvQuality = "GREEN"
  TEAMUP[104] = { "Anna-R" }; Loot(104); check("a team upgrade: left", OnBank(104), false)
  TEAMUP[104] = nil; m.MMT_ = nil
  Loot(105); check("a role already wants it: left", OnBank(105), false)
  DE[106] = { "DE", 1000 }; Loot(106); check("disenchanting worth more: left", OnBank(106), false)
  local _, why = m.RoleLootCheck(LINK(106)); check("why", why, "disenchanting is worth more (10s, Disenchant Loot)")
  DE[106] = { "JUNK", 10 }; Loot(106); check("Disenchant Loot says junk: left", OnBank(106), false)
  DE[106] = { "AH", 10 }; Loot(106); check("Disenchant Loot says auction house: on the role", OnBank(106), true)
  -- the auction house pays most by Disenchant Loot: no % of ours on top (161% < 300%)
  ITEMS[115] = { 2, 9614, 2 }; AH[115] = 15500; DE[115] = { "AH", 11588 }
  Loot(115); check("auction house pays most: on the role below our %", OnBank(115), true)
  ITEMS[116] = { 2, 9614, 2 }; AH[116] = 15500
  Loot(116); check("no Disenchant Loot verdict: our % (161% < 300%)", OnBank(116), false)
  Loot(107); check("white: left", OnBank(107), false)
  Loot(108); check("no vendor price: left", OnBank(108), false)
  ON.CHAT_MSG_LOOT(LOOT_ITEM_SELF_MULTIPLE:format(LINK(109), 2)); RUN_TIMERS()
  check("several at once", OnBank(109), true)
  local n = #MMT.db.roles.Bank.rules
  Loot(100); check("already on it: once", #MMT.db.roles.Bank.rules, n)
  -- item data not loaded yet: asked again a moment later
  ITEMS[110] = { 2, 100, 2 }; AH[110] = 900; HIDDEN = 110
  ON.CHAT_MSG_LOOT(LOOT_ITEM_SELF:format(LINK(110)))
  check("not loaded: not yet", OnBank(110), false)
  HIDDEN = nil; RUN_TIMERS(); check("then on the role", OnBank(110), true)
  ON.CHAT_MSG_LOOT("Anna receives loot: " .. LINK(101) .. ".")
  check("someone else's loot: not ours", #TIMERS, 0)
  -- traded to us: read while the window is open, checked on "Trade complete"
  ERR_TRADE_COMPLETE = "Trade complete."
  ITEMS[111], ITEMS[112] = { 2, 100, 2 }, { 2, 100, 2 }
  AH[111], AH[112] = 900, 150
  TRADE = { [1] = LINK(111), [3] = LINK(112), [7] = LINK(113) }
  function GetTradeTargetItemLink(i) return TRADE[i] end
  ON.TRADE_SHOW(); ON.TRADE_TARGET_ITEM_CHANGED(1); ON.TRADE_ACCEPT_UPDATE(1, 1)
  TRADE = {}   -- the slots are empty by the time the trade is done
  check("not before it's done", OnBank(111), false)
  ON.UI_INFO_MESSAGE(0, ERR_TRADE_COMPLETE); RUN_TIMERS()
  check("traded, worth it: on the role", OnBank(111), true)
  check("traded, too cheap: left", OnBank(112), false)
  check("slot 7 (not traded): left", OnBank(113), false)
  ITEMS[114] = { 2, 100, 2 }; AH[114] = 900
  TRADE = { [1] = LINK(114) }; ON.TRADE_SHOW(); ON.TRADE_ACCEPT_UPDATE(1, 0); ON.UI_INFO_MESSAGE(0, "Trade cancelled."); RUN_TIMERS()
  check("cancelled: left", OnBank(114), false)
  ON.UI_INFO_MESSAGE(0, ERR_TRADE_COMPLETE); RUN_TIMERS()
  db.rvOn = false; AH[101] = 900; Loot(101); check("switched off", OnBank(101), false); db.rvOn = true
  local qml = false
  for _, s in ipairs(SENT) do if s:find("^QML:") then qml = true end end
  check("the change goes to the team", qml, true)

  -- the Baganator category
  local p = BAGANATOR_CONFIG.Profiles.Default
  db.rvBag = true
  check("first pass: made", m.RoleBagSync(), true)
  check("through Baganator's import", IMPORTS, 1)
  check("named", p.custom_categories["7"].name, "MMT Role Items")
  check("with the role's items", p.category_modifications["7"].addedItems["i:100"], true)
  check("in sync: nothing to do", m.RoleBagSync(), false)
  check("made once", IMPORTS, 1)
  -- into the category in Baganator -> onto the role
  p.category_modifications["7"].addedItems["i:200"] = true
  check("bag -> role", m.RoleBagSync(), true)
  check("200 on the role", OnBank(200), true)
  -- out of the category -> off the role
  p.category_modifications["7"].addedItems["i:100"] = nil
  m.RoleBagSync(); check("100 off the role", OnBank(100), false)
  -- onto the role -> into the category, out of the other one it was put in
  m.MailAdd("Bank", 300); m.RoleBagSync()
  check("300 in ours", p.category_modifications["7"].addedItems["i:300"], true)
  check("out of Gear", p.category_modifications["1"].addedItems["i:300"], nil)
  -- off the role -> out of the category
  for i, r in ipairs(MMT.db.roles.Bank.rules) do if r.itemID == 300 then m.MailRemove("Bank", i) break end end
  m.RoleBagSync(); check("300 out of ours", p.category_modifications["7"].addedItems["i:300"], nil)
  check("bags redrawn", REFRESHES > 0, true)
  -- another role: the category shows its items, neither role changes
  db.rvRole = "Main"
  m.RoleBagSync()
  check("Main's item in the category", p.category_modifications["7"].addedItems["i:105"], true)
  check("Bank's item out of it", p.category_modifications["7"].addedItems["i:200"], nil)
  check("not onto Main", #MMT.db.roles.Main.rules, 1)
  check("Bank keeps its items", OnBank(200), true)
  check("then in sync", m.RoleBagSync(), false)
  db.rvBag = false; check("category off", m.RoleBagSync(), false)
  local lines = {}
  m.RoleLootFeature.Report(function(l) lines[#lines + 1] = l end)
  check("report", lines[1]:find("^Valuable loot: on=true role=Main") ~= nil, true)
  return table.concat(out, ", ")
end''')(mod))
# offering the features whose addon is loaded
print(lua.eval(r"""function(m)
  local db, out = m.M.db, {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  DIALOGS = {}
  MMT.UI.Confirm = function(text, yes, onYes, no, onNo) DIALOGS[#DIALOGS + 1] = { text = text, yes = onYes, no = onNo } end
  function IsInGroup() return INGROUP end
  function UnitIsGroupLeader() return LEADER end
  function InCombatLockdown() return COMBAT end
  local started = 0
  m.Feature({ key = "zed", addon = "Zed", title = "Zed things", tabText = "Zed", tip = "Shares Zed's lists.", OnEnable = function() started = started + 1 end })
  m.Feature({ key = "yak", addon = "Yak", title = "Yak things", tip = "Yak." })
  db.zed, db.yak, db.baganator = false, false, false
  LOADED = { Zed = true, Baganator = true }
  ON.PLAYER_ENTERING_WORLD(); ON.PLAYER_ENTERING_WORLD(); RUN_TIMERS()
  check("one dialog at a time", #DIALOGS, 1)
  check("Baganator's first (tab order)", DIALOGS[1].text:find("Baganator categories") ~= nil, true)
  check("says what it does", DIALOGS[1].text:find("Baganator is loaded on this character") ~= nil, true)
  DIALOGS[1].no(); RUN_TIMERS()
  check("then the next", #DIALOGS, 2)
  check("Zed's text", DIALOGS[2].text:find("Shares Zed's lists.", 1, true) ~= nil and DIALOGS[2].text:find("Quality of life > Zed", 1, true) ~= nil, true)
  DIALOGS[2].yes(); RUN_TIMERS()
  check("switched on", db.zed, true); check("started", started, 1)
  check("not loaded: not offered", #DIALOGS, 2)
  check("no remembered", m.M.store.offered.baganator, "no")
  check("yes remembered", m.M.store.offered.zed, "yes")
  check("not asked again", #m.Offers(), 0)
  INGROUP, LEADER = true, false
  m.M.store.offered = nil; db.zed = false
  check("not the leader: nothing", m.OfferAll(), 0)
  LEADER = true; DIALOGS = {}
  check("the leader: both again", m.OfferAll(), 2)
  check("still one at a time", #DIALOGS, 1)
  DIALOGS[1].no(); RUN_TIMERS(); DIALOGS[2].no(); RUN_TIMERS()
  DIALOGS = {}
  SlashCmdList.MMTQOL("offers"); RUN_TIMERS()
  check("/mmtqol offers asks again", #DIALOGS, 1)
  m.M.enabled = false; check("module off: nothing", m.OfferAll(true), 0); m.M.enabled = true
  return table.concat(out, ", ")
end""")(mod))
print("PASS")
