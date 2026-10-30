-- MMT Quality of life: SmartBuff's missing-buff alerts, called out to the team.
--
-- SmartBuff Forever builds every "needs a buff" / "runs out" alert in one
-- global function, SMARTBUFF_SetMissingBuffMessage(target, buff, icon,
-- canCharge, charges, timeLeft, expiring) (SmartBuff/Buff.lua): its splash,
-- chat line and sound all come from there, on every check (every 5 s by
-- default) while something is missing. We hook it (hooksecurefunc, nothing of
-- SmartBuff changes), so it works with SmartBuff's own splash / sound off too.
--   * on each character: one MMT.SendAlert (the FTL leader first, then the
--     team) per target + buff and minute (sbRepeat), and again right away
--     when it changes (missing -> running out) or after a fight (sbAfterCombat:
--     what was sent before the fight started counts as new again; SmartBuff
--     checks right when combat ends). SmartBuff reports only the FIRST missing
--     buff of each check (the one its button would cast), the next after that:
--     QSB:<N|E|C>:<seconds or charges>:<target>:<buff>   (%XX escaped)
--   * on the others: a chat line, optionally the raid warning text and a
--     sound - only on the FTL leader (sbShow LEADER, the group leader when no
--     FTL leader is known), on everyone (ALL) or nowhere (OFF). The same
--     alert from several characters shows once per 10 s.

local _, mod = ...
local MMT = MMT
local M = mod.M

local SHOW_AGAIN = 10        -- the same alert (from anyone) on screen at most once per 10 s
local FORGET = 300

local F
local sbs = { sent = 0, shown = 0, hooked = false }
mod.sbs = sbs
local lastSent = {}          -- ["<target>\t<buff>"] = { kind, time }
local lastShown = {}         -- ["<target>\t<buff>\t<kind>"] = time
local combatStart = -1       -- GetTime() when the last fight began

local RAID_WARNING_SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959

local function Clean(t, now)
    for k, v in pairs(t) do
        local at = type(v) == "table" and v.time or v
        if now - at > FORGET then t[k] = nil end
    end
end

-- "item:2589" -> the item's name, else the buff as SmartBuff gave it
-- mod.Esc, and ":" too (the fields are split on it)
local function Esc(s) return (mod.Esc(s):gsub(":", "%%3A")) end

local function BuffName(buff)
    local id = type(buff) == "string" and buff:match("^item:(%d+)")
    if id then return mod.ItemText(id) end
    return tostring(buff)
end

local function OnSmartBuffAlert(target, buff, _, canCharge, charges, timeLeft, expiring)
    if not mod.Active(F) or not M.db.sbSend then return end
    if type(target) ~= "string" or buff == nil or MMT.IsSecret(target) or MMT.IsSecret(buff) then return end
    local kind, value = "N", 0
    if expiring then
        if not M.db.sbExpire then return end
        if canCharge and tonumber(charges) and charges > 0 then kind, value = "C", charges
        else kind, value = "E", math.floor(tonumber(timeLeft) or 0) end
    end
    local name = BuffName(buff)
    local now = GetTime()
    Clean(lastSent, now)
    local key = target .. "\t" .. name
    local last = lastSent[key]
    local fresh = M.db.sbAfterCombat and last and last.time <= combatStart
    if last and last.kind == kind and not fresh and now - last.time < (tonumber(M.db.sbRepeat) or 60) then return end
    lastSent[key] = { kind = kind, time = now }
    local msg = ("QSB:%s:%d:%s:%s"):format(kind, value, Esc(target), Esc(name))
    if #msg > 240 then msg = msg:sub(1, 240):gsub("%%%x?$", "") end
    MMT.SendAlert(msg)
    sbs.sent = sbs.sent + 1
end

-- hooked once SmartBuff's function exists (it loads before us: OptionalDeps)
function mod.SmartBuffHook()
    if sbs.hooked then return true end
    if type(rawget(_G, "SMARTBUFF_SetMissingBuffMessage")) ~= "function" then return false end
    hooksecurefunc("SMARTBUFF_SetMissingBuffMessage", function(...)
        local ok, err = pcall(OnSmartBuffAlert, ...)
        if not ok then M:Debug("SmartBuff alert: %s", tostring(err)) end
    end)
    sbs.hooked = true
    return true
end

-- does this client show the team's alerts?
local function ShowsHere()
    local where = M.db.sbShow
    if where == "OFF" then return false end
    if where == "ALL" then return true end
    local leader = MMT.FTLLeader and MMT.FTLLeader()
    if leader then return MMT.IsSelf(leader) end
    if IsInGroup and IsInGroup() then return UnitIsGroupLeader and UnitIsGroupLeader("player") or false end
    return true
end
mod.SmartBuffShowsHere = ShowsHere

-- a team member's name as SmartBuff wrote it ("Bob" / "Bob Stone") -> the
-- name the privacy setting shows here (MMT.ShownName); anything else stays
local function Shown(name)
    if not MMT.ShownName then return name end
    local low = name:lower()
    local found
    for _, key in ipairs(MMT.SortedMembers()) do
        local first = (MMT.RealFirst and MMT.RealFirst(key) or key:match("^[^-]+") or ""):lower()
        local full = (MMT.RealName and MMT.RealName(key) or key:gsub("-", " ")):lower()
        if low == full or low == key:lower() then return MMT.ShownName(key) end
        if low == first then
            if found then return name end   -- two members with this first name: leave it
            found = key
        end
    end
    return found and MMT.ShownName(found) or name
end
mod.SmartBuffShownName = Shown

local function Text(from, kind, value, target, buff)
    local who = MMT.ShownName and MMT.ShownName(from) or MMT.FirstName and MMT.FirstName(from) or from
    target = Shown(target)
    if kind == "C" then return ("%s: %s - %s has %d charge(s) left"):format(who, target, buff, value) end
    if kind == "E" then return ("%s: %s - %s runs out in %d s"):format(who, target, buff, value) end
    return ("%s: %s needs %s"):format(who, target, buff)
end

local function OnAlert(from, _, body)
    local kind, value, target, buff = body:match("^([NEC]):(%d+):([^:]*):(.*)$")
    if not kind or not ShowsHere() then return end
    target, buff = mod.Unesc(target), mod.Unesc(buff)
    local now = GetTime()
    Clean(lastShown, now)
    local key = target .. "\t" .. buff .. "\t" .. kind
    if lastShown[key] and now - lastShown[key] < SHOW_AGAIN then return end
    lastShown[key] = now
    local text = Text(from, kind, tonumber(value) or 0, target, buff)
    MMT.Print("|cffffa020%s|r", text)
    if M.db.sbRaid and RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.63, b = 0.13 })
    end
    if M.db.sbSound and PlaySound then pcall(PlaySound, RAID_WARNING_SOUND, "Master") end
    sbs.shown = sbs.shown + 1
end

F = mod.Feature({
    key = "smartbuff", slash = "smartbuff", addon = "SmartBuff", title = "SmartBuff alerts", tabText = "SmartBuff",
    checkText = "Call out SmartBuff's alerts to the team",
    tip = "When SmartBuff on a character says a buff is missing (or runs out), the FTL leader - or everyone, see below - gets it as a chat line, raid warning text and sound.",
    notes = {
        "Each character with SmartBuff sends what its SmartBuff reports - the same alerts as its splash text, also with SmartBuff's splash or sound switched off - once a minute per target and buff, and right away when it changes.",
        "They go out as MMT alerts: the FTL leader first, then the team. Where they show is set on each character (\"Show the team's alerts\"). The same alert from several characters shows once.",
        "SmartBuff checks mostly out of combat, so the alerts come then. A character whose SmartBuff doesn't track a buff sends nothing for it.",
    },
    tags = { QSB = OnAlert },
    OnEnable = function() mod.SmartBuffHook() end,
    Page = function(ui)
        ui.Check("Send my SmartBuff alerts", "sbSend", "What SmartBuff reports on this character goes to the team.")
        ui.Check("Buffs running out too", "sbExpire", "Also SmartBuff's \"rebuff, 30 s left\" / low charges alerts. Off: only missing buffs.")
        ui.Cycle("Send the same alert again after", { { value = 30, text = "30 seconds" }, { value = 60, text = "1 minute" },
            { value = 120, text = "2 minutes" }, { value = 300, text = "5 minutes" } }, "sbRepeat")
        ui.Check("Again after each fight", "sbAfterCombat", "SmartBuff checks as soon as combat ends: what it reports then is sent even within the time above.")
        ui.Cycle("Show the team's alerts", { { value = "LEADER", text = "Only on the FTL leader" },
            { value = "ALL", text = "On every character" }, { value = "OFF", text = "Not on this character" } }, "sbShow")
        ui.Check("Raid warning text", "sbRaid", "The alert in the middle of the screen, like a raid warning.")
        ui.Check("Sound", "sbSound", "The raid warning sound with each alert shown.")
    end,
    Report = function(add)
        add(("SmartBuff: hooked=%s sent=%d shown=%d showsHere=%s show=%s"):format(tostring(sbs.hooked), sbs.sent, sbs.shown,
            tostring(ShowsHere()), tostring(M.db.sbShow)))
    end,
})

-- a fight starts: everything sent before it counts as new afterwards
M:On("PLAYER_REGEN_DISABLED", function() combatStart = GetTime() end)
