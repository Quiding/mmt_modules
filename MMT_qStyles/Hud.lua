-- MMT Styles: the windows you play with (Quest Tracker, Info window, Statistics' live tracker).
--
-- They are drawn with their own textures, not MMT.UI's widgets, so Skin.lua's
-- hooks never see them. This file finds them by their global names (they are
-- built when their addon loads, or later: the live tracker on first use) and
-- gives them the style's look without changing what their owner chose:
--   * the background: the style's panel colour (and gradient), with the owner's
--     opacity (the tracker's "Background opacity" stays what it is). A background
--     in a colour of the user's own (not a dark grey) is left alone.
--   * edges: 1 px in the style's border colour (none in MMT's own look)
--   * accent pieces (the live tracker's top line and title, the tracker's scroll
--     bar thumb): the style's accent colour while "Use the style's accent colour" is on
-- Classic and Modern Blizzard (game window art) leave these windows as they are:
-- the art is too heavy for a see-through window over the game.
-- Each is an entry of the Windows list (Targets.lua): off = untouched; its cogwheel
-- switches the background / edges / accent part off one by one.
-- Nothing of theirs is replaced; their own SetColorTexture calls are followed
-- (hooksecurefunc on our record of the texture) so a changed setting is painted again.
-- None, or the module switched off, puts back exactly the owner's colours.

local _, mod = ...

local windows = {}    -- [frame] = rec
local painting = false

local function Flat(S) return S and not S.art end
local function AccentOn() return mod.Opt("accent") and true or false end
-- the style for this window and part (nil: MMT's own look); part = "bg" | "edges" | "accent"
local function Want(rec, S, part)
    if not Flat(S) or not mod.TargetOn(rec.id) then return nil end
    if mod.TargetOpt(rec.id, part, true) == false then return nil end
    return S
end

local function DarkNeutral(c)
    local hi = math.max(c.r, c.g, c.b)
    return hi < 0.2 and (hi - math.min(c.r, c.g, c.b)) < 0.05
end

local function SetTex(t, r, g, b, a)
    painting = true
    t:SetColorTexture(r, g, b, a)
    painting = false
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
local function PaintBg(rec, S)
    local t, o = rec.bg, rec.bgColour
    if rec.gradient then t:SetVertexColor(1, 1, 1, 1) rec.gradient = nil end
    rec.visible = o.a > 0 and DarkNeutral(o)   -- a background of the user's own colour stays theirs
    S = rec.visible and Want(rec, S, "bg") or nil
    rec.styled = S and true or false
    if not rec.styled then
        SetTex(t, o.r, o.g, o.b, o.a)
        return
    end
    local p, top = S.panel, S.panelTop
    if top and t.SetGradient and CreateColor then
        SetTex(t, 1, 1, 1, 1)
        if pcall(t.SetGradient, t, "VERTICAL", CreateColor(p[1], p[2], p[3], o.a), CreateColor(top[1], top[2], top[3], o.a)) then
            rec.gradient = true
            return
        end
    end
    SetTex(t, p[1], p[2], p[3], o.a)
end

local function PaintEdges(rec, S)
    S = rec.visible and Want(rec, S, "edges") or nil
    local c = S and S.border
    for _, t in ipairs(rec.edges) do
        if c then
            t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            t:Show()
        else
            t:Hide()
        end
    end
end

local function PaintAccents(rec, S)
    S = Want(rec, S, "accent")
    for _, a in ipairs(rec.accents) do
        if S and AccentOn() then
            local r, g, b = S.accent()
            SetTex(a.t, r, g, b, a.a)
        else
            SetTex(a.t, a.r, a.g, a.b, a.a)
        end
    end
end

local function Paint(rec, S)
    pcall(PaintBg, rec, S)
    pcall(PaintEdges, rec, S)
    pcall(PaintAccents, rec, S)
end

---------------------------------------------------------------------------
-- Recording a window
---------------------------------------------------------------------------
local function Edges(f)
    local e = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER", nil, 7)
        t:Hide()
        e[i] = t
    end
    local function Px(t, horizontal)
        if PixelUtil and PixelUtil.SetHeight then
            if horizontal then PixelUtil.SetHeight(t, 1) else PixelUtil.SetWidth(t, 1) end
        elseif horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); Px(e[1], true)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); Px(e[2], true)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); Px(e[3], false)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); Px(e[4], false)
    return e
end

-- There is no getter for a colour texture's colour: the owner's values start as the
-- defaults it builds with (read from its code), then follow every SetColorTexture it makes.
local function Add(id, frame, bg, bgDefault, accents)
    if windows[frame] or not bg then return end
    local rec = { id = id, frame = frame, bg = bg, bgColour = bgDefault, edges = Edges(frame), accents = {} }
    for _, a in ipairs(accents or {}) do
        if a.t then
            local entry = { t = a.t, r = a.r, g = a.g, b = a.b, a = a.a }
            rec.accents[#rec.accents + 1] = entry
            hooksecurefunc(a.t, "SetColorTexture", function(_, r, g, b, al)
                if painting then return end
                entry.r, entry.g, entry.b, entry.a = r or entry.r, g or entry.g, b or entry.b, al or 1
                pcall(PaintAccents, rec, mod.Current())
            end)
        end
    end
    -- the owner paints its background again (the tracker on every redraw): follow it
    hooksecurefunc(bg, "SetColorTexture", function(_, r, g, b, a)
        if painting then return end
        rec.bgColour = { r = r or 0, g = g or 0, b = b or 0, a = a or 1 }
        pcall(PaintBg, rec, mod.Current())
        pcall(PaintEdges, rec, mod.Current())
    end)
    windows[frame] = rec
    Paint(rec, mod.Current())
end

local A = (MMT and MMT.UI and MMT.UI.ACCENT) or { 0.31, 0.70, 1.00 }

local function QuestTracker()
    local f = rawget(_G, "MMTQuestTrackerFrame")
    if not f or windows[f] or not f.bg then return windows[f] ~= nil end
    local accents = {}
    if f.sb and f.sb.thumb then accents[1] = { t = f.sb.thumb, r = 1, g = 1, b = 1, a = 0.55 } end
    -- its own background setting (Quest Tracker > Look): black, 0.35 by default; the real value
    -- arrives with its next redraw (hook)
    local QT = MMT and MMT.modules and MMT.modules.QuestTracker
    local db = QT and QT.db
    local c = db and db.bg or { r = 0, g = 0, b = 0 }
    Add("questtracker", f, f.bg, { r = c.r or 0, g = c.g or 0, b = c.b or 0, a = db and db.bgAlpha or 0.35 }, accents)
    return true
end

local function LiveTracker()
    local f = rawget(_G, "MMTStatsLiveTracker")
    if not f or windows[f] or not f.bg then return windows[f] ~= nil end
    Add("livetracker", f, f.bg, { r = 0, g = 0, b = 0, a = 0.6 }, { { t = f.line, r = A[1], g = A[2], b = A[3], a = 0.8 } })
    if f.title and mod.AddText then pcall(mod.AddText, f.title, "accent") end
    return true
end

-- the Info window (MMT/XPWindow.lua): its background (black, "Background opacity"), the
-- bars keep their colours; made when MMT loads, so found right away
local function InfoWindow()
    local f = rawget(_G, "MMTXPFrame")
    if not f or windows[f] or not f.bg then return windows[f] ~= nil end
    local x = MMT and MMT.db and MMT.db.xp
    Add("infowindow", f, f.bg, { r = 0, g = 0, b = 0, a = x and x.bgAlpha or 0.35 }, {})
    return true
end

-- both are made when their addon loads or later (the live tracker on first use): look until found
local ticker
local function Find()
    local a, b, c = QuestTracker(), LiveTracker(), InfoWindow()
    if a and b and c and ticker then ticker:Cancel() ticker = nil end
end
ticker = C_Timer.NewTicker(3, Find)
C_Timer.After(0, Find)

-- every style / option switch (Skin.lua mod.Apply)
mod.listeners = mod.listeners or {}
table.insert(mod.listeners, function()
    local S = mod.Current()
    for _, rec in pairs(windows) do Paint(rec, S) end
end)

function mod.HudReport()
    local n = {}
    for f, rec in pairs(windows) do n[#n + 1] = ((f.GetName and f:GetName()) or "?") .. (rec.styled and "=styled" or "=own") end
    table.sort(n)
    return "play windows: " .. (#n > 0 and table.concat(n, " ") or "none found yet")
end
