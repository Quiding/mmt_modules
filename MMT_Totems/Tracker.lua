-- MMT Totems: which totems are down.
--
-- Your own: GetTotemInfo, exact. Other shamans: this client doesn't let
-- addons read the combat log, so each client tells the team when ITS
-- totems change - one short message per totem dropped or gone, nothing
-- periodic:
--   MTT:<slot>:<remaining>/<duration>:<totem name>   totem down
--   MTT:<slot>:0                                      slot empty
--   MTTR                                              "which totems are down?" - whispered to each
--                                                     member on their first heartbeat after login /
--                                                     reload; answered with an MTT per totem (whisper)
-- Group members' totem casts (UNIT_SPELLCAST_SUCCEEDED) are used too, so a
-- shaman without this module still shows up while in your group.
-- In combat this client hides the shaman's own GetTotemInfo (secret values), so
-- the totem message also goes out from the shaman's own cast (OwnCast), and once
-- the values can be read again the slots are reported with their exact times.

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
            mod.LearnDuration(name, dur)
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
-- the last totem messages sent / received, for /mmtt check
local sendLog, recvLog = {}, {}
local function Log(list, text)
    table.insert(list, 1, ("%.1f %s"):format(GetTime(), text))
    list[9] = nil
end
local SendToTeam = function(msg, ...)
    Log(sendLog, msg)
    return MMT.SendToTeam(msg, ...)
end

local sent = {}   -- [slot] = start time we told the team about (false = empty, "cast" = from the cast)
local hidden = false   -- a slot couldn't be read (secret): read them all again later

local function ReportSlot(slot)
    local have, name, start, dur = GetTotemInfo(slot)
    if MMT.IsSecret(have) or MMT.IsSecret(start) or MMT.IsSecret(dur) or MMT.IsSecret(name) then
        hidden = true
        return
    end
    local up = have and name and name ~= "" and dur and dur > 0 and start + dur > GetTime()
    if up then
        mod.LearnDuration(name, dur)
        if sent[slot] ~= start then
            sent[slot] = start
            SendToTeam(("MTT:%d:%.1f/%.1f:%s"):format(slot, start + dur - GetTime(), dur, name), true)
        end
    elseif sent[slot] then
        sent[slot] = false
        SendToTeam(("MTT:%d:0"):format(slot), true)
    end
end

M:On("PLAYER_TOTEM_UPDATE", function(slot)
    if select(2, UnitClass("player")) ~= "SHAMAN" then return end
    if slot then ReportSlot(slot) else for s = 1, 4 do ReportSlot(s) end end
    mod.UpdateIcons()
    mod.UpdateSecure()
end)

-- the slots couldn't be read (in combat): again once they can, so a totem gone early
-- (killed, out of range) or the exact time reaches the team too
local function ReportHidden()
    if not hidden or select(2, UnitClass("player")) ~= "SHAMAN" then return end
    hidden = false
    for s = 1, 4 do ReportSlot(s) end
    mod.UpdateIcons()
end
M:On("PLAYER_REGEN_ENABLED", ReportHidden)
C_Timer.NewTicker(5, function() if hidden and M.enabled then ReportHidden() end end)

-- one totem spell of this shaman (a cast, or one totem of a Call): told to the team
-- right away, with its full duration - GetTotemInfo may be hidden now (combat)
local function OwnTotem(name)
    local _, element = mod.TotemByName(name)
    local slot = element and mod.TOTEM_SLOT[element]
    if not slot then return end
    -- readable now (out of combat): PLAYER_TOTEM_UPDATE reports it exactly, no second message
    local have, _, start, tdur = GetTotemInfo(slot)
    if not (MMT.IsSecret(have) or MMT.IsSecret(start) or MMT.IsSecret(tdur)) then return end
    local dur = mod.TotemDuration(name)
    local key = mod.OwnKey()
    if key then SetActive(key, element, name, dur, dur) end
    sent[slot] = "cast"
    hidden = true   -- the real start time follows once it can be read
    SendToTeam(("MTT:%d:%.1f/%.1f:%s"):format(slot, dur, dur, name), true)
    M:Debug("own totem cast: %s (slot %d)", name, slot)
end

local function OwnCast(spellID)
    if select(2, UnitClass("player")) ~= "SHAMAN" or not spellID or MMT.IsSecret(spellID) then return end
    local name = mod.SpellInfo(spellID)
    if not name or MMT.IsSecret(name) then return end
    if mod.RECALL[name] then
        local key = mod.OwnKey()
        if key then mod.active[key] = {} end
        for slot = 1, 4 do
            if sent[slot] then sent[slot] = false; SendToTeam(("MTT:%d:0"):format(slot), true) end
        end
    elseif mod.TotemByName(name) then
        OwnTotem(name)
    else
        -- a Call: its totems (what this client put on its Blizzard totem bar)
        local key = mod.OwnKey()
        for call, c in ipairs(mod.CALLS or {}) do
            if c.name == name and key then
                for _, el in ipairs(mod.ELEMENTS) do
                    local id = mod.CallTotem(key, call, el)
                    local tname = id and mod.TotemName(id)
                    if tname then OwnTotem(tname) end
                end
            end
        end
    end
    mod.UpdateIcons()
end
mod.OwnCast = OwnCast   -- (tests)

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local slot, data = text:match("^MTT:(%d):(.+)$")
    if not slot or MMT.IsSelf(key) then return end
    Log(recvLog, tostring(key) .. " " .. text)
    local element = mod.SLOT_ELEMENT[tonumber(slot)]
    if not element then return end
    if data == "0" then
        if mod.active[key] then mod.active[key][element] = nil end
    else
        local rem, dur, name = data:match("^([%d%.]+)/([%d%.]+):(.+)$")
        rem, dur = tonumber(rem), tonumber(dur)
        if not (rem and dur and dur > 0) then return end
        -- read from the game on their side (not just cast: then the time left is the whole duration)
        if rem < dur - 1 then mod.LearnDuration(name, dur) end
        SetActive(key, element, name, rem, dur)
    end
    mod.UpdateIcons()
end)

---------------------------------------------------------------------------
-- After login / reload: other shamans' totems aren't in memory any more
--  - a reload keeps them: saved on logout with the real clock (time()), put back on enable
--  - and each member is asked once, when their first heartbeat arrives (whisper MTTR)
---------------------------------------------------------------------------
-- this character's totems that are down, each as one MTT whispered to target
function mod.AnnounceTotems(target)
    if select(2, UnitClass("player")) ~= "SHAMAN" then return 0 end
    local n = 0
    for slot = 1, 4 do
        local have, name, start, dur = GetTotemInfo(slot)
        if not (MMT.IsSecret(have) or MMT.IsSecret(start) or MMT.IsSecret(dur) or MMT.IsSecret(name))
            and have and name and name ~= "" and dur and dur > 0 and start + dur > GetTime() then
            MMT.SendAddon(("MTT:%d:%.1f/%.1f:%s"):format(slot, start + dur - GetTime(), dur, name), "WHISPER", target)
            n = n + 1
        end
    end
    return n
end

M:On("PLAYER_LOGOUT", function()
    local now, clock, saved = GetTime(), time(), {}
    for key, list in pairs(mod.active) do
        if not MMT.IsSelf(key) then
            for element, a in pairs(list) do
                local rem = a.start + a.dur - now
                if rem > 1 then
                    saved[key] = saved[key] or {}
                    saved[key][element] = { name = a.name, rem = rem, dur = a.dur, at = clock }
                end
            end
        end
    end
    M.store.running = next(saved) and saved or nil
end)

function mod.RestoreRunning()
    local saved = M.store.running
    M.store.running = nil
    if type(saved) ~= "table" then return 0 end
    local clock, n = time(), 0
    for key, list in pairs(saved) do
        if not MMT.IsSelf(key) then
            for element, s in pairs(list) do
                local rem = (tonumber(s.rem) or 0) - (clock - (tonumber(s.at) or clock))
                local dur = tonumber(s.dur)
                if rem > 0 and dur and dur > 0 and type(s.name) == "string"
                    and not (mod.active[key] and mod.active[key][element]) then
                    SetActive(key, element, s.name, rem, dur)
                    n = n + 1
                end
            end
        end
    end
    return n
end

local asked = {}   -- [key] = true: asked this session
M:Listen("XP_RECEIVED", function(key, sender)
    if asked[key] or MMT.IsSelf(key) or not sender then return end
    asked[key] = true
    MMT.SendAddon("MTTR", "WHISPER", sender)
end)

local answered = {}
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if text ~= "MTTR" or MMT.IsSelf(key) then return end
    if answered[key] and GetTime() - answered[key] < 10 then return end
    answered[key] = GetTime()
    mod.AnnounceTotems(sender)
end)

---------------------------------------------------------------------------
-- Group members' casts
---------------------------------------------------------------------------
local function GroupUnit(unit)
    return unit and (unit:find("^party%d") or unit:find("^raid%d")) and true or false
end

M:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" then OwnCast(spellID) return end
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

-- /mmtt check: what this client reads, sent, received and shows
function mod.Check()
    local P = function(...) MMT.Print(...) end
    P("Totems check (now %.1f), version %s", GetTime(), tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("MMT_Totems", "Version")))
    if select(2, UnitClass("player")) == "SHAMAN" then
        for s = 1, 4 do
            local have, name, start, dur = GetTotemInfo(s)
            local secret = MMT.IsSecret(have) or MMT.IsSecret(name) or MMT.IsSecret(start) or MMT.IsSecret(dur)
            if secret then P(" own slot %d: HIDDEN (secret)", s)
            else P(" own slot %d: %s %s start=%s dur=%s told=%s", s, tostring(have), tostring(name), tostring(start), tostring(dur), tostring(sent[s])) end
        end
        P(" waiting to read again: %s, in combat: %s", tostring(hidden), tostring(InCombatLockdown()))
    end
    P(" sent (newest first): %s", #sendLog > 0 and table.concat(sendLog, " | ") or "nothing")
    P(" received: %s", #recvLog > 0 and table.concat(recvLog, " | ") or "nothing")
    -- why a team shaman has a bar or not (a bar needs: online by their heartbeats, or in the group)
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) and mod.IsShaman(key) then
            local st = MMT.status and MMT.status[key]
            local first = MMT.FirstName(key)
            P(" team shaman %s: online=%s (last heard %s s ago), in group=%s, onlyOnline=%s", first,
                tostring(MMT.IsOnline(key)), st and st.last and ("%.0f"):format(GetTime() - st.last) or "never",
                tostring((UnitInParty(first) or UnitInRaid(first)) and true or false), tostring(M.db.onlyOnline))
        end
    end
    for _, key in ipairs(mod.Shamans()) do
        local parts = {}
        for _, el in ipairs(mod.ELEMENTS) do
            local name, _, start, dur = mod.ActiveTotem(key, el)
            parts[#parts + 1] = el .. "=" .. (name and ("%s %.0fs"):format(name, start + dur - GetTime()) or "-")
        end
        local bar = mod.bars and mod.bars[key]
        P(" %s (bar %s): %s", MMT.FirstName(key), bar and (bar:IsShown() and "shown" or "hidden") or "none", table.concat(parts, ", "))
    end
    local ok, err = pcall(mod.UpdateIcons)
    if not ok then P(" |cffff5555UpdateIcons error: %s|r", tostring(err)) end
end

function mod.Test()
    mod.testUntil = GetTime() + 10
    mod.UpdateIcons()
    C_Timer.After(10.1, function() mod.UpdateIcons() end)
end
