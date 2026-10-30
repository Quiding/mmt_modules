-- MMT module: Team Gear.
-- A button on the character panel lists the team; clicking a member shows
-- their equipped items in a window laid out like the inspect frame. The
-- items come from Item Compare's database of the team's gear (synced by
-- Item Compare, kept for offline members), read only. The window also shows
-- each member's talents, which this module sends itself (Talents.lua).
--
--   Window.lua    the gear window
--   Talents.lua   own talents read and sent to the team, the team's stored
--   TalentsView.lua  the talents view of the window
--   Button.lua    the button on the character panel and the member list
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.2.1"

local M = MMT.NewModule({
    name = "TeamGear",
    title = "Team Gear",
    description = "A button on the character panel shows any team member's equipped items, like inspecting them, and their talents. Needs Item Compare for the gear.",
    sync = true,
    syncExclude = { "buttonPoint", "windowPoint", "overviewPoint", "windowScale", "overviewScale" },   -- positions belong to each screen
    defaults = {
        button = true,         -- button on the character panel
        includeSelf = false,   -- you in the member list too
        names = true,          -- item names beside the slots
        windowScale = 1,       -- the gear window
        overviewScale = 1,     -- the whole-team window
        others = false,        -- also other profiles' teams and every other character Item Compare stored
    },
})
mod.M = M

---------------------------------------------------------------------------
-- Data (Item Compare's, read only)
---------------------------------------------------------------------------
function mod.HasItemCompare()
    return MMT.ModuleActive and MMT.ModuleActive("ItemCompare") or false
end

-- { items = { [slot] = itemString }, time } or nil
function mod.Equipment(key)
    local d = MMTDB and MMTDB.moduleData and MMTDB.moduleData.ItemCompare
    local e = d and d.equipment and d.equipment[key]
    if type(e) == "table" and type(e.items) == "table" then return e end
    return nil
end

function mod.ItemCount(rec)
    local n = 0
    for _ in pairs(rec and rec.items or {}) do n = n + 1 end
    return n
end

-- members for the list, in team order
function mod.Members()
    local t = {}
    local own = MMT.PlayerFull()
    if M.db.includeSelf and own then t[#t + 1] = own end
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) then t[#t + 1] = key end
    end
    return t
end

-- Item Compare keeps everyone it ever stored (account-wide, per character),
-- so the list can go past this team: { { title, keys }, ... }, this team first,
-- then each other profile's team (MMTDB.profiles, read only), then the rest.
function mod.Groups()
    local groups, seen = {}, {}
    local mine = mod.Members()
    for _, key in ipairs(mine) do seen[key] = true end
    groups[1] = { title = "Team 1", note = "this team", keys = mine }
    if not M.db.others then return groups end
    local function Stored(key) return mod.Equipment(key) ~= nil and not seen[key] and not MMT.IsSelf(key) end
    local profiles = MMTDB and MMTDB.profiles
    if type(profiles) == "table" then
        local names = {}
        for name, p in pairs(profiles) do
            if name ~= MMT.profileName and type(p) == "table" and type(p.team) == "table" then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local keys = {}
            for key in pairs(profiles[name].team) do
                if Stored(key) then keys[#keys + 1] = key; seen[key] = true end
            end
            table.sort(keys)
            if #keys > 0 then groups[#groups + 1] = { title = "Team " .. (#groups + 1), note = name, keys = keys } end
        end
    end
    local rest = {}
    local d = MMTDB and MMTDB.moduleData and MMTDB.moduleData.ItemCompare
    for key in pairs(d and d.equipment or {}) do
        if Stored(key) then rest[#rest + 1] = key; seen[key] = true end
    end
    table.sort(rest)
    if #rest > 0 then groups[#groups + 1] = { title = "Other characters", keys = rest } end
    return groups
end

-- every character of the list in order (for < >)
function mod.AllKeys()
    local t = {}
    for _, g in ipairs(mod.Groups()) do
        for _, key in ipairs(g.keys) do t[#t + 1] = key end
    end
    return t
end

-- class of a character from another profile's team (read only), or nil
local function ProfileClass(key)
    for _, p in pairs(type(MMTDB) == "table" and type(MMTDB.profiles) == "table" and MMTDB.profiles or {}) do
        local m = type(p) == "table" and type(p.team) == "table" and p.team[key]
        if type(m) == "table" and m.class then return m.class end
    end
end

function mod.ClassOf(key)
    local s = MMT.status and MMT.status[key]
    if s and s.class then return s.class, s.level end
    local pc = ProfileClass(key)
    if pc then return pc, s and s.level end
    if MMT.IsSelf(key) then
        local _, class = UnitClass("player")
        return class, UnitLevel("player")
    end
    return nil, s and s.level
end

function mod.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function mod.ClassName(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
        or (class and (class:sub(1, 1) .. class:sub(2):lower())) or ""
end

-- the group unit of a member (for the 3D model), or nil
function mod.UnitOf(key)
    if MMT.IsSelf(key) then return "player" end
    local units = {}
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local _, _, k = MMT.SplitUnit(u)
            if k and MMT.Resolve(k) == key then return u end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
M.OnEnable = function()
    mod.RememberUnit(MMT.PlayerFull(), "player")
    mod.SetupButton()
end

M.OnDisable = function()
    if mod.button then mod.button:Hide() end
    if mod.window then mod.window:Hide() end
    if mod.overview then mod.overview:Hide() end
end

M.OnProfileChanged = function()
    mod.SetupButton()
    if mod.window and mod.window:IsShown() then mod.Refresh() end
end

---------------------------------------------------------------------------
-- Looks: race and gender for the model of members out of sight
---------------------------------------------------------------------------
-- The game can't draw someone's real look without their unit, so out of
-- sight the window shows their race and gender wearing the stored gear
-- (default face and hair). Each client tells its own on MMT's heartbeat
-- ("tgl=<raceID>.<sex>", sex 2 = male, 3 = female); group members in sight
-- are read from their unit. Kept account-wide in M.store.looks[key].
local function Looks()
    M.store.looks = M.store.looks or {}
    return M.store.looks
end

function mod.LookOf(key)
    return M.store and Looks()[key]
end

local function Remember(key, race, sex)
    race, sex = tonumber(race), tonumber(sex)
    if not key or not race or not (sex == 2 or sex == 3) then return end
    local l = Looks()[key]
    if l and l.race == race and l.sex == sex then return end
    Looks()[key] = { race = race, sex = sex }
end

-- from a unit (yourself, or a group member in sight)
function mod.RememberUnit(key, unit)
    local _, _, race = MMT.Safe(UnitRace, unit)
    Remember(key, race, MMT.Safe(UnitSex, unit))
end

M:Heartbeat("tgl", function()
    local _, _, race = MMT.Safe(UnitRace, "player")
    local sex = MMT.Safe(UnitSex, "player")
    return (race and sex) and (race .. "." .. sex) or nil
end)

M:Listen("XP_RECEIVED", function(key, sender, status)
    local v = status and status.ext and status.ext.tgl
    if type(v) == "string" then
        local race, sex = v:match("^(%d+)%.(%d+)$")
        Remember(key, race, sex)
    end
end)

-- Item Compare got new gear for someone: redraw if that one is shown
M:Listen("EQUIPMENT_CHANGED", function(key)
    if mod.window and mod.window:IsShown() and mod.window.key == key then mod.Refresh() end
    if mod.RefreshOverview then mod.RefreshOverview() end
end)

SLASH_MMTTEAMGEAR1 = "/mmtgear"
SlashCmdList.MMTTEAMGEAR = function(msg)
    if not M.enabled then MMT.Print("Team Gear is switched off (/mmt modules).") return end
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        MMT.Print("Team Gear: /mmtgear <name> shows a member's gear, /mmtgear all the whole team (or use the button on the character panel).")
        return
    end
    if msg:lower() == "all" then mod.OpenOverview() return end
    local key = MMT.Resolve(msg)
    if not key then MMT.Print("%s is not in your team.", msg) return end
    mod.Open(key)
end
