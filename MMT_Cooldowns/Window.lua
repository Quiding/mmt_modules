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
                if cfg.includeSelf or mod.preview then list[#list + 1] = key end
            elseif mod.preview or not cfg.onlyOnline or MMT.IsOnline(key)
                or UnitInParty(MMT.FirstName(key)) or UnitInRaid(MMT.FirstName(key)) then
                list[#list + 1] = key
            end
        end
    end
    return list
end

-- the entries tracked for a member: class, ALL, their roles, the character
function mod.EntriesFor(key)
    return mod.CollectEntries(key, true, mod.EntryKey)
end

local function Rows()
    local rows = {}
    for _, key in ipairs(mod.Members()) do
        local icons = {}
        for _, e in ipairs(mod.EntriesFor(key)) do
            local state, start, dur = mod.State(key, e)
            local bStart, bDur
            if state and M.db.showBuffs then bStart, bDur = mod.ActiveBuff(key, e) end
            if state and (bStart or not (M.db.hideReady and state == "ready")) then
                local icon = {
                    texture = mod.EntryIcon(e), state = state, start = start, duration = dur,
                    spell = e.t == "s" and e.id or nil, item = e.t == "i" and e.id or nil,
                }
                if bStart then
                    -- buff up: glow with its time left, then the cooldown
                    icon.after = { state = state, start = start, duration = dur }
                    icon.state, icon.start, icon.duration, icon.glow = "buff", bStart, bDur, true
                end
                icons[#icons + 1] = icon
            end
        end
        rows[#rows + 1] = { key = key, icons = icons }
    end
    return rows
end

-- with "hide ready" an icon must go away when its cooldown ends
C_Timer.NewTicker(1, function()
    if M.enabled and M.db and M.db.hideReady and M.db.shown then mod.Refresh() end
end)

mod.window = MMTIconBars.NewWindow({
    name = "MMTCooldowns",
    cfg = function() return M.db end,
    rows = Rows,
    config = function() MMT.ToggleConfig(M.name) end,
    active = function() return M.enabled end,
})
