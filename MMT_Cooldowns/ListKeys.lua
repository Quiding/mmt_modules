-- Which tracked lists apply to a member. M.db.lists is keyed by
--   a class token ("MAGE") or "ALL",
--   "RACE:<race token>" ("RACE:Troll", "RACE:Scourge", ...),
--   "ROLE:<role name>" (MMT roles, /mmt > Roles),
--   "CHAR:<team key>" (one character).
-- An entry with off = true stays in its list but isn't tracked.
-- Races: your own from the game; other members' from the MMT heartbeat
-- ("race=<token>", sent by MMT_Cooldowns), remembered in M.store.races.
-- MMT_Cooldowns and MMT_Buffs ship the same copy of this file (KEEP BOTH
-- IDENTICAL). It needs mod.CLASSES and mod.M.

local _, mod = ...
local MMT = MMT

local CLASS_NAMES = { ALL = "All classes" }
mod.RACES = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll" }
local RACE_NAMES = { NightElf = "Night Elf", Scourge = "Undead" }

local function IsClass(k)
    for _, c in ipairs(mod.CLASSES) do if c == k then return true end end
    return false
end

function mod.ValidListKey(k)
    if type(k) ~= "string" then return false end
    return IsClass(k) or (k:match("^RACE:%w+$") ~= nil) or (k:match("^ROLE:.+") ~= nil) or (k:match("^CHAR:.+") ~= nil)
end

function mod.ClassOf(key)
    if MMT.IsSelf(key) then return select(2, UnitClass("player")) end
    local m = MMT.db.team[key]
    return m and m.class
end

-- race token of a member (nil until their heartbeat has been seen once)
function mod.RaceOf(key)
    if MMT.IsSelf(key) then
        if not UnitRace then return nil end
        local _, race = UnitRace("player")
        return race
    end
    local s = MMT.status and MMT.status[key]
    local race = s and s.ext and s.ext.race
    local store = mod.M.store   -- nil for a moment before the module starts
    if race and race ~= "" then
        if store then
            store.races = store.races or {}
            store.races[key] = race
        end
        return race
    end
    return store and store.races and store.races[key]
end

-- list keys for a member, in order: class, [ALL], race, roles, character
function mod.ListKeysFor(key, withAll)
    local keys = {}
    local class = mod.ClassOf(key)
    if class then keys[#keys + 1] = class end
    if withAll then keys[#keys + 1] = "ALL" end
    local race = mod.RaceOf(key)
    if race then keys[#keys + 1] = "RACE:" .. race end
    for _, role in ipairs(MMT.MemberRoleList(key)) do keys[#keys + 1] = "ROLE:" .. role end
    keys[#keys + 1] = "CHAR:" .. key
    return keys
end

-- switched-on entries for a member from all their lists; id(e) removes doubles
function mod.CollectEntries(key, withAll, id)
    local out, seen = {}, {}
    for _, lk in ipairs(mod.ListKeysFor(key, withAll)) do
        for _, e in ipairs(mod.M.db.lists[lk] or {}) do
            local k = not e.off and id(e)
            if k and not seen[k] then seen[k] = true; out[#out + 1] = e end
        end
    end
    return out
end

function mod.ListLabel(k)
    local race = k:match("^RACE:(.+)$")
    if race then return "Race: " .. (RACE_NAMES[race] or race) end
    local role = k:match("^ROLE:(.+)$")
    if role then return "Role: " .. role end
    local char = k:match("^CHAR:(.+)$")
    if char then return MMT.FullDisplay(char) end
    return CLASS_NAMES[k] or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[k]) or k
end

-- races for the dropdown: the known ones, the team's and any list already made
local function AllRaces()
    local t, seen = {}, {}
    local function add(r) if r and not seen[r] then seen[r] = true; t[#t + 1] = r end end
    for _, r in ipairs(mod.RACES) do add(r) end
    for _, key in ipairs(MMT.SortedMembers()) do add(mod.RaceOf(key)) end
    add(mod.RaceOf(MMT.PlayerFull and MMT.PlayerFull() or ""))
    local extra = {}
    for k in pairs(mod.M.db.lists) do
        local r = k:match("^RACE:(.+)$")
        if r and not seen[r] then extra[#extra + 1] = r end
    end
    table.sort(extra)
    for _, r in ipairs(extra) do add(r) end
    return t
end

-- dropdown choices: classes, races, roles, characters (with the number of entries)
function mod.ListChoices()
    local lists = mod.M.db.lists
    local function Item(k)
        local n, on = 0, 0
        for _, e in ipairs(lists[k] or {}) do n = n + 1; if not e.off then on = on + 1 end end
        local count = (n == 0) and "" or (on == n and ("  |cff888888(" .. n .. ")|r")
            or ("  |cff888888(" .. on .. "/" .. n .. " on)|r"))
        return { value = k, text = mod.ListLabel(k) .. count }
    end
    local t = { { header = true, text = "Classes" } }
    for _, c in ipairs(mod.CLASSES) do t[#t + 1] = Item(c) end
    t[#t + 1] = { header = true, text = "Races" }
    for _, r in ipairs(AllRaces()) do t[#t + 1] = Item("RACE:" .. r) end
    local roles = MMT.SortedRoleNames()
    if #roles > 0 then
        t[#t + 1] = { header = true, text = "Roles" }
        for _, r in ipairs(roles) do t[#t + 1] = Item("ROLE:" .. r) end
    end
    t[#t + 1] = { header = true, text = "Characters" }
    for _, key in ipairs(MMT.SortedMembers()) do t[#t + 1] = Item("CHAR:" .. key) end
    return t
end

-- adds the preset entries of a list that aren't in it yet (switched on/off as
-- in the preset); returns how many were added. id(e) tells entries apart.
function mod.AddPreset(listKey, preset, id)
    local list = mod.M.db.lists[listKey] or {}
    mod.M.db.lists[listKey] = list
    local have = {}
    for _, e in ipairs(list) do have[id(e)] = true end
    local n = 0
    for _, e in ipairs(preset or {}) do
        if not have[id(e)] then
            local c = {}
            for k, v in pairs(e) do c[k] = v end
            list[#list + 1] = c
            n = n + 1
        end
    end
    return n
end
