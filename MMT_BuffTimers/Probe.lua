-- MMT Buff Timers: /mmtbt probe - what this client hides from addons in combat.
-- For 60 s it prints (throttled) for the player and party members: whether
-- the aura update info, its added auras (spell ID, name, instance ID), the
-- removed instance IDs and the cast events' spell IDs are readable ("ok") or
-- hidden ("SECRET"), and whether the display-only timer API exists. Nothing
-- else uses it: it only answers which in-combat workarounds can work.

local _, mod = ...
local MMT = MMT
local M = mod.M

local frame, untilT
local lastLine = {}   -- [text] = GetTime(): the same line at most every 3 s

local function S(v)
    if v == nil then return "nil" end
    if MMT.IsSecret(v) then return "SECRET" end
    return "ok(" .. tostring(v) .. ")"
end

local function Say(fmt, ...)
    local text = fmt:format(...)
    local now = GetTime()
    if lastLine[text] and now - lastLine[text] < 3 then return end
    lastLine[text] = now
    MMT.Print("|cff88ccffprobe|r %s", text)
end

local function Wanted(unit)
    return unit == "player" or (type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")))
end

local function OnEvent(_, event, unit, a, b)
    if not untilT or GetTime() > untilT then mod.ProbeStop() return end
    if not Wanted(unit) then return end
    local fight = InCombatLockdown() and "COMBAT" or "out of combat"
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = (not MMT.IsSecret(b) and b) and mod.SpellInfo(b) or nil
        Say("%s %s cast: spellID %s name %s", fight, unit, S(b), S(name))
        return
    end
    local info = a
    local hidden = mod.AurasHidden and mod.AurasHidden()
    if info == nil then Say("%s %s aura: no update info, aurasHidden=%s", fight, unit, tostring(hidden)) return end
    if MMT.IsSecret(info) then Say("%s %s aura: update info SECRET", fight, unit) return end
    local added, removed = info.addedAuras, info.removedAuraInstanceIDs
    local parts = { ("full=%s"):format(S(info.isFullUpdate)) }
    if added ~= nil then
        if MMT.IsSecret(added) then parts[#parts + 1] = "added=SECRET"
        elseif added[1] then
            local x = added[1]
            if MMT.IsSecret(x) then parts[#parts + 1] = "added[1]=SECRET"
            else
                parts[#parts + 1] = ("added %d: spellId %s name %s instance %s icon %s"):format(#added,
                    S(x.spellId), S(x.name), S(x.auraInstanceID), S(x.icon))
            end
        end
    end
    if removed ~= nil then
        if MMT.IsSecret(removed) then parts[#parts + 1] = "removed=SECRET"
        elseif removed[1] then parts[#parts + 1] = ("removed %d: first %s"):format(#removed, S(removed[1])) end
    end
    if info.updatedAuraInstanceIDs and not MMT.IsSecret(info.updatedAuraInstanceIDs) and info.updatedAuraInstanceIDs[1] then
        parts[#parts + 1] = ("updated %d: first %s"):format(#info.updatedAuraInstanceIDs, S(info.updatedAuraInstanceIDs[1]))
    end
    -- the tracked buffs asked for by spell ID (what Buff Timers does in combat)
    local asked, found, refused = 0, 0, 0
    for _, ids in pairs(M.store.auraIds or {}) do
        for id in pairs(ids) do
            asked = asked + 1
            local r, why = mod.AuraBySpellID(unit, id)
            if r then found = found + 1 elseif why then refused = refused + 1 end
        end
    end
    parts[#parts + 1] = ("byId asked %d found %d refused %d"):format(asked, found, refused)
    Say("%s %s aura: aurasHidden=%s %s", fight, unit, tostring(hidden), table.concat(parts, ", "))
end

function mod.ProbeStop()
    if frame then frame:UnregisterAllEvents() end
    if untilT then MMT.Print("|cff88ccffprobe|r finished.") end
    untilT = nil
end

function mod.ProbeStart()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    wipe(lastLine)
    untilT = GetTime() + 60
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    MMT.Print("|cff88ccffprobe|r on for 60 s: start a fight now, cast a seal / buff, let a proc (Flurry) come and go.")
    MMT.Print("|cff88ccffprobe|r timer display API: GetAuraDuration %s, SetCooldownFromDurationObject %s.",
        (C_UnitAuras and C_UnitAuras.GetAuraDuration) and "yes" or "no",
        (CreateFrame("Cooldown").SetCooldownFromDurationObject) and "yes" or "no")
    if C_Timer and C_Timer.After then C_Timer.After(61, function() if untilT and GetTime() > untilT then mod.ProbeStop() end end) end
end
