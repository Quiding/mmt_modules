-- MMT Cooldowns: tell the team when YOU use a tracked cooldown, so members
-- outside your group see it too. One short message per change, nothing
-- periodic:
--   MCDU:<entryKey>:<remaining>/<duration>   cooldown started (e.g. MCDU:s871:1799.8/1800)
--     ...:b<remaining>/<duration>           + the buff it gave you, if any (e.g. :b14.7/15)
--   MCDU:<entryKey>:a                        "after buff" spell used, cooldown starts later
--   MCDU:<entryKey>:r                        ready again before its time (Cold Snap,
--                                            Preparation, ... reset it)
--   MCDQ                                     "which of your cooldowns are running?" - sent
--                                            after taking over new lists (to the team) and
--                                            after login / reload (whispered to each member
--                                            the first time their heartbeat arrives); the
--                                            asked answer with their running ones (whisper)
-- Only state CHANGES of your own tracked entries are sent, found on the
-- game's cooldown events. An entry that just became tracked (lists changed)
-- counts as a change, so its running cooldown is announced too.

local _, mod = ...
local MMT = MMT
local M = mod.M

local EARLY = 1.5   -- seconds before the end: earlier than that is a reset worth telling

local last          -- [entryKey] = state of the previous check (nil before the first check)
local ends = {}     -- [entryKey] = when its running cooldown would end

local function Message(e, ek, state, start, dur)
    if state == "active" then return ("MCDU:%s:a"):format(ek) end
    local msg = ("MCDU:%s:%.1f/%.1f"):format(ek, start + dur - GetTime(), dur)
    local name = mod.CastName(e)
    local bStart, bDur
    if name then bStart, bDur = mod.UnitBuffTime("player", name) end
    if bStart then msg = msg .. (":b%.1f/%.1f"):format(bStart + bDur - GetTime(), bDur) end
    return msg
end

local function Check()
    if not M.enabled then return end
    local key = MMT.PlayerFull()
    if not key then return end
    local now, t = {}, GetTime()
    for _, e in ipairs(mod.EntriesFor(key)) do
        local ek = mod.EntryKey(e)
        local state, start, dur = mod.OwnState(e)
        if state then
            now[ek] = state
            local before = last and last[ek]
            local msg
            if last and state ~= before and state ~= "ready" then
                msg = Message(e, ek, state, start, dur)
            elseif last and state == "ready" and (before == "active"
                or (before == "cd" and ends[ek] and ends[ek] - t > EARLY)) then
                msg = ("MCDU:%s:r"):format(ek)   -- reset early: teammates drop the old timer
            end
            ends[ek] = (state == "cd") and (start + dur) or nil
            if msg then
                MMT.SendToTeam(msg, true)
                M:Debug("sent %s", msg)
            end
        end
    end
    last = now   -- the first check only learns the current state
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; Check() end)
end
mod.ShareCheck = Queue   -- lists changed: announce what became tracked and is running

M:On("SPELL_UPDATE_COOLDOWN", Queue)
M:On("BAG_UPDATE_COOLDOWN", Queue)
M:On("SPELLS_CHANGED", Queue)
M:On("PLAYER_ENTERING_WORLD", function() last = nil; Queue() end)

-- all running tracked cooldowns of this character, to one member or the team
function mod.AnnounceRunning(target)
    local key = MMT.PlayerFull()
    if not key then return 0 end
    local n = 0
    for _, e in ipairs(mod.EntriesFor(key)) do
        local state, start, dur = mod.OwnState(e)
        if state == "cd" or state == "active" then
            local msg = Message(e, mod.EntryKey(e), state, start, dur)
            if target then MMT.SendAddon(msg, "WHISPER", target) else MMT.SendToTeam(msg, true) end
            n = n + 1
        end
    end
    return n
end

-- ask the team for their running cooldowns (after taking over new lists)
function mod.RequestRunning()
    MMT.SendToTeam("MCDQ", true)
end

---------------------------------------------------------------------------
-- After login / reload: the team's running cooldowns aren't in memory any more
--  - a reload keeps them: saved on logout with the real clock (time()), put back on enable
--  - and each member is asked once, when their first heartbeat arrives (whisper MCDQ)
---------------------------------------------------------------------------
local asked = {}   -- [key] = true: asked this session

M:On("PLAYER_LOGOUT", function()
    local now, clock, saved = GetTime(), time(), {}
    for key, list in pairs(mod.cds) do
        for ek, c in pairs(list) do
            local rem = c.start and c.dur and (c.start + c.dur - now)
            if rem and rem > 1 then
                saved[key] = saved[key] or {}
                saved[key][ek] = { rem = rem, dur = c.dur, at = clock }
            end
        end
    end
    M.store.running = next(saved) and saved or nil
end)

function mod.RestoreRunning()
    local saved = M.store.running
    M.store.running = nil
    if type(saved) ~= "table" then return 0 end
    local now, clock, n = GetTime(), time(), 0
    for key, list in pairs(saved) do
        if not MMT.IsSelf(key) then
            for ek, s in pairs(list) do
                local rem = (tonumber(s.rem) or 0) - (clock - (tonumber(s.at) or clock))
                local dur = tonumber(s.dur)
                if rem > 0 and dur and dur > 0 then
                    mod.cds[key] = mod.cds[key] or {}
                    if not mod.cds[key][ek] then
                        mod.cds[key][ek] = { start = now - (dur - rem), dur = dur, msg = now }
                        n = n + 1
                    end
                end
            end
        end
    end
    if n > 0 then mod.Refresh() end
    return n
end

M:Listen("XP_RECEIVED", function(key, sender)
    if asked[key] or MMT.IsSelf(key) or not sender then return end
    asked[key] = true
    MMT.SendAddon("MCDQ", "WHISPER", sender)
end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function EntryOf(key, ek)
    for _, e in ipairs(mod.EntriesFor(key)) do
        if mod.EntryKey(e) == ek then return e end
    end
end

local answered = {}
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "MCDQ" then
        if answered[key] and GetTime() - answered[key] < 10 then return end
        answered[key] = GetTime()
        mod.AnnounceRunning(sender)
        return
    end
    local ek, data = text:match("^MCDU:([si]%d+):(.+)$")
    if not ek then return end
    local e = EntryOf(key, ek)
    if not e then return end   -- not in our lists for that member's class
    mod.cds[key] = mod.cds[key] or {}
    if e.t == "i" then
        M.store.seen = M.store.seen or {}
        M.store.seen[key] = M.store.seen[key] or {}
        M.store.seen[key][ek] = true
    end
    if data == "r" then
        mod.cds[key][ek] = nil
    elseif data == "a" then
        mod.cds[key][ek] = { pending = GetTime(), dur = mod.MemberDuration(key, e), buff = mod.CastName(e), msg = GetTime() }
    else
        local rem, dur, buff = data:match("^([%d%.]+)/([%d%.]+)(.*)$")
        rem, dur = tonumber(rem), tonumber(dur)
        if not rem or not dur or dur <= 0 then return end
        -- the real length (talents, ...): used next time their cast is seen before a message
        M.store.durs = M.store.durs or {}
        M.store.durs[key] = M.store.durs[key] or {}
        M.store.durs[key][ek] = math.floor(dur + 0.5)
        local c = { start = GetTime() - (dur - rem), dur = dur, msg = GetTime() }
        local bRem, bDur = (buff or ""):match("^:b([%d%.]+)/([%d%.]+)$")
        bRem, bDur = tonumber(bRem), tonumber(bDur)
        if bRem and bDur and bDur > 0 then c.buffStart, c.buffDur = GetTime() - (bDur - bRem), bDur end
        mod.cds[key][ek] = c
    end
    M:Debug("%s: %s %s", MMT.Repr(key), ek, data)
    mod.Refresh()
end)
