"""SettingsKit's mod.Tabs: a tab whose `blocked` returns a reason is greyed, can't be
opened and shows the reason in its tooltip (QoL: the addon a feature needs is missing)."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local function Tex()
  local t = { shown = true }
  for _, k in ipairs({ "SetColorTexture", "SetHeight", "SetSize", "SetPoint", "SetAllPoints", "SetTexture", "SetTexCoord", "SetDesaturated" }) do t[k] = function() end end
  function t:SetShown(v) self.shown = v and true or false end
  return t
end
local function Frame(kind)
  local f = { shown = true, scripts = {}, hooks = {}, kind = kind }
  function f:SetPoint() end
  function f:SetSize() end
  function f:GetHeight() return 560 end
  function f:SetShown(v) self.shown = v and true or false end
  function f:HookScript(ev, fn) self.hooks[ev] = fn end
  function f:SetScript(ev, fn) self.scripts[ev] = fn end
  function f:CreateTexture() return Tex() end
  return f
end
BUTTONS = {}
function CreateFrame(kind) local f = Frame(kind) if kind == "Button" then BUTTONS[#BUTTONS + 1] = f end return f end
TIP = {}
GameTooltip = { SetOwner = function() TIP = {} end, SetText = function(_, t) TIP.title = t end,
  AddLine = function(_, t) TIP.line = t end, Show = function() TIP.shown = true end, Hide = function() TIP.shown = false end }
MMT = { UI = { ACCENT = { 0.2, 0.6, 1 } }, ConfigHelpers = { PAGE_W = 698 } }
function MMT.UI.Label(parent, text)
  local fs = { text = text }
  for _, k in ipairs({ "SetPoint", "SetJustifyH", "SetWordWrap" }) do fs[k] = function() end end
  function fs:SetTextColor(r) self.r = r end
  return fs
end
''')
mod = lua.eval('{}')
lua.eval('function(src, m) assert(loadstring(src, "SettingsKit.lua"))("x", m) end')(
    open('MMT_QoL/SettingsKit.lua', encoding='utf-8').read(), mod)

print(lua.eval(r'''function(m)
  local page = CreateFrame()
  BUTTONS = {}
  local missing = true
  local panels = m.Tabs(page, {
    { "dejunk", "Dejunk", blocked = function() if missing then return "Dejunk is not installed. This tab needs it." end end },
    { "auras", "ForeverAuras" },
  })
  -- the blocked first tab is skipped: the first open one shows
  assert(not panels.dejunk.shown and panels.auras.shown, "a blocked tab opened at start")
  assert(BUTTONS[1].label.r == 0.35, "blocked tab not greyed")
  -- clicking it does nothing
  BUTTONS[1].scripts.OnClick()
  assert(not panels.dejunk.shown and panels.auras.shown, "a blocked tab opened on click")
  -- its tooltip says why
  BUTTONS[1].hooks.OnEnter(BUTTONS[1])
  assert(TIP.shown and TIP.line:find("not installed", 1, true), "no reason in the tooltip")
  -- an open tab has no such tooltip
  assert(BUTTONS[2].hooks.OnEnter == nil, "tooltip hook on an open tab")
  -- once the addon is there, it opens
  missing = false
  BUTTONS[1].scripts.OnClick()
  assert(panels.dejunk.shown and not panels.auras.shown, "tab didn't open once allowed")
  -- the core's tab strip look: the open tab is underlined, the others not
  assert(BUTTONS[1].bar.shown and not BUTTONS[2].bar.shown, "the open tab isn't the underlined one")
  assert(BUTTONS[1].label.text == "Dejunk" and BUTTONS[1].icon, "tab without label / icon")
  return "blocked tabs ok"
end''')(mod))
