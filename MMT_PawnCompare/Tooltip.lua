-- MMT Pawn Compare: Pawn lines in Item Compare's tooltips.
--
-- Item Compare shows one tooltip per team member (frames MMTCompareTip1..n)
-- with the item that member has equipped, and a header with the member's
-- name. We don't touch Item Compare's code: we hook those frames when they
-- are created and, every time one is shown, add the hovered item's Pawn
-- score for that member's scales compared against the equipped item.

local _, mod = ...
local MMT = MMT
local M = mod.M

local PREFIX = "MMTCompareTip"
local OFFHAND_ONLY = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local function HoveredLink()
    if not (GameTooltip and GameTooltip:IsShown()) then return nil end
    local link
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, l = pcall(TooltipUtil.GetDisplayedItem, GameTooltip)
        if ok then link = l end
    end
    if not link and GameTooltip.GetItem then
        local ok, _, l = pcall(GameTooltip.GetItem, GameTooltip)
        if ok then link = l end
    end
    if type(link) ~= "string" or (MMT.IsSecret and MMT.IsSecret(link)) then return nil end
    return link
end

local function EquipLoc(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return fn and select(4, fn(link)) or nil
end

-- header text is "<name>" or "<name>  <slot · age>", the name maybe class coloured
local function MemberOf(tip)
    local text = tip.header and tip.header.text and tip.header.text:GetText()
    if not text then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local name = text:match("^(.-)  ") or text
    for _, key in ipairs(MMT.SortedMembers()) do
        if MMT.FirstName(key) == name then return key end
    end
end

local function Fmt(v)
    return ("%.1f"):format(v)
end

local function AddLines(tip, key, hovered, equipped)
    local rec = mod.ScalesOf(key)
    local name = MMT.FirstName(key)
    if not rec or #rec.scales == 0 then
        if rec and rec.noPawn then
            tip:AddLine("Pawn: not installed on " .. name, 0.6, 0.6, 0.6)
        else
            tip:AddLine("Pawn: no scales from " .. name .. " yet", 0.6, 0.6, 0.6)
        end
        return
    end

    local newStats, exact = mod.ItemStats(hovered)
    if not newStats then tip:AddLine("Pawn: loading item...", 0.6, 0.6, 0.6) return end
    local oldStats = equipped and mod.ItemStats(equipped)
    if equipped and not oldStats then tip:AddLine("Pawn: loading item...", 0.6, 0.6, 0.6) return end

    -- score of the HOVERED item with this member's scales, against the item shown in this tip
    tip:AddLine(" ")
    tip:AddLine(("Pawn: hovered item for %s%s"):format(name, exact and "" or " (approx., no Pawn here)"), 0.6, 0.6, 0.6)
    tip:AddLine(oldStats and "  equipped -> hovered" or "  nothing equipped -> hovered", 0.5, 0.5, 0.5)
    local cfg = M.db
    for i, scale in ipairs(rec.scales) do
        if i > 1 and not cfg.allScales then break end
        local new, unusable = mod.Value(newStats, scale)
        local label = "  " .. scale.name .. ": "
        if unusable then
            tip:AddLine(label .. "can't use the hovered item", 1, 0.35, 0.35)
        elseif not oldStats then
            tip:AddLine(label .. Fmt(new) .. "  upgrade", 0.3, 1, 0.3)
        else
            local old = mod.Value(oldStats, scale)
            local d = new - old
            local text = ("%s%s -> %s  (%s%s"):format(label, Fmt(old), Fmt(new), d >= 0 and "+" or "", Fmt(d))
            if cfg.showPercent and old > 0 then text = text .. (", %+d%%"):format(math.floor(d / old * 100 + 0.5)) end
            if d > 0.05 then tip:AddLine(text .. ") upgrade", 0.3, 1, 0.3)
            elseif d < -0.05 then tip:AddLine(text .. ") downgrade", 1, 0.35, 0.35)
            else tip:AddLine(text .. ") same", 0.8, 0.8, 0.8) end
        end
    end
end

local busy = false
local function OnShow(tip)
    if busy or not (M.enabled and M.db.showInCompare) then return end
    local hovered = HoveredLink()
    if not hovered then return end
    local key = MemberOf(tip)
    if not key then return end
    local first = _G[tip:GetName() .. "TextLeft1"]
    local firstText = first and first:GetText() or ""
    if firstText:find("^No item data") then return end

    local equipped
    if tip.GetItem then
        local ok, _, l = pcall(tip.GetItem, tip)
        if ok and type(l) == "string" then equipped = l end
    end

    busy = true
    -- a two-hander is compared on the main hand; Item Compare names the slot in the header
    local header = tip.header and tip.header.text and tip.header.text:GetText() or ""
    local offHandTip = header:find("Off Hand", 1, true) or (equipped and OFFHAND_ONLY[EquipLoc(equipped) or ""])
    if EquipLoc(hovered) == "INVTYPE_2HWEAPON" and offHandTip then
        tip:AddLine(" ")
        tip:AddLine("Pawn: two-hander, compared on the main hand", 0.6, 0.6, 0.6)
    else
        local ok, err = pcall(AddLines, tip, key, hovered, equipped)
        if not ok then M:Debug("tooltip error: %s", tostring(err)) end
    end
    tip:Show()   -- resize to the new lines (no second OnShow, it is already shown)
    busy = false
end

local hooked = {}
local function Hook(frame)
    if frame and not hooked[frame] and frame.HookScript then
        hooked[frame] = true
        frame:HookScript("OnShow", OnShow)
        M:Debug("hooked %s", frame:GetName() or "?")
    end
end

-- tips that already exist (normally none, Item Compare creates them on first use)
for i = 1, 40 do Hook(_G[PREFIX .. i]) end

-- and every one created later, before it is first shown
hooksecurefunc("CreateFrame", function(_, name)
    if type(name) == "string" and name:find("^" .. PREFIX .. "%d+$") then Hook(_G[name]) end
end)
