-- MMT Buffs: what can be exported / imported (Transfer.lua does the string
-- and the dialog). Every value is checked before it is taken over.

local _, mod = ...
local MMT = MMT
local M = mod.M

local LOOK = { "bgTexture", "bgColor", "bgTint", "borderTexture", "borderColor", "borderSize", "rowColor", "rowAlpha", "timerColor", "font", "shown", "attach", "locked", "clickThrough", "vertical", "growth", "includeSelf", "onlyOnline",
    "iconSize", "iconZoom", "spacing", "rowGap", "scale", "bgAlpha", "showNames", "fullNames", "nameSize", "showTimers",
    "timerSize", "missingAlpha", "activeAlpha", "glowMissing", "glowAlerts", "allMissingLook", "onFrames", "framesSide", "framesX", "framesY", "framesIconSize", "framesFit", "framesOthers",
    "allOnFrames", "allX", "allY" }
local CHOICES = { attach = { OFF = true, LEFT = true, RIGHT = true }, allMissingLook = { PLAIN = true, RED = true, GREY = true },
    framesSide = { RIGHT = true, LEFT = true, TOP = true, BOTTOM = true }, framesOthers = { WINDOW = true, HIDE = true } }

local function GetKeys(keys)
    local t = {}
    for _, k in ipairs(keys) do t[k] = M.db[k] end
    return t
end

-- takes over values whose type (and, for choices, value) matches
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
        if v ~= nil and k ~= "font" and type(v) == type(M.db[k]) and (not CHOICES[k] or CHOICES[k][v]) then
            M.db[k] = v; n = n + 1
        end
    end
    return n > 0, n == 0 and "no known settings" or nil
end

-- replaces the lists (class, role, character) in the string, keeps the others
-- where an icon was dragged on the bars (ListKeys PlaceIcon): onto the Cooldowns bars, after the icon `after`
local function Place(t, e)
    t.host = e.host == "MMTCooldowns" and e.host or nil
    t.after = type(e.after) == "string" and #e.after <= 80 and e.after or nil
    return t
end

local function SetLists(data)
    if type(data) ~= "table" then return false, "unreadable" end
    local n = 0
    for class, list in pairs(data) do
        if mod.ValidListKey(class) and type(list) == "table" then
            local clean = {}
            for _, e in ipairs(list) do
                local only = type(e) == "table" and mod.CleanFilter and mod.CleanFilter(e.only) or nil
                if type(e) == "table" and type(e.id) == "number" then
                    clean[#clean + 1] = Place({ id = e.id, off = (e.off == true) or nil, only = only }, e)
                elseif type(e) == "table" and mod.ParsePattern and mod.ParsePattern(e.name) then
                    clean[#clean + 1] = Place({ name = mod.ParsePattern(e.name), off = (e.off == true) or nil, only = only,
                        caster = type(e.caster) == "string" and e.caster:match("^%u+$") or nil,
                        icon = type(e.icon) == "number" and e.icon or nil }, e)
                elseif type(e) == "table" and (e.weapon == "MH" or e.weapon == "OH") then
                    clean[#clean + 1] = Place({ weapon = e.weapon, off = (e.off == true) or nil, only = only }, e)
                end
            end
            M.db.lists[class] = clean
            n = n + 1
        end
    end
    return n > 0, n == 0 and "no class lists" or nil
end

local ALLROW = { "allBar", "allMissingLook", "allCount", "allCountSize", "allCountColor" }

local function GetAllRow()
    local t = GetKeys(ALLROW)
    t.exclude = MMT.CopyTable(M.db.allExclude)
    return t
end

local function SetAllRow(data)
    if type(data) ~= "table" then return false, "unreadable" end
    local ok = SetKeys(ALLROW, data)
    if type(data.exclude) == "table" then
        local ex = {}
        for key, v in pairs(data.exclude) do
            if type(key) == "string" and v == true then ex[key] = true end
        end
        M.db.allExclude = ex
        ok = true
    end
    return ok, not ok and "no known settings" or nil
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
        title = "Buff Timers",
        prefix = "MMTBF1",
        sections = {
            { id = "lists", label = "Tracked buffs", get = function() return MMT.CopyTable(M.db.lists) end, set = SetLists },
            { id = "look", label = "Window & look", get = function() return GetKeys(LOOK) end,
              set = function(d) return SetKeys(LOOK, d) end },
            { id = "allrow", label = "All bar", get = GetAllRow, set = SetAllRow },
            { id = "position", label = "Position", get = function() return MMT.CopyTable(M.db.point) end,
              set = SetPosition },
        },
        after = function()
            mod.BuildIndex()
            mod.ScanGroup()
            mod.Apply()
        end,
    }
end

function mod.OpenTransfer() MMTTransfer.Open(mod.TransferDef()) end

-- the core's "Sync to team" (sync = true) replaced M.db and ran OnProfileChanged
M.OnSyncReceived = function()
    mod.ScanGroup()
    mod.Apply()
    mod.KnownCheck()
end
