-- Which tracked lists apply to a member. M.db.lists is keyed by
--   a class token ("MAGE") or "ALL",
--   "RACE:<race token>" ("RACE:Troll", "RACE:Scourge", ...),
--   "ROLE:<role name>" (MMT roles, /mmt > Roles),
--   "CHAR:<team key>" (one character),
--   "SPEC:<CLASS>:<SPEC>" (a talent spec, used instead of the class list while
--   "Use spec lists" is on and the member's spec is known: Specs.lua).
-- An entry with off = true stays in its list but isn't tracked.
-- Races: your own from the game; other members' from the MMT heartbeat
-- ("race=<token>", sent by MMT_Cooldowns), remembered in M.store.races.
-- MMT_CooldownTimers and MMT_BuffTimers ship the same copy of this file (KEEP BOTH
-- IDENTICAL). It needs mod.CLASSES and mod.M (and Specs.lua for spec lists).

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
        or (k:match("^SPEC:%u+:%u+$") ~= nil)
end

-- "Mixed classes" preview (mod.preview == "MIXED"): every member gets a different
-- class in this order, you first, to see the bars with other classes' lists
local MIXED = { "WARRIOR", "PALADIN", "PRIEST", "MAGE", "DRUID", "HUNTER", "ROGUE", "SHAMAN", "WARLOCK" }
function mod.PreviewClass(key)
    local i = 1
    if not MMT.IsSelf(key) then
        for n, k in ipairs(MMT.SortedMembers()) do
            if k == key then i = n + 1 break end
        end
    end
    return MIXED[(i - 1) % #MIXED + 1]
end

-- "All classes" preview (mod.preview == "ALL"): made-up characters instead of the
-- team, one of every class
local FAKE = { { "Brakka", "WARRIOR" }, { "Seraphine", "PALADIN" }, { "Tamsin", "HUNTER" }, { "Vex", "ROGUE" },
    { "Lirael", "PRIEST" }, { "Orrin", "SHAMAN" }, { "Kaelyn", "MAGE" }, { "Morwen", "WARLOCK" }, { "Thandril", "DRUID" } }
local fakeClass = {}
for _, f in ipairs(FAKE) do fakeClass[f[1] .. "-Preview"] = f[2] end
function mod.PreviewMembers()
    local t = {}
    for i, f in ipairs(FAKE) do t[i] = f[1] .. "-Preview" end
    return t
end

-- the team for a preview: the made-up characters, or the real team (+ you)
function mod.PreviewTeam()
    if mod.preview == "ALL" then return mod.PreviewMembers() end
    local t = {}
    local own = MMT.PlayerFull and MMT.PlayerFull()
    if own then t[1] = own end
    for _, key in ipairs(MMT.SortedMembers()) do if key ~= own then t[#t + 1] = key end end
    return t
end

-- name colour of a member in the preview (their previewed class)
function mod.PreviewColor(key)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[mod.ClassOf(key) or ""]
    return c and { c.r, c.g, c.b } or nil
end

function mod.ClassOf(key)
    if mod.preview == "ALL" then return fakeClass[key] end
    if mod.preview == "MIXED" then return mod.PreviewClass(key) end
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

-- list keys for a member, in order: class (or spec), [ALL], race, roles, character
function mod.ListKeysFor(key, withAll)
    local keys = {}
    local class = mod.ClassOf(key)
    local spec = class and mod.M.db.specLists and mod.SpecOf and mod.SpecOf(key)
    if spec then
        mod.EnsureSpecLists()
        keys[#keys + 1] = "SPEC:" .. spec
    elseif class then
        keys[#keys + 1] = class
    end
    if withAll then keys[#keys + 1] = "ALL" end
    local race = mod.RaceOf(key)
    if race then keys[#keys + 1] = "RACE:" .. race end
    for _, role in ipairs(MMT.MemberRoleList(key)) do keys[#keys + 1] = "ROLE:" .. role end
    keys[#keys + 1] = "CHAR:" .. key
    return keys
end

-- switched-on entries for a member from all their lists; id(e) removes doubles.
-- Second value: from[i] = the list key out[i] came from.
function mod.CollectEntries(key, withAll, id)
    local out, from, seen = {}, {}, {}
    for _, lk in ipairs(mod.ListKeysFor(key, withAll)) do
        for _, e in ipairs(mod.M.db.lists[lk] or {}) do
            local k = not e.off and id(e)
            if k and not seen[k] then seen[k] = true; out[#out + 1] = e; from[#out] = lk end
        end
    end
    return out, from
end

-- Arrange mode of any of these IconBars windows (session only, /mmtct arrange, /mmtbt arrange): every
-- tracked icon shows, whatever the hide options say, and icons can be dragged to reorder their list.
function mod.Arranging(...)
    for i = 1, select("#", ...) do
        if MMTIconBars.Arranging(select(i, ...)) then return true end
    end
    return false
end

-- an icon dragged on the bars: move its entry in its list (mod.MoveEntry: SettingsKit), then the
-- module's mod.ListsChanged() redraws like the list editor does
local function Move(src, dst, after)
    local l = src.group
    local from, to
    for i, e in ipairs(l) do
        if e == src.id then from = i end
        if e == dst.id then to = i end
    end
    return from and to and mod.MoveEntry(l, from, after and to + 1 or to)
end

local function MoveIcon(src, dst, after)
    if Move(src, dst, after) then mod.ListsChanged() end
end

-- the bars an icon can be dragged to: Cooldown Timers' and Buff Timers' (IconBars v16 drag.place)
local HOSTS = { MMTCooldowns = true, MMTBuffs = true }

-- an icon dropped on a bar: on the other module's bar it stays there (e.host, e.after = the icon there it
-- follows), on our own bar it comes home; next to an icon of its own list it also moves in that list.
-- mod.WINDOW = our window's name; mod.ImpliedHost() = the window all our icons go to anyway (Buff Timers
-- attached to the Cooldowns bars): there only the spot is kept, so detaching brings everything home
local function PlaceIcon(src, win, anchor, nbr, after)
    local e = src.id
    if win == mod.WINDOW then
        e.host, e.after = nil, nil
    elseif mod.ImpliedHost and mod.ImpliedHost() == win then
        e.after = anchor
    else
        e.host, e.after = win, anchor
    end
    if nbr and nbr.group == src.group then Move(src, nbr, after) end
    mod.ListsChanged()
end

-- the window an entry's icon shows in: ours (nil) or the other module's bar it was dragged to
function mod.HostOf(e)
    if mod.ImpliedHost and mod.ImpliedHost() then return mod.ImpliedHost() end
    if e.host and e.host ~= mod.WINDOW and HOSTS[e.host] and MMTIconBars.CanHost(e.host) then return e.host end
end

-- an entry of ours shows on the other module's bar (that bar needs redrawing with ours)
function mod.Guesting()
    if mod.ImpliedHost and mod.ImpliedHost() then return true end
    for _, l in pairs(mod.M.db.lists or {}) do
        for _, e in ipairs(l) do if e.host and e.host ~= mod.WINDOW and not e.off then return true end end
    end
    return false
end

-- arrange mode is shared by both modules' bars (icons can move between them)
function mod.SetArrangeAll(on)
    -- every flag first: a bar redrawn while the other's flag is still set would keep arranging
    for name in pairs(HOSTS) do MMTIconBars.arrange[name] = on and true or nil end
    for name in pairs(HOSTS) do MMTIconBars.Refresh(name) end
end

-- icon.drag for an entry of list lk (only while arranging)
function mod.DragFor(lk, e)
    local l = lk and mod.M.db.lists[lk]
    if l then return { group = l, id = e, move = MoveIcon, place = PlaceIcon, hosts = HOSTS } end
end

function mod.ListLabel(k)
    local race = k:match("^RACE:(.+)$")
    if race then return "Race: " .. (RACE_NAMES[race] or race) end
    local role = k:match("^ROLE:(.+)$")
    if role then return "Role: " .. role end
    local char = k:match("^CHAR:(.+)$")
    if char then return MMT.FullDisplay(char) end
    local spec = k:match("^SPEC:(.+)$")
    if spec then
        local p = mod.PresetByKey(spec)
        return p and p.name or spec
    end
    if k == "ALL" and mod.ALL_LABEL then return mod.ALL_LABEL end   -- Buffs: "All bar"
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

-- the list the editor starts on: your spec's list (spec lists on), else your class's
function mod.OwnListKey()
    local own = MMT.PlayerFull and MMT.PlayerFull()
    local spec = mod.M.db.specLists and mod.SpecOf and own and mod.SpecOf(own)
    if spec then return "SPEC:" .. spec end
    return select(2, UnitClass("player")) or "ALL"
end

-- dropdown choices: classes (or specs), races, roles, characters (with the number of entries)
-- which lists apply to the team right now: [list key] = { first names }
function mod.ListsInUse()
    local used, team, seen = {}, {}, {}
    local own = MMT.PlayerFull and MMT.PlayerFull()
    if own then team[1] = own; seen[own] = true end
    for _, key in ipairs(MMT.SortedMembers()) do if not seen[key] then team[#team + 1] = key end end
    for _, key in ipairs(team) do
        for _, lk in ipairs(mod.ListKeysFor(key, true)) do
            used[lk] = used[lk] or {}
            table.insert(used[lk], MMT.FirstName and MMT.FirstName(key) or key:match("^[^-]+") or key)
        end
    end
    return used
end

function mod.ListChoices()
    local lists = mod.M.db.lists
    local used = mod.ListsInUse()
    local function Item(k)
        local n, on = 0, 0
        for _, e in ipairs(lists[k] or {}) do n = n + 1; if not e.off then on = on + 1 end end
        local count = (n == 0) and "" or (on == n and ("  |cff888888(" .. n .. ")|r")
            or ("  |cff888888(" .. on .. "/" .. n .. " on)|r"))
        -- in use: who it applies to right now, in green
        local who = used[k]
        local names = ""
        if who then
            names = k == "ALL" and "everyone" or table.concat(who, ", ", 1, math.min(#who, 3))
            if k ~= "ALL" and #who > 3 then names = names .. " +" .. (#who - 3) end
            names = "  |cff55dd55" .. names .. "|r"
        end
        return { value = k, text = mod.ListLabel(k) .. count .. names }
    end
    local t = {}
    local specs = mod.M.db.specLists and mod.SpecsOf
    if specs then
        -- spec lists on: the class lists are left out of the menu (only the All list stays);
        -- a member whose spec isn't known still uses theirs
        t[#t + 1] = Item("ALL")
    else
        t[#t + 1] = { header = true, text = "Classes" }
        for _, c in ipairs(mod.CLASSES) do t[#t + 1] = Item(c) end
    end
    if specs then
        mod.EnsureSpecLists()
        t[#t + 1] = { header = true, text = "Specs" }
        for _, c in ipairs(mod.CLASSES) do
            for _, s in ipairs(mod.SpecsOf(c)) do t[#t + 1] = Item("SPEC:" .. c .. ":" .. s) end
        end
    end
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

-- presets (mod.PRESETS) for the dropdown: the ones made for this kind of list
-- first (its class, races for a race list, "every member" for ALL), then the rest
function mod.PresetChoices(listKey)
    local group
    local spec = listKey and listKey:match("^SPEC:(.+)$")
    if listKey == "ALL" or IsClass(listKey) then group = listKey
    elseif spec then group = spec:match("^(%u+):")
    elseif listKey and listKey:match("^RACE:") then group = "RACE" end
    local fit, other = {}, {}
    for _, p in ipairs(mod.PRESETS or {}) do
        local item = { value = p.key, text = p.name }
        if p.key == spec then table.insert(fit, 1, item)   -- a spec list: its own spec's preset first
        elseif p.group == group or (group == "RACE" and p.race and listKey == "RACE:" .. p.race) then fit[#fit + 1] = item
        else other[#other + 1] = item end
    end
    local t = {}
    if #fit > 0 then
        t[#t + 1] = { header = true, text = "For this list" }
        for _, i in ipairs(fit) do t[#t + 1] = i end
    end
    t[#t + 1] = { header = true, text = (#fit > 0) and "Other presets" or "Presets" }
    for _, i in ipairs(other) do t[#t + 1] = i end
    return t
end

function mod.PresetByKey(key)
    for _, p in ipairs(mod.PRESETS or {}) do if p.key == key then return p end end
end

-- the first preset made for a list (the dropdown's starting value)
function mod.DefaultPreset(listKey)
    for _, c in ipairs(mod.PresetChoices(listKey)) do
        if not c.header then return c.value end
    end
end

-- puts a preset into a list: replace = the list becomes the preset, else only
-- the entries it misses are added. Returns how many entries were added.
function mod.ApplyPreset(listKey, presetKey, replace, id)
    local p = mod.PresetByKey(presetKey)
    if not p then return 0 end
    if replace then mod.M.db.lists[listKey] = {} end
    return mod.AddPreset(listKey, p.entries, id)
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
            for k, v in pairs(e) do c[k] = type(v) == "table" and MMT.CopyTable(v) or v end
            list[#list + 1] = c
            n = n + 1
        end
    end
    return n
end
