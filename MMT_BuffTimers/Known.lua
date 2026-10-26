-- MMT Buffs: which tracked buffs each member hasn't learned yet, so "Hide buffs
-- nobody has learned" hides them: a self-buff on the member's own row (Inner
-- Fire, a seal, an armor), and a buff cast on others (Fortitude, Blessings, ...)
-- when no one of that class who is here has learned it. Like Cooldown Timers'
-- Known.lua.
--
-- Only CLASS spells count: the spells of this character's class presets plus its
-- casters (Casters.lua) - a flask, food or world buff in a class list is never
-- "unlearned". Each client works out its own (any rank counts: the game knows a
-- spell by name only when the character has learned it) and sends it once when it
-- changes (login, spells learned / talents, lists changed):
--   MBFK:<id>,<id>,...       (MMT.SendLong: any size; empty = knows them all)
-- plus heartbeat "bfk=<hash of the list>"; a client whose stored hash differs asks
-- once with MBFKQ (whispered, at most once a minute). Kept per character in
-- M.store.unlearned[key] = { ids = { [spellID] = true }, hash }, matched by NAME.
-- A member who never sent a list: everything shows.

local _, mod = ...
local MMT = MMT
local M = mod.M

local function Store()
    M.store.unlearned = M.store.unlearned or {}
    return M.store.unlearned
end

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- names of the spells of a class (its presets and its casters list)
local classNames = {}
local ownNames    -- [buff name] = true: our own unlearned ones (worked out with OwnText)
local function ClassSpells(class)
    local t = classNames[class]
    if t and t.complete then return t end
    t = { complete = true }
    local function Add(id)
        local name = mod.SpellInfo(id)
        if name then t[mod.Canonical(name)] = true else t.complete = false end
    end
    for _, p in ipairs(mod.PRESETS or {}) do
        if p.group == class then
            for _, e in ipairs(p.entries) do if e.id then Add(e.id) end end
        end
    end
    for _, id in ipairs(mod.CASTERS and mod.CASTERS[class] or {}) do Add(id) end
    classNames[class] = t
    return t
end

-- this character's tracked class buffs it hasn't learned: sorted spell IDs
function mod.OwnUnlearned()
    local _, class = UnitClass("player")
    if not class then return nil end
    local mine = ClassSpells(class)
    local ids, seen = {}, {}
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do
            local name = e.id and mod.BuffName(e)
            if name and mine[name] and not seen[name] then
                seen[name] = true
                local own = mod.SpellInfo(e.id)
                if own and mod.SpellCooldown(own) == nil then ids[#ids + 1] = e.id end
            end
        end
    end
    table.sort(ids)
    return ids
end

local function Text(ids)
    local t = {}
    for i, id in ipairs(ids) do t[i] = tostring(id) end
    return table.concat(t, ",")
end

local sentText    -- what the team has from us
local function OwnText()
    local ids = mod.OwnUnlearned()
    if not ids then return nil end
    ownNames = {}
    for _, id in ipairs(ids) do
        local name = mod.SpellInfo(id)
        if name then ownNames[mod.Canonical(name)] = true end
    end
    return Text(ids)
end

M:Heartbeat("bfk", function()
    local text = sentText or OwnText()
    return text and Hash(text) or nil
end)

local function Send(target)
    local text = OwnText()
    if not text then return end
    sentText = text
    MMT.SendLong("MBFK:" .. text, target, "BULK")
end

-- after login, learning spells, talents or list changes: tell the team if it changed
local pending = false
-- spells learned, lists changed: names worked out again
function mod.KnownReset()
    classNames, ownNames = {}, nil
end

function mod.KnownCheck()
    mod.KnownReset()
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        if not M.enabled then return end
        local text = OwnText()
        if text and text ~= sentText then Send() end
        mod.Refresh()
    end)
end

M:On("SPELLS_CHANGED", mod.KnownCheck)
M:On("PLAYER_ENTERING_WORLD", mod.KnownCheck)

local namesOf = setmetatable({}, { __mode = "k" })   -- [stored record] = { [buff name] = true }

-- has member key NOT learned buff entry e (as their client told us)? Never in the preview.
function mod.Unlearned(key, e)
    if mod.preview or not e.id then return false end
    local name = mod.BuffName(e)
    if not name then return false end
    if MMT.IsSelf(key) then
        if not ownNames then OwnText() end
        return ownNames and ownNames[name] or false
    end
    local rec = Store()[key]
    if not (rec and rec.ids) then return false end
    local names = namesOf[rec]   -- worked out once per received list (not saved)
    if not names or not names.complete then
        names = { complete = true }
        for id in pairs(rec.ids) do
            local n = mod.SpellInfo(id)
            if n then names[mod.Canonical(n)] = true else names.complete = false end
        end
        namesOf[rec] = names
    end
    return names[name] or false
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local asked = {}

M:Listen("XP_RECEIVED", function(key, sender, status)
    if MMT.IsSelf(key) then return end
    local hash = tonumber(status and status.ext and status.ext.bfk)
    if not hash then return end
    local rec = Store()[key]
    if rec and rec.hash == hash then return end
    if asked[key] and GetTime() - asked[key] < 60 then return end
    asked[key] = GetTime()
    MMT.SendAddon("MBFKQ", "WHISPER", sender)
end)

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "MBFKQ" then Send(sender) return end
    local list = text:match("^MBFK:([%d,]*)$")
    if not list then return end
    local ids = {}
    for id in list:gmatch("%d+") do ids[tonumber(id)] = true end
    Store()[key] = { ids = ids, hash = Hash(list) }
    mod.Refresh()
end)
