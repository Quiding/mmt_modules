-- MMT Bug Fixes: Item Compare tooltips overlapping the "Equipped" tooltips.
--
-- Item Compare anchors its first team tooltip (MMTCompareTip1) directly at
-- the side of GameTooltip. The game's own comparison tooltips
-- (ShoppingTooltip1/2, the "Equipped" ones shown with Shift or auto-compare)
-- sit on that same side, so both end up on top of each other.
--
-- Fix: after Item Compare has laid out its tooltips, move MMTCompareTip1 (the
-- others are chained to it) past the outer edge of the comparison tooltips on
-- that side. If that would run off the screen, put them below the comparison
-- tooltips instead. Nothing in Item Compare is changed.

local _, mod = ...
local MMT = MMT
local M = mod.M

local PREFIX = "MMTCompareTip"
local GAP, HEADER = 6, 20   -- Item Compare's spacing and room for its name header

-- Item Compare 1.0.2 has this fix itself (patch merged upstream): then we do nothing
local function Version(addon)
    local v = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addon, "Version") or "0"
    local a, b, c = v:match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end
local UPSTREAM = Version("MMT_ItemCompare") >= 10002

mod.fixes[#mod.fixes + 1] = {
    key = "compareOverlap",
    title = "Item Compare: don't cover the \"Equipped\" tooltips",
    note = UPSTREAM and "Not needed any more: your Item Compare has this fix itself, so this does nothing."
        or "Moves Item Compare's team tooltips next to (or below) the game's comparison tooltips instead of on top of them.",
    report = function()
        return UPSTREAM and "not needed (Item Compare has it)" or ("moved=" .. tostring(mod.overlapMoves or 0))
    end,
}

local function Shops()
    local list = {}
    for _, s in ipairs({ ShoppingTooltip1, ShoppingTooltip2 }) do
        if s and s:IsShown() and s:GetLeft() and not (s.IsForbidden and s:IsForbidden()) then list[#list + 1] = s end
    end
    return list
end

-- visible Item Compare tooltips
local function Tips()
    local list = {}
    for i = 1, 40 do
        local t = _G[PREFIX .. i]
        if not t then break end
        if t:IsShown() then list[#list + 1] = t end
    end
    return list
end

local function Fix()
    if UPSTREAM or not (M.enabled and M.db.compareOverlap) then return end
    local gt = GameTooltip
    local t1 = _G[PREFIX .. "1"]
    if not (t1 and t1:IsShown() and gt and gt:IsShown() and gt:GetLeft()) then return end

    -- Item Compare uses TOPRIGHT for the left side, TOPLEFT for the right side
    local point = t1:GetPoint(1)
    local left = point == "TOPRIGHT"
    local gs, ts = gt:GetEffectiveScale(), t1:GetEffectiveScale()
    local gl, gr, gtop = gt:GetLeft() * gs, gt:GetRight() * gs, gt:GetTop() * gs

    -- outer edge and bottom of the comparison tooltips on our side (screen pixels)
    local edge, bottom
    for _, s in ipairs(Shops()) do
        local ss = s:GetEffectiveScale()
        local sl, sr, sb = s:GetLeft() * ss, s:GetRight() * ss, s:GetBottom() * ss
        if left and sr <= gl + 4 then
            edge, bottom = math.min(edge or sl, sl), math.min(bottom or sb, sb)
        elseif not left and sl >= gr - 4 then
            edge, bottom = math.max(edge or sr, sr), math.min(bottom or sb, sb)
        end
    end

    t1:ClearAllPoints()
    if not edge then
        -- nothing in the way: Item Compare's own position
        if left then t1:SetPoint("TOPRIGHT", gt, "TOPLEFT", -GAP, -HEADER)
        else t1:SetPoint("TOPLEFT", gt, "TOPRIGHT", GAP, -HEADER) end
        return
    end

    if left then t1:SetPoint("TOPRIGHT", gt, "TOPLEFT", (edge - gl) / ts - GAP, -HEADER)
    else t1:SetPoint("TOPLEFT", gt, "TOPRIGHT", (edge - gr) / ts + GAP, -HEADER) end

    -- off screen? then below the comparison tooltips, next to GameTooltip
    local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale()
    local off = false
    for _, t in ipairs(Tips()) do
        local es = t:GetEffectiveScale()
        local l, r = t:GetLeft(), t:GetRight()
        if l and ((l * es) < 0 or (r * es) > screenW) then off = true break end
    end
    if off then
        local y = (bottom - gtop) / ts - HEADER - GAP
        t1:ClearAllPoints()
        if left then t1:SetPoint("TOPRIGHT", gt, "TOPLEFT", -GAP, y)
        else t1:SetPoint("TOPLEFT", gt, "TOPRIGHT", GAP, y) end
    end
    mod.overlapMoves = (mod.overlapMoves or 0) + 1
end

-- run after Item Compare's layout and after the game (and other addons, e.g.
-- FojjiCore) have placed the comparison tooltips, which can be a frame later
local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        local ok, err = pcall(Fix)
        if not ok then M:Debug("compareOverlap: %s", tostring(err)) end
        C_Timer.After(0.05, function() pcall(Fix) end)
    end)
end

local hooked = {}
local function Hook(frame)
    if frame and not hooked[frame] and frame.HookScript then
        hooked[frame] = true
        frame:HookScript("OnShow", Queue)
        frame:HookScript("OnHide", Queue)
    end
end

for i = 1, 40 do Hook(_G[PREFIX .. i]) end
hooksecurefunc("CreateFrame", function(_, name)
    if type(name) == "string" and name:find("^" .. PREFIX .. "%d+$") then Hook(_G[name]) end
end)
Hook(ShoppingTooltip1)
Hook(ShoppingTooltip2)
