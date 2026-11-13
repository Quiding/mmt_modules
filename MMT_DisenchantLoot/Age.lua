-- MMT Disenchant Loot: how old Auctionator's prices are, and a reminder.
--
-- The prices count from the newest of:
--   Auctionator's own scans (SavedState: replicate / full / browse scan times),
--   Auctionator price updates seen here (Auctionator.API.v1.RegisterForDBUpdate),
--   Quality of life: your own scan (store.ahScan) and the scan time of prices
--   taken from the team (store.ahTaken).
-- Older than M.db.staleHours (staleOn): a chat line on login and at most once an
-- hour after (only on the group leader, or solo, so the team doesn't repeat it),
-- and a red line on the tooltips.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CALLER = "MMT Disenchant Loot"

function mod.PriceTime()
    local t = 0
    local A = rawget(_G, "Auctionator")
    local st = type(A) == "table" and type(A.SavedState) == "table" and A.SavedState
    if st then
        for _, k in ipairs({ "TimeOfLastReplicateScan", "TimeOfLastGetAllScan", "TimeOfLastBrowseScan" }) do
            t = math.max(t, tonumber(st[k]) or 0)
        end
    end
    if type(M.store) == "table" then t = math.max(t, tonumber(M.store.priceTime) or 0) end
    local q = MMT.modules and MMT.modules.QoL
    local qs = q and q.store
    if type(qs) == "table" then t = math.max(t, tonumber(qs.ahScan) or 0, tonumber(qs.ahTaken) or 0) end
    return t > 0 and t or nil
end

-- hours since the newest prices, nil = no scan time known
function mod.PriceAgeHours()
    local t = mod.PriceTime()
    if not t then return nil end
    return math.max(0, (time() - t) / 3600)
end

function mod.Stale()
    if not (M.db.staleOn and mod.HasPrices()) then return false end
    local h = mod.PriceAgeHours()
    return h == nil or h >= (M.db.staleHours or 8)
end

function mod.AgeText()
    local h = mod.PriceAgeHours()
    if not h then return "Auctionator prices: no scan time known - scan the auction house" end
    local age = h < 1 and ("%d min"):format(math.floor(h * 60)) or h < 48 and ("%d h"):format(math.floor(h)) or ("%d days"):format(math.floor(h / 24))
    if h >= (M.db.staleHours or 8) then return ("Auctionator prices are %s old - scan the auction house"):format(age) end
    return ("Auctionator prices: %s old"):format(age)
end

-- Auctionator's own price updates (its scans, searches)
local hooked = false
local function HookUpdates()
    if hooked then return end
    local A = rawget(_G, "Auctionator")
    local api = A and A.API and A.API.v1
    if not (api and api.RegisterForDBUpdate) then return end
    hooked = pcall(api.RegisterForDBUpdate, CALLER, function()
        if type(M.store) == "table" then M.store.priceTime = time() end
    end)
end

local lastWarn
function mod.Remind()
    if not (M.enabled and mod.Stale()) then return false end
    if IsInGroup() and not UnitIsGroupLeader("player") then return false end
    if lastWarn and GetTime() - lastWarn < 3600 then return false end
    lastWarn = GetTime()
    MMT.Print("Disenchant Loot: %s for fresh disenchant values.", mod.AgeText())
    return true
end

M:On("PLAYER_ENTERING_WORLD", function()
    HookUpdates()
    C_Timer.After(15, mod.Remind)
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(600, function() mod.Remind() end) end
