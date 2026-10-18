-- MMTIconBars: a movable window with one row of icons per team member, in
-- MMT's flat style. Shared by MMT_Cooldowns and MMT_Buffs: both ship this
-- same file and the newest version wins (like an embedded library), so
-- KEEP BOTH COPIES IDENTICAL and raise VERSION when changing it.
--
--   local w = MMTIconBars.NewWindow{
--       name   = "MMTCooldowns",           -- global frame name, also the id for extras
--       cfg    = function() return M.db end, -- layout settings, read fresh every time
--       rows   = function() return rows end, -- { { key, icons = { icon, ... } }, ... }
--                                            -- a row may have label (+ color {r,g,b}) instead of a key
--       config = function() ... end,         -- right-click (open settings)
--       active = function() return M.enabled end, -- optional: hidden while false
--   }
--   w:Refresh()          rebuild from rows()
--   w:SetShown(on)
--
-- icon = { texture, state, start, duration, count, spell, item, tip,
--          missingAlpha, glowMissing, activeAlpha (override the window's cfg for
--          "missing" / "buff"),
--          tint = { r, g, b }, desaturate = true,
--          glow = true (glow regardless of state),
--          after = { state, start, duration } (state to switch to when a "buff" runs out,
--                  e.g. a spell's buff, then its cooldown) }
--   state: "ready" | "cd" (start/duration) | "active" (glow) | "buff" (start/duration
--          optional, count) | "missing"
--
-- cfg fields: shown, locked, clickThrough, vertical, iconSize, spacing, rowGap,
--   showNames, fullNames, nameSize, showTimers, timerSize, readyAlpha, cdAlpha, missingAlpha, activeAlpha,
--   glowActive, glowMissing, scale, bgAlpha, point = { point, relPoint, x, y },
--   font (MMT font name), timerColor {r,g,b}, bgTexture / borderTexture (LibSharedMedia
--   names, "FLAT" / "NONE"), bgColor, borderColor {r,g,b}, borderSize, rowColor, rowAlpha,
--   bgTint (0..1: how strongly bgColor / rowColor colour a texture; Flat always takes the colour)
--
-- Extras: other modules can add icons to a window's rows:
--   MMTIconBars.SetExtra(windowName, id, fn(key) -> icons | nil, side "LEFT"|"RIGHT")
--   MMTIconBars.SetExtra(windowName, id, nil)   removes it

local VERSION = 9
if MMTIconBars and (MMTIconBars.version or 0) >= VERSION then return end

local lib = MMTIconBars or {}
MMTIconBars = lib
lib.version = VERSION
lib.windows = lib.windows or {}
lib.extras = lib.extras or {}   -- [windowName] = { [id] = { fn, side } }

local MMT = MMT

local function ClassColor(key)
    local m = MMT.db and MMT.db.team and MMT.db.team[key]
    local c = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- "First" or "First Last" (WoW: Forever characters have two names)
function lib.MemberName(key, full)
    if full then return MMT.FullDisplay(key) end
    return MMT.FirstName(key)
end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

-- LibSharedMedia texture (other addons bring it), nil for FLAT / NONE / unknown
local function Media(kind, name)
    if not name or name == "" or name == "FLAT" or name == "NONE" then return nil end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return LSM and LSM:Fetch(kind, name, true) or nil
end

-- background (+ border) of a frame; returns the inner padding the border needs
local function Skin(f, bgTex, color, alpha, edgeName, edgeColor, edgeSize, tint)
    color = color or {}
    local file = Media("background", bgTex)
    -- a real texture: blend white (its own colours) towards the colour by tint
    local r, g, b = color.r or 0, color.g or 0, color.b or 0
    if file then
        tint = math.max(0, math.min(1, tint or 1))
        r, g, b = 1 + (r - 1) * tint, 1 + (g - 1) * tint, 1 + (b - 1) * tint
    end
    local edge = Media("border", edgeName)
    if not f.SetBackdrop then
        f.bg:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, alpha or 0)
        return 0
    end
    if f.bg then f.bg:Hide() end
    local size = edge and (edgeSize or 12) or nil
    local inset = edge and math.floor(size / 4 + 0.5) or 0
    f:SetBackdrop({ bgFile = file or FLAT, edgeFile = edge, tile = false,
        edgeSize = size, insets = { left = inset, right = inset, top = inset, bottom = inset } })
    f:SetBackdropColor(r, g, b, alpha or 0)
    if edge then
        edgeColor = edgeColor or {}
        f:SetBackdropBorderColor(edgeColor.r or 1, edgeColor.g or 1, edgeColor.b or 1, 1)
    end
    return inset
end
lib.Media = Media

local function FormatTime(t)
    if t >= 3600 then return ("%dh"):format(math.floor(t / 3600 + 0.5)) end
    if t >= 60 then return ("%dm"):format(math.floor(t / 60 + 0.5)) end
    if t >= 10 then return tostring(math.floor(t + 0.5)) end
    return ("%.1f"):format(t)
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    local pulse = b.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.3); fade:SetDuration(0.5)
    b.pulse = pulse
    b.glow:Hide()
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.timer = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.timer:SetPoint("CENTER", 0, 0)
    b.count = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", function(self)
        local i = self.data
        if not i then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if i.spell then GameTooltip:SetSpellByID(i.spell)
        elseif i.item then GameTooltip:SetItemByID(i.item)
        else GameTooltip:SetText(i.tip or "?") end
        if self.key then GameTooltip:AddLine(MMT.FullDisplay(self.key), ClassColor(self.key)) end
        if i.tip and (i.spell or i.item) then GameTooltip:AddLine(i.tip, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- remaining seconds of a timed icon, or nil
local function Remaining(i)
    if i.start and i.duration and i.duration > 0 then
        local r = i.start + i.duration - GetTime()
        if r > 0 then return r end
    end
end

-- alpha, glow and timer text of one icon (called on every tick)
local function Paint(b, c)
    local i = b.data
    local state, rem = i.state, Remaining(i)
    if state == "buff" and i.after and not rem then
        -- the buff ran out: show what comes after it (the cooldown)
        local a = i.after
        i.state, i.start, i.duration, i.glow, i.after = a.state, a.start, a.duration, nil, nil
        if i.state == "cd" and Remaining(i) then b.cd:SetCooldown(i.start, i.duration); b.cd:Show() else b.cd:Hide() end
        return Paint(b, c)
    end
    if state == "cd" and not rem then state = "ready" end
    local alpha, glow = 1, false
    if state == "ready" then alpha = c.readyAlpha or 1
    elseif state == "cd" then alpha = c.cdAlpha or 1
    elseif state == "missing" then
        -- extras from another module bring their own look for "missing"
        alpha = i.missingAlpha or c.missingAlpha or 0.3
        if i.glowMissing ~= nil then glow = i.glowMissing else glow = c.glowMissing end
    elseif state == "buff" then alpha = i.activeAlpha or c.activeAlpha or 1
    elseif state == "active" then glow = c.glowActive end
    if i.glow then glow = true end
    b:SetAlpha(alpha)
    if glow then
        if not b.glow:IsShown() then b.glow:Show(); b.pulse:Play() end
    elseif b.glow:IsShown() then
        b.pulse:Stop(); b.glow:Hide()
    end
    if c.showTimers and rem and (state == "cd" or state == "buff") then
        b.timer:SetText(FormatTime(rem))
        local tc = c.timerColor
        if tc then b.timer:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1) end
        b.timer:Show()
    else
        b.timer:Hide()
    end
end

local function Setup(b, i, key, c)
    b.data, b.key = i, key
    b.tex:SetTexture(i.texture or 134400)
    local t = i.tint
    b.tex:SetVertexColor(t and t[1] or 1, t and t[2] or 1, t and t[3] or 1)
    if b.tex.SetDesaturated then b.tex:SetDesaturated(i.desaturate and true or false) end
    local size = c.iconSize or 28
    b:SetSize(size, size)
    b.glow:SetSize(size * 1.8, size * 1.8)
    b.glow:SetVertexColor(i.state == "missing" and 1 or 0.3, i.state == "missing" and 0.2 or 0.9, i.state == "missing" and 0.2 or 1)
    MMT.ApplyFont(b.timer, c.font, c.timerSize or 13, "OUTLINE")
    MMT.ApplyFont(b.count, c.font, math.max(8, math.floor((c.timerSize or 13) * 0.8)), "OUTLINE")
    b.count:SetText((i.count and i.count > 1) and i.count or "")
    if (i.state == "cd" or i.state == "buff") and Remaining(i) then
        b.cd:SetCooldown(i.start, i.duration)
        b.cd:Show()
    else
        b.cd:Hide()
    end
    b:EnableMouse(not c.clickThrough)
    Paint(b, c)
    b:Show()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function lib.NewWindow(def)
    local w = setmetatable({ def = def, rows = {} }, Window)
    local f = CreateFrame("Frame", def.name, UIParent, BACKDROP)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f:SetScript("OnDragStart", function(self) if not def.cfg().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        def.cfg().point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
    end)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" and def.config then def.config() end end)
    f:Hide()
    w.frame = f
    -- timers and expiry
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        local c = def.cfg()
        if not c then return end
        for _, row in ipairs(w.rows) do
            for _, b in ipairs(row.icons) do if b:IsShown() and b.data then Paint(b, c) end end
        end
    end)
    lib.windows[def.name] = w
    return w
end

function Window:Row(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, self.frame, BACKDROP)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.icons = {}
    row:RegisterForDrag("LeftButton")
    local f = self.frame
    row:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
    row:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    row:SetScript("OnMouseUp", function(_, button) f:GetScript("OnMouseUp")(f, button) end)
    self.rows[i] = row
    return row
end

-- icons of a row including the other modules' extras
local function WithExtras(name, key, icons)
    local ex = lib.extras[name]
    if not ex then return icons end
    local left, right = {}, {}
    for _, e in pairs(ex) do
        local ok, list = pcall(e.fn, key)
        if ok and type(list) == "table" then
            for _, i in ipairs(list) do
                if e.side == "LEFT" then left[#left + 1] = i else right[#right + 1] = i end
            end
        end
    end
    if #left == 0 and #right == 0 then return icons end
    local all = {}
    for _, i in ipairs(left) do all[#all + 1] = i end
    for _, i in ipairs(icons) do all[#all + 1] = i end
    for _, i in ipairs(right) do all[#all + 1] = i end
    return all
end

function Window:Refresh()
    local def, f = self.def, self.frame
    local c = def.cfg()
    if not c or not c.shown or (def.active and not def.active()) then f:Hide() return end
    local ok, rows = pcall(def.rows)
    if not ok then rows = {} end
    local size, gap = c.iconSize or 28, c.spacing or 2
    local rowGap, vertical = c.rowGap or 4, c.vertical
    local nameH = c.showNames and ((c.nameSize or 11) + 3) or 0
    -- frame background / border first: the border decides the padding
    local PAD = 4 + Skin(f, c.bgTexture, c.bgColor, c.bgAlpha or 0.4, c.borderTexture, c.borderColor, c.borderSize, c.bgTint)

    -- name column width (horizontal layout: names left of the icons)
    local nameW = 0
    local used = 0
    for i, r in ipairs(rows) do
        local row = self:Row(i)
        MMT.ApplyFont(row.name, c.font, c.nameSize or 11, "OUTLINE")
        Skin(row, c.bgTexture, c.rowColor, c.rowAlpha or 0, nil, nil, nil, c.bgTint)
        row.name:SetText(r.label or lib.MemberName(r.key, c.fullNames))
        if r.color then row.name:SetTextColor(r.color[1], r.color[2], r.color[3])
        else row.name:SetTextColor(ClassColor(r.key)) end
        if c.showNames and not vertical then nameW = math.max(nameW, row.name:GetStringWidth() + 6) end
    end

    local x, y, maxW, maxH = PAD, -PAD, 0, 0
    for i, r in ipairs(rows) do
        local row = self:Row(i)
        local icons = r.key and WithExtras(def.name, r.key, r.icons or {}) or (r.icons or {})
        -- vertical: a column as wide as the name, icons centred in it
        local colW = vertical and math.max(size, c.showNames and (row.name:GetStringWidth() + 2) or 0) or 0
        local colX = vertical and math.floor((colW - size) / 2 + 0.5) or 0
        for j, data in ipairs(icons) do
            local b = row.icons[j] or NewIcon(row)
            row.icons[j] = b
            Setup(b, data, r.key, c)
            b:ClearAllPoints()
            if vertical then
                b:SetPoint("TOPLEFT", colX, -nameH - (j - 1) * (size + gap))
            else
                b:SetPoint("TOPLEFT", nameW + (j - 1) * (size + gap), 0)
            end
        end
        for j = #icons + 1, #row.icons do row.icons[j]:Hide(); row.icons[j].data = nil end
        local n = math.max(1, #icons)
        local w, h
        row.name:ClearAllPoints()
        if vertical then
            w = colW
            h = nameH + n * size + (n - 1) * gap
            row.name:SetPoint("TOP", 0, 0)
        else
            w = nameW + n * size + (n - 1) * gap
            h = size
            row.name:SetPoint("LEFT", 0, 0)
        end
        row.name:SetShown(c.showNames and true or false)
        row:SetSize(w, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", x, y)
        row:EnableMouse(not c.clickThrough)
        row:Show()
        if vertical then
            x = x + w + rowGap
            maxH = math.max(maxH, h)
        else
            y = y - h - rowGap
            maxW = math.max(maxW, w)
        end
        used = i
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end

    if used == 0 then f:Hide() return end
    if vertical then f:SetSize(x - rowGap + PAD, maxH + 2 * PAD)
    else f:SetSize(maxW + 2 * PAD, -y - rowGap + PAD) end
    f:SetScale(c.scale or 1)
    f:EnableMouse(not c.clickThrough)
    -- position only when it changed (profile switch, reset), never while dragging
    local p = c.point
    if p and p ~= self.placed then
        self.placed = p
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    f:Show()
end

function Window:Hide() self.frame:Hide() end

function lib.SetExtra(windowName, id, fn, side)
    lib.extras[windowName] = lib.extras[windowName] or {}
    lib.extras[windowName][id] = fn and { fn = fn, side = side or "RIGHT" } or nil
    local w = lib.windows[windowName]
    if w then w:Refresh() end
end

function lib.Refresh(windowName)
    local w = lib.windows[windowName]
    if w then w:Refresh() end
end
