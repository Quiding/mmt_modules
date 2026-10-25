-- MMT Cooldowns: what can be exported / imported (Transfer.lua does the
-- string and the dialog). Every value is checked before it is taken over.

local _, mod = ...
local MMT = MMT
local M = mod.M

local LOOK = { "bgTexture", "bgColor", "bgTint", "borderTexture", "borderColor", "borderSize", "rowColor", "rowAlpha", "timerColor", "font", "shown", "locked", "clickThrough", "vertical", "growth", "includeSelf", "onlyOnline",
    "iconSize", "iconZoom", "spacing", "rowGap", "scale", "bgAlpha", "showNames", "fullNames", "nameSize", "showTimers",
    "timerSize", "readyAlpha", "cdAlpha", "glowActive", "hideReady", "hideUnknown",
    "hideUnseenItems", "showBuffs" }

local function GetKeys(keys)
    local t = {}
    for _, k in ipairs(keys) do t[k] = M.db[k] end
    return t
end

-- takes over values whose type matches the current setting
local function SetKeys(keys, data)
    if type(data) ~= "table" then return false, "unreadable" end
    local n = 0
    for _, k in ipairs(keys) do
        local v = data[k]
        if v ~= nil and k == "font" and type(v) == "string" then M.db.font = v ~= "" and v or nil; n = n + 1 end
        if k == "growth" then
            if v == "DOWN" or v == "UP" or v == "RIGHT" or v == "LEFT" then
                M.db.growth, M.db.vertical = v, (v == "RIGHT" or v == "LEFT"); n = n + 1
            end
            v = nil
        end
        if type(v) == "table" and k:find("Color$") then
            v = { r = tonumber(v.r) or 0, g = tonumber(v.g) or 0, b = tonumber(v.b) or 0 }
        end
        if v ~= nil and k ~= "font" and type(v) == type(M.db[k]) then M.db[k] = v; n = n + 1 end
    end
    return n > 0, n == 0 and "no known settings" or nil
end

-- replaces the lists (class, role, character) in the string, keeps the others
local function SetLists(data)
    if type(data) ~= "table" then return false, "unreadable" end
    local n = 0
    for class, list in pairs(data) do
        if mod.ValidListKey(class) and type(list) == "table" then
            local clean = {}
            for _, e in ipairs(list) do
                if type(e) == "table" and (e.t == "s" or e.t == "i") and type(e.id) == "number"
                    and type(e.cd) == "number" and e.cd >= 0 then
                    clean[#clean + 1] = { t = e.t, id = e.id, cd = e.cd, off = (e.off == true) or nil }
                end
            end
            M.db.lists[class] = clean
            n = n + 1
        end
    end
    return n > 0, n == 0 and "no class lists" or nil
end

local function SetPosition(p)
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string"
        or type(p[3]) ~= "number" or type(p[4]) ~= "number" then return false, "unreadable" end
    M.db.point = { p[1], p[2], p[3], p[4] }
    return true
end

-- everything this module can export / import (the import / export dialog)
function mod.TransferDef()
    return {
        title = "Cooldown Timers",
        prefix = "MMTCD1",
        sections = {
            { id = "lists", label = "Tracked lists", get = function() return MMT.CopyTable(M.db.lists) end, set = SetLists },
            { id = "look", label = "Window & look", get = function() return GetKeys(LOOK) end,
              set = function(d) return SetKeys(LOOK, d) end },
            { id = "position", label = "Position", get = function() return MMT.CopyTable(M.db.point) end,
              set = SetPosition },
        },
        after = function()
            mod.BuildIndex()
            mod.window:Refresh()
            mod.ShareCheck()       -- our running cooldowns that just became tracked
            mod.RequestRunning()   -- and the team's
        end,
    }
end

function mod.OpenTransfer() MMTTransfer.Open(mod.TransferDef()) end

-- the core's "Sync to team" (sync = true) replaced M.db and ran OnProfileChanged
M.OnSyncReceived = function()
    mod.ShareCheck()       -- our running cooldowns that just became tracked
    mod.RequestRunning()   -- and the team's
    mod.KnownCheck()       -- which tracked spells we haven't learned
end
