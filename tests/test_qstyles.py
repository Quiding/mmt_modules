"""Styles (MMT_qStyles): builds MMT's REAL widgets (MMT/Widgets.lua, read only) on stand-in frames
that keep their regions / children in creation order, colours, anchors, sizes and fonts, then
switches None -> ElvUI -> EllesmereUI -> None and checks what changed and that None gives back
exactly what MMT set. Also: frames built after a style was picked, the accent / font options,
coloured fills left alone, the core's background picker (pull request "settings-background"),
the QStyles API (Team Inventory's bags window), the settings window's nav bars, the module
switched off, and a hook problem never breaking the core's call."""
import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])

STUBS = r'''
local unpack = unpack
local Object = {}
Object.__index = Object
local function new(kind, parent, layer, sub)
  local o = setmetatable({ _kind = kind, _parent = parent, _points = {}, _regions = {}, _children = {},
    _shown = true, _w = 0, _h = 0, _layer = layer, _sub = sub, _scripts = {} }, Object)
  return o
end
function Object:GetObjectType() return self._kind end
function Object:GetParent() return self._parent end
function Object:GetName() return self._name end
function Object:SetSize(w, h) self._w, self._h = w, h end
function Object:SetWidth(w) self._w = w end
function Object:SetHeight(h) self._h = h end
function Object:GetWidth() return self._w end
function Object:GetHeight() return self._h end
function Object:SetPoint(p, rel, rp, x, y)
  if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
  self._points[#self._points + 1] = { p, rel or self._parent, rp or p, x or 0, y or 0 }
end
function Object:SetAllPoints() self:SetPoint("TOPLEFT"); self:SetPoint("BOTTOMRIGHT") end
function Object:ClearAllPoints() self._points = {} end
function Object:GetNumPoints() return #self._points end
function Object:GetPoint(i) local p = self._points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Object:Show() self._shown = true end
function Object:Hide() self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end
function Object:SetShown(v) if v then self:Show() else self:Hide() end end
function Object:IsShown() return self._shown end
function Object:IsVisible() return self._shown end
function Object:GetRegions() return unpack(self._regions) end
function Object:GetNumRegions() return #self._regions end
function Object:GetChildren() return unpack(self._children) end
function Object:GetNumChildren() return #self._children end
function Object:SetScript(k, fn) self._scripts[k] = fn end
function Object:GetScript(k) return self._scripts[k] end
function Object:HookScript(k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end fn(...) end end
function Object:GetFrameLevel() return 1 end
function Object:GetEffectiveScale() return 1 end
function Object:GetBottom() return 300 end
-- textures
function Object:CreateTexture(_, layer, _, sub)
  local t = new("Texture", self, layer or "ARTWORK", sub)
  self._regions[#self._regions + 1] = t
  return t
end
function Object:SetColorTexture(r, g, b, a) self._color = { r, g, b, a or 1 }; self._file = nil end
function Object:SetTexture(f) self._file = f end
function Object:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a or 1 }; self._gradient = nil end
function Object:SetGradient(o, c1, c2) self._gradient = { o, c1, c2 } end
function Object:GetDrawLayer() return self._layer, self._sub or 0 end
function Object:SetTexCoord() end
function Object:SetDesaturated() end
function Object:SetAlpha() end
-- font strings
local FONTS = { GameFontHighlightSmall = { "Fonts\\FRIZQT__.TTF", 10, "" }, GameFontNormal = { "Fonts\\FRIZQT__.TTF", 12, "" },
  GameFontNormalLarge = { "Fonts\\FRIZQT__.TTF", 16, "" } }
function Object:CreateFontString(_, layer, template)
  local fs = new("FontString", self, layer)
  local f = assert(FONTS[template or "GameFontHighlightSmall"], "no template " .. tostring(template))
  fs._font = { f[1], f[2], f[3] }
  fs._shadow = { 1, -1 }
  fs._tc = { 1, 0.82, 0, 1 }
  self._regions[#self._regions + 1] = fs
  return fs
end
function Object:SetFontObject(name) local f = FONTS[name]; self._font = { f[1], f[2], f[3] }; self._shadow = { 1, -1 } end
function Object:SetFont(path, size, flags)
  if path == "BAD" then return false end
  self._font = { path, size, flags }
  return true
end
function Object:GetFont() if self._font then return self._font[1], self._font[2], self._font[3] end end
function Object:SetShadowOffset(x, y) self._shadow = { x, y } end
function Object:GetShadowOffset() return self._shadow[1], self._shadow[2] end
function Object:SetText(t) self._text = t end
function Object:GetText() return self._text or "" end
function Object:SetFormattedText(f, ...) self._text = f:format(...) end
function Object:SetTextColor(r, g, b, a) self._tc = { r, g, b, a or 1 } end
function Object:GetTextColor() return self._tc[1], self._tc[2], self._tc[3], self._tc[4] end
function Object:GetStringHeight() return 12 end
function Object:GetStringWidth() return 50 end
-- any other method: a no-op (fields stay nil)
setmetatable(Object, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
-- sliders
function Object:SetThumbTexture(t) self._thumb = t end
function Object:GetThumbTexture() return self._thumb end

function CreateFrame(kind, name, parent)
  local f = new(kind, parent)
  f._name = name
  if parent then parent._children[#parent._children + 1] = f end
  if kind == "EditBox" then f._font = { "Fonts\\FRIZQT__.TTF", 10, "" }; f._shadow = { 0, 0 } end
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")
function UIParent:GetEffectiveScale() return 1 end
function hooksecurefunc(tbl, name, fn)
  if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
PixelUtil = { SetHeight = function(t, v) t._h = v; t._pixel = true end, SetWidth = function(t, v) t._w = v; t._pixel = true end }
C_Timer = { After = function() end }
function InCombatLockdown() return false end
function GetTime() return 1000 end
SlashCmdList = {}
LibStub = nil

-- the core: its real widgets, the rest stood in for
ns = { version = "test" }
function ns.Refresh() end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.IsSecret() return false end
function ns.Print() end
function ns.ConfigScale() return 1 end
MMT = ns
'''

MODULE = r'''
local function copy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = copy(v) end return r end
MMT.CopyTable = copy
MMT.ConfigHelpers = { COL_W = 248, COL2_X = 270, PAGE_W = 518 }
function MMT.ConfigHelpers.StatusLine(page) local fs = MMT.UI.Label(page, ""); fs.Show_ = function() end; return fs end
function MMT.ConfigHelpers.ConfirmButton(page, w, text, fn) local b = MMT.UI.Button(page, w, text, fn); CONFIRMS[#CONFIRMS + 1] = fn; return b end
CONFIRMS = {}
function MMT.RefreshConfig() end
function MMT.ToggleConfig() end
-- the background picker of the pull request "settings-background" (absent in MMT's main branch: then no hook)
BGKEY = "NONE"
function MMT.ConfigBackground() return BGKEY end
function MMT.ApplyBackground(frame) if frame.baseFill then frame.baseFill:SetColorTexture(0.05, 0.05, 0.06, BGKEY == "NONE" and 0.94 or 0.4) end end
function MMT.NewModule(def)
  local M = def
  M.enabled = false
  M.db = copy(def.defaults)
  M.store = {}
  function M:On() end
  function M:Listen() end
  function M:Debug(...) DEBUGS[#DEBUGS + 1] = string.format(...) end
  return M
end
DEBUGS = {}
'''

TESTS = r'''
local UI = MMT.UI
local mod = QS
local M = mod.M
local function near(a, b) return math.abs((a or -1) - b) < 0.001 end
local function col(t) return t._color end
local function eq(c, r, g, b, a) return c and near(c[1], r) and near(c[2], g) and near(c[3], b) and near(c[4], a) end
local function fail(msg) error(msg, 2) end
local A = UI.ACCENT

-- built with MMT's look, before the module is on (as at login)
local win = CreateFrame("Frame", "MMTTestWindow", UIParent)
win:SetSize(400, 300)
local winFill = UI.Fill(win, 0.05, 0.05, 0.06, 0.94)
UI.Border(win, 0.22, 0.22, 0.24, 1)
local winEdges = { select(2, win:GetRegions()) }
local title = UI.Label(win, "Title", "GameFontNormalLarge")
local btn = UI.Button(win, 120, "Press", function() end)
btn._h = 20
local btnFill = select(1, btn:GetRegions())
local check = UI.Check(win, 200, "Check me", function() return true end, function() end)
local box = select(1, check:GetChildren())
local boxMark
for _, r in ipairs({ box:GetRegions() }) do if r._layer == "ARTWORK" then boxMark = r end end
local slider = UI.Slider(win, 200, "Size", 1, 10, 1, function() return 5 end, function() end)
local s = select(1, slider:GetChildren())
local track
for _, r in ipairs({ s:GetRegions() }) do if r._layer == "BACKGROUND" then track = r end end
local thumb = s:GetThumbTexture()
local dd = UI.Dropdown(win, 200, "Pick", { { value = 1, text = "One" } }, function() return 1 end, function() end)
local cyc = UI.Cycle(win, 200, "Old name", { { value = 1, text = "One" } }, function() return 1 end, function() end)
local edit = UI.EditBox(win, 200, "type here")
local area = UI.TextArea(win, 200, 100)
local warn = CreateFrame("Frame", nil, win)
local warnFill = UI.Fill(warn, 1, 0.85, 0.2, 0.08)   -- a coloured notice: never touched
local tint = UI.Fill(CreateFrame("Frame", nil, win), 1, 1, 1, 0.025)
local sync = UI.SyncButton(win, "Sync to team", function() end)
local syncFill = select(1, sync:GetRegions())

assert(eq(col(winFill), 0.05, 0.05, 0.06, 0.94), "style None changed a fill")
assert(eq(col(winEdges[1]), 0.22, 0.22, 0.24, 1), "style None changed an edge")
assert(title._font[1] == "Fonts\\FRIZQT__.TTF" and title._font[2] == 16, "style None changed a font")
local c = mod.Counts()
assert(c.fills >= 8 and c.borders >= 6 and c.fonts >= 8 and c.accents >= 2 and c.tracks == 1 and c.texts == 2,
  ("not everything recorded: fills %d edges %d fonts %d accents %d tracks %d texts %d"):format(c.fills, c.borders, c.fonts, c.accents, c.tracks, c.texts))

-- the module goes on with ElvUI chosen (stored per account)
M.store.style = "ELVUI"
M.enabled = true
M.OnEnable(M)
assert(QStyles.Current() == "ELVUI", "ElvUI not current")
assert(eq(col(winFill), 0.06, 0.06, 0.06, 0.9), "ElvUI panel: " .. table.concat(col(winFill), ","))
assert(eq(col(btnFill), 0.1, 0.1, 0.1, 1), "ElvUI button fill")
assert(eq(col(winEdges[1]), 0, 0, 0, 1) and winEdges[1]._pixel, "ElvUI edges not black pixel lines")
local inner = mod.records.borders[winEdges[1]].rings.inner
assert(inner and inner[1]._shown and eq(col(inner[1]), 1, 1, 1, 0.07), "ElvUI inner line missing")
assert(title._font[1] == "Fonts\\ARIALN.TTF" and title._font[2] == 18 and title._font[3] == "OUTLINE", "ElvUI font: " .. tostring(title._font[1]) .. " " .. tostring(title._font[2]))
assert(title._shadow[1] == 0, "ElvUI keeps the shadow")
assert(edit._font[1] == "Fonts\\ARIALN.TTF" and area.edit._font[1] == "Fonts\\ARIALN.TTF", "edit boxes not styled")
assert(eq(col(boxMark), 0.09, 0.52, 0.82, 1), "check mark not in ElvUI's accent")
assert(eq(col(thumb), 0.09, 0.52, 0.82, 1) and eq(col(track), 0.1, 0.1, 0.1, 1), "slider")
assert(near(dd.valueLabel._tc[1], 0.09) and near(cyc.valueLabel._tc[1], 0.09), "dropdown value colour (both names)")
assert(eq(col(warnFill), 1, 0.85, 0.2, 0.08) and eq(col(tint), 1, 1, 1, 0.025), "a coloured fill / tint was changed")
assert(eq(col(syncFill), 0.09, 0.52, 0.82, 0.22), "sync button fill not in the accent")
sync.Update()   -- the core colours it again
assert(eq(col(syncFill), 0.09, 0.52, 0.82, 0.22), "sync button lost the style after its Update")

-- built after the style was picked: styled at once (popups, confirm dialog)
UI.Confirm("Really?", "Yes", function() end)
local cf = MMTConfirmFrame
assert(eq(col(select(1, cf:GetRegions())), 0.06, 0.06, 0.06, 0.9), "confirm dialog not styled")
local acc = select(2, cf:GetRegions())
assert(eq(col(acc), 0, 0, 0, 1), "accent edge of the dialog not black in ElvUI")
local list = CreateFrame("Button", nil, win); list:SetSize(100, 20)
UI.OpenList(list, { { value = 1, text = "a" }, { value = 2, text = "b" } }, 1, function() end)
local p = MMTDropdownList
assert(eq(col(select(1, p:GetRegions())), 0.06, 0.06, 0.06, 0.9), "dropdown list not styled")
local row = p.rows[1]
assert(eq(col(row.sel), 0.09, 0.52, 0.82, 0.18), "selected list row not in the accent")
assert(row.text._font[1] == "Fonts\\ARIALN.TTF", "list row text font")

-- EllesmereUI: gradient panels, faint edges, soft corners, shadow on windows only
mod.SetStyle("ELLESMERE")
local g = winFill._gradient
assert(g and g[1] == "VERTICAL" and near(g[2].r, 0.069) and near(g[3].r, 0.105) and near(g[2].a, 0.94 * 0.94), "Ellesmere gradient")
assert(eq(col(winFill), 1, 1, 1, 1), "gradient needs a white texture")
assert(eq(col(winEdges[1]), 1, 1, 1, 0.10), "Ellesmere window edge")
local btnEdge = select(2, btn:GetRegions())
assert(eq(col(btnEdge), 1, 1, 1, 0.25), "Ellesmere button edge")
local rec = mod.records.borders[winEdges[1]]
assert(not rec.rings.inner[1]._shown, "ElvUI's inner line still shown")
assert(rec.rings.shadow1 and rec.rings.shadow1[1]._shown and rec.rings.shadow2[1]._shown, "window has no shadow")
local brec = mod.records.borders[btnEdge]
assert(not (brec.rings.shadow1 and brec.rings.shadow1[1]._shown), "a small button got a shadow")
local top = winEdges[1]   -- TOPLEFT / TOPRIGHT
assert(top._points[1][4] == 1 and top._points[2][4] == -1, "corners not soft")
assert(near(col(boxMark)[1], 220 / 255), "EllesmereUI accent (bronze without EllesmereUI)")
assert(title._font[1] == "Fonts\\ARIALN.TTF" and title._font[2] == 18 and title._font[3] == "", "Ellesmere font")
assert(title._shadow[1] == 1, "Ellesmere should keep the shadow")
EllesmereUI = { ELLESMERE_GREEN = { r = 0.05, g = 0.8, b = 0.6 } }
mod.Apply()
assert(near(col(boxMark)[1], 0.05), "EllesmereUI's own accent not used")

-- options: accent and fonts off
mod.SetOpt("accent", false)
assert(eq(col(boxMark), A[1], A[2], A[3], 1), "accent off: mark not MMT's blue")
assert(near(dd.valueLabel._tc[1], A[1]), "accent off: dropdown value")
mod.SetOpt("fonts", false)
assert(title._font[1] == "Fonts\\FRIZQT__.TTF" and title._font[2] == 16, "fonts off: font not back")
mod.SetOpt("accent", true); mod.SetOpt("fonts", true)

-- None: exactly what MMT set
mod.SetStyle("NONE")
assert(QStyles.Current() == "NONE")
assert(eq(col(winFill), 0.05, 0.05, 0.06, 0.94) and winFill._gradient == nil and eq(winFill._vertex, 1, 1, 1, 1), "None: window fill")
assert(eq(col(btnFill), 0.12, 0.12, 0.12, 1), "None: button fill")
for i, e in ipairs(winEdges) do assert(eq(col(e), 0.22, 0.22, 0.24, 1), "None: edge " .. i) end
assert(top._points[1][4] == 0 and top._points[2][4] == 0 and top._h == 1, "None: edge anchors / thickness")
for _, ring in pairs(rec.rings) do for _, t in ipairs(ring) do assert(not t._shown, "None: extra lines shown") end end
assert(title._font[1] == "Fonts\\FRIZQT__.TTF" and title._font[2] == 16 and title._font[3] == "" and title._shadow[1] == 1, "None: font")
assert(edit._font[2] == 10, "None: edit box font")
assert(eq(col(boxMark), A[1], A[2], A[3], 1) and eq(col(track), 0.18, 0.18, 0.18, 1) and eq(col(thumb), A[1], A[2], A[3], 1), "None: check / slider")
assert(near(dd.valueLabel._tc[1], A[1]), "None: dropdown value")
assert(eq(col(row.sel), A[1], A[2], A[3], 0.18), "None: list row")

-- the settings window: the selected page's bar in the nav list; the background picker owns the base fill while it shows a picture
local w = CreateFrame("Frame", "MMTConfigFrame", UIParent); w:SetSize(880, 620)
w.baseFill = UI.Fill(w, 0.05, 0.05, 0.06, 0.94)
MMT.ApplyBackground(w)
w.tabs = {}
local tab = CreateFrame("Button", nil, w); tab:SetSize(150, 26)
UI.Fill(tab, 1, 1, 1, 0)
local bar = tab:CreateTexture(nil, "ARTWORK"); bar:SetColorTexture(A[1], A[2], A[3], 1); bar:SetWidth(2)
w.tabs[1] = tab
MMT.ToggleConfig()
mod.SetStyle("ELVUI")
assert(eq(col(bar), 0.09, 0.52, 0.82, 1), "nav bar not in the accent")
assert(eq(col(w.baseFill), 0.06, 0.06, 0.06, 0.9), "base fill not styled with no background")
MMT.ApplyBackground(w)   -- opening the window again
assert(eq(col(w.baseFill), 0.06, 0.06, 0.06, 0.9), "the background picker's colour stayed over the style")
BGKEY = "WOODS"
MMT.ApplyBackground(w)
assert(eq(col(w.baseFill), 0.05, 0.05, 0.06, 0.4), "the style painted over the background picture's fill")
mod.SetStyle("NONE")
assert(eq(col(w.baseFill), 0.05, 0.05, 0.06, 0.4), "None put MMT's fill over the background picture")
assert(eq(col(bar), A[1], A[2], A[3], 1), "None: nav bar")
BGKEY = "NONE"

-- the API (Team Inventory's own-skinned bags window): the colours it passes are the originals
local bags = CreateFrame("Frame", "MMTTeamBagsWindow", UIParent); bags:SetSize(500, 400)
local bg = bags:CreateTexture(nil, "BACKGROUND")
local edges = {}
for i = 1, 4 do edges[i] = bags:CreateTexture(nil, "BORDER") end
edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
QStyles.Paint(bg, 0.05, 0.05, 0.06, 0.94)
QStyles.PaintEdges(bags, edges, 0.22, 0.22, 0.24, 1)
assert(eq(col(bg), 0.05, 0.05, 0.06, 0.94) and eq(col(edges[2]), 0.22, 0.22, 0.24, 1), "API with None")
mod.SetStyle("ELVUI")
assert(eq(col(bg), 0.06, 0.06, 0.06, 0.9) and eq(col(edges[2]), 0, 0, 0, 1), "API with ElvUI")
QStyles.Paint(bg, 0.3, 0.1, 0.1, 1)   -- the player picks a red background in its Look tab: kept
assert(eq(col(bg), 0.3, 0.1, 0.1, 1), "a coloured background from its own settings was styled")
QStyles.Paint(bg, 0.05, 0.05, 0.06, 0.94)
mod.SetStyle("NONE")
assert(eq(col(bg), 0.05, 0.05, 0.06, 0.94), "API back to None")

-- switched off in /mmt: MMT's look; on again: the style
mod.SetStyle("ELLESMERE")
M.enabled = false; M.OnDisable(M)
assert(eq(col(btnFill), 0.12, 0.12, 0.12, 1) and title._font[2] == 16, "module off: not MMT's look")
M.enabled = true; M.OnEnable(M)
assert(eq(col(btnFill), 0.103, 0.095, 0.088, 0.9), "module on again: style not back")

-- straight from ElvUI (no shadow) to None
mod.SetStyle("ELVUI")
assert(title._shadow[1] == 0)
mod.SetStyle("NONE")
assert(title._shadow[1] == 1 and title._shadow[2] == -1, "None after ElvUI: text shadow not back")
mod.SetStyle("ELLESMERE")

-- a font the client can't load: MMT's font stays
local bad = mod.STYLES.ELLESMERE.font
mod.STYLES.ELLESMERE.font = function() return "BAD" end
local late = UI.Label(win, "late")
assert(late._font[1] == "Fonts\\FRIZQT__.TTF" and late._font[2] == 10, "a failed SetFont left a broken font")
mod.STYLES.ELLESMERE.font = bad

-- a problem in a hook never breaks the core's call
local odd = CreateFrame("Frame", nil, win)
function odd:GetRegions() error("boom") end
local t = UI.Fill(odd, 0.05, 0.05, 0.05, 1)
assert(t and eq(col(t), 0.05, 0.05, 0.05, 1), "UI.Fill broke because of the hook")
assert(#DEBUGS > 0, "hook error not reported in debug")

-- the settings page (real Column / widgets), then reset to defaults: back to None, options on
local page = CreateFrame("Frame", nil, UIParent); page:SetSize(518, 564); page.widgets = {}
M.Page(M, page)
for _, wd in ipairs(page.widgets) do wd.Refresh() end
page.OnRefresh()
assert(#CONFIRMS == 1, "no reset button")
mod.SetOpt("fonts", false)
CONFIRMS[1]()
assert(M.store.style == nil and mod.Opt("style") == "NONE" and mod.Opt("fonts") == true, "reset")
assert(eq(col(btnFill), 0.12, 0.12, 0.12, 1), "reset: look not back to MMT's")
local lines = {}
M.Report(M, function(l) lines[#lines + 1] = l end)
return "ok: " .. table.concat(lines, " | ")
'''

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
widgets = os.path.join("MMT", "Widgets.lua")
if not os.path.exists(widgets):
    print("MMT/Widgets.lua not found (MMT core not installed here): skipped")
    sys.exit(0)
lua.eval('function(src, name) assert(loadstring(src, name))("MMT", ns) end')(open(widgets, encoding="utf-8").read(), "MMT/Widgets.lua")
lua.execute(MODULE)
folder = "MMT_qStyles"
toc = [l.strip() for l in open(os.path.join(folder, folder + ".toc"), encoding="utf-8") if l.strip().endswith(".lua")]
mod = lua.eval("{}")
lua.globals().QS = mod
for f in toc:
    lua.eval('function(src, name, m) assert(loadstring(src, name))("MMT_qStyles", m) end')(
        open(os.path.join(folder, f), encoding="utf-8").read(), folder + "/" + f, mod)
print(lua.execute(TESTS))
