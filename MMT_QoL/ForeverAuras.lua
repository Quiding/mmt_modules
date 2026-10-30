-- MMT Quality of life: send ForeverAuras auras to the team.
--
-- ForeverAuras (Forever's WeakAuras) has a public API for this,
-- ForeverAurasAPI (ForeverAuras/API.lua):
--   :GetAuras()            every aura by id: parent, children, icon
--   :ExportAura(id)        its import string ("!WA:2!..."), a group with everything inside it
--   :DecodeAuraString(s)   the table an import string holds (nil if it isn't one)
--   :ImportAura(s, cb)     opens ForeverAuras' own import window (the one that
--                          shows what an update changes); cb(accepted, id) once
--                          it closes. One import window at a time, not in combat.
-- Its own sharing (chat links) only works from a link in chat, one aura at a
-- time, so we send the export strings ourselves:
--   QWAH:<batch>:<auras>:<bytes>:<names>  first, small: "Anna is sending you ..."
--   QWA:<batch>:<i>:<n>:<part>            the payload in parts of CHUNK bytes,
--                                         each one MMT.SendLong (the core drops a
--                                         text that takes over 2 minutes or 400 parts)
--   payload = <id>=<import string>;<id>=<import string>... (ids %XX escaped)
--   QWAR:<batch>:<state>                  whispered back: A importing, N:<why> not
--                                         taken, D:<imported>:<auras> done
-- The receiver is always shown what came (a dialog unless switched off, then
-- ForeverAuras' import window for each aura, one after the other).

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 6000          -- payload bytes per SendLong (~28 core parts: well inside its 2 minutes)
local FORGET = 600          -- an unfinished transfer is dropped after 10 minutes without a part
local RATE = 800            -- the core's data rate (bytes / s), for the time estimate

local F
local wa = { sent = 0, received = 0, imported = 0, declined = 0, failed = 0 }
mod.wa = wa
local incoming = {}         -- ["<key>:<batch>"] = { from, sender, auras, bytes, n, got, parts, last }
local queue = {}            -- { str, id, batch } waiting for ForeverAuras' import window
local importing             -- the queue entry whose import window is open
local waitNote              -- printed once while waiting for another import window

local function API() return rawget(_G, "ForeverAurasAPI") end
mod.AurasAPI = API

local function Esc(s) return (tostring(s):gsub("[%%;=|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function KB(bytes) return bytes < 1024 and (bytes .. " bytes") or ("%d KB"):format(math.floor(bytes / 1024 + 0.5)) end
local function Duration(sec)
    sec = math.max(1, math.ceil(sec))
    if sec < 60 then return sec .. " s" end
    return ("%d min"):format(math.ceil(sec / 60))
end

---------------------------------------------------------------------------
-- The auras here: a tree list for the send window
---------------------------------------------------------------------------
-- { { id, depth, group = true|nil, inside = auras inside it, section }, ... }:
-- groups before their children, like ForeverAuras' own list: the top level
-- split into "loaded" (ForeverAuras.IsAuraLoaded(id) ~= nil: loaded or on
-- standby; a group when any aura inside it is) and "unloaded", each sorted by
-- name. section = nil when this ForeverAuras can't tell (one plain list then).
function mod.AuraList()
    local api = API()
    if not (api and api.GetAuras) then return {} end
    local ok, auras = pcall(api.GetAuras, api)
    if not ok or type(auras) ~= "table" then return {} end
    local out = {}
    local function Count(id, seen)
        local a = auras[id]
        local n = 0
        for _, c in ipairs(a and a.children or {}) do
            if auras[c] and not seen[c] then seen[c] = true; n = n + 1 + Count(c, seen) end
        end
        return n
    end
    local function Add(id, depth, seen, section)
        local a = auras[id]
        if not a or seen[id] then return end
        seen[id] = true
        local isGroup = type(a.children) == "table"
        out[#out + 1] = { id = id, depth = depth, group = isGroup or nil, inside = isGroup and Count(id, {}) or 0, icon = a.icon, section = section }
        for _, c in ipairs(isGroup and a.children or {}) do Add(c, depth + 1, seen, section) end
    end
    local fa = rawget(_G, "ForeverAuras")
    local IsLoaded = type(fa) == "table" and type(fa.IsAuraLoaded) == "function" and fa.IsAuraLoaded
    local loaded, unloaded = {}, {}
    for id, a in pairs(auras) do
        if type(id) == "string" and (a.parent == nil or not auras[a.parent]) then
            local okL, state = true, true
            if IsLoaded then okL, state = pcall(IsLoaded, id) end
            if okL and state ~= nil then loaded[#loaded + 1] = id else unloaded[#unloaded + 1] = id end
        end
    end
    local function byName(a, b) return a:lower() < b:lower() end
    table.sort(loaded, byName)
    table.sort(unloaded, byName)
    local seen = {}
    for _, id in ipairs(loaded) do Add(id, 0, seen, IsLoaded and "loaded" or nil) end
    for _, id in ipairs(unloaded) do Add(id, 0, seen, "unloaded") end
    return out
end

-- top-level ids (everything else is inside one of them)
function mod.TopAuras()
    local t = {}
    for _, a in ipairs(mod.AuraList()) do if a.depth == 0 then t[#t + 1] = a.id end end
    return t
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- online team members other than this character
function mod.OnlineOthers()
    local t = {}
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) and MMT.IsOnline(key) then t[#t + 1] = key end
    end
    return t
end

-- ids = aura ids (a group brings everything inside it), to = team key or nil (the online team)
-- -> true, text for the player | false, why not
function mod.SendAuras(ids, to)
    if not mod.Active(F) then return false, "switched off, or ForeverAuras isn't loaded." end
    local api = API()
    if not (api and api.ExportAura) then return false, "this ForeverAuras has no export API (ForeverAurasAPI)." end
    local receivers
    if to then
        if MMT.IsSelf(to) then return false, "that's this character." end
        if not MMT.IsOnline(to) then return false, MMT.FullDisplay(to) .. " isn't online." end
        receivers = 1
    else
        receivers = #mod.OnlineOthers()
        if receivers == 0 then return false, "nobody of the team is online." end
    end
    local entries, names, bytes = {}, {}, 0
    for _, id in ipairs(ids or {}) do
        local ok, s = pcall(api.ExportAura, api, id)
        if ok and type(s) == "string" and s ~= "" then
            entries[#entries + 1] = Esc(id) .. "=" .. s
            names[#names + 1] = id
        end
    end
    if #entries == 0 then return false, "nothing to send (no such aura)." end
    local payload = table.concat(entries, ";")
    bytes = #payload
    local batch = tostring(math.random(100000, 999999))
    local n = math.max(1, math.ceil(bytes / CHUNK))
    -- the names for the receiver's first line, cut to fit one message
    local list = Esc(table.concat(names, ", "))
    local head = ("QWAH:%s:%d:%d:"):format(batch, #entries, bytes)
    if #head + #list > 240 then list = list:sub(1, 240 - #head - 3):gsub("%%%x?$", "") .. "..." end
    local target = to and MMT.WhisperTarget(to)
    if target then MMT.SendAddon(head .. list, "WHISPER", target) else MMT.SendToTeam(head .. list, true) end
    for i = 1, n do
        local msg = ("QWA:%s:%d:%d:%s"):format(batch, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
        MMT.SendLong(msg, target)
    end
    wa.sent = wa.sent + #entries
    local what = #entries == 1 and ("\"" .. names[1] .. "\"") or (#entries .. " auras")
    return true, ("Sending %s (%s) to %s: about %s."):format(what, KB(bytes),
        to and MMT.FullDisplay(to) or ("the online team (" .. receivers .. ")"), Duration(bytes * 1.2 * receivers / RATE))
end

local function Reply(sender, text)
    if sender then MMT.SendAddon("QWAR:" .. text, "WHISPER", sender) end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Allowed(key)
    if M.db.waFrom ~= "LEADER" then return true end
    if MMT.IsFTLLeader then return MMT.IsFTLLeader(key) and true or false end
    local l = MMT.FTLLeader and MMT.FTLLeader()
    return l ~= nil and l == key
end

local function Forget()
    local now = GetTime()
    for k, t in pairs(incoming) do if now - t.last > FORGET then incoming[k] = nil end end
end

local function Buffer(key, sender, batch)
    Forget()
    local k = key .. ":" .. batch
    local t = incoming[k]
    if not t then
        t = { from = key, sender = sender, batch = batch, got = 0, parts = {}, last = GetTime() }
        incoming[k] = t
    end
    return t, k
end

-- the next aura into ForeverAuras' import window (one at a time)
local function Next()
    if importing or #queue == 0 then return end
    local api = API()
    if not (api and api.ImportAura) or not mod.Active(F) then return end
    local e = queue[1]
    local entry = e
    local ok, opened, why = pcall(api.ImportAura, api, e.str, function(accepted)
        if importing ~= entry then return end
        importing = nil
        local b = entry.batch
        if accepted then wa.imported = wa.imported + 1; b.ok = b.ok + 1 else wa.declined = wa.declined + 1 end
        b.left = b.left - 1
        if b.left == 0 then
            Reply(b.sender, ("%s:D:%d:%d"):format(b.batch, b.ok, b.total))
            MMT.Print("Quality of life: %d of %d aura(s) from %s imported into ForeverAuras.", b.ok, b.total, MMT.FullDisplay(b.from))
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Next) else Next() end
    end)
    if ok and opened then
        table.remove(queue, 1)
        importing = entry
        waitNote = nil
        return
    end
    why = ok and why or tostring(opened)
    if why == "in combat" then
        if waitNote ~= why then MMT.Print("Quality of life: the auras from %s open in ForeverAuras after combat.", MMT.FullDisplay(e.batch.from)) end
        waitNote = why   -- PLAYER_REGEN_ENABLED goes on
        return
    end
    if why == "another import is still open" then
        if waitNote ~= why then MMT.Print("Quality of life: aura \"%s\" waits until ForeverAuras' open import window is closed.", e.id) end
        waitNote = why
        if C_Timer and C_Timer.After then C_Timer.After(2, Next) end
        return
    end
    -- this one can't be imported: say so, go on with the next
    table.remove(queue, 1)
    wa.failed = wa.failed + 1
    MMT.Print("Quality of life: ForeverAuras couldn't open aura \"%s\" from %s: %s", e.id, MMT.FullDisplay(e.batch.from), tostring(why))
    local b = e.batch
    b.left = b.left - 1
    if b.left == 0 then
        Reply(b.sender, ("%s:D:%d:%d"):format(b.batch, b.ok, b.total))
        MMT.Print("Quality of life: %d of %d aura(s) from %s imported into ForeverAuras.", b.ok, b.total, MMT.FullDisplay(b.from))
    end
    return Next()
end
mod.AurasNext = Next

-- a whole transfer is here: what it holds, then ask / import
local function Process(t)
    local api = API()
    if not (api and api.ImportAura and api.DecodeAuraString) then return end
    local payload = table.concat(t.parts)
    local here = {}
    if api.GetAuras then
        local ok, all = pcall(api.GetAuras, api)
        if ok and type(all) == "table" then here = all end
    end
    local items, lines = {}, {}
    for entry in payload:gmatch("[^;]+") do
        local id, str = entry:match("^([^=]*)=(.+)$")
        if id and str:match("^![FW]A:%d+!") then
            id = Unesc(id)
            local ok, d = pcall(api.DecodeAuraString, api, str)
            if ok and type(d) == "table" and d.m == "d" and type(d.d) == "table" then
                local name = type(d.d.id) == "string" and d.d.id or id
                local kids = type(d.c) == "table" and #d.c or 0
                items[#items + 1] = { str = str, id = name }
                lines[#lines + 1] = name .. (kids > 0 and (" (group, " .. kids .. " inside)") or "")
                    .. (here[name] and " - you have one by this name" or "")
            end
        end
    end
    if #items == 0 then
        Reply(t.sender, t.batch .. ":N:not an aura")
        MMT.Print("Quality of life: what %s sent isn't a ForeverAuras aura (nothing imported).", MMT.FullDisplay(t.from))
        return
    end
    wa.received = wa.received + #items
    local b = { from = t.from, sender = t.sender, batch = t.batch, total = #items, left = #items, ok = 0 }
    local function Go()
        Reply(t.sender, t.batch .. ":A")
        for _, it in ipairs(items) do queue[#queue + 1] = { str = it.str, id = it.id, batch = b } end
        Next()
    end
    if M.db.waAsk then
        mod.Ask(t.from, F, lines, Go, function() Reply(t.sender, t.batch .. ":N:ignored") end)
    else
        MMT.Print("Quality of life: %d aura(s) from %s: opening ForeverAuras' import window.", #items, MMT.FullDisplay(t.from))
        Go()
    end
end

local function OnHead(key, sender, body)
    local batch, auras, bytes, names = body:match("^(%d+):(%d+):(%d+):(.*)$")
    if not batch then return end
    if not Allowed(key) then
        Reply(sender, batch .. ":N:only the FTL leader may send auras there")
        MMT.Print("Quality of life: %s tried to send you ForeverAuras auras; only the FTL leader may (settings: Quality of life > ForeverAuras).", MMT.FullDisplay(key))
        return
    end
    local t = Buffer(key, sender, batch)
    t.auras, t.bytes = tonumber(auras), tonumber(bytes)
    MMT.Print("Quality of life: %s is sending you %s aura(s) (%s): %s", MMT.FullDisplay(key), auras, KB(t.bytes), Unesc(names))
end

local function OnPart(key, sender, body)
    local batch, i, n, part = body:match("^(%d+):(%d+):(%d+):(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not batch or not i or not n or i < 1 or i > n then return end
    if not Allowed(key) then return end
    local t, k = Buffer(key, sender, batch)
    t.n, t.last = n, GetTime()
    if not t.parts[i] then t.parts[i] = part; t.got = t.got + 1 end
    if t.got >= n then
        incoming[k] = nil
        Process(t)
    end
end

local function OnReply(key, _, body)
    local batch, state, rest = body:match("^(%d+):(%a)(.*)$")
    if not batch then return end
    local who = MMT.FullDisplay(key)
    if state == "A" then
        MMT.Print("Quality of life: %s is importing the auras (ForeverAuras' import window).", who)
    elseif state == "N" then
        MMT.Print("Quality of life: %s didn't take the auras: %s", who, rest:sub(2))
    elseif state == "D" then
        local ok, total = rest:match("^:(%d+):(%d+)$")
        if ok then MMT.Print("Quality of life: %s imported %s of %s aura(s).", who, ok, total) end
    end
end

F = mod.Feature({
    key = "auras", slash = "auras", addon = "ForeverAuras", title = "ForeverAuras",
    checkText = "Send and take ForeverAuras auras",
    tip = "Send one aura, a group (with everything inside it) or all of them to a team member or the whole online team. What comes in opens in ForeverAuras' own import window (it shows what an update changes).",
    askText = function(who, n)
        return ("%s sends you %d ForeverAuras aura(s). Each opens in ForeverAuras' import window:"):format(who, n)
    end,
    askAccept = "Import",
    notes = {
        "Pick an aura, a group (everything inside it comes along) or \"All auras\", and one online team member or the whole online team, then Send.",
        "The others get a dialog (Import / Ignore), then ForeverAuras' own import window for each aura, one after the other - the same window as pasting an import string, so an aura they already have shows what changes. You hear back when they import.",
        "Auras are a few KB each; a big group or \"all\" can be 100 KB and more. The team's messages share about 800 bytes a second, so that takes a minute or two, longer to several members at once. Only members who are online get them.",
    },
    tags = { QWAH = OnHead, QWA = OnPart, QWAR = OnReply },
    commands = { [""] = function() mod.OpenAuras() end },
    OnEnable = function()
        if mod.AurasDock then mod.AurasDock() end
        if not importing then Next() end
    end,
    Refresh = function() if mod.AurasDock then mod.AurasDock() end end,
    OnDisable = function()
        if mod.AurasClose then mod.AurasClose() end
    end,
    Page = function(ui)
        ui.Button("Open the send window", function() mod.OpenAuras() end,
            "Pick an aura, a group or all of them, and who gets them. Also /mmtqol auras, or the \"Send to team\" button above ForeverAuras' options.")
        ui.Check("\"Send to team\" on ForeverAuras' options", "waDock", "A button above ForeverAuras' options window opens the send window beside it.")
        ui.Check("Ask before importing", "waAsk", "A dialog lists the auras a team member sent, Import or Ignore. Off: they go straight to ForeverAuras' import window, which always asks too.")
        ui.Cycle("Who may send me auras", { { value = "TEAM", text = "Anyone in the team" }, { value = "LEADER", text = "Only the FTL leader" } }, "waFrom")
    end,
    Report = function(add)
        local n = 0
        for _ in pairs(incoming) do n = n + 1 end
        add(("ForeverAuras: api=%s auras=%d sent=%d received=%d imported=%d declined=%d failed=%d incoming=%d queued=%d importing=%s from=%s"):format(
            tostring(API() ~= nil), #mod.AuraList(), wa.sent, wa.received, wa.imported, wa.declined, wa.failed, n, #queue,
            importing and importing.id or "-", tostring(M.db.waFrom)))
    end,
})
mod.AurasFeature = F

M:On("PLAYER_REGEN_ENABLED", function() if waitNote == "in combat" then waitNote = nil; Next() end end)
