-- MMT Pawn Compare: the team's Pawn scales.
--
-- Every character with Pawn shares the scales that are visible for it in
-- Pawn (stat weights + normalization). They are stored account-wide in
-- M.store.scales[teamKey] = { scales = { {name, values, norm} }, hash, time, noPawn },
-- so they stay available when the member is offline, and also on clients
-- that don't have Pawn at all. Traffic works like Item Compare's equipment:
--   * the heartbeat carries "pcs=<hash of your scales>" (and "pcn=1" without Pawn),
--   * a member whose stored hash differs is asked once (PCMP_REQ),
--   * scales travel in numbered chunks (PCMP_S:<id>:<part>:<total>:<data>),
--     sent to the team when you change a scale in Pawn.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 200
local REQUEST_COOLDOWN = 60

---------------------------------------------------------------------------
-- Encoding: scales separated by "~", fields by "^", stats "Stat=value;..."
---------------------------------------------------------------------------
local function Escape(s)
    return (s:gsub("[^%w %-_.()']", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

mod.Escape, mod.Unescape = Escape, Unescape

local function Num(v)
    return ("%.4g"):format(v)
end

local function Encode(scales)
    local parts = {}
    for _, sc in ipairs(scales) do
        local stats = {}
        for stat, v in pairs(sc.values) do stats[#stats + 1] = stat .. "=" .. Num(v) end
        table.sort(stats)
        parts[#parts + 1] = Escape(sc.name) .. "^" .. Num(sc.norm or 0) .. "^" .. table.concat(stats, ";")
    end
    return table.concat(parts, "~")
end

local function Decode(data)
    local scales = {}
    for part in (data or ""):gmatch("[^~]+") do
        local name, norm, stats = part:match("^([^%^]*)%^([^%^]*)%^(.*)$")
        if name and name ~= "" then
            local values = {}
            for stat, v in stats:gmatch("(%w+)=([^;]+)") do values[stat] = tonumber(v) end
            local n = tonumber(norm)
            scales[#scales + 1] = { name = Unescape(name), values = values, norm = (n and n > 0) and n or nil }
        end
    end
    return scales
end

local function Hash(scales)
    local s = Encode(scales)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
local function DB()
    M.store.scales = M.store.scales or {}
    return M.store.scales
end

function mod.ScalesOf(key)
    return M.store and DB()[key]
end

function mod.StoredCount()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

local function Store(key, scales)
    local old = DB()[key]
    local rec = { scales = scales, hash = Hash(scales), time = time(), noPawn = old and old.noPawn }
    DB()[key] = rec
    MMT.Fire("PAWN_SCALES_CHANGED", key)
    return rec
end

---------------------------------------------------------------------------
-- Own scales (from Pawn)
---------------------------------------------------------------------------
-- visible scales of this character, values copied (Pawn's tables must not be touched)
local function ReadOwn()
    if not (mod.PawnReady() and PawnGetAllScalesEx and PawnGetAllStatValues) then return nil end
    local ok, list = pcall(PawnGetAllScalesEx)
    if not ok or type(list) ~= "table" then return nil end
    local scales = {}
    for _, info in ipairs(list) do
        if info.IsVisible then
            local values = {}
            for stat, v in pairs(PawnGetAllStatValues(info.Name) or {}) do
                if type(v) == "number" and v ~= 0 then values[stat] = v end
            end
            local norm = PawnCommon and PawnCommon.Scales and PawnCommon.Scales[info.Name]
                and PawnCommon.Scales[info.Name].NormalizationFactor
            scales[#scales + 1] = { name = info.LocalizedName or info.Name, values = values, norm = norm }
        end
    end
    table.sort(scales, function(a, b) return a.name < b.name end)
    -- round-trip so the own hash matches the one the team computes after decoding
    return Decode(Encode(scales))
end

function mod.OwnScaleCount()
    local rec = DB()[MMT.PlayerFull() or ""]
    return rec and #rec.scales or 0
end

function mod.OwnHash()
    local rec = DB()[MMT.PlayerFull() or ""]
    return rec and rec.hash
end

M:Heartbeat("pcs", mod.OwnHash)
M:Heartbeat("pcn", function() return (not mod.PawnInstalled()) and "1" or nil end)

-- re-reads the own scales; announce = send them to the team if they changed
function mod.UpdateOwn(announce)
    local key = MMT.PlayerFull()
    if not key then return end
    local own = DB()[key]
    if own then own.noPawn = not mod.PawnInstalled() or nil end
    local scales = ReadOwn()
    if not scales then return end   -- no Pawn here: keep what is stored
    if own and own.hash == Hash(scales) then return end
    Store(key, scales)
    M:Debug("own scales changed (%d)", #scales)
    if announce then mod.SendScales() end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
function mod.SendScales(target)
    local rec = DB()[MMT.PlayerFull() or ""]
    if not rec then return end
    local payload = rec.hash .. "#" .. Encode(rec.scales)
    local id = tostring(math.random(100000, 999999))
    local total = math.max(1, math.ceil(#payload / CHUNK))
    M:Debug("scales to %s (%d bytes, %d parts)", target and MMT.Repr(target) or "team", #payload, total)
    for i = 1, total do
        local msg = ("PCMP_S:%s:%d:%d:%s"):format(id, i, total, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
        C_Timer.After((i - 1) * 0.2, function()
            if target then MMT.SendAddon(msg, "WHISPER", target) else MMT.SendToTeam(msg, true) end
        end)
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local lastRequest = {}
local function Request(key, sender)
    if lastRequest[key] and GetTime() - lastRequest[key] < REQUEST_COOLDOWN then return end
    lastRequest[key] = GetTime()
    M:Debug("scale request to %s", MMT.Repr(sender))
    MMT.SendAddon("PCMP_REQ", "WHISPER", sender)
end

function mod.RequestAll()
    wipe(lastRequest)
    MMT.SendToTeam("PCMP_REQ", true)
end

M:Listen("XP_RECEIVED", function(key, sender, s)
    if MMT.IsSelf(key) or not s.ext then return end
    local rec = DB()[key]
    local noPawn = s.ext.pcn == "1" or nil
    if rec and rec.noPawn ~= noPawn then
        rec.noPawn = noPawn
        MMT.Fire("PAWN_SCALES_CHANGED", key)
    end
    local hash = tonumber(s.ext.pcs)
    if hash and (not rec or rec.hash ~= hash) then
        Request(key, sender)
    elseif not hash and not rec and noPawn then
        DB()[key] = { scales = {}, hash = 0, time = time(), noPawn = true }
        MMT.Fire("PAWN_SCALES_CHANGED", key)
    end
end)

local buffers, lastReply = {}, {}

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if text == "PCMP_REQ" then
        if lastReply[key] and GetTime() - lastReply[key] < 5 then return end
        lastReply[key] = GetTime()
        mod.SendScales(sender)
        return
    end

    local id, idx, total, chunk = text:match("^PCMP_S:(%d+):(%d+):(%d+):(.*)$")
    if not id or MMT.IsSelf(key) then return end
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > 30 or idx < 1 or idx > total then return end
    local buf = buffers[key]
    if not buf or buf.id ~= id then
        buf = { id = id, total = total, got = 0, parts = {} }
        buffers[key] = buf
    end
    if not buf.parts[idx] then buf.parts[idx] = chunk; buf.got = buf.got + 1 end
    if buf.got < buf.total then return end
    buffers[key] = nil
    local h, data = table.concat(buf.parts):match("^(%d+)#(.*)$")
    if not h then return end
    local rec = Store(key, Decode(data))
    M:Debug("scales from %s: %d scales, hash %s / %s", MMT.Repr(sender), #rec.scales, h, tostring(rec.hash))
end)

function mod.Clear()
    wipe(DB())
    mod.UpdateOwn(false)
end
