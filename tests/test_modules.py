import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
MMT = { CopyTable = copy, IsSecret = function() return false end }
function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
''')
lua.execute(open('MMT_CooldownTimers/Transfer.lua', encoding='utf-8').read())
captured = lua.execute('local c; MMTTransfer.Open = function(d) c = d end; return function() return c end')

def load(path, mod):
    chunk = lua.eval('function(src, name) local f = assert(loadstring(src, name)); return f end')(
        open(path, encoding='utf-8').read(), path)
    chunk("x", mod)

def new_mod(setup):
    return lua.eval('function(setup) local m = {} setup(m) return m end')(lua.eval(setup))

TEST = r'''function(mod, prefix, getdef, entryNeedsT)
  mod.OpenTransfer()
  local def = getdef()
  assert(def.prefix == prefix)
  local data = { sections = {} }
  for _, s in ipairs(def.sections) do data.sections[s.id] = s.get() end
  local str = MMTTransfer.Encode(prefix, data)
  local db = mod.M.db
  local saved = MMT.CopyTable(db)
  db.iconSize = 99; db.shown = false; db.point = {"TOP","TOP",1,1}
  for c in pairs(db.lists) do db.lists[c] = {} end
  if db.allExclude then db.allExclude = {}; db.allMissingLook = "GREY" end
  local back = assert(MMTTransfer.Decode(prefix, str))
  for _, s in ipairs(def.sections) do assert(s.set(back.sections[s.id]) ~= false, s.id) end
  assert(same(saved, db), "import did not restore the settings")
  for _, s in ipairs(def.sections) do assert(s.set("junk") == false, "accepted junk for " .. s.id) end
  local look
  for _, s in ipairs(def.sections) do if s.id == "look" then look = s end end
  look.set({ iconSize = "huge", shown = 5, attach = "EVERYWHERE" })
  assert(db.iconSize == saved.iconSize and db.shown == saved.shown, "wrong types taken")
  if db.attach then assert(db.attach == "OFF", "bad choice taken") end
  for _, s in ipairs(def.sections) do if s.id == "lists" then
    s.set({ WARRIOR = { {t="x",id=1,cd=1}, "junk", {id="12"} }, HACKER = { {id=1} } })
    assert(db.lists.HACKER == nil, "unknown class taken")
    assert(#db.lists.WARRIOR == (entryNeedsT and 0 or 1), "entry check wrong: " .. #db.lists.WARRIOR)
  end end
  return prefix .. " import/export ok (" .. #str .. " chars)"
end'''

cd = new_mod(r'''function(m)
  m.CLASSES = {"WARRIOR","MAGE","ALL"}
  m.M = { Listen = function() end, db = { shown=true, iconSize=28, scale=1, showBuffs=true, hideReady=false,
                 lists = { WARRIOR = {{t="s",id=871,cd=1800}}, MAGE = {}, ALL = {} },
                 point = {"CENTER","CENTER",200,0} } }
  m.BuildIndex = function() end
  m.window = { Refresh = function() end }
end''')
load('MMT_CooldownTimers/ListKeys.lua', cd)
load('MMT_CooldownTimers/Export.lua', cd)
print(lua.eval(TEST)(cd, 'MMTCD1', captured, True))

bf = new_mod(r'''function(m)
  m.CLASSES = {"WARRIOR","MAGE","ALL"}
  m.M = { Listen = function() end, db = { shown=true, attach="OFF", iconSize=28, missingAlpha=0.25, allBar=true, allMissingLook="RED",
                 allExclude = { ["Alt-Realm"] = true },
                 lists = { WARRIOR = {{id=6673}}, MAGE = {{id=1459}}, ALL = {{id=1243}} },
                 point = {"CENTER","CENTER",-200,0} } }
  m.BuildIndex = function() end; m.ScanGroup = function() end; m.Apply = function() end
end''')
load('MMT_BuffTimers/ListKeys.lua', bf)
load('MMT_BuffTimers/Export.lua', bf)
print(lua.eval(TEST)(bf, 'MMTBF1', captured, False))

# group buffs: Prayer of Fortitude on a unit counts for a tracked Power Word: Fortitude
names = {1243: "Power Word: Fortitude", 21562: "Prayer of Fortitude", 1126: "Mark of the Wild",
         21849: "Gift of the Wild", 1459: "Arcane Intellect", 23028: "Arcane Brilliance"}
lua.execute('NAMES = {}')
for k, v in names.items():
    lua.eval('function(k, v) NAMES[k] = v end')(k, v)
lists = new_mod(r'''function(m)
  m.SpellInfo = function(id) return NAMES[id] end
  m.SpellIcon = function() return 1 end
end''')
load('MMT_BuffTimers/Lists.lua', lists)
print(lua.eval(r'''function(m)
  assert(m.Canonical("Prayer of Fortitude") == "Power Word: Fortitude")
  assert(m.Canonical("Power Word: Fortitude") == "Power Word: Fortitude")
  assert(m.Canonical("Gift of the Wild") == "Mark of the Wild")
  assert(m.Canonical("Arcane Brilliance") == "Arcane Intellect")
  assert(m.Canonical("Battle Shout") == "Battle Shout")
  -- an entry added as the group spell is tracked under the single name, but listed under its own
  assert(m.BuildIndex == nil)
  assert(m.BuffName({ id = 21562 }) == "Power Word: Fortitude")
  assert(m.EntryName({ id = 21562 }) == "Prayer of Fortitude")
  return "group buff matching ok"
end''')(lists))

# bug: Seal of Righteousness showed the "?" icon while it was tracked fine: the game had no
# texture for that spell ID. Now: by the spell's name, else the icon the buff had when seen.
lua.execute(r'''
C_Spell = {
  GetSpellInfo = function(x)
    if x == 20154 or x == "Seal of Righteousness" then return { name = "Seal of Righteousness", iconID = nil, spellID = 20154 } end
    if x == 99999 or x == "Odd Buff" then return { name = "Odd Buff", iconID = nil, spellID = 99999 } end
  end,
  GetSpellTexture = function(x) if x == "Seal of Righteousness" then return 132325 end end,   -- by name only
}
''')
icons = new_mod(r'''function(m) m.M = { store = {} } end''')
load('MMT_BuffTimers/Compat.lua', icons)
load('MMT_BuffTimers/Lists.lua', icons)
print(lua.eval(r'''function(m)
  assert(m.SpellIcon(20154) == nil, "test needs an ID without a texture")
  assert(m.EntryIcon({ id = 20154 }) == 132325, "not found by name: " .. tostring(m.EntryIcon({ id = 20154 })))
  -- nothing by ID or name: the "?" until the buff was seen on someone, then its own icon
  assert(m.EntryIcon({ id = 99999 }) == 134400, "placeholder")
  m.SeeIcon("Odd Buff", 136000)
  assert(m.EntryIcon({ id = 99999 }) == 136000, "seen icon not used")
  return "entry icons ok"
end''')(icons))

# bug: Battle Shout showed as missing while it was on: the index of tracked buffs was built
# at login, when the game didn't know the spell's name yet (lazy spell data), and the scan
# only kept indexed buffs. Now the scan keeps every buff; unknown spells get their data requested.
lua.execute(r'''
KNOWN_NAMES = {}   -- the game's spell data: empty at login
REQUESTED = {}
C_Spell = {
  GetSpellInfo = function(x) local n = KNOWN_NAMES[x] if n then return { name = n, iconID = 1, spellID = x } end end,
  GetSpellTexture = function() return nil end,
  RequestLoadSpellData = function(id) REQUESTED[id] = true end,
}
C_Timer = { After = function(_, f) f() end }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function IsInRaid() return false end
function UnitExists(u) return u == "player" end
function GetTime() return 100 end
MMT.SplitUnit = function(u) if u == "player" then return "Alash", "Erelia", "Alash-Erelia" end end
MMT.Resolve = function(k) return k end
MMT.IsSecret = function() return false end
REDRAWS = 0
''')
tr = new_mod(r'''function(m)
  local M = { db = { lists = { WARRIOR = { { id = 6673 } } } }, store = {}, enabled = true }
  function M:On() end
  function M:Listen() end
  m.M = M
  m.Buff = function(unit, i) if unit == "player" and i == 1 then return "Battle Shout", 132333, 0, 120, 200 end end
  m.Redraw = function() REDRAWS = REDRAWS + 1 end
end''')
load('MMT_BuffTimers/Compat.lua', tr)
load('MMT_BuffTimers/Lists.lua', tr)
load('MMT_BuffTimers/Tracker.lua', tr)
print(lua.eval(r'''function(m)
  -- (Compat.lua brought its own reader: the stand-in after it)
  m.Buff = function(unit, i) if unit == "player" and i == 1 then return "Battle Shout", 132333, 0, 120, 200 end end
  -- login: the name isn't known yet
  m.BuildIndex()
  assert(REQUESTED[6673], "spell data not requested")
  m.ScanGroup()
  -- the data arrives: the buff that was already scanned counts
  KNOWN_NAMES[6673] = "Battle Shout"
  local state = m.State("Alash-Erelia", { id = 6673 })
  assert(state == "buff", "Battle Shout shown as " .. tostring(state))
  return "buffs with late spell data ok"
end''')(tr))

# a "Teaches ..." trainer spell's generic icon (WoW logo) counts as none: by name, or the seen buff
lua.execute(r'''
C_Spell = {
  GetSpellInfo = function(x)
    if x == 864 or x == "Seal of Righteousness" then return { name = "Seal of Righteousness", iconID = 136235, spellID = 864 } end
  end,
  GetSpellTexture = function(x) if x == 864 then return 136235 end if x == "Seal of Righteousness" then return KNOWS_SOR and 132325 or nil end end,
}
''')
teach = new_mod(r'''function(m) m.M = { store = {} } end''')
load('MMT_BuffTimers/Compat.lua', teach)
load('MMT_BuffTimers/Lists.lua', teach)
print(lua.eval(r'''function(m)
  -- a character that doesn't know the seal: the logo until the buff was seen
  assert(m.EntryIcon({ id = 864 }) == 136235, "generic icon as the last resort")
  m.SeeIcon("Seal of Righteousness", 132325)
  assert(m.EntryIcon({ id = 864 }) == 132325, "seen icon not preferred over the logo")
  -- the paladin knows it: by name
  m.M.store.icons = {}
  KNOWS_SOR = true
  assert(m.EntryIcon({ id = 864 }) == 132325, "not by name")
  return "trainer spell icons ok"
end''')(teach))
