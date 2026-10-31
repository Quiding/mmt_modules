-- MMT Cooldowns: what can be exported / imported (Transfer.lua does the
-- string and the dialog): one section per settings tab (TabTransfer.lua), the
-- lists by SetLists. Every value is checked before it is taken over.

local _, mod = ...
local MMT = MMT
local M = mod.M

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
                    clean[#clean + 1] = { t = e.t, id = e.id, cd = e.cd, off = (e.off == true) or nil,
                        -- dragged onto a Buff Timers bar, after its icon `after` (ListKeys PlaceIcon)
                        host = e.host == "MMTBuffs" and e.host or nil,
                        after = type(e.after) == "string" and #e.after <= 80 and e.after or nil }
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
        sections = mod.TabSections({ lists = { get = function() return MMT.CopyTable(M.db.lists) end, set = SetLists } }),
        -- what strings before 0.18 called their sections
        legacy = {
            { id = "look", label = "Window & look", set = function(d) return mod.SetTabKeys(mod.AllTabKeys(), d) end },
            { id = "position", label = "Position", set = SetPosition },
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
