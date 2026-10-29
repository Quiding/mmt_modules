import os, re, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

toc = [l.strip() for l in open('MMT_Totems/MMT_Totems.toc', encoding='utf-8') if l.strip().endswith('.lua')]

STUBS = r'''
local function noop() end
local Obj = {}
local function New(name)
  local o = { _attr = {}, _shown = false, _name = name, _parent = nil, _points = 0 }
  return setmetatable(o, Obj)
end
Obj.__index = function(t, k)
  local f = rawget(Obj, k)
  if f then return f end
  return noop
end
function Obj:SetAttribute(k, v) if self._secure and IN_COMBAT then error("ADDON_ACTION_BLOCKED: SetAttribute in combat") end self._attr[k] = v end
function Obj:GetAttribute(k) return self._attr[k] end
function Obj:Show() self._shown = true end
function Obj:Hide() self._shown = false end
function Obj:SetShown(v) self._shown = v and true or false end
function Obj:IsShown() return self._shown end
function Obj:IsVisible() return self._shown end
function Obj:SetParent(p) if self._secure and IN_COMBAT then error("ADDON_ACTION_BLOCKED: SetParent in combat") end self._parent = p end
function Obj:GetParent() return self._parent end
function Obj:CreateTexture() return New() end
-- like the game: a FontString needs a font (template or SetFont) before SetText
function Obj:CreateFontString(name, layer, template) local f = New(); f._text = ""; f._font = template ~= nil; f._fs = true; return f end
function Obj:SetFont() self._font = true; return true end
function Obj:SetFontObject() self._font = true end
function Obj:CreateAnimationGroup() local g = New(); function g:CreateAnimation() return New() end return g end
function Obj:SetText(t)
  if self._fs and not self._font then error("FontString:SetText(): Font not set") end
  self._text = t
end
function Obj:GetText() return self._text end
function Obj:GetStringWidth() return 50 end
function Obj:GetFrameLevel() return 1 end
function Obj:GetName() return self._name end
function Obj:IsMouseOver() return false end
function Obj:SetScript(ev, fn) self["_" .. ev] = fn end
function Obj:HookScript(ev, fn) self["_" .. ev] = fn end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:SetPoint(...) if self._secure and IN_COMBAT then error("ADDON_ACTION_BLOCKED: SetPoint in combat") end self._pt = { ... } end
function Obj:SetSize(w, h) self._w, self._h = w, h end

function CreateFrame(kind, name, parent, template)
  local o = New(name)
  o._parent = parent
  o._secure = template and template:find("Secure") and true or false
  if name then _G[name] = o end
  return o
end
UIParent = New("UIParent")
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
GameTooltip = New("GameTooltip")
IN_COMBAT = false
function InCombatLockdown() return IN_COMBAT end
NOW = 1000
function GetTime() return NOW end
C_Timer = { After = function(_, f) f() end, NewTicker = function() return { Cancel = noop } end }
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
function UnitInParty() return false end
function UnitInRaid() return false end
function UnitGroupRolesAssigned() return "NONE" end
function GetBindingText(k) return k end
OVERRIDES = {}
function ClearOverrideBindings() OVERRIDES = {} end
function SetOverrideBindingClick(_, _, key, button) OVERRIDES[key] = button end
function hooksecurefunc() end

SPELLS = {
  [3599] = "Searing Totem", [8190] = "Magma Totem", [5394] = "Healing Stream Totem", [5675] = "Mana Spring Totem",
  [8512] = "Windfury Totem", [8835] = "Grace of Air Totem", [8075] = "Strength of Earth Totem", [8071] = "Stoneskin Totem",
  [16190] = "Mana Tide Totem",
}
C_Spell = {
  GetSpellInfo = function(x)
    if type(x) == "number" then local n = SPELLS[x]; return n and { name = n, iconID = x, spellID = x } end
    for id, n in pairs(SPELLS) do if n == x then return { name = n, iconID = id, spellID = id } end end
  end,
  GetSpellTexture = function(x) if type(x) == "number" then return SPELLS[x] and x end end,
}
-- learned spells of this character (all totems used by the earlier steps; not Stoneskin 8071)
KNOWN = { [3599] = true, [8190] = true, [5394] = true, [5675] = true, [8512] = true, [8835] = true, [8075] = true, [16190] = true }
function IsPlayerSpell(id) return KNOWN[id] == true end
WHISPERS = {}
-- totem items in the bags (Earth 5175, Fire 5176, Water 5177, Air 5178)
ITEMS = { [5175] = 1, [5176] = 1, [5177] = 1, [5178] = 1 }
C_Item = { GetItemCount = function(id) return ITEMS[id] or 0 end }
TOTEMS_UP = {}   -- [slot] = { name, start, dur }
function GetTotemInfo(slot)
  local t = TOTEMS_UP[slot]
  if t then return true, t.name, t.start, t.dur, 1 end
  return false, "", 0, 0, nil
end

-- MMT core stand-in
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
SENT = {}
LISTEN = {}
EVENTS = {}
MMT = {
  CopyTable = copy, IsSecret = function() return false end,
  db = { team = { [ME] = { class = "SHAMAN", name = ME:match("^[^-]+") }, [OTHER] = { class = "SHAMAN", name = OTHER:match("^[^-]+") },
                  ["Wally-Warrior"] = { class = "WARRIOR", name = "Wally" } } },
}
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone", "Wally-Warrior" } end
function MMT.IsSelf(k) return k == ME end
function MMT.PlayerFull() return ME end
function MMT.IsOnline(k) return true end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Resolve(k) return MMT.db.team[k] and k end
function MMT.SplitUnit() return nil end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = msg end
function MMT.SendAddon(msg, channel, target) WHISPERS[#WHISPERS + 1] = { msg = msg, to = target } end
function MMT.Print() end
OPENED = {}
function MMT.ToggleConfig(k) OPENED[#OPENED + 1] = k end
function MMT.RefreshConfig() end
function MMT.ApplyFont(fs) fs._font = true end
function MMT.Repr(s) return s end
MMT.UI = setmetatable({}, { __index = function() return function() return CreateFrame("Frame") end end })
CONFIRMS = {}
MMT.UI.Confirm = function(text, acceptText, onAccept) CONFIRMS[#CONFIRMS + 1] = { text = text, accept = onAccept } end
function UnitClass() return "Shaman", "SHAMAN" end
MMT.ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }
function MMT.NewModule(def)
  local M = def
  M.enabled = false
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  HEARTBEATS = HEARTBEATS or {}
  function M:Heartbeat(k, fn) HEARTBEATS[k] = fn end
  M.db = copy(def.defaults)
  M.store = {}
  return M
end
function FIRE(ev, ...) for _, fn in ipairs(EVENTS[ev] or {}) do fn(...) end end
-- what the core's ns.ImportModuleSettings does with a module's synced M.db
function CORE_SYNC(M, data, from)
  assert(M.sync == true, "module doesn't opt in to the core sync")
  data = MMT.CopyTable(data)
  for _, k in ipairs(M.syncExclude or {}) do data[k] = M.db[k] end
  M.db = data
  if M.OnProfileChanged then M.OnProfileChanged(M) end
  if M.OnSyncReceived then M.OnSyncReceived(M, from) end
end
function DELIVER(from, msg) for _, fn in ipairs(LISTEN.TEAM_MESSAGE or {}) do fn(from, from, msg) end end
'''

def client(me, other):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"; OTHER = "%s"' % (me, other))
    lua.execute(STUBS)
    mod = lua.eval('{}')
    for f in toc:
        src = open('MMT_Totems/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("MMT_Totems", m) end')(src, f, mod)
    lua.eval('function(m) m.M.enabled = true; m.M.OnEnable() end')(mod)
    return lua, mod

A, amod = client("Anna-Smith", "Bob-Stone")
B, bmod = client("Bob-Stone", "Anna-Smith")

def sent(lua):
    msgs = list(lua.eval('SENT').values())
    lua.execute('SENT = {}')
    return msgs

def deliver(frm, msgs, lua):
    for m in msgs:
        lua.eval('function(f, m) DELIVER(f, m) end')(frm, m)

res = A.eval(r'''function(m)
  local own = m.bars["Anna-Smith"]
  assert(own, "own bar missing")
  local sh = table.concat(m.Shamans(), ",")
  assert(sh == "Anna-Smith,Bob-Stone", "shamans: " .. sh)
  -- choose totems
  m.SetSelected("Anna-Smith", "Fire", 3599)
  m.SetSelected("Anna-Smith", "Water", 5394)
  assert(own.slots.Fire:GetAttribute("*macrotext1") == "/cast Searing Totem", "fire slot macro")
  assert(own.slots.Water:GetAttribute("*macrotext1") == "/cast Healing Stream Totem")
  assert(own.slots.Air:GetAttribute("*macrotext1") == nil, "air should be empty")
  local seq = MMTTotemsSequenceButton:GetAttribute("macrotext")
  assert(seq == "/castsequence reset=10/combat Searing Totem, Healing Stream Totem", "seq: " .. tostring(seq))
  m.SetSequence("Anna-Smith", "water, fire")
  seq = MMTTotemsSequenceButton:GetAttribute("macrotext")
  assert(seq == "/castsequence reset=10/combat Healing Stream Totem, Searing Totem", "order: " .. tostring(seq))
  m.M.db.spamSafe = true; m.UpdateSecure()
  seq = MMTTotemsSequenceButton:GetAttribute("macrotext")
  assert(seq == "/castsequence reset=3 Healing Stream Totem, Searing Totem, null", "spam: " .. tostring(seq))
  -- key binding
  m.SetKey("ALT-T")
  assert(OVERRIDES["ALT-T"] == "MMTTotemsSequenceButton", "keybind")
  -- in combat: nothing secure changes until combat ends
  IN_COMBAT = true
  m.SetSelected("Anna-Smith", "Fire", 8190)
  assert(own.slots.Fire:GetAttribute("*macrotext1") == "/cast Searing Totem", "changed in combat!")
  m.Refresh()
  IN_COMBAT = false
  FIRE("PLAYER_REGEN_ENABLED")
  assert(own.slots.Fire:GetAttribute("*macrotext1") == "/cast Magma Totem", "not applied after combat")
  -- passive mode clears casting
  m.M.db.onlyTimers = true; m.UpdateSecure()
  assert(own.slots.Fire:GetAttribute("*macrotext1") == nil and MMTTotemsSequenceButton:GetAttribute("macrotext") == nil)
  m.M.db.onlyTimers = false; m.UpdateSecure()
  return "casting ok"
end''')(amod)
print("A:", res)
deliver("Anna-Smith", sent(A), B)
print("B:", B.eval(r'''function(m)
  assert(m.Selected("Anna-Smith", "Fire") == 8190, "selection not synced")
  assert(m.Sequence("Anna-Smith") == "water, fire", "sequence not synced: " .. m.Sequence("Anna-Smith"))
  -- B chooses a totem for Anna (another shaman)
  m.SetSelected("Anna-Smith", "Air", 8512)
  return "selection sync ok"
end''')(bmod))
deliver("Bob-Stone", sent(B), A)
print("A:", A.eval(r'''function(m)
  local own = m.bars["Anna-Smith"]
  assert(own.slots.Air:GetAttribute("*macrotext1") == "/cast Windfury Totem", "choice from Bob not applied")
  -- own totems: one message per change
  SENT = {}
  TOTEMS_UP[1] = { name = "Magma Totem", start = 1000, dur = 20 }
  FIRE("PLAYER_TOTEM_UPDATE", 1)
  FIRE("PLAYER_TOTEM_UPDATE", 1)
  assert(#SENT == 1 and SENT[1]:find("^MTT:1:20.0/20.0:Magma Totem$"), "totem message: " .. tostring(SENT[1]) .. " n=" .. #SENT)
  local n, _, s, d = m.ActiveTotem("Anna-Smith", "Fire")
  assert(n == "Magma Totem" and d == 20)
  return "own totems ok"
end''')(amod))
msgs = sent(A)
B.execute('NOW = 1005')
deliver("Anna-Smith", msgs, B)
print("B:", B.eval(r'''function(m)
  local n, icon, s, d = m.ActiveTotem("Anna-Smith", "Fire")
  assert(n == "Magma Totem" and d == 20 and math.abs((s + d - NOW) - 20) < 0.01, "remote totem")
  DELIVER("Anna-Smith", "MTT:1:0")
  assert(m.ActiveTotem("Anna-Smith", "Fire") == nil, "totem gone not applied")
  assert(m.LastTotem("Anna-Smith", "Fire") == "Magma Totem", "last used")
  return "remote totems ok"
end''')(bmod))
print("A:", A.eval(r'''function(m)
  -- sequence editor: order, swap, leave out
  local order, used = m.SequenceOrder("Earth, Fire")
  assert(table.concat(order, ",") == "Earth,Fire,Air,Water" and used.Earth and used.Fire and not used.Air, "order")
  order[1], order[2] = order[2], order[1]
  used.Water = true
  assert(m.SequenceText(order, used) == "Fire, Earth, Water", m.SequenceText(order, used))
  assert(m.SequenceText(order, {}) == m.DEFAULT_SEQUENCE, "empty sequence")
  return "sequence editor ok"
end''')(amod))
print("A:", A.eval(r'''function(m)
  -- presets
  local ok, msg = m.SavePreset("Anna-Smith", "AoE")
  assert(ok, msg)
  m.SetSelected("Anna-Smith", "Fire", 3599)
  m.ApplyPreset("Anna-Smith", "AoE")
  assert(m.Selected("Anna-Smith", "Fire") == 8190, "preset not applied")
  m.SetSelected("Bob-Stone", "Earth", 8075)
  ok, msg = m.SaveTeamPreset("Raid")
  assert(ok, msg)
  m.SetSelected("Bob-Stone", "Earth", 8071)
  m.ApplyTeamPreset("Raid")
  assert(m.Selected("Bob-Stone", "Earth") == 8075, "team preset not applied")
  assert(not m.SavePreset(nil, "x") and not m.SavePreset("Anna-Smith", "  "))
  SENT = {}
  return "presets ok"
end''')(amod))
sent(A)
# the core's "Sync to team": A's whole M.db, except B keeps its key binding
STR = A.eval('function(m) return MMTTransfer.Encode("T", m.M.db) end')(amod)
print("B:", B.eval(r'''function(m, str)
  m.M.db.keybind = "F5"
  CORE_SYNC(m.M, assert(MMTTransfer.Decode("T", str)), "Anna-Smith")
  assert(m.M.db.keybind == "F5", "key binding synced")
  assert(m.M.db.presets["Anna-Smith"] and m.M.db.presets["Anna-Smith"].AoE, "presets not received")
  assert(m.M.db.teamPresets.Raid and m.M.db.teamPresets.Raid.members["Bob-Stone"].totems.Earth == 8075, "team preset not received")
  -- import / export round trip
  local captured
  MMTTransfer.Open = function(d) captured = d end
  m.OpenTransfer()
  local data = { sections = {} }
  for _, s in ipairs(captured.sections) do data.sections[s.id] = s.get() end
  local str = MMTTransfer.Encode(captured.prefix, data)
  local before = MMT.CopyTable(m.M.db)
  m.M.db.iconSize = 99; m.M.db.selected = {}; m.M.db.presets = {}; m.M.db.order = "ROLE"
  local back = assert(MMTTransfer.Decode(captured.prefix, str))
  for _, s in ipairs(captured.sections) do assert(s.set(back.sections[s.id]) ~= false, s.id) end
  assert(m.M.db.iconSize == before.iconSize and m.M.db.order == before.order, "look not restored")
  assert(m.M.db.selected["Anna-Smith"].Fire == before.selected["Anna-Smith"].Fire, "totems not restored")
  assert(m.M.db.presets["Anna-Smith"].AoE, "presets not restored")
  for _, s in ipairs(captured.sections) do assert(s.set("junk") == false, "junk accepted: " .. s.id) end
  return "core sync + import/export ok"
end''')(bmod, STR))

print("A:", A.eval(r"""function(m)
  local captured
  MMT.UI.OpenList = function(owner, items) captured = items end
  local function Menu(key, el)
    captured = nil
    m.OpenTotemMenu(UIParent, key, el)
    local t = {}
    for _, it in ipairs(captured) do t[#t + 1] = tostring(it.value) .. (it.text:find("not learned") and "!" or "") end
    return table.concat(t, ",")
  end
  -- own: only learned totems
  m.SetSelected("Anna-Smith", "Earth", 0)
  m.SetSelected("Bob-Stone", "Earth", 0)   -- the team preset step chose one for Bob
  assert(Menu("Anna-Smith", "Earth") == "0,8075", "own earth menu: " .. Menu("Anna-Smith", "Earth"))
  -- another shaman without a list yet: everything
  assert(Menu("Bob-Stone", "Earth") == "0,8075,8071", "no list yet: " .. Menu("Bob-Stone", "Earth"))
  -- Bob's client tells us what Bob knows: Stoneskin, not Strength of Earth
  WHISPERS = {}
  DELIVER("Bob-Stone", "MTTK:8071,3599")
  assert(Menu("Bob-Stone", "Earth") == "0,8071", "bob earth menu: " .. Menu("Bob-Stone", "Earth"))
  assert(#WHISPERS == 1 and WHISPERS[1].msg:find("^MTTK:") and WHISPERS[1].to == "Bob-Stone", "no reply with our list")
  DELIVER("Bob-Stone", "MTTK:8071,3599")
  assert(#WHISPERS == 1, "replied twice")
  -- a chosen totem stays in the menu, marked
  m.SetSelected("Bob-Stone", "Earth", 8075)
  assert(Menu("Bob-Stone", "Earth") == "0,8075!,8071", "kept choice: " .. Menu("Bob-Stone", "Earth"))
  -- own casting skips a chosen totem that isn't learned
  m.SetSelected("Anna-Smith", "Earth", 8071)
  local own = m.bars["Anna-Smith"]
  assert(own.slots.Earth:GetAttribute("*macrotext1") == nil, "casts an unlearned totem")
  m.SetSequence("Anna-Smith", "Earth, Fire")
  local seq = MMTTotemsSequenceButton:GetAttribute("macrotext")
  assert(not seq:find("Stoneskin"), "sequence has an unlearned totem: " .. seq)
  -- learning it makes it castable
  KNOWN[8071] = true
  m.UpdateSecure()
  assert(own.slots.Earth:GetAttribute("*macrotext1") == "/cast Stoneskin Totem", "learned totem not cast")
  return "learned totems ok"
end""")(amod))

# look: background / border from LibSharedMedia, row backgrounds, font; export sanitizing
print("A:", A.eval(r"""function(m)
  local LSM = { Fetch = function(_, kind, name) return "media/" .. kind .. "/" .. name end }
  LibStub = function(name, silent) if name == "LibSharedMedia-3.0" then return LSM end end
  local Obj = getmetatable(m.container)
  function Obj:SetBackdrop(b) self._backdrop = b end
  function Obj:SetBackdropColor(r, g, b, a) self._bgc = { r, g, b, a } end
  function Obj:SetBackdropBorderColor(r, g, b, a) self._edgec = { r, g, b, a } end
  local c = m.M.db
  c.ungrouped = false
  c.bgTexture, c.bgColor, c.bgAlpha = "Marble", { r = 0.1, g = 0.2, b = 0.3 }, 0.5
  c.borderTexture, c.borderColor, c.borderSize = "Tooltip", { r = 1, g = 0, b = 0 }, 16
  c.rowColor, c.rowAlpha = { r = 0, g = 1, b = 0 }, 0.25
  m.Refresh()
  local f, bar = m.container, m.bars["Anna-Smith"]
  assert(f._backdrop and f._backdrop.bgFile == "media/background/Marble", "frame background")
  assert(f._backdrop.edgeFile == "media/border/Tooltip" and f._backdrop.edgeSize == 16, "frame border")
  local function near(a, b) return math.abs(a - b) < 1e-9 end
  assert(near(f._bgc[3], 0.3) and f._bgc[4] == 0.5 and f._edgec[1] == 1, "frame colours")
  c.bgTint = 0.5   -- half way from the texture's own colours (white) to the colour
  m.Refresh()
  assert(math.abs(f._bgc[1] - 0.55) < 1e-9 and math.abs(bar._bgc[2] - 1) < 1e-9 and math.abs(bar._bgc[1] - 0.5) < 1e-9, "colour strength")
  c.bgTint = 1
  assert(bar._backdrop.edgeFile == nil and near(bar._bgc[2], 1) and bar._bgc[4] == 0.25, "row background")
  -- ungrouped: each bar gets the frame look
  c.ungrouped = true
  m.Refresh()
  assert(bar._backdrop.edgeFile == "media/border/Tooltip" and bar._bgc[4] == 0.5, "ungrouped bar look")
  -- FLAT / NONE without the library
  LibStub = nil
  c.bgTexture, c.borderTexture = "FLAT", "NONE"
  m.Refresh()
  assert(bar._backdrop.bgFile == "Interface\\Buttons\\WHITE8X8" and bar._backdrop.edgeFile == nil, "flat look")
  c.ungrouped = false
  m.Refresh()
  -- import: colours become plain numbers, font "" = game font
  local opts
  local open = MMTTransfer.Open
  MMTTransfer.Open = function(o) opts = o end
  m.OpenTransfer()
  MMTTransfer.Open = open
  local look
  for _, s in ipairs(opts.sections) do if s.id == "look" then look = s end end
  c.font = "Friz"
  assert(look.get().font == "Friz", "font not exported")
  assert(look.set({ font = "", bgColor = { r = "x", g = 0.5 }, borderSize = 20 }), "import failed")
  assert(c.font == nil and c.bgColor.r == 0 and c.bgColor.g == 0.5 and c.bgColor.b == 0 and c.borderSize == 20, "import sanitizing")
  assert(look.set({ font = "Friz", rowColor = "red" }) and c.font == "Friz" and type(c.rowColor) == "table", "bad colour taken over")
  return "look ok"
end""")(amod))

print("A:", A.eval(r"""function(m)
  local own = m.bars["Anna-Smith"]
  local function Shown(bar) local t = {} for _, el in ipairs(m.ELEMENTS) do if bar.slots[el]:IsShown() then t[#t + 1] = el end end return table.concat(t, ",") end
  m.Refresh()
  assert(Shown(own) == "Fire,Air,Water,Earth", "own start: " .. Shown(own))
  -- no Air Totem in the bags: Air goes, the team hears it once, the sequence skips Air
  m.SetSelected("Anna-Smith", "Air", 8512)
  m.SetSequence("Anna-Smith", "Air, Fire")
  SENT = {}
  ITEMS[5178] = nil
  FIRE("BAG_UPDATE_DELAYED")
  assert(Shown(own) == "Fire,Water,Earth", "air not hidden: " .. Shown(own))
  local k = 0
  for _, msg in ipairs(SENT) do if msg:find("^MTTK:") then k = k + 1; local items = msg:match(";(%a*)$") or "?"
    assert(not items:find("A") and items:find("E") and items:find("F") and items:find("W"), "items part: " .. msg) end end
  assert(k == 1, "MTTK sent " .. k .. " times")
  local seq = MMTTotemsSequenceButton:GetAttribute("macrotext") or ""
  assert(not seq:find("Windfury"), "sequence casts a totem without its item: " .. seq)
  FIRE("BAG_UPDATE_DELAYED")
  k = 0
  for _, msg in ipairs(SENT) do if msg:find("^MTTK:") then k = k + 1 end end
  assert(k == 1, "resent without a change")
  -- in combat nothing moves; after combat the slot comes back
  IN_COMBAT = true
  ITEMS[5178] = 1
  FIRE("BAG_UPDATE_DELAYED")
  assert(Shown(own) == "Fire,Water,Earth", "layout changed in combat")
  IN_COMBAT = false
  FIRE("PLAYER_REGEN_ENABLED")
  assert(Shown(own) == "Fire,Air,Water,Earth", "air not back after combat: " .. Shown(own))
  -- another shaman: items from the message (Bob knows Searing + Strength of Earth, carries Earth + Fire)
  local bob = m.bars["Bob-Stone"]
  DELIVER("Bob-Stone", "MTTK:3599,8075;EF")
  assert(Shown(bob) == "Fire,Earth", "bob with items: " .. Shown(bob))
  -- an older client (no items part): only unlearned elements hide
  DELIVER("Bob-Stone", "MTTK:3599,8075")
  assert(Shown(bob) == "Fire,Earth", "bob old format: " .. Shown(bob))
  DELIVER("Bob-Stone", "MTTK:3599,8075,5394,8512")
  assert(Shown(bob) == "Fire,Air,Water,Earth", "bob old format, all learned: " .. Shown(bob))
  -- switches
  m.M.db.hideUnlearned = false
  DELIVER("Bob-Stone", "MTTK:3599;F")
  m.Refresh()
  assert(Shown(bob) == "Fire", "only the item rule: " .. Shown(bob))
  m.M.db.hideNoItem = false
  m.Refresh()
  assert(Shown(bob) == "Fire,Air,Water,Earth", "both rules off: " .. Shown(bob))
  m.M.db.hiddenElements.Fire = true
  m.Refresh()
  assert(Shown(bob) == "Air,Water,Earth" and Shown(own) == "Air,Water,Earth", "always hide Fire")
  m.M.db.hiddenElements.Fire = nil
  m.M.db.hideNoItem, m.M.db.hideUnlearned = true, true
  return "totem slots ok"
end""")(amod))

print("A:", A.eval(r"""function(m)
  local c = m.M.db
  c.showNames, c.vertical, c.ungrouped = true, false, false
  c.showPresets = false
  m.Refresh()
  local a, b = m.bars["Anna-Smith"], m.bars["Bob-Stone"]
  -- name column: 50 (stub text width) + 6; first icon right after it, the same on both bars
  local ax, bx = a.slots.Fire._pt[2], b.slots.Fire._pt[2]
  assert(ax == 56 and bx == 56, "icons not lined up after the name: " .. tostring(ax) .. " / " .. tostring(bx))
  assert(a.slots.Fire._pt[3] == 0, "icon not on the name's line")
  assert(a.name._pt[1] == "LEFT", "name not left of the icons")
  assert(a._h == c.iconSize, "row height " .. tostring(a._h) .. " instead of the icon size")
  -- vertical: the name above the icons
  c.vertical = true
  m.Refresh()
  assert(a.name._pt[1] == "TOP" and a.slots.Fire._pt[3] == -(c.nameSize + 3), "vertical: name not above")
  -- name (50) wider than an icon: icons centred in the column, no gap on one side
  local size = c.iconSize
  local colW = math.max(size, 52)
  assert(a._w == colW, "column width " .. tostring(a._w))
  assert(a.slots.Fire._pt[2] == math.floor((colW - size) / 2 + 0.5), "icons not centred: x=" .. tostring(a.slots.Fire._pt[2]))
  c.vertical = false
  -- names off: icons start at the left edge
  c.showNames = false
  m.Refresh()
  assert(a.slots.Fire._pt[2] == 0, "names off: icons not at the edge")
  c.showNames = true
  m.Refresh()
  return "look like Buffs / Cooldowns ok"
end""")(amod))

print("A:", A.eval(r"""function(m)
  local c = m.M.db
  c.ungrouped, c.locked = false, false
  m.Refresh()
  OPENED = {}
  -- right-click the frame background and a bar background: the Totems settings open
  MMTTotemsFrame._OnMouseUp(MMTTotemsFrame, "RightButton")
  local bar = m.bars["Bob-Stone"]
  bar._OnMouseUp(bar, "RightButton")
  assert(#OPENED == 2 and OPENED[1] == "Totems" and OPENED[2] == "Totems", "settings not opened: " .. #OPENED)
  MMTTotemsFrame._OnMouseUp(MMTTotemsFrame, "LeftButton")
  assert(#OPENED == 2, "left click opened the settings")
  -- dragging a bar while grouped moves (and saves) the whole frame
  bar._OnDragStart(bar)
  bar._OnDragStop(bar)
  assert(c.point[1] == "CENTER" and c.barPoints["Bob-Stone"] == nil, "grouped drag saved a bar position")
  c.ungrouped = true
  m.Refresh()
  bar._OnDragStart(bar)
  bar._OnDragStop(bar)
  assert(c.barPoints["Bob-Stone"], "ungrouped drag did not save the bar")
  -- locked: no moving
  c.locked = true
  c.barPoints["Bob-Stone"] = nil
  bar._OnDragStart(bar)
  bar._OnDragStop(bar)
  assert(c.barPoints["Bob-Stone"] == nil, "moved while locked")
  c.locked, c.ungrouped = false, false
  c.barPoints = {}
  m.Refresh()
  return "right-click settings + drag ok"
end""")(amod))

# --- growth direction: shared bars (IconBars) and the totem frame ---------------
A.eval('function(src) assert(loadstring(src, "IconBars.lua"))() end')(open('MMT_CooldownTimers/IconBars.lua', encoding='utf-8').read())
print("A:", A.eval(r"""function(m)
  local cfg = { shown = true, iconSize = 20, spacing = 0, rowGap = 0, showNames = false, point = { "CENTER", "CENTER", 0, 0 } }
  local w = MMTIconBars.NewWindow({ name = "TestBars", cfg = function() return cfg end,
    rows = function() return { { key = "Anna-Smith", icons = { { state = "ready" } } }, { key = "Bob-Stone", icons = { { state = "ready" } } } } end })
  local function Y(i) return w.rows[i]._pt[3] end
  local function X(i) return w.rows[i]._pt[2] end
  local function Name(i) return w.rows[i].icons[1].key end
  w:Refresh()
  assert(Name(1) == "Anna-Smith" and Y(1) > Y(2), "top > down: first member on top")
  cfg.growth = "UP"; w:Refresh()
  assert(Name(1) == "Bob-Stone" and Name(2) == "Anna-Smith" and Y(2) < Y(1), "down > top: first member at the bottom")
  cfg.growth = "RIGHT"; w:Refresh()
  assert(Name(1) == "Anna-Smith" and X(2) > X(1), "left > right")
  cfg.growth = "LEFT"; w:Refresh()
  assert(Name(1) == "Bob-Stone" and Name(2) == "Anna-Smith", "right > left")
  -- older profile without growth: vertical decides
  cfg.growth = nil; cfg.vertical = true
  assert(MMTIconBars.Growth(cfg) == "RIGHT")
  cfg.vertical = false
  assert(MMTIconBars.Growth(cfg) == "DOWN")
  -- pinned at the edge it grows away from: a frame at left 100, right 300, top 500, bottom 400
  -- on a 1000 x 800 screen, same scales
  local f = { GetLeft = function() return 100 end, GetRight = function() return 300 end,
              GetTop = function() return 500 end, GetBottom = function() return 400 end,
              GetEffectiveScale = function() return 1 end }
  UIParent.GetEffectiveScale = function() return 1 end
  UIParent.GetRight = function() return 1000 end
  UIParent.GetTop = function() return 800 end
  local p = MMTIconBars.PointAt(f, "BOTTOMLEFT")
  assert(p[1] == "BOTTOMLEFT" and p[3] == 100 and p[4] == 400, "bottom-left point")
  p = MMTIconBars.PointAt(f, "TOPRIGHT")
  assert(p[1] == "TOPRIGHT" and p[3] == -700 and p[4] == -300, "top-right point")
  p = MMTIconBars.PointAt(f, "TOPLEFT")
  assert(p[3] == 100 and p[4] == -300, "top-left point")
  -- totems: grouped frame in reverse order too
  local c = m.M.db
  c.ungrouped, c.showNames, c.showPresets = false, false, false
  c.growth = "UP"; m.Refresh()
  local a, b = m.bars["Anna-Smith"], m.bars["Bob-Stone"]
  assert(a._pt[3] < b._pt[3], "totems down > top: first shaman not at the bottom")
  c.growth = "DOWN"; m.Refresh()
  assert(a._pt[3] > b._pt[3], "totems top > down")
  c.showNames, c.showPresets = true, true
  m.Refresh()
  return "growth direction ok"
end""")(amod))

# after a /reload: other shamans' totems are saved on logout and put back (real clock), each member
# is asked once (whispered MTTR) on their first heartbeat, and the asked one answers with an MTT per totem
print("B:", B.eval(r"""function(m)
  CLOCK = 70000
  function time() return CLOCK end
  NOW = 5000
  local element = m.SLOT_ELEMENT[1]
  DELIVER("Anna-Smith", "MTT:1:100.0/120.0:Searing Totem")
  assert(m.active["Anna-Smith"][element], "totem not taken")
  FIRE("PLAYER_LOGOUT")
  assert(m.M.store.running and m.M.store.running["Anna-Smith"][element], "not saved")
  m.active = {}
  NOW, CLOCK = 5020, 70020          -- 20 s later
  assert(m.RestoreRunning() == 1, "not restored")
  local name, _, start, dur = m.ActiveTotem("Anna-Smith", element)
  assert(name == "Searing Totem" and math.abs(start + dur - NOW - 80) < 0.01, "time left after the reload: " .. tostring(start and (start + dur - NOW)))
  WHISPERS = {}
  for _, fn in ipairs(LISTEN.XP_RECEIVED or {}) do fn("Anna-Smith", "Anna", { ext = {} }) end
  for _, fn in ipairs(LISTEN.XP_RECEIVED or {}) do fn("Anna-Smith", "Anna", { ext = {} }) end
  local n = 0
  for _, w in ipairs(WHISPERS) do if w.msg == "MTTR" and w.to == "Anna" then n = n + 1 end end
  assert(n == 1, "MTTR whispers: " .. n)
  return "totems after a reload ok"
end""")(bmod))
print("A:", A.eval(r"""function(m)
  NOW = 6000
  TOTEMS_UP = { [2] = { name = "Stoneskin Totem", start = 5990, dur = 120 } }
  WHISPERS = {}
  DELIVER("Bob-Stone", "MTTR")
  DELIVER("Bob-Stone", "MTTR")            -- asked twice within 10 s: one answer
  assert(#WHISPERS == 1 and WHISPERS[1].to == "Bob-Stone" and WHISPERS[1].msg:find("^MTT:2:110%.0/120%.0:Stoneskin Totem$"), "answer: " .. tostring(WHISPERS[1] and WHISPERS[1].msg))
  TOTEMS_UP = {}
  return "MTTR answered ok"
end""")(amod))

# another shaman's slots follow THEIR learned list, even when this client has no spell data for
# the totems (a warrior's client often hasn't: the whole bar disappeared with "hide unlearned")
print("B:", B.eval(r"""function(m)
  m.M.db.hideUnlearned, m.M.db.hideNoItem = true, false
  m.M.store.known = m.M.store.known or {}
  m.M.store.known["Anna-Smith"] = { [3599] = true }          -- Searing Totem only (Fire)
  local realInfo = m.SpellInfo
  m.SpellInfo = function() return nil end                    -- no spell data here at all
  assert(m.SlotShown("Anna-Smith", "Fire"), "Fire hidden although Anna knows Searing Totem")
  assert(not m.SlotShown("Anna-Smith", "Water"), "Water shown although Anna knows no water totem")
  -- the name lookup is built again when the data arrives (built now without data: no names)
  m.TotemDataArrived(3599, true)
  assert(m.TotemByName("Searing Totem") == nil, "name known without data")
  m.SpellInfo = realInfo
  m.TotemDataArrived(3599, true)
  assert(m.TotemByName("Searing Totem") == 3599, "lookup not rebuilt when the data arrived")
  return "other shamans' slots without spell data ok"
end""")(bmod))

# the practice shaman: a made-up bar, nothing about it sent, wiped when it goes
print("A:", A.eval(r"""function(m)
  SENT = {}
  m.SetPractice(true)
  local found = false
  for _, k in ipairs(m.Shamans()) do if k == m.PRACTICE then found = true end end
  assert(found and m.IsShaman(m.PRACTICE), "no practice bar")
  assert(m.SlotShown(m.PRACTICE, "Fire") and m.KnowsTotem(m.PRACTICE, 3599), "practice shaman can't use every totem")
  m.SetSelected(m.PRACTICE, "Fire", 3599)
  m.SetSequence(m.PRACTICE, "Fire, Air")
  assert(#SENT == 0, "practice shaman sent to the team: " .. tostring(SENT[1]))
  assert(m.M.db.selected[m.PRACTICE].Fire == 3599, "choice not kept while practising")
  m.SetPractice(false)
  assert(m.M.db.selected[m.PRACTICE] == nil and m.M.db.sequences[m.PRACTICE] == nil, "practice choices left behind")
  for _, k in ipairs(m.Shamans()) do assert(k ~= m.PRACTICE, "practice bar after removing it") end
  return "practice shaman ok"
end""")(amod))
