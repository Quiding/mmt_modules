-- MMT module: Cooldowns.
-- A window with one row per team member showing their important cooldowns
-- (spells, trinkets, potions). Port of EMA Cooldowns to MMT.
--
--   Spells.lua    tracked lists (per class + ALL) and spell/item lookups
--   Tracker.lua   who used what: group members' casts (UNIT_SPELLCAST_SUCCEEDED),
--                 the game's own cooldown API for your own character. Nothing
--                 is sent over the addon channel for this.
--   Window.lua    rows for MMTIconBars (IconBars.lua, shared with MMT_Buffs)
--   Sync.lua      "Send lists to team" (the only addon messages, tag MCDL)
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "Cooldowns",
    title = "Cooldowns",
    description = "Team cooldown bars: every member's important spells and items.",
    defaults = {
        shown = true, locked = false, clickThrough = false, vertical = false,
        includeSelf = true, onlyOnline = true,
        iconSize = 28, spacing = 2, rowGap = 4, scale = 1, bgAlpha = 0.4,
        showNames = true, nameSize = 11, showTimers = true, timerSize = 13,
        readyAlpha = 0.35, cdAlpha = 1, glowActive = true,
        itemsOnlyWhenSeen = true,   -- items of other members appear after their first use
        point = { "CENTER", "CENTER", 200, 0 },
        hidden = {},                -- [teamKey] = true: no row for this member
        lists = mod.DEFAULT_LISTS,
    },
})
mod.M = M

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_Cooldowns", "Version") or "?"

M.OnEnable = function()
    mod.BuildIndex()
    mod.window:Refresh()
end

M.OnDisable = function()
    mod.window:Hide()
end

M.OnProfileChanged = function()
    mod.BuildIndex()
    mod.window:Refresh()
end

SLASH_MMTCOOLDOWNS1 = "/mmtcd"
SlashCmdList.MMTCOOLDOWNS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Cooldowns is switched off (/mmt modules).") return end
    if msg == "test" then
        mod.Test()
        MMT.Print("Cooldowns: 10 second test on every icon.")
    elseif msg == "show" or msg == "hide" or msg == "" then
        M.db.shown = (msg == "show") or (msg == "" and not M.db.shown)
        mod.window:Refresh()
    elseif msg == "lock" then
        M.db.locked = not M.db.locked
        MMT.Print("Cooldowns window %s.", M.db.locked and "locked" or "unlocked")
    else
        MMT.Print("/mmtcd = show/hide, /mmtcd lock, /mmtcd test. Settings: /mmt > MODULES > Cooldowns.")
    end
end
