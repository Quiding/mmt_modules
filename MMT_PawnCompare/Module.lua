-- MMT module: Pawn Compare.
-- Adds Pawn scores to the Item Compare tooltips: for every team member, the
-- hovered item is scored with THEIR Pawn scales and compared against the
-- item they have equipped in that slot. Optionally the normal item tooltip
-- lists the whole team's gains too, in place of Pawn's own lines.
--
--   Scales.lua   reads this character's Pawn scales, syncs them with the team
--                and keeps every member's scales in M.store (account-wide), so
--                offline members and clients without Pawn can still compare.
--   Score.lua    item stats (Pawn if loaded, else the game's item stats) and
--                the scale value calculation.
--   Tooltip.lua  adds the lines to Item Compare's tooltips.
--   ItemTooltip.lua  team list in the normal item tooltip (GameTooltip).
--   Loot.lua     master loot to the member an item is the biggest upgrade for
--                (Loot Distribution's MMT.RegisterLootChooser, core 1.4.0+).
--   Manage.lua   list of Pawn scales here and on the team, delete them on both.
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
        specFit = true,       -- no values for gear the member wouldn't wear: mail / plate before 40, a shield for Enhancement / Fury, a two-hander for Fury (Proficiency.lua)
        hideUnusable = true,  -- no values for members whose class can never use the item
        hideOffline = false,  -- leave out team members who are offline (item tooltip and Item Compare's)
        teamTooltip = "REPLACE",  -- team list in the item tooltip: REPLACE Pawn's lines | ADD below them | OFF
        askDelete = true,     -- ask before deleting the Pawn scales a team member deleted
        lootByUpgrade = false, -- master loot: gear to the member it is the biggest upgrade for
        lootMinGain = 1,      -- ... at least this many percent (an empty slot always counts)
        upgradesOnline = true, -- M.TeamUpgrades (Disenchant Loot's junk, Quality of life's valuable loot): online members only
        bopChat = true,        -- after Loot Distribution's "... is BOP" line: who it is the biggest upgrade for (Loot.lua)
        lootScale = {},       -- [teamKey] = Pawn scale name that member's loot is judged by
    },
    sync = true,              -- the core's "Sync to team" (nothing here is per client)
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
    mod.RegisterLoot()   -- in case Loot Distribution loaded after us
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
    mod.CloseScales()
    M:Debug("disabled")
end

-- the team's settings were applied: tooltips read M.db fresh, Pawn's cached ones are redrawn
M.OnSyncReceived = function()
    if PawnResetTooltips then pcall(PawnResetTooltips) end
    MMT.Fire("PAWN_SCALES_CHANGED")
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
    elseif msg == "scales" then
        mod.OpenScales()
    elseif msg:match("^loot") then
        local link = msg:match("(item:[%d:%-]+)")   -- from a link (lower-cased above) or typed
        local id = not link and tonumber(msg:match("^loot%s+(%d+)"))
        link = link or (id and ("item:" .. id))
        if not link then MMT.Print("Pawn Compare: /mmtpc loot <item link or ID> = who would get it as master loot.") return end
        mod.PrintLootRanking(link)
    elseif msg:match("^why") then
        local link = msg:match("(item:[%d:%-]+)")
        local id = not link and tonumber(msg:match("^why%s+(%d+)"))
        link = link or (id and ("item:" .. id))
        if not link then MMT.Print("Pawn Compare: /mmtpc why <item link or ID> = the values behind the team upgrade lines.") return end
        mod.PrintWhy(link)
    elseif msg == "request" then
        mod.RequestAll()
        MMT.Print("Pawn Compare: asked the online team for their scales.")
    else
        MMT.Print("Pawn Compare %s - Pawn %s, Item Compare %s. Stored scales for %d characters.",
            mod.VERSION, mod.PawnInstalled() and "found" or "NOT installed",
            mod.ItemCompareActive() and "on" or "OFF", mod.StoredCount())
        MMT.Print("/mmtpc send = send your scales, /mmtpc request = ask the team for theirs, /mmtpc scales = list / delete Pawn scales, /mmtpc loot <item> = who would get it by upgrade, /mmtpc why <item> = the values behind the upgrade lines.")
    end
end

-- /mmtpc why: the item's weapon stats, and per member and scale its value and that of what they wear there
local WHY_STATS = { "Dps", "MeleeDps", "OneHandDps", "MainHandDps", "OffHandDps", "TwoHandDps", "Speed", "Strength", "Agility", "HitRating", "CritRating", "Ap" }
function mod.PrintWhy(link)
    local loc = mod.EquipLoc(link)
    local stats, exact = mod.ItemStats(link)
    if not (loc and mod.SLOTS[loc] and stats) then MMT.Print("Pawn Compare: %s isn't equippable or not loaded yet.", link) return end
    local function StatText(st)
        if not st then return "not loaded" end
        local t = {}
        for _, k in ipairs(WHY_STATS) do if st[k] then t[#t + 1] = ("%s=%.1f"):format(k, st[k]) end end
        return #t > 0 and table.concat(t, " ") or "(none of the usual stats)"
    end
    MMT.Print("Pawn Compare: %s %s (%s): %s", link, loc, exact and "Pawn" or "game, approx.", StatText(stats))
    for _, key in ipairs(MMT.SortedMembers()) do
        local rec = mod.ScalesOf(key)
        if rec and rec.scales and #rec.scales > 0 and mod.HasEquipment(key) then
            for _, scale in ipairs(rec.scales) do
                local v, unusable = mod.Value(stats, scale)
                local parts = {}
                for _, slot in ipairs(loc == "INVTYPE_2HWEAPON" and { 16, 17 } or mod.SLOTS[loc]) do
                    local l = mod.EquippedLink(key, slot)
                    local st = l and mod.ItemStats(l)
                    local name = l and (C_Item.GetItemInfo(l)) or l or "empty"
                    parts[#parts + 1] = ("[%d] %s = %s (%s)"):format(slot, tostring(name), st and ("%.1f"):format((mod.Value(st, scale))) or "?", l and StatText(st) or "-")
                end
                MMT.Print("  %s %s: new %s; %s", MMT.FirstName(key), scale.name, unusable and "unusable" or ("%.1f"):format(v), table.concat(parts, "; "))
            end
        end
    end
end
