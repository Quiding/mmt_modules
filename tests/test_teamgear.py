"""MMT_TeamGear: member list, reading Item Compare's stored gear, the gear
window (stand-in frames), stepping through members, the character panel button."""
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
EVENTS, LISTEN = {}, {}
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
function MMT.Print(...) PRINTED = string.format(...) end
function MMT.ToggleConfig() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:Heartbeat(k, fn) HEARTBEAT = { k = k, fn = fn } end
  function M:On(ev, fn) EVENTS[ev] = fn end
  function M:Listen(ev, fn) LISTEN[ev] = fn end
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
  assert(HEARTBEAT.k == "tgl" and HEARTBEAT.fn() == "2.3", "heartbeat " .. tostring(HEARTBEAT.fn()))
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
