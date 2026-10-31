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
end
