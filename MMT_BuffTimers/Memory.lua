-- MMT Buff Timers: /mmtbt mem - where the memory goes. Prints this module's and
-- Cooldown Timers' memory before and after a full garbage collection (the
-- difference is garbage not collected yet, the rest is kept), and the size of
-- the tables that can grow. The shared bar library (IconBars) counts under
-- whichever of the two modules loaded it.

local _, mod = ...
local MMT = MMT
local M = mod.M

local function Count(t, seen, depth)
    if type(t) ~= "table" or seen[t] or depth > 6 then return 0 end
    seen[t] = true
    local n = 0
    for k, v in pairs(t) do
        n = n + 1 + Count(k, seen, depth + 1) + Count(v, seen, depth + 1)
    end
    return n
end

local function Usage(addon)
    local fn = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not fn then return nil end
    local ok, kb = pcall(fn, addon)
    return ok and type(kb) == "number" and kb or nil
end

local function MB(kb) return kb and ("%.1f MB"):format(kb / 1024) or "?" end

-- what each part allocates (garbage included): collectgarbage("count") before / after it.
-- Cheap, always on; the report shows KB per second since the first measured call.
local tally, calls, callers, since = {}, {}, {}, nil
function mod.MemTally(what, kb)
    calls[what] = (calls[what] or 0) + 1
    since = since or GetTime()
    if kb and kb > 0 then tally[what] = (tally[what] or 0) + kb end
end

-- who asked for a redraw: the first lines of the call stack outside the bar library, counted
-- (only the first 300 calls of each part: debugstack isn't free)
local function Caller(what)
    local by = callers[what] or {}
    callers[what] = by
    if (calls[what] or 0) > 300 or not debugstack then return end
    local stack = debugstack(3, 6, 0) or ""
    local where
    for line in stack:gmatch("[^\n]+") do
        local file, n = line:match("([%w_]+%.lua)\"?%]?:(%d+)")
        if file and file ~= "IconBars.lua" and file ~= "Memory.lua" then where = file .. ":" .. n break end
    end
    where = where or "?"
    by[where] = (by[where] or 0) + 1
end

local function Measured(what, fn)
    return function(...)
        Caller(what)
        local c = collectgarbage("count")
        local a, b, d = fn(...)
        mod.MemTally(what, collectgarbage("count") - c)
        return a, b, d
    end
end

-- the shared bar library's work, whoever asked for it: each window's redraws, the party-frame check
local wrapped = {}
function mod.MemWrap()
    local lib = MMTIconBars
    if not lib then return end
    for name, w in pairs(lib.windows or {}) do
        if not wrapped[w] then
            wrapped[w] = true
            w.Refresh = Measured("redraw " .. name, w.Refresh)   -- keeps a hook already on it (Live.lua)
        end
    end
    if not wrapped.check and lib.CheckFrames then
        wrapped.check = true
        lib.CheckFrames = Measured("party-frame check", lib.CheckFrames)
    end
end
M:On("PLAYER_ENTERING_WORLD", function() if C_Timer and C_Timer.After then C_Timer.After(3, mod.MemWrap) end end)

function mod.MemoryReport(say)
    if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    local bt, ct = Usage("MMT_BuffTimers"), Usage("MMT_CooldownTimers")
    collectgarbage("collect")
    if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    local bt2, ct2 = Usage("MMT_BuffTimers"), Usage("MMT_CooldownTimers")
    say(("memory: Buff Timers %s -> %s after collecting, Cooldown Timers %s -> %s"):format(MB(bt), MB(bt2), MB(ct), MB(ct2)))
    local icons, windows = 0, 0
    for _, w in pairs((MMTIconBars and MMTIconBars.windows) or {}) do
        windows = windows + 1
        for _, rows in ipairs({ w.rows or {}, w.frows or {} }) do
            for _, row in ipairs(rows) do icons = icons + #(row.icons or {}) end
        end
    end
    local seen = {}
    say(("tables: auras %d, store %d, lists %d, search names %d, bar icons %d in %d windows, live overlays %d"):format(
        Count(mod.auras, seen, 0), Count(M.store, {}, 0), Count(M.db.lists, {}, 0),
        mod.SearchSize and mod.SearchSize() or 0, icons, windows, mod.LiveCount and mod.LiveCount() or 0))
    mod.MemWrap()
    local secs = since and math.max(1, GetTime() - since) or nil
    local parts = {}
    for what, kb in pairs(tally) do parts[#parts + 1] = { what, kb } end
    table.sort(parts, function(a, b) return a[2] > b[2] end)
    local out = {}
    for _, p in ipairs(parts) do
        out[#out + 1] = ("%s %.0f KB/s (%.1f calls/s, %.0f KB each)"):format(p[1], p[2] / secs,
            (calls[p[1]] or 0) / secs, p[2] / math.max(1, calls[p[1]] or 1))
    end
    say(secs and ("made per second over %d s: %s"):format(secs, table.concat(out, ", "))
        or "made per second: nothing measured yet (play a bit, then /mmtbt mem again)")
    for what, by in pairs(callers) do
        local list = {}
        for where, n in pairs(by) do list[#list + 1] = { where, n } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        local top = {}
        for i = 1, math.min(4, #list) do top[#top + 1] = list[i][1] .. " x" .. list[i][2] end
        if #top > 0 then say(("%s asked by: %s"):format(what, table.concat(top, ", "))) end
    end
end
