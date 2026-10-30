-- MMT Quality of life: sending big import strings (ForeverAuras auras,
-- EllesmereUI profiles) to one team member or the online team.
--
-- b = mod.Bulk{ tag, noun, plural, where, fromKey, settings, process }
--   tag      "QWA": the messages are <tag>H, <tag> and <tag>R
--   noun     "aura(s)" / plural "auras": for the chat lines
--   where    "ForeverAuras' import window": what the receiver sees
--   fromKey  M.db key: "LEADER" = only the FTL leader may send here
--   settings "Quality of life > ForeverAuras" (said when refused)
--   process(t, entries)  a whole transfer arrived: t = { from, sender, batch },
--            entries = { { name = , str = }, ... }
-- b.tags   the three handlers, for mod.Feature's tags
-- b:Send(entries, to)  -> true, chat text | false, why not  (to = team key, nil = online team)
-- b:Reply(t, text)     back to the sender: "A" importing, "N:<why>", "D:<imported>:<total>"
--
-- Wire:
--   <tag>H:<batch>:<count>:<bytes>:<names>   first, small: "Anna is sending you ..."
--   <tag>:<batch>:<i>:<n>:<part>             the payload in parts of CHUNK bytes,
--                                            each one MMT.SendLong (the core drops a
--                                            text that takes over 2 minutes or 400 parts)
--   payload = <name>=<string>;<name>=<string>...  (names %XX escaped; the
--   strings are printable "!WA:2!..." / "!EUI_..." without ; or =)
--   <tag>R:<batch>:<state>                   whispered back

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 6000          -- payload bytes per SendLong (~28 core parts: well inside its 2 minutes)
local FORGET = 600          -- an unfinished transfer is dropped after 10 minutes without a part
local RATE = 800            -- the core's data rate (bytes / s), for the time estimate

local function Esc(s) return (tostring(s):gsub("[%%;=|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
mod.Esc, mod.Unesc = Esc, Unesc

function mod.KB(bytes) return bytes < 1024 and (bytes .. " bytes") or ("%d KB"):format(math.floor(bytes / 1024 + 0.5)) end
local function Duration(sec)
    sec = math.max(1, math.ceil(sec))
    if sec < 60 then return sec .. " s" end
    return ("%d min"):format(math.ceil(sec / 60))
end

-- online team members other than this character
function mod.OnlineOthers()
    local t = {}
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) and MMT.IsOnline(key) then t[#t + 1] = key end
    end
    return t
end

local function FromLeader(key)
    if MMT.IsFTLLeader then return MMT.IsFTLLeader(key) and true or false end
    local l = MMT.FTLLeader and MMT.FTLLeader()
    return l ~= nil and l == key
end

function mod.Bulk(spec)
    local b = { incoming = {} }   -- ["<key>:<batch>"] = { from, sender, batch, count, bytes, n, got, parts, last }
    local incoming = b.incoming

    function b:Send(entries, to)
        local receivers
        if to then
            if MMT.IsSelf(to) then return false, "that's this character." end
            if not MMT.IsOnline(to) then return false, MMT.FullDisplay(to) .. " isn't online." end
            receivers = 1
        else
            receivers = #mod.OnlineOthers()
            if receivers == 0 then return false, "nobody of the team is online." end
        end
        if #entries == 0 then return false, "nothing to send." end
        local parts, names = {}, {}
        for i, e in ipairs(entries) do
            parts[i] = Esc(e.name) .. "=" .. e.str
            names[i] = e.label or e.name
        end
        local payload = table.concat(parts, ";")
        local bytes = #payload
        local batch = tostring(math.random(100000, 999999))
        local n = math.max(1, math.ceil(bytes / CHUNK))
        -- the names for the receiver's first line, cut to fit one message
        local list = Esc(table.concat(names, ", "))
        local head = ("%sH:%s:%d:%d:"):format(spec.tag, batch, #entries, bytes)
        if #head + #list > 240 then list = list:sub(1, 240 - #head - 3):gsub("%%%x?$", "") .. "..." end
        local target = to and MMT.WhisperTarget(to)
        if target then MMT.SendAddon(head .. list, "WHISPER", target) else MMT.SendToTeam(head .. list, true) end
        for i = 1, n do
            MMT.SendLong(("%s:%s:%d:%d:%s"):format(spec.tag, batch, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK)), target)
        end
        local what = #entries == 1 and ("\"" .. names[1] .. "\"") or (#entries .. " " .. spec.plural)
        return true, ("Sending %s (%s) to %s: about %s."):format(what, mod.KB(bytes),
            to and MMT.FullDisplay(to) or ("the online team (" .. receivers .. ")"), Duration(bytes * 1.2 * receivers / RATE))
    end

    function b:Reply(t, text)
        if t.sender then MMT.SendAddon(("%sR:%s:%s"):format(spec.tag, t.batch, text), "WHISPER", t.sender) end
    end

    function b:Count()
        local n = 0
        for _ in pairs(incoming) do n = n + 1 end
        return n
    end

    local function Allowed(key) return M.db[spec.fromKey] ~= "LEADER" or FromLeader(key) end

    local function Buffer(key, sender, batch)
        local now = GetTime()
        for k, t in pairs(incoming) do if now - t.last > FORGET then incoming[k] = nil end end
        local k = key .. ":" .. batch
        local t = incoming[k]
        if not t then
            t = { from = key, sender = sender, batch = batch, got = 0, parts = {}, last = now }
            incoming[k] = t
        end
        return t, k
    end

    local function OnHead(key, sender, body)
        local batch, count, bytes, names = body:match("^(%d+):(%d+):(%d+):(.*)$")
        if not batch then return end
        if not Allowed(key) then
            b:Reply({ sender = sender, batch = batch }, ("N:only the FTL leader may send %s there"):format(spec.plural))
            MMT.Print("Quality of life: %s tried to send you %s; only the FTL leader may (settings: %s).", MMT.FullDisplay(key), spec.plural, spec.settings)
            return
        end
        local t = Buffer(key, sender, batch)
        t.count, t.bytes = tonumber(count), tonumber(bytes)
        MMT.Print("Quality of life: %s is sending you %s %s (%s): %s", MMT.FullDisplay(key), count, spec.noun, mod.KB(t.bytes), Unesc(names))
    end

    local function OnPart(key, sender, body)
        local batch, i, n, part = body:match("^(%d+):(%d+):(%d+):(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not batch or not i or not n or i < 1 or i > n then return end
        if not Allowed(key) then return end
        local t, k = Buffer(key, sender, batch)
        t.n, t.last = n, GetTime()
        if not t.parts[i] then t.parts[i] = part; t.got = t.got + 1 end
        if t.got < n then return end
        incoming[k] = nil
        local entries = {}
        for entry in table.concat(t.parts):gmatch("[^;]+") do
            local name, str = entry:match("^([^=]*)=(.+)$")
            if name then entries[#entries + 1] = { name = Unesc(name), str = str } end
        end
        spec.process(t, entries)
    end

    local function OnReply(key, _, body)
        local batch, state, rest = body:match("^(%d+):(%a)(.*)$")
        if not batch then return end
        local who = MMT.FullDisplay(key)
        if state == "A" then
            MMT.Print("Quality of life: %s is importing (%s).", who, spec.where)
        elseif state == "N" then
            MMT.Print("Quality of life: %s didn't take the %s: %s", who, spec.plural, rest:sub(2))
        elseif state == "D" then
            local ok, total = rest:match("^:(%d+):(%d+)$")
            if ok then MMT.Print("Quality of life: %s imported %s of %s %s.", who, ok, total, spec.noun) end
        end
    end

    b.tags = { [spec.tag .. "H"] = OnHead, [spec.tag] = OnPart, [spec.tag .. "R"] = OnReply }

    -----------------------------------------------------------------------
    -- Importing, one at a time through the addon's own import UI:
    -- spec.open(item, done) -> opened, why; done(accepted) once it closes.
    -- why == "in combat": tried again after combat; why in spec.busy (its
    -- import UI is in use): tried again every 2 s; anything else: skipped.
    -----------------------------------------------------------------------
    local queue, importing, waitNote = {}, nil, nil
    b.stats = { received = 0, imported = 0, declined = 0, failed = 0 }
    local stats = b.stats

    local function Finished(item)
        local t = item.batch
        t.left = t.left - 1
        if t.left == 0 then
            b:Reply(t, ("D:%d:%d"):format(t.ok, t.total))
            MMT.Print("Quality of life: %d of %d %s from %s imported.", t.ok, t.total, spec.noun, MMT.FullDisplay(t.from))
        end
    end

    function b:Next()
        if importing or #queue == 0 or not spec.ready() then return end
        local item = table.remove(queue, 1)
        importing = item   -- before open: done() may come right away
        local ok, opened, why = pcall(spec.open, item, function(accepted)
            if importing ~= item then return end
            importing = nil
            if accepted then stats.imported = stats.imported + 1; item.batch.ok = item.batch.ok + 1
            else stats.declined = stats.declined + 1 end
            Finished(item)
            if C_Timer and C_Timer.After then C_Timer.After(0, function() b:Next() end) else b:Next() end
        end)
        if ok and opened then
            waitNote = nil
            return
        end
        if importing == item then importing = nil end
        why = ok and why or tostring(opened)
        if why == "in combat" then
            table.insert(queue, 1, item)
            if waitNote ~= why then MMT.Print("Quality of life: the %s from %s open after combat.", spec.plural, MMT.FullDisplay(item.batch.from)) end
            waitNote = why
            return
        end
        if spec.busy and spec.busy[why] then
            table.insert(queue, 1, item)
            if waitNote ~= why then MMT.Print("Quality of life: \"%s\" waits until %s is free (%s).", item.label, spec.where, why) end
            waitNote = why
            if C_Timer and C_Timer.After then C_Timer.After(2, function() b:Next() end) end
            return
        end
        stats.failed = stats.failed + 1
        MMT.Print("Quality of life: \"%s\" from %s couldn't be opened: %s", item.label, MMT.FullDisplay(item.batch.from), tostring(why))
        Finished(item)
        return b:Next()
    end

    -- items = { { label, ... }, ... } of transfer t: into the queue (Accept / no ask)
    function b:Queue(t, items)
        stats.received = stats.received + #items
        t.total, t.left, t.ok = #items, #items, 0
        b:Reply(t, "A")
        for _, it in ipairs(items) do it.batch = t; queue[#queue + 1] = it end
        b:Next()
    end

    function b:InCombatEnded() if waitNote == "in combat" then waitNote = nil; b:Next() end end
    function b:Waiting() return #queue, importing and importing.label or "-" end
    return b
end
