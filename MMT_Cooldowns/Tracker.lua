-- MMT Cooldowns: who used what.
--
-- This client (WoW: Forever runs on the modern client) does not let addons
-- register COMBAT_LOG_EVENT_UNFILTERED, so team members are followed through
-- their party/raid unit instead: UNIT_SPELLCAST_SUCCEEDED starts the entry's
-- cooldown with the duration from the list. Spells like Nature's Swiftness
-- start when their buff is gone from the caster (UNIT_AURA); until then they
-- glow. Only members in your group can be seen this way, and nothing is sent
-- between the clients for this.
--
-- Your own character: the game's cooldown API, exact and with talents.

local _, mod = ...
local MMT = MMT
local M = mod.M

local GCD = 1.6
local PENDING_MAX = 120   -- a buff we never saw fade: start the cooldown anyway

mod.cds = {}              -- [teamKey][entryKey] = { start, dur } or { pending = GetTime(), dur }

---------------------------------------------------------------------------
-- Lookup: cast name -> entries
---------------------------------------------------------------------------
local index = {}          -- [castName] = { entry, ... }
local missing = false     -- some names weren't cached yet

function mod.BuildIndex()
    wipe(index)
    missing = false
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            local name = mod.CastName(e)
            if name then
                index[name] = index[name] or {}
                table.insert(index[name], e)
            else
                missing = true
            end
        end
    end
end

M:On("GET_ITEM_INFO_RECEIVED", function()
    if missing then mod.BuildIndex() end
end)

---------------------------------------------------------------------------
-- Group units -> team keys
---------------------------------------------------------------------------
local function UnitKey(unit)
    local _, _, key = MMT.SplitUnit(unit)
    return key and MMT.Resolve(key) or nil
end

M:Listen("TEAM_CHANGED", function() mod.Refresh() end)

local function EntryForMember(key, name)
    if not index[name] then return nil end
    for _, e in ipairs(mod.EntriesFor(key)) do
        if mod.CastName(e) == name then return e end
    end
end

local function GroupUnit(unit)
    return unit and (unit:find("^party%d") or unit:find("^raid%d")) and true or false
end

-- a group member cast something
M:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if not GroupUnit(unit) or not spellID or MMT.IsSecret(spellID) then return end
    local spellName = mod.SpellInfo(spellID)
    if not spellName or MMT.IsSecret(spellName) or not index[spellName] then return end
    local key = UnitKey(unit)
    if not key or MMT.IsSelf(key) then return end
    local e = EntryForMember(key, spellName)
    if not e then return end
    local ek = mod.EntryKey(e)
    mod.cds[key] = mod.cds[key] or {}
    if e.t == "i" then
        M.store.seen = M.store.seen or {}
        M.store.seen[key] = M.store.seen[key] or {}
        M.store.seen[key][ek] = true
    end
    if mod.IsAfterBuff(spellName) then
        mod.cds[key][ek] = { pending = GetTime(), dur = e.cd or 0, buff = spellName }
    else
        mod.cds[key][ek] = { start = GetTime(), dur = e.cd or 0 }
    end
    M:Debug("%s used %s", MMT.Repr(key), spellName)
    mod.Refresh()
end)

-- "after buff" spells: the cooldown starts when the buff is gone from the
-- caster (or after 3 s if the buff never showed up)
local function HasBuff(unit, name)
    for i = 1, 40 do
        local n = mod.Buff(unit, i)
        if not n then return false end
        if n == "secret" then return nil end   -- can't tell right now
        if n == name then return true end
    end
    return false
end

local function CheckPending(unit)
    local key = UnitKey(unit)
    local cds = key and mod.cds[key]
    if not cds then return end
    local now = GetTime()
    for ek, c in pairs(cds) do
        if c.pending and c.buff then
            local has = HasBuff(unit, c.buff)
            if has then
                c.seen = true
            elseif has == false and (c.seen or now - c.pending > 3) then
                cds[ek] = { start = now, dur = c.dur }
                mod.Refresh()
            end
        end
    end
end

M:On("UNIT_AURA", function(unit)
    if GroupUnit(unit) then CheckPending(unit) end
    -- buffs of tracked spells (Berserking, Evasion, ...) come and go
    if M.db.showBuffs and (unit == "player" or GroupUnit(unit)) then mod.Refresh() end
end)

---------------------------------------------------------------------------
-- The buff a tracked spell or item put on its user (same name as the cast)
---------------------------------------------------------------------------
local unitOf = {}   -- [teamKey] = group unit

local function MapUnits()
    wipe(unitOf)
    if IsInRaid() then
        for i = 1, 40 do local u = "raid" .. i; local k = UnitExists(u) and UnitKey(u); if k then unitOf[k] = u end end
    else
        for i = 1, 4 do local u = "party" .. i; local k = UnitExists(u) and UnitKey(u); if k then unitOf[k] = u end end
    end
end
M:On("GROUP_ROSTER_UPDATE", MapUnits)
M:On("PLAYER_ENTERING_WORLD", MapUnits)
M:Listen("TEAM_CHANGED", MapUnits)

-- start, duration of a timed buff called name on unit, or nil
local function UnitBuffTime(unit, name)
    for i = 1, 40 do
        local n, _, _, dur, expiration = mod.Buff(unit, i)
        if not n or n == "secret" then return nil end
        if n == name then
            if dur and dur > 0 and expiration then return expiration - dur, dur end
            return nil
        end
    end
end
mod.UnitBuffTime = UnitBuffTime

-- start, duration of the buff entry e gave member key right now, or nil
function mod.ActiveBuff(key, e)
    local name = mod.CastName(e)
    if not name then return nil end
    local unit = MMT.IsSelf(key) and "player" or unitOf[key]
    if unit and UnitExists(unit) then return UnitBuffTime(unit, name) end
    -- outside the group: the time their client sent with the use message
    local c = mod.cds[key] and mod.cds[key][mod.EntryKey(e)]
    if c and c.buffStart and c.buffStart + c.buffDur > GetTime() then return c.buffStart, c.buffDur end
end

---------------------------------------------------------------------------
-- State of one entry for one member: state, start, duration
---------------------------------------------------------------------------
local lastOwn = {}   -- [entryKey] = last readable state (the game hides cooldowns at times)

-- own spell not learned yet / item not carried: shown as ready unless hidden
local function Unknown()
    if M.db.hideUnknown then return nil end
    return "ready"
end

local function OwnState(e)
    local start, dur, enabled
    if e.t == "s" then
        local name = mod.SpellName(e.id)
        if not name then return nil end
        start, dur, enabled = mod.SpellCooldown(name)
        if start == nil then return Unknown() end   -- not learned by this character
        if start == "secret" then
            local l = lastOwn[mod.EntryKey(e)]
            if l then return l[1], l[2], l[3] end
            return "ready"
        end
    else
        local count = (C_Item and C_Item.GetItemCount or GetItemCount)(e.id)
        local equipped = (C_Item and C_Item.IsEquippedItem or IsEquippedItem)(e.id)
        if (count or 0) == 0 and not equipped then return Unknown() end
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        start, dur, enabled = fn(e.id)
    end
    local state
    if enabled == 0 or enabled == false then state = "active"
    elseif start and start > 0 and dur and dur > GCD then state = "cd"
    else state = "ready" end
    lastOwn[mod.EntryKey(e)] = { state, start, dur }
    if state == "cd" then return state, start, dur end
    return state
end

-- returns state ("ready" | "cd" | "active") or nil when the entry isn't shown for this member
mod.OwnState = OwnState

function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "cd", mod.testUntil - 10, 10 end
    if MMT.IsSelf(key) then return OwnState(e) end
    local ek = mod.EntryKey(e)
    if e.t == "i" and M.db.hideUnseenItems then
        local seen = M.store.seen and M.store.seen[key]
        if not (seen and seen[ek]) then return nil end
    end
    local c = mod.cds[key] and mod.cds[key][ek]
    if not c then return "ready" end
    local now = GetTime()
    if c.pending then
        if now - c.pending > PENDING_MAX then
            mod.cds[key][ek] = { start = c.pending, dur = c.dur }
            return mod.State(key, e)
        end
        return "active"
    end
    if c.start + c.dur > now then return "cd", c.start, c.dur end
    mod.cds[key][ek] = nil
    return "ready"
end

function mod.Test()
    mod.testUntil = GetTime() + 10
    mod.Refresh()
    C_Timer.After(10.1, mod.Refresh)
end

---------------------------------------------------------------------------
-- Redraw on own cooldown changes (throttled)
---------------------------------------------------------------------------
local queued = false
function mod.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0.15, function()
        queued = false
        if M.enabled then mod.window:Refresh() end
    end)
end

M:On("SPELL_UPDATE_COOLDOWN", mod.Refresh)
M:On("BAG_UPDATE_COOLDOWN", mod.Refresh)
M:On("SPELLS_CHANGED", mod.Refresh)
M:On("GROUP_ROSTER_UPDATE", mod.Refresh)
M:On("PLAYER_EQUIPMENT_CHANGED", mod.Refresh)
M:Listen("STATUS_CHANGED", mod.Refresh)
