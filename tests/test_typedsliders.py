"""TypedSliders.lua (shared by our modules): a slider built like MMT core's UI.Slider (a container with the
label TOPLEFT, the value TOPRIGHT and a Slider child) gets a clickable value: typing "250%" sets the
slider (in range, on its step), Escape leaves it, a disabled slider isn't edited, sliders built later
(tabs) are found too."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
TICKERS = {}
C_Timer = { After = function(_, fn) fn() end, NewTicker = function(_, fn) TICKERS[#TICKERS + 1] = fn; return {} end }
local function Obj(kind, parent)
  local o = { kind = kind, kids = {}, regions = {}, scripts = {}, shown = true, points = {} }
  if parent then table.insert(parent.kids, o) end
  function o:GetObjectType() return self.kind end
  function o:GetChildren() return unpack(self.kids) end
  function o:GetRegions() return unpack(self.regions) end
  function o:SetPoint(p, ...) self.points[#self.points + 1] = p end
  function o:GetPoint(i) return self.points[i or 1] end
  function o:SetScript(k, fn) self.scripts[k] = fn end
  function o:HookScript(k, fn) self.scripts[k] = fn end
  function o:Show() self.shown = true end
  function o:Hide() self.shown = false end
  function o:IsVisible() return self.shown end
  function o:CreateTexture() local t = Obj("Texture"); t.SetAllPoints = function() end; t.SetColorTexture = function() end; return t end
  function o:CreateFontString() local f = Obj("FontString"); table.insert(self.regions, f); return f end
  for _, n in ipairs({ "SetSize", "SetAutoFocus", "SetFontObject", "SetJustifyH", "SetTextInsets", "ClearFocus", "SetFocus", "HighlightText" }) do o[n] = function() end end
  function o:GetFontObject() return nil end
  function o:SetText(t) self.text = t end
  function o:GetText() return self.text end
  return o
end
function CreateFrame(kind, _, parent) return Obj(kind, parent) end
-- core's slider: container c, label, value (TOPRIGHT), Slider s
function SLIDER(parent, min, max, step, start)
  local c = Obj("Frame", parent)
  local label = c:CreateFontString(); label:SetPoint("TOPLEFT")
  local value = c:CreateFontString(); value:SetPoint("TOPRIGHT")
  local s = Obj("Slider", c)
  s.v, s.enabled = start, true
  function s:GetValue() return self.v end
  function s:GetMinMaxValues() return min, max end
  function s:GetValueStep() return step end
  function s:IsEnabled() return self.enabled end
  function s:SetValue(v) self.v = v; SET = v end
  return c, s, value
end
''')
mod = lua.eval('{}')
lua.eval('function(src, m) assert(loadstring(src, "TypedSliders.lua"))("x", m) end')(
    open('MMT_QoL/TypedSliders.lua', encoding='utf-8').read(), mod)

print(lua.eval(r'''function(m)
  local out = {}
  local function check(name, got, want)
    if got ~= want then error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
    out[#out + 1] = name
  end
  check("250%", m.ParseTyped("250%"), 250)
  check("spaces", m.ParseTyped(" 300 % "), 300)
  check("comma", m.ParseTyped("0,5"), 0.5)
  check("not a number", m.ParseTyped("abc"), nil)
  check("too high: max", m.FitTyped(9000, 100, 1000, 25), 1000)
  check("too low: min", m.FitTyped(5, 100, 1000, 25), 100)
  check("onto the step", m.FitTyped(262, 100, 1000, 25), 250)
  check("small steps", m.FitTyped(0.53, 0.5, 2, 0.05), 0.55)

  local page = CreateFrame("Frame")
  local tile = CreateFrame("Frame", nil, page)
  local c, s, value = SLIDER(tile, 100, 1000, 25, 300)
  m.TypedSliders(page)
  local box = c.mmtTyped
  check("box made", box ~= nil, true)
  check("box hidden", box.shown, false)
  local hit
  for _, k in ipairs(c.kids) do if k.kind == "Button" then hit = k end end
  hit.scripts.OnClick()
  check("click: box shown", box.shown, true)
  check("value hidden", value.shown, false)
  check("current value in it", box.text, "300")
  box:SetText("475%"); box.scripts.OnEnterPressed()
  check("set onto the step", SET, 475)
  check("value back", value.shown, true)
  check("box gone", box.shown, false)
  SET = nil
  hit.scripts.OnClick(); box:SetText("nope"); box.scripts.OnEnterPressed()
  check("not a number: unchanged", SET, nil)
  hit.scripts.OnClick(); box:SetText("2000"); box.scripts.OnEscapePressed()
  check("escape: unchanged", SET, nil)
  s.enabled = false; box.shown = false
  hit.scripts.OnClick(); check("disabled: no box", box.shown, false)
  -- a tab built later: found by the ticker
  local later = CreateFrame("Frame", nil, page)
  local c2 = SLIDER(later, 0.5, 2, 0.05, 1)
  TICKERS[#TICKERS]()
  check("later slider found", c2.mmtTyped ~= nil, true)
  local made = 0
  for _, k in ipairs(c.kids) do if k.kind == "EditBox" then made = made + 1 end end
  TICKERS[#TICKERS]()
  check("once per slider", made, 1)
  return table.concat(out, ", ")
end''')(mod))
print("PASS")
