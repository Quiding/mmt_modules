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
local sbs = { seen = 0, sent = 0, held = 0, shown = 0, hooked = false }
local ticker
mod.sbs = sbs
local lastSent = {}          -- ["<target>\t<buff>"] = { kind, time }
local lastShown = {}         -- ["<target>\t<buff>\t<kind>"] = time
local combatStart = -1       -- GetTime() when the last fight began
local combatEnd = -1         -- and when the last one ended: what was sent before that counts as new
local fights = { regen = 0, attack = 0, tick = 0 }   -- what noticed the fights (debug report)
local function FightStarted(source)
    combatStart = GetTime()
    fights[source] = fights[source] + 1
end
local function FightEnded() combatEnd = GetTime() end

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
    sbs.seen = sbs.seen + 1
    local name = BuffName(buff)
    local now = GetTime()
    Clean(lastSent, now)
    local key = target .. "\t" .. name
    local last = lastSent[key]
    -- after a fight: also what was sent DURING it (SmartBuff can report then) is new again
    local fresh = M.db.sbAfterCombat and last and last.time < combatEnd
    if last and last.kind == kind and not fresh and now - last.time < (tonumber(M.db.sbRepeat) or 60) then
        sbs.held = sbs.held + 1
        return
    end
    M:Debug("SmartBuff alert sent: %s / %s (%s)", target, name, kind)
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
        "SmartBuff reports only out of combat, and not while mounted, eating / drinking or with a group buff's target out of range; it reports one missing buff at a time (the one it would cast next). A character whose SmartBuff doesn't track a buff sends nothing for it.",
    },
    tags = { QSB = OnAlert },
    OnEnable = function()
        mod.SmartBuffHook()
        if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, mod.SmartBuffCombatTick) end
    end,
    OnDisable = function()
        if ticker then ticker:Cancel(); ticker = nil end
    end,
    Page = function(ui)
        ui.Check("Send my SmartBuff alerts", "sbSend", "What SmartBuff reports on this character goes to the team.")
        ui.Check("Buffs running out too", "sbExpire", "Also SmartBuff's \"rebuff, 30 s left\" / low charges alerts. Off: only missing buffs.")
        ui.Cycle("Send the same alert again after", { { value = 30, text = "30 seconds" }, { value = 60, text = "1 minute" },
            { value = 120, text = "2 minutes" }, { value = 300, text = "5 minutes" } }, "sbRepeat")
        ui.Check("Again after each fight", "sbAfterCombat", "When a fight ends (this character or anyone in the group was in combat), what SmartBuff reports next is sent even within the time above - also if the same alert went out just before or during the fight.")
        ui.Cycle("Show the team's alerts", { { value = "LEADER", text = "Only on the FTL leader" },
            { value = "ALL", text = "On every character" }, { value = "OFF", text = "Not on this character" } }, "sbShow")
        ui.Check("Raid warning text", "sbRaid", "The alert in the middle of the screen, like a raid warning.")
        ui.Check("Sound", "sbSound", "The raid warning sound with each alert shown.")
    end,
    Report = function(add)
        add(("SmartBuff: hooked=%s seen=%d sent=%d held=%d shown=%d showsHere=%s show=%s fights=regen %d/attack %d/poll %d lastFight=%s"):format(tostring(sbs.hooked),
            sbs.seen, sbs.sent, sbs.held, sbs.shown, tostring(ShowsHere()), tostring(M.db.sbShow), fights.regen, fights.attack, fights.tick,
            combatEnd < 0 and "-" or ("ended %d s ago"):format(GetTime() - combatEnd)))
    end,
})

-- a fight starts: everything sent before it counts as new afterwards. A fight
-- = this character OR anyone in the group in combat (followers that never get
-- into combat themselves still count the team's fights), polled every second.
local function Fighting(unit)
    local ok, v = pcall(UnitAffectingCombat, unit)
    if not ok then return false end
    if MMT.IsSecret(v) then return true end
    return v and true or false
end

local fighting = false
function mod.SmartBuffCombatTick()
    local now = Fighting("player")
    if not now and IsInGroup and IsInGroup() then
        local raid = IsInRaid and IsInRaid()
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, raid and n or math.min(n, 4) do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and Fighting(unit) then now = true break end
        end
    end
    if now and not fighting then FightStarted("tick") end
    if fighting and not now then FightEnded() end
    fighting = now
end

-- PLAYER_REGEN_DISABLED (in combat) didn't show up in the user's debug log on
-- Forever, PLAYER_ENTER_COMBAT (auto attack starts) did: either one counts
M:On("PLAYER_REGEN_DISABLED", function() FightStarted("regen") end)
M:On("PLAYER_ENTER_COMBAT", function() FightStarted("attack") end)
-- the end: out of combat again; auto attack stopping counts only when the game says we're out of combat
M:On("PLAYER_REGEN_ENABLED", FightEnded)
M:On("PLAYER_LEAVE_COMBAT", function() if not Fighting("player") then FightEnded() end end)

-- /mmtqol smartbuff combat: what this client says about combat right now
local function CombatCheck()
    local function V(fn, ...)
        local ok, v = pcall(fn, ...)
        if not ok then return "error" end
        if MMT.IsSecret(v) then return "secret" end
        return tostring(v)
    end
    MMT.Print("Quality of life: UnitAffectingCombat(player)=%s InCombatLockdown=%s party1=%s; fights seen: in-combat event %d, auto attack %d, poll %d; last %s%s",
        V(UnitAffectingCombat, "player"), V(InCombatLockdown), V(UnitAffectingCombat, "party1"),
        fights.regen, fights.attack, fights.tick,
        combatStart < 0 and "never" or ("started %d s ago"):format(GetTime() - combatStart),
        combatEnd < 0 and "" or (", ended %d s ago"):format(GetTime() - combatEnd))
end
F.commands = { combat = CombatCheck }
