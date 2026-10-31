-- MMT Buff Timers: tracked buffs drawn live in combat.
--
-- In combat this client hides every aura from addons (names, IDs, timers; even
-- "has this unit the aura with spell ID x" answers nothing). The game's own
-- aura widget still works: an AuraContainer (Blizzard_AuraContainer) is given a
-- unit and a list of spell IDs, and the GAME finds the matching aura and draws
-- it - icon, countdown, stacks - without the addon ever learning it is there.
-- ForeverAuras shows Flurry this way.
--
-- So while auras are hidden every member icon whose spell IDs are known (learned
-- while readable, Tracker.lua M.store.auraIds) gets such a widget laid over it,
-- and the icon underneath shows the "missing" look: buff up = the game draws it
-- on top, buff gone = the missing look shows. Out of combat nothing changes.
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

-- every spell ID an entry's buff is known by: learned ones (all ranks seen) + the entry's own
function mod.LiveIds(e)
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

local function Signature(ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ",")
end

-- the look of the slot's button: the aura's own icon, the game's countdown, stacks
local function Build(ov, button)
    ov.button = button
    button:SetAllPoints(ov.container)
    pcall(button.EnableMouse, button, false)
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
end

local function Style(ov, b)
    -- the icon's zoom and the timer size of the bar it sits on
    local cfg = (b.data and b.data.look) or M.db
    local z = (tonumber(cfg.iconZoom) or 8) / 100
    if ov.icon then ov.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    local numbers = ov.cooldown and ov.cooldown.GetCountdownFontString and ov.cooldown:GetCountdownFontString()
    if numbers and numbers.SetFont then
        local size = math.max(8, math.floor((b:GetHeight() or 30) * 0.4))
        pcall(numbers.SetFont, numbers, STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function NewOverlay(b)
    if not Available() then return nil end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not container then return nil end
    local ov = { container = container, enabled = false }
    container:SetEnabled(false)
    container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
    container:SetAllPoints(b)
    pcall(container.EnableMouse, container, false)
    container:SetFrameLevel(b:GetFrameLevel() + 5)
    local added = pcall(container.AddAuraSlot, container, SLOT, "HELPFUL", {
        candidateFilters = { includeSpellIDs = NONE },
        initializeFrame = function(button) Build(ov, button) end,
    })
    if not added then container:Hide() return nil end
    return ov
end

local function Disable(ov)
    if ov.enabled then pcall(ov.container.SetEnabled, ov.container, false) end
    ov.enabled = false
    ov.container:Hide()
end

-- set one overlay to a member's unit and a buff's spell IDs, on while live
local function Configure(ov, b, unit, ids)
    local sig = Signature(ids)
    if ov.unit ~= unit or ov.sig ~= sig then
        local c = ov.container
        pcall(c.SetEnabled, c, false)
        ov.enabled = false
        if ov.sig ~= sig and pcall(c.SetAuraSlotCandidateFilters, c, SLOT, { includeSpellIDs = ids }) then ov.sig = sig end
        if ov.unit ~= unit and pcall(c.SetUnit, c, unit) then ov.unit = unit end
    end
    Style(ov, b)
    ov.container:Show()
    if not ov.enabled and pcall(ov.container.SetEnabled, ov.container, true) then ov.enabled = true end
end

-- after every redraw: an overlay on each live icon of every bar (ours, and ours on the Cooldowns bars)
local hooked = {}   -- [window] = true: its own redraws (e.g. the Cooldowns bars) sync too

function mod.LiveSync()
    local lib = MMTIconBars
    local used = {}
    if lib and lib.windows then
        for _, w in pairs(lib.windows) do
            if not hooked[w] and hooksecurefunc then
                hooked[w] = true
                hooksecurefunc(w, "Refresh", function() if mod.live or mod.LiveCount() > 0 then mod.LiveSync() end end)
            end
        end
    end
    if mod.live and lib and lib.windows then
        for _, w in pairs(lib.windows) do
            for _, rows in ipairs({ w.rows or {}, w.frows or {} }) do
                for _, row in ipairs(rows) do
                    for _, b in ipairs(row.icons or {}) do
                        local live = b.data and b.data.live   -- the bar clears data on unused icons
                        local unit = live and mod.UnitOf(live.key)
                        local ids = unit and mod.LiveIds(live.e)
                        if ids then
                            local ov = overlays[b]
                            if ov == nil then ov = NewOverlay(b) or false; overlays[b] = ov end
                            if ov then Configure(ov, b, unit, ids); used[b] = true end
                        end
                    end
                end
            end
        end
    end
    for b, ov in pairs(overlays) do
        if ov and not used[b] then Disable(ov) end
    end
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
    for _, ov in pairs(overlays) do if ov then Disable(ov) end end
end
