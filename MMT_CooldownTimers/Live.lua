-- MMT Cooldown Timers: a spell's buff drawn on its icon in combat.
--
-- "Glow while the spell's buff is up" reads the buff by name (Tracker.lua mod.ActiveBuff),
-- and in combat this client hides every aura from addons - so a cooldown used in a fight
-- went straight to its cooldown. The game's own aura widget still works then: an
-- AuraContainer (Blizzard_AuraContainer) is given a unit and a list of spell IDs, and the
-- GAME finds the matching aura and draws it - icon, countdown - without the addon learning
-- it is there (Buff Timers' Live.lua, ForeverAuras' procs).
--
-- So every member icon (Window.lua icon.cdLive) whose member is in the group gets such a
-- widget laid over it, drawing all the time: buff up = the game draws it on top with its
-- real time left; buff gone = nothing, the cooldown underneath shows. The IDs: the spell's
-- own / the item's use spell, plus every one learned while the buff was readable
-- (mod.BuffIds). Built out of combat; Buff Timers' own copy handles its icons (icon.live).

local _, mod = ...
local MMT = MMT
local M = mod.M

-- two slots: the buff, and the few self "buffs" the game files as debuffs (Death Wish)
local SLOTS = { { "MMTCooldownBuff", "HELPFUL" }, { "MMTCooldownDebuff", "HARMFUL" } }
local NONE = { [1] = true }   -- a filter matching no aura
local overlays = {}           -- [icon button] = overlay
local available               -- nil = not checked yet

local function Available(recheck)
    if available ~= nil and not recheck then return available end
    available = false
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    available = (CustomAuraContainerAuraProcessingPolicy ~= nil) and true or false
    return available
end
mod.LiveAvailable = Available

-- the entry's IDs and their signature, cached until new IDs are learned
local idCache = setmetatable({}, { __mode = "k" })   -- [entry] = { gen, ids, sig }

local function Signature(ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ",")
end

function mod.LiveIds(e)
    local c = idCache[e]
    if not c or c[1] ~= mod.buffIdsGen then
        local ids = mod.BuffIds(e)
        c = { mod.buffIdsGen, ids, ids and Signature(ids) }
        idCache[e] = c
    end
    return c[2], c[3]
end

-- The countdown reaches 0 a moment before the game takes the aura away: the icon sits in a
-- clipping frame whose right edge follows the filled end of an invisible bar the game drives
-- with the aura's time left (button:SetDurationBar), so it closes with the countdown.
local GATE_W = 200000
local WHITE = [[Interface\Buttons\WHITE8X8]]

-- one slot's drawing (part): built by the game when the slot first gets an aura
local function Build(ov, button)
    ov.button = button
    button:SetAllPoints(ov.container)
    pcall(button.EnableMouse, button, false)
    local clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
    clip:SetClipsChildren(true)
    clip:SetAllPoints(button)
    ov.clip = clip
    local content = CreateFrame("Frame", nil, clip)
    content:SetAllPoints(button)
    -- solid behind the aura's icon: the cooldown icon underneath mustn't show through
    local bg = content:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(content)
    bg:SetColorTexture(0, 0, 0, 1)
    local icon = content:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(content)
    button:SetIcon(icon)
    ov.icon = icon
    local cd = CreateFrame("Cooldown", nil, content, "CooldownFrameTemplate")
    cd:SetAllPoints(content)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetReverse(true)
    cd:SetUseAuraDisplayTime(true)
    button:SetDurationCooldown(cd)
    ov.cooldown = cd
    -- a glow around it, like the glow while the buff is up out of combat
    local glow = content:CreateTexture(nil, "OVERLAY")
    glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", content, "CENTER")
    glow:SetVertexColor(0.3, 0.9, 1)
    ov.glow = glow
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetAlpha(0)
    bar:SetPoint("TOPLEFT", button, "TOPLEFT")
    bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
    bar:SetWidth(GATE_W)
    local ok = pcall(button.SetDurationBar, button, bar,
        { direction = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime })
    ov.bar = ok and bar or nil
end

local function Gate(ov)
    if ov.gated or not (ov.clip and ov.bar and ov.button) then return end
    local ok = pcall(function()
        ov.clip:ClearAllPoints()
        ov.clip:SetPoint("TOPLEFT", ov.button, "TOPLEFT")
        ov.clip:SetPoint("BOTTOMRIGHT", ov.bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    end)
    if ok then ov.gated = true end
end

-- the look of the bar it sits on: active opacity, zoom, the timer font and colours, swipe
local function StylePart(ov, b, cfg)
    local z = (tonumber(cfg.iconZoom) or 8) / 100
    if ov.icon then ov.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    if ov.glow then
        local size = b:GetHeight() or 30
        ov.glow:SetSize(size * 1.8, size * 1.8)
        ov.glow:SetShown(cfg.glowActive ~= false)
    end
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
end

local function Style(ov, b)
    local i = b.data or {}
    local cfg = i.look or M.db
    local c = ov.container
    if c.SetIgnoreParentAlpha then pcall(c.SetIgnoreParentAlpha, c, true) end
    c:SetAlpha(i.activeAlpha or cfg.activeAlpha or 1)
    for _, part in pairs(ov.parts) do StylePart(part, b, cfg); Gate(part) end
end

local stats = { made = 0, failed = 0 }
mod.liveStats = stats

local function Fail(where, err)
    stats.failed = stats.failed + 1
    stats.err = where .. ": " .. tostring(err)
    M:Debug("buff overlay %s", stats.err)
end

-- built OUT of combat (building one while auras are restricted fails); combat only uses it
local function NewOverlay(b)
    if not Available() or (InCombatLockdown and InCombatLockdown()) then return nil end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not container then Fail("CreateFrame", container) return false end
    local ov = { container = container, enabled = false, parts = {} }
    local built, err = pcall(function()
        container:SetEnabled(false)
        container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
        container:SetAllPoints(b)
        pcall(container.EnableMouse, container, false)
        container:SetFrameLevel(b:GetFrameLevel() + 5)
        for _, slot in ipairs(SLOTS) do
            local part = { container = container }
            ov.parts[slot[1]] = part
            container:AddAuraSlot(slot[1], slot[2], {
                candidateFilters = { includeSpellIDs = NONE },
                initializeFrame = function(button) Build(part, button) end,
            })
        end
    end)
    if not built then pcall(container.Hide, container) Fail("AddAuraSlot", err) return false end
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

local function Configure(ov, b, unit, ids, sig)
    if ov.unit ~= unit or ov.sig ~= sig then
        local c = ov.container
        SetOn(ov, false)
        if ov.sig ~= sig then
            local all = true
            for _, slot in ipairs(SLOTS) do
                local ok, err = pcall(c.SetAuraSlotCandidateFilters, c, slot[1], { includeSpellIDs = ids })
                if not ok then all = false; Fail("filters", err) end
            end
            if all then ov.sig = sig end
        end
        if ov.unit ~= unit then
            local ok, err = pcall(c.SetUnit, c, unit)
            if ok then ov.unit = unit else Fail("SetUnit", err) end
        end
    end
    if not (InCombatLockdown and InCombatLockdown()) then pcall(Style, ov, b) end
    SetOn(ov, true)
end

-- after every redraw: an overlay on each cooldown icon of a member in the group, on every bar
-- (ours, and ours dragged onto the Buff Timers bars)
local usedScratch = {}
local hooked = {}

function mod.LiveSync()
    local lib = MMTIconBars
    if not (lib and lib.windows) or not Available() then return end
    local used = wipe(usedScratch)
    local on = M.enabled ~= false and M.db.showBuffs
    for _, w in pairs(lib.windows) do
        if not hooked[w] and hooksecurefunc then
            hooked[w] = true
            hooksecurefunc(w, "Refresh", function() mod.LiveSync() end)
        end
        for _, rows in ipairs({ w.rows or {}, w.frows or {} }) do
            for _, row in ipairs(rows) do
                for _, b in ipairs(row.icons or {}) do
                    local live = on and type(b.data) == "table" and b.data.cdLive   -- the bar clears data on unused icons
                    local unit = live and mod.UnitOf(live.key)
                    local ids, sig
                    if unit then ids, sig = mod.LiveIds(live.e) end
                    if ids then
                        local ov = overlays[b]
                        if not ov then
                            local made = NewOverlay(b)
                            if made ~= nil then overlays[b] = made end   -- nil: in combat, try again later
                            ov = made
                        end
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

-- /mmtct live
function mod.LiveReport(say)
    local set, drawing = 0, 0
    for _, ov in pairs(overlays) do
        if ov then
            if ov.unit then set = set + 1 end
            if ov.enabled then drawing = drawing + 1 end
        end
    end
    say(("buffs in combat: widget %s, glow setting %s, auras hidden %s"):format(Available() and "yes" or "NO",
        tostring(M.db.showBuffs), tostring(mod.AurasHidden and mod.AurasHidden())))
    say(("overlays: made %d, failed %d, set up %d, drawing %d%s"):format(stats.made, stats.failed, set, drawing,
        stats.err and (" - last error: " .. stats.err) or ""))
    local names = {}
    for ek, ids in pairs(M.store.buffIds or {}) do
        local l = {}
        for id in pairs(ids) do l[#l + 1] = tostring(id) end
        table.sort(l)
        names[#names + 1] = ek .. " " .. table.concat(l, "/")
    end
    table.sort(names)
    say("learned buff IDs: " .. (#names > 0 and table.concat(names, ", ") or "none yet (the spell's own ID is used)"))
end

function mod.StopLive()
    for _, ov in pairs(overlays) do if ov then Disable(ov) end end
end

-- combat over: overlays that couldn't be built in it now can; and the first sync after login
-- (later ones follow every bar's redraw)
M:On("PLAYER_REGEN_ENABLED", function() mod.LiveSync() end)
M:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() if M.enabled then mod.LiveSync() end end) end)
M:On("GROUP_ROSTER_UPDATE", function() C_Timer.After(0.5, function() if M.enabled then mod.LiveSync() end end) end)
