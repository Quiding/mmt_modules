"""MMT_BuffTimers: the All bar's counter (how many members have a buff, in its own
corner) - the whole module loaded with test_settings' stand-in API."""
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
MMT.NewModule = function(def)
  local M = nm(def)
  function M:Listen(ev, fn) LISTEN[#LISTEN + 1] = { ev, fn } end
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
  -- 2 of 3 have it: "2" in the bottom left, white, size 12 (defaults)
  local i = AllIcon()
  assert(i.state == "missing" and i.tally == 2 and i.tallyPos == "BOTTOMLEFT" and i.tallySize == 12, "counter: " .. tostring(i.tally))
  assert(i.count == nil, "the missing count still shows next to the counter")
  assert(i.tip:find("2 have it", 1, true), "tooltip")
  -- one has it: no counter
  HAVE = { ["Anna-Smith"] = true }
  i = AllIcon()
  assert(i.tally == nil, "counter shown for one")
  -- everyone: "3", the corner and size from the settings
  HAVE = { ["Anna-Smith"] = true, ["Bob-Stone"] = true, ["Cid-Ray"] = true }
  c.allCount, c.allCountSize = "TOPRIGHT", 16
  i = AllIcon()
  assert(i.state == "buff" and i.tally == 3 and i.tallyPos == "TOPRIGHT" and i.tallySize == 16, "counter everyone")
  -- off
  c.allCount = "OFF"
  i = AllIcon()
  assert(i.tally == nil, "counter while off")
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
  for _, row in ipairs(m.window.def.rows()) do if row.key then keys[#keys + 1] = row.key end end
  assert(#keys == 1 and keys[1] == "Anna-Smith", "empty row: " .. table.concat(keys, ","))
  m.State = oldState
  return "empty rows hidden ok"
end""")(mod))
