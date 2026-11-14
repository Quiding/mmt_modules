-- Typed slider values for a module's settings page (shared by our modules: KEEP EVERY COPY IDENTICAL).
-- MMT core's sliders (UI.Slider: a label, the value on the right, the track below) only drag.
-- mod.TypedSliders(page) finds the sliders on the page - also ones built later (tabs) - and makes
-- the value clickable: it turns into a small text box, type 250 or 250% (or 0,5), Enter sets it
-- (kept inside the slider's range and on its step), Escape or clicking away leaves it. The value
-- goes through the slider itself, so the setting, its label and the redraw are the core's own.
-- Core's widget isn't changed.

local _, mod = ...

local done = setmetatable({}, { __mode = "k" })   -- sliders already given a box

-- "250", "250%", " 0,5 " -> number; nil when it isn't one
function mod.ParseTyped(text)
    local t = tostring(text or ""):gsub("%%", ""):gsub(",", "."):match("^%s*(-?%d*%.?%d+)%s*$")
    return tonumber(t)
end

-- the number in range and on the step (from the slider's minimum)
function mod.FitTyped(n, lo, hi, step)
    n = math.max(lo, math.min(hi, n))
    if step and step > 0 then n = lo + math.floor((n - lo) / step + 0.5) * step end
    return math.max(lo, math.min(hi, n))
end

local function ShowText(n, step)
    if step and step < 1 then
        local s = ("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")
        return s
    end
    return tostring(math.floor(n + 0.5))
end

local function Enhance(c, s)
    local value
    for _, r in ipairs({ c:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetPoint and r:GetPoint(1) == "TOPRIGHT" then value = r end
    end
    if not value then return end
    local box = CreateFrame("EditBox", nil, c)
    box:SetAutoFocus(false)
    box:SetFontObject(value:GetFontObject() or "GameFontHighlightSmall")
    box:SetSize(64, 16)
    box:SetPoint("TOPRIGHT", 0, 2)
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(4, 4, 0, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    box:Hide()
    local hit = CreateFrame("Button", nil, c)
    hit:SetSize(64, 16)
    hit:SetPoint("TOPRIGHT", 0, 2)
    local function Close()
        box:ClearFocus()
        box:Hide()
        value:Show()
        hit:Show()
    end
    hit:SetScript("OnClick", function()
        if s.IsEnabled and not s:IsEnabled() then return end
        box:SetText(ShowText(s:GetValue(), s:GetValueStep()))
        value:Hide()
        hit:Hide()
        box:Show()
        box:SetFocus()
        box:HighlightText()
    end)
    hit:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local lo, hi = s:GetMinMaxValues()
        local step = s:GetValueStep()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to type a value")
        GameTooltip:AddLine(("%s to %s, Enter sets it"):format(ShowText(lo, step), ShowText(hi, step)), 1, 1, 1)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    box:SetScript("OnEnterPressed", function()
        local n = mod.ParseTyped(box:GetText())
        if n then
            local lo, hi = s:GetMinMaxValues()
            s:SetValue(mod.FitTyped(n, lo, hi, s:GetValueStep()))
        end
        Close()
    end)
    box:SetScript("OnEscapePressed", Close)
    box:SetScript("OnEditFocusLost", Close)
    c.mmtTyped = box
end

local function Scan(f)
    for _, child in ipairs({ f:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Slider" then
            if not done[child] then
                done[child] = true
                Enhance(f, child)
            end
        else
            Scan(child)
        end
    end
end

-- the page now and whenever it shows (tabs build their panels later): once a second while shown
function mod.TypedSliders(page)
    if not (page and page.GetChildren) then return end
    local function Try() if page:IsVisible() then pcall(Scan, page) end end
    pcall(Scan, page)
    if page.HookScript then page:HookScript("OnShow", function() if C_Timer then C_Timer.After(0, Try) end end) end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, Try) end
end
