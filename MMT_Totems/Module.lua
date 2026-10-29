-- MMT module: Totems. Port of EMA Totems to MMT.
-- One bar per shaman in the team with the four totem elements:
--   * the active totem with its time left, else the chosen one, else the
--     last one used (dimmed while no totem is down),
--   * right-click a slot (any shaman): choose that element's totem,
--   * left-click a slot on YOUR bar: cast it,
--   * a sequence button / key that drops your totems in your element order,
--   * individual and team presets (P / TP buttons on the bars).
--
--   Data.lua      totems, elements, durations
--   Known.lua     which totems each shaman has learned (MTTK, once per login / when learning)
--   Tracker.lua   active totems: your own from the game; other shamans from
--                 one message per totem change (MTT), and group members' casts
--   Sync.lua      chosen totems / sequences (MTTS, MTTQ)
--   Bars.lua      the bars, the totem chooser, preset buttons
--   Secure.lua    casting: secure buttons, /castsequence, the key binding
--   Presets.lua   individual + team presets; PresetsDialog.lua edits them
--   Export.lua    import / export (Transfer.lua, shared with Cooldowns / Buffs)
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "Totems",
    title = "Totems",
    description = "Totem bars for the team's shamans: timers, choose and cast totems, sequences and presets.",
    sync = true,               -- the core's "Sync to team" sends M.db ...
    syncExclude = { "keybind" },   -- ... except the key binding (it belongs to one computer)
    defaults = {
        shown = true, locked = false, ungrouped = false, vertical = false,
        includeSelf = true, onlyOnline = true, order = "TEAM",
        showNames = true, fullNames = false, onlyTimers = false,
        showTimers = true, timerColor = { r = 1, g = 1, b = 1 },
        iconSize = 36, iconZoom = 8, spacing = 4, rowGap = 4, scale = 1, alpha = 1, bgAlpha = 0.4,
        hideNoItem = true,         -- hide an element whose totem item the shaman doesn't carry
        hideUnlearned = true,      -- hide an element with no totem learned yet
        hiddenElements = {},       -- [element] = true: always hidden
        inactiveAlpha = 0.4, nameSize = 11, timerSize = 16,
        bgTexture = "FLAT", bgColor = { r = 0, g = 0, b = 0 }, bgTint = 1,
        borderTexture = "NONE", borderColor = { r = 0.3, g = 0.3, b = 0.3 }, borderSize = 12,
        rowColor = { r = 0, g = 0, b = 0 }, rowAlpha = 0,   -- font = MMT font name (nil = game font)
        point = { "CENTER", "CENTER", 0, -150 },
        barPoints = {},            -- [teamKey] = point, ungrouped bars
        keybind = "", spamSafe = false,
        showPresets = true, showBarPresets = true, showTeamPreset = true,
        presetsOnHover = false, presetSide = "START",
        selected = {},             -- [teamKey] = { Fire = spellID, ... }
        sequences = {},            -- [teamKey] = "Fire, Air, Water, Earth"
        presets = {},              -- [teamKey] = { [name] = { totems = {...}, sequence, icon } }
        teamPresets = {},          -- [name] = { members = { [teamKey] = { totems, sequence } }, icon }
    },
})
mod.M = M

mod.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_Totems", "Version") or "?"

-- the team key of this character (or the plain name if it isn't in the team)
function mod.OwnKey()
    for _, key in ipairs(MMT.SortedMembers()) do
        if MMT.IsSelf(key) then return key end
    end
    return MMT.PlayerFull()
end

-- practice shaman (session only, /mmtt practice, button on the Bars tab): a made-up bar to set
-- things up where no shaman is around; it knows every totem, has every item, and nothing
-- about it is sent to the team. Whatever was chosen for it is wiped when it goes.
mod.PRACTICE = "Practice-Shaman"
mod.practice = false
function mod.IsPractice(key) return key == mod.PRACTICE end

local function ClearPractice()
    local k = mod.PRACTICE
    for _, t in ipairs({ M.db.selected, M.db.sequences, M.db.presets, M.db.barPoints }) do
        if type(t) == "table" then t[k] = nil end
    end
    if mod.active then mod.active[k] = nil end
    if mod.last then mod.last[k] = nil end
end

function mod.SetPractice(on)
    mod.practice = on and true or false
    if not mod.practice then ClearPractice() end
    mod.Refresh()
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

function mod.IsShaman(key)
    if key == mod.PRACTICE then return mod.practice end
    if MMT.IsSelf(key) then return select(2, UnitClass("player")) == "SHAMAN" end
    local m = MMT.db.team[key]
    return m and m.class == "SHAMAN" or false
end

-- shamans with a bar, in the chosen order
function mod.Shamans()
    local cfg = M.db
    local list = {}
    for i, key in ipairs(MMT.SortedMembers()) do
        if mod.IsShaman(key) then
            if MMT.IsSelf(key) then
                if cfg.includeSelf then list[#list + 1] = { key = key, pos = i } end
            elseif not cfg.onlyOnline or MMT.IsOnline(key)
                or UnitInParty(MMT.FirstName(key)) or UnitInRaid(MMT.FirstName(key)) then
                list[#list + 1] = { key = key, pos = i }
            end
        end
    end
    if mod.practice then list[#list + 1] = { key = mod.PRACTICE, pos = 999 } end
    -- a shaman that isn't in the team yet still gets its own bar
    local own = mod.OwnKey()
    if cfg.includeSelf and mod.IsShaman(own) and not MMT.db.team[own] then
        table.insert(list, 1, { key = own, pos = 0 })
    end
    local order = cfg.order
    if order == "NAME_ASC" then table.sort(list, function(a, b) return a.key < b.key end)
    elseif order == "NAME_DESC" then table.sort(list, function(a, b) return a.key > b.key end)
    elseif order == "ROLE" then
        local w = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
        local function role(k)
            local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned(MMT.FirstName(k))
            return w[r or "NONE"] or 4
        end
        table.sort(list, function(a, b)
            local ra, rb = role(a.key), role(b.key)
            if ra ~= rb then return ra < rb end
            return a.pos < b.pos
        end)
    end
    local keys = {}
    for _, e in ipairs(list) do keys[#keys + 1] = e.key end
    return keys
end

M:On("SPELL_DATA_LOAD_RESULT", function(id, ok) mod.TotemDataArrived(id, ok) end)

M.OnEnable = function()
    ClearPractice()        -- left in the profile when the game closed with it on
    mod.LoadTotemData()    -- names of totems this character never used (Data.lua)
    mod.RestoreRunning()   -- other shamans' totems from before a /reload (Tracker.lua)
    mod.Refresh()
    C_Timer.After(2, function() if M.enabled then mod.Refresh() end end)
end

M.OnDisable = function()
    mod.Refresh()
end

M.OnProfileChanged = function()
    mod.Refresh()
end

SLASH_MMTTOTEMS1 = "/mmttotems"
SLASH_MMTTOTEMS2 = "/mmtt"
SlashCmdList.MMTTOTEMS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Totems is switched off (/mmt modules).") return end
    if msg == "test" then
        mod.Test()
        MMT.Print("Totems: 10 second test on every slot.")
    elseif msg == "show" or msg == "hide" or msg == "" then
        M.db.shown = (msg == "show") or (msg == "" and not M.db.shown)
        mod.Refresh()
    elseif msg == "refresh" then
        mod.Refresh()
    elseif msg == "lock" then
        M.db.locked = not M.db.locked
        mod.Refresh()
        MMT.Print("Totem bars %s.", M.db.locked and "locked" or "unlocked")
    elseif msg == "presets" then
        mod.OpenPresets()
    elseif msg == "practice" then
        mod.SetPractice(not mod.practice)
        MMT.Print(mod.practice and "Totems: practice shaman on - a made-up bar to set things up, nothing about it is sent. /mmtt practice again (or /reload) removes it."
            or "Totems: practice shaman off.")
    elseif msg == "export" or msg == "import" then
        mod.OpenTransfer()
    else
        MMT.Print("/mmtt = show/hide, /mmtt lock, /mmtt test, /mmtt practice, /mmtt presets, /mmtt export. Settings: /mmt > MODULES > Totems.")
    end
end
