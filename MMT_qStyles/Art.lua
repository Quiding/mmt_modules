-- MMT Styles: the Classic style's game textures, and the drawn dropdown arrow /
-- close button of every style. All art is the client's own (Interface\...
-- files and atlases), nothing is shipped or copied.
--
-- Classic per frame (mod.ArtKind, from the role the widget hooks gave it and
-- its size):
--   button   the red panel button: MMT's fill becomes its middle piece, two end
--            pieces + a highlight are added; darker while pressed
--   check    MMT's box fill becomes the check box, the mark the yellow tick
--   dialog   windows >= 300 x 100: carved dialog border over the background
--            picked on the page (mod.CLASSIC_BGS: stone by default), MMT's
--            fill and edges go transparent
--   thin     everything else with edges (lists, dropdowns, edit boxes, small
--            panels): the thin tooltip border on the classic tooltip blue
-- A frame that is sized later (windows that grow with their content) is
-- checked again on OnSizeChanged: it may become a dialog.
-- Frames that already have a backdrop of their own or are protected (secure)
-- keep the colour look. Undo = ClearBackdrop + the saved points / sizes.

local _, mod = ...
local MMT = MMT

local FILE = {
    dialogBg = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dialogEdge = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tipEdge = "Interface\\Tooltips\\UI-Tooltip-Border",
    checkBox = "Interface\\Buttons\\UI-CheckBox-Up",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    sliderEdge = "Interface\\Buttons\\UI-SliderBar-Border",
    sliderBg = "Interface\\Buttons\\UI-SliderBar-Background",
    thumb = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal",
    close = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    arrow = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    buttonUp = "Interface\\Buttons\\UI-Panel-Button-Up",
    buttonDown = "Interface\\Buttons\\UI-Panel-Button-Down",
    buttonHighlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
}
mod.ART_FILES = FILE
-- the old button file: Left / Middle / Right of the 80 x 22 button in a 128 x 32 texture
local COORD = { Left = { 0, 0.09375, 0, 0.6875 }, Center = { 0.09375, 0.53125, 0, 0.6875 }, Right = { 0.53125, 0.625, 0, 0.6875 } }

local DIALOG = { bgFile = FILE.dialogBg, edgeFile = FILE.dialogEdge, tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 } }
local DIALOG_EDGE = { edgeFile = FILE.dialogEdge, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } }
local THIN = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = FILE.tipEdge, tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local TOOLTIP_BLUE = { 0.09, 0.09, 0.19 }   -- the game's classic tooltip background colour

-- window backgrounds for Classic (the dialog background itself is almost black)
mod.CLASSIC_BGS = {
    { value = "ROCK", text = "Stone", file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = 256, tint = { 0.6, 0.6, 0.6 } },
    { value = "MARBLE", text = "Marble", file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = 256, tint = { 0.5, 0.5, 0.5 } },
    { value = "TOOLTIP", text = "Tooltip blue", file = "Interface\\Tooltips\\UI-Tooltip-Background", tile = 16, tint = TOOLTIP_BLUE },
    { value = "DARK", text = "Dark (old dialogs)", file = FILE.dialogBg, tile = 32, tint = { 1, 1, 1 } },
}

-- the chosen one; a file this client doesn't have falls back to the old dialog background
local function ClassicBg()
    local key = mod.Opt("classicBg")
    local pick, dark
    for _, b in ipairs(mod.CLASSIC_BGS) do
        if b.value == key then pick = b end
        if b.value == "DARK" then dark = b end
    end
    pick = pick or mod.CLASSIC_BGS[1]
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, pick.file)
        if ok and not id then return dark end
    end
    return pick
end
mod.ClassicBg = ClassicBg
local SLIDER = { bgFile = FILE.sliderBg, edgeFile = FILE.sliderEdge, tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local state = setmetatable({}, { __mode = "k" })   -- [frame] = { mixed, backdrop, caps, highlight, ... }
local function State(f)
    local s = state[f]
    if not s then s = {}; state[f] = s end
    return s
end

local function Atlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and type(info) == "table" and info or nil
end

-- the modern client's red button atlases when it has them, else the old file
local useAtlas
local function ButtonAtlas()
    if useAtlas == nil then
        useAtlas = (Atlas("128-RedButton-Left") and Atlas("128-RedButton-Center") and Atlas("128-RedButton-Right")) and true or false
    end
    return useAtlas
end

local function SetPiece(t, part, pressed)
    if ButtonAtlas() and t.SetAtlas then
        local name = "128-RedButton-" .. part
        if pressed and Atlas(name .. "-Pressed") then name = name .. "-Pressed" end
        t:SetAtlas(name)
    else
        t:SetTexture(pressed and FILE.buttonDown or FILE.buttonUp)
        local c = COORD[part]
        t:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

local function CapWidth(h)
    h = (h and h > 0) and h or 20
    local info = ButtonAtlas() and Atlas("128-RedButton-Left")
    if info and tonumber(info.width) and tonumber(info.height) and info.height > 0 then
        return math.max(4, math.floor(h * info.width / info.height + 0.5))
    end
    return math.max(4, math.floor(h * 12 / 22 + 0.5))
end

local function Tex(f, layer, sub)
    local t = f:CreateTexture(nil, layer, nil, sub)
    mod.seen[t] = true
    t:Hide()
    return t
end

---------------------------------------------------------------------------
-- What a frame becomes
---------------------------------------------------------------------------
local function CanBackdrop(f)
    if not f or (f.IsProtected and f:IsProtected()) then return false end
    if f.SetBackdrop then return State(f).mixed and true or false end   -- a backdrop of its own: leave it
    return (BackdropTemplateMixin and Mixin) and true or false
end

function mod.ArtKind(frame)
    if not frame then return nil end
    local role = mod.roles[frame]
    if role == "button" or role == "check" then
        if frame.IsProtected and frame:IsProtected() then return nil end
        return role
    end
    if not mod.borderOf[frame] or not CanBackdrop(frame) then return nil end
    if role then return "thin" end
    local w, h = mod.Size(frame)
    if w >= 300 and h >= 100 then return "dialog" end
    return "thin"
end

local function SetBackdrop(f, def, r, g, b, a, er, eg, eb, ea)
    local s = State(f)
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
        if f.OnBackdropSizeChanged and f.HookScript then f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged) end
        s.mixed = true
    end
    f:SetBackdrop(def)
    if f.SetBackdropColor then f:SetBackdropColor(r or 1, g or 1, b or 1, a or 1) end
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(er or 1, eg or 1, eb or 1, ea or 1) end
    s.backdrop = true
end

local function ClearBackdrop(f)
    local s = state[f]
    if not (s and s.backdrop) then return end
    if f.ClearBackdrop then f:ClearBackdrop() else f:SetBackdrop(nil) end
    s.backdrop = nil
end

---------------------------------------------------------------------------
-- Fills
---------------------------------------------------------------------------
local function ButtonFill(t, rec)
    local f = rec.frame
    local s = State(f)
    local _, h = mod.Size(f)
    local cap = CapWidth(h)
    if not s.caps then
        s.caps = { Tex(f, "BACKGROUND"), Tex(f, "BACKGROUND") }
        s.highlight = Tex(f, "HIGHLIGHT")
        if f.HookScript then
            f:HookScript("OnMouseDown", function() if s.on then mod.Try(mod.ArtPress, f, true) end end)
            f:HookScript("OnMouseUp", function() if s.on then mod.Try(mod.ArtPress, f, false) end end)
        end
    end
    s.middle, s.on = t, true
    local left, right = s.caps[1], s.caps[2]
    left:ClearAllPoints(); left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); left:SetWidth(cap)
    right:ClearAllPoints(); right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); right:SetWidth(cap)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", cap, 0); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -cap, 0)
    t:SetVertexColor(1, 1, 1, 1)
    mod.ArtPress(f, false)
    left:Show(); right:Show()
    local hl = s.highlight
    hl:ClearAllPoints(); hl:SetAllPoints(f)
    if ButtonAtlas() and Atlas("128-RedButton-Highlight") and hl.SetAtlas then
        hl:SetAtlas("128-RedButton-Highlight")
    else
        hl:SetTexture(FILE.buttonHighlight)
        hl:SetTexCoord(0, 0.625, 0, 0.6875)
    end
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    hl:Show()
    rec.art = true
end

function mod.ArtPress(f, pressed)
    local s = state[f]
    if not (s and s.on and s.caps) then return end
    SetPiece(s.caps[1], "Left", pressed)
    SetPiece(s.middle, "Center", pressed)
    SetPiece(s.caps[2], "Right", pressed)
end

function mod.ArtFill(t, rec, S)
    local kind = mod.ArtKind(rec.frame)
    if kind == "button" then
        ButtonFill(t, rec)
        return true
    elseif kind == "check" then
        t:SetTexture(FILE.checkBox)
        t:SetVertexColor(1, 1, 1, 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", rec.frame, "CENTER", 0, 0)
        t:SetSize(24, 24)
        rec.art = true
        return true
    elseif kind == "dialog" or kind == "thin" then
        t:SetColorTexture(0, 0, 0, 0)   -- the backdrop is the background
        return true
    end
    return false   -- nothing: the style's colour
end

function mod.ArtUndoFill(t, rec)
    local s = state[rec.frame]
    if not s then return end
    if s.caps and s.middle == t then
        s.on = nil
        for _, c in ipairs(s.caps) do c:Hide() end
        if s.highlight then s.highlight:Hide() end
    end
end

---------------------------------------------------------------------------
-- Edges
---------------------------------------------------------------------------
function mod.ArtBorder(rec, S)
    local f = rec.frame
    local kind = mod.ArtKind(f)
    if not kind then return false end   -- the colour look with Classic's grey edges
    local s = State(f)
    s.kind = kind
    if not s.sizeHook and f.HookScript then
        s.sizeHook = true
        -- sized later (or resized): a small "thin" frame may now be a window, or the other way round
        f:HookScript("OnSizeChanged", function()
            if s.kind and mod.Current() and mod.Current().art and mod.ArtKind(f) ~= s.kind then mod.Try(mod.Repaint, f) end
        end)
    end
    for _, t in ipairs(rec.edges) do t:SetColorTexture(rec.r, rec.g, rec.b, 0) end
    local fill = mod.fillOf[f]
    local a = fill and mod.records.fills[fill] and mod.records.fills[fill].a or 1
    if kind == "dialog" then
        local picture = f.GetName and f:GetName() == "MMTConfigFrame" and mod.BackgroundShown()
        local bg = ClassicBg()
        DIALOG.bgFile, DIALOG.tileSize = bg.file, bg.tile
        SetBackdrop(f, picture and DIALOG_EDGE or DIALOG, bg.tint[1], bg.tint[2], bg.tint[3], math.max(a, 0.9), 1, 1, 1, 1)
    elseif kind == "thin" then
        local c = TOOLTIP_BLUE
        SetBackdrop(f, THIN, c[1], c[2], c[3], math.max(a, 0.9), 0.8, 0.8, 0.8, 1)
    end
    return true
end

function mod.ArtUndoBorder(rec)
    local s = state[rec.frame]
    if s then s.kind = nil end
    ClearBackdrop(rec.frame)
end

---------------------------------------------------------------------------
-- Check mark, slider
---------------------------------------------------------------------------
function mod.ArtColor(t, rec, S)
    if rec.kind == "mark" then
        local box = t.GetParent and t:GetParent()
        t:SetTexture(FILE.check)
        t:SetVertexColor(1, 1, 1, 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", box, "CENTER", 0, 0)
        t:SetSize(24, 24)
        return true
    elseif rec.kind == "thumb" then
        t:SetTexture(FILE.thumb)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetSize(32, 32)
        return true
    elseif rec.kind == "track" then
        local s = t.GetParent and t:GetParent()
        if not CanBackdrop(s) then return false end
        t:SetColorTexture(0, 0, 0, 0)
        SetBackdrop(s, SLIDER, 1, 1, 1, 1, 1, 1, 1, 1)
        return true
    end
    return false
end

function mod.ArtUndoColor(t, rec)
    if rec.kind == "track" then ClearBackdrop(t:GetParent()) end
end

---------------------------------------------------------------------------
-- Dropdown arrow and close button (every style)
---------------------------------------------------------------------------
local function Chevron(f)
    local s = State(f)
    if s.chevron ~= nil then return s.chevron end
    s.chevron = false
    if not f.CreateLine then return false end
    local lines = {}
    for i, p in ipairs({ { -15, 2, -11, -2 }, { -11, -2, -7, 2 } }) do
        local ok, l = pcall(f.CreateLine, f, nil, "OVERLAY")
        if not (ok and l and l.SetStartPoint) then return false end
        l:SetThickness(1.5)
        l:SetStartPoint("RIGHT", f, p[1], p[2])
        l:SetEndPoint("RIGHT", f, p[3], p[4])
        l:Hide()
        lines[i] = l
    end
    s.chevron = lines
    return lines
end

local function PaintWidget(f, w, S)
    local s = State(f)
    if w.arrow then
        local tex, lines = nil, nil
        if S and S.art then
            s.arrowTex = s.arrowTex or Tex(f, "OVERLAY")
            tex = s.arrowTex
            tex:SetTexture(FILE.arrow)
            tex:ClearAllPoints()
            tex:SetPoint("RIGHT", f, "RIGHT", -2, 0)
            tex:SetSize(18, 18)
        elseif S and S.chevron then
            lines = Chevron(f) or nil
        end
        if s.arrowTex then s.arrowTex:SetShown(tex ~= nil) end
        if type(s.chevron) == "table" then
            for _, l in ipairs(s.chevron) do
                if lines then l:SetColorTexture(1, 1, 1, 0.6); l:Show() else l:Hide() end
            end
        end
        w.arrow:SetAlpha((tex or lines) and 0 or 1)
    end
    if w.close then
        if S and S.art then
            s.closeTex = s.closeTex or Tex(f, "ARTWORK")
            s.closeTex:SetTexture(FILE.close)
            s.closeTex:ClearAllPoints()
            s.closeTex:SetPoint("CENTER", f, "CENTER", 0, 0)
            s.closeTex:SetSize(26, 26)
            s.closeTex:Show()
            w.close:SetAlpha(0)
        else
            if s.closeTex then s.closeTex:Hide() end
            w.close:SetAlpha(1)
        end
    end
end

function mod.ArtWidgets(S)
    for f, w in pairs(mod.widgets) do mod.Try(PaintWidget, f, w, S) end
end

function mod.WidgetAdded(f, w)
    PaintWidget(f, w, mod.Current())
end

-- tests: the atlas check is made once per session
function mod.ResetArtCache() useAtlas = nil end
