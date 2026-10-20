-- MMT Pawn Compare: the team in the normal item tooltip.
--
-- When you hover an item, GameTooltip gets a list of team members (with
-- stored Pawn scales) and what the item would gain them over what they have
-- equipped. Setting M.db.teamTooltip:
--   REPLACE  Pawn's own value lines are left out of GameTooltip and the team
--            list takes their place (your own character is in the list too)
--   ADD      the team list is added below Pawn's lines
--   OFF      nothing
--
-- Equipped items: your own from the game, the others from Item Compare's
-- stored equipment (see Score.lua). Rings and trinkets compare against the
-- weaker of the two, one-hand weapons against the main hand (or the off hand
-- if a weapon is there), two-handers against main + off hand together.

local _, mod = ...
local MMT = MMT
local M = mod.M

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}
local OFFHAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

local function EquipLoc(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return link and fn and select(4, fn(link)) or nil
end

-- only for items the team list covers, so Pawn still shows everything else
local function ReplaceOn(tip)
    if not (M.enabled and M.db.teamTooltip == "REPLACE") then return false end
    local ok, _, link = pcall(tip.GetItem, tip)
    local loc = ok and type(link) == "string" and EquipLoc(link)
    return loc and SLOTS[loc] and mod.ScalesOf(MMT.PlayerFull() or "") and true or false
end

---------------------------------------------------------------------------
-- Gain for one member and scale
---------------------------------------------------------------------------
-- value of the member's item in a slot; nil while the item isn't loaded
local function SlotValue(key, slot, scale)
    local link = mod.EquippedLink(key, slot)
    if not link then return 0, link end
    local stats = mod.ItemStats(link)
    if not stats then return nil end
    return (mod.Value(stats, scale)), link
end

-- returns gain, old value ("loading" while items are missing, "unusable")
local function Gain(key, loc, newStats, scale)
    local new, unusable = mod.Value(newStats, scale)
    if unusable then return "unusable" end
    local slots = SLOTS[loc]
    local old
    if loc == "INVTYPE_2HWEAPON" then
        local mh, oh = SlotValue(key, 16, scale), SlotValue(key, 17, scale)
        if not mh or not oh then return "loading" end
        old = mh + oh
    else
        for _, slot in ipairs(slots) do
            local v, link = SlotValue(key, slot, scale)
            if v == nil then return "loading" end
            -- a one-hander only goes into the off hand if a weapon is there already
            local usable = not (loc == "INVTYPE_WEAPON" and slot == 17 and not OFFHAND_WEAPON[EquipLoc(link) or ""])
            if usable and (not old or v < old) then old = v end
        end
    end
    return new - (old or 0), old or 0
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------
local function ClassName(key)
    local m = MMT.db and MMT.db.team and MMT.db.team[key]
    local c = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
    local name = MMT.FirstName(key)
    if c then name = ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name) end
    return name
end

local function AddTeam(tip, link)
    local loc = EquipLoc(link)
    if not (loc and SLOTS[loc]) then return end
    local newStats, exact = mod.ItemStats(link)
    if not newStats then return end
    local cfg = M.db

    local rows = {}
    for _, key in ipairs(MMT.SortedMembers()) do
        local rec = mod.ScalesOf(key)
        if rec and #rec.scales > 0 and mod.HasEquipment(key) and not (cfg.hideUnusable and not mod.CanUse(key, link)) then
            for i, scale in ipairs(rec.scales) do
                if i > 1 and not cfg.allScales then break end
                local left = ClassName(key)
                if cfg.allScales and #rec.scales > 1 then left = left .. " |cff888888" .. scale.name .. "|r" end
                local gain, old = Gain(key, loc, newStats, scale)
                local right, r, g, b
                if gain == "unusable" then
                    right, r, g, b = "can't use", 0.5, 0.5, 0.5
                elseif gain == "loading" then
                    right, r, g, b = "...", 0.5, 0.5, 0.5
                else
                    right = ("%s%.1f"):format(gain >= 0 and "+" or "", gain)
                    if old == 0 then right = right .. " (empty slot)"
                    elseif cfg.showPercent then right = right .. (" (%+d%%)"):format(math.floor(gain / old * 100 + 0.5)) end
                    if gain > 0.05 then r, g, b = 0.3, 1, 0.3
                    elseif gain < -0.05 then r, g, b = 1, 0.35, 0.35
                    else r, g, b = 0.8, 0.8, 0.8 end
                end
                rows[#rows + 1] = { left, right, r, g, b }
            end
        end
    end
    if #rows == 0 then return end

    tip:AddLine(" ")
    tip:AddLine("Team upgrades (Pawn)" .. (exact and "" or " - approx., no Pawn here"), 0.6, 0.6, 0.6)
    for _, row in ipairs(rows) do
        tip:AddDoubleLine("  " .. row[1], row[2], 1, 1, 1, row[3], row[4], row[5])
    end
    tip:Show()
end

---------------------------------------------------------------------------
-- Hooks (installed after Pawn's, so our lines come after Pawn's)
---------------------------------------------------------------------------
local done, doneLink = false, nil   -- lines added to the current GameTooltip content

local function OnItemSet(tip)
    if not M.enabled or M.db.teamTooltip == "OFF" then return end
    local ok, _, link = pcall(tip.GetItem, tip)
    if not ok or type(link) ~= "string" or (MMT.IsSecret and MMT.IsSecret(link)) then return end
    if done and link == doneLink then return end
    done, doneLink = true, link
    local ok2, err = pcall(AddTeam, tip, link)
    if not ok2 then M:Debug("item tooltip error: %s", tostring(err)) end
end

local METHODS = { "SetBagItem", "SetHyperlink", "SetInventoryItem", "SetLootItem", "SetLootRollItem",
    "SetMerchantItem", "SetBuybackItem", "SetQuestItem", "SetQuestLogItem", "SetInboxItem",
    "SetSendMailItem", "SetTradePlayerItem", "SetTradeTargetItem", "SetAuctionItem", "SetItemByID",
    "SetGuildBankItem" }

local installed = false
local function Install()
    if installed or not GameTooltip then return end
    installed = true
    for _, method in ipairs(METHODS) do
        if GameTooltip[method] then hooksecurefunc(GameTooltip, method, OnItemSet) end
    end
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function() done = false end)
    GameTooltip:HookScript("OnHide", function() done = false end)

    -- REPLACE: leave Pawn's value lines out of GameTooltip (Pawn's other tooltips are untouched)
    if type(PawnAddValuesToTooltip) == "function" then
        local original = PawnAddValuesToTooltip
        PawnAddValuesToTooltip = function(tooltip, ...)
            if tooltip == GameTooltip and ReplaceOn(tooltip) then return end
            return original(tooltip, ...)
        end
    end
    M:Debug("item tooltip hooks installed")
end

-- Pawn installs its hooks at PLAYER_LOGIN; we registered later, so we run after it
if IsLoggedIn and IsLoggedIn() then
    Install()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents() Install() end)
end
