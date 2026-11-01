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
local presetIcons   -- [pattern] = spell ID of its icon, from the presets (totems)
function mod.BuildIndex()
    if mod.TrackedReset then mod.TrackedReset() end
    if not presetIcons then
        presetIcons = {}
        for _, p in ipairs(mod.PRESETS or {}) do
            for _, e in ipairs(p.entries) do
                if mod.IsPattern(e) and e.icon then presetIcons[e.name] = e.icon end
            end
        end
    end
    local missing = false
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            -- a pattern taken from a preset before presets had icons: the preset's icon
            if mod.IsPattern(e) and not e.icon and presetIcons[e.name] then e.icon = presetIcons[e.name] end
            if e.icon and not requested[e.icon] then
                requested[e.icon] = true
                missing = true
                if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, e.icon) end
            end
            if e.id and not mod.BuffName(e) and not requested[e.id] then
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
-- the team key of a unit; the last one read is kept per unit, as in combat the
-- game can hide the unit's name too
local keyOf = {}
-- the group unit of a team member ("player", "party2", ...; Live.lua)
function mod.UnitOf(key)
    for unit, k in pairs(keyOf) do
        if k == key and UnitExists(unit) then return unit end
    end
end
local function UnitKey(unit)
    local ok, _, _, key = pcall(MMT.SplitUnit, unit)
    key = ok and key and not MMT.IsSecret(key) and MMT.Resolve(key) or nil
    if key then keyOf[unit] = key return key end
    if mod.AurasHidden and mod.AurasHidden() then return keyOf[unit] end
    return nil
end

-- In combat the game hides aura data ("secret"); new buffs can't be seen then.
-- A unit read as hidden keeps its last buffs (ones whose time ran out show as
-- missing, see State) and is read again every second until it's readable, and
-- the whole group once combat ends: no UNIT_AURA may come after it.
local hidden = {}   -- [unit] = true: last read was hidden
local ticker

local seenDur = {}  -- [buff name] = its length last seen readable (for the casts below)

local function Fighting(unit)
    if InCombatLockdown and InCombatLockdown() then return true end
    if not UnitAffectingCombat then return false end
    local ok, c = pcall(UnitAffectingCombat, unit)
    if not ok or MMT.IsSecret(c) then return true end
    return c and true or false
end

-- Spell IDs of the tracked buffs. In combat the game hides the aura LIST, but still
-- answers "does this unit have the aura with spell ID x?" (C_UnitAuras.GetUnitAuraBySpellID,
-- what ForeverAuras does then). So every tracked buff's IDs are learned while readable
-- (each rank, group versions: M.store.auraIds[name] = { [id] = true }, kept across
-- sessions) and asked for one by one while hidden: procs like Flurry, seals and
-- buffs falling off then update live. A buff never seen readable keeps its last state.
local trackedCache = {}   -- [buff name] = true | false
mod.idsGen = 0   -- raised whenever the learned IDs or the lists change (Live.lua caches by it)
function mod.TrackedReset() wipe(trackedCache); mod.idsGen = mod.idsGen + 1 end

local function Tracked(name)
    local v = trackedCache[name]
    if v ~= nil then return v end
    v = false
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            if not mod.IsWeapon(e) then
                if mod.IsPattern(e) then
                    if mod.Matches(e, name) then v = true end
                elseif mod.BuffName(e) == name then v = true end
            end
            if v then break end
        end
        if v then break end
    end
    trackedCache[name] = v
    return v
end

mod.Tracked = Tracked

-- has this entry's buff been seen with a timer (not a permanent aura)?
function mod.Timed(e)
    local timed = M.store.timed
    if not timed then return false end
    if mod.IsPattern(e) then
        for name in pairs(timed) do if mod.Matches(e, name) then return true end end
        return false
    end
    local name = mod.BuffName(e)
    return name and timed[name] or false
end

local function NoteId(name, id)
    if type(id) ~= "number" or not Tracked(name) then return end
    M.store.auraIds = M.store.auraIds or {}
    local ids = M.store.auraIds[name]
    if not ids then ids = {}; M.store.auraIds[name] = ids end
    if not ids[id] then ids[id] = true; mod.idsGen = mod.idsGen + 1 end
end

local function Clean(v)
    if v == nil or MMT.IsSecret(v) then return nil end
    return v
end

local function IsGroupSource(source)
    return type(source) == "string" and (source == "player" or source:find("^party%d") or source:find("^raid%d")) and true or nil
end

-- a buff kept from an earlier read whose time has run out (seen last before the
-- game hid the auras: it fell off since)
local function Expired(a)
    return a.start and a.dur and GetTime() > a.start + a.dur + 0.5 or false
end

-- On Forever the by-ID answer is "nothing" for every aura while they're hidden (the user's
-- probe: Battle Shout on, found 0 in combat, found while readable). So an answer only
-- counts once it found something while hidden at least once this session: until then a
-- "nothing" would wrongly mark every tracked buff missing in combat (0.24.0 did).
local byIdWorks = false

-- the unit's tracked buffs asked for one by one (auras hidden); nil when the game can't
local function ReadByIds(unit, key)
    local known = M.store.auraIds
    if not known or not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return nil end
    if not byIdWorks then
        -- one probe: any tracked buff that unit had before the fight
        for name, o in pairs(mod.auras[key] or {}) do
            local ids = known[name]
            if ids and not Expired(o) then
                for id in pairs(ids) do
                    if mod.AuraBySpellID(unit, id) then byIdWorks = true break end
                end
            end
            if byIdWorks then break end
        end
        if not byIdWorks then return nil end
    end
    local old, t, asked = mod.auras[key] or {}, {}, {}
    for name, ids in pairs(known) do
        if Tracked(name) then
            local a, blocked
            for id in pairs(ids) do
                local r, why = mod.AuraBySpellID(unit, id)
                if r then a = r break end
                if why then blocked = true end
            end
            if not blocked then asked[name] = true end   -- a refused answer: keep what we had
            if a then
                local o = old[name]
                local dur, exp = Clean(a.duration), Clean(a.expirationTime)
                if type(dur) ~= "number" then dur = nil end
                if type(exp) ~= "number" then exp = nil end
                local timed = dur and dur > 0 and exp
                t[name] = { start = timed and (exp - dur) or (o and o.start), dur = timed and dur or (o and o.dur),
                    count = Clean(a.applications) or (o and o.count), icon = Clean(a.icon) or (o and o.icon),
                    raw = Clean(a.name) or (o and o.raw) or name,
                    group = IsGroupSource(Clean(a.sourceUnit)) or (o and o.group) }
            end
        end
    end
    -- buffs we can't ask about (never seen readable): as they were
    for name, o in pairs(old) do
        if not asked[name] and not t[name] then t[name] = o end
    end
    return t
end

local function Hidden(unit, key)
    hidden[unit] = true
    if mod.SetLive and mod.AurasHidden() then mod.SetLive(true) end   -- the game draws them (Live.lua)
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, mod.RetryHidden) end
    local t = ReadByIds(unit, key)
    local changed = t and TrackedChanged(mod.auras[key], t) or false
    if t then mod.auras[key] = t end
    if mod.auras[key] then fromUnit[key] = true end
    return changed
end

-- did anything TRACKED change between two reads of a member? (an aura nobody tracks coming
-- or going - a debuff, a proc - is no reason to redraw every bar)
local function Same(a, b)
    return a.count == b.count and a.dur == b.dur and math.abs((a.start or 0) - (b.start or 0)) < 0.1
end
local function TrackedChanged(old, new)
    if not old then return next(new) ~= nil end
    for name, a in pairs(new) do
        local o = old[name]
        if (not o or not Same(o, a)) and Tracked(name) then return true end
    end
    for name in pairs(old) do
        if not new[name] and Tracked(name) then return true end
    end
    return false
end

-- reads one unit; true when a tracked buff changed
local function ScanUnit(unit)
    local key = UnitKey(unit)
    if not key then return false end
    local t = {}
    for i = 1, 40 do
        local name, icon, count, duration, expiration, source, spellId = mod.Buff(unit, i)
        if name == "secret" then return Hidden(unit, key) end   -- hidden right now (combat)
        if not name then break end
        local raw = name
        name = mod.Canonical(name)   -- Prayer of Fortitude counts as Fortitude, ...
        if raw == name then mod.SeeIcon(name, icon) end   -- for a "?" entry icon (EntryIcon)
        NoteId(name, spellId)
        local start = (duration and duration > 0 and expiration) and (expiration - duration) or nil
        if duration and duration > 0 then
            seenDur[name] = duration
            -- timed buffs, kept across sessions (Live.lua gates their icon on the time left)
            if Tracked(name) then
                M.store.timed = M.store.timed or {}
                M.store.timed[name] = true
            end
        end
        t[name] = { start = start, dur = (duration and duration > 0) and duration or nil, count = count,
            icon = (not MMT.IsSecret(icon)) and icon or nil, raw = raw,
            -- cast by someone in the group (blessings: one per paladin here, Casters.lua)
            group = IsGroupSource(source) }
    end
    -- nothing at all while that unit fights, though it had buffs: the game gave an empty
    -- list instead of hidden values (seen in game: every buff "missing" in combat)
    if next(t) == nil and mod.auras[key] and next(mod.auras[key]) and Fighting(unit) then
        return Hidden(unit, key)
    end
    local changed = TrackedChanged(mod.auras[key], t) or not fromUnit[key]
    mod.auras[key] = t
    fromUnit[key] = true
    hidden[unit] = nil
    if mod.live and not mod.AurasHidden() then mod.SetLive(false) end   -- readable again
    return changed
end

function mod.StopHidden()
    wipe(hidden)
    if ticker then ticker:Cancel(); ticker = nil end
end

-- the units read as hidden, again (ticker while there are any)
local expiredBefore = 0
function mod.RetryHidden()
    local any, changed = false, false
    for unit in pairs(hidden) do
        hidden[unit] = nil
        if UnitExists(unit) and ScanUnit(unit) then changed = true end
        any = any or hidden[unit] or false
    end
    if not any and ticker then ticker:Cancel(); ticker = nil end
    -- a kept buff that ran out meanwhile shows as missing: redraw when that count moves
    local expired = 0
    for _, list in pairs(mod.auras) do
        for _, a in pairs(list) do if Expired(a) then expired = expired + 1 end end
    end
    if expired ~= expiredBefore then expiredBefore, changed = expired, true end
    if changed and M.enabled then mod.Refresh() end
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
    wipe(hidden)
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then ScanUnit(unit) end
    end
    for key in pairs(mod.auras) do if not fromUnit[key] then mod.auras[key] = nil end end
end

M:On("UNIT_AURA", function(unit)
    if unit == "player" or (unit and (unit:find("^party%d") or unit:find("^raid%d"))) then
        local c = collectgarbage("count")
        local changed = ScanUnit(unit)
        if mod.MemTally then mod.MemTally("aura scans", collectgarbage("count") - c) end
        if changed then mod.Refresh() end
    end
end)

-- Buffs a character only ever casts on themself: while their auras are hidden (combat)
-- the cast says it all - which one, when, on whom. A seal lasts 30 s and a new seal
-- replaces the old one (Judgement does NOT use it up on Forever), so its timer stays exact.
local SELF = { "^Seal of ", "^Aspect of the ", "^Battle Shout$", "^Inner Fire$", "^Righteous Fury$",
    "^Lightning Shield$", "^Demon Skin$", "^Demon Armor$", "^Frost Armor$", "^Ice Armor$", "^Mage Armor$" }
local SELF_DUR = { ["^Seal of "] = 30 }   -- before one was ever seen readable

local function SelfBuff(name)
    for _, p in ipairs(SELF) do if name:find(p) then return p end end
end

local function SealsOff(auras)
    for n in pairs(auras) do if n:find("^Seal of ") then auras[n] = nil end end
end

-- a self-cast buff started on a member: replaces their other seals / aspects
local function StartSelf(key, name, dur, icon)
    local auras = key and mod.auras[key]
    if not auras then return end
    local p = SelfBuff(name)
    if not p then return end
    if p == "^Seal of " then SealsOff(auras) end
    if p == "^Aspect of the " then
        for n in pairs(auras) do if n:find(p) then auras[n] = nil end end
    end
    local old = auras[name]
    auras[name] = { start = GetTime(), dur = dur, count = 1, raw = name, group = true,
        icon = (old and old.icon) or icon }
    mod.Refresh()
end

-- buffs the caster gives the whole party at once (the cast refreshes it on everyone read from
-- a group unit; in a raid that's more than the caster's own party - the real read after combat fixes it)
local PARTY_WIDE = { ["^Battle Shout$"] = true }

local function Start(key, name, dur, icon)
    if PARTY_WIDE[SelfBuff(name) or ""] then
        for k in pairs(fromUnit) do StartSelf(k, name, dur, icon) end
    else
        StartSelf(key, name, dur, icon)
    end
end

-- %XX for the characters the message uses
local function Esc(s) return (s:gsub("[%%:]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function mod.SelfCast(unit, spellID)
    if not (hidden[unit] or mod.AurasHidden()) or not spellID or MMT.IsSecret(spellID) then return end   -- readable: UNIT_AURA shows it
    local name = mod.SpellInfo(spellID)
    if not name or MMT.IsSecret(name) then return end
    name = mod.Canonical(name)
    local p = SelfBuff(name)
    if not p then return end
    local dur = seenDur[name] or SELF_DUR[p]
    if not dur then return end
    Start(UnitKey(unit), name, dur, mod.SpellIcon(spellID))
    -- the other clients don't see this cast in combat: one message per own cast
    -- (the user agreed, like Cooldowns' MCDU); only while auras are hidden here
    if unit == "player" then
        local msg = ("MBFC:%s:%d"):format(Esc(name), math.floor(dur + 0.5))
        MMT.SendToTeam(msg, true)
        M:Debug("sent %s", msg)
    end
end

-- MBFC:<buff name>:<seconds> = that member just cast a self buff (in combat on their client)
M:Listen("TEAM_MESSAGE", function(key, _, text)
    local name, dur = text:match("^MBFC:([^:]+):(%d+)$")
    if not name or MMT.IsSelf(key) then return end
    dur = tonumber(dur)
    if not dur or dur <= 0 then return end
    name = Unesc(name)
    -- readable here (not fighting): their unit's own update shows it exactly
    local unit
    for u, k in pairs(keyOf) do if k == key then unit = u end end
    if not mod.AurasHidden() and unit and not hidden[unit] and fromUnit[key] then return end
    Start(key, name, dur)
end)

M:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" or (unit and (unit:find("^party%d") or unit:find("^raid%d"))) then mod.SelfCast(unit, spellID) end
end)

M:On("GROUP_ROSTER_UPDATE", function() wipe(keyOf) mod.ScanGroup() mod.Refresh() end)
M:On("PLAYER_REGEN_ENABLED", function()
    mod.ScanGroup() mod.Refresh()
    C_Timer.After(1, function() if M.enabled then mod.ScanGroup() mod.Refresh() end end)
end)
M:On("PLAYER_ENTERING_WORLD", function() mod.ScanGroup() mod.Refresh() end)
M:On("UNIT_CONNECTION", function() mod.Refresh() end)   -- a group member went offline / came back (Casters.lua)

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

-- mode: nil / false = off, "REAL" = the team as it is, "MIXED" = made-up classes,
-- "ALL" = made-up characters, one of every class (ListKeys.lua)
function mod.SetPreview(mode)
    if mode == true then mode = "REAL" end
    mod.preview = (mode == "REAL" or mode == "MIXED" or mode == "ALL") and mode or nil
    if mod.BuildIndex then mod.BuildIndex() end
    mod.Refresh()
end

-- returns "buff", start, duration, count[, matched name, icon (patterns)]  or
-- "missing"  or nil (member not in the group)
function mod.State(key, e)
    if mod.testUntil and GetTime() < mod.testUntil then return "buff", mod.testUntil - 10, 10, 1 end
    if mod.preview then
        local h = Hash(key .. ":" .. (mod.EntryKey(e) or ""))
        if h % 4 == 0 then return "missing" end
        local dur = (h % 3 + 1) * 600                    -- 10, 20 or 30 minutes
        local left = 60 + h % (dur - 60)                 -- some time left, different per icon
        local now = GetTime()
        return "buff", now - (dur - left), dur, 1
    end
    if mod.IsWeapon(e) then return mod.WeaponState(key, e) end
    local name = mod.BuffName(e)
    if not name then return nil end
    if fromUnit[key] then
        local auras = mod.auras[key] or {}
        if mod.IsPattern(e) then
            -- any matching buff; the one with the most time left, else any
            local best, bestName
            for n, a in pairs(auras) do
                if not Expired(a) and (mod.Matches(e, a.raw or n) or mod.Matches(e, n)) then
                    local left = a.start and a.dur and (a.start + a.dur) or math.huge
                    if not best or left > best[1] then best, bestName = { left, a }, a.raw or n end
                end
            end
            if best then local a = best[2] return "buff", a.start, a.dur, a.count, bestName, a.icon end
            return "missing"
        end
        local a = auras[name]
        if a and not Expired(a) then return "buff", a.start, a.dur, a.count end
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
