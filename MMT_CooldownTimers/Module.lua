-- MMT module: Cooldowns.
-- A window with one row per team member showing their important cooldowns
-- (spells, trinkets, potions). Port of EMA Cooldowns to MMT.
--
--   Spells.lua    tracked lists (per class + ALL) and spell/item lookups
--   Tracker.lua   who used what: group members' casts (UNIT_SPELLCAST_SUCCEEDED),
--                 the game's own cooldown API for your own character. Nothing
--                 is sent over the addon channel for this.
--   Window.lua    rows for MMTIconBars (IconBars.lua, shared with MMT_Buffs)
--   Share.lua     one message (MCDU) when YOUR character uses a tracked cooldown,
--                 so members outside the group are tracked too
--   Export.lua    import / export strings; the core's "Sync to team" sends M.db
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "CooldownTimers",
    title = "Cooldown Timers",
    syncExclude = { "takenFrom" },   -- see TakeOver
    description = "Team cooldown bars: every member's important spells and items.",
    sync = true,               -- the core's "Sync to team" sends M.db (lists, look, position)
    defaults = {
        shown = true, locked = false, clickThrough = false, vertical = false,
        includeSelf = true, onlyOnline = true,
        specLists = false,         -- a member with a known spec uses their spec's list instead of the class list (Specs.lua)
        iconSize = 28, iconZoom = 8, spacing = 2, rowGap = 4, scale = 1, bgAlpha = 0.4,
        bgTexture = "FLAT", bgColor = { r = 0, g = 0, b = 0 }, bgTint = 1,
        borderTexture = "NONE", borderColor = { r = 0.3, g = 0.3, b = 0.3 }, borderSize = 12,
        rowColor = { r = 0, g = 0, b = 0 }, rowAlpha = 0, timerColor = { r = 1, g = 1, b = 1 },
        showNames = true, fullNames = false, nameSize = 11, showTimers = true, timerSize = 13,
        readyAlpha = 0.35, cdAlpha = 1, glowActive = true,
        hideReady = false,          -- only show icons while they are on cooldown
        showBuffs = true,           -- while the spell's buff is up: glow with the buff's time left
        hideUnknown = true,         -- spells a character hasn't learned (shared, Known.lua) / items you don't carry
        hideUnseenItems = false,    -- other members' items only after you saw them used
        point = { "CENTER", "CENTER", 200, 0 },
        hidden = {},                -- [teamKey] = true: no row for this member
        lists = mod.DEFAULT_LISTS,
    },
})
mod.M = M

-- tell the team our race (for the race lists); tiny, rides on MMT's heartbeat
M:Heartbeat("race", function()
    local _, race = UnitRace("player")
    return race and race:gsub("[^%w]", "") or nil
end)

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_CooldownTimers", "Version") or "?"


-- Until 0.10 this module was called "Cooldowns" (MMT keeps a module's settings under
-- its name). Once per profile, and once for the account-wide storage, the settings
-- of the old name are copied over. MMT's own data is only READ here; only our own
-- M.db / M.store are written. takenFrom stays on this client (syncExclude).
local OLD = "Cooldowns"
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
    mod.BuildIndex()
    mod.window:Refresh()
end

M.OnDisable = function()
    mod.window:Hide()
end

M.OnProfileChanged = function()
    TakeOver()
    mod.BuildIndex()
    mod.window:Refresh()
    if mod.KnownCheck then mod.KnownCheck() end
end

SLASH_MMTCOOLDOWNTIMERS1 = "/mmtct"
SlashCmdList.MMTCOOLDOWNTIMERS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Cooldown Timers is switched off (/mmt modules).") return end
    if msg == "preview" or msg == "preview mixed" or msg == "preview all" then
        local want = msg == "preview mixed" and "MIXED" or msg == "preview all" and "ALL" or "REAL"
        mod.SetPreview(mod.preview ~= want and want or nil)
        MMT.Print("%s: preview %s.", M.title, mod.preview == "ALL" and "on, one made-up character of every class"
            or mod.preview == "MIXED" and "on, mixed classes (warrior, paladin, priest, ...)"
            or mod.preview and "on - every team member as if in your group, made-up states" or "off")
        if MMT.RefreshConfig then MMT.RefreshConfig() end
    elseif msg == "test" then
        mod.Test()
        MMT.Print("Cooldown Timers: 10 second test on every icon.")
    elseif msg == "show" or msg == "hide" or msg == "" then
        M.db.shown = (msg == "show") or (msg == "" and not M.db.shown)
        mod.window:Refresh()
    elseif msg == "export" or msg == "import" then
        mod.OpenTransfer()
    elseif msg == "lock" then
        M.db.locked = not M.db.locked
        MMT.Print("Cooldowns window %s.", M.db.locked and "locked" or "unlocked")
    else
        MMT.Print("/mmtct = show/hide, /mmtct lock, /mmtct test, /mmtct preview [mixed|all], /mmtct export. Settings: /mmt > MODULES > Cooldown Timers.")
    end
end
