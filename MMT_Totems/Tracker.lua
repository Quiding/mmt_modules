-- MMT Totems: which totems are down.
--
-- Your own: GetTotemInfo, exact. Other shamans: this client doesn't let
-- addons read the combat log, so each client tells the team when ITS
-- totems change - one short message per totem dropped or gone, nothing
-- periodic:
--   MTT:<slot>:<remaining>/<duration>:<totem name>   totem down
--   MTT:<slot>:0                                      slot empty
-- Group members' totem casts (UNIT_SPELLCAST_SUCCEEDED) are used too, so a
-- shaman without this module still shows up while in your group.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.active = {}   -- [teamKey][element] = { name, icon, start, dur }
mod.last = {}     -- [teamKey][element] = { name, icon }  (last totem used)

local function Remember(key, element, name, icon)
    mod.last[key] = mod.last[key] or {}
    mod.last[key][element] = { name = name, icon = icon }
end

-- active totem of a member: name, icon, start, duration (nil if none)
function mod.ActiveTotem(key, element)
    local now = GetTime()
    if mod.testUntil and now < mod.testUntil then
        local id = mod.Selected(key, element)
        return "Test", mod.TotemIcon(id) or mod.PRESET_ICON, mod.testUntil - 10, 10
    end
    if MMT.IsSelf(key) then
        local have, name, start, dur, icon = GetTotemInfo(mod.TOTEM_SLOT[element])
        if MMT.IsSecret(have) or MMT.IsSecret(start) or MMT.IsSecret(dur) or MMT.IsSecret(name) then
            local a = mod.active[key] and mod.active[key][element]   -- hidden right now: last known
            if a and a.start + a.dur > now then return a.name, a.icon, a.start, a.dur end
            return nil
        end
        if have and name and name ~= "" and dur and dur > 0 and start + dur > now then
            mod.active[key] = mod.active[key] or {}
            mod.active[key][element] = { name = name, icon = icon, start = start, dur = dur }
            Remember(key, element, name, icon)
            return name, icon, start, dur
        end
        return nil
    end
    local a = mod.active[key] and mod.active[key][element]
    if a and a.start + a.dur > now then return a.name, a.icon, a.start, a.dur end
end

function mod.LastTotem(key, element)
    local l = mod.last[key] and mod.last[key][element]
    if l then return l.name, l.icon end
end

local function SetActive(key, element, name, rem, dur)
    local id = mod.TotemByName(name)
    local icon = mod.TotemIcon(id) or mod.PRESET_ICON
    mod.active[key] = mod.active[key] or {}
    mod.active[key][element] = { name = name, icon = icon, start = GetTime() - (dur - rem), dur = dur }
    Remember(key, element, name, icon)
end

---------------------------------------------------------------------------
-- Own totems -> one message per change
---------------------------------------------------------------------------
local sent = {}   -- [slot] = start time we told the team about (false = empty)

local function ReportSlot(slot)
    local have, name, start, dur = GetTotemInfo(slot)
    if MMT.IsSecret(have) or MMT.IsSecret(start) or MMT.IsSecret(dur) or MMT.IsSecret(name) then return end
    local up = have and name and name ~= "" and dur and dur > 0 and start + dur > GetTime()
    if up then
        if sent[slot] ~= start then
            sent[slot] = start
            MMT.SendToTeam(("MTT:%d:%.1f/%.1f:%s"):format(slot, start + dur - GetTime(), dur, name), true)
        end
    elseif sent[slot] then
        sent[slot] = false
        MMT.SendToTeam(("MTT:%d:0"):format(slot), true)
    end
end

M:On("PLAYER_TOTEM_UPDATE", function(slot)
    if select(2, UnitClass("player")) ~= "SHAMAN" then return end
    if slot then ReportSlot(slot) else for s = 1, 4 do ReportSlot(s) end end
    mod.UpdateIcons()
    mod.UpdateSecure()
end)

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local slot, data = text:match("^MTT:(%d):(.+)$")
    if not slot or MMT.IsSelf(key) then return end
    local element = mod.SLOT_ELEMENT[tonumber(slot)]
    if not element then return end
    if data == "0" then
        if mod.active[key] then mod.active[key][element] = nil end
    else
        local rem, dur, name = data:match("^([%d%.]+)/([%d%.]+):(.+)$")
        rem, dur = tonumber(rem), tonumber(dur)
        if not (rem and dur and dur > 0) then return end
        SetActive(key, element, name, rem, dur)
    end
    mod.UpdateIcons()
end)

---------------------------------------------------------------------------
-- Group members' casts
---------------------------------------------------------------------------
local function GroupUnit(unit)
    return unit and (unit:find("^party%d") or unit:find("^raid%d")) and true or false
end

M:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if not GroupUnit(unit) or not spellID or MMT.IsSecret(spellID) then return end
    local name = mod.SpellInfo(spellID)
    if not name or MMT.IsSecret(name) then return end
    local _, _, key = MMT.SplitUnit(unit)
    key = key and MMT.Resolve(key)
    if not key or MMT.IsSelf(key) then return end
    if mod.RECALL[name] then
        mod.active[key] = {}
    else
        local _, element = mod.TotemByName(name)
        if not element then return end
        local dur = mod.TotemDuration(name)
        SetActive(key, element, name, dur, dur)
    end
    mod.UpdateIcons()
end)

function mod.Test()
    mod.testUntil = GetTime() + 10
    mod.UpdateIcons()
    C_Timer.After(10.1, function() mod.UpdateIcons() end)
end
