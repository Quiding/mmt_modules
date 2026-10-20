"""MMT_TeamInventory/Bags.lua: the team bags window (stand-in frames):
categories in Baganator's Classic order, junk last, search, whole team,
bank / mail notes, scrolling, and the minimap button."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local U = {}
local function new() return setmetatable({}, U) end
U.__index = function(t, k)
  if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
  if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
  if k == "SetTexture" then return function(self, v) rawset(self, "_tex", v) end end
  if k == "Show" then return function(self) rawset(self, "_shown", true) end end
  if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
  if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
  if k == "SetPoint" then return function(self, ...) rawset(self, "_point", { ... }) end end
  if k == "ClearAllPoints" then return function(self) rawset(self, "_point", nil) end end
  if k == "GetPoint" then return function(self) local p = rawget(self, "_point") if p then return unpack(p) end end end
  if k == "SetSize" then return function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end end
  if k == "SetScript" or k == "HookScript" then return function(self, ev, fn) rawset(self, "_" .. ev, fn) end end
  if k == "GetWidth" then return function() return 140 end end
  if k == "GetFrameLevel" then return function() return 1 end end
  return function() return new() end
end
function CreateFrame(_, name) local f = new(); if name then _G[name] = f end return f end
UIParent, Minimap = new(), new()
C_Timer = { After = function(_, f) f() end }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
GetTime = function() return 0 end
function IsLoggedIn() return true end
function UnitClass() return "Shaman", "SHAMAN" end
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
Enum = { BagIndex = { Backpack = 0 } }
SlashCmdList = {}
-- id = { name, quality, classID }
ITEMS = { [6948] = { "Hearthstone", 1, 15 }, [13446] = { "Major Healing Potion", 1, 0 }, [2589] = { "Linen Cloth", 1, 7 },
  [5000] = { "Sword", 2, 2 }, [7073] = { "Broken Fang", 0, 15 }, [9999] = { "Quest Thing", 1, 12 } }
C_Item = {
  GetItemInfo = function(id) local i = ITEMS[id] if i then return i[1], "|Hitem:" .. id .. "|h[" .. i[1] .. "]|h", i[2], nil, nil, nil, nil, nil, nil, 1000 + id end end,
  GetItemInfoInstant = function(id) local i = ITEMS[id] return id, nil, nil, nil, 1000 + id, i and i[3], 0 end,
  GetItemQualityColor = function() return 0.1, 1, 0 end,
}
C_Container = {}
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
MMT = { CopyTable = copy, ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }, status = {},
  UI = setmetatable({ ACCENT = { 0.3, 0.7, 1 } }, { __index = function() return function() return new() end end }) }
function MMT.UI.OpenList(owner, items, current, onPick) LIST = { items = items, pick = onPick } end
function MMT.UI.Button(parent, w, text, onClick) local b = new(); b.label = new(); b._click = onClick; return b end
function MMT.UI.EditBox() local e = new(); return e end
function MMT.IsSecret() return false end
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
function MMT.PlayerFull() return "Anna-Smith" end
function MMT.IsSelf(k) return k == "Anna-Smith" end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone" } end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Ago() return "1 min ago" end
function MMT.Print() end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On(ev, fn) EVENTS = EVENTS or {}; EVENTS[ev] = fn end
  function M:Listen() end
  function M:Heartbeat() end
  return M
end
''')
mod = lua.eval('{}')
for f in [l.strip() for l in open('MMT_TeamInventory/MMT_TeamInventory.toc', encoding='utf-8') if l.strip().endswith('.lua')]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open('MMT_TeamInventory/' + f, encoding='utf-8').read(), f, mod)

print(lua.eval(r'''function(m)
  local chars = m.Chars()
  chars["Anna-Smith"] = { b = { [6948] = 1, [13446] = 5, [2589] = 20, [5000] = 1, [7073] = 3, [9999] = 1 }, k = {}, m = {}, e = {} }
  chars["Bob-Stone"] = { b = { [13446] = 2 }, k = { [2589] = 40 }, m = {}, e = {}, time = 100, class = "SHAMAN" }
  -- categories in Baganator's Classic order, junk last
  local groups = m.Group(m.BagSlots("Anna-Smith", "b", ""))
  local names = {}
  for _, g in ipairs(groups) do names[#names + 1] = g.id end
  assert(table.concat(names, ",") == "hearth,consumable,quest,weapon,tradegoods,junk", table.concat(names, ","))
  -- the window: headers and slots
  m.SetupMinimap()
  assert(m.minimap and m.minimap:IsShown(), "no minimap button")
  m.minimap._OnClick(m.minimap, "LeftButton")
  local f = m.bags
  assert(f and f:IsShown() and f.place == "b" and f.who == "Anna-Smith" and f:GetPoint(1), "bags window")
  local heads = {}
  for _, h in ipairs(f.headers) do if h:IsShown() then heads[#heads + 1] = h:GetText():match("^(.-)  ") end end
  assert(table.concat(heads, ",") == "Hearthstone,Consumables,Quest items,Weapons,Trade goods,Junk", table.concat(heads, ","))
  local shown = 0
  for _, b in ipairs(f.slots) do if b:IsShown() and rawget(b, "slot") then shown = shown + 1 end end
  assert(shown == 6, "slots " .. shown)
  -- flat grid
  m.M.db.categories = false
  m.RefreshBags()
  heads = 0
  for _, h in ipairs(f.headers) do if h:IsShown() then heads = heads + 1 end end
  assert(heads == 0, "headers in the flat grid")
  m.M.db.categories = true
  -- search
  f.search:SetText("cloth")
  m.RefreshBags()
  shown = 0
  for _, b in ipairs(f.slots) do if b:IsShown() and rawget(b, "slot") then shown = shown + 1 end end
  assert(shown == 1, "search")
  f.search:SetText("")
  -- right-click: bank; Anna never opened hers
  m.minimap._OnClick(m.minimap, "RightButton")
  assert(f.place == "k" and f.info:GetText():find("open the bank", 1, true), "bank note: " .. f.info:GetText())
  -- whole team: everyone's added up
  f.who = "__ALL__"
  m.RefreshBags()
  assert(rawget(f.slots[1], "slot") and f.slots[1].slot.count == 40, "whole team bank")
  m.OpenBags("b", "__ALL__")
  local potion
  for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if s and s.id == 13446 then potion = s.count end end
  assert(potion == 7, "whole team bags: " .. tostring(potion))
  -- the character picker
  f.owner._click(f.owner)
  assert(LIST.items[1].value == "__ALL__" and LIST.items[2].value == "__BYCHAR__" and LIST.items[3].value == "Anna-Smith" and LIST.items[4].value == "Bob-Stone", "picker")
  -- by character: a section per character, their items in category order
  LIST.pick("__BYCHAR__")
  local heads = {}
  for _, h in ipairs(f.headers) do if h:IsShown() then heads[#heads + 1] = h:GetText() end end
  assert(#heads == 2 and heads[1]:find("Anna Smith", 1, true) and heads[2]:find("Bob Stone", 1, true), table.concat(heads, " / "))
  assert(f.slots[1].slot.id == 6948, "Anna's first slot isn't the hearthstone (category order)")
  assert(f.info:GetText():find("^7 different", 1, false) or f.info:GetText():find("different items", 1, true), "footer")
  LIST.pick("Bob-Stone")
  assert(f.who == "Bob-Stone" and f.info:GetText():find("updated", 1, true), "Bob")
  -- the cog opens the settings
  MMT.ToggleConfig = function(name) CONFIG = name end
  f.cog._OnClick(f.cog)
  assert(CONFIG == "TeamInventory", "cog")
  -- the same view again closes it
  m.OpenBags("b", "Bob-Stone")
  assert(not f:IsShown(), "toggle")
  -- lots of items: scrolls by line
  for id = 20000, 20200 do ITEMS[id] = { "Thing " .. id, 1, 15 }; chars["Anna-Smith"].b[id] = 1 end
  m.OpenBags("b", "Anna-Smith")
  local h1 = f._h
  f._OnMouseWheel(f, -1)
  assert(f.offset == 1 and f._h <= 768, "scroll: offset " .. tostring(f.offset) .. " height " .. tostring(f._h) .. " was " .. tostring(h1))
  -- few items: the window fits them, no scrolling
  m.OpenBags("b", "Bob-Stone")
  f._OnMouseWheel(f, -1)
  assert(f.offset == 0 and not f.info:GetText():find("scrolls", 1, true), "scrolls with few items")
  -- "Open on": the last one viewed (remembered), this character, the whole team, by character
  f:Hide()
  m.M.db.lastWho = "Bob-Stone"
  m.OpenBags("b")
  assert(f.who == "Bob-Stone", "open on last viewed: " .. tostring(f.who))
  f:Hide()
  m.M.db.openOn = "SELF"; m.OpenBags("b")
  assert(f.who == "Anna-Smith", "open on this character")
  f:Hide()
  m.M.db.openOn = "ALL"; m.OpenBags("b")
  assert(f.who == "__ALL__", "open on whole team")
  f:Hide()
  m.M.db.openOn = "BYCHAR"; m.OpenBags("b")
  assert(f.who == "__BYCHAR__", "open on by character")
  f:Hide()
  m.M.db.openOn = "LAST"; m.M.db.lastWho = "Gone-Char"; m.OpenBags("b")
  assert(f.who == "Anna-Smith", "a last one that's gone: this character")
  -- open: bags -> bank keeps the character
  f.who = "Bob-Stone"
  m.OpenBags("k")
  assert(f.who == "Bob-Stone" and f.place == "k", "switching to the bank changed the character")
  f:Hide()
  -- key bindings: toggle the window
  assert(BINDING_HEADER_MMTTEAMINV and BINDING_NAME_MMTTEAMINV_BANK, "binding names")
  MMTTeamInventory_Toggle("k")
  assert(f:IsShown() and f.place == "k", "bank key")
  MMTTeamInventory_Toggle("k")
  assert(not f:IsShown(), "bank key again closes")
  MMTTeamInventory_Toggle("b", "__BYCHAR__")
  assert(f:IsShown() and f.who == "__BYCHAR__", "by-character key")
  -- minimap off
  m.M.db.minimap = false
  m.SetupMinimap()
  assert(not m.minimap:IsShown(), "minimap button not hidden")
  return "team bags ok"
end''')(mod))

# Baganator on: its order, custom categories, priorities, dragged items and hidden ones
print(lua.eval(r'''function(m)
  local CLASSES = { [0] = "Consumable", [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods", [12] = "Quest", [15] = "Miscellaneous" }
  C_Item.GetItemClassInfo = function(c) return CLASSES[c] end
  C_Item.GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end
  Enum.ItemClass = { Consumable = 0, Weapon = 2, Armor = 4, Tradegoods = 7, Questitem = 12, Miscellaneous = 15 }
  -- a tiny stand-in for Syndicator's search: "#class", "name", "&" and "!" are enough here
  local function One(d, term)
    local neg = term:sub(1, 1) == "!"
    if neg then term = term:sub(2) end
    local i = ITEMS[d.itemID]
    local r
    if term:sub(1, 1) == "#" then
      local k = term:sub(2)
      r = (CLASSES[i[3]] or ""):lower() == k or (k == "junk" and i[2] == 0) or (k == "gear" and (i[3] == 2 or i[3] == 4))
        or (k == "potion" and i[1]:lower():find("potion", 1, true) ~= nil)
        or ((k == "unique" or k == "soulbound") and d.itemID == 6948)
    else
      r = i[1]:lower():find(term, 1, true) ~= nil
    end
    if neg then r = not r end
    return r
  end
  Syndicator = { Locales = { KEYWORD_REAGENT = "reagent", KEYWORD_GEAR = "gear", KEYWORD_JUNK = "junk", KEYWORD_KEY = "key" },
    Search = {
      GetBaseInfo = function(c) return { itemID = c.itemID, itemLink = c.itemLink } end,
      CheckItem = function(d, search)
        for part in search:gmatch("[^&]+") do if not One(d, part) then return false end end
        return true
      end,
    } }
  Baganator = {}
  BAGANATOR_CURRENT_PROFILE = "DEFAULT"
  BAGANATOR_CONFIG = { Profiles = { DEFAULT = {
    category_display_order = { "default_auto_recents", "----", "default_hearthstone", "custom_potions", "default_consumable",
      "default_questitem", "_1", "default_weapon", "default_armor", "__end", "default_tradegoods", "default_miscellaneous",
      "default_other", "----", "default_junk", "default_special_empty" },
    custom_categories = { custom_potions = { name = "Potions", search = "#Potion" } },
    category_modifications = { custom_potions = { priority = 1 }, default_weapon = { addedItems = { ["i:2589"] = true } } },
    category_hidden = {},
  } } }
  local chars = m.Chars()
  for id in pairs(chars["Anna-Smith"].b) do if id >= 20000 then chars["Anna-Smith"].b[id] = nil end end
  local function Names(groups) local t = {} for _, g in ipairs(groups) do t[#t + 1] = g.name .. "=" .. #g.slots end return table.concat(t, ",") end
  local groups, fromBaganator = m.Categorize(m.BagSlots("Anna-Smith", "b", ""))
  assert(fromBaganator, "Baganator's categories not used")
  -- the potion goes to the higher-priority custom category, the cloth was dragged into Weapons
  assert(Names(groups) == "Hearthstone=1,Potions=1,Quest=1,Weapon=2,Junk=1", Names(groups))
  -- a change in Baganator shows at once: hide Weapons, drop the custom category
  BAGANATOR_CONFIG.Profiles.DEFAULT.category_hidden = { default_weapon = true }
  BAGANATOR_CONFIG.Profiles.DEFAULT.custom_categories = {}
  groups = m.Categorize(m.BagSlots("Anna-Smith", "b", ""))
  assert(Names(groups) == "Hearthstone=1,Consumable=1,Quest=1,Junk=1", Names(groups))
  -- switched off, or Baganator's data missing: the built-in categories
  m.M.db.baganatorCats = false
  local _, b = m.Categorize(m.BagSlots("Anna-Smith", "b", ""))
  assert(b == false, "setting ignored")
  m.M.db.baganatorCats = true
  BAGANATOR_CONFIG = nil
  _, b = m.Categorize(m.BagSlots("Anna-Smith", "b", ""))
  assert(b == false, "no fallback without Baganator's data")
  return "Baganator categories ok"
end''')(mod))
