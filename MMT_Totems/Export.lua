-- MMT Totems: what can be exported / imported (Transfer.lua does the string
-- and the dialog). Every value is checked before it is taken over. The key
-- binding is not exported (it belongs to one computer).

local _, mod = ...
local MMT = MMT
local M = mod.M

local LOOK = { "shown", "locked", "ungrouped", "vertical", "includeSelf", "onlyOnline", "order",
    "showNames", "fullNames", "onlyTimers", "showTimers", "timerColor", "iconSize", "spacing", "rowGap",
    "scale", "alpha", "bgAlpha", "inactiveAlpha", "nameSize", "timerSize", "spamSafe",
    "showPresets", "showBarPresets", "showTeamPreset", "presetsOnHover", "presetSide",
    "bgTexture", "bgColor", "bgTint", "borderTexture", "borderColor", "borderSize", "rowColor", "rowAlpha", "font" }
local CHOICES = {
    order = { TEAM = true, NAME_ASC = true, NAME_DESC = true, ROLE = true },
    presetSide = { START = true, END = true },
}

local function GetLook()
    local t = {}
    for _, k in ipairs(LOOK) do t[k] = M.db[k] end
    t.font = M.db.font or ""
    return t
end

local function SetLook(data)
    if type(data) ~= "table" then return false, "unreadable" end
    local n = 0
    for _, k in ipairs(LOOK) do
        local v = data[k]
        if k == "font" then
            -- nil in the profile = game font, so the type can't be checked against it
            if type(v) == "string" then M.db.font = v ~= "" and v or nil; n = n + 1 end
        elseif v ~= nil and type(v) == type(M.db[k]) and (not CHOICES[k] or CHOICES[k][v]) then
            if type(v) == "table" and k:find("Color$") then
                v = { r = tonumber(v.r) or 0, g = tonumber(v.g) or 0, b = tonumber(v.b) or 0 }
            end
            M.db[k] = v
            n = n + 1
        end
    end
    return n > 0, n == 0 and "no known settings" or nil
end

local function ValidPoint(p)
    return type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
        and type(p[3]) == "number" and type(p[4]) == "number"
end

local function SetPosition(data)
    if type(data) ~= "table" or not ValidPoint(data.point) then return false, "unreadable" end
    M.db.point = { data.point[1], data.point[2], data.point[3], data.point[4] }
    local bp = {}
    for key, p in pairs(type(data.bars) == "table" and data.bars or {}) do
        if type(key) == "string" and ValidPoint(p) then bp[key] = { p[1], p[2], p[3], p[4] } end
    end
    M.db.barPoints = bp
    return true
end

function mod.OpenTransfer()
    MMTTransfer.Open({
        title = "Totems",
        prefix = "MMTTT1",
        sections = {
            { id = "look", label = "Bars & look", get = GetLook, set = SetLook },
            { id = "totems", label = "Chosen totems & sequences",
              get = function() return { selected = MMT.CopyTable(M.db.selected), sequences = MMT.CopyTable(M.db.sequences) } end,
              set = function(d)
                  if type(d) ~= "table" then return false, "unreadable" end
                  return mod.TakeOver(d, { totems = true })
              end },
            { id = "presets", label = "Presets",
              get = function() return { presets = MMT.CopyTable(M.db.presets), teamPresets = MMT.CopyTable(M.db.teamPresets) } end,
              set = function(d)
                  if type(d) ~= "table" then return false, "unreadable" end
                  return mod.TakeOver(d, { presets = true })
              end },
            { id = "position", label = "Position",
              get = function() return { point = MMT.CopyTable(M.db.point), bars = MMT.CopyTable(M.db.barPoints) } end,
              set = SetPosition },
        },
        after = function() mod.Refresh() end,
    })
end
