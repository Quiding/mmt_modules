-- MMT Team Gear: the gear window, laid out like the inspect frame: the
-- armor slots down both sides, the weapons at the bottom, the member's 3D
-- model in the middle while they are in your group and in sight.
-- Hover a slot for the item's tooltip; Shift-click links it in chat,
-- Ctrl-click tries it on.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetILvl = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local QualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local SLOT_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
    [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot",
    [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}
local LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }

local W, H = 540, 438
local ICON, GAP, PAD, TOP = 36, 6, 12, 58
local TEXT_W = 150

---------------------------------------------------------------------------
-- Item data
---------------------------------------------------------------------------
-- item string -> link (with name once the client knows the item), quality,
-- item level, icon. Missing data arrives with GET_ITEM_INFO_RECEIVED.
function mod.ItemData(itemString)
    local raw = "item:" .. itemString
    local name, link, quality, _, _, _, _, _, _, icon = MMT.Safe(GetInfo, raw)
    if not icon then icon = select(5, MMT.Safe(GetInstant, raw)) end
    local ilvl = MMT.Safe(GetILvl, link or raw)
    return { raw = raw, name = name, link = link or raw, quality = quality, ilvl = ilvl, icon = icon }
end

-- the enchant's name (armor kits too) from the tooltip data of the whole
-- stored item string: the classic enchant field is often empty on this client
-- while the tooltip still shows the enchant, so every item is looked at. The
-- game tags the line; otherwise the "Enchanted: %s" line. Cached per item
-- string once the item's tooltip has loaded.
local ENCHANT_LINE = Enum and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent or Enum.TooltipDataLineType.ItemEnchant) or 15
local ENCHANTED = type(ENCHANTED_TOOLTIP_LINE) == "string" and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s") or "Enchanted: "
local enchantNames = {}

function mod.EnchantName(itemString)
    if not itemString then return nil end
    local known = enchantNames[itemString]
    if known ~= nil then return known or nil end
    local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    local data = get and MMT.Safe(get, "item:" .. itemString)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = type(line.leftText) == "string" and not MMT.IsSecret(line.leftText) and line.leftText or ""
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local name
        if line.type == ENCHANT_LINE then name = text
        elseif text:sub(1, #ENCHANTED) == ENCHANTED then name = text:sub(#ENCHANTED + 1) end
        if name and name ~= "" then
            name = name:gsub("^Enchant%s+[^-]+%-%s*", "")
            enchantNames[itemString] = name
            return name
        end
    end
    -- no enchant line: remember that only once the tooltip has the item's name
    -- (before that the item data is still on its way)
    if #data.lines > 1 then enchantNames[itemString] = false end
    return nil
end

local function EmptyTexture(slot)
    local _, tex = MMT.Safe(GetInventorySlotInfo, SLOT_NAMES[slot])
    return tex
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
local function InsertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

local function NewSlot(parent, slot, textSide)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.slot = slot
    UI.Fill(b, 0.1, 0.1, 0.1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetHeight(p[4])
        b.border[#b.border + 1] = t
    end
    for _, p in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetWidth(2)
        b.border[#b.border + 1] = t
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetWidth(TEXT_W)
    b.level = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.level:SetTextColor(0.7, 0.7, 0.7)
    b.enchant = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.enchant:SetTextColor(0.3, 1, 0.3)
    b.enchant:SetWordWrap(false)
    if textSide == "RIGHT" then
        b.name:SetPoint("TOPLEFT", b, "TOPRIGHT", 6, -3); b.name:SetJustifyH("LEFT")
        b.level:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
        b.enchant:SetPoint("TOPLEFT", b.level, "BOTTOMLEFT", 0, -1)
        b.enchant:SetWidth(TEXT_W); b.enchant:SetJustifyH("LEFT")
    elseif textSide == "LEFT" then
        b.name:SetPoint("TOPRIGHT", b, "TOPLEFT", -6, -3); b.name:SetJustifyH("RIGHT")
        b.level:SetPoint("TOPRIGHT", b.name, "BOTTOMRIGHT", 0, -2)
        b.enchant:SetPoint("TOPRIGHT", b.level, "BOTTOMRIGHT", 0, -1)
        b.enchant:SetWidth(TEXT_W); b.enchant:SetJustifyH("RIGHT")
    else
        b.name:SetWidth(ICON + 40)
        b.name:SetPoint("TOP", b, "BOTTOM", 0, -3); b.name:SetJustifyH("CENTER")
        b.level:SetPoint("TOP", b.name, "BOTTOM", 0, -1)
        b.enchant:SetPoint("TOP", b.level, "BOTTOM", 0, -1)
        b.enchant:SetWidth(ICON + 60); b.enchant:SetJustifyH("CENTER")
    end
    b.name:SetWordWrap(false)

    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.raw)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not self.item then return end
        if IsShiftKeyDown() then pcall(InsertLink, self.item.link)
        elseif IsControlKeyDown() and DressUpItemLink then pcall(DressUpItemLink, self.item.link) end
    end)
    return b
end

local function PaintSlot(b, itemString)
    local item = itemString and mod.ItemData(itemString)
    b.item = item
    local r, g, bl = 0.25, 0.25, 0.25
    if item then
        b.icon:SetTexture(item.icon or 134400)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(1)
        if item.quality then
            local qr, qg, qb = MMT.Safe(QualityColor, item.quality)
            if qr then r, g, bl = qr, qg, qb end
        end
        b.name:SetText(M.db.names and (item.name or "...") or "")
        b.name:SetTextColor(r, g, bl)
        b.level:SetText((M.db.names and item.ilvl) and ("Item level " .. item.ilvl) or "")
        b.enchant:SetText(M.db.names and mod.EnchantName(itemString) or "")
    else
        b.icon:SetTexture(EmptyTexture(b.slot) or 136525)
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(0.5)
        b.name:SetText("")
        b.level:SetText("")
        b.enchant:SetText("")
    end
    for _, t in ipairs(b.border) do t:SetColorTexture(r, g, bl, 1) end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SavePoint(f)
    local p, _, rp, x, y = f:GetPoint(1)
    M.db.windowPoint = { p, rp, x, y }
end

local function Build()
    local f = CreateFrame("Frame", "MMTTeamGearWindow", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")   -- above the character panel (skins put it on HIGH)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint(self) end)
    UI.Fill(f, 0.05, 0.05, 0.06, 0.95)
    UI.Border(f, 0.25, 0.25, 0.25, 1)
    UI.CloseOnEscape(f)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    f.sub:SetTextColor(0.75, 0.75, 0.75)

    local close = UI.TextButton(f, "x", function() f:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    local prev = UI.TextButton(f, "<", function() mod.Step(-1) end, 22)
    prev:SetPoint("TOPLEFT", 8, -12)
    UI.Tooltip(prev, "Previous member")
    local nxt = UI.TextButton(f, ">", function() mod.Step(1) end, 22)
    nxt:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    UI.Tooltip(nxt, "Next member")
    local list = UI.TextButton(f, "List", function(self) mod.OpenMemberList(self) end, 34)
    list:SetPoint("LEFT", nxt, "RIGHT", 4, 0)
    UI.Tooltip(list, "List", "Choose a team member.")
    local all = UI.TextButton(f, "Team", function() mod.OpenOverview() end, 40)
    all:SetPoint("LEFT", list, "RIGHT", 2, 0)
    UI.Tooltip(all, "Whole team", "Everyone's gear at once, one row per member.")

    f.model = CreateFrame("DressUpModel", nil, f)
    f.model:SetPoint("TOPLEFT", PAD + ICON + TEXT_W + 8, -TOP)
    f.model:SetPoint("BOTTOMRIGHT", -(PAD + ICON + TEXT_W + 8), PAD + ICON + 40)

    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("CENTER", f.model, "CENTER")
    f.note:SetWidth(W - 2 * (PAD + ICON + TEXT_W + 8))
    f.lookNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.lookNote:SetPoint("BOTTOM", f.model, "BOTTOM", 0, 2)
    f.lookNote:SetText("")
    -- the model loads a moment after SetCustomRace: dress it once it's there
    f.model:SetScript("OnModelLoaded", function(self) if self.dress then self.dress() end end)   -- kept until the next Refresh

    f.slots = {}
    for i, slot in ipairs(LEFT) do
        local b = NewSlot(f, slot, "RIGHT")
        b:SetPoint("TOPLEFT", PAD, -TOP - (i - 1) * (ICON + GAP))
        f.slots[slot] = b
    end
    for i, slot in ipairs(RIGHT) do
        local b = NewSlot(f, slot, "LEFT")
        b:SetPoint("TOPRIGHT", -PAD, -TOP - (i - 1) * (ICON + GAP))
        f.slots[slot] = b
    end
    local bw = #BOTTOM * ICON + (#BOTTOM - 1) * 50
    for i, slot in ipairs(BOTTOM) do
        local b = NewSlot(f, slot, "BOTTOM")
        b:SetPoint("BOTTOMLEFT", (W - bw) / 2 + (i - 1) * (ICON + 50), PAD + 26)
        f.slots[slot] = b
    end

    f:SetScript("OnHide", function() if f.model.ClearModel then f.model:ClearModel() end end)
    f:Hide()   -- new frames start shown: hidden until Open places it
    return f
end

local function Place(f)
    f:ClearAllPoints()
    local p = M.db.windowPoint
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif CharacterFrame and CharacterFrame:IsShown() then
        f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 12, 0)
    else
        f:SetPoint("CENTER", 0, 40)
    end
end

-- average item level of the stored items (shirt and tabard left out)
function mod.AverageLevel(rec)
    local sum, n = 0, 0
    for slot, s in pairs(rec.items) do
        if slot ~= 4 and slot ~= 19 then
            local d = mod.ItemData(s)
            if d.ilvl then sum, n = sum + d.ilvl, n + 1 end
        end
    end
    return n > 0 and math.floor(sum / n + 0.5) or nil
end

function mod.Refresh()
    local f = mod.window
    if not f or not f.key then return end
    local key = f.key
    local class, level = mod.ClassOf(key)
    f.title:SetText(MMT.FullDisplay(key))
    f.title:SetTextColor(mod.ClassColor(class))
    local rec = mod.Equipment(key)
    local parts = {}
    if level then parts[#parts + 1] = "Level " .. level end
    if class then parts[#parts + 1] = mod.ClassName(class) end
    if rec then
        local avg = mod.AverageLevel(rec)
        if avg then parts[#parts + 1] = "item level " .. avg end
        -- Item Compare stores a new copy only when the gear changes: the time is the last change
        if rec.time then parts[#parts + 1] = "gear changed " .. MMT.Ago(rec.time) end
    end
    f.sub:SetText(table.concat(parts, "  -  "))
    for slot, b in pairs(f.slots) do PaintSlot(b, rec and rec.items[slot]) end

    local unit = mod.UnitOf(key)
    local look = mod.LookOf(key)
    f.model.dress = nil
    f.lookNote:Hide()
    mod.modelInfo = "none"
    local inSight = unit and UnitIsVisible(unit)
    local kind = not inSight and rec and mod.Mannequin(f.model, look, rec)
    if inSight then
        mod.RememberUnit(key, unit)
        f.model:Show()
        f.model:SetUnit(unit)
        mod.modelInfo = "unit=" .. unit
        f.note:SetText("")
    elseif kind then
        f.lookNote:SetText(kind == "race" and "Not in sight: their race in their gear" or "Not in sight: your character in their gear")
        f.lookNote:Show()
        f.note:SetText("")
    else
        f.model:Hide()
        if not mod.HasItemCompare() then f.note:SetText("Switch on Item Compare (/mmt > MODULES): it collects the team's gear.")
        elseif not rec then f.note:SetText("No gear stored for this character yet. It arrives when they are online with MMT and Item Compare.")
        else f.note:SetText("") end
    end
end

-- the stored gear on a model: like AtlasLoot, start from your own character
-- (SetUnit("player") gives the model a body), switch it to their race and
-- gender when the client allows, then undress it and put their items on.
-- Returns "race" (their race and gender) or "own" (your body), false if no model.
function mod.Mannequin(model, look, rec)
    model:Show()
    if not pcall(model.SetUnit, model, "player") then model:Hide() return false end
    local kind = "own"
    -- SetCustomRace takes 0 = male, 1 = female
    if look and model.SetCustomRace and pcall(model.SetCustomRace, model, look.race, look.sex - 2) then kind = "race" end
    mod.modelInfo = ("mannequin=%s customRace=%s look=%s"):format(kind, tostring(model.SetCustomRace ~= nil),
        look and (look.race .. "." .. look.sex) or "none")
    -- the model loads in steps (your body, then the race switch reloads it),
    -- and each load starts from scratch: dress it after every load and a few
    -- times shortly after, as long as this mannequin is still the one shown
    local function Dress()
        if model.Undress then pcall(model.Undress, model) end
        for _, item in pairs(rec.items) do pcall(model.TryOn, model, "item:" .. item) end
    end
    model.dress = Dress
    Dress()
    for _, t in ipairs({ 0.1, 0.4, 1 }) do
        C_Timer.After(t, function() if model.dress == Dress then Dress() end end)
    end
    return kind
end

function mod.Open(key)
    mod.window = mod.window or Build()
    local f = mod.window
    f:SetScale(tonumber(M.db.windowScale) or 1)
    if not f:IsShown() or not f:GetPoint(1) then Place(f) end
    f.key = key
    -- shown first: a model set up while its frame is hidden stays empty
    f:Show()
    f:Raise()
    mod.Refresh()
end

-- the next / previous character in the list
function mod.Step(dir)
    local f = mod.window
    local list = mod.AllKeys()
    if not f or #list == 0 then return end
    local at = 0
    for i, key in ipairs(list) do if key == f.key then at = i end end
    local i = ((at - 1 + dir) % #list) + 1
    mod.Open(list[i])
end

-- item data the client didn't know yet came in: redraw once
local pending
M:On("GET_ITEM_INFO_RECEIVED", function()
    if pending or not ((mod.window and mod.window:IsShown()) or (mod.overview and mod.overview:IsShown())) then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        if mod.window and mod.window:IsShown() then mod.Refresh() end
        mod.RefreshOverview()
    end)
end)
