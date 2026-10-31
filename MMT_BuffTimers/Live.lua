-- MMT Buff Timers: tracked buffs drawn live in combat.
--
-- In combat this client hides every aura from addons (names, IDs, timers; even
-- "has this unit the aura with spell ID x" answers nothing). The game's own
-- aura widget still works: an AuraContainer (Blizzard_AuraContainer) is given a
-- unit and a list of spell IDs, and the GAME finds the matching aura and draws
-- it - icon, countdown, stacks - without the addon ever learning it is there.
-- ForeverAuras shows Flurry this way.
--
-- So every member icon whose spell IDs are known (learned while readable,
-- Tracker.lua M.store.auraIds) gets such a widget laid over it, drawing all the
-- time (one look in and out of combat). While auras are hidden the icon
-- underneath shows the "missing" look: buff up = the game draws it on top,
-- buff gone = the missing look shows; out of combat it shows the real state.
-- The All bar keeps its last counts (counting needs reading, which is blocked).

local _, mod = ...
local MMT = MMT
local M = mod.M

local SLOT = "MMTBuff"
local NONE = { [1] = true }   -- a filter matching no aura
mod.live = false              -- true while the overlays draw (auras hidden)
local overlays = {}           -- [icon button] = overlay
local available               -- nil = not checked yet

local function Available()
    if available ~= nil then return available end
    available = false
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    available = (CustomAuraContainerAuraProcessingPolicy ~= nil) and true or false
    return available
end
mod.LiveAvailable = Available

-- every spell ID an entry's buff is known by: learned ones (all ranks seen) + the entry's own;
-- cached per entry until the learned IDs or the lists change (asked on every redraw)
local idCache = setmetatable({}, { __mode = "k" })   -- [entry] = { gen, ids, sig }

local function Signature(ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ",")
end

local function Collect(e)
    if mod.IsWeapon(e) then return nil end
    local known, ids, any = M.store.auraIds or {}, {}, false
    if mod.IsPattern(e) then
        for name, set in pairs(known) do
            if mod.Matches(e, name) then for id in pairs(set) do ids[id], any = true, true end end
        end
    else
        local name = mod.BuffName(e)
        for id in pairs(name and known[name] or {}) do ids[id], any = true, true end
        if e.id then ids[e.id], any = true, true end
    end
    return any and ids or nil
end

function mod.LiveIds(e)
    local c = idCache[e]
    if not c or c[1] ~= mod.idsGen then
        local ids = Collect(e)
        c = { mod.idsGen, ids, ids and Signature(ids) }
        idCache[e] = c
    end
    return c[2], c[3]
end

-- the look of the slot's button: the aura's own icon, the game's countdown, stacks
local function Build(ov, button)
    ov.button = button
    button:SetAllPoints(ov.container)
    pcall(button.EnableMouse, button, false)
    -- solid behind the aura's icon: the missing-look icon underneath mustn't show through
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetColorTexture(0, 0, 0, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button:SetIcon(icon)
    ov.icon = icon
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetReverse(true)
    cd:SetUseAuraDisplayTime(true)
    button:SetDurationCooldown(cd)
    ov.cooldown = cd
    local stacks = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(stacks)
    ov.stacks = stacks
    ov.bg = bg
    -- the countdown reaches 0 a moment before the game takes the aura away: the plain icon
    -- flashed up in between. Blank once the timer is done, back with the next countdown or
    -- the next aura the game puts in the slot (the icon underneath shows meanwhile)
    local function Seen(on)
        local a = on and 1 or 0
        for _, r in ipairs({ bg, icon, stacks }) do pcall(r.SetAlpha, r, a) end
    end
    pcall(cd.HookScript, cd, "OnCooldownDone", function() Seen(false) end)
    pcall(cd.HookScript, cd, "OnShow", function() Seen(true) end)
    pcall(button.HookScript, button, "OnShow", function() Seen(true) end)
end

local function Style(ov, b)
    -- the look of the bar it sits on: active opacity (not the missing one of the icon
    -- underneath: the widget is its child), zoom, the bar's timer font and colours, swipe
    local i = b.data or {}
    local cfg = i.look or M.db
    local c = ov.container
    if c.SetIgnoreParentAlpha then pcall(c.SetIgnoreParentAlpha, c, true) end
    c:SetAlpha(i.activeAlpha or cfg.activeAlpha or 1)
    local z = (tonumber(cfg.iconZoom) or 8) / 100
    if ov.icon then ov.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    local cd = ov.cooldown
    if cd then
        local sc, sa = cfg.swipeColor, tonumber(cfg.swipeAlpha) or 0.8
        if cd.SetSwipeColor then cd:SetSwipeColor(sc and sc.r or 0, sc and sc.g or 0, sc and sc.b or 0, sa) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(cfg.showTimers == false) end
        local numbers = cd.GetCountdownFontString and cd:GetCountdownFontString()
        if numbers and numbers.SetFont then
            local font, size, flags
            if b.timer and b.timer.GetFont then font, size, flags = b.timer:GetFont() end
            if not font then font, size, flags = STANDARD_TEXT_FONT, math.max(8, math.floor((b:GetHeight() or 30) * 0.4)), "OUTLINE" end
            pcall(numbers.SetFont, numbers, font, size, flags)
            local tc = cfg.timerColor
            if tc and numbers.SetTextColor then numbers:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1) end
        end
    end
    if ov.stacks and b.count and b.count.GetFont then
        local font, size, flags = b.count:GetFont()
        if font then pcall(ov.stacks.SetFont, ov.stacks, font, size, flags) end
    end
end

local stats = { made = 0, failed = 0 }
mod.liveStats = stats

local function Fail(where, err)
    stats.failed = stats.failed + 1
    stats.err = where .. ": " .. tostring(err)
    M:Debug("live overlay %s", stats.err)
end

-- built OUT of combat (ForeverAuras' note: building one while auras are restricted fails);
-- combat only switches it on
local function NewOverlay(b)
    if not Available() then return nil end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not container then Fail("CreateFrame", container) return nil end
    local ov = { container = container, enabled = false }
    local built, err = pcall(function()
        container:SetEnabled(false)
        container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
        container:SetAllPoints(b)
        pcall(container.EnableMouse, container, false)
        container:SetFrameLevel(b:GetFrameLevel() + 5)
        container:AddAuraSlot(SLOT, "HELPFUL", {
            candidateFilters = { includeSpellIDs = NONE },
            initializeFrame = function(button) Build(ov, button) end,
        })
    end)
    if not built then pcall(container.Hide, container) Fail("AddAuraSlot", err) return nil end
    stats.made = stats.made + 1
    return ov
end

local function SetOn(ov, on)
    if ov.enabled == on then return end
    local ok, err = pcall(ov.container.SetEnabled, ov.container, on)
    if ok then ov.enabled = on else Fail("SetEnabled", err) end
end

local function Disable(ov)
    SetOn(ov, false)
    ov.unit, ov.sig = nil, nil
end

-- one overlay set to a member's unit and a buff's spell IDs; drawing only while live
local function Configure(ov, b, unit, ids, sig)
    if ov.unit ~= unit or ov.sig ~= sig then
        local c = ov.container
        SetOn(ov, false)
        if ov.sig ~= sig then
            local ok, err = pcall(c.SetAuraSlotCandidateFilters, c, SLOT, { includeSpellIDs = ids })
            if ok then ov.sig = sig else Fail("filters", err) end
        end
        if ov.unit ~= unit then
            local ok, err = pcall(c.SetUnit, c, unit)
            if ok then ov.unit = unit else Fail("SetUnit", err) end
        end
    end
    if not mod.live then pcall(Style, ov, b) end
    -- drawing in and out of combat: switching to our own drawing when combat ended made the
    -- icons jump (another timer font / format / swipe); out of combat the icon underneath still
    -- shows the real state, so a buff whose ID isn't learned yet looks right there
    SetOn(ov, true)
end

-- after every redraw: an overlay on each member icon whose IDs are known, on every bar
-- (ours, and ours on the Cooldowns bars) - set up out of combat, switched on in combat
local usedScratch = {}
local hooked = {}   -- [window] = true: its own redraws (e.g. the Cooldowns bars) sync too

function mod.LiveSync()
    local lib = MMTIconBars
    if not (lib and lib.windows) or not Available() then return end
    local used = wipe(usedScratch)
    for _, w in pairs(lib.windows) do
        if not hooked[w] and hooksecurefunc then
            hooked[w] = true
            hooksecurefunc(w, "Refresh", function() mod.LiveSync() end)
        end
        for _, rows in ipairs({ w.rows or {}, w.frows or {} }) do
            for _, row in ipairs(rows) do
                for _, b in ipairs(row.icons or {}) do
                    local live = b.data and b.data.live   -- the bar clears data on unused icons
                    local unit = live and mod.UnitOf(live.key)
                    local ids, sig
                    if unit then ids, sig = mod.LiveIds(live.e) end
                    if ids then
                        local ov = overlays[b]
                        if ov == nil then ov = NewOverlay(b) or false; overlays[b] = ov end
                        if ov then Configure(ov, b, unit, ids, sig); used[b] = true end
                    end
                end
            end
        end
    end
    for b, ov in pairs(overlays) do
        if ov and not used[b] then Disable(ov) end
    end
end

-- /mmtbt live
function mod.LiveReport(say)
    local set, on = 0, 0
    for _, ov in pairs(overlays) do
        if ov then
            if ov.unit then set = set + 1 end
            if ov.enabled then on = on + 1 end
        end
    end
    say(("live: widget %s, live mode %s, auras hidden %s"):format(Available() and "yes" or "NO",
        tostring(mod.live), tostring(mod.AurasHidden and mod.AurasHidden())))
    say(("overlays: made %d, failed %d, set up %d, drawing %d%s"):format(stats.made, stats.failed, set, on,
        stats.err and (" - last error: " .. stats.err) or ""))
    local names = {}
    for name, ids in pairs(M.store.auraIds or {}) do
        local l = {}
        for id in pairs(ids) do l[#l + 1] = tostring(id) end
        names[#names + 1] = name .. " " .. table.concat(l, "/")
    end
    table.sort(names)
    say("learned: " .. (#names > 0 and table.concat(names, ", ") or "nothing yet"))
end

function mod.LiveCount()
    local n = 0
    for _, ov in pairs(overlays) do if ov and ov.enabled then n = n + 1 end end
    return n
end

-- on while auras are hidden (combat), off once they're readable again
function mod.SetLive(on)
    on = (on and Available()) and true or false
    if on == mod.live then return end
    mod.live = on
    mod.Refresh()
end

M:On("PLAYER_REGEN_DISABLED", function() mod.SetLive(true) end)
M:On("PLAYER_REGEN_ENABLED", function() mod.SetLive(false) end)

function mod.StopLive()
    mod.live = false
    for _, ov in pairs(overlays) do if ov then SetOn(ov, false) end end
end
