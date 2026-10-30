-- MMT Styles: the skinning.
--
-- How it finds things: MMT's windows (the core's, the friend's modules', ours)
-- are built from MMT.UI. hooksecurefunc on MMT.UI.Fill / Border / Label and on
-- the widget builders (Check, Slider, Dropdown, EditBox, TextArea, SyncButton)
-- runs after each call; the new texture / font string / widget is the newest
-- region or child of the frame it was made on (WoW keeps them in creation
-- order), and the call's arguments are its original colour. Each one is
-- remembered with what it had, so a style can be put on and taken off any time:
-- None puts back exactly what MMT set. Only dark neutral fills, neutral or
-- accent-coloured edges and MMT's accent pieces are touched; coloured fills
-- (quality colours, warnings, tints) stay as they are.
--
-- Hooks are installed when this file loads (MMT is loaded before: dependency),
-- so only frames built before that keep MMT's look. Every hook runs in pcall: a
-- problem here never breaks the core's own call. Anything not found (the core
-- changed) is left alone.
--
-- Modules that colour textures themselves (Team Inventory's bags window: its
-- own Look settings) call the public API instead of SetColorTexture:
--   QStyles.Paint(texture, r, g, b, a)        a fill, painted for the style
--   QStyles.PaintEdges(frame, edges, r, g, b, a)  the 4 edge textures of a frame
--   QStyles.Current()                         "NONE" | "ELVUI" | "ELLESMERE"

local _, mod = ...
local MMT = MMT
local M = mod.M

local weak = { __mode = "k" }
local fills = setmetatable({}, weak)     -- [texture] = { r, g, b, a, frame, painted, gradient, skip }
local borders = setmetatable({}, weak)   -- [first edge] = { frame, edges, points, thick, r, g, b, a, rings, painted }
local fonts = setmetatable({}, weak)     -- [font string / edit box] = { path, size, flags, sx, sy, painted }
local accents = setmetatable({}, weak)   -- [texture] = { r, g, b, a, painted }: MMT's accent pieces
local tracks = setmetatable({}, weak)    -- [texture] = { r, g, b, a, painted }: slider tracks
local texts = setmetatable({}, weak)     -- [font string] = { r, g, b, a, painted }: accent-coloured text
local seen = setmetatable({}, weak)      -- regions already recorded

-- MMT's slider track (MMT/Widgets.lua: UI.Slider); there is no getter for a colour texture
local TRACK = { 0.18, 0.18, 0.18, 1 }

local function Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and M.Debug then M:Debug("Styles: %s", tostring(err)) end
end

local function Num(v) return tonumber(v) or 0 end

local function Neutral(r, g, b)
    return math.abs(r - g) < 0.03 and math.abs(g - b) < 0.03 and math.abs(r - b) < 0.03
end

local function IsAccent(r, g, b)
    local A = MMT.UI and MMT.UI.ACCENT
    if type(A) ~= "table" then return false end
    return math.abs(r - Num(A[1])) < 0.01 and math.abs(g - Num(A[2])) < 0.01 and math.abs(b - Num(A[3])) < 0.01
end

local function AccentOn() return mod.Opt("accent") and true or false end

local function Regions(frame)
    if not (frame and frame.GetRegions) then return {} end
    return { frame:GetRegions() }
end

local function Children(frame)
    if not (frame and frame.GetChildren) then return {} end
    return { frame:GetChildren() }
end

local function Type(o) return o and o.GetObjectType and o:GetObjectType() end

local function Layer(t)
    if not t.GetDrawLayer then return nil end
    return (t:GetDrawLayer())
end

-- the newest `count` regions of frame of a kind, not recorded yet, oldest first
local function Newest(frame, kind, count, layer)
    local list, out = Regions(frame), {}
    for i = #list, 1, -1 do
        local r = list[i]
        if not seen[r] and Type(r) == kind and (not layer or Layer(r) == layer) then
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

local function Size(frame)
    local h = frame and frame.GetHeight and Num(frame:GetHeight()) or 0
    return h
end

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

local function PaintFill(t, rec, S)
    if rec.skip and rec.skip() then return end
    local cls = S and FillClass(rec)
    if not cls then
        if rec.painted then
            NoGradient(t, rec)
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
    if not done then
        NoGradient(t, rec)
        t:SetColorTexture(r, g, b, a)
    end
    rec.painted = true
end

local function AddFill(t, frame, r, g, b, a, skip)
    seen[t] = true
    local rec = fills[t] or {}
    rec.r, rec.g, rec.b, rec.a, rec.frame, rec.skip = Num(r), Num(g), Num(b), tonumber(a) or 1, frame, skip
    fills[t] = rec
    PaintFill(t, rec, mod.Current())
    return rec
end

---------------------------------------------------------------------------
-- Edges (UI.Border's four 1 px textures)
---------------------------------------------------------------------------
local function Points(t)
    local p = {}
    for i = 1, Num(t.GetNumPoints and t:GetNumPoints()) do
        local a, rel, b, x, y = t:GetPoint(i)
        p[#p + 1] = { a, rel, b, Num(x), Num(y) }
    end
    return p
end

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

local function PaintBorder(rec, S)
    local cls = S and BorderClass(rec)
    if not cls then
        if rec.painted then
            for i, t in ipairs(rec.edges) do
                t:SetColorTexture(rec.r, rec.g, rec.b, rec.a)
                Thickness(t, rec.horizontal[i], rec.thick[i], false)
                PlaceEdge(t, rec.points[i], rec.horizontal[i], false)
            end
            for _, ring in pairs(rec.rings or {}) do ShowRing(ring, nil) end
            rec.painted = nil
        end
        return
    end
    local h = Size(rec.frame)
    local small = (h > 0 and h <= 32) or (h <= 0 and math.max(rec.r, rec.g, rec.b) >= 0.28)
    local c
    if cls == "neutral" then
        c = small and S.controlBorder or S.border
    elseif S.accentBorder == "BLACK" then
        c = { 0, 0, 0, rec.a > 0 and 1 or 0 }
    elseif AccentOn() then
        local r, g, b = S.accent()
        c = { r, g, b, rec.a }
    else
        c = { rec.r, rec.g, rec.b, rec.a }
    end
    for i, t in ipairs(rec.edges) do
        t:SetColorTexture(c[1], c[2], c[3], c[4])
        Thickness(t, rec.horizontal[i], 1, S.pixel)
        PlaceEdge(t, rec.points[i], rec.horizontal[i], S.round)
    end
    rec.rings = rec.rings or {}
    local f = rec.frame
    if S.inner and not rec.rings.inner then rec.rings.inner = Ring(f, 1, "BORDER", 1) end
    ShowRing(rec.rings.inner, S.inner)
    local shadow = (not small) and S.shadow
    for k = 1, 2 do
        local key = "shadow" .. k
        if shadow and shadow[k] and not rec.rings[key] then rec.rings[key] = Ring(f, -k, "BACKGROUND", -8, true) end
        ShowRing(rec.rings[key], shadow and shadow[k])
    end
    rec.painted = true
end

local function AddBorder(frame, edges, r, g, b, a)
    for _, t in ipairs(edges) do seen[t] = true end
    local rec = borders[edges[1]]
    if not rec then
        rec = { frame = frame, edges = edges, points = {}, horizontal = {}, thick = {} }
        for i, t in ipairs(edges) do
            rec.points[i] = Points(t)
            rec.horizontal[i] = Horizontal(rec.points[i])
            local px = rec.horizontal[i] and t:GetHeight() or t:GetWidth()
            rec.thick[i] = (tonumber(px) and px > 0 and px <= 4) and px or 1
        end
        borders[edges[1]] = rec
    end
    rec.r, rec.g, rec.b, rec.a = Num(r), Num(g), Num(b), tonumber(a) or 1
    PaintBorder(rec, mod.Current())
    return rec
end

---------------------------------------------------------------------------
-- Fonts, accent pieces, tracks, accent text
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

local function PaintColor(kind, t, rec, S)
    local c
    if S then
        if kind == "track" then c = S.track
        elseif AccentOn() then
            local r, g, b = S.accent()
            c = { r, g, b, rec.a }
        end
    end
    local set = (kind == "text") and t.SetTextColor or t.SetColorTexture
    if not c then
        if rec.painted then set(t, rec.r, rec.g, rec.b, rec.a); rec.painted = nil end
        return
    end
    set(t, c[1], c[2], c[3], c[4])
    rec.painted = true
end

local function AddColor(list, kind, t, r, g, b, a)
    if not t or list[t] then return end
    seen[t] = true
    local rec = { r = Num(r), g = Num(g), b = Num(b), a = tonumber(a) or 1 }
    list[t] = rec
    PaintColor(kind, t, rec, mod.Current())
end

local function AddAccentTexture(t)
    local A = MMT.UI.ACCENT
    AddColor(accents, "accent", t, A[1], A[2], A[3], 1)
end

local function AddAccentText(fs)
    if not (fs and fs.GetTextColor) or texts[fs] then return end
    local r, g, b, a = fs:GetTextColor()
    if not IsAccent(Num(r), Num(g), Num(b)) then return end
    AddColor(texts, "text", fs, r, g, b, a)
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
end

-- the settings window's base fill belongs to the core's background picker
-- (pull request "settings-background") while a picture is chosen there
local function BackgroundShown()
    local fn = MMT.ConfigBackground
    if type(fn) ~= "function" then return false end
    local ok, key = pcall(fn)
    return ok and key ~= nil and key ~= "NONE"
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
        if frame.GetName and frame:GetName() == "MMTConfigFrame" then skip = BackgroundShown end
        AddFill(t, frame, r, g, b, a, skip)
    end)
    H("Border", function(frame, r, g, b, a)
        local edges = Newest(frame, "Texture", 4, "BORDER")
        if #edges == 4 then AddBorder(frame, edges, r, g, b, a) end
    end)
    H("Label", function(parent)
        AddFont(Newest(parent, "FontString", 1)[1])
    end)
    H("Check", function(parent)
        local b = NewestChild(parent)
        local box = b and Children(b)[1]
        for _, t in ipairs(Regions(box)) do
            if Type(t) == "Texture" and Layer(t) == "ARTWORK" then AddAccentTexture(t) end
        end
    end)
    H("Slider", function(parent)
        local c = NewestChild(parent)
        for _, s in ipairs(Children(c)) do
            if Type(s) == "Slider" then
                for _, t in ipairs(Regions(s)) do
                    if Type(t) == "Texture" and Layer(t) == "BACKGROUND" then AddColor(tracks, "track", t, TRACK[1], TRACK[2], TRACK[3], TRACK[4]) end
                end
                local thumb = s.GetThumbTexture and s:GetThumbTexture()
                if thumb then AddAccentTexture(thumb) end
            end
        end
    end)
    local function Dropdown(parent)
        local b = NewestChild(parent)
        if b and rawget(b, "valueLabel") then AddAccentText(b.valueLabel) end
    end
    H("Dropdown", Dropdown)
    if UI.Cycle ~= UI.Dropdown then H("Cycle", Dropdown) end   -- the old name holds the unhooked function
    H("EditBox", function(parent)
        local e = NewestChild(parent)
        if Type(e) == "EditBox" then AddFont(e) end
    end)
    H("TextArea", function(parent)
        local holder = NewestChild(parent)
        local e = holder and rawget(holder, "edit")
        if e then AddFont(e) end
    end)
    H("SyncButton", function(page)
        local b = NewestChild(page)
        if not (b and type(rawget(b, "Update")) == "function") then return end
        -- its Update colours the fill again: paint it after that
        hooksecurefunc(b, "Update", function()
            Try(function()
                for _, t in ipairs(Regions(b)) do
                    local rec = fills[t]
                    if rec then rec.painted = true; PaintFill(t, rec, mod.Current()) end
                end
            end)
        end)
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
    end)
end
Install()

---------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------
function mod.Apply()
    local S = mod.Current()
    mod.ScanConfig()
    for t, rec in pairs(fills) do Try(PaintFill, t, rec, S) end
    for _, rec in pairs(borders) do Try(PaintBorder, rec, S) end
    for fs, rec in pairs(fonts) do Try(PaintFont, fs, rec, S) end
    for t, rec in pairs(accents) do Try(PaintColor, "accent", t, rec, S) end
    for t, rec in pairs(tracks) do Try(PaintColor, "track", t, rec, S) end
    for t, rec in pairs(texts) do Try(PaintColor, "text", t, rec, S) end
end

function mod.Counts()
    local function n(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
    return { fills = n(fills), borders = n(borders), fonts = n(fonts), accents = n(accents), tracks = n(tracks), texts = n(texts) }
end

-- test / debug access
mod.records = { fills = fills, borders = borders, fonts = fonts, accents = accents, tracks = tracks, texts = texts }

---------------------------------------------------------------------------
-- Public API for modules that colour textures themselves
---------------------------------------------------------------------------
QStyles = QStyles or {}
QStyles.VERSION = 1

-- instead of texture:SetColorTexture(r, g, b, a) for a window's background
function QStyles.Paint(t, r, g, b, a)
    if not t then return end
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
