import os, sys
from lupa.lua51 import LuaRuntime
os.chdir(sys.argv[1])
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- minimal hooksecurefunc
function hooksecurefunc(a, b, c)
  if type(a) == "string" then
    local orig, fn = _G[a], b
    _G[a] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
  else
    local orig = a[b]
    a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
  end
end

-- fake GameTooltip-like frames
local function NewText() local t = { s = "" } function t:SetText(v) self.s = v end function t:GetText() return self.s end return t end
function CreateFrame(kind, name, parent)
  local f = { name = name, lines = {}, scripts = {}, shown = false }
  function f:GetName() return self.name end
  function f:HookScript(ev, fn) local old = self.scripts[ev]; self.scripts[ev] = function(...) if old then old(...) end fn(...) end end
  function f:Fire(ev) if self.scripts[ev] then self.scripts[ev](self) end end
  function f:SetOwner() end
  function f:SetScale() end
  function f:ClearLines() self.lines = {}; self:Fire("OnTooltipCleared") end
  function f:AddLine(t) self.lines[#self.lines + 1] = t end
  function f:AddDoubleLine(a) self.lines[#self.lines + 1] = a end
  function f:Show() self.shown = true end
  function f:IsShown() return self.shown end
  -- like the modern client: loading an item clears, fills and shows the tooltip (twice)
  function f:SetHyperlink(link) self:ClearLines(); self.item = link; self:AddLine("ITEM " .. link); self:Show(); self:Show() end
  function f:GetItem() return "x", self.item end
  if name then _G[name] = f end
  return f
end

MMT = { IsSecret = function() return false end }
function MMT.SortedMembers() return { "Quiding-Alasha", "Bob-Stone" } end
function MMT.FirstName(k) return (k:match("^[^-]+")) end
function MMT.FullDisplay(k) return (k:gsub("-", " ")) end
C_Item = { GetItemInfoInstant = function() return 1, nil, nil, "INVTYPE_CLOAK" end }
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
GameTooltip.shown = true
GameTooltip.item = "item:15508"
''')

mod = lua.eval(r'''function()
  local m = {}
  m.M = { enabled = true, db = { showInCompare = true, allScales = true, showPercent = true }, Debug = function() end }
  m.ScalesOf = function() return { scales = { { name = "Hunter: Beast Mastery", values = { Agility = 1 } } } } end
  m.ItemStats = function(link) return { Agility = (link == "item:15508") and 4 or 2 }, true end
  m.Value = function(stats, sc) return stats.Agility * 1, false end
  m.EquippedLink = function() return nil end
  return m
end''')()
src = open('MMT_PawnCompare/Tooltip.lua', encoding='utf-8').read()
lua.eval('function(src, m) assert(loadstring(src, "Tooltip.lua"))("x", m) end')(src, mod)

print(lua.execute(r'''
-- Item Compare's Render, as in MMT_ItemCompare/Compare.lua
local tips = {}
local function Tip(i)
  local t = tips[i]
  if t then return t end
  t = CreateFrame("GameTooltip", "MMTCompareTip" .. i, nil, "GameTooltipTemplate")
  t.header = CreateFrame("Frame", nil, t)
  local text = { s = "" } function text:SetText(v) self.s = v end function text:GetText() return self.s end
  t.header.text = text
  tips[i] = t
  return t
end
local function Render(members, equipped)
  for _, t in ipairs(tips) do t.shown = false end
  for i, key in ipairs(members) do
    local t = Tip(i)
    t:SetOwner(nil, "ANCHOR_NONE")
    t:SetScale(1)
    if equipped then
      t:SetHyperlink(equipped)
      t:AddLine(" ")
      t:AddLine("If " .. key .. " equips the hovered item:")
    else
      t:ClearLines()
      t:AddLine("Nothing equipped")
    end
    t.header.text:SetText(MMT.FirstName(key))
    t:Show()
  end
end
local function Count(t, word)
  local n, at = 0, nil
  for i, l in ipairs(t.lines) do if tostring(l):find(word, 1, true) then n = n + 1; at = at or i end end
  return n, at
end
local function Check(label)
  for i, t in ipairs(tips) do
    local n, at = Count(t, "Pawn: hovered item for")
    local _, ic = Count(t, "If ")
    assert(n == 1, label .. ": tip " .. i .. " has " .. n .. " Pawn blocks")
    if ic then assert(at > ic, label .. ": Pawn block above Item Compare's lines") end
    local name = MMT.FirstName(MMT.SortedMembers()[i])
    assert(tostring(t.lines[at]):find(name, 1, true), label .. ": wrong member on tip " .. i .. ": " .. tostring(t.lines[at]))
  end
end
Render(MMT.SortedMembers(), "item:4680"); Check("first press")
Render(MMT.SortedMembers(), "item:4680"); Check("second press")
Render(MMT.SortedMembers(), "item:4680"); Check("third press")
-- order of members changes: names must follow
MMT.SortedMembers = function() return { "Bob-Stone", "Quiding-Alasha" } end
Render(MMT.SortedMembers(), "item:4680"); Check("reordered")
Render(MMT.SortedMembers(), nil); Check("nothing equipped")
return "Pawn lines: exactly once per tooltip, below Item Compare's lines, right member - ok"
'''))
