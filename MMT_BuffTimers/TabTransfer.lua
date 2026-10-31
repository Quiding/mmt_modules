-- MMT Cooldown / Buff Timers: export / import sections built from the settings tabs (mod.TAB_KEYS, the
-- same lists "Reset..." uses), so every setting travels and a new one only needs adding to its tab.
-- Values are checked against the defaults' type before they are taken over. Identical in
-- MMT_CooldownTimers and MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M

-- the tabs in the dialog's order, with their labels (a tab missing from TAB_KEYS is left out)
local ORDER = {
    { "bars", "Bars (what is shown, position)" },
    { "look.window", "Look: Window" },
    { "look.icons", "Look: Icons" },
    { "look.timer", "Look: Timer" },
    { "lists", "Tracked lists" },
    { "specs", "Specs (spec lists, set by hand)" },
    { "frames", "Party frames" },
}

local SIDES = { RIGHT = true, LEFT = true, TOP = true, BOTTOM = true }
local CHOICES = {
    growth = { DOWN = true, UP = true, RIGHT = true, LEFT = true },
    attach = { OFF = true, LEFT = true, RIGHT = true },
    allMissingLook = { PLAIN = true, RED = true, GREY = true },
    allCount = { OFF = true, BOTTOMLEFT = true, BOTTOMRIGHT = true, TOPLEFT = true, TOPRIGHT = true },
    framesSide = SIDES,
    framesOthers = { WINDOW = true, HIDE = true },
}

-- a value from a string, cleaned; nil = not taken
local function Clean(k, v)
    if CHOICES[k] then return CHOICES[k][v] and v or nil end
    if k == "font" then return type(v) == "string" and v or nil end
    local d = M.defaults[k]
    if d == nil or type(v) ~= type(d) then return nil end
    if type(v) ~= "table" then return v end
    if k:find("Color$") then return { r = tonumber(v.r) or 0, g = tonumber(v.g) or 0, b = tonumber(v.b) or 0 } end
    if k == "point" then
        if type(v[1]) == "string" and type(v[2]) == "string" and type(v[3]) == "number" and type(v[4]) == "number" then
            return { v[1], v[2], v[3], v[4] }
        end
        return nil
    end
    local out = {}
    if k == "specSet" then   -- [team key] = spec ("RET")
        for key, s in pairs(v) do if type(key) == "string" and type(s) == "string" and s:match("^%u+$") then out[key] = s end end
        return out
    end
    if k == "hidden" or k == "allExclude" then   -- [team key] = true
        for key, on in pairs(v) do if type(key) == "string" and on == true then out[key] = true end end
        return out
    end
    return nil
end

-- every setting of every tab but the lists (older strings had them in one section)
function mod.AllTabKeys()
    local t = {}
    for id, keys in pairs(mod.TAB_KEYS) do
        if id ~= "lists" then for _, k in ipairs(keys) do t[#t + 1] = k end end
    end
    return t
end

function mod.GetTabKeys(keys)
    local t = {}
    for _, k in ipairs(keys) do t[k] = MMT.CopyTable(M.db[k]) end
    return t
end

-- takes over what passes Clean; returns ok, why
function mod.SetTabKeys(keys, data)
    if type(data) ~= "table" then return false, "unreadable" end
    local n = 0
    for _, k in ipairs(keys) do
        local v = data[k]
        if v ~= nil then
            if k == "font" and v == "" then M.db.font = nil; n = n + 1
            else
                v = Clean(k, v)
                if v ~= nil then
                    M.db[k] = v
                    if k == "growth" then M.db.vertical = (v == "RIGHT" or v == "LEFT") end
                    n = n + 1
                end
            end
        end
    end
    return n > 0, n == 0 and "no known settings" or nil
end

-- the dialog's sections; special[id] = { get, set } replaces the plain copy (the lists)
function mod.TabSections(special)
    local out = {}
    for _, t in ipairs(ORDER) do
        local keys = mod.TAB_KEYS[t[1]]
        if keys then
            local sp = special and special[t[1]]
            out[#out + 1] = {
                id = t[1], label = t[2],
                get = sp and sp.get or function() return mod.GetTabKeys(keys) end,
                set = sp and sp.set or function(d) return mod.SetTabKeys(keys, d) end,
            }
        end
    end
    return out
end
