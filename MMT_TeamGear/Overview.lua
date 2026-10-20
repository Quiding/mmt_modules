-- MMT Team Gear: the whole team at once. One row per member: name in class
-- colour, level and average item level, then every slot as a small icon in
-- the item's quality colour. Hover an icon for its tooltip (Shift-click
-- links it); click a name to open that member's full gear window.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }   -- shirt and tabard left out
local ICON, GAP, ROW_GAP, PAD, NAME_W, TOP = 24, 2, 4, 10, 120, 40
local MAX_ROWS = 20

local QualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local function InsertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

local function NewIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.raw)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.item and IsShiftKeyDown() then pcall(InsertLink, self.item.link) end
    end)
    return b
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(NAME_W + #ORDER * (ICON + GAP), ICON)
    r.name = CreateFrame("Button", nil, r)
    r.name:SetSize(NAME_W - 6, ICON)
    r.name:SetPoint("LEFT")
    r.name.text = r.name:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name.text:SetPoint("TOPLEFT", 0, -1)
    r.name.text:SetWidth(NAME_W - 6)
    r.name.text:SetJustifyH("LEFT")
    r.name.text:SetWordWrap(false)
    r.name.sub = r.name:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name.sub:SetPoint("TOPLEFT", r.name.text, "BOTTOMLEFT", 0, -1)
    r.name.sub:SetTextColor(0.6, 0.6, 0.6)
    r.name:SetScript("OnClick", function(self) if r.key then mod.Open(r.key) end end)
    UI.Tooltip(r.name, "Open", "Click to open this character's gear.")
    r.icons = {}
    for i in ipairs(ORDER) do
        local b = NewIcon(r)
        b:SetPoint("LEFT", NAME_W + (i - 1) * (ICON + GAP), 0)
        r.icons[i] = b
    end
    return r
end

local function Build()
    local f = CreateFrame("Frame", "MMTTeamGearOverview", UIParent)
    f:SetFrameStrata("DIALOG")   -- above the character panel (skins put it on HIGH)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        M.db.overviewPoint = { p, rp, x, y }
    end)
    UI.Fill(f, 0.05, 0.05, 0.06, 0.95)
    UI.Border(f, 0.25, 0.25, 0.25, 1)
    UI.CloseOnEscape(f)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -12)
    f.title:SetText("Team Gear")
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    local close = UI.TextButton(f, "x", function() f:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    f.rows = {}
    f:Hide()   -- new frames start shown: hidden until OpenOverview places it
    return f
end

local function Place(f)
    f:ClearAllPoints()
    local p = M.db.overviewPoint
    if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif CharacterFrame and CharacterFrame:IsShown() then f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 12, 0)
    else f:SetPoint("CENTER", 0, 60) end
end

local function PaintIcon(b, itemString)
    local item = itemString and mod.ItemData(itemString)
    b.item = item
    local r, g, bl = 0.2, 0.2, 0.2
    if item then
        b.icon:SetTexture(item.icon or 134400)
        b.icon:SetAlpha(1)
        if item.quality then
            local qr, qg, qb = MMT.Safe(QualityColor, item.quality)
            if qr then r, g, bl = qr, qg, qb end
        end
    else
        b.icon:SetTexture(nil)
        b.icon:SetAlpha(0)
    end
    b.bg:SetColorTexture(r, g, bl, 1)
end

-- the characters shown: this team (and the other teams when that option is on)
local function Keys()
    local t = mod.AllKeys()
    while #t > MAX_ROWS do table.remove(t) end
    return t
end

function mod.RefreshOverview()
    local f = mod.overview
    if not f or not f:IsShown() then return end
    local keys = Keys()
    for i, key in ipairs(keys) do
        local r = f.rows[i] or NewRow(f)
        f.rows[i] = r
        r.key = key
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD, -TOP - (i - 1) * (ICON + ROW_GAP))
        local class, level = mod.ClassOf(key)
        r.name.text:SetText(MMT.FullDisplay(key))
        r.name.text:SetTextColor(mod.ClassColor(class))
        local rec = mod.Equipment(key)
        local avg = rec and mod.AverageLevel(rec)
        local sub = {}
        if level then sub[#sub + 1] = tostring(level) end
        if avg then sub[#sub + 1] = "ilvl " .. avg end
        if not rec then sub[#sub + 1] = "no gear stored" end
        r.name.sub:SetText(table.concat(sub, "  "))
        for j, slot in ipairs(ORDER) do PaintIcon(r.icons[j], rec and rec.items[slot]) end
        r:Show()
    end
    for i = #keys + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(PAD * 2 + NAME_W + #ORDER * (ICON + GAP), TOP + math.max(1, #keys) * (ICON + ROW_GAP) + PAD)
    if not mod.HasItemCompare() then f.note:SetText("Item Compare is off: nothing new arrives.")
    elseif #keys == 0 then f.note:SetText("No team members yet.")
    else f.note:SetText("Click a name for the full window.") end
end

function mod.OpenOverview()
    mod.overview = mod.overview or Build()
    local f = mod.overview
    f:SetScale(tonumber(M.db.overviewScale) or 1)
    if not f:IsShown() or not f:GetPoint(1) then Place(f) end
    f:Show()
    f:Raise()
    mod.RefreshOverview()
end
