-- MMT Quality of life: Dejunk's lists, the same on the whole team.
--
-- Dejunk has no API to add or remove list items (DejunkApi only offers
-- IsJunk and a listener), so:
--   * changes here: DejunkApi:AddListener tells us its state changed; we
--     compare its four lists with what we saw last and send the difference
--     (QDJ:+GI2589,-GE2589 ...: sign, list, item ID).
--   * changes from the team: written into the lists in Dejunk's saved state
--     (the same tables its store holds). Dejunk keeps its own copy of the
--     lists in memory and only reads the state at login, so they work after a
--     /reload. Until then Dejunk saves its copy over them when that list
--     changes here; `pending` puts them back (and is not sent on).
-- Lists: GI / GE global junk / not junk, PI / PE the active profile's.

local _, mod = ...
local MMT = MMT
local M = mod.M

local SV = "__DEJUNK_ADDON_V3_SAVED_VARIABLES__"
local DEFAULT_PROFILE = "DEFAULT_PROFILE"
local LISTS = { "GI", "GE", "PI", "PE" }
local OPPOSITE = { GI = "GE", GE = "GI", PI = "PE", PE = "PI" }
local NAMES = { GI = "junk (global)", GE = "not junk (global)", PI = "junk (profile)", PE = "not junk (profile)" }
local BULK = 10      -- more changes at once (import, "Remove all", profile reset) are not sent
local MSG_MAX = 240

local F
local ready = false  -- Dejunk's store exists (its first state update came)
local snap           -- [list][id] = true: what we saw last
local profileId      -- Dejunk profile of snap's PI / PE
local pending = { GI = {}, GE = {}, PI = {}, PE = {} }  -- [list][id] = "+" | "-" from the team, not in Dejunk's copy yet
local queued, reloadNoted
local dj = { sent = 0, taken = 0 }
mod.dj = dj

-- the same key Dejunk uses for its character -> profile map
local function CharKey()
    local forever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
    local name = forever and GetUnitName and GetUnitName("player") or UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    return ("%s-%s"):format(tostring(name), tostring(realm))
end

-- the live list tables (key -> true, keys are item IDs as strings), profile ID
local function State()
    local sv = rawget(_G, SV)
    if type(sv) ~= "table" or type(sv.global) ~= "table" or type(sv.profiles) ~= "table" then return nil end
    local p = sv.profiles
    local map = type(p.profileMap) == "table" and p.profileMap or {}
    local id = type(p.characterMap) == "table" and p.characterMap[CharKey()] or DEFAULT_PROFILE
    if type(map[id]) ~= "table" then id = DEFAULT_PROFILE end
    local s = type(map[id]) == "table" and map[id].settings
    local function T(t) return type(t) == "table" and t or nil end
    return {
        GI = T(sv.global.inclusions), GE = T(sv.global.exclusions),
        PI = s and T(s.inclusions), PE = s and T(s.exclusions),
    }, id
end
mod.DejunkState = State

local function Copy(t)
    local r = {}
    for k, v in pairs(t or {}) do r[k] = v end
    return r
end

local function Wanted(sign, list)
    if sign == "+" and not M.db.djAdd then return false end
    if sign == "-" and not M.db.djRemove then return false end
    if list:sub(1, 1) == "P" and not M.db.djProfile then return false end
    return true
end

local function SendOps(tag, ops)
    local msg = ""
    for _, op in ipairs(ops) do
        if #msg + #op + 1 > MSG_MAX - #tag - 1 then
            MMT.SendToTeam(tag .. ":" .. msg, true)
            msg = ""
        end
        msg = msg == "" and op or (msg .. "," .. op)
    end
    if msg ~= "" then MMT.SendToTeam(tag .. ":" .. msg, true) end
end

-- what changed here since we looked last
local function Check()
    queued = false
    if not mod.Active(F) or not ready then snap = nil return end
    local lists, id = State()
    if not lists then return end
    if snap and id ~= profileId then
        -- another Dejunk profile: its lists are not a change
        snap.PI, snap.PE = Copy(lists.PI), Copy(lists.PE)
        pending.PI, pending.PE = {}, {}
        profileId = id
    end
    if not snap then
        snap, profileId = {}, id
        for _, k in ipairs(LISTS) do snap[k] = Copy(lists[k]) end
        return
    end

    local adds, dels, readd, redel = {}, {}, {}, {}
    for _, k in ipairs(LISTS) do
        local now, old, pend = lists[k] or {}, snap[k] or {}, pending[k]
        for item in pairs(now) do
            if not old[item] then
                if pend[item] == "-" then redel[#redel + 1] = { k, item }
                else adds[#adds + 1] = { k, item }; pend[item] = nil end
            end
        end
        for item in pairs(old) do
            if not now[item] then
                if pend[item] == "+" then readd[#readd + 1] = { k, item }
                else dels[#dels + 1] = { k, item }; pend[item] = nil end
            end
        end
    end
    -- Dejunk saved its own copy over what the team sent: put it back, unless
    -- the item was put on the opposite list here just now (that one counts)
    local addedTo = {}
    for _, a in ipairs(adds) do addedTo[a[1] .. a[2]] = true end
    for _, r in ipairs(readd) do
        local k, item = r[1], r[2]
        if addedTo[OPPOSITE[k] .. item] then pending[k][item] = nil
        elseif lists[k] then lists[k][item] = true end
    end
    for _, r in ipairs(redel) do
        if lists[r[1]] then lists[r[1]][r[2]] = nil end
    end
    for _, k in ipairs(LISTS) do snap[k] = Copy(lists[k]) end

    local ops = {}
    for _, a in ipairs(adds) do if Wanted("+", a[1]) then ops[#ops + 1] = "+" .. a[1] .. a[2] end end
    for _, d in ipairs(dels) do
        -- an item that moved to the opposite list goes as that "+" alone
        if not addedTo[OPPOSITE[d[1]] .. d[2]] and Wanted("-", d[1]) then ops[#ops + 1] = "-" .. d[1] .. d[2] end
    end
    if #ops == 0 then return end
    if #ops > BULK then
        MMT.Print("Quality of life: %d Dejunk list changes at once (an import, \"Remove all\" or a profile reset) were not sent to the team. /mmtqol dejunk send sends your whole lists.", #ops)
        return
    end
    SendOps("QDJ", ops)
    dj.sent = dj.sent + #ops
    M:Debug("Dejunk sent %s", table.concat(ops, ","))
end

local function Queue()
    if queued then return end
    queued = true
    if C_Timer and C_Timer.After then C_Timer.After(0.3, Check) else Check() end
end

if DejunkApi and DejunkApi.AddListener then
    DejunkApi:AddListener(function(event)
        if event ~= (DejunkApi.Events and DejunkApi.Events.StateUpdated or "StateUpdated") then return end
        ready = true
        Queue()
    end)
end

-- ops = { {sign, list, id} }; returns how many lists changed
local function Apply(ops)
    if not ready then return 0 end
    local lists = State()
    if not lists then return 0 end
    local n = 0
    local function set(k, item, on, sign)
        local t = lists[k]
        if not t or (t[item] and true or false) == on then return false end
        t[item] = on or nil
        pending[k][item] = sign
        if snap and snap[k] then snap[k][item] = on or nil end
        return true
    end
    for _, op in ipairs(ops) do
        local sign, k, item = op[1], op[2], op[3]
        if sign == "+" then
            if set(k, item, true, "+") then n = n + 1 end
            set(OPPOSITE[k], item, false, "-")   -- like Dejunk: on one list takes it off the other
        elseif set(k, item, false, "-") then
            n = n + 1
        end
    end
    dj.taken = dj.taken + n
    if n > 0 and not reloadNoted then
        reloadNoted = true
        MMT.Print("Quality of life: Dejunk uses list changes from the team after a /reload (it has no way to take them while running).")
    end
    return n
end

local function Describe(from, ops)
    local lines = {}
    for _, op in ipairs(ops) do
        lines[#lines + 1] = ("%s %s %s %s"):format(op[1], mod.ItemText(op[3]), op[1] == "+" and "to" or "from", NAMES[op[2]])
    end
    return lines
end

local function Take(from, ops, lines)
    if #ops == 0 then return end
    lines = lines or Describe(from, ops)
    local function apply()
        local n = Apply(ops)
        if n > 0 and M.db.djChat then
            if #lines == 1 then MMT.Print("Dejunk from %s: %s", MMT.FullDisplay(from), lines[1])
            else MMT.Print("Dejunk from %s: %d list changes.", MMT.FullDisplay(from), n) end
        end
    end
    if M.db.djAsk then mod.Ask(from, F, lines, apply) else apply() end
end

local function OnChange(from, _, body)
    local ops = {}
    for sign, k, item in body:gmatch("([%+%-])(%u%u)(%d+)") do
        if OPPOSITE[k] and Wanted(sign, k) then ops[#ops + 1] = { sign, k, item } end
    end
    Take(from, ops)
end

-- the whole lists: "GI=1,2;GE=;PI=3;PE=" (receivers merge: additions only)
local function OnAll(from, _, body)
    local lists = ready and State()
    if not lists then return end
    local ops, counts = {}, {}
    for k, ids in body:gmatch("(%u%u)=([%d,]*)") do
        if OPPOSITE[k] and (k:sub(1, 1) == "G" or M.db.djProfile) and lists[k] then
            for item in ids:gmatch("%d+") do
                if not lists[k][item] then
                    ops[#ops + 1] = { "+", k, item }
                    counts[k] = (counts[k] or 0) + 1
                end
            end
        end
    end
    local lines = {}
    for _, k in ipairs(LISTS) do
        if counts[k] then lines[#lines + 1] = ("+ %d item(s) to %s"):format(counts[k], NAMES[k]) end
    end
    if #ops == 0 then
        if M.db.djChat then MMT.Print("Dejunk lists from %s: nothing new.", MMT.FullDisplay(from)) end
        return
    end
    Take(from, ops, lines)
end

local function SendAll()
    if not mod.Active(F) then return false, "switched off, or Dejunk isn't loaded." end
    local lists = ready and State()
    if not lists then return false, "Dejunk isn't ready yet." end
    local parts = {}
    for _, k in ipairs(LISTS) do
        if k:sub(1, 1) == "G" or M.db.djProfile then
            local ids = {}
            for item in pairs(lists[k] or {}) do ids[#ids + 1] = item end
            table.sort(ids)
            parts[#parts + 1] = k .. "=" .. table.concat(ids, ",")
        end
    end
    MMT.SendLong("QDJL:" .. table.concat(parts, ";"))
    return true
end

F = mod.Feature({
    key = "dejunk", slash = "dejunk", addon = "Dejunk", title = "Dejunk lists",
    checkText = "Sync Dejunk's lists",
    tip = "Items you put on or take off Dejunk's junk / not junk lists here are put on or taken off the same lists on the team's characters. Baganator's junk follows Dejunk, so that syncs too. The team's changes count in Dejunk after a /reload on that character.",
    tags = { QDJ = OnChange, QDJL = OnAll },
    SendAll = SendAll,
    OnEnable = function() snap = nil; if ready then Queue() end end,
    OnDisable = function() snap = nil end,
    Page = function(ui)
        ui.Check("Send and take additions", "djAdd", "Items put on a list.")
        ui.Check("Send and take removals", "djRemove", "Items taken off a list.")
        ui.Check("Profile lists too", "djProfile", "Also Dejunk's profile lists (they go to the profile each character uses). Off: only the global lists.")
        ui.Check("Ask before taking changes", "djAsk", "A dialog shows what a team member changed, Apply or Ignore. Off: taken right away.")
        ui.Check("Chat line for each change taken", "djChat")
        ui.Button("Send my lists to the team", function()
            local ok, err = SendAll()
            ui.status.Show_(ok and "Your Dejunk lists were sent; the team adds what it doesn't have." or ("Not sent: " .. tostring(err)), not ok)
        end, "Sends your whole Dejunk lists once. The others add the items they don't have yet (nothing is removed).")
        ui.Note("Dejunk takes the team's changes after a /reload of that character.")
    end,
    Report = function(add)
        local lists, id = State()
        local sizes = {}
        for _, k in ipairs(LISTS) do
            local n, p = 0, 0
            for _ in pairs(lists and lists[k] or {}) do n = n + 1 end
            for _ in pairs(pending[k]) do p = p + 1 end
            sizes[#sizes + 1] = ("%s=%d(+%d pending)"):format(k, n, p)
        end
        add(("Dejunk: ready=%s profile=%s %s sent=%d taken=%d"):format(tostring(ready), tostring(id),
            table.concat(sizes, " "), dj.sent, dj.taken))
    end,
})

-- for the tests: Check, and what a /reload does (Dejunk reads the state, nothing pending)
mod.DejunkCheck = Check
function mod.DejunkReloaded() for _, k in ipairs(LISTS) do pending[k] = {} end end
