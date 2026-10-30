-- MMT Styles: the skinning.
--
-- How it finds things: MMT's windows (the core's, the friend's modules', ours)
-- are built from MMT.UI. hooksecurefunc on MMT.UI.Fill / Border / Label, on the
-- widget builders (Button, Check, Slider, Dropdown, Color, EditBox, TextArea,
-- TextButton, SyncButton) and on Column:Header runs after each call; the new
-- texture / font string / widget is the newest region or child of the frame it
-- was made on (WoW keeps them in creation order), and the call's arguments are
-- its original colour. Each one is remembered with what it had, so a style can
-- be put on and taken off any time: None puts back exactly what MMT set. Only
-- dark neutral fills, neutral or accent-coloured edges, MMT's accent pieces and
-- plain white / gold text are touched; coloured fills (quality colours,
-- warnings, tints) stay as they are. The widget hooks only add a ROLE (button,
-- check, dropdown, input) to what Fill / Border recorded: Art.lua (Classic's
-- game textures) and Hover.lua use it.
--
-- Hooks are installed when this file loads (MMT is loaded before: dependency),
-- so only frames built before that keep MMT's look. Every hook runs in pcall: a
-- problem here never breaks the core's own call. Anything not found (the core
-- changed) is left alone.
--
-- Modules that colour textures themselves (Team Inventory's bags window: its
-- own Look settings) call the public API instead of SetColorTexture:
--   QStyles.Paint(texture, r, g, b, a)            a fill, painted for the style
--   QStyles.PaintEdges(frame, edges, r, g, b, a)  the 4 edge textures of a frame
--   QStyles.Current()                             "NONE" | "ELVUI" | "ELLESMERE" | "CLASSIC"

local _, mod = ...
local MMT = MMT
local M = mod.M

local weak = { __mode = "k" }
local fills = setmetatable({}, weak)     -- [texture] = { r, g, b, a, frame, role, painted, gradient, art, skip }
local fillOf = setmetatable({}, weak)    -- [frame] = its (first) fill texture
local borders = setmetatable({}, weak)   -- [first edge] = { frame, edges, points, horizontal, thick, r, g, b, a, role, rings, painted }
local borderOf = setmetatable({}, weak)  -- [frame] = its edge record
local fonts = setmetatable({}, weak)     -- [font string / edit box] = { path, size, flags, sx, sy, painted }
local colors = setmetatable({}, weak)    -- [texture] = { kind = accent | mark | thumb | track, r, g, b, a, points, w, h, painted }
local texts = setmetatable({}, weak)     -- [font string] = { kind = accent | plain | button | header, orig, set, painted }
local headers = setmetatable({}, weak)   -- [font string] = { line, text, upper }: Column:Header
local seen = setmetatable({}, weak)      -- regions already recorded (or made by us)
mod.fillOf, mod.borderOf, mod.seen = fillOf, borderOf, seen

-- MMT's slider track (MMT/Widgets.lua: UI.Slider); there is no getter for a colour texture
local TRACK = { 0.18, 0.18, 0.18, 1 }

local function Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and M.Debug then M:Debug("Styles: %s", tostring(err)) end
    return ok
end
mod.Try = Try

local function Num(v) return tonumber(v) or 0 end

local function Neutral(r, g, b)
    return math.abs(r - g) < 0.03 and math.abs(g - b) < 0.03 and math.abs(r - b) < 0.03
end

local function Near(c, r, g, b)
    return c and math.abs(Num(c[1]) - r) < 0.02 and math.abs(Num(c[2]) - g) < 0.02 and math.abs(Num(c[3]) - b) < 0.02
end

local function IsAccent(r, g, b)
    local A = MMT.UI and MMT.UI.ACCENT
    if type(A) ~= "table" then return false end
    return Near({ r, g, b }, Num(A[1]), Num(A[2]), Num(A[3]))
end
mod.IsAccent = IsAccent

local function AccentOn() return mod.Opt("accent") and true or false end
mod.AccentOn = AccentOn

local function Regions(frame)
    if not (frame and frame.GetRegions) then return {} end
    return { frame:GetRegions() }
end
mod.Regions = Regions

local function Children(frame)
    if not (frame and frame.GetChildren) then return {} end
    local out = {}
    for _, c in ipairs({ frame:GetChildren() }) do
        if not seen[c] then out[#out + 1] = c end   -- our own (Classic's border frames) are no widgets
    end
    return out
end

local function Type(o) return o and o.GetObjectType and o:GetObjectType() end

local function Layer(t)
    if not t.GetDrawLayer then return nil end
    return (t:GetDrawLayer())
end

-- the newest `count` regions of frame of a kind, not recorded yet, oldest first
local function Newest(frame, kind, count, layer, any)
    local list, out = Regions(frame), {}
    for i = #list, 1, -1 do
        local r = list[i]
        if (any or not seen[r]) and Type(r) == kind and (not layer or Layer(r) == layer) then
            table.insert(out, 1, r)
            if #out == count then return out end
        end
    end
    return out
end

local function NewestChild(parent)
    local list = Children(parent)
    return list[#list]
end

function mod.Size(frame)
    if not frame then return 0, 0 end
    return Num(frame.GetWidth and frame:GetWidth()), Num(frame.GetHeight and frame:GetHeight())
end

function mod.SavePoints(t)
    local p = {}
    for i = 1, Num(t.GetNumPoints and t:GetNumPoints()) do
        local a, rel, b, x, y = t:GetPoint(i)
        p[#p + 1] = { a, rel, b, Num(x), Num(y) }
    end
    return p
end

function mod.RestorePoints(t, points)
    if not points then return end
    t:ClearAllPoints()
    for _, p in ipairs(points) do t:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

-- a texture we made (or changed into art) goes back to a plain colour texture
local function Plain(t)
    if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
    if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 1) end
    if t.SetBlendMode then t:SetBlendMode("BLEND") end
end
mod.Plain = Plain

---------------------------------------------------------------------------
-- Fills
---------------------------------------------------------------------------
local function FillClass(rec)
    if IsAccent(rec.r, rec.g, rec.b) then return AccentOn() and "accent" or nil end
    if not Neutral(rec.r, rec.g, rec.b) then return nil end
    local v = math.max(rec.r, rec.g, rec.b)
    if v < 0.085 then return "panel" end
    if v < 0.2 then return "control" end
    return nil
end

local function NoGradient(t, rec)
    if rec.gradient then
        t:SetVertexColor(1, 1, 1, 1)
        rec.gradient = nil
    end
end

local function UndoFill(t, rec)
    NoGradient(t, rec)
    if rec.art then
        Plain(t)
        mod.RestorePoints(t, rec.points)
        if mod.ArtUndoFill then mod.ArtUndoFill(t, rec) end
        rec.art = nil
    end
end

local function PaintFill(t, rec, S)
    if rec.skip and rec.skip() then return end
    UndoFill(t, rec)
    if S and S.art and mod.ArtFill and mod.ArtFill(t, rec, S) then
        rec.painted = true
        return
    end
    local cls = S and FillClass(rec)
    if not cls then
        if rec.painted then
            t:SetColorTexture(rec.r, rec.g, rec.b, rec.a)
            rec.painted = nil
        end
        return
    end
    local r, g, b, a
    if cls == "accent" then
        r, g, b = S.accent()
        a = rec.a
    elseif cls == "panel" then
        r, g, b, a = S.panel[1], S.panel[2], S.panel[3], S.panelAlpha(rec.a)
    else
        r, g, b, a = S.control[1], S.control[2], S.control[3], S.controlAlpha(rec.a)
    end
    local top = cls == "panel" and S.panelTop
    local done = false
    if top and t.SetGradient and CreateColor then
        t:SetColorTexture(1, 1, 1, 1)
        local ok = pcall(t.SetGradient, t, "VERTICAL", CreateColor(r, g, b, a), CreateColor(top[1], top[2], top[3], a))
        if ok then rec.gradient, done = true, true end
    end
    if not done then t:SetColorTexture(r, g, b, a) end
    rec.painted = true
end
mod.FillClass = FillClass

local function AddFill(t, frame, r, g, b, a, skip)
    seen[t] = true
    local rec = fills[t] or {}
    rec.r, rec.g, rec.b, rec.a, rec.frame, rec.skip = Num(r), Num(g), Num(b), tonumber(a) or 1, frame, skip
    rec.points = rec.points or mod.SavePoints(t)
    fills[t] = rec
    if frame and not fillOf[frame] then fillOf[frame] = t end
    PaintFill(t, rec, mod.Current())
    return rec
end

---------------------------------------------------------------------------
-- Edges (UI.Border's four 1 px textures)
---------------------------------------------------------------------------
local function Horizontal(points)
    if #points < 2 then return nil end
    local top, bottom = true, true
    for _, p in ipairs(points) do
        local name = tostring(p[1])
        if not name:find("TOP") then top = false end
        if not name:find("BOTTOM") then bottom = false end
    end
    return top or bottom
end

-- four lines `inset` px inside the frame's edge (negative = outside); cut = leave the corners empty
local function Ring(frame, inset, layer, sub, cut)
    local lines = {}
    local c = cut and 1 or 0
    local function line(p1, x1, y1, p2, x2, y2, w, h)
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetPoint(p1, frame, p1, x1, y1)
        t:SetPoint(p2, frame, p2, x2, y2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:Hide()
        seen[t] = true
        lines[#lines + 1] = t
    end
    local i = inset
    line("TOPLEFT", i + c, -i, "TOPRIGHT", -i - c, -i, nil, 1)
    line("BOTTOMLEFT", i + c, i, "BOTTOMRIGHT", -i - c, i, nil, 1)
    line("TOPLEFT", i, -i - 1, "BOTTOMLEFT", i, i + 1, 1, nil)
    line("TOPRIGHT", -i, -i - 1, "BOTTOMRIGHT", -i, i + 1, 1, nil)
    return lines
end

local function ShowRing(lines, c)
    for _, t in ipairs(lines or {}) do
        if c then
            t:SetColorTexture(c[1], c[2], c[3], c[4])
            t:Show()
        else
            t:Hide()
        end
    end
end

local function BorderClass(rec)
    if IsAccent(rec.r, rec.g, rec.b) then return "accent" end
    if Neutral(rec.r, rec.g, rec.b) and math.max(rec.r, rec.g, rec.b) < 0.6 then return "neutral" end
    return nil
end

local function Thickness(t, horizontal, px, pixel)
    if horizontal == nil then return end
    if pixel and PixelUtil then
        local ok = pcall(horizontal and PixelUtil.SetHeight or PixelUtil.SetWidth, t, px)
        if ok then return end
    end
    if horizontal then t:SetHeight(px) else t:SetWidth(px) end
end

local function PlaceEdge(t, points, horizontal, round)
    t:ClearAllPoints()
    for _, p in ipairs(points) do
        local x, y = p[4], p[5]
        if round and horizontal ~= nil then
            local name = tostring(p[1])
            if horizontal then
                x = x + (name:find("LEFT") and 1 or (name:find("RIGHT") and -1 or 0))
            else
                y = y + (name:find("TOP") and -1 or (name:find("BOTTOM") and 1 or 0))
            end
        end
        t:SetPoint(p[1], p[2], p[3], x, y)
    end
end

-- small = a widget-sized frame (controls: their own edge colour, no shadow)
function mod.Small(rec)
    if rec.role then return true end
    local _, h = mod.Size(rec.frame)
    return (h > 0 and h <= 32) or (h <= 0 and math.max(rec.r, rec.g, rec.b) >= 0.28)
end

-- the colour of a frame's edges in style S (nil = leave MMT's)
function mod.EdgeColor(rec, S)
    local cls = BorderClass(rec)
    if not cls then return nil end
    if cls == "neutral" then return mod.Small(rec) and S.controlBorder or S.border end
    if S.accentBorder == "BLACK" then return { 0, 0, 0, rec.a > 0 and 1 or 0 } end
    if AccentOn() then
        local r, g, b = S.accent()
        return { r, g, b, rec.a }
    end
    return { rec.r, rec.g, rec.b, rec.a }
end

local function UndoBorder(rec)
    if mod.ArtUndoBorder then mod.ArtUndoBorder(rec) end
    for i, t in ipairs(rec.edges) do
        t:SetColorTexture(rec.r, rec.g, rec.b, rec.a)
        Thickness(t, rec.horizontal[i], rec.thick[i], false)
        PlaceEdge(t, rec.points[i], rec.horizontal[i], false)
    end
    for _, ring in pairs(rec.rings or {}) do ShowRing(ring, nil) end
end

local function PaintBorder(rec, S)
    if rec.painted then UndoBorder(rec) end
    rec.painted = nil
    if not S then return end
    if S.art and mod.ArtBorder and mod.ArtBorder(rec, S) then
        rec.painted = true
        return
    end
    local c = mod.EdgeColor(rec, S)
    if not c then return end
    for i, t in ipairs(rec.edges) do
        t:SetColorTexture(c[1], c[2], c[3], c[4])
        Thickness(t, rec.horizontal[i], 1, S.pixel)
        PlaceEdge(t, rec.points[i], rec.horizontal[i], S.round)
    end
    rec.rings = rec.rings or {}
    local f = rec.frame
    if S.inner and not rec.rings.inner then rec.rings.inner = Ring(f, 1, "BORDER", 1) end
    ShowRing(rec.rings.inner, S.inner)
    local shadow = (not mod.Small(rec)) and S.shadow
    for k = 1, 2 do
        local key = "shadow" .. k
        if shadow and shadow[k] and not rec.rings[key] then rec.rings[key] = Ring(f, -k, "BACKGROUND", -8, true) end
        ShowRing(rec.rings[key], shadow and shadow[k])
    end
    rec.painted = true
end

-- only the edge colour (hover): the rest of the paint stays
function mod.SetEdgeColor(rec, c)
    for _, t in ipairs(rec.edges) do t:SetColorTexture(c[1], c[2], c[3], c[4]) end
end

local function AddBorder(frame, edges, r, g, b, a)
    for _, t in ipairs(edges) do seen[t] = true end
    local rec = borders[edges[1]]
    if not rec then
        rec = { frame = frame, edges = edges, points = {}, horizontal = {}, thick = {} }
        for i, t in ipairs(edges) do
            rec.points[i] = mod.SavePoints(t)
            rec.horizontal[i] = Horizontal(rec.points[i])
            local px = rec.horizontal[i] and t:GetHeight() or t:GetWidth()
            rec.thick[i] = (tonumber(px) and px > 0 and px <= 4) and px or 1
        end
        borders[edges[1]] = rec
        if frame and not borderOf[frame] then borderOf[frame] = rec end
    end
    rec.r, rec.g, rec.b, rec.a = Num(r), Num(g), Num(b), tonumber(a) or 1
    PaintBorder(rec, mod.Current())
    -- the fill came first (UI.Fill, then UI.Border): it was painted before the frame had edges, i.e. before
    -- Classic knew it is a window (the Team Gear window kept a black fill over its stone)
    local t = frame and fillOf[frame]
    if t then PaintFill(t, fills[t], mod.Current()) end
    return rec
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local function PaintFont(fs, rec, S)
    local file = S and S.font and mod.Opt("fonts") and S.font()
    if not file then
        if rec.painted then
            pcall(fs.SetFont, fs, rec.path, rec.size, rec.flags)
            if rec.sx and fs.SetShadowOffset then fs:SetShadowOffset(rec.sx, rec.sy) end
            rec.painted = nil
        end
        return
    end
    local ok, res = pcall(fs.SetFont, fs, file, rec.size + (S.fontDelta or 0), S.fontFlags or rec.flags or "")
    if not ok or res == false then
        pcall(fs.SetFont, fs, rec.path, rec.size, rec.flags)
        return
    end
    if fs.SetShadowOffset and rec.sx then
        if S.noShadow then fs:SetShadowOffset(0, 0) else fs:SetShadowOffset(rec.sx, rec.sy) end
    end
    rec.painted = true
end

local function AddFont(fs)
    if not (fs and fs.GetFont) or fonts[fs] then return end
    seen[fs] = true
    local path, size, flags = fs:GetFont()
    if not path or not tonumber(size) then return end
    local rec = { path = path, size = tonumber(size), flags = flags or "" }
    if fs.GetShadowOffset then rec.sx, rec.sy = fs:GetShadowOffset() end
    fonts[fs] = rec
    PaintFont(fs, rec, mod.Current())
end

---------------------------------------------------------------------------
-- Accent pieces, slider tracks (colour textures)
---------------------------------------------------------------------------
local function PaintColor(t, rec, S)
    if rec.art then
        Plain(t)
        mod.RestorePoints(t, rec.points)
        if rec.w and t.SetSize then t:SetSize(rec.w, rec.h) end
        if mod.ArtUndoColor then mod.ArtUndoColor(t, rec) end
        rec.art = nil
        rec.painted = true   -- the colour below puts it back
    end
    if rec.kind == "line" then   -- under a Column:Header: the style's header line colour, else MMT's
        local c = S and S.headerLine
        if c == "ACCENT" then
            if AccentOn() then local r, g, b = S.accent(); c = { r, g, b, 0.5 } else c = nil end
        end
        if c then
            t:SetColorTexture(c[1], c[2], c[3], c[4])
            rec.painted = true
        elseif rec.painted then
            t:SetColorTexture(rec.r, rec.g, rec.b, rec.a)
            rec.painted = nil
        end
        return
    end
    if S and S.art and mod.ArtColor and mod.ArtColor(t, rec, S) then
        rec.art, rec.painted = true, true
        return
    end
    local c
    if S then
        if rec.kind == "track" then c = S.track
        elseif AccentOn() then
            local r, g, b = S.accent()
            c = { r, g, b, rec.a }
        end
    end
    if not c then
        if rec.painted then t:SetColorTexture(rec.r, rec.g, rec.b, rec.a); rec.painted = nil end
        return
    end
    t:SetColorTexture(c[1], c[2], c[3], c[4])
    rec.painted = true
end

local function AddColor(kind, t, r, g, b, a)
    if not t or colors[t] then return colors[t] end
    seen[t] = true
    local rec = { kind = kind, r = Num(r), g = Num(g), b = Num(b), a = tonumber(a) or 1, points = mod.SavePoints(t) }
    if t.GetWidth then rec.w, rec.h = t:GetWidth(), t:GetHeight() end
    colors[t] = rec
    PaintColor(t, rec, mod.Current())
    return rec
end

local function AddAccentTexture(t, kind, a)
    local A = MMT.UI.ACCENT
    return AddColor(kind or "accent", t, A[1], A[2], A[3], a or 1)
end

---------------------------------------------------------------------------
-- Text colours. The owner may colour a label again any time (greyed-out
-- options, selected tabs): what we set is remembered, and a label whose colour
-- is no longer ours belongs to its owner again.
---------------------------------------------------------------------------
local GOLD = { 1, 0.82, 0 }

local function TextWant(rec, S)
    local o = rec.orig
    if rec.kind == "accent" then
        if not (IsAccent(Num(o[1]), Num(o[2]), Num(o[3])) and AccentOn()) then return nil end
        local r, g, b = S.accent()
        return { r, g, b, o[4] }
    end
    local white = Near(o, 1, 1, 1)
    if rec.kind == "plain" then
        if IsAccent(Num(o[1]), Num(o[2]), Num(o[3])) and AccentOn() then   -- e.g. the nav list's CORE / MODULES
            local r, g, b = S.accent()
            return { r, g, b, o[4] }
        end
        return white and S.plainText or nil
    end
    if rec.kind == "button" then
        if white then return S.buttonText end
        if IsAccent(Num(o[1]), Num(o[2]), Num(o[3])) and AccentOn() and S.buttonText then   -- a selected tab
            local r, g, b = S.accent()
            return { r, g, b, o[4] }
        end
        return nil
    end
    if rec.kind == "header" then
        if not (Near(o, GOLD[1], GOLD[2], GOLD[3]) or white) then return nil end
        if S.headerText == "ACCENT" then
            if not AccentOn() then return nil end
            local r, g, b = S.accent()
            return { r, g, b, 1 }
        end
        return S.headerText
    end
end

local painting = false   -- our own SetTextColor (the per-label hook ignores it)

-- a colour our own label hooks don't take for the owner's (the hover light)
function mod.QuietTextColor(fs, r, g, b, a)
    painting = true
    pcall(fs.SetTextColor, fs, r, g, b, a)
    painting = false
end

local function PaintText(fs, rec, S)
    local cur = { fs:GetTextColor() }
    if rec.painted and not (Near(cur, rec.set[1], rec.set[2], rec.set[3]) and math.abs(Num(cur[4]) - Num(rec.set[4])) < 0.02) then
        rec.painted = nil   -- coloured again by its owner
    end
    if not rec.painted then rec.orig = cur end
    local want = S and TextWant(rec, S)
    painting = true
    if want then
        fs:SetTextColor(want[1], want[2], want[3], want[4] or 1)
        rec.set = { want[1], want[2], want[3], want[4] or 1 }
        rec.painted = true
    elseif rec.painted then
        local o = rec.orig
        fs:SetTextColor(o[1], o[2], o[3], o[4])
        rec.painted = nil
    end
    painting = false
end

local function AddText(fs, kind)
    if not (fs and fs.GetTextColor) then return end
    local rec = texts[fs]
    if rec then
        rec.kind = kind
    else
        rec = { kind = kind }
        texts[fs] = rec
    end
    -- labels are coloured again by their owner (a selected tab or row, greyed out): the style follows at once
    if not rec.hooked then
        rec.hooked = true
        hooksecurefunc(fs, "SetTextColor", function()
            if painting then return end
            Try(PaintText, fs, rec, mod.Current())
        end)
    end
    PaintText(fs, rec, mod.Current())
end
mod.AddText = AddText

-- Column:Header: EllesmereUI writes them in capitals, Elv in the accent colour; the line under it follows
local function PaintHeader(fs, rec, S)
    local cur = fs:GetText()
    if rec.upper and cur ~= rec.upper then rec.upper = nil end
    if not rec.upper then rec.text = cur end
    if S and S.headerUpper and type(rec.text) == "string" then
        rec.upper = rec.text:upper()
        fs:SetText(rec.upper)
    elseif rec.upper then
        fs:SetText(rec.text)
        rec.upper = nil
    end
end

---------------------------------------------------------------------------
-- The settings window: the bar of the selected page in the nav list
---------------------------------------------------------------------------
function mod.ScanConfig()
    local w = _G.MMTConfigFrame
    if not (w and type(rawget(w, "tabs")) == "table") then return end
    for _, tab in ipairs(w.tabs) do
        for _, t in ipairs(Regions(tab)) do
            if not seen[t] and Type(t) == "Texture" and Layer(t) == "ARTWORK" and t.GetWidth and Num(t:GetWidth()) > 0 and Num(t:GetWidth()) <= 3 then
                AddAccentTexture(t)
            end
        end
    end
    -- the nav list's scroll position marker (2 px, accent at 0.6)
    local nav = w.tabs[1] and w.tabs[1].GetParent and w.tabs[1]:GetParent()
    for _, t in ipairs(nav and Regions(nav) or {}) do
        if not seen[t] and Type(t) == "Texture" and Layer(t) == "OVERLAY" and t.GetWidth and Num(t:GetWidth()) > 0 and Num(t:GetWidth()) <= 3 then
            AddAccentTexture(t, nil, 0.6)
        end
    end
end

-- the settings window's base fill belongs to the core's background picker
-- (pull request "settings-background") while a picture is chosen there
function mod.BackgroundShown()
    local fn = MMT.ConfigBackground
    if type(fn) ~= "function" then return false end
    local ok, key = pcall(fn)
    return ok and key ~= nil and key ~= "NONE"
end

---------------------------------------------------------------------------
-- Roles: the widget hooks say what a recorded frame is
---------------------------------------------------------------------------
mod.roles = setmetatable({}, weak)   -- [frame] = role
mod.widgets = setmetatable({}, weak) -- [frame] = { role, label, arrow, close, hover = edge frame }

local function Repaint(frame)
    local S = mod.Current()
    local rec = borderOf[frame]
    if rec then Try(PaintBorder, rec, S) end
    local t = fillOf[frame]
    if t then Try(PaintFill, t, fills[t], S) end
end

mod.Repaint = Repaint

local function SetRole(frame, role)
    if not frame then return end
    mod.roles[frame] = role
    local rec = borderOf[frame]
    if rec then rec.role = role end
    local t = fillOf[frame]
    if t then fills[t].role = role end
    Repaint(frame)
end

-- a widget: frame = the button the mouse is on, edge = the frame with the edges
local function Widget(frame, role, edge, label, extra)
    local w = mod.widgets[frame] or {}
    w.role, w.edge, w.label = role, edge or frame, label
    for k, v in pairs(extra or {}) do w[k] = v end
    mod.widgets[frame] = w
    if mod.WidgetAdded then Try(mod.WidgetAdded, frame, w) end
    return w
end

---------------------------------------------------------------------------
-- The hooks
---------------------------------------------------------------------------
local function Hook(tbl, name, fn)
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
    hooksecurefunc(tbl, name, function(...) Try(fn, ...) end)
    return true
end

mod.hooked = {}

local function Install()
    local UI = MMT.UI
    if type(UI) ~= "table" then return end
    local function H(name, fn) mod.hooked[name] = Hook(UI, name, fn) end

    H("Fill", function(frame, r, g, b, a, layer)
        local t = Newest(frame, "Texture", 1, layer or "BACKGROUND")[1]
        if not t then return end
        local skip
        if frame.GetName and frame:GetName() == "MMTConfigFrame" then skip = mod.BackgroundShown end
        AddFill(t, frame, r, g, b, a, skip)
    end)
    H("Border", function(frame, r, g, b, a)
        local edges = Newest(frame, "Texture", 4, "BORDER")
        if #edges == 4 then AddBorder(frame, edges, r, g, b, a) end
    end)
    H("Label", function(parent, _, template)
        local fs = Newest(parent, "FontString", 1)[1]
        AddFont(fs)
        if fs and (template == nil or template == "GameFontHighlightSmall") then AddText(fs, "plain") end
    end)
    H("Button", function(parent)
        local b = NewestChild(parent)
        if not (b and rawget(b, "label")) then return end
        SetRole(b, "button")
        AddText(b.label, "button")
        Widget(b, "button", b, b.label)
    end)
    H("Check", function(parent)
        local b = NewestChild(parent)
        local box = b and Children(b)[1]
        if not box then return end
        for _, t in ipairs(Regions(box)) do
            if Type(t) == "Texture" and Layer(t) == "ARTWORK" then AddAccentTexture(t, "mark") end
        end
        SetRole(box, "check")
        Widget(b, "check", box, rawget(b, "label"))
    end)
    H("Slider", function(parent)
        local c = NewestChild(parent)
        for _, s in ipairs(Children(c)) do
            if Type(s) == "Slider" then
                for _, t in ipairs(Regions(s)) do
                    if Type(t) == "Texture" and Layer(t) == "BACKGROUND" then AddColor("track", t, TRACK[1], TRACK[2], TRACK[3], TRACK[4]) end
                end
                local thumb = s.GetThumbTexture and s:GetThumbTexture()
                if thumb then AddAccentTexture(thumb, "thumb") end
            end
        end
    end)
    local function Dropdown(parent)
        local b = NewestChild(parent)
        if not b then return end
        if rawget(b, "valueLabel") then AddText(b.valueLabel, "accent") end
        local arrow
        for _, fs in ipairs(Regions(b)) do
            if Type(fs) == "FontString" and fs:GetText() == "v" then arrow = fs end
        end
        SetRole(b, "dropdown")
        Widget(b, "dropdown", b, nil, { arrow = arrow })
    end
    H("Dropdown", Dropdown)
    if UI.Cycle ~= UI.Dropdown then H("Cycle", Dropdown) end   -- the old name holds the unhooked function
    H("Color", function(parent)
        local b = NewestChild(parent)
        if not b then return end
        SetRole(b, "dropdown")
        Widget(b, "dropdown", b, nil)
    end)
    H("EditBox", function(parent)
        local e = NewestChild(parent)
        if Type(e) ~= "EditBox" then return end
        AddFont(e)
        SetRole(e, "input")
    end)
    H("TextArea", function(parent)
        local holder = NewestChild(parent)
        local e = holder and rawget(holder, "edit")
        if e then AddFont(e) end
        SetRole(holder, "area")
    end)
    H("TextButton", function(parent)
        local b = NewestChild(parent)
        local label = b and rawget(b, "label")
        if label and label:GetText() == "x" then Widget(b, "close", b, nil, { close = label }) end
    end)
    H("SyncButton", function(page)
        local b = NewestChild(page)
        if not (b and type(rawget(b, "Update")) == "function") then return end
        SetRole(b, "button")
        -- its Update colours the fill again: paint it after that. OnShow runs the Update it got when it
        -- was built (SetScript("OnShow", b.Update), not our hooked one): hook the script too
        local function Again()
            Try(function()
                local t = fillOf[b]
                if t then fills[t].painted = true; PaintFill(t, fills[t], mod.Current()) end
            end)
        end
        hooksecurefunc(b, "Update", Again)
        if b.HookScript then b:HookScript("OnShow", Again) end
    end)
    -- Column:Header (the Column metatable is the core's: its methods are looked up at call time)
    local probe = UI.Column and UI.Column(UIParent, 0, 0, 10)
    local Column = probe and getmetatable(probe)
    mod.hooked.Header = Hook(Column, "Header", function(col)
        local parent = col.parent
        local fs = Newest(parent, "FontString", 1, nil, true)[1]
        local line = Newest(parent, "Texture", 1, "ARTWORK")[1]
        if not fs then return end
        headers[fs] = { line = line }
        AddText(fs, "header")
        if line then AddColor("line", line, 1, 1, 1, 0.08) end
        PaintHeader(fs, headers[fs], mod.Current())
    end)
    mod.hooked.ToggleConfig = Hook(MMT, "ToggleConfig", mod.ScanConfig)
    -- the background picker sets the base fill again each time the window opens
    mod.hooked.ApplyBackground = Hook(MMT, "ApplyBackground", function(frame)
        local t = frame and rawget(frame, "baseFill")
        local rec = t and fills[t]
        if not rec then return end
        rec.painted = nil   -- it has just set its own colour
        NoGradient(t, rec)
        PaintFill(t, rec, mod.Current())
        local brec = borderOf[frame]
        if brec then PaintBorder(brec, mod.Current()) end
    end)
end
Install()

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------
function mod.Apply()
    local S = mod.Current()
    if mod.HoverReset then Try(mod.HoverReset) end
    mod.ScanConfig()
    for _, rec in pairs(borders) do Try(PaintBorder, rec, S) end
    for t, rec in pairs(fills) do Try(PaintFill, t, rec, S) end
    for fs, rec in pairs(fonts) do Try(PaintFont, fs, rec, S) end
    for t, rec in pairs(colors) do Try(PaintColor, t, rec, S) end
    for fs, rec in pairs(texts) do Try(PaintText, fs, rec, S) end
    for fs, rec in pairs(headers) do Try(PaintHeader, fs, rec, S) end
    if mod.ArtWidgets then Try(mod.ArtWidgets, S) end
    if mod.HoverStart then Try(mod.HoverStart, S) end
end

-- /mmtstyle frame: what Styles did to the window under the mouse (and the frames it sits in)
function mod.Describe()
    local f = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    local lines, n = {}, 0
    while f and n < 8 do
        n = n + 1
        local name = (f.GetName and f:GetName()) or Type(f) or "?"
        local w, h = mod.Size(f)
        local parts = { ("%s %dx%d"):format(name, w, h) }
        if mod.roles[f] then parts[#parts + 1] = "role=" .. mod.roles[f] end
        if mod.ArtKind and mod.Current() and mod.Current().art then parts[#parts + 1] = "classic=" .. tostring(mod.ArtKind(f)) end
        local t = fillOf[f]
        if t then
            local r = fills[t]
            parts[#parts + 1] = ("fill %.2f/%.2f/%.2f/%.2f class=%s painted=%s"):format(r.r, r.g, r.b, r.a, tostring(FillClass(r)), tostring(r.painted))
        end
        local b = borderOf[f]
        if b then parts[#parts + 1] = ("edges %.2f/%.2f/%.2f/%.2f painted=%s"):format(b.r, b.g, b.b, b.a, tostring(b.painted)) end
        if f.GetBackdrop then parts[#parts + 1] = "backdrop=" .. tostring(f:GetBackdrop() and (f:GetBackdrop().bgFile or "edge only")) end
        lines[#lines + 1] = table.concat(parts, "  ")
        f = f.GetParent and f:GetParent()
        if f == UIParent then break end
    end
    return lines
end

function mod.Counts()
    local function n(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
    return { fills = n(fills), borders = n(borders), fonts = n(fonts), colors = n(colors), texts = n(texts),
        headers = n(headers), widgets = n(mod.widgets) }
end

-- test / debug access
mod.records = { fills = fills, borders = borders, fonts = fonts, colors = colors, texts = texts, headers = headers }
mod.PaintBorder, mod.PaintFill, mod.PaintText = PaintBorder, PaintFill, PaintText

---------------------------------------------------------------------------
-- Public API for modules that colour textures themselves
---------------------------------------------------------------------------
QStyles = QStyles or {}
QStyles.VERSION = 2

-- instead of texture:SetColorTexture(r, g, b, a) for a window's background
function QStyles.Paint(t, r, g, b, a)
    if not t then return end
    local rec = fills[t]
    if rec then UndoFill(t, rec) end
    t:SetColorTexture(r, g, b, a)
    pcall(AddFill, t, t.GetParent and t:GetParent(), r, g, b, a)
end

-- edges = the frame's four edge textures (top, bottom, left, right), colour r, g, b, a
function QStyles.PaintEdges(frame, edges, r, g, b, a)
    if type(edges) ~= "table" or #edges ~= 4 then return end
    for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a) end
    pcall(AddBorder, frame, edges, r, g, b, a)
end

function QStyles.Current()
    local S = mod.Current()
    return S and S.key or "NONE"
end
