-- MMT module: Buffs.
-- One row per team member with the buffs tracked for their class: lit with
-- a timer while they have it, dimmed (optionally glowing) when it is missing.
-- Port of EMA Buffs to MMT.
--
--   Lists.lua     tracked lists (per class + ALL)
--   Tracker.lua   group members' auras from their unit (exact timers).
--                 Nothing is sent between the clients for this.
--   Weapons.lua   weapon enchants (imbues, poisons, oils): own read, ONE message per change
--   Window.lua    own window, or icons attached to the Cooldowns window
--                 (MMTIconBars extras, IconBars.lua shared with MMT_Cooldowns)
--   Export.lua    import / export strings; the core's "Sync to team" sends M.db
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "BuffTimers",
    title = "Buff Timers",
    syncExclude = { "takenFrom" },   -- see TakeOver
    description = "Team buff bars: who has, and who misses, the buffs you track.",
    sync = true,               -- the core's "Sync to team" sends M.db (lists, look, position)
    defaults = {
        shown = true, locked = false, clickThrough = false, vertical = false,
        includeSelf = true, onlyOnline = true,
        specSet = {},              -- [teamKey] = spec key set by hand (Specs tab)
        specLists = false,         -- a member with a known spec uses their spec's list instead of the class list (Specs.lua)
        attach = "OFF",            -- OFF: own window (or party frames, onFrames) | LEFT / RIGHT: on the Cooldowns rows
        iconSize = 28, iconZoom = 8, spacing = 2, rowGap = 4, scale = 1, bgAlpha = 0.4,
        bgTexture = "FLAT", bgColor = { r = 0, g = 0, b = 0 }, bgTint = 1,
        borderTexture = "NONE", borderColor = { r = 0.3, g = 0.3, b = 0.3 }, borderSize = 12,
        rowColor = { r = 0, g = 0, b = 0 }, rowAlpha = 0, timerColor = { r = 1, g = 1, b = 1 },
        showNames = true, fullNames = false, nameSize = 11, showTimers = true, timerSize = 13,
        missingAlpha = 0.25, activeAlpha = 1, glowMissing = false,
        swipeColor = { r = 0, g = 0, b = 0 }, swipeAlpha = 0.8,   -- the countdown circle on the icons (Timer tab)
        soonSecs = 0, soonTextColor = { r = 1, g = 0.82, b = 0 }, soonSwipeColor = { r = 0.4, g = 0.3, b = 0 },     -- 0 = off
        urgentSecs = 0, urgentTextColor = { r = 1, g = 0.2, b = 0.2 }, urgentSwipeColor = { r = 0.5, g = 0, b = 0 },
        glowAlerts = true,         -- a SmartBuff alert (own or the team's) makes the buff's icon glow (Alerts.lua)
        point = { "CENTER", "CENTER", -200, 0 },
        onFrames = false,          -- icons beside each member's party / raid frame (IconBars v14, FramesTab.lua)
        framesSide = "RIGHT", framesX = 0, framesY = 0, framesIconSize = 22, framesFit = false,
        framesOthers = "WINDOW",   -- members without a frame: WINDOW (own window) | HIDE
        allOnFrames = false,       -- the All bar above the top party / raid frame (else free, in the window)
        allX = 0, allY = 0,
        hidden = {},
        allBar = true,             -- "All classes" row; the ALL buffs leave the members' rows
        allMissingLook = "RED",    -- missing buffs: PLAIN (normal icon) | RED | GREY, all at missingAlpha
        allExclude = {},           -- [teamKey] = true: not counted in the All classes row
        allCount = "BOTTOMLEFT",   -- All bar: how many have the buff (2+), in this corner | "OFF"
        allCountSize = 12, allCountColor = { r = 1, g = 1, b = 1 },
        hideUnlearned = true,      -- hide buffs not learned yet: own row, and casters who haven't (Known.lua)
        blessingLimit = true,      -- one blessing per paladin in the group (Casters.lua)
        hideNoCaster = true,       -- hide buffs nobody in the group / online team can cast (Casters.lua)
        playerRoles = {},          -- [teamKey] = TANK | HEALER | MELEE | RANGED | CASTER, set by hand (Roles.lua)
        lists = mod.DEFAULT_LISTS,
    },
})
mod.M = M

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_BuffTimers", "Version") or "?"


-- Until 0.9 this module was called "Buffs" (MMT keeps a module's settings under
-- its name). Once per profile, and once for the account-wide storage, the settings
-- of the old name are copied over. MMT's own data is only READ here; only our own
-- M.db / M.store are written. takenFrom stays on this client (syncExclude).
local OLD = "Buffs"
local function TakeOver()
    if not M.db.takenFrom then
        local old = MMT.db and MMT.db.modules and MMT.db.modules[OLD]
        if type(old) == "table" and next(old) then
            for k in pairs(M.db) do M.db[k] = nil end
            for k, v in pairs(old) do M.db[k] = MMT.CopyTable(v) end
            for k, v in pairs(M.defaults or {}) do
                if M.db[k] == nil then M.db[k] = MMT.CopyTable(v) end
            end
            MMT.Print("%s: settings taken over from the old \"%s\" module.", M.title, OLD)
        end
        M.db.takenFrom = OLD
    end
    local store = MMTDB and MMTDB.moduleData and MMTDB.moduleData[OLD]
    if M.store and not M.store.takenFrom and type(store) == "table" then
        for k, v in pairs(store) do
            if M.store[k] == nil then M.store[k] = MMT.CopyTable(v) end
        end
    end
    if M.store then M.store.takenFrom = OLD end
end
mod.TakeOver = TakeOver

M.OnEnable = function()
    TakeOver()
    mod.OwnSpecSent()
    if mod.OwnRoleSent then mod.OwnRoleSent() end
    mod.BuildIndex()
    mod.ScanGroup()
    mod.StartWeapons()
    mod.AlertHook()   -- our own SmartBuff's alerts (Alerts.lua)
    mod.Apply()
    C_Timer.After(1, function() if M.enabled then mod.Apply() end end) -- Cooldowns starts after us
end

M.OnDisable = function()
    mod.StopWeapons()
    mod.Detach()
    mod.window:Hide()
end

M.OnProfileChanged = function()
    TakeOver()
    mod.BuildIndex()
    mod.Apply()
    mod.KnownCheck()
end

SLASH_MMTBUFFTIMERS1 = "/mmtbt"
SlashCmdList.MMTBUFFTIMERS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Buff Timers is switched off (/mmt modules).") return end
    if msg == "preview" or msg == "preview mixed" or msg == "preview all" then
        local want = msg == "preview mixed" and "MIXED" or msg == "preview all" and "ALL" or "REAL"
        mod.SetPreview(mod.preview ~= want and want or nil)
        MMT.Print("%s: preview %s.", M.title, mod.preview == "ALL" and "on, one made-up character of every class"
            or mod.preview == "MIXED" and "on, mixed classes (warrior, paladin, priest, ...)"
            or mod.preview and "on - every team member as if in your group, made-up states" or "off")
        if MMT.RefreshConfig then MMT.RefreshConfig() end
    elseif msg == "test" then
        mod.Test()
        MMT.Print("Buff Timers: 10 second test on every icon.")
    elseif msg == "show" or msg == "hide" or msg == "" then
        M.db.shown = (msg == "show") or (msg == "" and not M.db.shown)
        mod.Apply()
    elseif msg == "export" or msg == "import" then
        mod.OpenTransfer()
    elseif msg == "lock" then
        M.db.locked = not M.db.locked
        MMT.Print("Buffs window %s.", M.db.locked and "locked" or "unlocked")
    elseif msg == "arrange" then
        mod.ToggleArrange()
    elseif msg == "spec" then
        mod.SpecReport(function(line) MMT.Print("%s %s", M.title .. ":", line) end)
    else
        MMT.Print("/mmtbt = show/hide, /mmtbt lock, /mmtbt arrange, /mmtbt spec, /mmtbt test, /mmtbt preview [mixed|all], /mmtbt export. Settings: /mmt > MODULES > Buff Timers.")
    end
end
