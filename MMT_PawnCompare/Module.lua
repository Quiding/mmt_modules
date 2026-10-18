-- MMT module: Pawn Compare.
-- Adds Pawn scores to the Item Compare tooltips: for every team member, the
-- hovered item is scored with THEIR Pawn scales and compared against the
-- item they have equipped in that slot.
--
--   Scales.lua   reads this character's Pawn scales, syncs them with the team
--                and keeps every member's scales in M.store (account-wide), so
--                offline members and clients without Pawn can still compare.
--   Score.lua    item stats (Pawn if loaded, else the game's item stats) and
--                the scale value calculation.
--   Tooltip.lua  adds the lines to Item Compare's tooltips.
--   Settings.lua settings page and debug report.
--
-- Uses only the documented MMT module API. Message tags start with PCMP_.

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "PawnCompare",
    title = "Pawn Compare",
    description = "Adds Pawn scores for every team member to the Item Compare tooltips. Needs Item Compare.",
    defaults = {
        greetOnLogin = true,
        showInCompare = true,
        allScales = true,     -- every visible scale of the member, or only the first
        showPercent = true,
    },
})
mod.M = M

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_PawnCompare", "Version") or "?"

function mod.PawnInstalled()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded and isLoaded("Pawn") and true or false
end

function mod.PawnReady()
    return mod.PawnInstalled() and PawnIsReady and PawnIsReady() and true or false
end

function mod.ItemCompareActive()
    return MMT.ModuleActive and MMT.ModuleActive("ItemCompare") or false
end

-- one line telling what is missing, or nil if everything is there
function mod.Problems()
    local p = {}
    if not mod.ItemCompareActive() then p[#p + 1] = "Item Compare is not switched on (/mmt > MODULES), Pawn Compare needs it" end
    if not mod.PawnInstalled() then p[#p + 1] = "Pawn is not installed on this character, using stored scales and approximate stats" end
    return #p > 0 and table.concat(p, ". ") .. "." or nil
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local ticker

M.OnEnable = function()
    -- Pawn and the other modules need a moment after login
    C_Timer.After(3, function()
        if not M.enabled then return end
        mod.UpdateOwn(true)
        local problems = mod.Problems()
        if problems then
            MMT.Print("Pawn Compare: %s", problems)
        elseif M.db.greetOnLogin then
            MMT.Print("Pawn Compare %s ready, %d of your Pawn scales shared with the team.", mod.VERSION, mod.OwnScaleCount())
        end
    end)
    -- Pawn has no event for edited scales, so check for changes now and then
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(20, function() if M.enabled then mod.UpdateOwn(true) end end)
    M:Debug("enabled")
end

M.OnDisable = function()
    if ticker then ticker:Cancel() ticker = nil end
    M:Debug("disabled")
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_MMTPAWNCOMPARE1 = "/mmtpc"
SlashCmdList.MMTPAWNCOMPARE = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Pawn Compare is switched off (/mmt modules).") return end
    if msg == "send" then
        mod.UpdateOwn(false)
        mod.SendScales()
        MMT.Print("Pawn Compare: your scales were sent to the team.")
    elseif msg == "request" then
        mod.RequestAll()
        MMT.Print("Pawn Compare: asked the online team for their scales.")
    else
        MMT.Print("Pawn Compare %s - Pawn %s, Item Compare %s. Stored scales for %d characters.",
            mod.VERSION, mod.PawnInstalled() and "found" or "NOT installed",
            mod.ItemCompareActive() and "on" or "OFF", mod.StoredCount())
        MMT.Print("/mmtpc send = send your scales, /mmtpc request = ask the team for theirs.")
    end
end
