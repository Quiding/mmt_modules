"""MMT_QoL MailList.lua: a role's item list docked beside the bags (MMT's role rules,
what "Mail to team" mails).
Stand-ins for MMT's roles (AddRule / RemoveRule / DescribeRule / HasRole), the bag
frames (Baganator's backpack window named after its skin, the game's bags) and
just enough of a frame to build and draw the panel: adding by ID / link / name,
duplicates refused, removing, the role falling back to the first, who it is mailed
to, docking beside the open bags (on the side with room), folding away, off."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
LISTEN, EVENTS, PRINTS, TICKERS, TIME = {}, {}, {}, {}, 0
SlashCmdList = {}
LOADED = { Baganator = true }
function GetTime() return TIME end

-- a frame: shown state, its points, size; anything else does nothing
Frame = {}
Frame.__index = function(t, k)
  local v = rawget(Frame, k)
  if v ~= nil then return v end
  return function() end
end
function Frame.new(name, parent)
  local f = setmetatable({ shown = true, scripts = {}, points = {}, w = 0, h = 0, name = name, parent = parent }, Frame)
  if name then _G[name] = f end
  return f
end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) self.shown = v and true or false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() local p = rawget(self, "parent"); return self.shown and (not p or p == UIParent or p:IsVisible()) end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn) self.scripts[k] = fn end
function Frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetLeft() return rawget(self, "left") end
function Frame:GetName() return self.name end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:GetFrameLevel() return 5 end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text or "" end
function Frame:CreateTexture() return Frame.new() end
function Frame:CreateFontString() return Frame.new() end
function CreateFrame(_, name, parent) return Frame.new(name, parent) end
UIParent = Frame.new("UIParent")
GameTooltip = Frame.new("GameTooltip")

CURSOR = nil
function GetCursorInfo() if CURSOR then return "item", CURSOR end end
function ClearCursor() CURSOR = nil end

C_Timer = { After = function(_, fn) fn() end,
  NewTicker = function(_, fn) TICKERS[#TICKERS + 1] = fn; return { Cancel = function() TICKERS = {} end } end }
function TICK() for _, fn in ipairs(TICKERS) do fn() end end
C_AddOns = {
  IsAddOnLoaded = function(n) return LOADED[n] == true end,
  GetAddOnInfo = function(n) return n, n, "", false, LOADED[n] == nil and "MISSING" or "DISABLED" end,
}
C_Item = { GetItemInfo = function(id) if tonumber(id) == 2589 then return "Linen Cloth", "[Linen Cloth]" end end }

-- MMT core: roles and their rules, as in Team.lua
local UI = { ACCENT = { 0.3, 0.7, 1 }, ROW = 22 }
local function W(parent) local f = Frame.new(nil, parent); f.label = Frame.new(); return f end
function UI.Fill() return Frame.new() end
function UI.Border() end
function UI.Label(parent, text) local f = Frame.new(nil, parent); f.text = text; return f end
function UI.Tooltip() end
function UI.Button(parent, w, text, onClick) local b = W(parent); b.label.text = text; b:SetScript("OnClick", onClick); return b end
function UI.TextButton(parent, text, onClick) local b = W(parent); b:SetScript("OnClick", onClick); return b end
function UI.Dropdown(parent, w, text, choices, get, set)
  local b = W(parent); b.choices, b.get, b.set = choices, get, set
  b.Refresh = function() b.value = get() end
  return b
end
function UI.EditBox(parent, w, ph, onEnter) local e = W(parent); e.text = ""; e:SetScript("OnEnterPressed", function(self) onEnter(self:GetText(), self) end); return e end
function UI.AcceptItemLinks() end
MMT = { UI = UI, IsSecret = function() return false end, db = { roles = {}, team = {} } }
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
SENT = {}
function MMT.SendToTeam(msg) assert(#msg <= 250, "message too long: " .. #msg); SENT[#SENT + 1] = msg end
function MMT.AddRole(name) MMT.db.roles[name] = { rules = {} }; MMT.Fire("ROLES_CHANGED") return name end
function TAKE() local t = SENT; SENT = {} return t end
function DELIVER(msg) for _, fn in ipairs(LISTEN.TEAM_MESSAGE) do fn("Bob-Realm", "Bob", msg) end end
function MMT.Fire(ev) if LISTEN[ev] then for _, fn in ipairs(LISTEN[ev]) do fn() end end end
function MMT.SortedRoleNames()
  local t = {} for n in pairs(MMT.db.roles) do t[#t + 1] = n end
  table.sort(t, function(a, b) return a:lower() < b:lower() end) return t
end
function MMT.ItemInfo(id) if tonumber(id) == 2589 then return "Linen Cloth" end end
function MMT.RuleFromText(text)
  local id = tonumber(text:match("item:(%d+)") or (text:match("^%d+$") and text))
  if id then return { type = "item", itemID = id } end
  return { type = "item", name = text }
end
function MMT.AddRule(role, rule)
  local r = MMT.db.roles[role]
  if not r then return false, "Select or create a role first." end
  for _, e in ipairs(r.rules) do
    if e.type == rule.type and ((e.itemID and e.itemID == rule.itemID) or (not e.itemID and e.name == rule.name)) then
      return false, "That rule is already on this role." end
  end
  table.insert(r.rules, rule); MMT.Fire("ROLES_CHANGED") return true
end
function MMT.RemoveRule(role, i) table.remove(MMT.db.roles[role].rules, i); MMT.Fire("ROLES_CHANGED") end
function MMT.DescribeRule(rule)
  if rule.itemID then return (MMT.ItemInfo(rule.itemID) or ("Item " .. rule.itemID)), 134400, 1, 1, 1 end
  return tostring(rule.name) .. " (by name)", nil, 1, 1, 1
end
function MMT.HasRole(key, role) local m = MMT.db.team[key]; return m and m.roles and m.roles[role] and true or false end
function MMT.ShownName(key) return (key:match("^[^-]+")) end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On(ev, fn) EVENTS[ev] = fn end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  return M
end
'''

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
mod = lua.eval('{}')
for f in ('Module.lua', 'MailList.lua'):
    src = open('MMT_QoL/' + f, encoding='utf-8').read()
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)

print(lua.eval(r'''function(m)
  local M = m.M
  local F
  for _, f in ipairs(m.features) do if f.key == "mlist" then F = f end end
  assert(F and F.slash == "roles" and F.slashAlias == "mail", "feature registered")
  assert(M.db.mlist and M.db.mlDock and M.db.mlOpen == false, "on, docked, folded by default")

  -- no roles yet: nothing to add to
  assert(m.MailRole() == nil)
  local ok, err = m.MailAdd(m.MailRole(), 2589)
  assert(not ok and err:find("Roles"), "no role: " .. tostring(err))

  -- roles: the first (by name) until one is picked; a picked role that's gone falls back
  MMT.db.roles = { Tailor = { rules = {} }, cloth = { rules = { { type = "quality", quality = 0 } } } }
  assert(m.MailRole() == "cloth", "first by name: " .. tostring(m.MailRole()))
  M.db.mlRole = "Tailor"
  assert(m.MailRole() == "Tailor")
  M.db.mlRole = "Gone"
  assert(m.MailRole() == "cloth", "gone role falls back")
  M.db.mlRole = "Tailor"

  -- adding: an ID, a link, a name; the same item twice is refused
  assert(m.MailAdd("Tailor", 2589))
  ok, err = m.MailAdd("Tailor", "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r")
  assert(not ok and err:find("already"), "duplicate link: " .. tostring(err))
  assert(m.MailAdd("Tailor", "|cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r"))
  assert(m.MailAdd("Tailor", "Mageweave Cloth"))
  assert(#MMT.db.roles.Tailor.rules == 3 and MMT.db.roles.Tailor.rules[1].type == "item", "on the role's own items")
  local e = m.MailEntries("Tailor")
  assert(#e == 3 and e[1].rule.itemID == 2589 and e[1].rule.name == "Linen Cloth" and e[2].rule.itemID == 4306
    and e[3].rule.name == "Mageweave Cloth", "entries")
  ok, err = m.MailAdd("Tailor", nil)
  assert(not ok, "nothing to add")

  -- who gets it mailed
  MMT.db.team = { ["Bob-Realm"] = { order = 2, roles = { Tailor = true } }, ["Anna-Realm"] = { order = 1, roles = { cloth = true } },
                  ["Cara-Realm"] = { order = 3, roles = { Tailor = true } } }
  local who = m.MailMembers("Tailor")
  assert(#who == 2 and who[1] == "Bob" and who[2] == "Cara", "members")

  -- removing
  m.MailRemove("Tailor", 2)
  e = m.MailEntries("Tailor")
  assert(#e == 2 and e[2].rule.name == "Mageweave Cloth", "removed the second")
  m.MailRemove("Gone", 1)   -- no such role: nothing happens

  -- bags: nothing open, no panel built
  M.OnEnable(M)
  TICK()
  assert(_G.MMTQoLMailList == nil, "built only once the bags are open")

  -- the game's bags (Baganator loaded but its frames don't exist yet)
  local bags = Frame.new("ContainerFrame1"); bags.left = 900; bags:Show()
  m.MailDock()
  local p, tab = m.MailFrames()
  assert(p and not p:IsShown() and tab:IsShown(), "bags open: only the button")
  assert(tab.points[1][1] == "BOTTOMRIGHT" and tab.points[1][2] == bags and tab.points[1][3] == "TOPRIGHT", "button on top of the bags")
  tab:GetScript("OnClick")()
  assert(p:IsShown() and not tab:IsShown(), "panel beside the game's backpack")
  assert(p.points[1][1] == "TOPRIGHT" and p.points[1][2] == bags and p.points[1][3] == "TOPLEFT", "left of the bags")
  assert(p.role.value == "Tailor", "dropdown shows the role")
  assert(p.to.text:find("Bob, Cara"), "mailed to: " .. tostring(p.to.text))
  assert(p.rows[1]:IsShown() and p.rows[1].text.text == "Linen Cloth" and not p.rows[3]:IsShown(), "rows drawn: " .. tostring(p.rows[1].text.text) .. " search=" .. tostring(p.search:GetText()) .. " count=" .. tostring(p.count.text))
  assert(p.count.text:find("2 on the list"), "count: " .. tostring(p.count.text))

  -- drop an item from the cursor
  CURSOR = 4306
  p.drop:GetScript("OnReceiveDrag")()
  assert(CURSOR == nil and #m.MailEntries("Tailor") == 3 and p.rows[3].text.text == "Item 4306", "dropped item added")
  assert(p.status.text:find("Tailor"), "said so: " .. tostring(p.status.text))
  p.drop:GetScript("OnClick")()
  assert(p.status.text:find("Drag an item"), "no item on the cursor")

  -- dropped on the list (an empty spot, or a row), dragged or clicked; a plain click adds nothing
  CURSOR = 6000
  p.list:GetScript("OnMouseUp")()
  assert(CURSOR == nil and #m.MailEntries("Tailor") == 4, "dropped on the list")
  p.list:GetScript("OnMouseUp")()
  CURSOR = 6001
  p.rows[1]:GetScript("OnReceiveDrag")()
  assert(CURSOR == nil and #m.MailEntries("Tailor") == 5, "dropped on a row")
  p.rows[1]:GetScript("OnClick")()
  assert(#m.MailEntries("Tailor") == 5, "plain click adds nothing")
  m.MailRemove("Tailor", 5); m.MailRemove("Tailor", 4)

  -- the box: shift-clicked link + Enter
  p.box.text = "|cffffffff|Hitem:2592::::::::|h[Wool Cloth]|h|r"
  p.box:GetScript("OnEnterPressed")(p.box)
  assert(#m.MailEntries("Tailor") == 4 and p.box.text == "", "added from the box")

  -- the x on a row
  p.rows[1].remove:GetScript("OnClick")()
  assert(#m.MailEntries("Tailor") == 3 and m.MailEntries("Tailor")[1].rule.name == "Mageweave Cloth", "removed by x")

  -- the search box: only matching entries, any case; x / Esc clears it
  p.search.text = "MAGEweave"; p.search.scripts.OnTextChanged()
  assert(p.rows[1]:IsShown() and not p.rows[2]:IsShown() and p.count.text:find("^1 of 3 match"), "search: " .. tostring(p.count.text))
  assert(p.rows[1].entry.rule.name == "Mageweave Cloth", "search found the wrong one")
  p.search.text = "zzz"; p.search.scripts.OnTextChanged()
  assert(not p.rows[1]:IsShown() and p.empty.text:find("matches the search"), "no match")
  p.search:GetScript("OnEscapePressed")(p.search); p.search.scripts.OnTextChanged()
  assert(p.search.text == "" and p.count.text:find("^3 on the list"), "cleared")
  assert(#m.MailFilter(m.MailEntries("Tailor"), "  ") == 3, "blank search = all")

  -- another role from the dropdown
  p.role.set("cloth")
  assert(M.db.mlRole == "cloth" and p.rows[1]:IsShown() and not p.rows[2]:IsShown() and p.count.text:find("^1 on the list"), "cloth list (its other rule too)")
  assert(p.to.text:find("Anna"), "cloth to Anna")
  M.db.mlRole = "Tailor"

  -- scrolling past ten
  for id = 5000, 5011 do m.MailAdd("Tailor", id) end
  MMT.Fire("ROLES_CHANGED")
  assert(p.rows[10]:IsShown() and p.count.text:find("scroll"), "more than fits")
  p.list:GetScript("OnMouseWheel")(nil, -1)
  assert(p.offset == 3, "scrolled: " .. tostring(p.offset))

  -- fold away: a small button instead; the slash opens it again
  bags:Hide(); TICK(); assert(not tab:IsShown() and not p:IsShown(), "goes with the bags")
  bags:Show(); TICK(); assert(p:IsShown() and not tab:IsShown(), "open last time: open again")
  p.hide = nil
  F.commands[""]()
  assert(not p:IsShown() and tab:IsShown() and M.db.mlOpen == false, "the slash folds it")
  bags:Hide(); TICK(); bags:Show(); TICK()
  assert(not p:IsShown() and tab:IsShown(), "folded last time: folded again")
  F.commands[""]()
  assert(p:IsShown() and not tab:IsShown(), "the slash opens it")

  -- bags closed: hidden
  bags:Hide()
  TICK()
  assert(not p:IsShown(), "hidden with the bags")

  -- Baganator's backpack (named after its skin), near the left edge: the panel goes right of it
  TIME = 20
  -- its parts are named after it (and shown with it): they must not count
  local part = Frame.new("Baganator_CategoryViewBackpackViewFramedarkSearchBox", Frame.new()); part:Show()
  local bg = Frame.new("Baganator_CategoryViewBackpackViewFramedark", UIParent); bg.left = 50; bg:Show()
  function Frame:GetParent() return rawget(self, "parent") end
  TICK()
  assert(p:IsShown() and p.points[1][2] == bg and p.points[1][1] == "TOPLEFT" and p.points[1][3] == "TOPRIGHT", "right of Baganator")

  -- Team Inventory's team bags, opened after Baganator's backpack: the panel goes beside them,
  -- away from their member list
  TIME = 30
  local tb = Frame.new("MMTTeamBagsWindow", UIParent); tb.left = 800; tb.team = Frame.new(); tb.team.left = false; tb:Show()
  TICK()
  assert(p.points[1][2] == tb and p.points[1][1] == "TOPRIGHT" and p.points[1][3] == "TOPLEFT", "left of the team bags (list on their right)")
  tb.team.left = true; TICK()
  assert(p.points[1][2] == tb and p.points[1][1] == "TOPLEFT" and p.points[1][3] == "TOPRIGHT", "right of the team bags (list on their left)")
  -- an item dragged out of the team bags (Team Inventory calls this)
  local before = #m.MailEntries("Tailor")
  p.mmtAcceptItem(8000)
  assert(#m.MailEntries("Tailor") == before + 1, "team bags item not added")
  -- team bags closed: back beside Baganator; opened again: beside them (opened last)
  tb:Hide(); TICK(); assert(p.points[1][2] == bg, "back to Baganator")
  TIME = 40; tb:Show(); TICK(); assert(p.points[1][2] == tb, "opened last")
  -- only the team bags open
  bg:Hide(); TICK(); assert(p:IsShown() and p.points[1][2] == tb, "team bags alone")
  bg:Show(); tb:Hide(); TICK()
  _G.MMTTeamBagsWindow = nil

  -- option off, feature off
  M.db.mlDock = false
  TICK()
  assert(not p:IsShown(), "not docked")
  M.db.mlDock = true
  TICK()
  assert(p:IsShown() and not tab:IsShown(), "back, still open")
  M.OnDisable(M)
  assert(not p:IsShown() and not tab:IsShown(), "off")

  local lines = {}
  F.Report(function(l) lines[#lines + 1] = l end)
  assert(lines[1]:find("role=Tailor") and lines[1]:find("baganatorFrames=1"), lines[1])

  -- team sync: what is added / taken off here is sent
  M.OnEnable(M)
  TAKE()
  assert(m.MailAdd("Tailor", 7001))
  local sent = TAKE()
  assert(#sent == 1 and sent[1] == "QML:+:Tailor:i7001", "add sent: " .. tostring(sent[1]))
  local idx
  for i, e in ipairs(m.MailEntries("Tailor")) do if e.rule.itemID == 7001 then idx = e.index end end
  m.MailRemove("Tailor", idx)
  sent = TAKE()
  assert(#sent == 1 and sent[1] == "QML:-:Tailor:i7001", "remove sent: " .. tostring(sent[1]))
  m.MailAdd("Tailor", 5000)                      -- already on it: nothing sent
  assert(#TAKE() == 0, "duplicate not sent")
  -- a role name with odd characters, a name entry
  MMT.db.roles["Odd: a,b"] = { rules = {} }
  m.MailAdd("Odd: a,b", "Mageweave, Cloth")
  sent = TAKE()
  assert(sent[1] == "QML:+:Odd%3A a%2Cb:nMageweave%2C Cloth", "escaped: " .. tostring(sent[1]))

  -- taken from the team: added (also for a role this character doesn't have), removed; a chat line
  PRINTS = {}
  DELIVER("QML:+:Herbs:i2447,i765,nBriarthorn")
  local h = m.MailEntries("Herbs")
  assert(#h == 3 and h[1].rule.itemID == 2447 and h[3].rule.name == "Briarthorn", "role made and filled")
  assert(PRINTS[1] and PRINTS[1]:find("Bob") and PRINTS[1]:find("3 items added to Herbs"), tostring(PRINTS[1]))
  assert(#TAKE() == 0, "taken changes are not sent back")
  DELIVER("QML:+:Herbs:i2447")                   -- already there: no line
  assert(#PRINTS == 1, "nothing new, no line")
  DELIVER("QML:-:Herbs:i765,nbriarthorn")
  h = m.MailEntries("Herbs")
  assert(#h == 1 and h[1].rule.itemID == 2447, "removed")
  DELIVER("QML:+:Odd%3A a%2Cb:nMageweave%2C Cloth")
  assert(#m.MailEntries("Odd: a,b") == 1, "escaped names match")
  DELIVER("QML:-:Nope:i1")                       -- unknown role, remove: nothing
  assert(MMT.db.roles.Nope == nil)

  -- batched: changes wait 5 s after the last one, then go together (one message per role and sign);
  -- added then taken off again sends only the removal; at most 30 s after the first change
  local after, due = C_Timer.After, {}
  C_Timer.After = function(d, fn) due[#due + 1] = { TIME + d, fn } end
  local function RUN() local d = due; due = {}; for _, x in ipairs(d) do if x[1] <= TIME then x[2]() else due[#due + 1] = x end end end
  TAKE()
  for id = 8001, 8006 do assert(m.MailAdd("Tailor", id)); TIME = TIME + 1; RUN() end
  assert(#TAKE() == 0 and m.ml.queued == 6, "waiting while items keep coming")
  for i, e in ipairs(m.MailEntries("Tailor")) do if e.rule.itemID == 8003 then idx = e.index end end
  m.MailRemove("Tailor", idx)
  TIME = TIME + 4.9; RUN()
  assert(#TAKE() == 0, "not yet: 5 s after the last change")
  TIME = TIME + 0.2; RUN()
  sent = TAKE()
  assert(#sent == 2 and sent[1] == "QML:-:Tailor:i8003" and sent[2] == "QML:+:Tailor:i8001,i8002,i8004,i8005,i8006",
    "one batch: " .. table.concat(sent, " | "))
  assert(m.ml.queued == 0 and PRINTS[#PRINTS]:find("6 changes sent"), tostring(PRINTS[#PRINTS]))
  for id = 8101, 8140 do m.MailAdd("Tailor", id); TIME = TIME + 1; RUN() end
  sent = TAKE()
  assert(#sent == 1 and select(2, sent[1]:gsub(",", "")) == 29, "sent 30 s after the first: " .. #sent)
  TIME = TIME + 5; RUN()
  assert(#TAKE() == 1 and m.ml.queued == 0, "the rest 5 s later")
  m.MailAdd("Tailor", 8201)
  M.OnDisable(M)
  assert(#TAKE() == 1, "switched off: what waits goes now")
  M.OnEnable(M)
  C_Timer.After = after
  -- sync off: nothing sent, nothing taken
  M.db.mlSync = false
  m.MailAdd("Tailor", 7002)
  assert(#TAKE() == 0, "off: not sent")
  DELIVER("QML:+:Herbs:i999")
  assert(#m.MailEntries("Herbs") == 1, "off: not taken")
  M.db.mlSync = true

  -- send all: every role's item entries, long lists split, other rules left out
  for id = 10000, 10060 do MMT.AddRule("Tailor", { type = "item", itemID = id }) end
  F.commands.send()
  sent = TAKE()
  local items, tailor = 0, 0
  for _, msg in ipairs(sent) do
    assert(#msg <= 240, "too long")
    local role, list = msg:match("^QML:%+:([^:]+):(.*)$")
    assert(role, msg)
    assert(not list:find("quality"), "only items")
    for _ in list:gmatch("[^,]+") do items = items + 1; if role == "Tailor" then tailor = tailor + 1 end end
  end
  assert(tailor == #m.MailEntries("Tailor") and #sent > 2, "all of Tailor in several messages: " .. tailor)
  assert(PRINTS[#PRINTS]:find("sent " .. items .. " item"), PRINTS[#PRINTS])
  return "mail list: roles, add / remove, members, docking, folding, off, team sync"
end''')(mod))
