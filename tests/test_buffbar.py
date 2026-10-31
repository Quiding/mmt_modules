"""MMT_BuffTimers: the All bar's counter (how many members have a buff, in its own
corner), SmartBuff alerts making icons glow, ... - the whole module loaded with test_settings' stand-in API."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open('tests/test_settings.py', encoding='utf-8').read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
# team messages: listeners kept, sent messages recorded
lua.execute('''
local nm = MMT.NewModule
LISTEN = {}
EVENTS = {}
function FIRE(ev, ...) for _, fn in ipairs(EVENTS[ev] or {}) do fn(...) end end
MMT.NewModule = function(def)
  local M = nm(def)
  function M:Listen(ev, fn) LISTEN[#LISTEN + 1] = { ev, fn } end
  function M:On(ev, fn) EVENTS[ev] = EVENTS[ev] or {}; table.insert(EVENTS[ev], fn) end
  return M
end
SENT = {}
MMT.SendToTeam = function(msg) SENT[#SENT + 1] = msg end
MMT.SendAddon = function(msg, ch, to) SENT[#SENT + 1] = ch .. ":" .. to .. ":" .. msg end
function TEAM_MESSAGE(key, text)
  for _, l in ipairs(LISTEN) do if l[1] == "TEAM_MESSAGE" then l[2](key, key, text) end end
end
''')
mod = lua.eval('{}')
folder = 'MMT_BuffTimers'
for f in [l.strip() for l in open(os.path.join(folder, folder + '.toc'), encoding='utf-8') if l.strip().endswith('.lua')]:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
        open(os.path.join(folder, f), encoding='utf-8').read(), folder + '/' + f, mod)

print(lua.eval(r'''function(m)
  ORIG_STATE = m.State
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone", "Cid-Ray" } end
  MMT.status = {}
  MMT.IsOnline = function() return true end
  local c = m.M.db
  c.hideNoCaster = false
  c.allBar = true
  c.lists.ALL = { { id = 19740 } }   -- Blessing of Might
  HAVE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true }
  m.State = function(key, e) if HAVE[key] then return "buff", 100, 300, 1 end return "missing" end
  local function AllIcon()
    for _, row in ipairs(m.window.def.rows()) do
      if row.label == "All" then return row.icons[1] end
    end
  end
  -- 2 of 3 have it: "2/3" in the bottom left, size 12 (defaults), no separate missing count
  local i = AllIcon()
  assert(i.state == "missing" and i.tally == "2/3" and i.tallyPos == "BOTTOMLEFT" and i.tallySize == 12, "counter: " .. tostring(i.tally))
  assert(i.count == nil, "a missing count still shows")
  assert(i.tip:find("2 of 3 have it", 1, true), "tooltip")
  -- one has it: "1/3"
  HAVE = { ["Anna-Smith"] = true }
  i = AllIcon()
  assert(i.tally == "1/3" and i.count == nil, "one of three: " .. tostring(i.tally))
  -- everyone has it: no number, just the timer
  HAVE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true, ["Cid-Ray"] = true }
  c.allCount, c.allCountSize = "TOPRIGHT", 16
  i = AllIcon()
  assert(i.state == "buff" and i.tally == nil, "a number while everyone has it")
  HAVE = { ["Anna-Smith"] = true }
  i = AllIcon()
  assert(i.tally == "1/3" and i.tallyPos == "TOPRIGHT" and i.tallySize == 16, "corner and size from the settings")
  -- off
  c.allCount = "OFF"
  i = AllIcon()
  assert(i.tally == nil and i.count == nil, "counter while off")
  return "All bar counter ok"
end''')(mod))

# "All classes" preview: made-up characters, one of every class, in their class colours
print(lua.eval(r"""function(m)
  m.State = ORIG_STATE
  RAID_CLASS_COLORS = {}
  for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    RAID_CLASS_COLORS[c] = { r = #c / 10, g = 0.5, b = 0.5 }
  end
  for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    m.M.db.lists[c] = { { id = 6673 } }   -- something tracked for every class, else no row
  end
  m.SetPreview("ALL")
  local rows, byKey = m.window.def.rows(), {}
  for _, r in ipairs(rows) do if r.key then byKey[r.key] = r end end
  local n = 0
  for _ in pairs(byKey) do n = n + 1 end
  assert(n == 9, "made-up rows: " .. n)
  local w = byKey["Brakka-Preview"]
  assert(w and m.ClassOf("Brakka-Preview") == "WARRIOR" and w.color and w.color[1] == 0.7, "warrior row / colour")
  assert(#w.icons >= 1, "warrior list not shown for the made-up warrior")
  assert(m.ClassOf("Lirael-Preview") == "PRIEST", "priest")
  assert(MMT.FirstName("Brakka-Preview") == "Brakka", "made-up name")
  m.SetPreview(nil)
  rows = m.window.def.rows()
  for _, r in ipairs(rows) do assert(r.key ~= "Brakka-Preview", "made-up row after the preview") end
  return "All classes preview ok"
end""")(mod))

# the All bar's default and the raid presets: party buffs (no auras), with "Only for"
print(lua.eval(r"""function(m)
  local function Ids(list) local t = {} for _, e in ipairs(list) do t[m.EntryKey(e)] = e end return t end
  local def = Ids(m.DEFAULT_LISTS.ALL)
  assert(def[1243] and def[1126] and def[20217] and not def[1243].only, "Fortitude / Mark / Kings for everyone")
  for _, e in ipairs(m.DEFAULT_LISTS.ALL) do assert(not e.only, "a default buff has Only for: " .. e.id) end
  assert(def[19740] and def[19742] and def[1459] and def[1038] and def[6673], "party buffs missing")
  assert(not def[19506] and not def[17007] and not def[24907], "auras in the default")
  local raid, auras = m.PresetByKey("ALL:RAID"), m.PresetByKey("ALL:RAIDAURAS")
  assert(raid and auras, "raid presets")
  local r, a = Ids(raid.entries), Ids(auras.entries)
  assert(not r[19506] and a[19506] and a[17007] and a[24907], "auras only in the + auras preset")
  -- a preset's tables are copied into the list, not shared with the preset
  r[19740].only = { roles = { MELEE = true } }
  m.M.db.lists.ALL = {}
  m.ApplyPreset("ALL", "ALL:RAID", true, function(e) return e.id end)
  local might
  for _, e in ipairs(m.M.db.lists.ALL) do if e.id == 19740 then might = e end end
  might.only.roles.CASTER = true
  assert(not r[19740].only.roles.CASTER, "the preset changed with the list")
  r[19740].only = nil
  return "party buff presets ok"
end""")(mod))

# buff spec presets: per class, defaults on only when every spec keeps them up
print(lua.eval(r"""function(m)
  local ret = m.PresetByKey("PALADIN:RET")
  assert(ret and ret.name == "Paladin: Retribution", "ret buff preset")
  local ids = {}
  for _, e in ipairs(ret.entries) do ids[m.EntryKey(e)] = e end
  assert(ids["Seal of *"] and not ids["Seal of *"].off and ids[20050] and not ids[20375], "ret buffs: any seal")
  local function Default(class)
    local t = {} for _, e in ipairs(m.DEFAULT_LISTS[class]) do t[m.EntryKey(e)] = e end return t
  end
  local pal, rogue, priest = Default("PALADIN"), Default("ROGUE"), Default("PRIEST")
  assert(pal["Seal of *"] and not pal["Seal of *"].off, "any seal on for every paladin")
  assert(Default("HUNTER")["Aspect of the *"], "any aspect for hunters")
  assert(rogue[5171] and not rogue[5171].off, "Slice and Dice off for rogues")
  assert(priest[588] and not priest[588].off and priest[15473].off, "priest defaults")
  for _, p in ipairs(m.PRESETS) do assert(not p.key:find(":REC$"), "old class preset " .. p.key) end
  return "buff spec presets ok"
end""")(mod))

# name patterns: "Seal of *" counts any seal, shows the one that's up
print(lua.eval(r"""function(m)
  assert(m.ParsePattern("  Seal of *  ") == "Seal of *" and not m.ParsePattern("Seal of Light") and not m.ParsePattern(" * "), "ParsePattern")
  local e = { name = "Seal of *" }
  assert(m.IsPattern(e) and m.Matches(e, "Seal of Command") and m.Matches(e, "seal of the crusader"), "matches")
  assert(not m.Matches(e, "Blessing of Might") and not m.Matches(e, "Greater Seal of X"), "no match")
  assert(m.Matches({ name = "A.b (x) *" }, "A.b (x) y") and not m.Matches({ name = "A.b *" }, "Axb y"), "magic characters")
  local buffs = {}
  local oldBuff = m.Buff
  m.Buff = function(unit, i) local b = unit == "player" and buffs[i] if b then return b[1], b[2], 1, b[3], b[4] end end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" end
  IsInRaid = IsInRaid or function() return false end
  local oldSplit, oldResolve = MMT.SplitUnit, MMT.Resolve
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  buffs = { { "Blessing of Might", 111, 300, GetTime() + 200 }, { "Seal of Command", 132347, 30, GetTime() + 20 } }
  m.ScanGroup()
  local key = next(m.auras)
  assert(key == "Me-Realm", "player scanned")
  local state, start, dur, count, matched, icon = m.State(key, e)
  assert(state == "buff" and dur == 30 and matched == "Seal of Command" and icon == 132347, "seal found: " .. tostring(state) .. tostring(matched))
  buffs = { { "Blessing of Might", 111, 300, GetTime() + 200 } }
  m.ScanGroup()
  assert(m.State(key, e) == "missing", "no seal = missing")
  assert(m.EntryName(e) == "Seal of *" and m.BuffName(e) == "Seal of *", "names")
  m.Buff, MMT.SplitUnit, MMT.Resolve = oldBuff, oldSplit, oldResolve
  m.ScanGroup()
  return "name patterns ok"
end""")(mod))

# weapon enchants: own from C_Item.GetWeaponEnchantInfo, others from MBW messages
print(lua.eval(r"""function(m)
  m.preview, m.testUntil = nil, nil
  Enum = { WeaponSlot = { MainHand = 1, OffHand = 2 }, ItemEnchantType = { Temporary = 0, Imbue = 1 } }
  local items = { [16] = 1001 }                 -- a main-hand weapon, nothing in the off hand
  GetInventoryItemID = function(_, inv) return items[inv] end
  GetItemInfoInstant = function() return 1001, "Weapon", "", "", 1, 2, 0 end
  GetInventoryItemTexture = function() return 777 end
  local list = { { hasEnchant = true, enchantType = 1, timeLeft = 1800000, enchantID = 5, enchantIconID = 136018 } }
  C_Item = { GetWeaponEnchantInfo = function(ws) if ws == 1 then return list end return {} end }
  local MH, OH = { weapon = "MH" }, { weapon = "OH" }
  assert(m.ParseWeapon("Main hand") == "MH" and m.ParseWeapon("off-hand") == "OH" and not m.ParseWeapon("Fortitude"), "ParseWeapon")
  m.ScanWeapons(true)
  local state, start, dur, _, _, icon = m.State("Anna-Smith", MH)
  assert(state == "buff" and dur == 1800 and start == 1000 and icon == 136018, "own imbue: " .. tostring(state))
  assert(m.State("Anna-Smith", OH) == nil, "no off-hand weapon: nothing shown")
  assert(m.OwnWeaponMessage() == "MBW:1800/1800/136018/;x", m.OwnWeaponMessage())
  -- an oil on the same weapon: the imbue still wins
  list[2] = { hasEnchant = true, enchantType = 0, timeLeft = 3600000, enchantID = 9 }
  m.ScanWeapons(true)
  assert(select(6, m.State("Anna-Smith", MH)) == 136018, "imbue before oil")
  -- gone
  list = {}
  m.ScanWeapons(true)
  assert(m.State("Anna-Smith", MH) == "missing", "own imbue gone")
  -- another member tells us theirs
  TEAM_MESSAGE("Bob-Stone", "MBW:600/1800/135000/Instant Poison VI;0")
  state, start, dur, _, matched, icon = m.State("Bob-Stone", MH)
  assert(state == "buff" and dur == 1800 and start == 1000 + 600 - 1800 and matched == "Instant Poison VI" and icon == 135000, "Bob's poison")
  assert(m.State("Bob-Stone", OH) == "missing", "Bob's off hand empty")
  assert(m.State("Cid-Ray", MH) == nil, "never heard from Cid: nothing")
  -- asked for ours: whispered back
  SENT = {}
  TEAM_MESSAGE("Bob-Stone", "MBWQ")
  assert(SENT[1] == "WHISPER:Bob-Stone:MBW:0;x", tostring(SENT[1]))
  assert(m.EntryKey(MH) == "weapon:MH" and m.EntryName(OH) == "Off-hand enchant", "names")
  -- presets: rogues track both hands, enhancement the main hand, totems need a shaman
  local enh = {} for _, e in ipairs(m.PresetByKey("SHAMAN:ENH").entries) do enh[m.EntryKey(e)] = e end
  assert(enh["weapon:MH"] and not enh["weapon:MH"].off, "enhancement imbue")
  local rogue = {} for _, e in ipairs(m.DEFAULT_LISTS.ROGUE) do rogue[m.EntryKey(e)] = e end
  assert(rogue["weapon:MH"] and not rogue["weapon:MH"].off and rogue["weapon:OH"], "rogue poisons")
  local totems = m.PresetByKey("ALL:TOTEMS")
  assert(totems and m.CasterClass(totems.entries[1]) == "SHAMAN", "totem preset")
  return "weapon enchants ok"
end""")(mod))

# a buff in the All bar and in a class list: only in the All row
print(lua.eval(r"""function(m)
  m.State = function() return "buff", 100, 300, 1 end
  local oldInfo = m.SpellInfo
  m.SpellInfo = function(id) return ({ [6673] = "Battle Shout", [324] = "Lightning Shield" })[id] end
  m.M.db.allBar, m.M.db.hideNoCaster = true, false
  m.M.db.lists.ALL = { { id = 6673 } }
  m.M.db.lists.SHAMAN = { { id = 6673 }, { id = 324 } }
  for _, row in ipairs(m.window.def.rows()) do
    if row.key == "Anna-Smith" then
      for _, i in ipairs(row.icons) do assert(i.spell ~= 6673, "Battle Shout twice") end
      assert(#row.icons == 1, "Lightning Shield stays: " .. #row.icons)
    end
  end
  m.State = ORIG_STATE
  m.SpellInfo = oldInfo
  return "All bar buffs out of member rows ok"
end""")(mod))

# totem preset in the preview: the shaman's made-up states, preset icons
print(lua.eval(r"""function(m)
  local oldIcon = m.SpellIconAny
  m.SpellIconAny = function(id) if id == 8076 then return 136023 end end
  local soe = m.PresetByKey("ALL:TOTEMS").entries[1]
  assert(soe.icon == 8076 and m.EntryIcon(soe) == 136023, "totem icon before it was seen")
  m.M.db.lists.ALL = { { name = soe.name, caster = "SHAMAN", icon = 8076 } }
  m.SetPreview("ALL")
  local found
  for _, row in ipairs(m.window.def.rows()) do
    if row.label == "All" then found = row.icons[1] end
  end
  assert(found and found.texture == 136023 and not found.tip:find("None of", 1, true), "totem in the preview All bar")
  m.SetPreview(nil)
  m.SpellIconAny = oldIcon
  return "totem preview ok"
end""")(mod))

# a totem pattern added before presets had icons gets the preset's icon
print(lua.eval(r"""function(m)
  m.M.db.lists.ALL = { { name = "Grace of Air*", caster = "SHAMAN" } }
  m.BuildIndex()
  assert(m.M.db.lists.ALL[1].icon == 8836, "icon filled in: " .. tostring(m.M.db.lists.ALL[1].icon))
  return "old totem entries get icons ok"
end""")(mod))

# spec lists: a member with a known spec uses their spec's list instead of the class list
print(lua.eval(r"""function(m)
  m.preview = nil
  assert(m.ListKeysFor("Anna-Smith", false)[1] == "SHAMAN", "class list while the option is off")
  m.M.db.specLists = true
  m.TreePoints = function() return { 0, 31, 5 } end          -- Enhancement
  local keys = m.ListKeysFor("Anna-Smith", false)
  assert(keys[1] == "SPEC:SHAMAN:ENH", "own spec: " .. tostring(keys[1]))
  local enh = {} for _, e in ipairs(m.M.db.lists["SPEC:SHAMAN:ENH"]) do enh[m.EntryKey(e)] = true end
  assert(enh["weapon:MH"], "spec list starts as the spec preset")
  MMT.db.team["Bob-Stone"] = { class = "PALADIN" }
  MMT.db.team["Cid-Ray"] = { class = "PALADIN" }
  local oldStatus = MMT.status
  MMT.status = { ["Bob-Stone"] = { ext = { cts = "1" } } }
  assert(m.SpecOf("Bob-Stone") == "PALADIN:HOLY", "heartbeat spec")
  TEAM_MESSAGE("Bob-Stone", "MSPC:3")
  assert(m.SpecOf("Bob-Stone") == "PALADIN:RET", "respec message")
  assert(m.ListKeysFor("Cid-Ray", false)[1] == "PALADIN", "spec unknown: class list")
  assert(m.ListLabel("SPEC:PALADIN:RET") == "Paladin: Retribution", "label")
  local found
  for _, c in ipairs(m.ListChoices()) do if c.value == "SPEC:DRUID:BEAR" then found = true end end
  assert(found, "spec lists in the List menu")
  assert(m.PresetChoices("SPEC:PALADIN:RET")[2].value == "PALADIN:RET", "own preset first")
  assert(m.ValidListKey("SPEC:PALADIN:RET") and not m.ValidListKey("SPEC:x"), "valid keys")
  m.M.db.specLists = false
  MMT.status = oldStatus
  MMT.db.team["Bob-Stone"], MMT.db.team["Cid-Ray"] = nil, nil
  return "spec lists ok"
end""")(mod))

# a member with nothing tracked gets no row
print(lua.eval(r"""function(m)
  local oldState = m.State
  m.M.db.allBar = true
  m.M.db.lists.ALL = {}
  m.M.db.lists.SHAMAN = { { id = 324 } }
  m.State = function(key) if key == "Anna-Smith" then return "buff", 100, 300, 1 end end
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone" } end
  local keys = {}
  -- (an empty member row asks IconBars to leave it out: dropEmpty, v16)
  for _, row in ipairs(m.window.def.rows()) do if row.key and (#row.icons > 0 or not row.dropEmpty) then keys[#keys + 1] = row.key end end
  assert(#keys == 1 and keys[1] == "Anna-Smith", "empty row: " .. table.concat(keys, ","))
  m.State = oldState
  return "empty rows hidden ok"
end""")(mod))

# a spec set by hand (Specs tab) wins over the talents, if it fits the class
print(lua.eval(r"""function(m)
  m.M.db.specLists = true
  MMT.db.team["Bob-Stone"] = { class = "WARRIOR" }
  m.M.db.specSet = { ["Bob-Stone"] = "FURY", ["Anna-Smith"] = "RET" }   -- RET doesn't fit a shaman
  assert(m.SpecOf("Bob-Stone") == "WARRIOR:FURY", "set by hand: " .. tostring(m.SpecOf("Bob-Stone")))
  assert(m.ListKeysFor("Bob-Stone", false)[1] == "SPEC:WARRIOR:FURY", "fury list")
  assert(m.SpecOf("Anna-Smith") ~= "SHAMAN:RET", "a spec of another class is ignored")
  -- one set in Cooldown Timers counts here too
  m.M.db.specSet = {}
  MMT.db.modules = { CooldownTimers = { specSet = { ["Bob-Stone"] = "ARMS" } } }
  assert(m.SpecOf("Bob-Stone") == "WARRIOR:ARMS", "set in the other module")
  MMT.db.modules = nil
  m.M.db.specLists = false
  MMT.db.team["Bob-Stone"] = nil
  return "specs set by hand ok"
end""")(mod))

# the List menu shows who each list applies to right now
print(lua.eval(r"""function(m)
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone" } end
  MMT.db.team["Bob-Stone"] = { class = "WARRIOR" }
  local text = {}
  for _, c in ipairs(m.ListChoices()) do if c.value then text[c.value] = c.text end end
  assert(text.SHAMAN:find("Anna", 1, true) and text.WARRIOR:find("Bob", 1, true), "class lists in use: " .. text.SHAMAN)
  assert(not text.MAGE:find("|cff55dd55", 1, true), "mage list not in use")
  assert(text.ALL:find("everyone", 1, true), "All bar in use")
  MMT.db.team["Bob-Stone"] = nil
  return "lists in use ok"
end""")(mod))

# "Only for" specs; the List menu without class lists while spec lists are on
print(lua.eval(r"""function(m)
  MMT.db.team["Bob-Stone"] = { class = "PALADIN" }
  MMT.db.team["Cid-Ray"] = { class = "PALADIN" }
  m.M.db.specSet = { ["Bob-Stone"] = "RET", ["Cid-Ray"] = "HOLY" }
  local e = { id = 19740, only = { specs = { ["PALADIN:RET"] = true } } }
  assert(m.HasFilter(e) and m.Applies(e, "Bob-Stone") and not m.Applies(e, "Cid-Ray"), "only for Retribution")
  -- spec unknown (no talents yet): any ticked spec of the class counts
  MMT.db.team["Dan-Low"] = { class = "PALADIN" }
  MMT.db.team["Eve-Low"] = { class = "MAGE" }
  local oldTree = m.TreeOf
  m.TreeOf = function() return nil end
  assert(m.Applies(e, "Dan-Low") and not m.Applies(e, "Eve-Low"), "spec unknown: class fallback")
  m.TreeOf = oldTree
  MMT.db.team["Dan-Low"], MMT.db.team["Eve-Low"] = nil, nil
  assert(m.FilterText(e) == "Paladin: Retribution", tostring(m.FilterText(e)))
  local clean = m.CleanFilter({ specs = { ["PALADIN:RET"] = true, bad = true } })
  assert(clean.specs["PALADIN:RET"] and not clean.specs.bad, "export keeps specs")
  m.M.db.specLists = true
  local values = {}
  for _, c in ipairs(m.ListChoices()) do if c.value then values[c.value] = true end end
  assert(values.ALL and values["SPEC:PALADIN:RET"] and not values.PALADIN and not values.WARRIOR, "class lists hidden")
  m.M.db.specLists = false
  values = {}
  for _, c in ipairs(m.ListChoices()) do if c.value then values[c.value] = true end end
  assert(values.PALADIN and not values["SPEC:PALADIN:RET"], "class lists back")
  m.M.db.specSet = {}
  MMT.db.team["Bob-Stone"], MMT.db.team["Cid-Ray"] = nil, nil
  return "spec filter and menu ok"
end""")(mod))

# buffs not learned yet: own row, and buffs cast on others when no caster here has learned them
print(lua.eval(r"""function(m)
  local oldInfo, oldCd, oldCaster, oldState, oldTime = m.SpellInfo, m.SpellCooldown, m.CasterClass, m.State, GetTime
  local NAMES = { [324] = "Lightning Shield", [408510] = "Water Shield", [1243] = "Power Word: Fortitude" }
  m.SpellInfo = function(id) return NAMES[id] end
  m.SpellCooldown = function(name) if name == "Lightning Shield" then return 0, 0, true end end   -- Water Shield not learned
  m.CasterClass = function(e) return e.id == 1243 and "PRIEST" or nil end
  m.State = function() return "buff", 100, 300, 1 end
  GetTime = function() return 5000 end                                  -- past the "who is here" cache
  m.preview = nil
  m.M.db.allBar, m.M.db.specLists, m.M.db.hideUnlearned, m.M.db.hideNoCaster = false, false, true, true
  m.M.db.lists.ALL = { { id = 1243 } }
  m.M.db.lists.SHAMAN = { { id = 324 }, { id = 408510 } }
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone" } end
  MMT.db.team["Bob-Stone"] = { class = "PRIEST" }
  m.KnownReset()
  local own = m.OwnUnlearned()
  assert(#own == 1 and own[1] == 408510, "own unlearned: " .. #own)
  assert(m.Unlearned("Anna-Smith", { id = 408510 }) and not m.Unlearned("Anna-Smith", { id = 324 }), "own")
  -- the priest hasn't learned Fortitude: nobody here can give it
  TEAM_MESSAGE("Bob-Stone", "MBFK:1243")
  assert(not m.Castable({ id = 1243 }), "Fortitude hidden")
  local function AnnaSpells()
    local t = {}
    for _, row in ipairs(m.window.def.rows()) do
      if row.key == "Anna-Smith" then for _, i in ipairs(row.icons) do t[i.spell] = true end end
    end
    return t
  end
  local s = AnnaSpells()
  assert(s[324] and not s[408510] and not s[1243], "Anna's row: only Lightning Shield")
  -- the priest learns it
  GetTime = function() return 6000 end
  TEAM_MESSAGE("Bob-Stone", "MBFK:")
  assert(m.Castable({ id = 1243 }), "Fortitude back")
  -- option off: everything shows
  m.M.db.hideUnlearned = false
  GetTime = function() return 7000 end
  s = AnnaSpells()
  assert(s[408510], "option off")
  m.M.db.hideUnlearned = true
  m.SpellInfo, m.SpellCooldown, m.CasterClass, m.State, GetTime = oldInfo, oldCd, oldCaster, oldState, oldTime
  MMT.db.team["Bob-Stone"] = nil
  m.KnownReset()
  return "unlearned buffs ok"
end""")(mod))

# name patterns not learned yet: from the spellbook (learned spells only), shared after "#"
print(lua.eval(r"""function(m)
  local oldInfo, oldEnum, oldSB, oldSafe = m.SpellInfo, Enum, C_SpellBook, rawget(MMT, "Safe")
  MMT.Safe = function(f, ...) local r = { pcall(f, ...) } if r[1] then return unpack(r, 2, 8) end end   -- like the core
  local NAMES = { [324] = "Lightning Shield", [8076] = "Strength of Earth Totem" }
  m.SpellInfo = function(id) return NAMES[id] end
  Enum = { SpellBookItemType = { Spell = 1, FutureSpell = 2 }, SpellBookSpellBank = { Player = 0 },
    WeaponSlot = { MainHand = 1, OffHand = 2 }, ItemEnchantType = { Temporary = 0, Imbue = 1 } }
  local items = { { 1, 324 }, { 2, 8076 } }   -- Lightning Shield learned, the totem only listed for later
  C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #items } end,
    GetSpellBookItemType = function(i) return items[i][1], nil, items[i][2] end,
  }
  m.M.db.specLists = false
  local soe, ls = { name = "Strength of Earth*", caster = "SHAMAN" }, { name = "Lightning*" }
  m.M.db.lists.ALL = { soe }
  m.M.db.lists.SHAMAN = { ls }
  m.KnownReset()
  local pats = m.OwnUnlearnedPatterns()
  assert(#pats == 1 and pats[1] == "Strength of Earth*", "own patterns: " .. #pats)
  assert(m.Unlearned("Anna-Smith", soe) and not m.Unlearned("Anna-Smith", ls), "own pattern check")
  MMT.db.team["Bob-Stone"] = { class = "HUNTER" }
  local aspects = { name = "Aspect of the *" }
  TEAM_MESSAGE("Bob-Stone", "MBFK:#Aspect of the *")
  assert(m.Unlearned("Bob-Stone", aspects), "hunter without aspects")
  TEAM_MESSAGE("Bob-Stone", "MBFK:")
  assert(not m.Unlearned("Bob-Stone", aspects), "hunter learned one")
  m.SpellInfo, Enum, C_SpellBook = oldInfo, oldEnum, oldSB
  rawset(MMT, "Safe", oldSafe)
  MMT.db.team["Bob-Stone"] = nil
  m.KnownReset()
  return "unlearned patterns ok"
end""")(mod))

# a talent spell the game knows by ID (not by a cooldown for its name) counts as learned
print(lua.eval(r"""function(m)
  local oldInfo, oldCd, oldPS = m.SpellInfo, m.SpellCooldown, IsPlayerSpell
  local NAMES = { [16864] = "Omen of Clarity", [17007] = "Leader of the Pack" }
  m.SpellInfo = function(id) return NAMES[id] end
  m.SpellCooldown = function() return nil end                  -- no cooldown known by name for either
  IsPlayerSpell = function(id) return id == 17007 end          -- the talent: known by its ID
  m.M.db.specLists = false
  m.M.db.lists.SHAMAN = { { id = 16864 }, { id = 17007 } }   -- (the test character is a shaman)
  m.M.db.lists.ALL = {}
  m.KnownReset()
  -- only class spells count: give the shaman these two via a fake preset
  table.insert(m.PRESETS, { key = "SHAMAN:TEST", group = "SHAMAN", name = "test", entries = { { id = 16864 }, { id = 17007 } } })
  m.KnownReset()
  local own = m.OwnUnlearned()
  assert(#own == 1 and own[1] == 16864, "talent spell counted as not learned: " .. table.concat(own, ","))
  table.remove(m.PRESETS)
  m.SpellInfo, m.SpellCooldown, IsPlayerSpell = oldInfo, oldCd, oldPS
  m.KnownReset()
  return "talent spells known by ID ok"
end""")(mod))

# weapon enchants need an imbue spell (shaman) / Poisons (rogue); the spellbook may give only action IDs
print(lua.eval(r"""function(m)
  local oldInfo, oldEnum, oldSB, oldSafe = m.SpellInfo, Enum, C_SpellBook, rawget(MMT, "Safe")
  MMT.Safe = function(f, ...) local r = { pcall(f, ...) } if r[1] then return unpack(r, 2, 8) end end
  local NAMES = { [403] = "Lightning Bolt", [8017] = "Rockbiter Weapon" }
  m.SpellInfo = function(id) return NAMES[id] end
  Enum = { SpellBookItemType = { Spell = 1, FutureSpell = 2 }, SpellBookSpellBank = { Player = 0 },
    WeaponSlot = { MainHand = 1, OffHand = 2 }, ItemEnchantType = { Temporary = 0, Imbue = 1 } }
  local items = { { 1, 403 } }                       -- level 1: Lightning Bolt only
  C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #items } end,
    GetSpellBookItemType = function(i) return items[i][1], items[i][2], nil end,   -- action ID only
  }
  m.KnownReset()
  assert(m.SpellbookCount() == 1, "spellbook read from action IDs")
  local mh = { weapon = "MH" }
  assert(not m.OwnCanImbue() and m.Unlearned("Anna-Smith", mh), "level 1 shaman: no imbue")
  items[2] = { 1, 8017 }                             -- learns Rockbiter Weapon
  m.KnownReset()
  assert(m.OwnCanImbue() and not m.Unlearned("Anna-Smith", mh), "imbue learned")
  MMT.db.team["Bob-Stone"] = { class = "ROGUE" }
  TEAM_MESSAGE("Bob-Stone", "MBFK:#@imbue")
  assert(m.Unlearned("Bob-Stone", mh), "rogue without Poisons")
  MMT.db.team["Bob-Stone"] = nil
  m.SpellInfo, Enum, C_SpellBook = oldInfo, oldEnum, oldSB
  rawset(MMT, "Safe", oldSafe)
  m.KnownReset()
  return "imbues learned ok"
end""")(mod))

# one blessing per paladin in the group: with one paladin and Might up (from the group), Kings isn't missing;
# a blessing from a paladin outside the group (a random) doesn't use up the slot
print(lua.eval(r"""function(m)
  local oldInfo, oldBuff, oldPal, oldState = m.SpellInfo, m.Buff, m.PaladinsHere, m.State
  local oldSplit, oldResolve, oldExists = MMT.SplitUnit, MMT.Resolve, UnitExists
  local NAMES = { [19740] = "Blessing of Might", [20217] = "Blessing of Kings", [1038] = "Salvation" }
  m.SpellInfo = function(id) return NAMES[id] end
  m.State = ORIG_STATE
  m.KnownReset()
  assert(m.IsBlessing({ id = 19740 }) and not m.IsBlessing({ id = 1038 }), "Salvation isn't a blessing on Forever")
  m.preview, m.testUntil = nil, nil
  m.PaladinsHere = function() return 1 end
  m.KnownReset()
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Anna", "Smith", "Anna-Smith" end
  MMT.Resolve = function(k) return k end
  MMT.SortedMembers = function() return { "Anna-Smith" } end
  local c = m.M.db
  c.allBar, c.specLists, c.hideNoCaster, c.hideUnlearned, c.blessingLimit = false, false, false, false, true
  c.lists.ALL = {}
  c.lists.SHAMAN = { { id = 19740 }, { id = 20217 } }
  local source = "party1"
  m.Buff = function(unit, i) if unit == "player" and i == 1 then return "Blessing of Might", 135908, 1, 300, GetTime() + 200, source end end
  local function Shown()
    m.ScanGroup()
    local t = {}
    for _, row in ipairs(m.window.def.rows()) do
      if row.key == "Anna-Smith" then for _, i in ipairs(row.icons) do t[i.spell] = i.state end end
    end
    return t
  end
  local s = Shown()
  assert(s[19740] == "buff" and s[20217] == nil, "Kings shown though the one paladin's blessing is up")
  source = nil                                   -- Might from a random outside the group
  s = Shown()
  assert(s[19740] == "buff" and s[20217] == "missing", "a random's blessing used up our paladin's slot")
  source = "party1"
  c.blessingLimit = false
  s = Shown()
  assert(s[20217] == "missing", "option off")
  c.blessingLimit = true
  -- the All bar: Kings left out while the one paladin's blessing (Might) is up
  c.allBar, c.lists.SHAMAN, c.lists.ALL = true, {}, { { id = 19740 }, { id = 20217 } }
  m.ScanGroup()
  local all
  for _, row in ipairs(m.window.def.rows()) do if row.label == "All" then all = row end end
  assert(all and #all.icons == 1 and all.icons[1].spell == 19740 and all.icons[1].state == "buff", "All bar: " .. (all and #all.icons or 0))
  c.allBar = false
  m.SpellInfo, m.Buff, m.PaladinsHere, m.State = oldInfo, oldBuff, oldPal, oldState
  MMT.SplitUnit, MMT.Resolve, UnitExists = oldSplit, oldResolve, oldExists
  m.KnownReset()
  m.ScanGroup()
  return "one blessing per paladin ok"
end""")(mod))

# weapon enchants after a /reload: saved on logout with the real clock and put back, and each
# member is asked once (whispered MBWQ) on their first heartbeat
print(lua.eval(r"""function(m)
  CLOCK = 90000
  function time() return CLOCK end
  local now = GetTime()
  m.weapons = { ["Bob-Stone"] = { MH = { endTime = now + 600, dur = 1800, icon = 136018, name = "Windfury" }, OH = false } }
  FIRE("PLAYER_LOGOUT")
  assert(m.M.store.weaponsSaved and m.M.store.weaponsSaved["Bob-Stone"], "not saved")
  m.weapons = {}
  CLOCK = CLOCK + 100
  assert(m.RestoreWeapons() == 1, "not restored")
  local w = m.weapons["Bob-Stone"]
  assert(w and w.OH == false and w.MH and math.abs(w.MH.endTime - GetTime() - 500) < 0.01 and w.MH.name == "Windfury", "restored enchant")
  SENT = {}
  for _, l in ipairs(LISTEN) do if l[1] == "XP_RECEIVED" then l[2]("Cid-Ray", "Cid", { ext = {} }) end end
  for _, l in ipairs(LISTEN) do if l[1] == "XP_RECEIVED" then l[2]("Cid-Ray", "Cid", { ext = {} }) end end
  local n = 0
  for _, s in ipairs(SENT) do if s == "WHISPER:Cid:MBWQ" then n = n + 1 end end
  assert(n == 1, "MBWQ whispers: " .. n)
  return "weapon enchants after a reload ok"
end""")(mod))

# SmartBuff alerts (Alerts.lua): the team's QSB message makes the member's icon and the All bar's glow
# until they have the buff (a greater blessing counts as the single one); own SmartBuff the same
print(lua.eval(r"""function(m)
  local c = m.M.db
  local oldState, oldInfo, oldCast = m.State, m.SpellInfo, m.Castable
  m.SpellInfo = function(id) return ({ [19740] = "Blessing of Might", [25782] = "Greater Blessing of Might" })[id] end
  m.Castable = function() return true end
  MMT.SortedMembers = function() return { "Anna-Smith", "Bob-Stone" } end
  MMT.RealFirst = function(k) return k:match("^[^-]+") end
  MMT.RealName = function(k) return (k:gsub("-", " ")) end
  MMT.db.team["Bob-Stone"] = { class = "WARRIOR" }
  c.hideUnlearned, c.allBar, c.glowAlerts = false, true, true
  c.lists.ALL = { { id = 19740 } }
  local have = false
  m.State = function(key, e) if key == "Bob-Stone" and not have then return "missing" end return "buff", GetTime() - 10, 300 end
  m.BuildIndex()
  local function AllIcon()
    for _, r in ipairs(m.window.def.rows()) do if r.label then return r.icons[1] end end
  end
  assert(not AllIcon().glow, "glows before any alert")
  -- the team's alert, Bob as SmartBuff writes him, the greater blessing
  TEAM_MESSAGE("Anna-Smith", "QSB:N:0:Bob Stone:Greater Blessing of Might")
  local i = AllIcon()
  assert(i.glow and i.tip:find("SmartBuff"), "All bar icon not glowing after the alert")
  -- the same buff in Bob's own row
  c.allBar = false
  local bob
  for _, r in ipairs(m.window.def.rows()) do if r.key == "Bob-Stone" then bob = r end end
  assert(bob and bob.icons[1].glow, "Bob's icon not glowing")
  c.allBar = true
  -- the setting off: no glow
  c.glowAlerts = false
  assert(not AllIcon().glow, "glow with glowAlerts off")
  c.glowAlerts = true
  -- he has it again: the glow ends (and the alert is forgotten)
  have = true
  assert(not AllIcon().glow, "still glowing with the buff back")
  have = false
  assert(not AllIcon().glow, "the old alert came back")
  -- an unknown target or someone else's name: nothing
  TEAM_MESSAGE("Anna-Smith", "QSB:N:0:Zed:Greater Blessing of Might")
  assert(not AllIcon().glow, "glow for a stranger")
  -- own SmartBuff's alert (the hook), first name only
  m.NoteAlert("N", "Bob", "Blessing of Might")
  assert(AllIcon().glow, "own SmartBuff alert didn't glow")
  m.alerts = {}
  m.State, m.SpellInfo, m.Castable = oldState, oldInfo, oldCast
  return "SmartBuff alerts glow ok"
end""")(mod))

# in combat the game hides aura data ("secret"): the last buffs stay (ones that ran out
# meanwhile show as missing), the unit is read again until it's readable
print(lua.eval(r"""function(m)
  local oldBuff, oldExists, oldTime = m.Buff, UnitExists, GetTime
  local oldSplit, oldResolve = MMT.SplitUnit, MMT.Resolve
  local now, hide, buffs = 1000, false, {}
  GetTime = function() return now end
  m.Buff = function(unit, i)
    if unit ~= "player" then return nil end
    if hide then return "secret" end
    local b = buffs[i] if b then return b[1], 1, 1, b[2], b[3] end
  end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  local bs, fort = { name = "Battle Shout*" }, { name = "Fortitude*" }
  buffs = { { "Battle Shout", 120, 1100 }, { "Fortitude", 1800, 2700 } }
  m.ScanGroup()
  assert(m.State("Me-Realm", bs) == "buff", "readable buff")
  hide = true
  m.ScanGroup()
  assert(m.State("Me-Realm", bs) == "buff", "hidden: last buff kept")
  now = 1101
  assert(m.State("Me-Realm", bs) == "missing", "ran out while hidden: still shown")
  assert(m.State("Me-Realm", fort) == "buff", "pattern kept while time is left")
  -- readable again: the retry reads the new buffs
  hide = false
  buffs = { { "Battle Shout", 120, 1221 } }
  m.RetryHidden()
  assert(m.State("Me-Realm", bs) == "buff", "retry didn't read the unit again")
  assert(m.State("Me-Realm", fort) == "missing", "retry kept an old buff")
  -- an EMPTY list while fighting (the game gave nothing instead of hidden values): kept
  local oldLock, oldUAC = InCombatLockdown, UnitAffectingCombat
  UnitAffectingCombat = function() return false end
  InCombatLockdown = function() return true end
  buffs = {}
  m.ScanGroup()
  assert(m.State("Me-Realm", bs) == "buff", "empty read in combat dropped the buffs")
  InCombatLockdown = function() return false end
  m.RetryHidden()
  assert(m.State("Me-Realm", bs) == "missing", "empty read out of combat: really gone")
  InCombatLockdown, UnitAffectingCombat = oldLock, oldUAC
  m.StopHidden()
  m.Buff, UnitExists, GetTime = oldBuff, oldExists, oldTime
  MMT.SplitUnit, MMT.Resolve = oldSplit, oldResolve
  m.ScanGroup()
  return "hidden auras in combat ok"
end""")(mod))

# seals in combat: the paladin's own casts keep the timer exact while auras are hidden
print(lua.eval(r"""function(m)
  local oldBuff, oldExists, oldTime, oldInfo = m.Buff, UnitExists, GetTime, m.SpellInfo
  local oldSplit, oldResolve = MMT.SplitUnit, MMT.Resolve
  local now, hide = 1000, false
  GetTime = function() return now end
  local NAMES = { [1] = "Seal of Command", [2] = "Seal of the Crusader", [3] = "Judgement", [4] = "Blessing of Might" }
  m.SpellInfo = function(id) return NAMES[id] end
  m.Buff = function(unit, i)
    if unit ~= "player" then return nil end
    if hide then return "secret" end
    if i == 1 then return "Seal of Command", 1, 1, 30, 1020 end
    if i == 2 then return "Blessing of Might", 2, 1, 300, 1200 end
  end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  local seal, bom = { name = "Seal of *" }, { name = "Blessing of Might*" }
  m.ScanGroup()
  hide = true
  local oldHidden = m.AurasHidden
  m.AurasHidden = function() return hide end
  MMT.SplitUnit = function() return nil end        -- the game hides the name in combat too
  m.ScanGroup()                                    -- combat: hidden, last read kept
  m.StopHidden()                                   -- the cast must count without the scan's mark
  now = 1030
  assert(m.State("Me-Realm", seal) == "missing", "old seal ran out")
  SENT = {}
  m.SelfCast("player", 2)                          -- new seal in combat
  assert(SENT[1] == "MBFC:Seal of the Crusader:30", "own seal cast not sent: " .. tostring(SENT[1]))
  local s, st, d, _, n = m.State("Me-Realm", seal)
  assert(s == "buff" and st == 1030 and d == 30 and n == "Seal of the Crusader", "seal from the cast: " .. tostring(s) .. tostring(n))
  now = 1040
  m.SelfCast("player", 1)                          -- another seal replaces it
  s, st, d, _, n = m.State("Me-Realm", seal)
  assert(s == "buff" and st == 1040 and n == "Seal of Command", "seal not replaced")
  local count = 0
  for k in pairs(m.auras["Me-Realm"]) do if k:find("^Seal of") then count = count + 1 end end
  assert(count == 1, "two seals at once")
  m.SelfCast("player", 3)                          -- Judgement: the seal stays on Forever
  assert(m.State("Me-Realm", seal) == "buff", "Judgement ended the seal")
  -- another client's message: that member's seal starts here (their cast isn't seen in combat)
  now = 1050
  TEAM_MESSAGE("Me-Realm", "MBFC:Seal of the Crusader:30")
  s, st, d, _, n = m.State("Me-Realm", seal)
  assert(s == "buff" and st == 1050 and n == "Seal of the Crusader", "MBFC not applied: " .. tostring(n))
  TEAM_MESSAGE("Me-Realm", "MBFC:Blessing of Might:300")   -- only self buffs
  assert(select(2, m.State("Me-Realm", bom)) == 900, "MBFC applied a non-self buff")
  m.SelfCast("player", 4)                          -- a blessing may be on someone else: not guessed
  assert(m.State("Me-Realm", bom) == "buff" and select(2, m.State("Me-Realm", bom)) == 900, "blessing changed by a cast")
  hide = false
  m.StopHidden()
  m.AurasHidden = oldHidden
  m.Buff, UnitExists, GetTime, m.SpellInfo = oldBuff, oldExists, oldTime, oldInfo
  MMT.SplitUnit, MMT.Resolve = oldSplit, oldResolve
  m.ScanGroup()
  return "seals in combat ok"
end""")(mod))

# in combat: tracked buffs asked for by spell ID (learned while readable) - procs like Flurry
# come and go live; a buff never seen readable keeps its last state
print(lua.eval(r"""function(m)
  local oldBuff, oldExists, oldTime, oldHidden = m.Buff, UnitExists, GetTime, m.AurasHidden
  local oldSplit, oldResolve = MMT.SplitUnit, MMT.Resolve
  local oldUA = C_UnitAuras
  local now, hide = 1000, false
  GetTime = function() return now end
  local flurry = nil                                -- what the game would answer by ID
  C_UnitAuras = { GetUnitAuraBySpellID = function(unit, id)
    if unit == "player" and id == 12970 then return flurry end
  end }
  m.Buff = function(unit, i)
    if unit ~= "player" then return nil end
    if hide then return "secret" end
    if i == 1 then return "Flurry", 132152, 3, 15, 1025, "player", 12970 end
    if i == 2 then return "Inner Focus", 1, 1, 0, 0, "player", 14751 end
  end
  m.AurasHidden = function() return hide end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  m.M.db.lists.ALL = m.M.db.lists.ALL or {}
  local fl, inf = { name = "Flurry*" }, { name = "Inner Focus*" }
  table.insert(m.M.db.lists.ALL, fl)
  table.insert(m.M.db.lists.ALL, inf)
  m.TrackedReset()
  m.M.store.auraIds = nil
  m.ScanGroup()                                     -- readable: IDs learned
  -- Forever: the by-ID answer is "nothing" while hidden - nothing may turn missing
  hide = true
  m.ScanGroup()
  assert(m.State("Me-Realm", fl) == "buff", "a blind by-ID answer marked Flurry missing")
  hide = false
  m.ScanGroup()
  assert(m.M.store.auraIds and m.M.store.auraIds.Flurry and m.M.store.auraIds.Flurry[12970], "Flurry's ID not learned")
  m.M.store.auraIds["Inner Focus"] = nil            -- as if never seen readable
  hide = true
  now = 1020
  flurry = { name = "Flurry", applications = 2, duration = 15, expirationTime = 1033, icon = 132152, sourceUnit = "player" }
  m.ScanGroup()                                     -- combat: asked for by ID
  local s, st, d, c = m.State("Me-Realm", fl)
  assert(s == "buff" and st == 1018 and d == 15 and c == 2, "Flurry by ID: " .. tostring(s) .. " " .. tostring(c))
  assert(m.State("Me-Realm", inf) == "buff", "a buff without known IDs was dropped")
  flurry = nil                                      -- the proc fades in combat
  m.RetryHidden()
  assert(m.State("Me-Realm", fl) == "missing", "faded proc still shown")
  hide = false
  m.StopHidden()
  for i = #m.M.db.lists.ALL, 1, -1 do local e = m.M.db.lists.ALL[i] if e == fl or e == inf then table.remove(m.M.db.lists.ALL, i) end end
  m.TrackedReset()
  C_UnitAuras = oldUA
  m.AurasHidden = oldHidden
  m.Buff, UnitExists, GetTime = oldBuff, oldExists, oldTime
  MMT.SplitUnit, MMT.Resolve = oldSplit, oldResolve
  m.ScanGroup()
  return "auras by spell ID in combat ok"
end""")(mod))

# live in combat (Live.lua): each member icon with known spell IDs gets the game's aura widget
# (a stand-in here) set to the member's unit and the buff's IDs, on only while auras are hidden;
# the icon underneath shows the missing look
print(lua.eval(r"""function(m)
  local oldCF, oldBuff, oldExists, oldHidden = CreateFrame, m.Buff, UnitExists, m.AurasHidden
  local oldSplit, oldResolve = MMT.SplitUnit, MMT.Resolve
  local made = {}
  CreateFrame = function(kind, ...)
    if kind ~= "AuraContainer" then return oldCF(kind, ...) end
    local c = oldCF("Frame")
    local rec = { enabled = false }
    made[#made + 1] = rec
    rawset(c, "SetEnabled", function(_, on) rec.enabled = on end)
    rawset(c, "SetUnit", function(_, u) rec.unit = u end)
    rawset(c, "AddAuraSlot", function(_, name, filter, opts)
      rec.slot, rec.filter, rec.ids = name, filter, opts.candidateFilters.includeSpellIDs
      local b = oldCF("Frame")
      rawset(b, "SetIcon", function() rec.icon = true end)
      rawset(b, "SetDurationCooldown", function() rec.cooldown = true end)
      rawset(b, "SetApplicationCount", function() rec.stacks = true end)
      opts.initializeFrame(b)
    end)
    rawset(c, "SetAuraSlotCandidateFilters", function(_, name, f) rec.ids = f.includeSpellIDs end)
    return c
  end
  local hide = false
  m.Buff = function(unit, i)
    if unit ~= "player" then return nil end
    if hide then return "secret" end
    if i == 1 then return "Flurry", 132152, 3, 15, 1025, "player", 12970 end
  end
  m.AurasHidden = function() return hide end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  local oldMembers = m.Members
  m.Members = function() return { "Me-Realm" } end
  local fl = { name = "Flurry*" }
  m.M.db.lists.ALL = m.M.db.lists.ALL or {}
  m.M.db.lists["CHAR:Me-Realm"] = { fl }
  m.TrackedReset()
  m.ScanGroup()                                     -- readable: Flurry's ID learned
  local ids = m.LiveIds(fl)
  assert(ids and ids[12970], "live IDs")
  assert(m.Timed(fl), "Flurry not known as a timed buff (its icon gate)")
  assert(not m.Timed({ name = "Devotion*" }), "a never-seen buff counted as timed")
  m.Redraw()
  local before = #made
  assert(before > 0 and made[1].enabled, "the overlay doesn't draw out of combat (one look in and out of combat)")
  assert(before > 0 and made[1].unit == "player" and made[1].ids[12970], "overlay not set up out of combat")
  hide = true
  m.live = true                                     -- combat (SetLive's queued redraw done by hand)
  m.Redraw()
  local on
  for _, r in ipairs(made) do if r.enabled then on = r end end
  local nIcons, nLive = 0, 0
  for _, w in pairs(MMTIconBars.windows) do for _, row in ipairs(w.rows) do for _, b in ipairs(row.icons) do
    nIcons = nIcons + 1; if b.data and b.data.live then nLive = nLive + 1 end end end end
  assert(on, "no live overlay in combat (" .. #made .. " made, icons " .. nIcons .. " live " .. nLive .. " unit " .. tostring(m.UnitOf("Me-Realm")) .. ")")
  assert(on.unit == "player" and on.ids[12970] and on.filter == "HELPFUL", "overlay set wrong: " .. tostring(on.unit))
  assert(on.icon and on.cooldown and on.stacks, "overlay doesn't draw icon / countdown / stacks")
  assert(#made == before, "an overlay was built in combat")
  local lines = {}
  m.LiveReport(function(l) lines[#lines + 1] = l end)
  assert(#lines == 3 and lines[2]:find("drawing 1"), "report: " .. tostring(lines[2]))
  -- the icon underneath: the missing look
  local under
  for _, w in pairs(MMTIconBars.windows) do
    for _, row in ipairs(w.rows) do for _, b in ipairs(row.icons) do
      if b.data and b.data.live then under = b.data end
    end end
  end
  assert(under and under.state == "missing" and not under.start, "underneath not the missing look")
  m.live = false
  hide = false
  m.Redraw()
  assert(made[1].enabled, "the overlay went off after combat (the icons jumped)")
  m.StopLive()
  m.M.db.lists["CHAR:Me-Realm"] = nil
  m.TrackedReset()
  m.Members = oldMembers
  CreateFrame, m.Buff, UnitExists, m.AurasHidden = oldCF, oldBuff, oldExists, oldHidden
  MMT.SplitUnit, MMT.Resolve = oldSplit, oldResolve
  m.ScanGroup()
  return "live overlays in combat ok"
end""")(mod))

# Battle Shout cast in combat refreshes it on the whole group (the All bar counts from these)
print(lua.eval(r"""function(m)
  local oldBuff, oldExists, oldTime, oldInfo, oldHidden = m.Buff, UnitExists, GetTime, m.SpellInfo, m.AurasHidden
  local oldSplit, oldResolve, oldUA, oldRaid = MMT.SplitUnit, MMT.Resolve, C_UnitAuras, IsInRaid
  C_UnitAuras = {}
  IsInRaid = function() return false end
  local now, hide = 1000, false
  GetTime = function() return now end
  m.SpellInfo = function(id) if id == 25289 then return "Battle Shout" end end
  m.Buff = function(unit, i)
    if hide then return "secret" end
    if i == 1 then return "Battle Shout", 1, 1, 120, 1060 end
  end
  m.AurasHidden = function() return hide end
  m.preview, m.testUntil = nil, nil
  UnitExists = function(u) return u == "player" or u == "party1" end
  MMT.SplitUnit = function(u) if u == "player" then return "Me", "Realm", "Me-Realm" end return "Bo", "Realm", "Bo-Realm" end
  MMT.Resolve = function(k) return k end
  local bs = { name = "Battle Shout*" }
  m.ScanGroup()
  hide = true
  m.ScanGroup()
  now = 1050
  SENT = {}
  m.SelfCast("player", 25289)
  for _, k in ipairs({ "Me-Realm", "Bo-Realm" }) do
    local s, st, d = m.State(k, bs)
    assert(s == "buff" and st == 1050 and d == 120, k .. " not refreshed: " .. tostring(st))
  end
  assert(SENT[1] == "MBFC:Battle Shout:120", "not sent: " .. tostring(SENT[1]))
  hide = false
  m.StopHidden()
  m.Buff, UnitExists, GetTime, m.SpellInfo, m.AurasHidden = oldBuff, oldExists, oldTime, oldInfo, oldHidden
  MMT.SplitUnit, MMT.Resolve, C_UnitAuras, IsInRaid = oldSplit, oldResolve, oldUA, oldRaid
  m.ScanGroup()
  return "Battle Shout refreshes the group ok"
end""")(mod))

# an aura nobody tracks coming or going doesn't redraw the bars (memory churn); a tracked one does
print(lua.eval(r"""function(m)
  local oldBuff, oldExists, oldSplit, oldResolve, oldRefresh = m.Buff, UnitExists, MMT.SplitUnit, MMT.Resolve, m.Refresh
  local auras = { { "Battle Shout", 120, 2000 } }
  m.Buff = function(unit, i) local a = unit == "player" and auras[i] if a then return a[1], 1, 1, a[2], a[3] end end
  UnitExists = function(u) return u == "player" end
  MMT.SplitUnit = function() return "Me", "Realm", "Me-Realm" end
  MMT.Resolve = function(k) return k end
  m.M.db.lists["CHAR:Me-Realm"] = { { name = "Battle Shout*" } }
  m.TrackedReset()
  m.TrackedReset()
  m.ScanGroup()
  local n = 0
  m.Refresh = function() n = n + 1 end
  auras = { { "Battle Shout", 120, 2000 }, { "Sunder Armor", 30, 1500 } }
  FIRE("UNIT_AURA", "player")
  assert(n == 0, "an untracked aura redrew the bars")
  auras = { { "Battle Shout", 120, 2100 }, { "Sunder Armor", 30, 1500 } }
  FIRE("UNIT_AURA", "player")
  assert(n == 1, "a refreshed tracked buff didn't redraw")
  auras = { { "Sunder Armor", 30, 1500 } }
  FIRE("UNIT_AURA", "player")
  assert(n == 2, "a tracked buff falling off didn't redraw")
  m.Refresh = oldRefresh
  m.M.db.lists["CHAR:Me-Realm"] = nil
  m.TrackedReset()
  m.Buff, UnitExists, MMT.SplitUnit, MMT.Resolve = oldBuff, oldExists, oldSplit, oldResolve
  m.ScanGroup()
  return "redraw only on tracked changes ok"
end""")(mod))
