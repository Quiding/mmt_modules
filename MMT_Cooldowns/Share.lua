-- MMT Cooldowns: tell the team when YOU use a tracked cooldown, so members
-- outside your group see it too. One short message per use, nothing
-- periodic:
--   MCDU:<entryKey>:<remaining>/<duration>   cooldown started (e.g. MCDU:s871:1799.8/1800)
--   MCDU:<entryKey>:a                        "after buff" spell used, cooldown starts later
-- Only state CHANGES of your own tracked entries are sent (ready -> cooldown,
-- ready -> active, active -> cooldown), found on the game's cooldown events.

local _, mod = ...
local MMT = MMT
local M = mod.M

local last          -- [entryKey] = state of the previous check (nil before the first check)

local function Check()
    if not M.enabled then return end
    local key = MMT.PlayerFull()
    if not key then return end
    local now = {}
    for _, e in ipairs(mod.EntriesFor(key)) do
        local ek = mod.EntryKey(e)
        local state, start, dur = mod.OwnState(e)
        if state then
            now[ek] = state
            local before = last and last[ek]
            if last and state ~= before and state ~= "ready" then
                local msg
                if state == "active" then
                    msg = ("MCDU:%s:a"):format(ek)
                else
                    msg = ("MCDU:%s:%.1f/%.1f"):format(ek, start + dur - GetTime(), dur)
                end
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

M:On("SPELL_UPDATE_COOLDOWN", Queue)
M:On("BAG_UPDATE_COOLDOWN", Queue)
M:On("SPELLS_CHANGED", Queue)
M:On("PLAYER_ENTERING_WORLD", function() last = nil; Queue() end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function EntryOf(key, ek)
    for _, e in ipairs(mod.EntriesFor(key)) do
        if mod.EntryKey(e) == ek then return e end
    end
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local ek, data = text:match("^MCDU:([si]%d+):(.+)$")
    if not ek or MMT.IsSelf(key) then return end
    local e = EntryOf(key, ek)
    if not e then return end   -- not in our lists for that member's class
    mod.cds[key] = mod.cds[key] or {}
    if e.t == "i" then
        M.store.seen = M.store.seen or {}
        M.store.seen[key] = M.store.seen[key] or {}
        M.store.seen[key][ek] = true
    end
    if data == "a" then
        mod.cds[key][ek] = { pending = GetTime(), dur = e.cd or 0, buff = mod.CastName(e) }
    else
        local rem, dur = data:match("^([%d%.]+)/([%d%.]+)$")
        rem, dur = tonumber(rem), tonumber(dur)
        if not rem or not dur or dur <= 0 then return end
        mod.cds[key][ek] = { start = GetTime() - (dur - rem), dur = dur }
    end
    M:Debug("%s: %s %s", MMT.Repr(key), ek, data)
    mod.Refresh()
end)
