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

mod.WINDOW = "MMTCooldowns"
local BF_WINDOW = "MMTBuffs"

-- icons of a member: the ones shown here (host nil), or the ones dragged onto another bar (host = its
-- window: a Buff Timers bar, ListKeys mod.HostOf); second value: the id of every entry, in order
local function Icons(key, host)
    local icons, order = {}, {}
    -- arrange mode (shared with Buff Timers' bars): every tracked icon shows (not learned, not carried, ready), draggable (ListKeys.lua)
    local arranging = mod.Arranging("MMTCooldowns", BF_WINDOW)
    local entries, from = mod.EntriesFor(key)
    for n, e in ipairs(entries) do
        local oid = "c:" .. mod.EntryKey(e)
        order[#order + 1] = oid
        if mod.HostOf(e) == host then
            local state, start, dur = mod.State(key, e)
            if arranging and not state then state = "ready" end
            local bStart, bDur
            if state and M.db.showBuffs then bStart, bDur = mod.ActiveBuff(key, e) end
            if state and (bStart or arranging or not (M.db.hideReady and state == "ready")) then
                local icon = {
                    texture = mod.EntryIcon(e), state = state, start = start, duration = dur,
                    spell = e.t == "s" and e.id or nil, item = e.t == "i" and e.id or nil,
                    drag = arranging and mod.DragFor(from[n], e) or nil,
                    oid = oid, anchor = host and e.after or nil,
                    -- our look, also on a Buff Timers bar (IconBars v17)
                    readyAlpha = M.db.readyAlpha, cdAlpha = M.db.cdAlpha, glowActive = M.db.glowActive,
                }
                if bStart then
                    -- buff up: glow with its time left, then the cooldown
                    icon.after = { state = state, start = start, duration = dur }
                    icon.state, icon.start, icon.duration, icon.glow = "buff", bStart, bDur, true
                end
                icons[#icons + 1] = icon
            end
        end
    end
    return icons, order
end

local function Rows()
    local rows = {}
    for _, key in ipairs(mod.Members()) do
        local icons, order = Icons(key, nil)
        rows[#rows + 1] = { key = key, icons = icons, order = order, color = mod.preview and mod.PreviewColor(key) or nil }
    end
    return rows
end

-- our icons dragged onto Buff Timers' bars ride on its rows
MMTIconBars.SetExtra(BF_WINDOW, "cooldowns", function(key)
    if not (M.enabled and M.db and M.db.shown) then return nil end
    return (Icons(key, BF_WINDOW))
end, "RIGHT")

-- arrange mode on / off (session only), for Buff Timers' bars too
function mod.ToggleArrange()
    local on = not mod.Arranging("MMTCooldowns", BF_WINDOW)
    mod.SetArrangeAll(on)
    if on and not M.db.shown then MMT.Print("%s: the window is hidden (/mmtct shows it).", M.title) end
    MMT.Print("%s: %s", M.title, on and "arranging - every tracked icon shows; drag icons by their dots to reorder, or onto a Buff Timers bar. /mmtct arrange again to stop."
        or "arranging off.")
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

-- a list changed from the bars (an icon dragged): like the list editor's changes
function mod.ListsChanged()
    mod.BuildIndex()
    mod.window:Refresh()
    MMTIconBars.Refresh(BF_WINDOW)   -- icons may have moved to / from its bars
    if MMT.RefreshConfig then MMT.RefreshConfig() end   -- the list editor, if it's open
end

-- with "hide ready" an icon must go away when its cooldown ends
C_Timer.NewTicker(1, function()
    if M.enabled and M.db and M.db.hideReady and M.db.shown and not mod.Arranging("MMTCooldowns") and not MMTIconBars.IsDragging() then mod.Refresh() end
end)

mod.window = MMTIconBars.NewWindow({
    name = "MMTCooldowns",
    frameOrder = 1,   -- beside a party frame: nearest it (Buff Timers' row comes after)
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
