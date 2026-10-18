-- MMT Buffs: who has which tracked buff.
--
-- Members in your group (and you): read from their unit with UnitBuff, so
-- timers and stacks are exact. Members outside the group: the combat log's
-- SPELL_AURA_APPLIED / _REFRESH / _REMOVED, which says that they have it
-- but not for how long. Nothing is sent between the clients for this.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.auras = {}   -- [teamKey] = { [buffName] = { start, dur, count } }, from units
mod.logged = {}  -- [teamKey] = { [buffName] = true }, from the combat log
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
        local name, _, count, _, duration, expiration = UnitBuff(unit, i)
        if not name then break end
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

---------------------------------------------------------------------------
-- Combat log (members outside the group)
---------------------------------------------------------------------------
local byGUID = {}
local function KeyOf(guid, name)
    local k = byGUID[guid]
    if k ~= nil then return k or nil end
    k = MMT.Resolve(MMT.NameFromGUID(guid, name)) or MMT.Resolve(name) or false
    byGUID[guid] = k
    return k or nil
end
M:Listen("TEAM_CHANGED", function() wipe(byGUID) mod.Refresh() end)

local PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

M:On("COMBAT_LOG_EVENT_UNFILTERED", function()
    local _, event, _, _, _, _, _, guid, name, flags, _, _, spellName, _, auraType = CombatLogGetCurrentEventInfo()
    if event ~= "SPELL_AURA_APPLIED" and event ~= "SPELL_AURA_REFRESH" and event ~= "SPELL_AURA_REMOVED" then return end
    if not index[spellName] or auraType ~= "BUFF" or not flags or bit.band(flags, PLAYER) == 0 then return end
    local key = KeyOf(guid, name)
    if not key or fromUnit[key] then return end   -- grouped members come from their unit
    mod.logged[key] = mod.logged[key] or {}
    mod.logged[key][spellName] = (event ~= "SPELL_AURA_REMOVED") or nil
    mod.Refresh()
end)

---------------------------------------------------------------------------
-- State of one tracked buff on one member
---------------------------------------------------------------------------
-- returns "buff", start, duration, count  or  "missing"  or nil (no data about this member)
function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "buff", mod.testUntil - 10, 10, 1 end
    local name = mod.BuffName(e)
    if not name then return nil end
    if fromUnit[key] then
        local a = mod.auras[key] and mod.auras[key][name]
        if a then return "buff", a.start, a.dur, a.count end
        return "missing"
    end
    local l = mod.logged[key]
    if l and l[name] then return "buff" end
    return "missing"
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
