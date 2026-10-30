"""MMT_TeamGear: member list, reading Item Compare's stored gear, the gear
window (stand-in frames), stepping through members, the character panel button,
talents (own read from a stand-in trait tree / classic API, sent and received,
the Talents view)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- universal stand-in frame: any method exists; remembers SetText / SetTexture / Show
local U = {}
local function new() return setmetatable({}, U) end
STUB = new
local NUM = { GetFrameLevel = 1, GetLeft = 100, GetTop = 500, GetWidth = 24 }
U.__index = function(t, k)
  if NUM[k] then return function() return NUM[k] end end
  if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
  if k == "GetText" then return function(self) return rawget(self, "_text") end end
  if k == "SetTexture" then return function(self, v) rawset(self, "_tex", v) end end
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "SetShown" then return function(self, v) rawset(self, "_shown", v and true or false) end end
  if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
  if k == "SetScale" then return function(self, v) rawset(self, "_scale", v) end end
  if k == "SetPoint" then return function(self, ...) rawset(self, "_point", { ... }) end end
  if k == "ClearAllPoints" then return function(self) rawset(self, "_point", nil) end end
  if k == "GetPoint" then return function(self) local p = rawget(self, "_point") if p then return unpack(p) end end end
  return function() return new() end
end
function CreateFrame(kind, name)
  local f = new(); if name then _G[name] = f end
  if kind == "DressUpModel" then
    MODEL = f
    rawset(f, "SetCustomRace", function(self, race, gender) rawset(self, "_race", race); rawset(self, "_gender", gender); rawset(self, "_worn", {}) end)
    rawset(f, "TryOn", function(self, item) table.insert(rawget(self, "_worn"), item) end)
    rawset(f, "Undress", function(self) rawset(self, "_worn", {}) end)
    rawset(f, "SetUnit", function(self, u)
      -- like the game: nothing loads into a model whose window is hidden
      assert(rawget(_G.MMTTeamGearWindow, "_shown") ~= false, "model set up while the window is hidden")
      rawset(self, "_unit", u); rawset(self, "_worn", {}); rawset(self, "_race", nil)
    end)
  end
  return f
end
VISIBLE = true
function UnitRace(u) if u == "player" then return "Orc", "Orc", 2 end return "Human", "Human", 1 end
function UnitSex(u) if u == "player" then return 3 end return 2 end
UIParent, CharacterFrame = new(), new()
C_Timer = { After = function(_, f) f() end }
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, PRIEST = { r = 1, g = 1, b = 1 } }
LOCALIZED_CLASS_NAMES_MALE = { SHAMAN = "Shaman", PRIEST = "Priest" }
SlashCmdList = {}
ITEMS = { [4567] = { "Tough Helm", 3, 25, 133071 } }
C_Item = {
  GetItemInfo = function(s) local id = tonumber(s:match("item:(%d+)")) local i = ITEMS[id]
    if i then return i[1], "|cff0070dd|H" .. s .. "|h[" .. i[1] .. "]|h|r", i[2], nil, nil, nil, nil, nil, nil, i[4] end end,
  GetItemInfoInstant = function() return 1, nil, nil, nil, 134400 end,
  GetDetailedItemLevelInfo = function(s) local id = tonumber(s:match("item:(%d+)")) return ITEMS[id] and ITEMS[id][3] end,
  GetItemQualityColor = function() return 0, 0.44, 0.87 end,
}
C_TooltipInfo = { GetHyperlink = function(link)
  if link:find("28:5237$") then return { lines = { { leftText = "Tough Helm" }, { leftText = "Reinforced (+8 Armor)", type = 15 } } } end
  if link:find("^item:4567:1883") then return { lines = { { leftText = "Tough Helm" }, { leftText = "|cff00ff00Enchant Head - Stamina +7|r", type = 15 } } } end
  return { lines = {} } end }
function GetInventorySlotInfo() return 1, 136525 end
function IsInRaid() return false end
function IsInGroup() return true end
function UnitExists(u) return u == "party1" end
function UnitIsVisible() return VISIBLE end
function UnitClass() return "Shaman", "SHAMAN" end
function UnitLevel() return 13 end
EVENTS, LISTEN, HEARTBEATS, SENT = {}, {}, {}, {}
NOW = 1000
function GetTime() return NOW end
time = os.time
-- a stand-in Forever trait tree: three groups (given out of order), node positions
-- with one a few units off its line, one with an extra zero, a choice node, a hidden node
GROUPS = { { groupID = 103, orderIndex = 3, displayName = "Retribution" }, { groupID = 101, orderIndex = 1, displayName = "Holy" },
  { groupID = 102, orderIndex = 2, displayName = "Protection" } }
NODES, NODE_IDS, SPELLS = {}, {}, {}
local function node(id, g, x, y, rank, max, spell)
  NODE_IDS[#NODE_IDS + 1] = id
  NODES[id] = { ID = id, groupIDs = { g }, posX = x, posY = y, activeRank = rank, ranksPurchased = rank, maxRanks = max,
    entryIDs = { id * 10 }, isVisible = true }
  SPELLS[id * 10] = spell
end
node(1, 101, 1000, 1000, 5, 5, 20257); node(2, 101, 1300, 1000, 0, 5, 20262); node(3, 101, 1000, 1600, 2, 3, 20205)
node(4, 102, 3000, 1000, 1, 1, 20096)
node(5, 103, 5000, 1000, 5, 5, 20060); node(6, 103, 5600, 2200, 1, 1, 20375); node(7, 103, 5300, 22000, 1, 1, 20117)
node(8, 103, 5000, 1603, 2, 2, 20100)
NODES[8].entryIDs = { 80, 81 }; NODES[8].activeEntry = { entryID = 81 }; SPELLS[81] = 999
node(9, 103, 5900, 1000, 0, 1, 1); NODES[9].isVisible = false
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
  GetConfigInfo = function(c) return { treeIDs = { 77 } } end,
  GetTreeNodes = function(t) local r = {} for i, id in ipairs(NODE_IDS) do r[i] = id end return r end,
  GetNodeInfo = function(c, id) return NODES[id] end,
  GetEntryInfo = function(c, e) return { definitionID = e } end,
  GetDefinitionInfo = function(d) return { spellID = SPELLS[d] } end,
  GetGroupDisplayInfoByTreeID = function() local r = {} for i, g in ipairs(GROUPS) do r[i] = g end return r end,
}
C_Spell = { GetSpellTexture = function(id) return 100000 + id end }
MMTDB = { moduleData = { ItemCompare = { equipment = {
  ["Bob-Stone"] = { items = { [1] = "4567:1883", [7] = "4567:::::::::::1::1:28:5237", [16] = "9999:0:0" }, time = 100 },
  ["Dan-Lee"] = { items = { [1] = "4567" }, time = 50 },
  ["Eve-Old"] = { items = { [5] = "4567" }, time = 10 },
} } },
  profiles = { Main = { team = {} }, Alts = { team = { ["Dan-Lee"] = { class = "SHAMAN" }, ["Zed-NoGear"] = {} } } } }
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
MMT = { UI = setmetatable({ ROW = 22 }, { __index = function() return function() return new() end end }),
  ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }, CopyTable = copy,
  status = { ["Bob-Stone"] = { class = "PRIEST", level = 12 }, ["Cid-Ray"] = { class = "SHAMAN", level = 11 } } }
function MMT.UI.TextButton() local b = new(); rawset(b, "label", new()); return b end
function MMT.UI.OpenList(owner, items, current, onPick) LIST = { items = items, pick = onPick } end
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
MMT.profileName = "Main"
function MMT.ModuleActive(n) return n == "ItemCompare" end
function MMT.IsSecret() return false end
function MMT.PlayerFull() return "Anna-Smith" end
function MMT.IsSelf(k) return k == "Anna-Smith" end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone", "Cid-Ray" } end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Resolve(k) return k end
function MMT.SplitUnit(u) return nil, nil, u == "party1" and "Bob-Stone" or "Anna-Smith" end
function MMT.Ago() return "5 min ago" end   -- like the core: with "ago"
function MMT.SendLong(text, target) SENT[#SENT + 1] = { text = text, target = target } end
function MMT.SendAddon(text, kind, target) SENT[#SENT + 1] = { text = text, target = target } end
function MMT.Print(...) PRINTED = string.format(...) end
function MMT.ToggleConfig() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:Heartbeat(k, fn) HEARTBEATS[k] = fn end
  -- several files may listen to the same thing: all of them run
  local function add(t, ev, fn) local prev = t[ev] t[ev] = prev and function(...) prev(...) fn(...) end or fn end
  function M:On(ev, fn) add(EVENTS, ev, fn) end
  function M:Listen(ev, fn) add(LISTEN, ev, fn) end
  return M
end
''')
mod = lua.eval('{}')
for f in [l.strip() for l in open('MMT_TeamGear/MMT_TeamGear.toc', encoding='utf-8') if l.strip().endswith('.lua')]:
    src = open('MMT_TeamGear/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_TeamGear/' + f, mod)

print(lua.eval(r'''function(m)
  m.M.OnEnable(m.M)
  assert(m.button and m.button:IsShown(), "no button on the character panel")
  -- the list: team without yourself, class colours, greyed without stored gear
  assert(m.M.db.others == false, "other teams on by default")
  local items = m.MemberItems()
  assert(items[1].value == "__ALL__", "no whole-team entry")
  table.remove(items, 1)
  assert(#items == 2 and items[1].value == "Bob-Stone" and items[2].value == "Cid-Ray", "members")
  assert(items[1].text:find("^|cffffffffBob Stone") and items[2].text:find("^|cff0038"), "colours: " .. items[1].text .. " / " .. items[2].text)
  m.M.db.includeSelf = true
  assert(#m.MemberItems() == 4, "self not listed")
  m.M.db.includeSelf = false
  assert(#m.AllKeys() == 2, "other teams stepped through while off")
  -- other profiles' teams and every other stored character, under headers
  m.M.db.others = true
  items = m.MemberItems()
  table.remove(items, 1)
  local vals = {}
  for _, it in ipairs(items) do vals[#vals + 1] = it.header and ("#" .. it.text) or it.value end
  assert(table.concat(vals, ","):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == "#Team 1  (this team),Bob-Stone,Cid-Ray,#Team 2  (Alts),Dan-Lee,#Other characters,Eve-Old", table.concat(vals, ","))
  assert(items[5].text:find("^|cff666666%-|r |cff0070dd"), "indent + class from the other profile: " .. items[5].text)
  assert(table.concat(m.AllKeys(), ",") == "Bob-Stone,Cid-Ray,Dan-Lee,Eve-Old", "all keys")
  -- open Bob from the list
  m.OpenMemberList(m.button)
  LIST.pick("Bob-Stone")
  local f = m.window
  assert(f and f:IsShown() and f.key == "Bob-Stone", "window not open")
  assert(f:GetPoint(1), "window open but not placed (invisible in the game)")
  assert(f._scale == 1, "window scale")
  assert(f.title:GetText() == "Bob Stone", "title " .. tostring(f.title:GetText()))
  local sub = f.sub:GetText()
  assert(sub:find("Level 12") and sub:find("Priest") and sub:find("item level 25") and sub:find("gear changed 5 min ago", 1, true) and not sub:find("ago ago", 1, true), "sub: " .. sub)
  local helm = f.slots[1]
  assert(helm.item and helm.item.name == "Tough Helm" and helm.item.ilvl == 25 and helm.icon._tex == 133071, "helm")
  assert(helm.name:GetText() == "Tough Helm" and helm.level:GetText() == "Item level 25", "helm text")
  assert(helm.enchant:GetText() == "Stamina +7", "enchant: " .. tostring(helm.enchant:GetText()))
  assert(f.slots[16].enchant:GetText() == "", "enchant on an item without one")
  assert(f.slots[7].enchant:GetText() == "Reinforced (+8 Armor)", "armor kit with an empty enchant field: " .. tostring(f.slots[7].enchant:GetText()))
  -- an item the client doesn't know yet: placeholder, filled in later
  assert(f.slots[16].item and f.slots[16].name:GetText() == "...", "unknown item")
  ITEMS[9999] = { "Big Mace", 2, 20, 133000 }
  EVENTS.GET_ITEM_INFO_RECEIVED()
  assert(f.slots[16].name:GetText() == "Big Mace", "not redrawn after item info")
  assert(rawget(f.slots[2], "item") == nil and f.slots[2].icon._tex == 136525, "empty slot")
  -- next member: Cid has no gear stored
  m.Step(1)
  assert(f.key == "Cid-Ray" and rawget(f.slots[1], "item") == nil, "step")
  assert(f.note:GetText():find("No gear stored", 1, true), "no-gear note")
  m.Step(1); m.Step(1); m.Step(1)
  assert(f.key == "Bob-Stone", "step wraps over all stored characters: " .. f.key)
  m.Step(-1)
  assert(f.key == "Eve-Old" and rawget(f.slots[5], "item"), "other stored character")
  -- looks: own race/gender on the heartbeat, others from it; in sight = the real unit
  assert(HEARTBEATS.tgl() == "2.3", "heartbeat " .. tostring(HEARTBEATS.tgl()))
  m.Open("Bob-Stone")
  assert(MODEL._unit == "party1", "in sight: not the unit model")
  assert(m.LookOf("Bob-Stone").race == 1 and m.LookOf("Bob-Stone").sex == 2, "look not read from the unit")
  VISIBLE = false
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tgl = "5.3" } })
  m.Open("Bob-Stone")
  assert(MODEL._race == 5 and MODEL._gender == 1, "mannequin race/gender")
  -- a reload of the model (race switch) wipes the gear: it goes on again
  rawset(MODEL, "_worn", {})
  MODEL.dress()
  assert(#MODEL._worn == 3 and f.lookNote:IsShown() and f.lookNote:GetText():find("their race", 1, true), "gear not tried on: " .. #MODEL._worn)
  LISTEN.XP_RECEIVED("Dan-Lee", "Dan", { ext = { tgl = "bad" } })
  m.Open("Dan-Lee")
  assert(m.LookOf("Dan-Lee") == nil and MODEL:IsShown() and MODEL._unit == "player" and #MODEL._worn == 1, "no look: your body in their gear")
  assert(f.lookNote:GetText():find("your character", 1, true), "own-body label")
  VISIBLE = true
  -- the whole team at once
  m.OpenMemberList(m.button)
  LIST.pick("__ALL__")
  local o = m.overview
  assert(o and o:IsShown() and o:GetPoint(1), "overview not open / not placed")
  assert(o.rows[1].key == "Bob-Stone" and o.rows[4].key == "Eve-Old", "overview rows")
  assert(o.rows[1].icons[1].item and o.rows[1].icons[1].item.name == "Tough Helm", "overview helm")
  assert(o.rows[1].name.sub:GetText():find("ilvl", 1, true) and o.rows[2].name.sub:GetText():find("no gear stored", 1, true), "overview sub")
  m.M.db.others = false
  m.RefreshOverview()
  assert(not o.rows[3]:IsShown(), "other teams in the overview while off")
  m.M.db.others = true
  m.M.db.overviewScale = 0.8
  SlashCmdList.MMTTEAMGEAR("all")
  assert(o:IsShown() and o._scale == 0.8, "overview scale")
  -- Item Compare off
  MMT.ModuleActive = function() return false end
  m.Open("Cid-Ray")
  assert(f.note:GetText():find("Item Compare", 1, true), "item compare note")
  -- names off, button off, slash
  m.M.db.names = false; m.Open("Bob-Stone")
  assert(f.slots[1].name:GetText() == "", "names still shown")
  m.M.db.button = false; m.SetupButton()
  assert(not m.button:IsShown(), "button not hidden")
  m.Open("Cid-Ray"); SlashCmdList.MMTTEAMGEAR(" Bob-Stone ")
  assert(f.key == "Bob-Stone")
  local n = 0
  m.M.Report(m.M, function() n = n + 1 end)
  assert(n >= 4, "report lines " .. n)
  return "team gear ok"
end''')(mod))

print(lua.eval(r'''function(m)
  MMT.ModuleActive = function(n) return n == "ItemCompare" end
  m.M.db.names = true
  -- own talents from the trait tree
  local own = m.ReadOwnTalents()
  assert(own and own.source == "traits" and #own.talents == 8, "own talents: " .. tostring(own and #own.talents) .. " " .. tostring(m.talentError))
  assert(own.names[1] == "Holy" and own.names[3] == "Retribution", "tree names in group order")
  local where = {}
  for _, t in ipairs(own.talents) do where[t.spell] = t end
  assert(where[20257].tree == 1 and where[20257].row == 0 and where[20257].col == 0 and where[20257].rank == 5, "first talent")
  assert(where[20262].col == 1 and where[20205].row == 1 and where[20205].max == 3, "grid")
  assert(where[20375].tree == 3 and where[20375].row == 2 and where[20375].col == 2, "row step: " .. where[20375].row)
  assert(where[20117].row == 2 and where[20117].col == 1, "extra zero in the position: row " .. where[20117].row)
  assert(where[999] and where[999].row == 1 and where[999].col == 0 and not where[20100], "choice node: the active entry")
  assert(where[20096].icon == 120096, "icon")
  assert(not where[1], "hidden node")
  local p = m.TreePoints(own)
  assert(p[1] == 7 and p[2] == 1 and p[3] == 9, "points")
  assert(m.TalentSummary("Anna-Smith") == "Retribution 7 / 1 / 9", m.TalentSummary("Anna-Smith"))
  -- the first read only goes on the heartbeat; a change is sent to the team
  m.TalentsChanged()
  assert(#SENT == 0, "sent at login")
  local hash = HEARTBEATS.tgt()
  assert(hash and hash:match("^%d+$"), "heartbeat")
  NODES[2].activeRank = 1
  m.TalentsChanged()
  assert(#SENT == 1 and SENT[1].target == nil and SENT[1].text:find("^TGT:%d+#Holy~Protection~Retribution#1%.0%.0%.5%.5%.20257%.120257;"), "change not sent: " .. tostring(SENT[1] and SENT[1].text))
  assert(HEARTBEATS.tgt() ~= hash, "heartbeat hash not updated")
  assert(m.TalentSummary("Anna-Smith") == "Retribution 8 / 1 / 9", "own not read again")
  -- a member asks (whispered back)
  LISTEN.TEAM_MESSAGE("Bob-Stone", "Bob", "TGTQ")
  assert(#SENT == 2 and SENT[2].target == "Bob" and SENT[2].text == SENT[1].text, "TGTQ not answered")
  -- the Talents view: nothing known yet, then a member's talents arrive
  assert(m.TalentsOf("Bob-Stone") == nil, "talents before any arrived")
  m.Open("Bob-Stone")
  local f = m.window
  m.ToggleTalents()
  local panel = m.talentPanel
  assert(m.showTalents and panel and panel:IsShown() and not f.slots[1]:IsShown(), "talents view not shown")
  assert(not MODEL:IsShown(), "model shown over the talents")
  assert(panel.note:GetText():find("No talents known yet", 1, true), "unknown note")
  LISTEN.TEAM_MESSAGE("Bob-Stone", "Bob", SENT[1].text)
  local bob = m.TalentsOf("Bob-Stone")
  assert(bob and #bob.talents == 8 and bob.names[3] == "Retribution", "received talents")
  assert(panel.note:GetText() == "" and panel.buttons[1]:IsShown() and panel.buttons[1].rank:GetText() == "5/5", "not redrawn on arrival")
  assert(panel.heads[3]:GetText():find("^Retribution") and panel.heads[3]:GetText():find("9", 1, true), "tree head")
  assert(rawget(panel.buttons[1], "_point") and f.sub:GetText():find("Retribution 8 / 1 / 9", 1, true), "sub: " .. f.sub:GetText())
  assert(m.M.store.talents["Bob-Stone"].text, "not stored for offline use")
  -- heartbeat: a matching hash asks nothing, another one asks once a minute
  local sent = #SENT
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tgt = SENT[1].text:match("^TGT:(%d+)#") } })
  assert(#SENT == sent, "asked although the hash matches")
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tgt = "12345" } })
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tgt = "12345" } })
  assert(#SENT == sent + 1 and SENT[#SENT].text == "TGTQ" and SENT[#SENT].target == "Bob", "TGTQ not sent once")
  NOW = NOW + 61
  LISTEN.XP_RECEIVED("Bob-Stone", "Bob", { ext = { tgt = "12345" } })
  assert(#SENT == sent + 2, "not asked again after a minute")
  -- stepping keeps the talents view; someone without talents
  m.Open("Cid-Ray")
  assert(m.showTalents and panel.note:GetText():find("No talents known yet", 1, true) and not panel.buttons[1]:IsShown(), "Cid")
  m.ToggleTalents()
  assert(not panel:IsShown() and f.slots[1]:IsShown(), "back to the gear")
  -- garbage is ignored
  LISTEN.TEAM_MESSAGE("Cid-Ray", "Cid", "TGT:1#nonsense")
  assert(m.TalentsOf("Cid-Ray") == nil, "garbage stored")
  LISTEN.TEAM_MESSAGE("Cid-Ray", "Cid", "TGT:x")
  LISTEN.TEAM_MESSAGE("Cid-Ray", "Cid", "TGT:5#a~b~c#9.0.0.1.1.1.1;1.x")
  assert(#m.TalentsOf("Cid-Ray").talents == 0, "bad talents kept")
  -- no trait groups: the three bands of node columns, classic names
  C_Traits.GetGroupDisplayInfoByTreeID = nil
  own = m.ReadOwnTalents()
  p = m.TreePoints(own)
  assert(own and p[1] == 8 and p[2] == 1 and p[3] == 9 and own.names[1] == nil, "bands")
  assert(m.TreeName(own, "PALADIN", 3) == "Retribution", "classic tree name")
  -- Forever: the classic API exists but every rank reads 0 -> the trait tree
  function GetNumTalentTabs() return 3 end
  function GetTalentTabInfo(t) return ({ "Arms", "Fury", "Protection" })[t], 1, 0 end
  function GetNumTalents() return 2 end
  function GetTalentInfo(t, i) return "Zero" .. t .. i, 4000 + i, i, t, 0, 3 end
  own = m.ReadOwnTalents()
  assert(own and own.source == "traits" and m.TreePoints(own)[3] == 9, "classic zeros won over the traits: " .. tostring(own and own.source))
  -- the classic talent API where the client has it (names travel along, cleaned)
  function GetNumTalentTabs() return 3 end
  function GetTalentTabInfo(t) return ({ "Arms", "Fury", "Protection" })[t], 1, 0 end
  function GetNumTalents() return 2 end
  function GetTalentInfo(t, i) return "Deep; Wounds." .. t .. i, 4000 + i, i, t, i == 1 and 2 or 0, 3 end
  own = m.ReadOwnTalents()
  assert(own.source == "classic" and #own.talents == 6 and own.talents[1].name == "Deep Wounds11", "classic: " .. tostring(own.talents[1].name))
  local back = m.ParseTalents(m.TalentText(own))
  local t21
  for _, t in ipairs(back.talents) do if t.name == "Deep Wounds21" then t21 = t end end
  assert(back.names[2] == "Fury" and t21 and t21.rank == 2 and t21.tree == 2 and t21.row == 0 and t21.col == 1, "classic round trip")
  local n = 0
  m.M.Report(m.M, function(line) if line:find("talents: own=", 1, true) then n = n + 1 end end)
  assert(n == 1, "no talents line in the report")
  return "team gear talents ok"
end''')(mod))
