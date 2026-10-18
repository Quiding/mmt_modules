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

local index = {} -- [buffName] = true
function mod.BuildIndex()
    wipe(index)
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            local n = mod.BuffName(e)
            if n then index[n] = true end
        end
    end
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
        local name, _, count, duration, expiration = mod.Buff(unit, i)
        if name == "secret" then return end   -- hidden right now: keep what we had
        if not name then break end
        name = mod.Canonical(name)   -- Prayer of Fortitude counts as Fortitude, ...
        if index[name] then
            local start = (duration and duration > 0 and expiration) and (expiration - duration) or nil
            t[name] = { start = start, dur = (duration and duration > 0) and duration or nil, count = count }
        end
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
-- returns "buff", start, duration, count  or  "missing"  or nil (member not in the group)
function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "buff", mod.testUntil - 10, 10, 1 end
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
