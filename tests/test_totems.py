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
function Obj:SetPoint() if self._secure and IN_COMBAT then error("ADDON_ACTION_BLOCKED: SetPoint in combat") end end

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
function MMT.RefreshConfig() end
function MMT.ApplyFont(fs) fs._font = true end
function MMT.Repr(s) return s end
MMT.UI = setmetatable({}, { __index = function() return function() return CreateFrame("Frame") end end })
function UnitClass() return "Shaman", "SHAMAN" end
MMT.ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }
function MMT.NewModule(def)
  local M = def
  M.enabled = false
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  function M:Listen(ev, fn) LISTEN[ev] = LISTEN[ev] or {}; table.insert(LISTEN[ev], fn) end
  function M:Debug() end
  M.db = copy(def.defaults)
  M.store = {}
  return M
end
function FIRE(ev, ...) for _, fn in ipairs(EVENTS[ev] or {}) do fn(...) end end
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
  m.SendAll()
  return "presets ok"
end''')(amod))
deliver("Anna-Smith", sent(A), B)
print("B:", B.eval(r'''function(m)
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
  return "sync all + import/export ok"
end''')(bmod))

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
