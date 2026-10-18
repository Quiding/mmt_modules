-- MMT Totems: the bars.
--
-- One bar per shaman: name, [P preset button], Fire / Air / Water / Earth,
-- and on YOUR bar the sequence button. Grouped (one movable frame) or
-- ungrouped (each bar moves on its own). Your slot buttons and the sequence
-- button are secure action buttons (they cast), so the layout can only
-- change out of combat; icons and timers update in combat too.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local PAD = 4
local bars = {}          -- [teamKey] = bar
mod.bars = bars
local pendingLayout = false

local container = CreateFrame("Frame", "MMTTotemsFrame", UIParent)
container:SetFrameStrata("MEDIUM")
container:SetClampedToScreen(true)
container:SetMovable(true)
container.bg = container:CreateTexture(nil, "BACKGROUND")
container.bg:SetAllPoints()
container:Hide()
mod.container = container

local function Font(fs, size)
    MMT.ApplyFont(fs, nil, size, "OUTLINE")
end

local function FormatTime(t)
    if t >= 60 then return ("%dm"):format(math.floor(t / 60 + 0.5)) end
    return tostring(math.floor(t + 0.5))
end

---------------------------------------------------------------------------
-- Drag grips (hidden while locked)
---------------------------------------------------------------------------
local function Grip(parent, target, onStop)
    local g = CreateFrame("Frame", nil, parent)
    g:SetWidth(8)
    UI.Fill(g, 0.25, 0.25, 0.25, 0.9)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnDragStart", function() if not M.db.locked and not InCombatLockdown() then target:StartMoving() end end)
    g:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        local point, _, relPoint, x, y = target:GetPoint()
        onStop({ point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) })
    end)
    g:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Drag to move")
        GameTooltip:AddLine("Lock the bars in /mmt > MODULES > Totems.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return g
end

container.grip = Grip(container, container, function(p) M.db.point = p end)
container.grip:SetPoint("TOPRIGHT", container, "TOPLEFT", 0, 0)
container.grip:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", 0, 0)

---------------------------------------------------------------------------
-- Small text buttons (P / TP)
---------------------------------------------------------------------------
local function TextButton(parent, text, r, g, b)
    local btn = CreateFrame("Button", nil, parent)
    UI.Fill(btn, 0, 0, 0, 0.85)
    UI.Border(btn, 0.35, 0.35, 0.35, 1)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    btn.text:SetTextColor(r, g, b)
    return btn
end

local teamBtn = TextButton(container, "TP", 1, 0.8, 0)
teamBtn:SetScript("OnClick", function(self) mod.OpenPresetMenu(self, nil) end)
teamBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Team presets")
    GameTooltip:AddLine("Click: apply a team preset. Manage them in /mmt > MODULES > Totems.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
teamBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
do  -- only while the mouse is over it or its frame / bar
    local t = 0
    teamBtn:SetScript("OnUpdate", function(self, e)
        t = t + e
        if t < 0.1 then return end
        t = 0
        if M.db and M.db.presetsOnHover then
            local parent = self:GetParent()
            self:SetAlpha((self:IsMouseOver() or (parent and parent:IsMouseOver(4, -4, -12, 4))) and 1 or 0)
        end
    end)
end
teamBtn:Hide()

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function SlotTooltip(self)
    local key, element = self.key, self.element
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local name = mod.ActiveTotem(key, element) or mod.TotemName(mod.Selected(key, element)) or mod.LastTotem(key, element) or "none"
    GameTooltip:SetText(("%s - %s"):format(MMT.FirstName(key), element))
    GameTooltip:AddLine(name, 1, 1, 1)
    if not M.db.onlyTimers then
        if MMT.IsSelf(key) then GameTooltip:AddLine("Left-click: cast", 1, 0.8, 0) end
        GameTooltip:AddLine("Right-click: choose the totem", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function NewSlot(bar, key, element, secure)
    local s = CreateFrame("Button", nil, bar, secure and "SecureActionButtonTemplate" or nil)
    s.key, s.element = key, element
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
    s.cd:SetAllPoints()
    if s.cd.SetHideCountdownNumbers then s.cd:SetHideCountdownNumbers(true) end
    if s.cd.SetDrawEdge then s.cd:SetDrawEdge(false) end
    s.cd:EnableMouse(false)
    local over = CreateFrame("Frame", nil, s)
    over:SetAllPoints()
    over:SetFrameLevel(s.cd:GetFrameLevel() + 2)
    s.timer = over:CreateFontString(nil, "OVERLAY")
    s.timer:SetPoint("CENTER")
    s:RegisterForClicks("AnyUp", "AnyDown")
    s:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down and not M.db.onlyTimers then mod.OpenTotemMenu(self, key, element) end
    end)
    s:SetScript("OnEnter", SlotTooltip)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return s
end

local function NewBar(key)
    local own = MMT.IsSelf(key)
    local bar = CreateFrame("Frame", nil, container)
    bar.key = key
    bar:SetClampedToScreen(true)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.name = bar:CreateFontString(nil, "OVERLAY")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.grip = Grip(bar, bar, function(p) M.db.barPoints[key] = p end)
    bar.grip:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
    bar.grip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
    bar.preset = TextButton(bar, "P", 1, 1, 1)
    bar.preset:SetScript("OnClick", function(self) mod.OpenPresetMenu(self, key) end)
    bar.preset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Presets - " .. MMT.FirstName(key))
        GameTooltip:Show()
    end)
    bar.preset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.slots = {}
    for _, element in ipairs(mod.ELEMENTS) do bar.slots[element] = NewSlot(bar, key, element, own) end
    -- presets only while the mouse is over the bar
    local t = 0
    bar:SetScript("OnUpdate", function(self, e)
        t = t + e
        if t < 0.1 then return end
        t = 0
        local c = M.db
        if c.presetsOnHover and c.showPresets then
            self.preset:SetAlpha(self:IsMouseOver(4, -4, -12, 4) and 1 or 0)
        end
    end)
    bars[key] = bar
    return bar
end

-- layout of one bar (out of combat): returns width, height
local function LayoutBar(bar)
    local c = M.db
    local size, gap = c.iconSize, c.spacing
    local own = MMT.IsSelf(bar.key)
    local seqBtn = mod.sequenceButton
    local hasSeq = own and not c.onlyTimers
    local hasPreset = c.showPresets and c.showBarPresets
    local items = {}
    if hasPreset and c.presetSide == "START" then items[#items + 1] = bar.preset end
    for _, element in ipairs(mod.ELEMENTS) do items[#items + 1] = bar.slots[element] end
    if hasSeq then items[#items + 1] = seqBtn end
    if hasPreset and c.presetSide ~= "START" then items[#items + 1] = bar.preset end
    bar.preset:SetShown(hasPreset)
    bar.preset:SetAlpha((hasPreset and not c.presetsOnHover) and 1 or 0)
    Font(bar.preset.text, math.floor(size * 0.55))

    Font(bar.name, c.nameSize)
    bar.name:SetText(c.fullNames and MMT.FullDisplay(bar.key) or MMT.FirstName(bar.key))
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.SHAMAN
    if cc then bar.name:SetTextColor(cc.r, cc.g, cc.b) end
    bar.name:SetShown(c.showNames)
    local nameH = c.showNames and (c.nameSize + 3) or 0

    for i, item in ipairs(items) do
        if item == seqBtn then seqBtn:SetParent(bar) end
        item:SetSize(size, size)
        item:ClearAllPoints()
        if c.vertical then item:SetPoint("TOPLEFT", 0, -nameH - (i - 1) * (size + gap))
        else item:SetPoint("TOPLEFT", (i - 1) * (size + gap), -nameH) end
        item:Show()
    end
    for _, s in pairs(bar.slots) do Font(s.timer, c.timerSize) end
    bar.name:ClearAllPoints()
    bar.name:SetPoint("TOPLEFT", 0, 0)
    local n = #items
    local w, h
    if c.vertical then
        w = math.max(size, c.showNames and (bar.name:GetStringWidth() + 2) or 0)
        h = nameH + n * size + (n - 1) * gap
    else
        w = math.max(n * size + (n - 1) * gap, c.showNames and (bar.name:GetStringWidth() + 2) or 0)
        h = nameH + size
    end
    bar:SetSize(w, h)
    return w, h
end

-- whole layout (out of combat only)
function mod.Refresh()
    if InCombatLockdown() then pendingLayout = true; mod.UpdateIcons() return end
    pendingLayout = false
    local c = M.db
    local seqBtn = mod.sequenceButton
    if not (M.enabled and c and c.shown) then
        container:Hide()
        for _, bar in pairs(bars) do bar:Hide() end
        if seqBtn then seqBtn:SetParent(UIParent); seqBtn:Hide() end
        teamBtn:Hide()
        return
    end
    local keys = mod.Shamans()
    local show = {}
    for _, key in ipairs(keys) do show[key] = true end
    for key, bar in pairs(bars) do if not show[key] then bar:Hide() end end
    if seqBtn and not show[mod.OwnKey()] then seqBtn:SetParent(UIParent); seqBtn:Hide() end

    local x, y, maxW, maxH = PAD, -PAD, 0, 0
    for _, key in ipairs(keys) do
        local bar = bars[key] or NewBar(key)
        local w, h = LayoutBar(bar)
        bar.bg:SetColorTexture(0, 0, 0, c.ungrouped and c.bgAlpha or 0)
        bar.grip:SetShown(c.ungrouped and not c.locked)
        bar:ClearAllPoints()
        if c.ungrouped then
            bar:SetParent(UIParent)
            bar:SetMovable(true)
            bar:SetScale(c.scale)
            bar:SetAlpha(c.alpha)
            bar:SetFrameStrata("MEDIUM")
            local p = c.barPoints[key]
            if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
            else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150 - y) end
            y = y - h - c.rowGap
        else
            bar:SetParent(container)
            bar:SetMovable(false)
            bar:SetScale(1)
            bar:SetAlpha(1)
            bar:SetPoint("TOPLEFT", x, y)
            if c.vertical then x = x + w + c.rowGap; maxH = math.max(maxH, h)
            else y = y - h - c.rowGap; maxW = math.max(maxW, w) end
        end
        bar:Show()
    end

    if c.ungrouped or #keys == 0 then
        container:Hide()
    else
        if c.vertical then container:SetSize(x - c.rowGap + PAD, maxH + 2 * PAD)
        else container:SetSize(maxW + 2 * PAD, -y - c.rowGap + PAD) end
        container:SetScale(c.scale)
        container:SetAlpha(c.alpha)
        container.bg:SetColorTexture(0, 0, 0, c.bgAlpha)
        container.grip:SetShown(not c.locked)
        local p = c.point
        if p ~= container.placed then
            container.placed = p
            container:ClearAllPoints()
            container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        container:Show()
    end

    -- team preset button: on the frame, or on the first bar when ungrouped
    if c.showPresets and c.showTeamPreset and #keys > 0 then
        local size = math.max(16, math.floor(c.iconSize * 0.8))
        teamBtn:SetSize(size, size)
        Font(teamBtn.text, math.floor(size * 0.5))
        teamBtn:ClearAllPoints()
        if c.ungrouped then
            local first = bars[keys[1]]
            teamBtn:SetParent(first)
            if c.vertical then teamBtn:SetPoint("BOTTOM", first, "TOP", 0, 2)
            else teamBtn:SetPoint("RIGHT", first, "LEFT", -10, 0) end
        else
            teamBtn:SetParent(container)
            teamBtn:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", -10, 0)
        end
        teamBtn:SetAlpha(c.presetsOnHover and 0 or 1)
        teamBtn:Show()
    else
        teamBtn:Hide()
    end
    mod.UpdateIcons()
    mod.UpdateSecure()
end

M:On("PLAYER_REGEN_ENABLED", function() if pendingLayout then mod.Refresh() end end)
M:Listen("TEAM_CHANGED", function() mod.Refresh() end)
M:Listen("STATUS_CHANGED", function()
    -- shamans coming online / going offline
    local now = table.concat(mod.Shamans(), ",")
    if now ~= mod.lastShamans then mod.lastShamans = now; mod.Refresh() end
end)
M:On("GROUP_ROSTER_UPDATE", function() mod.Refresh() end)

---------------------------------------------------------------------------
-- Icons and timers (any time, also in combat)
---------------------------------------------------------------------------
function mod.UpdateIcons()
    local c = M.db
    if not (M.enabled and c) then return end
    local now = GetTime()
    for key, bar in pairs(bars) do
        if bar:IsShown() then
            for element, s in pairs(bar.slots) do
                local name, icon, start, dur = mod.ActiveTotem(key, element)
                if name then
                    s.icon:SetTexture(icon or mod.PRESET_ICON)
                    s.icon:SetAlpha(1)
                    if s.cdStart ~= start then s.cdStart = start; s.cd:SetCooldown(start, dur) end
                    s.cd:Show()
                    if c.showTimers then
                        local col = c.timerColor
                        s.timer:SetText(FormatTime(start + dur - now))
                        s.timer:SetTextColor(col.r or 1, col.g or 1, col.b or 1)
                        s.timer:Show()
                    else
                        s.timer:Hide()
                    end
                else
                    local _, lastIcon = mod.LastTotem(key, element)
                    s.icon:SetTexture(mod.TotemIcon(mod.Selected(key, element)) or lastIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    s.icon:SetAlpha(c.inactiveAlpha)
                    s.cdStart = nil
                    s.cd:Hide()
                    s.timer:Hide()
                end
            end
        end
    end
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < 0.1 then return end
    acc = 0
    if M.enabled then mod.UpdateIcons() end
end)

---------------------------------------------------------------------------
-- Menus: choose a totem / apply a preset
---------------------------------------------------------------------------
local function IconText(icon, text)
    return ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(tostring(icon or mod.PRESET_ICON), text)
end

function mod.OpenTotemMenu(owner, key, element)
    local items = { { value = 0, text = "None" } }
    for _, id in ipairs(mod.ElementTotems(element)) do
        items[#items + 1] = { value = id, text = IconText(mod.TotemIcon(id), mod.TotemName(id)) }
    end
    UI.OpenList(owner, items, mod.Selected(key, element) or 0, function(id)
        mod.SetSelected(key, element, id)
    end)
end

-- key = a shaman (individual presets) or nil (team presets)
function mod.OpenPresetMenu(owner, key)
    local items = {}
    local source = key and (M.db.presets[key] or {}) or M.db.teamPresets
    local names = {}
    for name in pairs(source) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        items[#items + 1] = { value = name, text = IconText(source[name].icon, name) }
    end
    if #items == 0 then
        MMT.Print("Totems: no %s yet. Make them with /mmtt presets.", key and ("presets for " .. MMT.FirstName(key)) or "team presets")
        return
    end
    UI.OpenList(owner, items, nil, function(name)
        if key then mod.ApplyPreset(key, name) else mod.ApplyTeamPreset(name) end
    end)
end
