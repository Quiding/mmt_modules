-- MMT Buffs: "Send lists to team". The only addon messages this module
-- sends, and only when you press the button:
--   MBFL:<id>:<part>:<total>:<data>   data = "CLASS=1459,6673-|CLASS=..." ("-" = switched off)
-- The receiver is asked before its lists are replaced.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 200

local function Encode(lists)
    local parts = {}
    for class in pairs(lists) do
        local items = {}
        for _, e in ipairs(lists[class] or {}) do
            items[#items + 1] = tostring(e.id) .. (e.off and "-" or "")
        end
        local k = class:gsub("[^%w:]", function(c) return ("%%%02X"):format(c:byte()) end)
        parts[#parts + 1] = k .. "=" .. table.concat(items, ",")
    end
    return table.concat(parts, "|")
end

local function Decode(data)
    local lists = {}
    for k, items in data:gmatch("([^=|]+)=([^|]*)") do
        local class = k:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        local list = {}
        for id, off in items:gmatch("(%d+)(%-?)") do list[#list + 1] = { id = tonumber(id), off = (off == "-") or nil } end
        if mod.ValidListKey(class) then lists[class] = list end
    end
    return lists
end

function mod.SendLists()
    local payload = Encode(M.db.lists)
    local id = tostring(math.random(100000, 999999))
    local total = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, total do
        local msg = ("MBFL:%s:%d:%d:%s"):format(id, i, total, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
        C_Timer.After((i - 1) * 0.2, function() MMT.SendToTeam(msg, true) end)
    end
    M:Debug("lists sent (%d bytes, %d parts)", #payload, total)
end

-- someone sent their lists: ask first (like MMT's own profile sync), then take them over
local function Offer(key, lists, title, apply)
    local n = 0
    for _, l in pairs(lists) do if #l > 0 then n = n + 1 end end
    MMT.UI.Confirm(("%s sent you their %s lists (%d with entries).\n\nTake them over? Your current lists are replaced.")
        :format(MMT.FullDisplay(key), title, n), "Take them over", function()
        apply()
        MMT.RefreshConfig()
        MMT.Print("%s: tracked lists taken over from %s.", title, MMT.FullDisplay(key))
    end, "Keep mine")
end
mod.OfferLists = Offer

local buffers = {}
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local id, idx, total, chunk = text:match("^MBFL:(%d+):(%d+):(%d+):(.*)$")
    if not id or MMT.IsSelf(key) then return end
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > 40 or idx < 1 or idx > total then return end
    local buf = buffers[key]
    if not buf or buf.id ~= id then
        buf = { id = id, total = total, got = 0, parts = {} }
        buffers[key] = buf
    end
    if not buf.parts[idx] then buf.parts[idx] = chunk; buf.got = buf.got + 1 end
    if buf.got < buf.total then return end
    buffers[key] = nil
    local lists = Decode(table.concat(buf.parts))
    for _, class in ipairs(mod.CLASSES) do lists[class] = lists[class] or {} end
    Offer(key, lists, "Buffs", function()
        M.db.lists = lists
        mod.BuildIndex()
        mod.ScanGroup()
        mod.Refresh()
    end)
end)
