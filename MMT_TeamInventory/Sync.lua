-- MMT Team Inventory: sharing the counts with the team (like Item Compare).
--   heartbeat  tiv=<hash of your counts>
--   TIVREQ                 "send me your counts" (whispered when a hash differs)
--   TIVS:<hash>:<CLASS>#<data>  every count of one character (MMT.SendLong: any size)
--   TIVD:<hash>#<changes>  only what changed ("b13446=4;k6948=0"), to the team
-- data = "b=13446x4,6948x1;k=...;m=...;e=..." (b bags, k bank, m mail, e equipped)

local _, mod = ...
local MMT = MMT
local M = mod.M

local REQUEST_COOLDOWN = 60
local MAX_DELTA = 240

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
local function SortedIDs(t)
    local ids = {}
    for id, n in pairs(t or {}) do if n > 0 then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end

-- rec (or a part of it) -> text, the same text for the same counts
function mod.Encode(rec)
    local parts = {}
    for _, p in ipairs(mod.PLACES) do
        if rec[p] then
            local items = {}
            for _, id in ipairs(SortedIDs(rec[p])) do items[#items + 1] = id .. "x" .. rec[p][id] end
            parts[#parts + 1] = p .. "=" .. table.concat(items, ",")
        end
    end
    return table.concat(parts, ";")
end

function mod.Decode(text)
    local rec = { b = {}, k = {}, m = {}, e = {} }
    for p, items in (text or ""):gmatch("(%a)=([^;]*)") do
        if rec[p] then
            for id, n in items:gmatch("(%d+)x(%d+)") do rec[p][tonumber(id)] = tonumber(n) end
        end
    end
    return rec
end

function mod.Hash(rec)
    local s = mod.Encode({ b = rec.b or {}, k = rec.k or {}, m = rec.m or {}, e = rec.e or {} })
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local changes = {}   -- "<place><itemID>" = new count, since the last send

function mod.NoteChange(place, old, new)
    for id, n in pairs(new) do if old[id] ~= n then changes[place .. id] = n end end
    for id in pairs(old) do if not new[id] then changes[place .. id] = 0 end end
end

function mod.SendSnapshot(target)
    local rec = mod.Own()
    if not rec then return end
    rec.hash = rec.hash or mod.Hash(rec)
    MMT.SendLong("TIVS:" .. rec.hash .. ":" .. (rec.class or "") .. "#" .. mod.Encode(rec), target, "BULK")
end

-- after a scan that changed something: the changes, or everything if that's shorter
function mod.OwnChanged()
    local list = {}
    for k, n in pairs(changes) do list[#list + 1] = k .. "=" .. n end
    wipe(changes)
    if #list == 0 then return end
    table.sort(list)
    local rec = mod.Own()
    local msg = "TIVD:" .. rec.hash .. "#" .. table.concat(list, ";")
    if #msg <= MAX_DELTA then MMT.SendToTeam(msg, true)
    else mod.SendSnapshot() end
end

M:Heartbeat("tiv", function()
    local rec = mod.Own()
    return rec and rec.hash or nil
end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local lastRequest = {}

local function Request(key, sender)
    if lastRequest[key] and GetTime() - lastRequest[key] < REQUEST_COOLDOWN then return end
    lastRequest[key] = GetTime()
    MMT.SendAddon("TIVREQ", "WHISPER", sender)
end

function mod.RequestAll()
    wipe(lastRequest)
    MMT.SendToTeam("TIVREQ", true)
end

M:Listen("XP_RECEIVED", function(key, sender, status)
    if MMT.IsSelf(key) then return end
    local hash = tonumber(status and status.ext and status.ext.tiv)
    if not hash then return end
    local rec = mod.Chars()[key]
    if not rec or rec.hash ~= hash then Request(key, sender) end
end)

local lastReply = {}

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "TIVREQ" then
        if lastReply[key] and GetTime() - lastReply[key] < 5 then return end
        lastReply[key] = GetTime()
        mod.SendSnapshot(sender)
        return
    end
    local hash, class, data = text:match("^TIVS:(%d+):?(%u*)#(.*)$")
    if hash then
        local rec = mod.Decode(data)
        rec.hash, rec.time = tonumber(hash), time()
        rec.class = class ~= "" and class or (mod.Chars()[key] and mod.Chars()[key].class)
        mod.Chars()[key] = rec
        if mod.RefreshBags then mod.RefreshBags() end
        return
    end
    hash, data = text:match("^TIVD:(%d+)#(.*)$")
    if hash then
        local rec = mod.Chars()[key]
        if not rec then Request(key, sender) return end
        for p, id, n in data:gmatch("(%a)(%d+)=(%d+)") do
            if rec[p] then
                n = tonumber(n)
                rec[p][tonumber(id)] = n > 0 and n or nil
            end
        end
        rec.time = time()
        rec.hash = mod.Hash(rec)
        if rec.hash ~= tonumber(hash) then Request(key, sender) end
        if mod.RefreshBags then mod.RefreshBags() end
    end
end)
