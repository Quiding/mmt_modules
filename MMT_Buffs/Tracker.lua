-- MMT Buffs: who has which tracked buff.
--
-- Members in your group (and you): read from their unit (mod.Buff), so
-- timers and stacks are exact. Members outside the group can't be seen
-- (this client doesn't let addons read the combat log), so their row stays
-- empty. Nothing is sent between the clients for this.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.auras = {}   -- [teamKey] = { [buffName] = { start, dur, count } }, from units
local fromUnit = {} -- [teamKey] = true while the member is read from a unit

-- The game loads spell data lazily: right after login it may not know the name of a
-- spell this character never used (Battle Shout then showed as missing while it was
-- on, and its icon was "?"). So the scan keeps EVERY buff it sees (at most 40 a member,
-- the window looks up the tracked ones by name), and spells still unknown get their
-- data requested; the window redraws once it had time to arrive.
local requested = {}
function mod.BuildIndex()
    local missing = false
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            if not mod.BuffName(e) and not requested[e.id] then
                requested[e.id] = true
                missing = true
                if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, e.id) end
            end
        end
    end
    if missing then C_Timer.After(2, function() if M.enabled then mod.Refresh() end end) end
end

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------
local function UnitKey(unit)
    local _, _, key = MMT.SplitUnit(unit)
    return key and MMT.Resolve(key) or nil
end

local function ScanUnit(unit)
    local key = UnitKey(unit)
    if not key then return end
    local t = {}
    for i = 1, 40 do
        local name, icon, count, duration, expiration = mod.Buff(unit, i)
        if name == "secret" then return end   -- hidden right now: keep what we had
        if not name then break end
        local raw = name
        name = mod.Canonical(name)   -- Prayer of Fortitude counts as Fortitude, ...
        if raw == name then mod.SeeIcon(name, icon) end   -- for a "?" entry icon (EntryIcon)
        local start = (duration and duration > 0 and expiration) and (expiration - duration) or nil
        t[name] = { start = start, dur = (duration and duration > 0) and duration or nil, count = count }
    end
    mod.auras[key] = t
    fromUnit[key] = true
end

local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

function mod.ScanGroup()
    wipe(fromUnit)
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then ScanUnit(unit) end
    end
    for key in pairs(mod.auras) do if not fromUnit[key] then mod.auras[key] = nil end end
end

M:On("UNIT_AURA", function(unit)
    if unit == "player" or (unit and (unit:find("^party%d") or unit:find("^raid%d"))) then
        ScanUnit(unit)
        mod.Refresh()
    end
end)

M:On("GROUP_ROSTER_UPDATE", function() mod.ScanGroup() mod.Refresh() end)
M:On("PLAYER_ENTERING_WORLD", function() mod.ScanGroup() mod.Refresh() end)

M:Listen("TEAM_CHANGED", function() mod.ScanGroup() mod.Refresh() end)

---------------------------------------------------------------------------
-- State of one tracked buff on one member
---------------------------------------------------------------------------

-- Preview (mod.preview, this session only): every team member as if in your
-- group, with made-up states that stay the same between redraws - to set up
-- the look and position without the team around.
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end
mod.PreviewHash = Hash

function mod.SetPreview(on)
    mod.preview = on and true or nil
    mod.Refresh()
end

-- returns "buff", start, duration, count  or  "missing"  or nil (member not in the group)
function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "buff", mod.testUntil - 10, 10, 1 end
    if mod.preview then
        local h = Hash(key .. ":" .. e.id)
        if h % 4 == 0 then return "missing" end
        local dur = (h % 3 + 1) * 600                    -- 10, 20 or 30 minutes
        local left = 60 + h % (dur - 60)                 -- some time left, different per icon
        local now = GetTime()
        return "buff", now - (dur - left), dur, 1
    end
    local name = mod.BuffName(e)
    if not name then return nil end
    if fromUnit[key] then
        local a = mod.auras[key] and mod.auras[key][name]
        if a then return "buff", a.start, a.dur, a.count end
        return "missing"
    end
    return nil
end

function mod.Test()
    mod.testUntil = GetTime() + 10
    mod.Refresh()
    C_Timer.After(10.1, mod.Refresh)
end

local queued = false
function mod.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        if M.enabled then mod.Redraw() end
    end)
end

M:Listen("STATUS_CHANGED", mod.Refresh)
