-- MMT Quality of life: offer the features whose addon is here.
-- Every feature starts off. A while after logging in, for each feature tied to an
-- addon (Dejunk, Baganator, Auctionator, ...) that is loaded on this character while
-- the feature is off, a dialog says in short what it does and asks to switch it on.
-- Each is asked once per account (M.store.offered[key] = "yes" | "no"); answering
-- "Not now" leaves it off for good (the checkbox is on its tab). Only on the group
-- leader, or solo, so the team's windows don't all ask at once; never in combat.
-- One dialog at a time, through the same queue as the team's changes (Ask.lua).
-- /mmtqol offers asks again about everything left off.

local _, mod = ...
local MMT = MMT
local M = mod.M

local DELAY = 12          -- seconds after the loading screen
local asked = false       -- this session

-- the features to offer now, in tab order
function mod.Offers()
    local list = {}
    local offered = type(M.store) == "table" and M.store.offered or {}
    for _, f in ipairs(mod.features) do
        if f.addon and not M.db[f.key] and not offered[f.key] and (mod.AddonState(f.addon)) then list[#list + 1] = f end
    end
    return list
end

local function Answer(f, how)
    M.store.offered = M.store.offered or {}
    M.store.offered[f.key] = how
end

local function Text(f)
    return ("|cffffd100Quality of life: %s|r\n\n%s is loaded on this character. %s\n\nSwitch it on? You can change it later in /mmt > Quality of life > %s."):format(
        f.title, f.addonTitle or f.addon, f.offer or f.tip or "", f.tabText or f.title)
end

function mod.OfferAll(force)
    if not M.enabled then return 0 end
    if not force and IsInGroup and IsInGroup() and not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return 0 end
    local list = mod.Offers()
    for _, f in ipairs(list) do
        mod.AskText(Text(f), "Switch it on", function()
            Answer(f, "yes")
            M.db[f.key] = true
            if f.OnEnable then pcall(f.OnEnable) end
            if MMT.RefreshConfig then pcall(MMT.RefreshConfig) end
            MMT.Print("Quality of life: %s switched on.", f.title)
        end, "Not now", function() Answer(f, "no") end)
    end
    return #list
end

local function Later()
    if asked then return end
    asked = true
    C_Timer.After(DELAY, function()
        if InCombatLockdown and InCombatLockdown() then
            -- after the fight
            local waiting = true
            M:On("PLAYER_REGEN_ENABLED", function()
                if waiting then waiting = false; mod.OfferAll() end
            end)
            return
        end
        mod.OfferAll()
    end)
end

M:On("PLAYER_ENTERING_WORLD", Later)

-- /mmtqol offers: ask again about every feature left off whose addon is here
local qol = SlashCmdList.MMTQOL
if qol then
    SlashCmdList.MMTQOL = function(msg)
        if (msg or ""):lower():match("^%s*offers%s*$") then
            if type(M.store) == "table" then M.store.offered = nil end
            local n = mod.OfferAll(true)
            if n == 0 then MMT.Print("Quality of life: nothing to offer - every feature whose addon is loaded is on already.") end
            return
        end
        return qol(msg)
    end
end
