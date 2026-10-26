import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

toc = [l.strip() for l in open('MMT_CooldownTimers/MMT_CooldownTimers.toc', encoding='utf-8') if l.strip().endswith('.lua')]

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
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetSpellBaseCooldown() return nil end
function UnitExists() return false end
function IsInRaid() return false end
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
  [11958] = "Ice Block", [12472] = "Cold Snap", [12042] = "Arcane Power", [12051] = "Evocation",
  [12043] = "Presence of Mind", [11129] = "Combustion", [2139] = "Counterspell",
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
  db = { team = { [ME] = { class = "MAGE", name = ME:match("^[^-]+") }, [OTHER] = { class = "MAGE", name = OTHER:match("^[^-]+") },
                  ["Wally-Warrior"] = { class = "WARRIOR", name = "Wally" } } },
}
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone", "Wally-Warrior" } end
function MMT.IsSelf(k) return k == ME end
function MMT.MemberRoleList() return {} end
function MMT.SortedRoleNames() return {} end
function MMT.ModuleActive() return true end
function MMT.PlayerFull() return ME end
function MMT.IsOnline(k) return true end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.Resolve(k) return MMT.db.team[k] and k end
function MMT.SplitUnit() return nil end
function MMT.SendToTeam(msg) SENT[#SENT + 1] = msg end
function MMT.SendAddon(msg, channel, target) WHISPERS[#WHISPERS + 1] = { msg = msg, to = target } end
LONG = {}
function MMT.SendLong(text, target) LONG[#LONG + 1] = { msg = text, to = target } end
function MMT.Print() end
OPENED = {}
function MMT.ToggleConfig(k) OPENED[#OPENED + 1] = k end
function MMT.RefreshConfig() end
function MMT.ApplyFont(fs) fs._font = true end
function MMT.Repr(s) return s end
MMT.UI = setmetatable({}, { __index = function() return function() return CreateFrame("Frame") end end })
CONFIRMS = {}
MMT.UI.Confirm = function(text, acceptText, onAccept) CONFIRMS[#CONFIRMS + 1] = { text = text, accept = onAccept } end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Night Elf", "NightElf" end
-- own spell cooldowns by name: { start, dur }
SPELLCD = {}
C_Spell.GetSpellCooldown = function(name)
  if type(name) ~= "string" then return nil end
  if UNLEARNED and UNLEARNED[name] then return nil end   -- not learned by this character
  local c = SPELLCD[name]
  if c then return { startTime = c.start, duration = c.dur, isEnabled = true } end
  return { startTime = 0, duration = 0, isEnabled = true }
end
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
        src = open('MMT_CooldownTimers/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("MMT_CooldownTimers", m) end')(src, f, mod)
    lua.eval('function(m) m.M.enabled = true; m.M.OnEnable() end')(mod)
    return lua, mod

A, amod = client("Anna-Smith", "Bob-Stone")
B, bmod = client("Bob-Stone", "Anna-Smith")

def take(lua, name="SENT"):
    msgs = list(lua.eval(name).values())
    lua.execute(name + ' = {}')
    return msgs

def deliver(frm, msgs, lua):
    for m in msgs:
        text = m if isinstance(m, str) else m["msg"]
        lua.eval('function(f, m) DELIVER(f, m) end')(frm, text)

print("A:", A.eval(r"""function(m)
  local v = HEARTBEATS.race()
  assert(v == "NightElf" and not v:find("[:,=]"), "race heartbeat: " .. tostring(v))
  assert(table.concat(m.ListKeysFor("Anna-Smith", true), ","):find("RACE:NightElf", 1, true), "own race list missing")
  return "race heartbeat ok"
end""")(amod))

# Anna uses Ice Block, then Cold Snap resets it early
print("A:", A.eval(r"""function(m)
  SENT = {}
  FIRE("SPELL_UPDATE_COOLDOWN")            -- first check only learns
  assert(#SENT == 0, "sent on the first check")
  SPELLCD["Ice Block"] = { start = 1000, dur = 300 }
  FIRE("SPELL_UPDATE_COOLDOWN")
  assert(#SENT == 1 and SENT[1]:find("^MCDU:s11958:300.0/300.0$"), "use not sent: " .. tostring(SENT[1]))
  return "use sent"
end""")(amod))
deliver("Anna-Smith", take(A), B)
B.execute("NOW = 1010")
print("B:", B.eval(r"""function(m)
  local e
  for _, x in ipairs(m.EntriesFor("Anna-Smith")) do if x.id == 11958 then e = x end end
  local state, start, dur = m.State("Anna-Smith", e)
  assert(state == "cd" and math.abs(start + dur - 1300) < 0.01, "ice block not on cooldown for Bob")
  return "ice block running"
end""")(bmod))
A.execute("NOW = 1010")
print("A:", A.eval(r"""function(m)
  SPELLCD["Ice Block"] = nil               -- Cold Snap
  FIRE("SPELL_UPDATE_COOLDOWN")
  assert(#SENT == 1 and SENT[1] == "MCDU:s11958:r", "reset not sent: " .. tostring(SENT[1]))
  -- a cooldown that simply runs out is not announced
  SPELLCD["Evocation"] = { start = 1010, dur = 480 }
  FIRE("SPELL_UPDATE_COOLDOWN")
  NOW = 1491
  SENT = {}
  SPELLCD["Evocation"] = nil
  FIRE("SPELL_UPDATE_COOLDOWN")
  assert(#SENT == 0, "normal end announced: " .. tostring(SENT[1]))
  NOW = 1010
  SENT = { "MCDU:s11958:r" }
  return "reset sent, normal end quiet"
end""")(amod))
deliver("Anna-Smith", take(A), B)
print("B:", B.eval(r"""function(m)
  local e
  for _, x in ipairs(m.EntriesFor("Anna-Smith")) do if x.id == 11958 then e = x end end
  assert(m.State("Anna-Smith", e) == "ready", "reset not applied")
  return "reset applied"
end""")(bmod))
# Bob asks for running cooldowns (after taking over lists): Anna answers by whisper
A.execute("NOW = 1020")
print("A:", A.eval(r"""function(m)
  SPELLCD["Arcane Power"] = { start = 1015, dur = 180 }
  FIRE("SPELL_UPDATE_COOLDOWN")
  SENT, WHISPERS = {}, {}
  DELIVER("Bob-Stone", "MCDQ")
  assert(#WHISPERS == 1 and WHISPERS[1].msg:find("^MCDU:s12042:175.0/180.0") and WHISPERS[1].to == "Bob-Stone",
    "running cooldown not whispered: " .. tostring(WHISPERS[1] and WHISPERS[1].msg))
  DELIVER("Bob-Stone", "MCDQ")
  assert(#WHISPERS == 1, "answered twice within 10 s")
  -- a running cooldown that becomes tracked (lists changed) is announced
  SPELLCD["Blink"] = { start = 1018, dur = 15 }
  SPELLS[1953] = "Blink"
  table.insert(m.M.db.lists.MAGE, { t = "s", id = 1953, cd = 15 })
  SENT = {}
  m.ShareCheck()
  assert(#SENT == 1 and SENT[1]:find("^MCDU:s1953:"), "newly tracked running cooldown not announced: " .. tostring(SENT[1]))
  return "MCDQ answer + newly tracked ok"
end""")(amod))

# the core's "Sync to team": M.db replaced, then the running cooldowns are asked for
print("B:", B.eval(r"""function(m)
  local data = MMT.CopyTable(m.M.db)
  data.iconSize = 33
  SENT = {}
  CORE_SYNC(m.M, data, "Anna-Smith")
  assert(m.M.db.iconSize == 33, "synced settings not in M.db")
  local asked
  for _, s in ipairs(SENT) do if s == "MCDQ" then asked = true end end
  assert(asked, "running cooldowns not requested after the sync")
  return "core sync ok"
end""")(bmod))

# the core's "Sync to team" from another client: look, position and lists arrive
STR = A.eval(r"""function(m)
  local c = m.M.db
  c.iconSize, c.growth, c.vertical, c.bgAlpha = 40, "UP", false, 0.8
  c.point = { "BOTTOMLEFT", "BOTTOMLEFT", 123, 45 }
  c.lists.MAGE[1].off = true
  return MMTTransfer.Encode("T", c)
end""")(amod)
print("B:", B.eval(r"""function(m, str)
  CORE_SYNC(m.M, assert(MMTTransfer.Decode("T", str)), "Anna-Smith")
  local c = m.M.db
  assert(c.iconSize == 40 and c.growth == "UP" and c.bgAlpha == 0.8, "look not taken over")
  assert(c.point[1] == "BOTTOMLEFT" and c.point[3] == 123 and c.point[4] == 45, "position not taken over")
  assert(c.lists.MAGE[1].off == true, "lists not taken over")
  return "sync from the team ok"
end""")(bmod, STR))

# "Reset to defaults": every setting back, in the same table the core keeps
print("B:", B.eval(r"""function(m)
  local db = m.M.db
  db.iconSize, db.extra = 55, "junk"
  db.lists.MAGE = {}
  m.ResetSettings()
  assert(m.M.db == db, "db table replaced")
  assert(db.iconSize == m.M.defaults.iconSize and db.extra == nil, "not reset")
  assert(#db.lists.MAGE == #m.M.defaults.lists.MAGE and db.lists ~= m.M.defaults.lists, "lists not reset / shared with the defaults")
  return "reset to defaults ok"
end""")(bmod))

# a cast's "buff" that the game files as a debuff (Death Wish) still counts
print("A:", A.eval(r"""function(m)
  local buffs = { { name = "Battle Shout", duration = 120, expirationTime = 1100 } }
  local debuffs = { { name = "Death Wish", duration = 30, expirationTime = 1025 } }
  C_UnitAuras = {
    GetBuffDataByIndex = function(_, i) return buffs[i] end,
    GetDebuffDataByIndex = function(_, i) return debuffs[i] end,
  }
  local s, d = m.UnitBuffTime("player", "Death Wish")
  assert(s == 995 and d == 30, "debuff not found: " .. tostring(s) .. " / " .. tostring(d))
  s, d = m.UnitBuffTime("player", "Battle Shout")
  assert(s == 980 and d == 120, "buff")
  s, d = m.UnitBuffTime("player", "Recklessness")
  assert(s == nil and d == nil, "missing aura: " .. tostring(d))
  C_UnitAuras = nil
  return "debuff as the cast's buff ok"
end""")(amod))

# lazy spell data: a tracked spell unknown when the index was built still counts when a
# group member casts it later (the index is built again)
C, cmod = client("Anna-Smith", "Bob-Stone")
print("C:", C.eval(r"""function(m)
  local REQ = {}
  C_Spell.RequestLoadSpellData = function(id) REQ[id] = true end
  m.M.db.lists.ALL = m.M.db.lists.ALL or {}
  table.insert(m.M.db.lists.ALL, { t = "s", id = 55555, cd = 60 })
  m.BuildIndex()                       -- the game doesn't know spell 55555 yet
  assert(REQ[55555], "spell data not requested")
  SPELLS[55555] = "Late Spell"         -- now it does
  MMT.SplitUnit = function(u) if u == "party1" then return "Bob", "Stone", "Bob-Stone" end end
  MMT.Resolve = function(k) return k end
  FIRE("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 55555)
  local found = false
  for _ in pairs(m.cds["Bob-Stone"] or {}) do found = true end
  assert(found, "the cast of a late-known spell wasn't tracked")
  return "late spell data ok"
end""")(cmod))

# preview: every team member gets a row, made-up states that stay the same between redraws
print("A:", A.eval(r"""function(m)
  local old = MMT.IsOnline
  MMT.IsOnline = function() return false end
  m.M.db.onlyOnline = true
  local before = #m.Members()
  m.SetPreview(true)
  local members = m.Members()
  assert(#members >= 2 and #members > before - 1, "preview rows: " .. #members)
  local seen = {}
  for _, key in ipairs(members) do
    for _, e in ipairs(m.EntriesFor(key)) do
      local s1, st1 = m.State(key, e)
      local s2, st2 = m.State(key, e)
      assert(s1 == s2 and st1 == st2, "preview state changed between redraws")
      assert(s1 == "ready" or s1 == "cd", "preview state " .. tostring(s1))
      seen[s1] = true
    end
  end
  assert(seen.ready and seen.cd, "preview shows only one kind of state")
  m.SetPreview(false)
  assert(#m.Members() == before, "preview not switched off")
  MMT.IsOnline = old
  return "preview ok"
end""")(amod))

# preview with mixed classes: you a warrior, the next a paladin, ... and their class lists
print("A:", A.eval(r"""function(m)
  m.SetPreview("MIXED")
  local own = MMT.PlayerFull()
  assert(m.ClassOf(own) == "WARRIOR", "own preview class " .. tostring(m.ClassOf(own)))
  local others = {}
  for _, key in ipairs(MMT.SortedMembers()) do if not MMT.IsSelf(key) then others[#others + 1] = m.ClassOf(key) end end
  assert(#others > 0 and others[1] ~= "WARRIOR", "members all warriors")
  local warrior = 0
  for _, e in ipairs(m.EntriesFor(own)) do if e.t == "s" and e.id == 1719 then warrior = warrior + 1 end end
  assert(warrior == 1, "warrior list (Recklessness) not used for the preview warrior")
  m.SetPreview(nil)
  assert(m.ClassOf(own) ~= "WARRIOR" or select(2, UnitClass("player")) == "WARRIOR", "class still made up after the preview")
  m.SetPreview(true)
  assert(m.preview == "REAL", "true = the team as it is")
  m.SetPreview(nil)
  return "mixed preview ok"
end""")(amod))


# "Hide what you don't have" across clients: Anna hasn't learned Ice Block; Bob's bar hides it on her row
print("A:", A.eval(r"""function(m)
  UNLEARNED = { ["Ice Block"] = true }
  m.M.db.lists.MAGE = m.M.db.lists.MAGE or {}
  local has
  for _, e in ipairs(m.M.db.lists.MAGE) do if e.id == 11958 then has = true; e.off = nil end end
  if not has then table.insert(m.M.db.lists.MAGE, { t = "s", id = 11958, cd = 300 }) end
  LONG = {}
  m.KnownCheck()
  assert(#LONG == 1 and LONG[1].msg:find("^MCDK:") and LONG[1].msg:find("11958", 1, true), "unlearned list: " .. tostring(LONG[1] and LONG[1].msg))
  m.KnownCheck()
  assert(#LONG == 1, "sent again without a change")
  HB = HEARTBEATS.cdk()
  assert(type(HB) == "number", "heartbeat hash")
  return "unlearned sent"
end""")(amod))
msgs = take(A, "LONG")
hb = A.eval('function() return HB end')()
deliver("Anna-Smith", msgs, B)
print("B:", B.eval(r"""function(m, hb)
  m.M.db.lists.MAGE = m.M.db.lists.MAGE or {}
  local iceblock
  for _, e in ipairs(m.M.db.lists.MAGE) do if e.id == 11958 then iceblock = e end end
  if not iceblock then iceblock = { t = "s", id = 11958, cd = 300 }; table.insert(m.M.db.lists.MAGE, iceblock) end
  iceblock.off = nil
  m.M.db.hideUnknown = true
  assert(m.State("Anna-Smith", iceblock) == nil, "Ice Block shown for Anna who hasn't learned it")
  m.M.db.hideUnknown = false
  assert(m.State("Anna-Smith", iceblock) ~= nil, "hidden with the option off")
  m.M.db.hideUnknown = true
  -- the heartbeat hash matches what we have: no question
  WHISPERS = {}
  for _, fn in ipairs(LISTEN.XP_RECEIVED) do fn("Anna-Smith", "Anna", { ext = { cdk = tostring(hb) } }) end
  assert(#WHISPERS == 0, "asked although the list matches")
  -- a different hash (she learned something meanwhile): ask once
  for _, fn in ipairs(LISTEN.XP_RECEIVED) do fn("Anna-Smith", "Anna", { ext = { cdk = "12345" } }) end
  for _, fn in ipairs(LISTEN.XP_RECEIVED) do fn("Anna-Smith", "Anna", { ext = { cdk = "12345" } }) end
  assert(#WHISPERS == 1 and WHISPERS[1].msg == "MCDKQ", "no / repeated question")
  -- someone who never sent a list: everything shows
  assert(m.Unlearned("Carl-Nobody", iceblock) == false, "unknown member")
  return "unlearned hidden on other clients"
end""")(bmod, hb))
print("A:", A.eval(r"""function(m)
  LONG = {}
  DELIVER("Bob-Stone", "MCDKQ")
  assert(#LONG == 1 and LONG[1].to == "Bob-Stone" and LONG[1].msg:find("^MCDK:"), "no answer to MCDKQ")
  -- she learns it: the next check sends the shorter list
  UNLEARNED = {}
  LONG = {}
  m.KnownCheck()
  assert(#LONG == 1 and not LONG[1].msg:find("11958", 1, true), "learned spell still sent as unlearned")
  return "MCDKQ + learning ok"
end""")(amod))

# renamed module (was "Cooldowns"): once per profile its settings and storage are taken over
print("B:", B.eval(r"""function(m)
  local db = m.M.db
  db.takenFrom = nil
  db.iconSize = 28
  MMT.db.modules = { Cooldowns = { iconSize = 51, lists = { MAGE = { { t = "s", id = 12042, cd = 180 } } } } }
  MMTDB = { moduleData = { Cooldowns = { races = { ["Old-Char"] = "Orc" } } } }
  m.M.store.takenFrom = nil
  m.TakeOver()
  assert(m.M.db == db, "settings table replaced (the core holds it)")
  assert(db.iconSize == 51 and #db.lists.MAGE == 1 and db.takenFrom == "Cooldowns", "not taken over")
  assert(db.scale ~= nil, "defaults missing after the takeover")
  assert(m.M.store.races["Old-Char"] == "Orc" and m.M.store.takenFrom == "Cooldowns", "storage not taken over")
  -- only once: later changes stay
  db.iconSize = 30
  m.TakeOver()
  assert(db.iconSize == 30, "taken over twice")
  MMT.db.modules = nil
  MMTDB = nil
  return "takeover ok"
end""")(bmod))

# spec presets (Wowhead Forever guides): every class has its specs, no old class presets;
# the class default = every spec's entries, on when on in any spec
print("A:", A.eval(r"""function(m)
  local specs = {}
  for _, p in ipairs(m.PRESETS) do
    if p.group ~= "RACE" and p.group ~= "ALL" then
      specs[p.group] = (specs[p.group] or 0) + 1
      assert(not p.key:find(":REC$") and not p.key:find(":MAJOR$"), "old class preset " .. p.key)
    end
  end
  for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK" }) do
    assert(specs[c] == 3, c .. " specs: " .. tostring(specs[c]))
  end
  assert(specs.DRUID == 4, "druid: balance, cat, bear, resto")
  local ret = m.PresetByKey("PALADIN:RET")
  assert(ret and ret.name == "Paladin: Retribution", "ret preset")
  local on, off = {}, {}
  for _, e in ipairs(ret.entries) do if e.off then off[e.id] = e.cd else on[e.id] = e.cd end end
  assert(on[10310] == 1200 and on[1020] == 300 and on[20066] == 60 and off[10333] == 10 and off[20271] == 10, "ret entries")
  local def = {}
  for _, e in ipairs(m.DEFAULT_LISTS.PALADIN) do assert(not def[e.id], "double " .. e.id); def[e.id] = e end
  assert(def[20216] and not def[20216].off, "Divine Favor (holy) on in the class default")
  assert(def[10333] and def[10333].off, "Holy Strike on in the class default")
  assert(m.PresetByKey("WARRIOR:PROT") and select(2, (function()
    for _, e in ipairs(m.PresetByKey("WARRIOR:PROT").entries) do if e.id == 12975 then return true, e.cd end end end)()) == 180, "Last Stand 3 min")
  return "spec presets ok"
end""")(amod))

# a member's real cooldown length (talents): their message wins over their cast seen
# right after it, and is used for their next cast seen before any message
print("C:", C.eval(r"""function(m)
  NOW = 2000
  m.cds["Bob-Stone"] = {}
  DELIVER("Bob-Stone", "MCDU:s55555:45.0/45.0")      -- talented: 45 s instead of the list's 60
  FIRE("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 55555)
  local c = m.cds["Bob-Stone"]["s55555"]
  assert(c and c.dur == 45, "the cast replaced the real length: " .. tostring(c and c.dur))
  NOW = 2100
  FIRE("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 55555)
  c = m.cds["Bob-Stone"]["s55555"]
  assert(c and c.dur == 45 and c.start == 2100, "next cast doesn't use the remembered length: " .. tostring(c and c.dur))
  assert(m.MemberDuration("Alice-Nobody", { t = "s", id = 55555, cd = 60 }) == 60, "others: list seconds")
  return "real cooldown lengths ok"
end""")(cmod))
