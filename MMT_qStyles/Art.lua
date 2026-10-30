-- MMT Styles: the Classic style's game textures, and the drawn dropdown arrow /
-- close button of every style. All art is the client's own (Interface\...
-- files and atlases), nothing is shipped or copied.
--
-- Classic per frame (mod.ArtKind, from the role the widget hooks gave it and
-- its size):
--   button   the red panel button: MMT's fill becomes its middle piece, two end
--            pieces + a highlight are added; darker while pressed
--   check    MMT's box fill becomes the check box, the mark the yellow tick
--   dropdown the old dropdown frame (CharacterCreate-LabelFrame, 3 pieces) and
--            the round arrow button; input = the old edit box (Common-Input-Border)
--   dialog   windows >= 150 x 100 (mod.IsWindow: parent UIParent, or a side panel outside its parent;
--            not the dropdown list / colour picker): the background picked on the page
--            (mod.CLASSIC_BGS: stone by default) on the frame, the carved border
--            on a child frame ABOVE it (so it also shows over the core's
--            background pictures and the window's own pieces), full thickness
--            (32) on windows >= 400 x 200; MMT's fill and edges go transparent
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
    dropdown = "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame",
    arrowDown = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
    arrowHighlight = "Interface\\Buttons\\UI-Common-MouseHilight",
    selected = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    input = "Interface\\Common\\Common-Input-Border",
}
mod.ART_FILES = FILE
-- the old button file: Left / Middle / Right of the 80 x 22 button in a 128 x 32 texture
local COORD = { Left = { 0, 0.09375, 0, 0.6875 }, Center = { 0.09375, 0.53125, 0, 0.6875 }, Right = { 0.53125, 0.625, 0, 0.6875 } }

-- one table per look: the game keeps the table a frame got (it is read again on every resize), never change one
local DIALOG_EDGE = { [32] = { edgeFile = FILE.dialogEdge, edgeSize = 32 }, [24] = { edgeFile = FILE.dialogEdge, edgeSize = 24 } }
local dialogBg = {}   -- [background file] = backdrop (the whole window: the border is outside it)
local function DialogBg(bg)
    dialogBg[bg.file] = dialogBg[bg.file] or { bgFile = bg.file, tile = true, tileSize = bg.tile }
    return dialogBg[bg.file]
end
local THIN_BG = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 }
local THIN_EDGE = { edgeFile = FILE.tipEdge, edgeSize = 12 }
local TOOLTIP_BLUE = { 0.09, 0.09, 0.19 }   -- the game's classic tooltip background colour

-- window backgrounds for Classic (the dialog background itself is almost black)
mod.CLASSIC_BGS = {
    { value = "ROCK", text = "Stone", file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = 256, tint = { 0.75, 0.75, 0.75 } },
    { value = "MARBLE", text = "Marble", file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = 256, tint = { 0.6, 0.6, 0.6 } },
    { value = "TOOLTIP", text = "Tooltip blue", file = "Interface\\Tooltips\\UI-Tooltip-Background", tile = 16, tint = TOOLTIP_BLUE },
    { value = "DARK", text = "Dark (old dialogs)", file = FILE.dialogBg, tile = 32, tint = { 1, 1, 1 } },
}

-- false when this client doesn't have the file (nil = can't tell)
function mod.HasFile(file)
    if not GetFileIDFromPath then return nil end
    local ok, id = pcall(GetFileIDFromPath, file)
    if not ok then return nil end
    return id ~= nil
end

-- the page's choices, with the ones this client lacks marked
function mod.ClassicBgChoices()
    local t = {}
    for _, b in ipairs(mod.CLASSIC_BGS) do
        t[#t + 1] = { value = b.value, text = b.text .. (mod.HasFile(b.file) == false and " (not on this client)" or "") }
    end
    return t
end

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

-- popups that are lists, not windows: the thin border like the game's dropdown menus
local LISTS = { MMTDropdownList = true, MMTColorPopup = true }

local function Outside(p, rp)
    p, rp = tostring(p), tostring(rp)
    return (p:find("LEFT") and rp:find("RIGHT")) or (p:find("RIGHT") and rp:find("LEFT"))
        or (p:find("TOP") and rp:find("BOTTOM")) or (p:find("BOTTOM") and rp:find("TOP"))
end

-- a window: on the screen itself, or a side panel attached OUTSIDE its parent (Team Inventory's Team panel);
-- a panel inside a page or window (Statistics' gold graph, a window's list) is not
function mod.IsWindow(frame)
    local name = frame.GetName and frame:GetName()
    if name and LISTS[name] then return false end
    local parent = frame.GetParent and frame:GetParent()
    if parent == nil or parent == UIParent then return true end
    for i = 1, tonumber(frame.GetNumPoints and frame:GetNumPoints()) or 0 do
        local p, rel, rp = frame:GetPoint(i)
        if rel == parent and Outside(p, rp) then return true end
    end
    return false
end

function mod.ArtKind(frame)
    if not frame then return nil end
    local role = mod.roles[frame]
    if role == "button" or role == "check" then
        if frame.IsProtected and frame:IsProtected() then return nil end
        return role
    end
    if role == "dropdown" or role == "input" then
        if frame.IsProtected and frame:IsProtected() then return nil end
        if mod.borderOf[frame] then return role end
    end
    if not mod.borderOf[frame] or not CanBackdrop(frame) then return nil end
    if role then return "thin" end
    local w, h = mod.Size(frame)
    if mod.IsWindow(frame) and w >= 150 and h >= 100 then return "dialog" end
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
    elseif mod.FillClass(rec) == "accent" then
        -- a selected row (MMT's accent at low alpha): the quest log's selection glow
        t:SetTexture(FILE.selected)
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:SetVertexColor(1, 1, 1, math.min(1, rec.a * 4))
        rec.art = true
        return true
    elseif kind == "check" then
        t:SetTexture(FILE.checkBox)
        t:SetVertexColor(1, 1, 1, 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", rec.frame, "CENTER", 0, 0)
        t:SetSize(24, 24)
        rec.art = true
        return true
    elseif kind == "dialog" or kind == "thin" or kind == "dropdown" or kind == "input" then
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
-- Dropdown / edit box pieces, the dialog's border frame
---------------------------------------------------------------------------
local function Pieces(f, kind)
    local s = State(f)
    s.pieces = s.pieces or {}
    local p = s.pieces[kind]
    if p then return p end
    p = { Tex(f, "BACKGROUND", 2), Tex(f, "BACKGROUND", 2), Tex(f, "BACKGROUND", 2) }
    local left, mid, right = p[1], p[2], p[3]
    if kind == "dropdown" then
        -- the art is 64 px high for a ~26 px box: scaled to the widget
        local _, h = mod.Size(f)
        local k = ((h > 0) and h or 20) / 26
        for i, c in ipairs({ { 0, 0.1953125 }, { 0.1953125, 0.8046875 }, { 0.8046875, 1 } }) do
            p[i]:SetTexture(FILE.dropdown)
            p[i]:SetTexCoord(c[1], c[2], 0, 1)
            p[i]:SetHeight(64 * k)
        end
        left:SetWidth(25 * k); left:SetPoint("LEFT", f, "LEFT", -16 * k, -2 * k)
        right:SetWidth(25 * k); right:SetPoint("RIGHT", f, "RIGHT", 16 * k, -2 * k)
    else
        for i, c in ipairs({ { 0, 0.0625 }, { 0.0625, 0.9375 }, { 0.9375, 1 } }) do
            p[i]:SetTexture(FILE.input)
            p[i]:SetTexCoord(c[1], c[2], 0, 0.625)
        end
        left:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 0); left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -2, 0); left:SetWidth(8)
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 0); right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, 0); right:SetWidth(8)
    end
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
    s.pieces[kind] = p
    return p
end

local function ShowPieces(f, kind)
    local s = state[f]
    for k, p in pairs(s and s.pieces or {}) do
        for _, t in ipairs(p) do t:SetShown(k == kind) end
    end
end

-- the carved border, on a child frame above everything the window draws itself
-- `out` px OUTSIDE the frame: the border frames the window's content instead of covering what sits near its edge
-- (MMT's windows keep only a few px between their 1 px edge and the content)
local function EdgeFrame(f, out)
    local s = State(f)
    if s.edge == nil then
        s.edge = false
        if BackdropTemplateMixin then
            local e = CreateFrame("Frame", nil, f, "BackdropTemplate")
            mod.seen[e] = true   -- not a widget of the page (the hooks look for the newest child)
            if e.EnableMouse then e:EnableMouse(false) end
            e:Hide()
            s.edge = e
        end
    end
    local e = s.edge
    if not e then return nil end
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out)
    e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out)
    e:SetFrameLevel(f:GetFrameLevel() + 20)
    return e
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
    if kind == "dropdown" or kind == "input" then
        Pieces(f, kind)
        ShowPieces(f, kind)
    elseif kind == "dialog" then
        local picture = f.GetName and f:GetName() == "MMTConfigFrame" and mod.BackgroundShown()
        if not picture then
            local bg = ClassicBg()
            SetBackdrop(f, DialogBg(bg), bg.tint[1], bg.tint[2], bg.tint[3], math.max(a, 0.9))
        end
        local w, h = mod.Size(f)
        local size = (w >= 400 and h >= 200) and 32 or 24
        local e = EdgeFrame(f, size == 32 and 10 or 7)   -- the art's visible border is about a third of its size
        if e then
            e:SetBackdrop(DIALOG_EDGE[size])
            if e.SetBackdropBorderColor then e:SetBackdropBorderColor(1, 1, 1, 1) end
            e:Show()
        end
    elseif kind == "thin" then
        local c = TOOLTIP_BLUE
        SetBackdrop(f, THIN_BG, c[1], c[2], c[3], math.max(a, 0.9))
        local e = EdgeFrame(f, 3)
        if e then
            e:SetBackdrop(THIN_EDGE)
            if e.SetBackdropBorderColor then e:SetBackdropBorderColor(0.8, 0.8, 0.8, 1) end
            e:Show()
        end
    end
    return true
end

function mod.ArtUndoBorder(rec)
    local s = state[rec.frame]
    if s then
        s.kind = nil
        if s.edge then s.edge:Hide() end
        ShowPieces(rec.frame, nil)
    end
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
            if not s.arrowTex then
                s.arrowTex = Tex(f, "OVERLAY")
                s.arrowHl = Tex(f, "HIGHLIGHT")
                if f.HookScript then
                    f:HookScript("OnMouseDown", function() if s.arrowTex:IsShown() then s.arrowTex:SetTexture(FILE.arrowDown) end end)
                    f:HookScript("OnMouseUp", function() if s.arrowTex:IsShown() then s.arrowTex:SetTexture(FILE.arrow) end end)
                end
            end
            tex = s.arrowTex
            tex:SetTexture(FILE.arrow)
            tex:ClearAllPoints()
            tex:SetPoint("RIGHT", f, "RIGHT", 2, 0)
            tex:SetSize(24, 24)
            s.arrowHl:SetTexture(FILE.arrowHighlight)
            if s.arrowHl.SetBlendMode then s.arrowHl:SetBlendMode("ADD") end
            s.arrowHl:ClearAllPoints()
            s.arrowHl:SetAllPoints(tex)
        elseif S and S.chevron then
            lines = Chevron(f) or nil
        end
        if s.arrowTex then s.arrowTex:SetShown(tex ~= nil); s.arrowHl:SetShown(tex ~= nil) end
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
