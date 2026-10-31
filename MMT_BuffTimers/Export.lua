-- MMT Buffs: what can be exported / imported (Transfer.lua does the string
-- and the dialog): one section per settings tab (TabTransfer.lua), the lists
-- by SetLists. Every value is checked before it is taken over.

local _, mod = ...
local MMT = MMT
local M = mod.M

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

-- the All bar section of strings before 0.23 (its member list was "exclude")
local function SetAllRow(data)
    if type(data) ~= "table" then return false, "unreadable" end
    local d = MMT.CopyTable(data)
    d.allExclude = d.exclude
    return mod.SetTabKeys(mod.AllTabKeys(), d)
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
        sections = mod.TabSections({ lists = { get = function() return MMT.CopyTable(M.db.lists) end, set = SetLists } }),
        -- what strings before 0.23 called their sections
        legacy = {
            { id = "look", label = "Window & look", set = function(d) return mod.SetTabKeys(mod.AllTabKeys(), d) end },
            { id = "allrow", label = "All bar", set = SetAllRow },
            { id = "position", label = "Position", set = SetPosition },
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
