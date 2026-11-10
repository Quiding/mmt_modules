-- MMT Cooldown Timers / Buff Timers (the same file in both): settings changes go to the team
-- by themselves - no "Sync to team" click each time.
--
-- Whatever changes this module's settings (a checkbox, a slider, a list, an icon dragged on the
-- bars, ...) also redraws MMT ("REFRESH") or its settings window: then, once nothing has changed
-- for QUIET seconds, only what CHANGED since the last send goes out - in one message per burst,
-- each changed setting (a list: the whole list of that class / role / character).
-- The team's clients with "Take the team's changes" apply them at once, no dialog.
--
-- Never sent, and kept as they are when changes come in: window positions ("point" at any depth)
-- and the two switches below (each client chooses for itself), and the module's syncExclude.
--
--   <TAG>:<MMT.Serialize{ c = { { p = { key [, key2] }, v = value | d = true }, ... } }>
-- (MMT.SendLong: any size, bulk priority)

local _, mod = ...
local MMT = MMT
local M = mod.M

local TAG = ({ CooldownTimers = "MCDA", BuffTimers = "MBTA" })[M.name] or ("MAS" .. M.name)
local QUIET = 5
local SWITCHES = { autoSend = true, autoTake = true }

local function Local(k, depth)
    if k == "point" then return true end
    if depth == 0 then
        if SWITCHES[k] then return true end
        for _, x in ipairs(M.syncExclude or {}) do if x == k then return true end end
    end
    return false
end

-- a copy of v without the keys that stay on this client
local function Strip(v, depth)
    if type(v) ~= "table" then return v end
    if depth > 30 then return nil end
    local t = {}
    for k, x in pairs(v) do
        if not Local(k, depth) and type(x) ~= "function" then t[k] = Strip(x, depth + 1) end
    end
    return t
end

-- the same text for the same contents (pairs() order differs between tables)
local function Sig(v, out)
    local top = not out
    out = out or {}
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = type(k) .. ":" .. tostring(k) .. "="
            Sig(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = t .. ":" .. tostring(v)
    end
    if top then return table.concat(out) end
end
mod.SettingsSig = Sig

local last          -- Strip(M.db) as last sent / received
local lastSig       -- Sig(last)
local pendingSig, changedAt, armed
local stats = { sent = 0, changes = 0, received = 0, applied = 0 }
mod.autoSyncStats = stats

local function Snapshot()
    if not M.db then return end
    last = Strip(M.db, 0)
    lastSig = Sig(last)
    pendingSig, changedAt = nil, nil
end
mod.AutoSyncReset = Snapshot

-- the changes from old to new, two levels deep
local function Diff(old, new)
    local c = {}
    local keys = {}
    for k in pairs(old) do keys[k] = true end
    for k in pairs(new) do keys[k] = true end
    for k in pairs(keys) do
        local a, b = new[k], old[k]
        if Sig(a) ~= Sig(b) then
            if type(a) == "table" and type(b) == "table" then
                local k2s = {}
                for k2 in pairs(a) do k2s[k2] = true end
                for k2 in pairs(b) do k2s[k2] = true end
                for k2 in pairs(k2s) do
                    if Sig(a[k2]) ~= Sig(b[k2]) then
                        c[#c + 1] = a[k2] == nil and { p = { k, k2 }, d = true } or { p = { k, k2 }, v = a[k2] }
                    end
                end
            else
                c[#c + 1] = a == nil and { p = { k }, d = true } or { p = { k }, v = a }
            end
        end
    end
    return c
end
mod.SettingsDiff = Diff

-- what changed since the last send goes out now (nothing when nothing did)
function mod.AutoSyncFlush()
    pendingSig, changedAt = nil, nil
    if not (M.enabled and M.db) then return end
    if not last then Snapshot() return end
    local now = Strip(M.db, 0)
    local c = Diff(last, now)
    last, lastSig = now, Sig(now)
    if #c == 0 or not M.db.autoSend then return end
    MMT.SendLong(TAG .. ":" .. MMT.Serialize({ c = c }), nil, "BULK")
    stats.sent, stats.changes = stats.sent + 1, stats.changes + #c
    M:Debug("settings: %d change(s) sent to the team", #c)
end

local applying = false
local Tick
local function Arm(delay)
    if armed then return end
    armed = true
    C_Timer.After(delay, function() armed = false; Tick() end)
end

-- sent once the settings have stayed the same for QUIET seconds
Tick = function()
    mod.AutoSyncCheck(true)
    if not changedAt then return end
    local wait = changedAt + QUIET - GetTime()
    if wait > 0.05 then Arm(wait) return end
    mod.AutoSyncFlush()
end

-- something may have changed: note when the settings last looked different
local lastCheck = -10
function mod.AutoSyncCheck(force)
    if applying or not (M.enabled and M.db and M.db.autoSend) then return end
    if not last then Snapshot() return end
    local t = GetTime()
    if not force and t - lastCheck < 1 then Arm(1) return end   -- many redraws at once: one look a second
    lastCheck = t
    local sig = Sig(Strip(M.db, 0))
    if sig == lastSig then pendingSig, changedAt = nil, nil return end
    if sig ~= pendingSig then pendingSig, changedAt = sig, t end
    Arm(math.max(0.1, changedAt + QUIET - t))
end
local function Schedule() mod.AutoSyncCheck() end

-- the window positions of old put into new where new has none
local function KeepPoints(new, old, depth)
    if type(new) ~= "table" or type(old) ~= "table" or depth > 30 then return end
    for k, v in pairs(old) do
        if k == "point" then
            if new[k] == nil then new[k] = MMT.CopyTable(v) end
        elseif type(v) == "table" then
            KeepPoints(new[k], v, depth + 1)
        end
    end
end

local function Apply(changes)
    local n = 0
    for _, ch in ipairs(changes) do
        local p = type(ch) == "table" and type(ch.p) == "table" and ch.p
        local k, k2 = p and p[1], p and p[2]
        if k ~= nil and not Local(k, 0) and (k2 == nil or not Local(k2, 1)) then
            local parent, key = M.db, k
            if k2 ~= nil then
                if type(M.db[k]) ~= "table" then M.db[k] = {} end
                parent, key = M.db[k], k2
            end
            local old = parent[key]
            local v = nil
            if not ch.d then
                v = MMT.CopyTable(ch.v)
                KeepPoints(v, old, 0)
            end
            -- the same as here already (a change that came back): nothing to do
            if Sig(Strip(v, 1)) ~= Sig(Strip(old, 1)) then
                parent[key] = v
                n = n + 1
            end
            -- the baseline follows, so this isn't sent back as our own change
            if last then
                if k2 ~= nil then
                    if type(last[k]) ~= "table" then last[k] = {} end
                    last[k][k2] = Strip(v, 1)
                else
                    last[k] = Strip(v, 1)
                end
            end
        end
    end
    if last then lastSig = Sig(last) end
    return n
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if type(text) ~= "string" or text:sub(1, #TAG + 1) ~= TAG .. ":" then return end
    if MMT.IsSelf(key) then return end
    stats.received = stats.received + 1
    if not M.db.autoTake then return end
    local t = MMT.Deserialize(text:sub(#TAG + 2))
    if type(t) ~= "table" or type(t.c) ~= "table" then return end
    applying = true
    local ok, n = pcall(Apply, t.c)
    if ok and n > 0 then
        stats.applied = stats.applied + n
        if M.OnProfileChanged then pcall(M.OnProfileChanged, M) end
        if M.OnSyncReceived then pcall(M.OnSyncReceived, M, key) end
        if MMT.RefreshConfig then pcall(MMT.RefreshConfig) end
        MMT.Print("%s: %d setting change(s) from %s.", M.title, n, MMT.FullDisplay and MMT.FullDisplay(key) or tostring(key))
    end
    applying = false
end)

M:Listen("REFRESH", Schedule)
if hooksecurefunc and type(MMT.RefreshConfig) == "function" then hooksecurefunc(MMT, "RefreshConfig", Schedule) end
-- a setting that changes nothing else: caught while MMT's settings window is open
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(3, function()
        local f = rawget(_G, "MMTConfigFrame")
        if f and f.IsShown and f:IsShown() then Schedule() end
    end)
end

-- the baseline: what this client has when it starts / switches profile (nothing is sent for it)
M:On("PLAYER_ENTERING_WORLD", function() if not last then Snapshot() end end)
-- another profile, or the module's settings from a "Sync to team": the new baseline, not a change of ours
if hooksecurefunc then
    if type(MMT.SetProfile) == "function" then hooksecurefunc(MMT, "SetProfile", Snapshot) end
    if type(MMT.ImportModuleSettings) == "function" then
        hooksecurefunc(MMT, "ImportModuleSettings", function(name) if name == M.name then Snapshot() end end)
    end
end

function mod.AutoSyncReport(add)
    add(("auto sync: send=%s take=%s sent=%d (%d changes) received=%d applied=%d"):format(
        tostring(M.db.autoSend), tostring(M.db.autoTake), stats.sent, stats.changes, stats.received, stats.applied))
end
