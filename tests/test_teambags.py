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
  if k == "SetColorTexture" then return function(self, r, g, b, a) rawset(self, "_color", { r, g, b, a }) end end
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
STUBFRAME = new
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
  -- 14th value: bind type (ITEMS[id][4]: 1 Bind on Pickup, 2 Bind on Equip, 4 quest item)
  GetItemInfo = function(id) local i = ITEMS[id] if i then return i[1], "|Hitem:" .. id .. "|h[" .. i[1] .. "]|h", i[2], nil, nil, nil, nil, nil, nil, 1000 + id, nil, nil, nil, i[4] end end,
  GetItemInfoInstant = function(id) local i = ITEMS[id] return id, nil, nil, nil, 1000 + id, i and i[3], 0 end,
  GetItemQualityColor = function() return 0.1, 1, 0 end,
}
C_Container = {}
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
MMT = { CopyTable = copy, ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }, status = {},
  UI = setmetatable({ ACCENT = { 0.3, 0.7, 1 } }, { __index = function() return function() return new() end end }) }
function MMT.UI.OpenList(owner, items, current, onPick) LIST = { items = items, pick = onPick } end
function MMT.UI.Button(parent, w, text, onClick) local b = new(); b.label = new(); b._click = onClick; return b end
function MMT.UI.TextButton(parent, text, onClick) local b = new(); b.label = new(); rawset(b, "_OnClick", onClick); return b end
function MMT.UI.EditBox() local e = new(); return e end
function MMT.IsSecret() return false end
function MMT.Safe(fn, ...) local r = { pcall(fn, ...) } if r[1] then return select(2, unpack(r)) end end
function MMT.PlayerFull() return "Anna-Smith" end
function MMT.IsSelf(k) return k == "Anna-Smith" end
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone" } end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.ApplyFont(fs) end
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

# planned gifts: by character, drag Anna's Linen Cloth onto Bob's section
print(lua.eval(r'''function(m)
  SENT = {}
  function MMT.SendToTeam(msg) SENT[#SENT + 1] = msg end
  function IsShiftKeyDown() return SHIFT end
  GameTooltip = STUBFRAME()
  rawset(UIParent, "GetEffectiveScale", function() return 1 end)
  local f = m.bags
  rawset(f, "GetLeft", function() return 0 end)
  rawset(f, "GetRight", function() return 400 end)
  rawset(f, "GetTop", function() return 500 end)
  rawset(f, "GetEffectiveScale", function() return 1 end)
  local function Section(key) for _, b in ipairs(f.bands) do if b.key == key then return b end end end
  local function Over(key)   -- the cursor over that character's section
    local b = Section(key)
    function GetCursorPosition() return 10, 500 + (b.top + b.bottom) / 2 end
  end
  local function Button(owner, id, planned)
    for _, b in ipairs(f.slots) do
      local s = rawget(b, "slot")
      if b:IsShown() and s and s.owner == owner and s.id == id and (s.planned ~= nil) == (planned or false) and not s.outgoing then return b, s end
    end
  end
  f:Hide()
  m.OpenBags("b", "__BYCHAR__")
  assert(Section("Anna-Smith") and Section("Bob-Stone"), "no drop zones")
  local b = Button("Anna-Smith", 2589)
  assert(b, "Anna's linen not shown")
  Over("Bob-Stone")
  b._OnDragStart(b)
  b._OnDragStop(b)
  assert(SENT[1] == "TIVG:2589:20:" .. m.Gives()["Anna-Smith"]["Bob-Stone"][2589].t .. ":Anna-Smith:Bob-Stone", "plan message: " .. tostring(SENT[1]))
  -- the icon moved: glowing first in Bob's section with "Anna" on it; at Anna dimmed with "Bob"
  assert(not Button("Anna-Smith", 2589), "still in Anna's bags")
  local pb, ps = Button("Bob-Stone", 2589, true)
  assert(pb and ps.count == 20 and ps.planned == "Anna-Smith" and pb.glow:IsShown(), "not glowing at Bob")
  assert(pb.tag:GetText():find("Anna", 1, true), "giver's name not on the icon")
  local ob, os_
  for _, x in ipairs(f.slots) do local s = rawget(x, "slot") if x:IsShown() and s and s.outgoing then ob, os_ = x, s end end
  assert(os_ and os_.owner == "Anna-Smith" and os_.outgoing == "Bob-Stone" and os_.count == 20, "no dimmed slot at Anna")
  assert(ob.tag:GetText():find("Bob", 1, true) and not ob.glow:IsShown(), "receiver's name / glow at Anna")
  -- dimmed: the slot colour too, not only the icon (the quality colour shone through)
  assert(ob.bg._color[1] < 0.1 and ob.bg._color[2] < 0.1, "outgoing slot colour not dimmed")
  assert(pb.bg._color[1] >= 0.2, "incoming slot dimmed")
  -- who trades whom: in the side panel
  local pr = f.pairRows[1]
  assert(pr and pr:IsShown() and pr.label:GetText():find("Anna", 1, true) and pr.label:GetText():find("Bob", 1, true), "trade in the panel")
  assert(pr.icons[1]:IsShown() and pr.icons[1].id == 2589 and pr.icons[1].n == 20, "trade item icon")
  local heads = {}
  for _, h in ipairs(f.headers) do if h:IsShown() then heads[#heads + 1] = h:GetText() end end
  assert(not heads[1]:find("Trades", 1, true), "trades still in the main view")
  -- dragging the dimmed one does nothing; right-clicking it cancels too
  ob._OnDragStart(ob)
  assert(not rawget(ob, "dragging"), "dragged an outgoing gift")
  local first
  for _, x in ipairs(f.slots) do if rawget(x, "slot") and x.slot.owner == "Bob-Stone" then first = x.slot break end end
  assert(first.planned, "planned gift not first in Bob's section")
  ob._OnClick(ob, "RightButton")
  assert(not Button("Bob-Stone", 2589, true), "right-click on the giver's side didn't cancel")
  b = Button("Anna-Smith", 2589)
  b._OnDragStart(b); b._OnDragStop(b)
  pb = Button("Bob-Stone", 2589, true)
  -- the whole team added up doesn't change
  local slots = m.BagSlots("__ALL__", "b", "")
  for _, s in ipairs(slots) do if s.id == 2589 then assert(s.count == 20, "whole team count changed") end end
  -- right-click cancels it: back at Anna, no glow left
  pb._OnClick(pb, "RightButton")
  assert(Button("Anna-Smith", 2589) and not Button("Bob-Stone", 2589, true), "not cancelled")
  assert(not f.pairRows[1]:IsShown() and f.team.empty:IsShown(), "trade left over in the panel")
  for _, x in ipairs(f.slots) do if x:IsShown() then assert(not x.glow:IsShown(), "glow left over") end end
  -- Shift + drop: how many
  SHIFT = true
  b = Button("Anna-Smith", 2589)
  b._OnDragStart(b); b._OnDragStop(b)
  SHIFT = false
  local box = MMTTeamBagsAmount
  assert(box and box.accept, "no amount box")
  box.accept("5")
  local _, rest = Button("Anna-Smith", 2589)
  local _, gift = Button("Bob-Stone", 2589, true)
  assert(rest.count == 15 and gift.count == 5, "split gift")
  -- dropped on her own section, or outside the window: nothing
  local n = #SENT
  b = Button("Anna-Smith", 2589)
  Over("Anna-Smith"); b._OnDragStart(b); b._OnDragStop(b)
  function GetCursorPosition() return 900, 100 end
  b._OnDragStart(b); b._OnDragStop(b)
  assert(#SENT == n, "a drop on the own section / outside planned something")
  -- the team list beside the window: every member, always there
  m.SetGive("Anna-Smith", "Bob-Stone", 2589, 0)
  m.OpenBags("b", "Anna-Smith")
  local names = {}
  for _, tb in ipairs(f.teamButtons) do if tb:IsShown() then names[#names + 1] = tb.key end end
  assert(table.concat(names, ",") == "Anna-Smith,Bob-Stone", "team list: " .. table.concat(names, ","))
  -- one character's view: drag onto a name in the list
  local bobButton = f.teamButtons[2]
  rawset(bobButton, "IsMouseOver", function() return true end)
  b = Button("Anna-Smith", 2589)
  b._OnDragStart(b)
  assert(rawget(b, "dragging"), "can't drag in a single character's view")
  b._OnDragStop(b)
  rawset(bobButton, "IsMouseOver", nil)
  assert(m.PlannedOut("Anna-Smith", 2589) == 20, "drop on a name (the whole stack): " .. m.PlannedOut("Anna-Smith", 2589))
  assert(bobButton.label:GetText():find("+1", 1, true), "incoming count on the name: " .. tostring(bobButton.label:GetText()))
  -- the bank isn't tradeable: no dragging there
  m.OpenBags("k", "Anna-Smith")
  for _, x in ipairs(f.slots) do
    local s = rawget(x, "slot")
    if x:IsShown() and s then x._OnDragStart(x); assert(not rawget(x, "dragging"), "dragging from the bank") end
  end
  -- clicking a name shows that character
  m.OpenBags("b", "Anna-Smith")
  bobButton._click(bobButton)
  assert(f.who == "Bob-Stone", "name click didn't switch")
  assert(bobButton.label:GetText():find(">", 1, true), "current character not marked")
  -- the trades are in the panel in every view: here one character's bags
  m.SetGive("Anna-Smith", "Bob-Stone", 13446, 2)
  m.OpenBags("b", "Anna-Smith")
  pr = f.pairRows[1]
  assert(pr:IsShown() and pr.from == "Anna-Smith" and pr.to == "Bob-Stone", "trade not in the panel of a single view")
  assert(pr.icons[2]:IsShown() and pr.icons[2].id == 13446, "second item")
  -- right-click one item icon: only that one
  pr.icons[2]._OnClick(pr.icons[2], "RightButton")
  assert(m.PlannedOut("Anna-Smith", 13446) == 0 and m.PlannedOut("Anna-Smith", 2589) == 20, "item cancel")
  -- "Trade": Anna is the giver, so this client opens it with Bob
  function MMT.Resolve(n) if n == "Bob" then return "Bob-Stone" end end
  function MMT.SplitUnit(u) if u == "party1" then return "Bob", "Stone", "Bob-Stone" end end
  function InitiateTrade(u) TRADED = u end
  pr.trade._click(pr.trade)
  assert(TRADED == "party1", "trade not opened: " .. tostring(TRADED))
  -- the "x" cancels the whole trade
  m.SetGive("Anna-Smith", "Bob-Stone", 13446, 2)
  pr.cancel._OnClick(pr.cancel)
  assert(m.PlannedOut("Anna-Smith", 2589) == 0 and m.PlannedOut("Anna-Smith", 13446) == 0, "x didn't cancel the pair")
  assert(not f.pairRows[1]:IsShown(), "trade left over")
  -- the panel flips to the left at the right edge of the screen, also while the window moves
  rawset(UIParent, "GetRight", function() return 1000 end)
  rawset(f, "GetRight", function() return 500 end)
  m.PlaceTeam(f)
  assert(f.team:GetPoint(1) == "TOPLEFT", "panel not on the right")
  rawset(f, "GetRight", function() return 950 end)
  f._OnDragStart(f)
  f._OnUpdate(f)
  assert(f.team:GetPoint(1) == "TOPRIGHT", "panel didn't flip while moving")
  f._OnDragStop(f)
  rawset(f, "GetRight", function() return 500 end)
  m.PlaceTeam(f)
  assert(f.team:GetPoint(1) == "TOPLEFT", "panel didn't flip back")
  return "planned gifts in the team bags ok"
end''')(mod))

# bug: buying from a vendor with the window open didn't show until it was reopened
print(lua.eval(r'''function(m)
  local f = m.bags
  f:Hide()
  m.OpenBags("b", "Anna-Smith")
  local function Has(id)
    for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if b:IsShown() and s and s.id == id then return s.count end end
  end
  assert(not Has(13446 + 1), "test item already there")
  ITEMS[13447] = { "Bought Thing", 1, 0 }
  -- the bag now holds what Anna had plus the new item
  local bag = {}
  for id, n in pairs(m.Chars()["Anna-Smith"].b) do bag[#bag + 1] = { itemID = id, stackCount = n } end
  bag[#bag + 1] = { itemID = 13447, stackCount = 3 }
  C_Container.GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return b == 0 and bag[s] or nil end
  assert(m.ScanAll(), "scan saw no change")
  assert(Has(13447) == 3, "the open window didn't show the new item")
  return "open window updates on bag changes ok"
end''')(mod))

# bug: dragging in "Whole team" planned a gift from "__ALL__"; now from whoever has it
print(lua.eval(r'''function(m)
  local f = m.bags
  local chars = m.Chars()
  for from in pairs(m.Gives()) do m.Gives()[from] = nil end
  chars["Cara-Sun"] = { b = { [13446] = 1 }, k = {}, m = {}, e = {} }
  f:Hide()
  m.OpenBags("b", "__ALL__")
  local function Slot(id)
    for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if b:IsShown() and s and s.id == id then return b, s end end
  end
  local bob
  for _, tb in ipairs(f.teamButtons) do if tb.key == "Bob-Stone" then bob = tb end end
  rawset(bob, "IsMouseOver", function() return true end)
  -- only Anna has Linen Cloth in her bags: it comes from her
  local b, s = Slot(2589)
  assert(s and s.owner == nil, "whole team slot has an owner")
  b._OnDragStart(b)
  assert(rawget(b, "dragging"), "can't drag in the whole team view")
  b._OnDragStop(b)
  assert(m.PlannedOut("Anna-Smith", 2589) == 20 and m.Gives()["__ALL__"] == nil, "not planned from Anna")
  -- potions: Anna (5) and Cara (1) could give them to Bob: ask who
  LIST = nil
  b = Slot(13446)
  b._OnDragStart(b); b._OnDragStop(b)
  assert(LIST and LIST.items[1].header and #LIST.items == 3, "no 'who gives it' list")
  assert(LIST.items[2].value == "Anna-Smith" and LIST.items[2].text:find("(5)", 1, true) and LIST.items[3].value == "Cara-Sun", "holders")
  LIST.pick("Cara-Sun")
  assert(m.PlannedOut("Cara-Sun", 13446) == 1 and m.PlannedOut("Anna-Smith", 13446) == 0, "not from the chosen one")
  rawset(bob, "IsMouseOver", nil)
  -- a gift from / to a view is refused
  m.SetGive("__ALL__", "Bob-Stone", 2589, 3)
  m.SetGive("Anna-Smith", "__BYCHAR__", 2589, 3)
  assert(m.Gives()["__ALL__"] == nil and (m.Gives()["Anna-Smith"]["__BYCHAR__"] == nil), "view stored as a character")
  m.SetGive("Anna-Smith", "Bob-Stone", 2589, 0)
  m.SetGive("Cara-Sun", "Bob-Stone", 13446, 0)
  chars["Cara-Sun"] = nil
  return "drag from the whole team view ok"
end''')(mod))

# soulbound items can't be given: Bind on Pickup (Hearthstone), a Bind on Equip one
# that was equipped (the owner's client sends how many are bound), part of a stack
print(lua.eval(r'''function(m)
  local f = m.bags
  ITEMS[6948][4] = 1      -- Hearthstone: Bind on Pickup
  ITEMS[5000][4] = 2      -- Sword: Bind on Equip
  local anna = m.Chars()["Anna-Smith"]
  anna.s = { [5000] = 1, [13446] = 2 }   -- her sword was equipped once, 2 of 5 potions are soulbound
  for from in pairs(m.Gives()) do m.Gives()[from] = nil end
  LINES = {}
  GameTooltip = setmetatable({ AddLine = function(_, t) LINES[#LINES + 1] = t end }, { __index = function() return function() end end })
  f:Hide()
  m.OpenBags("b", "Anna-Smith")
  local function Slot(id)
    for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if b:IsShown() and s and s.id == id and not s.planned and not s.outgoing then return b, s end end
  end
  local bob
  for _, tb in ipairs(f.teamButtons) do if tb.key == "Bob-Stone" then bob = tb end end
  rawset(bob, "IsMouseOver", function() return true end)
  local function Tip(b) LINES = {}; b._OnEnter(b); return table.concat(LINES, " | ") end
  for _, id in ipairs({ 6948, 5000 }) do
    local b = Slot(id)
    b._OnDragStart(b)
    assert(not rawget(b, "dragging"), "dragged soulbound item " .. id)
    assert(Tip(b):find("can't be traded", 1, true), "no soulbound line for " .. id .. ": " .. Tip(b))
  end
  -- potions: only the 3 that aren't soulbound
  local b = Slot(13446)
  assert(Tip(b):find("only 3 can be given", 1, true), "partial line: " .. Tip(b))
  b._OnDragStart(b); b._OnDragStop(b)
  assert(m.PlannedOut("Anna-Smith", 13446) == 3, "gave soulbound potions: " .. m.PlannedOut("Anna-Smith", 13446))
  -- all tradeable ones promised: nothing more to drag
  b = Slot(13446)
  b._OnDragStart(b)
  assert(not rawget(b, "dragging"), "dragged potions already promised")
  -- whole team: the hearthstone can't be dragged there either
  m.OpenBags("b", "__ALL__")
  b = Slot(6948)
  b._OnDragStart(b)
  assert(not rawget(b, "dragging") and Tip(b):find("can't be traded", 1, true), "hearthstone in the whole team view")
  rawset(bob, "IsMouseOver", nil)
  m.SetGive("Anna-Smith", "Bob-Stone", 13446, 0)
  anna.s = nil
  return "soulbound items ok"
end''')(mod))

# the team / trades panel can be switched off in the settings
print(lua.eval(r'''function(m)
  local f = m.bags
  f:Hide()
  m.OpenBags("b", "Anna-Smith")
  assert(f.team:IsShown(), "panel not shown by default")
  m.M.db.sidePanel = false
  m.RefreshBags()
  assert(not f.team:IsShown(), "panel shown while switched off")
  -- a drop can't land on the hidden names
  local bob
  for _, tb in ipairs(f.teamButtons) do if tb.key == "Bob-Stone" then bob = tb end end
  rawset(bob, "IsMouseOver", function() return true end)
  local b
  for _, x in ipairs(f.slots) do local s = rawget(x, "slot") if x:IsShown() and s and s.id == 2589 then b = x end end
  b._OnDragStart(b); b._OnDragStop(b)
  assert(m.PlannedOut("Anna-Smith", 2589) == 0, "dropped on a hidden name")
  rawset(bob, "IsMouseOver", nil)
  m.M.db.sidePanel = true
  m.RefreshBags()
  assert(f.team:IsShown(), "panel not back")
  return "side panel setting ok"
end''')(mod))

# filter: hide / only BoE gear and soulbound items
print(lua.eval(r'''function(m)
  local f = m.bags
  ITEMS[6948][4] = 1      -- Hearthstone: Bind on Pickup -> soulbound
  ITEMS[5000][4] = 2      -- Sword (weapon): Bind on Equip -> BoE gear
  local anna = m.Chars()["Anna-Smith"]
  anna.s = { [13446] = 5 }   -- all 5 potions soulbound
  for from in pairs(m.Gives()) do m.Gives()[from] = nil end
  f:Hide()
  m.OpenBags("b", "Anna-Smith")
  local function Ids()
    local t = {}
    for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if b:IsShown() and s then t[#t + 1] = s.id end end
    table.sort(t)
    return table.concat(t, ",")
  end
  local all = Ids()
  local function Pick(v) f.filter._click(f.filter); LIST.pick(v) end
  Pick("NOBOE")
  assert(not Ids():find("5000", 1, true) and Ids():find("6948", 1, true), "hide BoE: " .. Ids())
  Pick("BOE")
  assert(Ids() == "5000", "only BoE: " .. Ids())
  Pick("NOBOUND")
  assert(not Ids():find("6948", 1, true) and not Ids():find("13446", 1, true) and Ids():find("5000", 1, true), "hide soulbound: " .. Ids())
  Pick("BOUND")
  assert(Ids() == "6948,13446", "only soulbound: " .. Ids())
  Pick("NOBOTH")
  assert(not Ids():find("5000", 1, true) and not Ids():find("6948", 1, true) and Ids():find("2589", 1, true), "hide both: " .. Ids())
  assert(f.filter.label:GetText():find("Hide both", 1, true), "filter label")
  -- equipped: a BoE sword there is bound
  anna.e = { [5000] = 1 }
  m.OpenBags("e", "Anna-Smith")
  Pick("BOUND")
  assert(Ids() == "5000", "equipped BoE counts as soulbound: " .. Ids())
  -- planned gifts stay visible whatever the filter
  m.OpenBags("b", "Anna-Smith")
  Pick("BOE")
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 3)
  local planned = false
  for _, b in ipairs(f.slots) do local s = rawget(b, "slot") if b:IsShown() and s and s.planned then planned = true end end
  assert(planned, "planned gift hidden by the filter")
  m.SetGive("Bob-Stone", "Anna-Smith", 2589, 0)
  Pick("ALL")
  assert(Ids() == all, "all items again")
  anna.s, anna.e = nil, {}
  return "filter ok"
end''')(mod))
