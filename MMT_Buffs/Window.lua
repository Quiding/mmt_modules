-- MMT Buffs: own window, or icons on the Cooldowns window's rows.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CD_WINDOW = "MMTCooldowns"

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

local function EntriesFor(key)
    local m = MMT.db.team[key]
    local class = m and m.class
    if MMT.IsSelf(key) then class = select(2, UnitClass("player")) end
    local out = {}
    for _, c in ipairs({ class, "ALL" }) do
        for _, e in ipairs((c and M.db.lists[c]) or {}) do out[#out + 1] = e end
    end
    return out
end

-- icons of one member
local function Icons(key)
    local icons = {}
    for _, e in ipairs(EntriesFor(key)) do
        local state, start, dur, count = mod.State(key, e)
        if state then
            icons[#icons + 1] = { texture = mod.EntryIcon(e), state = state, start = start, duration = dur,
                count = count, spell = e.id, missingAlpha = M.db.missingAlpha, glowMissing = M.db.glowMissing }
        end
    end
    return icons
end

mod.window = MMTIconBars.NewWindow({
    name = "MMTBuffs",
    cfg = function() return M.db end,
    rows = function()
        local rows = {}
        for _, key in ipairs(mod.Members()) do rows[#rows + 1] = { key = key, icons = Icons(key) } end
        return rows
    end,
    config = function() MMT.ToggleConfig(M.name) end,
    active = function() return M.enabled end,
})

---------------------------------------------------------------------------
-- Own window or attached to Cooldowns
---------------------------------------------------------------------------
local function CooldownsActive()
    return MMT.ModuleActive and MMT.ModuleActive("Cooldowns") and MMTIconBars.windows[CD_WINDOW] ~= nil
end

function mod.Attached()
    return M.db.attach ~= "OFF" and CooldownsActive()
end

function mod.Detach()
    MMTIconBars.SetExtra(CD_WINDOW, "buffs", nil)
end

-- apply the attach setting and redraw
function mod.Apply()
    if mod.Attached() then
        mod.window:Hide()
        MMTIconBars.SetExtra(CD_WINDOW, "buffs", function(key)
            if not (M.enabled and M.db.shown) then return nil end
            return Icons(key)
        end, M.db.attach)
    else
        mod.Detach()
        mod.window:Refresh()
    end
end

-- Cooldowns switched on/off or settings changed: attach or detach again
M:Listen("REFRESH", function() mod.Apply() end)

function mod.Redraw()
    if mod.Attached() then MMTIconBars.Refresh(CD_WINDOW) else mod.window:Refresh() end
end
