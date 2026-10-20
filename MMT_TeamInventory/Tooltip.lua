-- MMT Team Inventory: the lines in the item tooltip.
--
--   Team inventory                      Total: 34
--     Quiding Ala          bags 4, bank 8
--     Quiding Alasha       mail 22
--
-- Syndicator (Baganator) lists the characters of the account you're on in
-- its own lines. With it shown ("withSyndicator"):
--   OTHERS  only characters of your other accounts, the total counts all
--   ALL     every team character anyway
--   OFF     nothing from us
-- Our post-call is registered after Syndicator's (OptionalDeps), so the
-- lines come right below its block.

local _, mod = ...
local MMT = MMT
local M = mod.M

local WHITE, BLUE = "|cffffffff", "|cff82c5ff"

-- class: stored with the counts (sent along), else MMT's status / team list
local function ClassOf(key)
    local rec = mod.Chars()[key]
    if rec and rec.class then return rec.class end
    if MMT.IsSelf(key) then return (select(2, UnitClass("player"))) end
    local s = MMT.status and MMT.status[key]
    if s and s.class then return s.class end
    local m = MMT.db and MMT.db.team and MMT.db.team[key]
    return m and m.class
end
mod.ClassOf = ClassOf

local function ClassColored(key)
    local class = ClassOf(key)
    local name = MMT.FullDisplay(key)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local function B(v) return math.floor(v * 255 + 0.5) end
    if c then return ("|cff%02x%02x%02x%s|r"):format(B(c.r), B(c.g), B(c.b), name) end
    return name
end

local function Parts(parts)
    local t = {}
    for _, p in ipairs(mod.PLACES) do
        if parts[p] then t[#t + 1] = mod.PLACE_NAMES[p] .. " " .. WHITE .. parts[p] .. "|r" .. BLUE end
    end
    return BLUE .. table.concat(t, ", ") .. "|r"
end

-- the lines for itemID: { {left, right}, ... } and the total (nil when nobody has it)
function mod.TooltipLines(itemID)
    local syn = mod.HasSyndicator() and M.db.withSyndicator or nil
    if syn == "OFF" then return nil end
    local mine = mod.Mine()
    local rows, total, shownTotal = {}, 0, 0
    for key in pairs(mod.Chars()) do
        local n, parts = mod.CountOf(key, itemID)
        if n > 0 then
            total = total + n
            if not (syn == "OTHERS" and mine[key]) then
                rows[#rows + 1] = { key = key, n = n, parts = parts }
                shownTotal = shownTotal + n
            end
        end
    end
    if total == 0 or #rows == 0 then return nil end
    table.sort(rows, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.key < b.key
    end)
    local lines = {}
    for i, r in ipairs(rows) do
        if i > (M.db.limit or 10) then lines[#lines + 1] = { "  ...", "" } break end
        lines[#lines + 1] = { "  " .. ClassColored(r.key), Parts(r.parts) }
    end
    local title = syn == "OTHERS" and "Team (other accounts)" or "Team inventory"
    table.insert(lines, 1, { title, BLUE .. "Total: " .. WHITE .. total .. "|r" })
    return lines, total
end

local function ItemID(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(link) ~= "string" or not fn then return nil end
    return (MMT.Safe(fn, link))
end

local function Add(tip, link)
    if not (M.enabled and M.db.tooltip) or (M.db.onlyShift and not IsShiftKeyDown()) then return end
    local id = ItemID(link)
    local lines = id and mod.TooltipLines(id)
    if not lines then return end
    for _, l in ipairs(lines) do tip:AddDoubleLine(l[1], l[2], 1, 0.82, 0, 1, 1, 1) end
    tip:Show()
end
mod.AddToTooltip = Add

local function Valid(tip)
    return tip == GameTooltip or tip == ItemRefTooltip
end

-- installed once at login (after Syndicator / Baganator registered theirs);
-- Add() checks M.enabled, so switching the module off needs no unhooking
local function Install()
    if mod.tooltipHooked then return end
    mod.tooltipHooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
            if not Valid(tip) then return end
            local link
            if TooltipUtil and TooltipUtil.GetDisplayedItem then link = select(2, TooltipUtil.GetDisplayedItem(tip)) end
            if not link and tip.GetItem then link = select(2, tip:GetItem()) end
            Add(tip, link)
        end)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tip:HookScript("OnTooltipSetItem", function(self) Add(self, select(2, self:GetItem())) end)
        end
    end
end
mod.InstallTooltip = Install

if IsLoggedIn and IsLoggedIn() then
    Install()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents() Install() end)
end
