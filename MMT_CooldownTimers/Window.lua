-- MMT Cooldowns: the window (rows for MMTIconBars).

local _, mod = ...
local MMT = MMT
local M = mod.M

-- members with a row, in team order
function mod.Members()
    if mod.preview == "ALL" then return mod.PreviewMembers() end   -- made-up characters (ListKeys.lua)
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
-- (second value: the list each one comes from)
function mod.EntriesFor(key)
    return mod.CollectEntries(key, true, mod.EntryKey)
end

local function Rows()
    local rows = {}
    -- arrange mode: every tracked icon shows (not learned, not carried, ready), draggable (ListKeys.lua)
    local arranging = mod.Arranging("MMTCooldowns")
    for _, key in ipairs(mod.Members()) do
        local icons = {}
        local entries, from = mod.EntriesFor(key)
        for n, e in ipairs(entries) do
            local state, start, dur = mod.State(key, e)
            if arranging and not state then state = "ready" end
            local bStart, bDur
            if state and M.db.showBuffs then bStart, bDur = mod.ActiveBuff(key, e) end
            if state and (bStart or arranging or not (M.db.hideReady and state == "ready")) then
                local icon = {
                    texture = mod.EntryIcon(e), state = state, start = start, duration = dur,
                    spell = e.t == "s" and e.id or nil, item = e.t == "i" and e.id or nil,
                    drag = arranging and mod.DragFor(from[n], e) or nil,
                }
                if bStart then
                    -- buff up: glow with its time left, then the cooldown
                    icon.after = { state = state, start = start, duration = dur }
                    icon.state, icon.start, icon.duration, icon.glow = "buff", bStart, bDur, true
                end
                icons[#icons + 1] = icon
            end
        end
        rows[#rows + 1] = { key = key, icons = icons, color = mod.preview and mod.PreviewColor(key) or nil }
    end
    return rows
end

-- arrange mode on / off (session only)
function mod.ToggleArrange()
    local on = not mod.Arranging("MMTCooldowns")
    MMTIconBars.SetArrange("MMTCooldowns", on)
    if on and not M.db.shown then MMT.Print("%s: the window is hidden (/mmtct shows it).", M.title) end
    MMT.Print("%s: %s", M.title, on and "arranging - every tracked icon shows; drag icons by their dots to reorder. /mmtct arrange again to stop."
        or "arranging off.")
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

-- a list changed from the bars (an icon dragged): like the list editor's changes
function mod.ListsChanged()
    mod.BuildIndex()
    mod.window:Refresh()
    if MMT.RefreshConfig then MMT.RefreshConfig() end   -- the list editor, if it's open
end

-- with "hide ready" an icon must go away when its cooldown ends
C_Timer.NewTicker(1, function()
    if M.enabled and M.db and M.db.hideReady and M.db.shown and not mod.Arranging("MMTCooldowns") and not MMTIconBars.IsDragging() then mod.Refresh() end
end)

mod.window = MMTIconBars.NewWindow({
    name = "MMTCooldowns",
    cfg = function() return M.db end,
    rows = Rows,
    config = function() MMT.ToggleConfig(M.name) end,
    active = function() return M.enabled end,
})

-- move tab above the window's corner while unlocked (SettingsKit), always while arranging
do
    local f = mod.window.frame
    mod.MoveTab(f, {
        locked = function() return M.db.locked end,
        start = function() f:GetScript("OnDragStart")(f) end,
        stop = function() f:GetScript("OnDragStop")(f) end,
        always = function() return MMTIconBars.Arranging("MMTCooldowns") end,
        tip = "Lock its position on the Bars tab of its settings (or /mmtct lock).",
    })
end
