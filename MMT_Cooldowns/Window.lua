-- MMT Cooldowns: the window (rows for MMTIconBars).

local _, mod = ...
local MMT = MMT
local M = mod.M

-- members with a row, in team order
function mod.Members()
    local list = {}
    local cfg = M.db
    for _, key in ipairs(MMT.SortedMembers()) do
        if not cfg.hidden[key] then
            if MMT.IsSelf(key) then
                if cfg.includeSelf then list[#list + 1] = key end
            elseif not cfg.onlyOnline or MMT.IsOnline(key)
                or UnitInParty(MMT.FirstName(key)) or UnitInRaid(MMT.FirstName(key)) then
                list[#list + 1] = key
            end
        end
    end
    return list
end

-- the entries tracked for a member: their class list, then ALL
function mod.EntriesFor(key)
    local m = MMT.db.team[key]
    local class = m and m.class
    if MMT.IsSelf(key) then class = select(2, UnitClass("player")) end
    local out = {}
    for _, c in ipairs({ class, "ALL" }) do
        for _, e in ipairs((c and M.db.lists[c]) or {}) do out[#out + 1] = e end
    end
    return out
end

local function Rows()
    local rows = {}
    for _, key in ipairs(mod.Members()) do
        local icons = {}
        for _, e in ipairs(mod.EntriesFor(key)) do
            local state, start, dur = mod.State(key, e)
            if state then
                icons[#icons + 1] = {
                    texture = mod.EntryIcon(e), state = state, start = start, duration = dur,
                    spell = e.t == "s" and e.id or nil, item = e.t == "i" and e.id or nil,
                }
            end
        end
        rows[#rows + 1] = { key = key, icons = icons }
    end
    return rows
end

mod.window = MMTIconBars.NewWindow({
    name = "MMTCooldowns",
    cfg = function() return M.db end,
    rows = Rows,
    config = function() MMT.ToggleConfig(M.name) end,
    active = function() return M.enabled end,
})
