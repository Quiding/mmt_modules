"""Every setting of every module, through everything that can happen to it (stand-in widgets
of test_settings.py):
- each checkbox both ways, each cycle through all its choices, each slider at both ends,
  each colour changed; after each one the page refreshes and OnProfileChanged runs
- every default key set to another value, then: a core sync (M.db REPLACED by a new table as
  the core's ImportModuleSettings does, syncExclude keys kept), the page built again on the new
  table, reset to defaults (= the defaults again, OnProfileChanged ran), profile change
- module switched off (OnDisable) and on again (OnEnable)
A setting that errors, a reset that leaves something behind or skips OnProfileChanged, or a
module that still reads the old table after a sync fails here."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_settings.py"), encoding="utf-8").read()
STUBS = src[src.index("STUBS = r'''") + 12: src.index("'''\n\nfor folder")]

EXTRA = r'''
-- one-time migration flags OnProfileChanged sets again (takenFrom: Cooldown / Buff Timers; toLeader: Whispers)
MIGRATED = { takenFrom = true, toLeader = true }
CONFIRMS = {}   -- text -> function of every H.ConfirmButton
rawset(MMT.ConfigHelpers, "ConfirmButton", function(_, _, text, fn) CONFIRMS[text] = fn; return STUB() end)
C_Container = {}   -- no bags, equipment or mail here
function GetInventoryItemID() return nil end
function GetInboxNumItems() return 0 end
function MMT.Safe(f, ...)   -- like the core's: 7 values at most
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if r[1] then return unpack(r, 2, 8) end
end
PROFILE_CHANGES = 0
function DEEPEQ(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not DEEPEQ(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
-- the core's MergeDefaults (MMT/Profiles.lua), run on M.db at every login, profile change and sync:
-- a value whose TYPE differs from its default is put back to the default
local function IsArray(t) return next(t) == nil or t[1] ~= nil end
function MERGE(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = MMT.CopyTable(v)
      elseif not IsArray(v) then MERGE(dst[k], v) end
    elseif dst[k] == nil or type(dst[k]) ~= type(v) then
      dst[k] = v
    end
  end
end
-- another value of the same type
function OTHER(v)
  if type(v) == "boolean" then return not v end
  if type(v) == "number" then return v + 1 end
  if type(v) == "string" then return v end   -- choices: the cycles go through them
  if type(v) == "table" then
    if v.r then return { r = 0.11, g = 0.22, b = 0.33 } end
    return v
  end
  return v
end
'''

RUN = r'''function(m, folder)
  local M = m.M
  local fails = {}
  local function Try(what, fn, ...)
    local args = { ... }
    local ok, err = xpcall(function() return fn(unpack(args)) end, function(e) return tostring(e) .. " | " .. debug.traceback("", 2):sub(1, 600) end)
    if not ok then fails[#fails + 1] = what .. ": " .. tostring(err) end
    return ok
  end
  local real = M.OnProfileChanged
  if real then M.OnProfileChanged = function(...) PROFILE_CHANGES = PROFILE_CHANGES + 1; return real(...) end end
  local function Changed() if M.OnProfileChanged then M.OnProfileChanged(M) end end
  if M.OnEnable then Try("OnEnable", M.OnEnable, M) end

  -- the page, and every control at every value
  local page
  local function Build()
    USES, CYCLES, CYCLE_GS, CONFIRMS = {}, {}, {}, {}
    page = STUB()
    M.Page(M, page)
    if rawget(page, "OnRefresh") then page.OnRefresh() end
  end
  local function Refresh() if rawget(page, "OnRefresh") then page.OnRefresh() end end
  Try("page", Build)
  local n = 0
  for label, gs in pairs(CYCLE_GS) do
    local g, s = gs[1], gs[2]
    local list = CYCLES[label]
    if type(list) == "function" then list = list() end
    local was = g()
    for _, c in ipairs(list or {}) do
      if not c.header and c.value ~= nil and not (type(c.value) == "string" and c.value:find("^__")) then
        n = n + 1
        Try("cycle " .. label .. " = " .. tostring(c.value), function()
          s(c.value); Refresh(); Changed()
          local now = g()
          MERGE(M.db, M.defaults or {})   -- a /reload
          assert(g() == now, "lost after a /reload: " .. tostring(now) .. " -> " .. tostring(g()))
        end)
      end
    end
    Try("cycle " .. label .. " back", function() s(was) end)
  end
  -- checks / sliders / colours: test_settings' USE() reads and sets back; here flip / move them
  local checks = {}
  local col = UI.Column
  UI.Column = function(...)
    local c = col(...)
    rawset(c, "Check", function(_, text, g, s) checks[#checks + 1] = { "check " .. text, g, s, "b" }; return STUB() end)
    rawset(c, "Slider", function(_, text, lo, hi, step, g, s) checks[#checks + 1] = { "slider " .. text, g, s, "n", lo, hi }; return STUB() end)
    rawset(c, "Color", function(_, text, g, s) checks[#checks + 1] = { "colour " .. text, g, s, "c" }; return STUB() end)
    return c
  end
  Try("page (controls)", Build)
  UI.Column = col
  for _, c in ipairs(checks) do
    local label, g, s, kind = c[1], c[2], c[3], c[4]
    local was = g()
    local vals = kind == "b" and { not was, was } or kind == "n" and { c[5], c[6], was }
      or { { r = 0.1, g = 0.2, b = 0.3 }, was }
    for _, v in ipairs(vals) do
      n = n + 1
      Try(label .. " = " .. tostring(v), function()
        s(v); Refresh(); Changed()
        local now = g()
        MERGE(M.db, M.defaults or {})   -- a /reload
        assert(DEEPEQ(g(), now), "lost after a /reload: " .. tostring(now) .. " -> " .. tostring(g()))
      end)
    end
  end

  -- every default changed, then a core sync onto a NEW table
  local defaults = M.defaults or {}
  for k, v in pairs(defaults) do M.db[k] = MMT.CopyTable(OTHER(v)) end
  local data = MMT.CopyTable(M.db)
  local keep = {}
  for _, k in ipairs(M.syncExclude or {}) do keep[k] = true; data[k] = nil end
  local old = M.db
  for _, k in ipairs(M.syncExclude or {}) do data[k] = old[k] end
  for k, v in pairs(defaults) do if data[k] == nil then data[k] = MMT.CopyTable(v) end end
  M.db = data
  if M.enabled and M.OnProfileChanged then Try("sync: OnProfileChanged", M.OnProfileChanged, M) end
  if M.OnSyncReceived then Try("sync: OnSyncReceived", M.OnSyncReceived, M, "Bob-Jones") end
  Try("page after sync", Build)
  -- the old table must not be read any more: poison it
  setmetatable(old, { __index = function(_, k) error("old M.db read after sync: " .. tostring(k)) end })
  for k in pairs(old) do old[k] = nil end
  Try("page refresh after sync", Refresh)

  -- reset to defaults: the module's button (or SettingsKit's)
  PROFILE_CHANGES = 0
  -- Cooldown / Buff Timers' old module names still in the profile: a reset must not take them over again
  MMT.db.modules = { Cooldowns = { iconSize = 77, shown = false }, Buffs = { iconSize = 77, shown = false } }
  local reset = CONFIRMS["Reset to defaults"] or m.ResetSettings
  if not reset then fails[#fails + 1] = "no reset to defaults"
  else
    Try("reset", reset)
    for k, v in pairs(defaults) do
      if not DEEPEQ(M.db[k], v) then fails[#fails + 1] = "reset left " .. k .. " = " .. tostring(M.db[k]) end
    end
    for k in pairs(M.db) do
      if defaults[k] == nil and not MIGRATED[k] then fails[#fails + 1] = "reset kept " .. k end
    end
    if M.OnProfileChanged and PROFILE_CHANGES == 0 then fails[#fails + 1] = "reset ran no OnProfileChanged" end
  end
  MMT.db.modules = nil

  -- export -> import: every setting comes back (not the key binding: it belongs to one computer)
  if m.TransferDef then
    local NOT_EXPORTED = { keybind = true, takenFrom = true }
    local want = {}
    for k, v in pairs(defaults) do
      if not NOT_EXPORTED[k] then
        want[k] = OTHER(v)
        if k == "point" then want[k] = { "TOPLEFT", "TOPLEFT", 11, -22 } end
        M.db[k] = MMT.CopyTable(want[k])
      end
    end
    local def = m.TransferDef()
    local data = {}
    for _, sec in ipairs(def.sections) do data[sec.id] = sec.get() end
    local text = MMTTransfer.Encode(def.prefix, data)
    local back = assert(MMTTransfer.Decode(def.prefix, text))
    Try("reset before import", m.ResetSettings or reset)
    for _, sec in ipairs(def.sections) do
      -- a section of nothing but empty tables (Totems' chosen totems / presets: test_totems.py) may say "nothing"
      local empty = type(back[sec.id]) == "table"
      for _, v in pairs(back[sec.id] or {}) do if type(v) ~= "table" or next(v) ~= nil then empty = false end end
      Try("import " .. sec.id, function() local ok, why = sec.set(back[sec.id]); assert(ok or empty, why) end)
    end
    if def.after then Try("import: after", def.after) end
    for k, v in pairs(want) do
      if not DEEPEQ(M.db[k], v) then fails[#fails + 1] = "export / import lost " .. k .. " (" .. tostring(M.db[k]) .. ")" end
    end
  end

  -- off and on again
  if M.OnDisable then M.enabled = false; Try("OnDisable", M.OnDisable, M) end
  M.enabled = true
  if M.OnEnable then Try("OnEnable again", M.OnEnable, M) end
  Try("page at the end", Build)

  if #fails > 0 then return "FAIL " .. folder .. "\n  " .. table.concat(fails, "\n  ") end
  return folder .. ": " .. n .. " control values, sync / reset / off-on" .. (m.TransferDef and " / export-import" or "") .. " ok"
end'''

bad = 0
for folder in ["MMT_PawnCompare", "MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems", "MMT_Whispers", "MMT_TeamGear", "MMT_TeamInventory", "MMT_QoL", "MMT_qStyles"]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(EXTRA)
    toc = [l.strip() for l in open(os.path.join(folder, folder + ".toc"), encoding="utf-8") if l.strip().endswith(".lua")]
    mod = lua.eval("{}")
    for f in toc:
        s = open(os.path.join(folder, f), encoding="utf-8").read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(s, folder + "/" + f, mod)
    out = lua.eval(RUN)(mod, folder)
    print(out)
    bad += out.startswith("FAIL")
sys.exit(1 if bad else 0)
