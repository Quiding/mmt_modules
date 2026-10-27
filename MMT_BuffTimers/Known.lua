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
--   MBFK:<id>,<id>,...[#<pattern>#<pattern>...]   (MMT.SendLong: any size; empty = knows them all)
-- Name patterns ("Aspect of the *", "Seal of *", totem buffs): learned when a spell in
-- the spellbook matches (learned ones only, not the ones it lists for later levels);
-- checked for the patterns in this character's own lists and those its class casts.
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
local book        -- the spellbook's learned spell names (false: can't be read)
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

-- names of the spells this character has learned, from the spellbook; nil if it can't be read
local Spellbook
function mod.SpellbookCount() local s = Spellbook() return s and #s or 0 end
Spellbook = function()
    if book ~= nil then return book or nil end
    book = false
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemType
        and Enum and Enum.SpellBookItemType and Enum.SpellBookSpellBank) then return nil end
    local bank, SPELL = Enum.SpellBookSpellBank.Player, Enum.SpellBookItemType.Spell
    local n = MMT.Safe(SB.GetNumSpellBookSkillLines)
    if type(n) ~= "number" then return nil end
    local names = {}
    for li = 1, n do
        local line = MMT.Safe(SB.GetSpellBookSkillLineInfo, li)
        if type(line) == "table" and line.itemIndexOffset and line.numSpellBookItems then
            for si = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local kind, actionID, spellID = MMT.Safe(SB.GetSpellBookItemType, si, bank)
                spellID = spellID or actionID   -- like EllesmereUI: some clients give only the action ID
                if kind == SPELL and type(spellID) == "number" then
                    local name = mod.SpellInfo(spellID)
                    if type(name) == "string" then names[#names + 1] = name end
                end
            end
        end
    end
    if #names == 0 then return nil end
    book = names
    return book
end

-- is a spell of this name (any rank) in the spellbook? (false when it can't be read)
local bookSet
local function InBook(name)
    local spells = Spellbook()
    if not spells then return false end
    if not bookSet or bookSet.of ~= spells then
        bookSet = { of = spells }
        for _, n in ipairs(spells) do bookSet[mod.Canonical(n)] = true end
    end
    return bookSet[name] or false
end

-- weapon enchant entries (Weapons.lua): a shaman needs an imbue spell, a rogue Poisons
-- (level 20); other classes can always use an oil or a stone. Shared as "#@imbue".
local IMBUE = "@imbue"
local IMBUES = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }
function mod.OwnCanImbue()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" and class ~= "ROGUE" then return true end
    local spells = Spellbook()
    if not spells then return true end   -- can't tell: show it
    for _, name in ipairs(spells) do
        if class == "ROGUE" and (name == "Poisons" or name:find("Poison", 1, true)) then return true end
        if class == "SHAMAN" then
            for _, imbue in ipairs(IMBUES) do if name == imbue then return true end end
        end
    end
    return class == "ROGUE" and mod.KnowsSpell(2842, nil) or false   -- Poisons (the skill)
end

-- name patterns this character hasn't learned: those in its own lists (not the All
-- bar) and those its class casts (totems), when no learned spell matches
function mod.OwnUnlearnedPatterns()
    local spells = Spellbook()
    if not spells then return {} end
    local _, class = UnitClass("player")
    local own = MMT.PlayerFull and MMT.PlayerFull()
    local candidates, seen = {}, {}
    local function Add(e)
        if mod.IsPattern(e) and not seen[e.name] then seen[e.name] = true; candidates[#candidates + 1] = e end
    end
    for _, lk in ipairs(own and mod.ListKeysFor(own, false) or {}) do
        for _, e in ipairs(M.db.lists[lk] or {}) do Add(e) end
    end
    for _, list in pairs(M.db.lists or {}) do
        for _, e in ipairs(list) do if e.caster == class then Add(e) end end
    end
    local out = {}
    for _, e in ipairs(candidates) do
        local learned = false
        for _, name in ipairs(spells) do
            if mod.Matches(e, name) then learned = true break end
        end
        if not learned then out[#out + 1] = e.name end
    end
    table.sort(out)
    return out
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
                if own and not mod.KnowsSpell(e.id, own) and not InBook(name) then ids[#ids + 1] = e.id end
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
    local text = Text(ids)
    for _, pattern in ipairs(mod.OwnUnlearnedPatterns()) do
        ownNames[pattern] = true
        text = text .. "#" .. pattern:gsub("#", "")
    end
    if not mod.OwnCanImbue() then
        ownNames[IMBUE] = true
        text = text .. "#" .. IMBUE
    end
    return text
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
    classNames, ownNames, book = {}, nil, nil
    if mod.BlessingsReset then mod.BlessingsReset() end
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
    if mod.preview or not (e.id or mod.IsPattern(e) or mod.IsWeapon(e)) then return false end
    local name = mod.IsWeapon(e) and IMBUE or mod.BuffName(e)
    if not name then return false end
    if MMT.IsSelf(key) then
        if not ownNames then OwnText() end
        return ownNames and ownNames[name] or false
    end
    local rec = Store()[key]
    if not (rec and rec.ids) then return false end
    if mod.IsPattern(e) or mod.IsWeapon(e) then return rec.patterns and rec.patterns[name] or false end
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
    local list = text:match("^MBFK:(.*)$")
    if not list then return end
    local idPart = list:match("^([%d,]*)")
    local ids, patterns = {}, {}
    for id in idPart:gmatch("%d+") do ids[tonumber(id)] = true end
    for pattern in list:gmatch("#([^#]+)") do patterns[pattern] = true end
    Store()[key] = { ids = ids, patterns = next(patterns) and patterns or nil, hash = Hash(list) }
    mod.Refresh()
end)
