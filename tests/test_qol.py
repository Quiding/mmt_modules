"""MMT_QoL: two clients, Anna and Bob, each with stand-ins for Dejunk (its saved
state + DejunkApi listener, and its in-memory list copy that it saves over the
state) and Baganator (its profile config + API). Changes on one reach the
other, changes taken are not sent back, bulk changes aren't sent.
ForeverAuras: a stand-in ForeverAurasAPI (GetAuras / ExportAura / DecodeAuraString /
ImportAura, refusing while another import window is open or in combat): one aura, a
group in two parts delivered out of order, "all" to the team, ask / straight import,
waiting for an open import window and for combat, "only the FTL leader".
EllesmereUI: a stand-in with its profile export / interactive import / full account
functions: a profile in parts, a busy import page, the full account always asked and
confirmed in its own popup, straight import without ask.
SmartBuff: its alert function hooked, once a minute per target + buff, shown on the
leader / everyone / nowhere."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
EVENTS, LISTEN, SENT, PRINTS, DIALOG, REFRESHED, IMPORTED, SLASHED = {}, {}, {}, {}, nil, 0, nil, nil
LOADED = { Dejunk = true, Baganator = true }
MMT = {
  CopyTable = copy, IsSecret = function() return false end, UI = {},
  ConfigHelpers = { COL_W = 330, COL2_X = 366, PAGE_W = 698 },
  ToggleConfig = function() end,
}
function MMT.Print(fmt, ...) PRINTS[#PRINTS + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
function MMT.SendToTeam(msg) assert(#msg < 250, "message too long: " .. #msg); SENT[#SENT + 1] = msg end
function MMT.SendLong(msg) SENT[#SENT + 1] = msg end
function MMT.UI.Confirm(text, accept, onAccept, cancel, onCancel) DIALOG = { text = text, ok = onAccept, no = onCancel } end
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On(ev, fn) local old = EVENTS[ev]; EVENTS[ev] = old and function(...) old(...); fn(...) end or fn end
  function M:Listen(ev, fn) LISTEN[ev] = fn end
  function M:Debug() end
  return M
end
function DELIVER(from, msg) LISTEN.TEAM_MESSAGE(from, from, msg) end
RELOADS, COMBAT = 0, false
C_UI = { Reload = function() RELOADS = RELOADS + 1 end }
function InCombatLockdown() return COMBAT end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
C_AddOns = {
  IsAddOnLoaded = function(n) return LOADED[n] == true end,
  GetAddOnInfo = function(n) return n, n, "", false, LOADED[n] == nil and "MISSING" or "DISABLED" end,
}
C_Item = { GetItemInfo = function(id) if id == 2589 then return "Linen Cloth", "[Linen Cloth]" end end }
function UnitName() return (ME:match("^[^-]+")) end
function GetNormalizedRealmName() return "Realm" end
SlashCmdList = {}

-- Dejunk: state in its saved variable (rewritten as a shallow copy on every
-- change, the list tables are the store's), and its own copy of the lists
DJ_LISTENERS = {}
DejunkApi = { Events = { StateUpdated = "StateUpdated", BagsUpdated = "BagsUpdated" } }
function DejunkApi:AddListener(fn) DJ_LISTENERS[#DJ_LISTENERS + 1] = fn end
local function set(...) local t = {} for _, v in ipairs({...}) do t[tostring(v)] = true end return t end
DJ = { global = { inclusions = set(), exclusions = set() },
       profiles = { characterMap = {}, profileMap = {
         DEFAULT_PROFILE = { settings = { inclusions = set(), exclusions = set() } },
         other = { settings = { inclusions = set(111, 112), exclusions = set() } } } } }
DJ_CACHE = { GI = {}, GE = {}, PI = {}, PE = {} }   -- what Dejunk's list objects hold
local function where(k)
  local p = DJ.profiles.profileMap[DJ.profiles.characterMap[UnitName() .. "-Realm"] or "DEFAULT_PROFILE"].settings
  if k == "GI" then return DJ.global, "inclusions" elseif k == "GE" then return DJ.global, "exclusions"
  elseif k == "PI" then return p, "inclusions" else return p, "exclusions" end
end
function DJ_FIRE()
  local sv = copy(DJ); sv.global = DJ.global; sv.profiles = { characterMap = DJ.profiles.characterMap, profileMap = DJ.profiles.profileMap }
  __DEJUNK_ADDON_V3_SAVED_VARIABLES__ = sv
  for _, fn in ipairs(DJ_LISTENERS) do fn("StateUpdated") end
end
-- like Dejunk's Lists:Add: on the list, off the opposite, each list saves a copy of its own items
local OPP = { GI = "GE", GE = "GI", PI = "PE", PE = "PI" }
function DJ_SAVE(k) local t, f = where(k); t[f] = copy(DJ_CACHE[k]) end
function DJ_ADD(k, id) id = tostring(id); DJ_CACHE[k][id] = true; DJ_CACHE[OPP[k]][id] = nil; DJ_SAVE(OPP[k]); DJ_SAVE(k); DJ_FIRE() end
function DJ_DEL(k, id) DJ_CACHE[k][tostring(id)] = nil; DJ_SAVE(k); DJ_FIRE() end
function DJ_HAS(k, id) local t, f = where(k); return t[f][tostring(id)] == true end
-- Dejunk's hidden key binding buttons: the item in GameTooltip on / off a list (like its Lists:Add / :Remove)
NOW = 1000
function GetTime() return NOW end
TIP = { shown = false }
GameTooltip = {
  SetOwner = function(_, owner) TIP.owner = owner; TIP.item = nil; TIP.shown = true end,
  SetItemByID = function(_, id) TIP.item = id end,
  GetItem = function() if TIP.item then return "x", "item:" .. TIP.item end end,
  Hide = function() TIP.shown = false; TIP.item = nil end,
  IsShown = function() return TIP.shown end,
  GetOwner = function() return TIP.owner end,
}
UIParent = {}
CLICKS = 0
function DJ_BUTTONS()
  local names = { GI = "GlobalInclusions", GE = "GlobalExclusions", PI = "ProfileInclusions", PE = "ProfileExclusions" }
  for k, n in pairs(names) do
    _G["DejunkKeybinding_addTo" .. n] = { Click = function()
      CLICKS = CLICKS + 1; assert(TIP.item, "no item in the tooltip")
      if not DJ_CACHE[k][tostring(TIP.item)] then DJ_ADD(k, TIP.item) end end }
    _G["DejunkKeybinding_removeFrom" .. n] = { Click = function()
      CLICKS = CLICKS + 1; assert(TIP.item, "no item in the tooltip")
      if DJ_CACHE[k][tostring(TIP.item)] then DJ_DEL(k, TIP.item) end end }
  end
end

-- Baganator: profile config, its Config.Set stores a copy
BAGANATOR_CURRENT_PROFILE = "DEFAULT"
BAGANATOR_CONFIG = { Profiles = { DEFAULT = { category_modifications = {}, custom_categories = {},
  category_display_order = { "default_junk" }, category_sections = {}, category_hidden = {} } } }
function BG() return BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE] end
function BG_MOVE(item, from, to)   -- like Baganator's CategoryAddItemEnd
  local mods = BG().category_modifications
  if from and mods[from] and mods[from].addedItems then mods[from].addedItems[item] = nil end
  if to then mods[to] = mods[to] or {}; mods[to].addedItems = mods[to].addedItems or {}; mods[to].addedItems[item] = true end
  BG().category_modifications = copy(mods)
end
function BG_IN(src, item) local m = BG().category_modifications[src]; return m and m.addedItems and m.addedItems[item] == true or false end
Baganator = { API = {
  RequestItemButtonsRefresh = function() REFRESHED = REFRESHED + 1 end,
  RequestLayoutUpdate = function() end,
  ImportString = function(text) IMPORTED = text end,
} }
SlashCmdList.Baganator = function(msg) SLASHED = msg end
C_EncodingUtil = { SerializeCBOR = function(t) assert(t.addon == "Baganator" and t.kind == "categories"); return "cbor" end,
  CompressString = function(s) return s .. "z" end, EncodeBase64 = function(s) return "QUJD" end }
'''

def client(me):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('ME = "%s"' % me)
    lua.execute(STUBS)
    mod = lua.eval('{}')
    toc = [l.strip() for l in open('MMT_QoL/MMT_QoL.toc', encoding='utf-8') if l.strip().endswith('.lua')]
    for f in toc:
        src = open('MMT_QoL/' + f, encoding='utf-8').read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, 'MMT_QoL/' + f, mod)
    # at load (before Dejunk reads its saved variables at login) the unbound add / remove bindings got a chord
    print(lua.eval(r'''function(m)
      local kb = __DEJUNK_ADDON_V3_SAVED_VARIABLES__.global.keybindings
      assert(kb.addToGlobalInclusions == "ALT-CTRL-SHIFT-F13" and kb.removeFromProfileExclusions == "ALT-CTRL-SHIFT-F20", "chords")
      assert(kb.toggleMainWindow == nil, "touched another binding")
      return ME .. ": Dejunk bindings got their chords"
    end''')(mod))
    lua.eval('function(m) m.M.OnEnable(m.M); DJ_FIRE(); m.BaganatorTick() end')(mod)
    return lua, mod

A, amod = client("Anna-Smith")
B, bmod = client("Bob-Stone")

def take(lua):
    msgs = lua.eval('function() local t = SENT; SENT = {} return t end')()
    return [msgs[i] for i in range(1, len(msgs) + 1)]

def deliver(msgs, lua, frm):
    for m in msgs: lua.eval('DELIVER')(frm, m)

def run(lua, mod, code):
    print(lua.eval(code)(mod))

# --- Dejunk -------------------------------------------------------------
run(B, bmod, r'''function(m)
  DJ_ADD("GI", 2589)
  assert(#SENT == 1 and SENT[1] == "QDJ:+GI2589", "add: " .. tostring(SENT[1]))
  return "Bob: added Linen Cloth to junk, sent"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(DJ_HAS("GI", 2589), "not on Anna's junk list")
  assert(PRINTS[#PRINTS]:find("[Linen Cloth] to junk (global)", 1, true), "chat: " .. tostring(PRINTS[#PRINTS]))
  -- taken changes are not sent back
  DJ_FIRE(); assert(#SENT == 0, "echo: " .. tostring(SENT[1]))
  -- Anna's Dejunk saves its own copy (without 2589) when she adds an item: 2589 is put back, only hers is sent
  DJ_ADD("GI", 999)
  assert(DJ_HAS("GI", 2589) and DJ_HAS("GI", 999), "Dejunk's save lost the team's item")
  assert(#SENT == 1 and SENT[1] == "QDJ:+GI999", "after Dejunk's save: " .. table.concat(SENT, " | "))
  return "Anna: taken, kept over Dejunk's own save, no echo"
end''')
deliver(take(A), B, "Anna-Smith")
run(B, bmod, r'''function(m)
  assert(DJ_HAS("GI", 999), "Bob didn't take 999")
  -- moved to "not junk": one "+" (Dejunk takes it off junk itself)
  DJ_ADD("GE", 2589)
  assert(#SENT == 1 and SENT[1] == "QDJ:+GE2589", "move: " .. table.concat(SENT, " | "))
  return "Bob: moved to not junk"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(DJ_HAS("GE", 2589) and not DJ_HAS("GI", 2589), "move not mirrored")
  DJ_FIRE(); assert(#SENT == 0, "echo after move")
  return "Anna: moved too"
end''')
run(B, bmod, r'''function(m)
  -- 999 came from Anna: Bob's Dejunk doesn't know it until a /reload, so Dejunk saving
  -- its copy (without 999) is no removal
  DJ_ADD("GI", 1234)
  assert(DJ_HAS("GI", 999) and #SENT == 1 and SENT[1] == "QDJ:+GI1234", "own save dropped 999: " .. table.concat(SENT, " | "))
  SENT = {}
  -- after a /reload Dejunk knows it (and our "pending" is gone): a real removal
  DJ_CACHE.GI["999"] = true
  m.DejunkReloaded()
  DJ_DEL("GI", 999)
  assert(#SENT == 1 and SENT[1] == "QDJ:-GI999", "remove: " .. table.concat(SENT, " | "))
  return "Bob: Dejunk's own save kept 999, removal after reload sent"
end''')
msgs = take(B)
run(A, amod, r'''function(m)
  m.M.db.djRemove = false
  return "Anna: removals off"
end''')
deliver(msgs, A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(DJ_HAS("GI", 999), "removal taken while off")
  m.M.db.djRemove = true
  -- ask first: a dialog, applied on accept
  m.M.db.djAsk = true
  DELIVER("Bob-Stone", "QDJ:-GI999")
  assert(DIALOG and DIALOG.text:find("Bob Stone sent 1 Dejunk lists change", 1, true), "no dialog: " .. tostring(DIALOG and DIALOG.text))
  assert(DJ_HAS("GI", 999), "applied before asking")
  DIALOG.ok(); assert(not DJ_HAS("GI", 999), "not applied on accept")
  DIALOG = nil
  m.M.db.djAsk = false
  return "Anna: removal option + ask ok"
end''')
run(B, bmod, r'''function(m)
  -- many at once (an import): not sent
  for i = 1, 11 do DJ_CACHE.GI[tostring(5000 + i)] = true end
  DJ_SAVE("GI"); DJ_FIRE()
  assert(#SENT == 0, "bulk sent")
  assert(PRINTS[#PRINTS]:find("11 Dejunk list changes", 1, true), "no bulk note")
  -- another profile: its lists are no change
  DJ.profiles.characterMap["Bob-Realm"] = "other"; DJ_FIRE()
  assert(#SENT == 0, "profile switch sent: " .. tostring(SENT[1]))
  DJ.profiles.characterMap["Bob-Realm"] = nil; DJ_FIRE()
  assert(#SENT == 0, "profile switch back sent")
  -- profile lists on, the whole lists once
  DJ_ADD("PI", 777); SENT = {}
  local f
  for _, x in ipairs(m.features) do if x.key == "dejunk" then f = x end end
  assert(f.commands.send())
  assert(#SENT == 1 and SENT[1]:find("^QDJL:GI=") and SENT[1]:find("PI=777", 1, true), "send all: " .. tostring(SENT[1]))
  return "Bob: bulk not sent, profile switch quiet, whole lists sent"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(DJ_HAS("GI", 5001) and DJ_HAS("GI", 5011) and DJ_HAS("PI", 777), "merge")
  assert(DJ_HAS("GE", 2589), "merge removed something")
  DJ_FIRE(); assert(#SENT == 0, "merge echoed")
  -- profile lists off: a PI change is neither taken nor sent
  m.M.db.djProfile = false
  DELIVER("Bob-Stone", "QDJ:+PI888"); assert(not DJ_HAS("PI", 888), "profile change taken while off")
  DJ_ADD("PI", 889); assert(#SENT == 0, "profile change sent while off")
  m.M.db.djProfile = true
  -- Dejunk not loaded: nothing taken, the feature reads as off
  LOADED.Dejunk = false
  DELIVER("Bob-Stone", "QDJ:+GI4444"); assert(not DJ_HAS("GI", 4444), "taken without Dejunk")
  assert(m.Active(m.features[1]) == false, "active without Dejunk")
  local ok, why = m.AddonState("Dejunk"); assert(not ok and why:find("switched off"), tostring(why))
  LOADED.Dejunk = nil; ok, why = m.AddonState("Dejunk"); assert(why:find("not installed"), tostring(why))
  LOADED.Dejunk = true
  -- the push again: everything is there, the line says Dejunk shows it after a reload
  DELIVER("Bob-Stone", "QDJL:GI=5001;GE=;PI=;PE=")
  assert(PRINTS[#PRINTS]:find("have them all already", 1, true) and PRINTS[#PRINTS]:find("/reload", 1, true), "nothing new line: " .. PRINTS[#PRINTS])
  return "Anna: merged, profile option, missing addon ok"
end''')
run(B, bmod, r'''function(m)
  -- Bob took nothing since his reload: the team reload leaves him alone, Anna (who took changes) reloads
  assert(m.features[1].commands.reload() and SENT[#SENT] == "QDJR:", "reload not sent")
  SENT = {}
  DELIVER("Anna-Smith", "QDJR:"); assert(RELOADS == 0, "Bob reloaded without changes")
  return "Bob: asked the team to reload"
end''')
run(A, amod, r'''function(m)
  COMBAT = true
  DELIVER("Bob-Stone", "QDJR:"); assert(RELOADS == 0, "reloaded in combat")
  COMBAT = false; EVENTS.PLAYER_REGEN_ENABLED(); assert(RELOADS == 1, "no reload after combat")
  DELIVER("Bob-Stone", "QDJR:"); assert(RELOADS == 2, "no reload")
  return "Anna: reloads for Dejunk (after combat)"
end''')

# --- Dejunk right away, through its key binding buttons --------------------
run(A, amod, r'''function(m)
  DJ_BUTTONS(); SENT = {}; PRINTS = {}
  DELIVER("Bob-Stone", "QDJ:+GI3000")
  assert(CLICKS == 1 and DJ_CACHE.GI["3000"] and DJ_HAS("GI", 3000), "not added through Dejunk")
  assert(not PRINTS[#PRINTS]:find("/reload", 1, true), "still says reload: " .. PRINTS[#PRINTS])
  assert(#SENT == 0, "echo: " .. tostring(SENT[1]))
  assert(not TIP.shown, "tooltip left open")
  -- moved to not junk: Dejunk takes it off junk itself, nothing sent back
  DELIVER("Bob-Stone", "QDJ:+GE3000")
  assert(DJ_CACHE.GE["3000"] and not DJ_CACHE.GI["3000"] and #SENT == 0, "move: " .. tostring(SENT[1]))
  DELIVER("Bob-Stone", "QDJ:-GE3000")
  assert(not DJ_CACHE.GE["3000"] and not DJ_HAS("GE", 3000) and #SENT == 0, "remove")
  -- the player hovers something: waits, then does it anyway
  TIP.shown, TIP.owner = true, "SomeBagSlot"
  DELIVER("Bob-Stone", "QDJ:+GI3001")
  assert(DJ_CACHE.GI["3001"], "never applied while the tooltip was up")
  -- one sent by a team member before the buttons (in the saved state only): the push now puts it into Dejunk
  assert(DJ_HAS("GI", 5011) and not DJ_CACHE.GI["5011"], "setup")
  DELIVER("Bob-Stone", "QDJL:GI=5011;GE=;PI=;PE=")
  assert(DJ_CACHE.GI["5011"] and #SENT == 0, "pending item not pushed into Dejunk")
  -- Anna's own change still goes out
  DJ_ADD("GI", 3002); assert(#SENT == 1 and SENT[1] == "QDJ:+GI3002", "own change: " .. tostring(SENT[1]))
  -- option off: the saved state again
  m.M.db.djLive = false; SENT = {}
  local c = CLICKS
  DELIVER("Bob-Stone", "QDJ:+GI3003")
  assert(CLICKS == c and DJ_HAS("GI", 3003) and not DJ_CACHE.GI["3003"], "used the button while off")
  m.M.db.djLive = true
  return "Anna: changes go into Dejunk right away, no echo"
end''')

# --- Baganator ----------------------------------------------------------
# (the Junk <-> Dejunk link is tested on its own at the end)
for lua, mod in ((A, amod), (B, bmod)):
    lua.eval('function(m) m.M.db.junkLink = false end')(mod)
run(B, bmod, r'''function(m)
  SENT = {}
  BG().custom_categories["1"] = { name = "Trash; mine", search = "" }
  BG_MOVE("i:2589", nil, "default_junk"); m.BaganatorTick()
  assert(#SENT == 1 and SENT[1] == "QBG:+i:2589=default_junk", "add: " .. tostring(SENT[1]))
  return "Bob: put Linen Cloth into Junk"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(BG_IN("default_junk", "i:2589"), "not in Anna's Junk")
  assert(REFRESHED > 0, "no redraw")
  m.BaganatorTick(); for i = 1, 5 do m.BaganatorTick() end
  assert(#SENT == 0, "echo: " .. tostring(SENT[1]))
  BG().custom_categories["3"] = { name = "Trash; mine", search = "" }
  return "Anna: in Junk, redrawn, no echo"
end''')
run(B, bmod, r'''function(m)
  -- a move to a custom category: out of Junk, into it by name
  BG_MOVE("i:2589", "default_junk", "1"); m.BaganatorTick()
  assert(#SENT == 1 and SENT[1] == "QBG:-i:2589=default_junk;+i:2589=c:Trash%3B mine", "move: " .. tostring(SENT[1]))
  return "Bob: moved to his custom category"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(BG_IN("3", "i:2589") and not BG_IN("default_junk", "i:2589"), "move not mirrored by name")
  m.BaganatorTick(); assert(#SENT == 0, "echo after move")
  -- Junk only: other categories are neither taken nor sent
  m.M.db.bgScope = "JUNK"
  DELIVER("Bob-Stone", "QBG:+i:3000=c:Trash%3B mine"); assert(not BG_IN("3", "i:3000"), "taken outside Junk")
  BG_MOVE("i:3001", nil, "3"); m.BaganatorTick(); assert(#SENT == 0, "sent outside Junk")
  m.M.db.bgScope = "ALL"
  -- a category this character doesn't have: a note, nothing else
  DELIVER("Bob-Stone", "QBG:+i:3002=c:Nope"); assert(PRINTS[#PRINTS]:find("\"Nope\"", 1, true), "no missing note")
  -- Baganator's own copy keeps what was taken
  BG_MOVE("i:3003", nil, "default_junk"); m.BaganatorTick()
  assert(BG_IN("3", "i:2589") and #SENT == 1 and SENT[1] == "QBG:+i:3003=default_junk", "after own change: " .. tostring(SENT[1]))
  return "Anna: scope + missing category ok"
end''')
deliver(take(A), B, "Anna-Smith")
run(B, bmod, r'''function(m)
  assert(BG_IN("default_junk", "i:3003"), "Bob didn't take 3003")
  -- many at once: not sent
  for i = 1, 11 do BG().category_modifications.default_junk.addedItems["i:" .. (6000 + i)] = true end
  BG().category_modifications = MMT.CopyTable(BG().category_modifications); m.BaganatorTick()
  assert(#SENT == 0, "bulk sent")
  -- another Baganator profile: quiet
  BAGANATOR_CONFIG.Profiles.Other = { category_modifications = { default_junk = { addedItems = { ["i:1"] = true } } } }
  BAGANATOR_CURRENT_PROFILE = "Other"; m.BaganatorTick(); assert(#SENT == 0, "profile switch sent")
  BAGANATOR_CURRENT_PROFILE = "DEFAULT"; m.BaganatorTick(); assert(#SENT == 0, "profile switch back sent")
  local f
  for _, x in ipairs(m.features) do if x.key == "baganator" then f = x end end
  local ok, n = f.commands.send(); assert(ok and n >= 13, "send all " .. tostring(n))
  assert(SENT[1]:find("^QBGL:"), "send all tag")
  return "Bob: bulk quiet, profile switch quiet, all items sent (" .. n .. ")"
end''')
deliver(take(B), A, "Bob-Stone")
run(A, amod, r'''function(m)
  assert(BG_IN("default_junk", "i:6001") and BG_IN("3", "i:2589"), "merge")
  m.BaganatorTick(); assert(#SENT == 0, "merge echoed")
  return "Anna: merged Bob's category items"
end''')
run(B, bmod, r'''function(m)
  -- the whole setup through Baganator's own import
  local ok, n = m.BaganatorSendSetup()
  assert(ok and #SENT == 1 and SENT[1] == "QBGF:BGR!1!QUJD", "setup: " .. tostring(SENT[1]))
  SENT = {}
  local s = m.BaganatorExport(BG())
  assert(s.addon == "Baganator" and #s.categories == 1 and s.order[1] == "default_junk", "export table")
  local found
  for _, mm in ipairs(s.modifications) do if mm.source == "default_junk" then found = mm end end
  assert(found and #found.items >= 12, "export items")
  return "Bob: export table built like Baganator's"
end''')
run(A, amod, r'''function(m)
  DELIVER("Bob-Stone", "QBGF:BGR!1!QUJD")
  assert(DIALOG and DIALOG.text:find("whole Baganator category setup", 1, true), "setup not asked")
  assert(IMPORTED == nil, "imported before asking")
  DIALOG.ok()
  assert(IMPORTED == "BGR!1!QUJD" and SLASHED == "removeunusedcategories", "import " .. tostring(IMPORTED) .. " / " .. tostring(SLASHED))
  local n = 0
  m.M.Report(m.M, function() n = n + 1 end)
  assert(n == 6, "report lines " .. n)
  return "Anna: whole setup asked, imported, report ok"
end''')

# --- Junk link: Baganator's Junk <-> Dejunk's global junk list ------------
run(A, amod, r'''function(m)
  m.M.db.junkLink = true; SENT = {}
  local function sent(msg) for _, x in ipairs(SENT) do if x == msg then return true end end return false end
  -- into Baganator's Junk: on Dejunk's junk list (through its button), both sent
  BG_MOVE("i:3100", nil, "default_junk"); m.BaganatorTick()
  assert(DJ_CACHE.GI["3100"], "not on Dejunk's junk list")
  assert(sent("QBG:+i:3100=default_junk") and sent("QDJ:+GI3100"), "sent: " .. table.concat(SENT, " | "))
  -- off Dejunk's junk list: out of Baganator's Junk, both sent, nothing loops
  SENT = {}
  local clicks = CLICKS
  DJ_DEL("GI", 3100); m.BaganatorTick()
  assert(not BG_IN("default_junk", "i:3100"), "still in Baganator's Junk")
  assert(sent("QDJ:-GI3100") and sent("QBG:-i:3100=default_junk") and #SENT == 2, "sent: " .. table.concat(SENT, " | "))
  assert(CLICKS == clicks, "Dejunk clicked again")
  -- moved to "not junk" in Dejunk: out of Baganator's Junk too
  BG_MOVE("i:3104", nil, "default_junk"); m.BaganatorTick(); SENT = {}
  DJ_ADD("GE", 3104); m.BaganatorTick()
  assert(not BG_IN("default_junk", "i:3104") and sent("QBG:-i:3104=default_junk"), "move to not junk: " .. table.concat(SENT, " | "))
  -- out of Baganator's Junk into another category: off Dejunk's junk list
  BG_MOVE("i:3101", nil, "default_junk"); m.BaganatorTick(); SENT = {}
  BG_MOVE("i:3101", "default_junk", "3"); m.BaganatorTick()
  assert(not DJ_CACHE.GI["3101"] and sent("QDJ:-GI3101"), "moved out of Junk: " .. table.concat(SENT, " | "))
  -- link off: nothing on Dejunk
  m.M.db.junkLink = false; SENT = {}
  BG_MOVE("i:3102", nil, "default_junk"); m.BaganatorTick()
  assert(not DJ_CACHE.GI["3102"] and #SENT == 1, "linked while off")
  m.M.db.junkLink = true
  return "Anna: Junk <-> Dejunk junk list both ways, no loop"
end''')
run(B, bmod, r'''function(m)
  -- what the team changed is not linked again (the sender linked it already)
  m.M.db.junkLink = true; SENT = {}
  DELIVER("Anna-Smith", "QBG:+i:3103=default_junk"); m.BaganatorTick()
  DELIVER("Anna-Smith", "QDJ:-GI2589"); DJ_FIRE(); m.BaganatorTick()
  assert(BG_IN("default_junk", "i:3103") and not DJ_HAS("GI", 3103), "a taken change was linked")
  assert(#SENT == 0, "sent: " .. table.concat(SENT, " | "))
  return "Bob: taken changes not linked again"
end''')

# --- ForeverAuras: send auras -------------------------------------------
FA = r"""
LOADED.ForeverAuras = true
ONLINE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true, ["Cara-Moon"] = false }
function MMT.SortedMembers() return { "Anna-Smith", "Bob-Stone", "Cara-Moon" } end
function MMT.IsSelf(k) return k == ME end
function MMT.IsOnline(k) return ONLINE[k] == true end
function MMT.WhisperTarget(k) return (k:gsub("-", " ")) end
OUT = {}
function MMT.SendLong(msg, target) OUT[#OUT + 1] = { msg = msg, to = target, long = true } end
function MMT.SendAddon(msg, channel, target) assert(#msg < 250, "too long " .. #msg); OUT[#OUT + 1] = { msg = msg, to = target } end
function MMT.SendToTeam(msg) assert(#msg < 250, "too long " .. #msg); OUT[#OUT + 1] = { msg = msg } end
TIMERS = {}
C_Timer.After = function(_, fn) TIMERS[#TIMERS + 1] = fn end
function FLUSH() while #TIMERS > 0 do local t = TIMERS; TIMERS = {} for _, fn in ipairs(t) do fn() end end end
FA_AURAS = { ["Big group"] = { children = { "Child 1", "Child 2" } }, ["Child 1"] = { parent = "Big group" },
  ["Child 2"] = { parent = "Big group" }, ["Solo; one"] = {} }
local function hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function unhex(s) return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
IMPORTS, FA_OPEN = {}, nil
ForeverAurasAPI = {}
function ForeverAurasAPI:GetAuras() return FA_AURAS end
function ForeverAurasAPI:ExportAura(id)
  local a = FA_AURAS[id]
  if not a then return nil end
  return "!WA:2!" .. hex(id) .. "(" .. string.rep("a", a.children and 9000 or 100)
end
function ForeverAurasAPI:DecodeAuraString(s)
  local h = type(s) == "string" and s:match("^!WA:2!(%x+)%(")
  if not h then return nil end
  local id = unhex(h)
  return { m = "d", d = { id = id }, c = FA_AURAS[id] and FA_AURAS[id].children and { {}, {} } or nil }
end
function ForeverAurasAPI:ImportAura(s, cb)
  if COMBAT then return false, "in combat" end
  if FA_OPEN then return false, "another import is still open" end
  local d = self:DecodeAuraString(s)
  if not d then return false, "not an aura import string" end
  FA_OPEN = { id = d.d.id, cb = cb }
  IMPORTS[#IMPORTS + 1] = d.d.id
  return true
end
function FA_CLOSE(accepted) local o = FA_OPEN; FA_OPEN = nil; o.cb(accepted, accepted and o.id or nil) end
function TAKE() local t = OUT; OUT = {} return t end
function LAST() return PRINTS[#PRINTS] or "" end
"""
for lua in (A, B):
    lua.execute(FA)

def out(lua):
    t = lua.eval('TAKE')()
    return [(t[i].msg, t[i].to) for i in range(1, len(t) + 1)]

def deliver_to(msgs, lua, frm, order=None):
    for i in (order or range(len(msgs))): lua.eval('DELIVER')(frm, msgs[i][0])

run(A, amod, r"""function(m)
  local list = m.AuraList()
  assert(#list == 4 and list[1].id == "Big group" and list[1].group and list[1].inside == 2, "list 1")
  assert(list[2].depth == 1 and list[3].id == "Child 2" and list[4].id == "Solo; one" and list[4].depth == 0, "list order")
  local top = m.TopAuras(); assert(#top == 2 and top[1] == "Big group" and top[2] == "Solo; one", "top")
  local ok, why = m.SendAuras({ "Solo; one" }, "Cara-Moon"); assert(not ok and why:find("isn't online"), tostring(why))
  ok, why = m.SendAuras({ "Nope" }, "Bob-Stone"); assert(not ok and why:find("nothing to send"), tostring(why))
  ok, why = m.SendAuras({ "Solo; one" }, "Bob-Stone")
  assert(ok and why:find("\"Solo; one\"", 1, true) and why:find("Bob Stone", 1, true), tostring(why))
  assert(#OUT == 2 and OUT[1].msg:find("^QWAH:%d+:1:%d+:Solo%%3B one$") and OUT[1].to == "Bob Stone", "head: " .. OUT[1].msg)
  assert(OUT[2].long and OUT[2].to == "Bob Stone" and OUT[2].msg:find("^QWA:%d+:1:1:Solo%%3B one=!WA:2!"), "part: " .. OUT[2].msg)
  return "Anna: aura list, offline / unknown refused, one aura sent to Bob"
end""")
msgs = out(A)
deliver_to(msgs[:1], B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(LAST():find("Anna Smith is sending you 1 aura(s) (", 1, true) and LAST():find("Solo; one", 1, true), LAST())
  return "Bob: told it's coming"
end""")
deliver_to(msgs[1:], B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(DIALOG and DIALOG.text:find("Anna Smith sends you 1 ForeverAuras aura(s)", 1, true), "no dialog: " .. tostring(DIALOG and DIALOG.text))
  assert(DIALOG.text:find("Solo; one - you have one by this name", 1, true), DIALOG.text)
  assert(#IMPORTS == 0, "imported before asking")
  DIALOG.ok(); DIALOG = nil
  assert(#IMPORTS == 1 and IMPORTS[1] == "Solo; one", "not opened in ForeverAuras")
  assert(#OUT == 1 and OUT[1].msg:find("^QWAR:%d+:A$") and OUT[1].to == "Anna-Smith", "ack: " .. tostring(OUT[1] and OUT[1].msg))
  FA_CLOSE(true); FLUSH()
  assert(OUT[2].msg:find("^QWAR:%d+:D:1:1$"), "done reply: " .. tostring(OUT[2] and OUT[2].msg))
  assert(LAST():find("1 of 1 aura(s) from Anna Smith imported", 1, true), LAST())
  return "Bob: asked, imported through ForeverAuras' window, replied"
end""")
deliver_to(out(B), A, "Bob-Stone")
run(A, amod, r"""function(m)
  assert(PRINTS[#PRINTS - 1]:find("Bob Stone is importing", 1, true), PRINTS[#PRINTS - 1])
  assert(LAST():find("Bob Stone imported 1 of 1", 1, true), LAST())
  -- "all" to the online team: the group is 9 KB, so two parts
  ONLINE["Cara-Moon"] = true
  local ok, why = m.SendAuras(m.TopAuras())
  assert(ok and why:find("2 auras", 1, true) and why:find("online team (2)", 1, true), tostring(why))
  assert(#OUT == 3 and OUT[1].to == nil and OUT[1].msg:find("^QWAH:%d+:2:"), "team head")
  assert(OUT[2].msg:find("^QWA:%d+:1:2:") and OUT[3].msg:find("^QWA:%d+:2:2:") and OUT[3].to == nil, "parts")
  return "Anna: all auras to the team in 2 parts"
end""")
msgs = out(A)
run(B, bmod, r"""function(m)
  m.M.db.waAsk = false
  FA_OPEN = { id = "mine", cb = function() end }   -- Bob has an import window of his own open
  return "Bob: no ask, an import window already open"
end""")
deliver_to(msgs, B, "Anna-Smith", order=[0, 2, 1])
run(B, bmod, r"""function(m)
  assert(DIALOG == nil, "asked while ask is off")
  assert(#IMPORTS == 1 and LAST():find("waits until ForeverAuras' import window is free", 1, true), LAST())
  FA_OPEN = nil; FLUSH()
  assert(#IMPORTS == 2 and IMPORTS[2] == "Big group", "group not opened after the window closed")
  FA_CLOSE(false); FLUSH()
  assert(#IMPORTS == 3 and IMPORTS[3] == "Solo; one", "next one not opened")
  FA_CLOSE(true); FLUSH()
  local last = OUT[#OUT].msg
  assert(last:find("^QWAR:%d+:D:1:2$"), "done: " .. last)
  return "Bob: parts out of order, waited for his window, declined one, imported one"
end""")
out(B)
run(B, bmod, r"""function(m) COMBAT = true return "Bob: in combat" end""")
run(A, amod, r"""function(m) assert(m.SendAuras({ "Solo; one" }, "Bob-Stone")) return "Anna: sent again" end""")
deliver_to(out(A), B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(#IMPORTS == 3 and LAST():find("after combat", 1, true), LAST())
  COMBAT = false; EVENTS.PLAYER_REGEN_ENABLED()
  assert(#IMPORTS == 4, "not opened after combat")
  FA_CLOSE(true); FLUSH(); OUT = {}
  -- only the FTL leader may send
  m.M.db.waFrom = "LEADER"
  MMT.FTLLeader = function() return "Cara-Moon" end
  return "Bob: opened after combat; only the leader may send now"
end""")
run(A, amod, r"""function(m) assert(m.SendAuras({ "Solo; one" }, "Bob-Stone")) return "Anna: sent once more" end""")
deliver_to(out(A), B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(#IMPORTS == 4 and DIALOG == nil, "taken from a non-leader")
  assert(LAST():find("only the FTL leader may", 1, true), LAST())
  assert(OUT[1].msg:find("^QWAR:%d+:N:only the FTL leader"), "refusal reply")
  local n = 0
  m.M.Report(m.M, function(l) if l:find("^ForeverAuras:") then n = n + 1; assert(l:find("imported=3", 1, true), l) end end)
  assert(n == 1, "report")
  -- ForeverAuras not loaded: off, nothing sent
  LOADED.ForeverAuras = false
  local ok, why = m.SendAuras({ "Solo; one" }, "Anna-Smith"); assert(not ok and why:find("switched off"), tostring(why))
  return "Bob: refused a non-leader, report ok, off without ForeverAuras"
end""")
deliver_to(out(B), A, "Bob-Stone")
run(A, amod, r"""function(m)
  assert(LAST():find("Bob Stone didn't take the auras: only the FTL leader", 1, true), LAST())
  return "Anna: heard Bob's refusal"
end""")
run(B, bmod, r"""function(m)
  LOADED.ForeverAuras = true; m.M.db.waFrom = "TEAM"; m.M.db.waAsk = true; OUT = {}
  return "Bob: anyone may send, asks again"
end""")
run(A, amod, r"""function(m) assert(m.SendAuras({ "Big group" }, "Bob-Stone")) return "Anna: sent the group" end""")
deliver_to(out(A), B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(DIALOG and DIALOG.text:find("Big group (group, 2 inside)", 1, true), "group line: " .. tostring(DIALOG and DIALOG.text))
  DIALOG.no(); DIALOG = nil; FLUSH()
  assert(#IMPORTS == 4 and OUT[1].msg:find("^QWAR:%d+:N:ignored$"), "ignore reply: " .. tostring(OUT[1] and OUT[1].msg))
  return "Bob: ignored the group, Anna is told"
end""")
run(A, amod, r"""function(m)
  LOADED.ForeverAuras = true
  local function ids() local t = {} for _, r in ipairs(m.AurasRows()) do t[#t + 1] = r.id end return table.concat(t, ",", 2) end
  assert(ids() == "Big group,Solo; one", "closed: " .. ids())
  m.AurasToggle("Big group")
  assert(ids() == "Big group,Child 1,Child 2,Solo; one", "open: " .. ids())
  m.AurasToggle("Big group")
  assert(ids() == "Big group,Solo; one", "closed again: " .. ids())
  return "Anna: send window groups start closed, open and close"
end""")
run(A, amod, r"""function(m)
  -- loaded / not loaded like ForeverAuras' own list (a group counts as loaded when any aura inside it is)
  ForeverAuras = { IsAuraLoaded = function(id) if id == "Solo; one" then return false end end }   -- false = standby = loaded section
  local function ids() local t = {} for _, r in ipairs(m.AurasRows()) do t[#t + 1] = (r.id:gsub("\001", "#")) end return table.concat(t, ",", 2) end
  assert(ids() == "#loaded,Solo; one,#unloaded,Big group", "sections: " .. ids())
  local rows = m.AurasRows(); assert(rows[2].header and rows[2].text == "Loaded (1)" and rows[4].text == "Not loaded (1)", "headers")
  m.AurasToggle("\001loaded")
  assert(ids() == "#loaded,#unloaded,Big group", "loaded closed: " .. ids())
  m.AurasToggle("\001loaded"); m.AurasToggle("Big group")
  assert(ids() == "#loaded,Solo; one,#unloaded,Big group,Child 1,Child 2", "group open: " .. ids())
  local top = m.TopAuras(); assert(#top == 2 and top[1] == "Solo; one" and top[2] == "Big group", "top")
  ForeverAuras = nil
  return "Anna: send window sorted into Loaded / Not loaded, sections close"
end""")

# --- EllesmereUI: send profiles ------------------------------------------
EU = r"""
LOADED.EllesmereUI = true
local function hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function unhex(s) return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
EUI_IMPORTS, EUI_SESSION, EUI_POPUP, EUI_FULL_DONE = {}, nil, nil, 0
EllesmereUI = {}
function EllesmereUI.GetProfileList() return { "Default", "Healer; mine", "Gone" }, { Default = {}, ["Healer; mine"] = {} } end
function EllesmereUI.GetActiveProfileName() return "Healer; mine" end
function EllesmereUI.ExportProfile(name) return "!EUI_P" .. hex(name) .. "(" .. string.rep("b", 7000) end
function EllesmereUI.ExportFullAccountData() return "!EUI_F" .. hex("Healer; mine") .. "(" .. string.rep("c", 200) end
function EllesmereUI.ImportProfileInteractive(o)
  if COMBAT then return false, "in combat" end
  if EUI_SESSION then return false, "an interactive import is already pending" end
  assert(o.importString:sub(1, 6) == "!EUI_P", "not a profile string")
  EUI_SESSION = o
  EUI_IMPORTS[#EUI_IMPORTS + 1] = o.profileName
  return true
end
function EUI_CLOSE(ok) local s = EUI_SESSION; EUI_SESSION = nil; s.callback(ok) end
function EllesmereUI.DecodeImportStringAsync(str, onDone)
  local kind, h = str:match("^!EUI_(%a)(%x+)%(")
  onDone({ fullExport = kind == "F", profileName = unhex(h) })
end
function EllesmereUI.IsFullAccountPayload(p) return p.fullExport == true end
function EllesmereUI.ImportFullAccountData(p) EUI_FULL_DONE = EUI_FULL_DONE + 1 end
function EllesmereUI:ShowConfirmPopup(o) assert(self == EllesmereUI); EUI_POPUP = o end
"""
for lua in (A, B):
    lua.execute(EU)

run(A, amod, r"""function(m)
  local p = m.EuiProfiles()
  assert(#p == 2 and p[1].name == "Default" and p[2].active, "profiles")
  local rows = m.EuiRows(); assert(#rows == 3 and rows[3].id == m.EUI_FULL, "rows")
  OUT = {}
  local ok, why = m.SendEui("Healer; mine", "Bob-Stone")
  assert(ok and why:find("\"Healer; mine\"", 1, true), tostring(why))
  assert(OUT[1].msg:find("^QEUH:%d+:1:%d+:Healer%%3B mine$") and OUT[1].to == "Bob Stone", "head: " .. OUT[1].msg)
  assert(#OUT == 3 and OUT[2].msg:find("^QEU:%d+:1:2:P%%7CHealer%%3B mine=!EUI_P") and OUT[3].msg:find("^QEU:%d+:2:2:"), "parts")
  return "Anna: EllesmereUI profiles listed, one sent to Bob in 2 parts"
end""")
msgs = out(A)
deliver_to(msgs, B, "Anna-Smith", order=[0, 2, 1])
run(B, bmod, r"""function(m)
  DIALOG = DIALOG   -- the aura ask is done with
  assert(DIALOG and DIALOG.text:find("sends you 1 EllesmereUI export", 1, true), "no dialog: " .. tostring(DIALOG and DIALOG.text))
  assert(DIALOG.text:find("profile \"Healer; mine\" - you have one by this name", 1, true), DIALOG.text)
  assert(#EUI_IMPORTS == 0, "opened before asking")
  EUI_SESSION = { callback = function() end }   -- an import of Bob's own is open
  DIALOG.ok(); DIALOG = nil
  assert(#EUI_IMPORTS == 0 and LAST():find("waits until EllesmereUI's import page is free", 1, true), LAST())
  EUI_SESSION = nil; FLUSH()
  assert(#EUI_IMPORTS == 1 and EUI_IMPORTS[1] == "Healer; mine" and EUI_SESSION.source:find("Anna Smith", 1, true), "import page")
  OUT = {}
  EUI_CLOSE(true); FLUSH()
  assert(OUT[1].msg:find("^QEUR:%d+:D:1:1$") and OUT[1].to == "Anna-Smith", "done reply: " .. tostring(OUT[1] and OUT[1].msg))
  return "Bob: asked, waited for his own import, EllesmereUI's import page opened, replied"
end""")
deliver_to(out(B), A, "Bob-Stone")
run(A, amod, r"""function(m)
  assert(LAST():find("Bob Stone imported 1 of 1 EllesmereUI profile(s)", 1, true), LAST())
  local ok = m.SendEui(m.EUI_FULL, "Bob-Stone"); assert(ok, "full not sent")
  return "Anna: heard back, sent her full account"
end""")
deliver_to(out(A), B, "Anna-Smith")
run(B, bmod, r"""function(m)
  m.M.db.euAsk = false
  return "Bob: ask off (a full account is asked anyway)"
end""")
run(B, bmod, r"""function(m)
  assert(DIALOG and DIALOG.text:find("FULL ACCOUNT settings + profile \"Healer; mine\"", 1, true), "full not asked: " .. tostring(DIALOG and DIALOG.text))
  DIALOG.ok(); DIALOG = nil
  assert(EUI_POPUP and EUI_POPUP.typeToConfirm == "Confirm" and EUI_POPUP.message:find("Anna Smith sends you a FULL ACCOUNT", 1, true), "EllesmereUI's confirm")
  assert(EUI_FULL_DONE == 0, "imported before Confirm")
  OUT = {}
  EUI_POPUP.onConfirm(); EUI_POPUP.onCancel()   -- a close after the confirm counts nothing
  assert(EUI_FULL_DONE == 1, "full account not imported")
  assert(#OUT == 1 and OUT[1].msg:find("^QEUR:%d+:D:1:1$"), "reply before the reload: " .. tostring(OUT[1] and OUT[1].msg))
  return "Bob: full account always asked, EllesmereUI's typed Confirm, imported, replied first"
end""")
run(A, amod, r"""function(m) OUT = {}; assert(m.SendEui("Default")); return "Anna: Default to the team" end""")
deliver_to(out(A), B, "Anna-Smith")
run(B, bmod, r"""function(m)
  assert(DIALOG == nil and #EUI_IMPORTS == 2 and EUI_IMPORTS[2] == "Default", "no ask: straight to the import page")
  OUT = {}
  EUI_CLOSE(false); FLUSH()
  assert(OUT[1].msg:find("^QEUR:%d+:D:0:1$"), "declined reply")
  local n = 0
  m.M.Report(m.M, function(l) if l:find("^EllesmereUI:") then n = n + 1; assert(l:find("imported=2", 1, true) and l:find("declined=1", 1, true), l) end end)
  assert(n == 1, "report")
  LOADED.EllesmereUI = false
  local ok, why = m.SendEui("Default", "Anna-Smith"); assert(not ok and why:find("switched off"), tostring(why))
  return "Bob: profile straight to the import page, declined, report ok, off without EllesmereUI"
end""")

# --- SmartBuff alerts ------------------------------------------------------
SB = r"""
LOADED.SmartBuff = true
SB_SPLASH = 0
function SMARTBUFF_SetMissingBuffMessage(target, buff) SB_SPLASH = SB_SPLASH + 1 end
function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...) local r = orig(...); fn(...); return r end
end
function MMT.SendAlert(msg) assert(#msg < 250, "too long"); OUT[#OUT + 1] = { msg = msg, alert = true } end
RAID, SOUNDS = {}, 0
RaidWarningFrame = {}
function RaidNotice_AddMessage(_, text) RAID[#RAID + 1] = text end
function PlaySound() SOUNDS = SOUNDS + 1 end
function IsInGroup() return true end
function UnitIsGroupLeader() return LEADS == true end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
"""
for lua in (A, B):
    lua.execute(SB)
    lua.execute("MMT.FTLLeader = function() return nil end")

run(B, bmod, r"""function(m)
  assert(m.SmartBuffHook(), "not hooked"); OUT = {}
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Arcane Intellect", "icon", false, 0, nil, false)
  assert(SB_SPLASH == 1, "SmartBuff's own function didn't run")
  assert(#OUT == 1 and OUT[1].alert and OUT[1].msg == "QSB:N:0:Bob Stone:Arcane Intellect", "alert: " .. tostring(OUT[1] and OUT[1].msg))
  -- SmartBuff checks every 5 s: the same alert not again within a minute
  NOW = NOW + 5; SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Arcane Intellect", "icon", false, 0, nil, false)
  assert(#OUT == 1, "sent again within the minute")
  -- a change (running out) goes right away; names with ":" are escaped
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Arcane Intellect", "icon", false, 0, 28.6, true)
  SMARTBUFF_SetMissingBuffMessage("Pet: Fluffy", "Blessing of Might", "icon", false, 0, nil, false)
  assert(#OUT == 3 and OUT[2].msg == "QSB:E:28:Bob Stone:Arcane Intellect" and OUT[3].msg == "QSB:N:0:Pet%3A Fluffy:Blessing of Might", "change: " .. tostring(OUT[2] and OUT[2].msg))
  NOW = NOW + 61; SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Arcane Intellect", "icon", false, 0, 20, true)
  assert(#OUT == 4, "not sent again after the minute")
  -- running out off: only missing buffs; sending off: nothing
  m.M.db.sbExpire = false; NOW = NOW + 100
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Arcane Intellect", "icon", false, 0, 20, true)
  assert(#OUT == 4, "running out sent while off")
  m.M.db.sbExpire = true; m.M.db.sbSend = false
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Thorns", "icon", false, 0, nil, false)
  assert(#OUT == 4, "sent while sending is off")
  m.M.db.sbSend = true
  return "Bob: SmartBuff's alerts sent once a minute, changes right away"
end""")
msgs = out(B)
run(A, amod, r"""function(m)
  -- not the leader (no FTL leader, group leader is someone else): nothing shown
  LEADS = false; PRINTS = {}
  DELIVER("Bob-Stone", "QSB:N:0:Bob Stone:Arcane Intellect")
  assert(#RAID == 0 and #PRINTS == 0, "shown on a follower")
  LEADS = true
  return "Anna: not shown while not the leader"
end""")
deliver_to(msgs, A, "Bob-Stone")
run(A, amod, r"""function(m)
  -- (the 4th, the same "runs out" again, comes within 10 s on this clock: shown once)
  assert(#RAID == 3 and RAID[1] == "Bob: Bob Stone needs Arcane Intellect", "raid text: " .. tostring(RAID[1]))
  assert(RAID[2] == "Bob: Bob Stone - Arcane Intellect runs out in 28 s" and RAID[3] == "Bob: Pet: Fluffy needs Blessing of Might", tostring(RAID[2]))
  assert(SOUNDS == 3 and PRINTS[1]:find("needs Arcane Intellect", 1, true), "sound / chat")
  -- the same alert from another character within 10 s: once
  DELIVER("Cara-Moon", "QSB:N:0:Bob Stone:Arcane Intellect")
  NOW = NOW + 11; DELIVER("Cara-Moon", "QSB:N:0:Bob Stone:Arcane Intellect")
  assert(#RAID == 4, "repeat: " .. #RAID)
  -- the FTL leader decides when one is known; raid text / sound off; everywhere / nowhere
  MMT.FTLLeader = function() return "Bob-Stone" end
  NOW = NOW + 11; DELIVER("Cara-Moon", "QSB:N:0:Cara Moon:Thorns"); assert(#RAID == 4, "shown on a non-FTL-leader")
  m.M.db.sbShow = "ALL"; m.M.db.sbRaid = false; m.M.db.sbSound = false; PRINTS = {}
  DELIVER("Cara-Moon", "QSB:N:0:Cara Moon:Thorns")
  assert(#RAID == 4 and SOUNDS == 4 and #PRINTS == 1, "ALL / raid / sound options")
  m.M.db.sbShow = "OFF"; NOW = NOW + 11; DELIVER("Cara-Moon", "QSB:N:0:Cara Moon:Thorns"); assert(#PRINTS == 1, "shown while OFF")
  local n = 0
  m.M.Report(m.M, function(l) if l:find("^SmartBuff:") then n = n + 1 end end)
  assert(n == 1, "report")
  return "Anna (leader): alerts shown with raid text + sound, repeats once, leader / ALL / OFF"
end""")
run(B, bmod, r"""function(m)
  -- after a fight: what SmartBuff still reports goes out again, even within the minute
  OUT = {}; NOW = NOW + 500
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Mark of the Wild", "icon", false, 0, nil, false)
  NOW = NOW + 5; EVENTS.PLAYER_REGEN_DISABLED(); NOW = NOW + 10
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Mark of the Wild", "icon", false, 0, nil, false)
  assert(#OUT == 2, "not sent again after the fight: " .. #OUT)
  NOW = NOW + 5; SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Mark of the Wild", "icon", false, 0, nil, false)
  assert(#OUT == 2, "sent again without a fight")
  m.M.db.sbAfterCombat = false
  EVENTS.PLAYER_REGEN_DISABLED(); NOW = NOW + 10
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Mark of the Wild", "icon", false, 0, nil, false)
  assert(#OUT == 2, "sent after a fight while the option is off")
  m.M.db.sbAfterCombat = true
  return "Bob: SmartBuff's alerts go out again after each fight"
end""")
run(A, amod, r"""function(m)
  -- privacy names: team members in SmartBuff's text and the sender show as MMT.ShownName does
  local SHOWN = { ["Anna-Smith"] = "Healer", ["Bob-Stone"] = "Druid 2", ["Cara-Moon"] = "Slot 3" }
  MMT.ShownName = function(k) return SHOWN[k] or k end
  MMT.RealFirst = function(k) return (k:match("^[^-]+")) end
  MMT.RealName = function(k) return (k:gsub("-", " ")) end
  assert(m.SmartBuffShownName("Bob") == "Druid 2" and m.SmartBuffShownName("cara moon") == "Slot 3", "names")
  assert(m.SmartBuffShownName("Pet: Fluffy") == "Pet: Fluffy" and m.SmartBuffShownName("Stranger") == "Stranger", "others")
  m.M.db.sbShow = "ALL"; m.M.db.sbRaid = true; NOW = NOW + 30
  DELIVER("Bob-Stone", "QSB:N:0:Cara:Arcane Intellect")
  assert(RAID[#RAID] == "Druid 2: Slot 3 needs Arcane Intellect", "privacy text: " .. tostring(RAID[#RAID]))
  MMT.ShownName = nil
  return "Anna: SmartBuff alerts use the privacy names"
end""")
run(B, bmod, r"""function(m)
  -- a follower that never gets into combat itself: the group's fight counts too
  INFIGHT = {}
  function UnitAffectingCombat(u) return INFIGHT[u] == true end
  function UnitExists(u) return u == "party1" or u == "player" end
  function IsInRaid() return false end
  function GetNumGroupMembers() return 2 end
  OUT = {}; NOW = NOW + 500
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Thorns", "icon", false, 0, nil, false)
  NOW = NOW + 5; m.SmartBuffCombatTick()
  INFIGHT.party1 = true; NOW = NOW + 1; m.SmartBuffCombatTick()
  INFIGHT.party1 = nil; NOW = NOW + 10; m.SmartBuffCombatTick()
  SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Thorns", "icon", false, 0, nil, false)
  assert(#OUT == 2, "not sent again after the group's fight: " .. #OUT)
  NOW = NOW + 5; SMARTBUFF_SetMissingBuffMessage("Bob Stone", "Thorns", "icon", false, 0, nil, false)
  assert(#OUT == 2, "sent again without a fight")
  local line
  m.M.Report(m.M, function(l) if l:find("^SmartBuff:") then line = l end end)
  assert(line:find("held=", 1, true) and line:find("lastFight=", 1, true), line)
  return "Bob: a group member's fight counts as a fight"
end""")
