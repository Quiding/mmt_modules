"""Builds every settings page (all tabs) of Cooldowns, Buffs and Totems with
stand-in widgets. Each checkbox / slider / dropdown / colour gets its getter
called and its value set back, and dropdown choice lists are built, so a
broken option or a missing helper fails here instead of in the game."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
-- universal stand-in: any field is callable, any call returns another stand-in
local U = {}
local NUM = { GetHeight = 564, GetWidth = 518, GetStringWidth = 50, GetFrameLevel = 1, GetEffectiveScale = 1, GetScale = 1 }
local function new() return setmetatable({}, U) end
STUB = new
U.__index = function(t, k)
  if NUM[k] then return function() return NUM[k] end end
  if k == "IsShown" or k == "IsVisible" or k == "HasFocus" then return function() return false end end
  if k == "GetText" then return function() return "" end end
  local s = new(); rawset(t, k, s); return s
end
U.__call = function() return new() end
-- globals that must really be missing (libraries this code creates, optional APIs)
local MISSING = { MMTIconBars = true, MMTTransfer = true, LibStub = true, BackdropTemplateMixin = true,
  issecretvalue = true, GetSpellInfo = true, UnitBuff = true, GetSpellCooldown = true, ChatEdit_InsertLink = true }
setmetatable(_G, { __index = function(_, k) if MISSING[k] then return nil end return new() end })

-- columns remember every getter / setter / choices; they are used after the page is built
USES = {}
function USE(fn) USES[#USES + 1] = fn end
local function Choices(c) if type(c) == "function" then c = c() end return c end
local function Column()
  local col = new()
  rawset(col, "Header", function() return new() end)
  rawset(col, "Note", function() return new() end)
  rawset(col, "Space", function() end)
  rawset(col, "Add", function(_, f) return f end)
  rawset(col, "Button", function() return new() end)
  rawset(col, "Check", function(_, text, g, s) assert(type(g) == "function" and type(s) == "function", "check " .. text .. ": no getter/setter"); USE(function() s(g()) end); return new() end)
  rawset(col, "Slider", function(_, text, lo, hi, step, g, s) assert(type(g) == "function" and type(s) == "function", "slider " .. text); USE(function() local v = g(); assert(type(v) == "number", "slider " .. text .. " value " .. tostring(v)); s(v) end); return new() end)
  rawset(col, "Cycle", function(_, text, choices, g, s)
    assert(type(g) == "function" and type(s) == "function", "cycle " .. text .. ": no getter/setter")
    USE(function()
    local list = Choices(choices)
    assert(type(list) == "table" and #list > 0, "cycle " .. text .. ": no choices")
    local v = g()
    local found = false
    for _, c in ipairs(list) do if not c.header and c.value == v then found = true end end
    assert(found, "cycle " .. text .. ": current value " .. tostring(v) .. " not in its choices")
    s(v)
    end)
    return new()
  end)
  rawset(col, "Color", function(_, text, g, s) USE(function() local c = g(); assert(type(c) == "table" and c.r, "colour " .. text); s(c) end); return new() end)
  return col
end

local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
UI = { ROW = 22, ACCENT = { 0.3, 0.7, 1 } }
UI.Column = function() return Column() end
setmetatable(UI, { __index = function() return function() return new() end end })
local frames = {}
function CreateFrame(_, name) local f = new(); if name then rawset(_G, name, f) end return f end
UIParent = new()
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", SHAMAN = "Shaman", PRIEST = "Priest", MAGE = "Mage" }
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
C_Timer = { After = function() end, NewTicker = function() return new() end }
C_AddOns = { GetAddOnMetadata = function() return "0" end }
SlashCmdList = {}
function InCombatLockdown() return false end
function GetTime() return 1000 end
function UnitClass() return "Shaman", "SHAMAN" end
function hooksecurefunc() end
MMT = {
  UI = UI, CopyTable = copy, fonts = { { name = "Friz", path = "x" } },
  ConfigHelpers = setmetatable({ COL_W = 248, COL2_X = 270, PAGE_W = 518 }, { __index = function() return function() return new() end end }),
  db = { team = { ["Anna-Smith"] = { class = "SHAMAN" } }, roles = { Healer = {} } },
  IsSecret = function() return false end,
}
function MMT.SortedMembers() return { "Anna-Smith" } end
function MMT.SortedRoleNames() return { "Healer" } end
function MMT.MemberRoleList() return {} end
function MMT.IsSelf(k) return k == "Anna-Smith" end
function MMT.PlayerFull() return "Anna-Smith" end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return k end
function MMT.IsOnline() return true end
setmetatable(MMT, { __index = function() return function() return new() end end })
function MMT.NewModule(def)
  local M = def
  M.enabled = true
  M.db = copy(def.defaults)
  M.store = {}
  function M:On() end
  function M:Listen() end
  function M:Debug() end
  function M:Heartbeat() end
  return M
end
'''

for folder in ["MMT_Cooldowns", "MMT_Buffs", "MMT_Totems", "MMT_Whispers"]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    toc = [l.strip() for l in open(os.path.join(folder, folder + ".toc"), encoding="utf-8") if l.strip().endswith(".lua")]
    mod = lua.eval("{}")
    for f in toc:
        src = open(os.path.join(folder, f), encoding="utf-8").read()
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(src, folder + "/" + f, mod)
    print(lua.eval(r'''function(m, folder)
      local page = STUB()
      m.M.Page(m.M, page)
      if rawget(page, "OnRefresh") then page.OnRefresh() end
      for _, use in ipairs(USES) do use() end
      if rawget(page, "OnRefresh") then page.OnRefresh() end
      return folder .. ": settings page built, " .. #USES .. " options read and set"
    end''')(mod, folder))
