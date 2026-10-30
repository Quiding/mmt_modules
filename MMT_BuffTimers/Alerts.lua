-- MMT Buffs: SmartBuff's alerts make the buff's icon glow (setting glowAlerts).
--
-- SmartBuff Forever builds every "needs a buff" / "runs out" alert in the global
-- SMARTBUFF_SetMissingBuffMessage(target, buff, ...); Quality of life (SmartBuff
-- alerts) sends each one to the team as QSB:<N|E|C>:<value>:<target>:<buff>
-- (%XX escaped). We read both: our own SmartBuff (hooksecurefunc, nothing of
-- SmartBuff changes) and the team's QSB messages, whatever Quality of life on
-- this client shows. The member's icon (and the All bar's) glows until they
-- have the buff again (a "runs out" alert: until it was cast again), or for
-- ALERT_FOR seconds after the last alert.

local _, mod = ...
local MMT = MMT
local M = mod.M

local ALERT_FOR = 90    -- SmartBuff repeats an alert while it lasts (Quality of life: once a minute)

mod.alerts = {}         -- [teamKey] = { [buff name, canonical] = { kind, time } }

local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- SmartBuff's target ("Bob" / "Bob Stone") -> team key; a first name two members share stays unknown
local function KeyOf(name)
    local low = name:lower()
    local found
    for _, key in ipairs(MMT.SortedMembers()) do
        local first = (MMT.RealFirst and MMT.RealFirst(key) or key:match("^[^-]+") or ""):lower()
        local full = (MMT.RealName and MMT.RealName(key) or key:gsub("-", " ")):lower()
        if low == full or low == key:lower() then return key end
        if low == first then
            if found then return nil end
            found = key
        end
    end
    return found
end

local function Note(kind, target, buff)
    if type(target) ~= "string" or type(buff) ~= "string" or (MMT.IsSecret and (MMT.IsSecret(target) or MMT.IsSecret(buff))) then return end
    local key = KeyOf(target)
    if not key then return end
    local name = mod.Canonical(buff) or buff
    -- (spell data not loaded yet: a greater blessing still counts as the single one)
    if name == buff and buff:find("^Greater Blessing of ") then name = buff:gsub("^Greater ", "") end
    mod.alerts[key] = mod.alerts[key] or {}
    mod.alerts[key][name] = { kind = kind, time = GetTime() }
    if M.enabled and M.db.glowAlerts then
        mod.Refresh()
        if C_Timer and C_Timer.After then C_Timer.After(ALERT_FOR + 0.1, mod.Refresh) end   -- the glow ends
    end
end
mod.NoteAlert = Note

-- the team's alerts (Quality of life's QSB messages)
M:Listen("TEAM_MESSAGE", function(_, _, text)
    if type(text) ~= "string" then return end
    local kind, _, target, buff = text:match("^QSB:([NEC]):(%d+):([^:]*):(.*)$")
    if kind then Note(kind, Unesc(target), Unesc(buff)) end
end)

-- our own SmartBuff's alerts ("item:2589" buffs are items: never a tracked buff name)
local hooked = false
function mod.AlertHook()
    if hooked or type(SMARTBUFF_SetMissingBuffMessage) ~= "function" then return end
    hooked = true
    hooksecurefunc("SMARTBUFF_SetMissingBuffMessage", function(target, buff, _, canCharge, charges, timeLeft, expiring)
        local kind = (canCharge and charges and charges > 0) and "C" or (expiring and "E") or "N"
        Note(kind, target, buff)
    end)
end

-- should entry e glow for member key now? (state / start = what mod.State said)
function mod.Alerted(key, e, state, start)
    if not M.db.glowAlerts then return false end
    local t = mod.alerts[key]
    if not t then return false end
    local now = GetTime()
    local own = mod.BuffName(e)
    for name, a in pairs(t) do
        if now - a.time > ALERT_FOR then
            t[name] = nil
        elseif name == own or (mod.IsPattern(e) and mod.Matches(e, name)) then
            -- they have it again: missing -> any buff; running out -> cast again since the alert
            if state == "buff" and (a.kind == "N" or (start and start >= a.time - 1)) then
                t[name] = nil
            else
                return true
            end
        end
    end
    return false
end
