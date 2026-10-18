-- MMT Cooldowns: who used what.
--
-- Team members: SPELL_CAST_SUCCESS in the combat log starts the entry's
-- cooldown with the duration from the list. Spells like Nature's Swiftness
-- start when their buff fades (SPELL_AURA_REMOVED); until then they glow.
-- The combat log only reaches as far as the game shows it (roughly the same
-- zone and range), and nothing is sent between the clients for this.
--
-- Your own character: the game's cooldown API, exact and with talents.

local _, mod = ...
local MMT = MMT
local M = mod.M

local GCD = 1.6
local PENDING_MAX = 120   -- a buff that never faded in our log: start the cooldown anyway

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
-- Combat log names -> team keys (cached per GUID)
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

local function EntryForMember(key, name)
    local list = index[name]
    if not list then return nil end
    local m = MMT.db.team[key]
    local class = m and m.class
    for _, e in ipairs(list) do
        for _, c in ipairs({ class, "ALL" }) do
            local l = c and M.db.lists[c]
            if l then for _, x in ipairs(l) do if x == e then return e end end end
        end
    end
end

local PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

M:On("COMBAT_LOG_EVENT_UNFILTERED", function()
    local _, event, _, guid, name, flags, _, destGUID, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()
    if event ~= "SPELL_CAST_SUCCESS" and event ~= "SPELL_AURA_REMOVED" then return end
    if not index[spellName] or not flags or bit.band(flags, PLAYER) == 0 then return end
    local key = KeyOf(guid, name)
    if not key or MMT.IsSelf(key) then return end
    local e = EntryForMember(key, spellName)
    if not e then return end
    local ek = mod.EntryKey(e)
    mod.cds[key] = mod.cds[key] or {}
    local cur = mod.cds[key][ek]

    if event == "SPELL_AURA_REMOVED" then
        -- buff of an "after buff" spell faded on its caster: the cooldown starts now
        if cur and cur.pending and destGUID == guid then
            mod.cds[key][ek] = { start = GetTime(), dur = e.cd or 0 }
            mod.Refresh()
        end
        return
    end

    if e.t == "i" then
        M.store.seen = M.store.seen or {}
        M.store.seen[key] = M.store.seen[key] or {}
        M.store.seen[key][ek] = true
    end
    if mod.IsAfterBuff(spellName) then
        mod.cds[key][ek] = { pending = GetTime(), dur = e.cd or 0 }
    else
        mod.cds[key][ek] = { start = GetTime(), dur = e.cd or 0 }
    end
    M:Debug("%s used %s", MMT.Repr(key), spellName)
    mod.Refresh()
end)

---------------------------------------------------------------------------
-- State of one entry for one member: state, start, duration
---------------------------------------------------------------------------
local function OwnState(e)
    local start, dur, enabled
    if e.t == "s" then
        local name = mod.SpellName(e.id)
        if not name then return nil end
        start, dur, enabled = GetSpellCooldown(name)
        if start == nil then return nil end   -- not known by this character
    else
        local count = (C_Item and C_Item.GetItemCount or GetItemCount)(e.id)
        local equipped = (C_Item and C_Item.IsEquippedItem or IsEquippedItem)(e.id)
        if (count or 0) == 0 and not equipped then return nil end
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        start, dur, enabled = fn(e.id)
    end
    if enabled == 0 or enabled == false then return "active" end
    if start and start > 0 and dur and dur > GCD then return "cd", start, dur end
    return "ready"
end

-- returns state ("ready" | "cd" | "active") or nil when the entry isn't shown for this member
function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "cd", mod.testUntil - 10, 10 end
    if MMT.IsSelf(key) then return OwnState(e) end
    local ek = mod.EntryKey(e)
    if e.t == "i" and M.db.itemsOnlyWhenSeen then
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
