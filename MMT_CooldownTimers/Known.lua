-- MMT Cooldowns: which tracked spells each member hasn't learned yet, so "Hide
-- what you don't have" also hides them on the OTHER clients' bars (a paladin
-- without Divine Shield yet). Spells only (items come and go too often).
--
-- Each client works out its own: the spells of the lists that apply to it whose
-- cooldown the game doesn't know (not learned). Sent once to the team when that
-- changes (login, spells learned / talents, lists changed):
--   MCDK:<id>,<id>,...       (MMT.SendLong: any size; empty = knows them all)
-- plus heartbeat "cdk=<hash of the list>"; a client whose stored hash differs
-- asks once with MCDKQ (whispered, at most once a minute). Kept per character in
-- M.store.unlearned[key] = { ids = { [spellID] = true }, hash }. A member who
-- never sent a list: everything shows.

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

-- this character's tracked spells it hasn't learned: sorted spell IDs, or nil
-- while spell data is still loading (then nothing is claimed)
function mod.OwnUnlearned()
    local own = MMT.PlayerFull()
    if not own then return nil end
    local ids, seen = {}, {}
    for _, e in ipairs(mod.EntriesFor(own)) do
        if e.t == "s" and not seen[e.id] then
            seen[e.id] = true
            local name = mod.SpellName(e.id)
            if name and not mod.KnowsSpell(e.id, name) then ids[#ids + 1] = e.id end
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
    return ids and Text(ids) or nil
end

M:Heartbeat("cdk", function()
    local text = sentText or OwnText()
    return text and Hash(text) or nil
end)

local function Send(target)
    local text = OwnText()
    if not text then return end
    sentText = text
    MMT.SendLong("MCDK:" .. text, target, "BULK")
end

-- after login, learning spells, talents or list changes: tell the team if it changed
local pending = false
function mod.KnownCheck()
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        if not M.enabled then return end
        local text = OwnText()
        if text and text ~= sentText then Send() end
    end)
end

M:On("SPELLS_CHANGED", mod.KnownCheck)
M:On("PLAYER_ENTERING_WORLD", mod.KnownCheck)

-- is spell entry e one member key hasn't learned (as their client told us)?
function mod.Unlearned(key, e)
    if e.t ~= "s" then return false end
    local rec = Store()[key]
    return rec and rec.ids and rec.ids[e.id] and true or false
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local asked = {}

M:Listen("XP_RECEIVED", function(key, sender, status)
    if MMT.IsSelf(key) then return end
    local hash = tonumber(status and status.ext and status.ext.cdk)
    if not hash then return end
    local rec = Store()[key]
    if rec and rec.hash == hash then return end
    if asked[key] and GetTime() - asked[key] < 60 then return end
    asked[key] = GetTime()
    MMT.SendAddon("MCDKQ", "WHISPER", sender)
end)

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "MCDKQ" then Send(sender) return end
    local list = text:match("^MCDK:([%d,]*)$")
    if not list then return end
    local ids = {}
    for id in list:gmatch("%d+") do ids[tonumber(id)] = true end
    Store()[key] = { ids = ids, hash = Hash(list) }
    mod.Refresh()
end)
