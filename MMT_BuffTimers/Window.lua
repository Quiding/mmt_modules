-- MMT Buffs: own window, or icons on the Cooldowns window's rows.
--
-- "All classes" row (M.db.allBar): one icon per buff of the ALL list for the
-- whole team (minus M.db.allExclude). Shown as missing when anyone lacks it
-- (tooltip says who), otherwise the shortest time left of all members. The
-- ALL buffs are then left out of the members' own rows. When the buffs are
-- attached to the Cooldowns bars, the Buffs window still shows this row.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CD_WINDOW = "MMTCooldowns"
mod.WINDOW = "MMTBuffs"

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

-- class, ALL (unless the All classes row has them), their roles, the character
-- (second value: the list each one comes from)
local function EntriesFor(key)
    local list, from = mod.CollectEntries(key, not M.db.allBar, mod.BuffName)
    if not M.db.allBar then return list, from end
    -- a buff the All bar shows stays out of the member's row, even when a class list has it too
    local inAll = {}
    for _, e in ipairs(M.db.lists.ALL or {}) do
        local name = not e.off and (mod.BuffName(e) or mod.EntryKey(e))
        if name then inAll[name] = true end
    end
    local out, outFrom = {}, {}
    for n, e in ipairs(list) do
        if not inAll[mod.BuffName(e) or mod.EntryKey(e) or ""] then out[#out + 1] = e; outFrom[#out] = from[n] end
    end
    return out, outFrom
end

-- arrange mode for the member rows (ListKeys.lua): shared by our bars and the Cooldowns bars
local function ArrangingRows()
    return mod.Arranging("MMTBuffs", CD_WINDOW)
end

-- look of a buff icon (missing: normal / red / grey, glow; active: opacity),
-- carried on the icon so it also holds on the Cooldowns bars
local RED = { 1, 0.25, 0.25 }
local function Look(i)
    local cfg = M.db
    i.missingAlpha, i.glowMissing, i.activeAlpha = cfg.missingAlpha, cfg.glowMissing, cfg.activeAlpha
    if i.state == "missing" then
        if cfg.allMissingLook == "RED" then i.tint = RED
        elseif cfg.allMissingLook == "GREY" then i.desaturate = true end
    end
    return i
end

-- icons of one member: the ones shown here (host nil), or the ones on another bar (host = its window: the
-- Cooldowns bars, all of them while attached; ListKeys mod.HostOf); second value: every entry's id, in order
local function Icons(key, host)
    local icons, order = {}, {}
    local arranging = ArrangingRows()
    local entries, from = EntriesFor(key)
    for n, e in ipairs(entries) do
        local oid = "b:" .. tostring(mod.EntryKey(e))
        order[#order + 1] = oid
        local state, start, dur, count, matched, micon
        if mod.HostOf(e) == host then
        -- "Only for" (Roles.lua), nobody here can cast it (Casters.lua)
        if arranging or (mod.Applies(e, key) and mod.Castable(e)
            and not (M.db.hideUnlearned and mod.Unlearned(key, e))) then
            state, start, dur, count, matched, micon = mod.State(key, e)
            -- a blessing they can't get: they already have one from every paladin here
            if not arranging and state == "missing" and mod.BlessingCovered(key, e) then state = nil end
            if arranging and not state then state = "ready" end
        end
        end
        if state then
            icons[#icons + 1] = Look({ texture = micon or mod.EntryIcon(e), state = state, start = start, duration = dur,
                count = count, spell = e.id, drag = arranging and mod.DragFor(from[n], e) or nil,
                oid = oid, anchor = host and e.after or nil,
                glow = mod.Alerted(key, e, state, start) or nil,   -- SmartBuff says it's missing (Alerts.lua)
                tip = mod.IsPattern(e) and (matched and (matched .. "  (" .. e.name .. ")")
                        or state == "missing" and ("None of " .. e.name) or e.name)
                    or mod.IsWeapon(e) and (matched and (matched .. "  (" .. mod.EntryName(e) .. ")")
                        or state == "missing" and ("No " .. mod.EntryName(e):lower()) or mod.EntryName(e)) or nil })
        end
    end
    return icons, order
end

---------------------------------------------------------------------------
-- All classes row
---------------------------------------------------------------------------
-- members counted in the All classes row
function mod.AllMembers()
    local list = {}
    for _, key in ipairs(mod.Members()) do
        if not M.db.allExclude[key] then list[#list + 1] = key end
    end
    return list
end

local function AllRow()
    local cfg = M.db
    local icons = {}
    local members = mod.AllMembers()
    -- arrange mode: every switched-on buff of the list shows, draggable
    local arranging = mod.Arranging("MMTBuffs")
    for _, e in ipairs(cfg.lists.ALL or {}) do
        local before = #icons
        -- only the members this buff is for ("Only for", Roles.lua)
        local forThem = {}
        if not e.off and (arranging or mod.Castable(e)) then
            for _, key in ipairs(members) do if arranging or mod.Applies(e, key) then forThem[#forThem + 1] = key end end
        end
        local missingBy, noData, have, covered, alerted = {}, 0, 0, 0, false
        local minStart, minDur, minLeft
        if #forThem > 0 then
        for _, key in ipairs(forThem) do
            local state, start, dur = mod.State(key, e)
            if mod.Alerted(key, e, state, start) then alerted = true end   -- SmartBuff (Alerts.lua)
            -- a blessing they can't get (one per paladin, Casters.lua): not counted
            if not arranging and state == "missing" and mod.BlessingCovered(key, e) then state = "covered" end
            if state == "covered" then
                covered = covered + 1
            elseif state == nil then
                noData = noData + 1
            elseif state == "missing" then
                missingBy[#missingBy + 1] = MMTIconBars.MemberName(key, cfg.fullNames)
            elseif state == "buff" then
                have = have + 1
            end
            if state == "buff" and start and dur then
                local left = start + dur - GetTime()
                if not minLeft or left < minLeft then minStart, minDur, minLeft = start, dur, left end
            end
        end
        -- nobody needs it right now (everyone checked has their blessings from the paladins here)
        if have == 0 and #missingBy == 0 and covered > 0 then forThem = {} end
        end
        if #forThem > 0 then
        local i = { texture = mod.EntryIcon(e), spell = e.id }
        if mod.IsPattern(e) or mod.IsWeapon(e) then i.tip = mod.EntryName(e) end
        if #missingBy > 0 or noData == #forThem - covered then
            i.state = "missing"
            i.tip = #missingBy > 0 and ("Missing: " .. table.concat(missingBy, ", ")) or "Nobody in your group to check."
        else
            i.state, i.start, i.duration = "buff", minStart, minDur
            i.tip = "Everyone has it" .. (minLeft and ", shortest time left shown." or ".")
        end
        local only = mod.FilterText(e)
        if only then i.tip = i.tip .. "\nOnly for: " .. only end
        if noData > 0 and #missingBy > 0 then i.tip = i.tip .. (" (%d not in your group)"):format(noData) end
        -- while someone misses it: "have / checked" (3/5) in its corner (Look > All bar counter);
        -- one number only, nothing once everyone has it (the timer shows)
        local checked = #forThem - noData - covered
        if cfg.allCount and cfg.allCount ~= "OFF" and #missingBy > 0 and checked > 0 then
            i.tally, i.tallyPos, i.tallySize, i.tallyColor = have .. "/" .. checked, cfg.allCount, cfg.allCountSize, cfg.allCountColor
            i.tip = i.tip .. ("\n%d of %d have it."):format(have, checked)
        end
        if alerted then
            i.glow = true
            i.tip = i.tip .. "\nSmartBuff: someone needs it."
        end
        icons[#icons + 1] = Look(i)
        end
        if arranging and not e.off then
            -- shown even when nobody needs it now
            if #icons == before then
                icons[#icons + 1] = Look({ texture = mod.EntryIcon(e), state = "ready", spell = e.id,
                    tip = (mod.IsPattern(e) or mod.IsWeapon(e)) and mod.EntryName(e) or nil })
            end
            icons[#icons].drag = mod.DragFor("ALL", e)
        end
    end
    return { label = "All", color = { 1, 0.82, 0 }, icons = icons }
end

mod.window = MMTIconBars.NewWindow({
    name = "MMTBuffs",
    frameOrder = 2,   -- beside a party frame: after Cooldown Timers' row
    cfg = function() return M.db end,
    rows = function()
        local rows = {}
        if M.db.allBar then
            local all = AllRow()
            if #all.icons > 0 then rows[1] = all end
        end
        if not mod.Attached() then
            for _, key in ipairs(mod.Members()) do
                -- a member with nothing tracked (or nothing readable, Cooldowns' icons dragged here included) gets no empty row
                local icons, order = Icons(key, nil)
                rows[#rows + 1] = { key = key, icons = icons, order = order, dropEmpty = true,
                    color = mod.preview and mod.PreviewColor(key) or nil }
            end
        end
        return rows
    end,
    config = function() MMT.ToggleConfig(M.name) end,
    active = function() return M.enabled end,
    guests = function() return not mod.Attached() end,   -- attached: no member rows to take Cooldowns' icons
})

-- move tab above the window's corner while unlocked (SettingsKit), always while arranging
do
    local f = mod.window.frame
    mod.MoveTab(f, {
        locked = function() return M.db.locked end,
        start = function() f:GetScript("OnDragStart")(f) end,
        stop = function() f:GetScript("OnDragStop")(f) end,
        always = function() return MMTIconBars.Arranging("MMTBuffs") end,
        tip = "Lock its position on the Bars tab of its settings (or /mmtbt lock).",
    })
end

---------------------------------------------------------------------------
-- Own window or attached to Cooldowns
---------------------------------------------------------------------------
local function CooldownsActive()
    return MMT.ModuleActive and MMT.ModuleActive("CooldownTimers") and MMTIconBars.windows[CD_WINDOW] ~= nil
end

function mod.Attached()
    return M.db.attach ~= "OFF" and CooldownsActive()
end

function mod.Detach()
    MMTIconBars.SetExtra(CD_WINDOW, "buffs", nil)
end

-- attached: every buff icon goes on the Cooldowns bars (ListKeys mod.HostOf / PlaceIcon)
function mod.ImpliedHost() return mod.Attached() and CD_WINDOW or nil end

-- apply the attach setting and redraw; our icons on the Cooldowns bars (all of them while attached,
-- else the ones dragged there) ride on its rows, by default at the attach side
function mod.Apply()
    mod.window:Refresh()   -- attached: only the All classes row, if on
    MMTIconBars.SetExtra(CD_WINDOW, "buffs", function(key)
        if not (M.enabled and M.db.shown) then return nil end
        return (Icons(key, CD_WINDOW))
    end, M.db.attach == "LEFT" and "LEFT" or "RIGHT")
end

-- arrange mode on / off (session only); attached, it covers our icons on the Cooldowns bars too
function mod.ToggleArrange()
    local on = not mod.Arranging("MMTBuffs", CD_WINDOW)
    mod.SetArrangeAll(on)   -- the Cooldowns bars too (ListKeys.lua)
    mod.Apply()
    if on and not M.db.shown then MMT.Print("%s: the window is hidden (/mmtbt shows it).", M.title) end
    MMT.Print("%s: %s", M.title, on and "arranging - every tracked buff shows; drag icons by their dots to reorder, or onto a Cooldown Timers bar. /mmtbt arrange again to stop."
        or "arranging off.")
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

-- a list changed from the bars (an icon dragged): like the list editor's changes
function mod.ListsChanged()
    mod.BuildIndex()
    mod.ScanGroup()
    mod.Apply()
    mod.KnownCheck()
    if MMT.RefreshConfig then MMT.RefreshConfig() end   -- the list editor, if it's open
end

-- Cooldowns switched on/off or settings changed: attach or detach again
M:Listen("REFRESH", function() mod.Apply() end)

function mod.Redraw()
    if mod.Guesting() then MMTIconBars.Refresh(CD_WINDOW) end   -- our icons on its bars
    mod.window:Refresh()
end
