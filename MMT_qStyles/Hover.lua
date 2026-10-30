-- MMT Styles: the widget under the mouse (ElvUI: its edges in the accent colour;
-- EllesmereUI: brighter edges and label). One small frame watches the mouse
-- focus while a style with a hover look is on, instead of hooking OnEnter /
-- OnLeave of every widget (a later SetScript - a tooltip added by the page -
-- would drop such a hook). Classic needs none: its art has its own highlight.

local _, mod = ...
local MMT = MMT

local driver
local current      -- the widget frame lit now
local saved        -- its label's colour before, and what we set

local function Focus()
    if GetMouseFoci then
        local list = GetMouseFoci()
        return type(list) == "table" and list[1] or nil
    end
    return GetMouseFocus and GetMouseFocus() or nil
end

local function Color(c, S)
    if c ~= "ACCENT" then return c end
    if mod.AccentOn() then
        local r, g, b = S.accent()
        return { r, g, b, 1 }
    end
    local A = MMT.UI.ACCENT
    return { A[1], A[2], A[3], 1 }
end

local function Leave()
    local f = current
    current = nil
    if not f then return end
    local w = mod.widgets[f]
    local rec = w and mod.borderOf[w.edge]
    if rec then mod.PaintBorder(rec, mod.Current()) end
    if saved and saved.label then
        local r, g, b, a = saved.label:GetTextColor()
        local s = saved.set
        if math.abs(r - s[1]) < 0.02 and math.abs(g - s[2]) < 0.02 and math.abs(b - s[3]) < 0.02 and math.abs((a or 1) - s[4]) < 0.02 then
            mod.QuietTextColor(saved.label, saved.prev[1], saved.prev[2], saved.prev[3], saved.prev[4])
        end
    end
    saved = nil
end
mod.HoverReset = Leave

local function Enter(f)
    local S = mod.Current()
    local h = S and S.hover
    local w = mod.widgets[f]
    if not (h and w) then return end
    current = f
    local rec = mod.borderOf[w.edge]
    if rec and rec.painted and h.edge then mod.SetEdgeColor(rec, Color(h.edge, S)) end
    if w.label and h.label and w.label.GetTextColor then
        local c = Color(h.label, S)
        saved = { label = w.label, prev = { w.label:GetTextColor() }, set = { c[1], c[2], c[3], c[4] or 1 } }
        mod.QuietTextColor(w.label, c[1], c[2], c[3], c[4] or 1)
    end
end

local function OnUpdate()
    local f = Focus()
    if f == current then return end
    mod.Try(Leave)
    if f and mod.widgets[f] then mod.Try(Enter, f) end
end

function mod.HoverStart(S)
    if not (S and S.hover) then
        if driver then driver:Hide() end
        return
    end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
    end
    driver:Show()
end

-- test access
function mod.HoverTick() OnUpdate() end
