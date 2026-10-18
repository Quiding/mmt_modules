-- MMT module: Buffs.
-- One row per team member with the buffs tracked for their class: lit with
-- a timer while they have it, dimmed (optionally glowing) when it is missing.
-- Port of EMA Buffs to MMT.
--
--   Lists.lua     tracked lists (per class + ALL)
--   Tracker.lua   group members' auras from their unit (exact timers).
--                 Nothing is sent between the clients for this.
--   Window.lua    own window, or icons attached to the Cooldowns window
--                 (MMTIconBars extras, IconBars.lua shared with MMT_Cooldowns)
--   Sync.lua      "Send lists to team" (the only addon messages, tag MBFL)
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "Buffs",
    title = "Buffs",
    description = "Team buff bars: who has, and who misses, the buffs you track.",
    defaults = {
        shown = true, locked = false, clickThrough = false, vertical = false,
        includeSelf = true, onlyOnline = true,
        attach = "OFF",            -- OFF: own window | LEFT / RIGHT: on the Cooldowns rows
        iconSize = 28, spacing = 2, rowGap = 4, scale = 1, bgAlpha = 0.4,
        showNames = true, nameSize = 11, showTimers = true, timerSize = 13,
        missingAlpha = 0.25, glowMissing = false,
        point = { "CENTER", "CENTER", -200, 0 },
        hidden = {},
        allBar = true,             -- "All classes" row; the ALL buffs leave the members' rows
        allMissingLook = "RED",    -- RED | GREY when someone misses an All classes buff
        allExclude = {},           -- [teamKey] = true: not counted in the All classes row
        lists = mod.DEFAULT_LISTS,
    },
})
mod.M = M

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_Buffs", "Version") or "?"

M.OnEnable = function()
    mod.BuildIndex()
    mod.ScanGroup()
    mod.Apply()
    C_Timer.After(1, function() if M.enabled then mod.Apply() end end) -- Cooldowns starts after us
end

M.OnDisable = function()
    mod.Detach()
    mod.window:Hide()
end

M.OnProfileChanged = function()
    mod.BuildIndex()
    mod.Apply()
end

SLASH_MMTBUFFS1 = "/mmtbf"
SlashCmdList.MMTBUFFS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Buffs is switched off (/mmt modules).") return end
    if msg == "test" then
        mod.Test()
        MMT.Print("Buffs: 10 second test on every icon.")
    elseif msg == "show" or msg == "hide" or msg == "" then
        M.db.shown = (msg == "show") or (msg == "" and not M.db.shown)
        mod.Apply()
    elseif msg == "export" or msg == "import" then
        mod.OpenTransfer()
    elseif msg == "lock" then
        M.db.locked = not M.db.locked
        MMT.Print("Buffs window %s.", M.db.locked and "locked" or "unlocked")
    else
        MMT.Print("/mmtbf = show/hide, /mmtbf lock, /mmtbf test, /mmtbf export. Settings: /mmt > MODULES > Buffs.")
    end
end
