"""MMT_QoL: two clients, Anna and Bob, each with stand-ins for Dejunk (its saved
state + DejunkApi listener, and its in-memory list copy that it saves over the
state) and Baganator (its profile config + API). Changes on one reach the
other, changes taken are not sent back, bulk changes aren't sent."""
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
  function M:On(ev, fn) EVENTS[ev] = fn end
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

# --- Baganator ----------------------------------------------------------
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
  assert(n == 3, "report lines " .. n)
  return "Anna: whole setup asked, imported, report ok"
end''')
