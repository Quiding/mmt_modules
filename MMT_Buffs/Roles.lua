-- MMT Buffs: who a buff is for.
--
-- Every tracked buff can be limited ("Only for", the cog in the list editor) to
-- player roles, classes and / or MMT roles: e.only = { roles = { MELEE = true },
-- classes = { WARRIOR = true }, mmt = { Healer = true } }. Nothing ticked = for
-- everyone; otherwise a member counts when they match ANY ticked one. Members it
-- isn't for don't count as missing it.
--
-- A member's player role (Tank / Healer / Melee / Ranged / Caster), first that
-- answers:
--   1. set by hand on the settings page (M.db.playerRoles[key])
--   2. a druid's form right now, read from their buffs (Cat = Melee, Bear =
--      Tank, Moonkin = Caster, Tree of Life = Healer): changes with the form
--   3. their talents: each client reads its own character's talent tree with the
--      most points and tells the team on MMT's heartbeat ("bpr=<letter>", every
--      30 s), plus ONE message "BPR:<letter>" right when it changes (respec, dual
--      spec swap) - never periodic
--   4. their class (warrior / rogue Melee, hunter Ranged, mage / warlock Caster,
--      priest Healer, paladin Melee, shaman Caster, druid Healer)

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.PLAYER_ROLES = {
    { "TANK", "Tank" }, { "HEALER", "Healer" }, { "MELEE", "Melee" }, { "RANGED", "Ranged" }, { "CASTER", "Caster" },
}
local ROLE_NAME = {}
for _, r in ipairs(mod.PLAYER_ROLES) do ROLE_NAME[r[1]] = r[2] end
mod.ROLE_NAME = ROLE_NAME
local LETTER = { TANK = "T", HEALER = "H", MELEE = "M", RANGED = "R", CASTER = "C" }
local FROM_LETTER = {}
for role, l in pairs(LETTER) do FROM_LETTER[l] = role end

-- talent trees in their tab order -> role
local TREES = {
    WARRIOR = { "MELEE", "MELEE", "TANK" },        -- Arms, Fury, Protection
    PALADIN = { "HEALER", "TANK", "MELEE" },       -- Holy, Protection, Retribution
    HUNTER = { "RANGED", "RANGED", "RANGED" },
    ROGUE = { "MELEE", "MELEE", "MELEE" },
    PRIEST = { "HEALER", "HEALER", "CASTER" },     -- Discipline, Holy, Shadow
    SHAMAN = { "CASTER", "MELEE", "HEALER" },      -- Elemental, Enhancement, Restoration
    MAGE = { "CASTER", "CASTER", "CASTER" },
    WARLOCK = { "CASTER", "CASTER", "CASTER" },
    DRUID = { "CASTER", "MELEE", "HEALER" },       -- Balance, Feral, Restoration
}
local CLASS_ROLE = { WARRIOR = "MELEE", ROGUE = "MELEE", HUNTER = "RANGED", MAGE = "CASTER", WARLOCK = "CASTER",
    PRIEST = "HEALER", PALADIN = "MELEE", SHAMAN = "CASTER", DRUID = "HEALER" }

-- druid forms (spell IDs; matched by the buff's name, any rank)
local FORMS = { { 768, "MELEE" }, { 5487, "TANK" }, { 9634, "TANK" }, { 24858, "CASTER" }, { 33891, "HEALER" } }

---------------------------------------------------------------------------
-- This character's talents
---------------------------------------------------------------------------
local function Readable(v) return v ~= nil and not MMT.IsSecret(v) end

-- points per tree, or nil. Classic talent tabs where the client has them; on
-- Forever the talents are one trait tree, whose three classic trees are the
-- three bands of node columns (left to right = tab order).
local function TreePoints()
    local n = GetNumTalentTabs and MMT.Safe(GetNumTalentTabs)
    if type(n) == "number" and n >= 3 then
        local t = {}
        for tab = 1, 3 do
            local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
            local spent = ok and (type(a) == "string" and c or e)
            if not Readable(spent) or type(spent) ~= "number" then t = nil break end
            t[tab] = spent
        end
        if t then return t end
    end
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
        and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
    local config = MMT.Safe(C_ClassTalents.GetActiveConfigID)
    if type(config) ~= "number" then return nil end
    local info = MMT.Safe(C_Traits.GetConfigInfo, config)
    local tree = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if type(tree) ~= "number" then return nil end
    local nodes = MMT.Safe(C_Traits.GetTreeNodes, tree)
    if type(nodes) ~= "table" then return nil end
    local cols, xs = {}, {}
    for _, id in ipairs(nodes) do
        local node = MMT.Safe(C_Traits.GetNodeInfo, config, id)
        local x = type(node) == "table" and node.posX
        if type(x) == "number" then
            if not cols[x] then cols[x] = 0; xs[#xs + 1] = x end
            cols[x] = cols[x] + (tonumber(node.ranksPurchased) or 0)
        end
    end
    if #xs < 3 then return nil end
    table.sort(xs)
    local step
    for i = 2, #xs do
        local gap = xs[i] - xs[i - 1]
        if gap > 0 and (not step or gap < step) then step = gap end
    end
    if not step then return nil end
    local t = { cols[xs[1]] }
    for i = 2, #xs do
        if xs[i] - xs[i - 1] > step * 2 then t[#t + 1] = 0 end
        t[#t] = t[#t] + cols[xs[i]]
    end
    return #t == 3 and t or nil
end

-- this character's role from its talents (the tree with the most points), or nil
local cache, cacheTime
function mod.OwnTalentRole()
    if cacheTime and GetTime() - cacheTime < 10 then return cache end
    cacheTime = GetTime()
    local _, class = UnitClass("player")
    local trees, points = TREES[class], TreePoints()
    cache = nil
    if trees and points then
        local best, most = nil, 0
        for i = 1, 3 do
            if points[i] > most then best, most = i, points[i] end
        end
        cache = best and trees[best] or nil
    end
    return cache
end

-- the role this character shows the team: its talents (forms are read live)
M:Heartbeat("bpr", function()
    local role = mod.OwnTalentRole()
    return role and LETTER[role] or nil
end)

-- talents changed (respec, dual spec swap): tell the team once, at once. Events
-- registered with pcall on an own frame: not every one exists on this client.
local sent
local function TalentsChanged()
    cacheTime = nil
    C_Timer.After(1, function()
        if not M.enabled then return end
        cacheTime = nil
        local role = mod.OwnTalentRole()
        local letter = role and LETTER[role]
        if letter and letter ~= sent then
            sent = letter
            MMT.SendToTeam("BPR:" .. letter, true)
            mod.Refresh()
        end
    end)
end
local talentFrame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    pcall(talentFrame.RegisterEvent, talentFrame, ev)
end
talentFrame:SetScript("OnEvent", TalentsChanged)
function mod.OwnRoleSent() sent = LETTER[mod.OwnTalentRole() or ""] end   -- at enable: the heartbeat says it

-- what the team told us right away (newer than their last heartbeat)
local told = {}   -- [key] = { letter, time }
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local l = text:match("^BPR:(%a)$")
    if l and FROM_LETTER[l] and not MMT.IsSelf(key) then
        told[key] = { l, GetTime() }
        mod.Refresh()
    end
end)

---------------------------------------------------------------------------
-- Any member's role
---------------------------------------------------------------------------
local formNames
local function FormNames()
    if formNames and formNames.complete then return formNames end
    formNames = { complete = true }
    for _, f in ipairs(FORMS) do
        local name = mod.SpellInfo(f[1])
        if name then formNames[name] = f[2] else formNames.complete = false end
    end
    return formNames
end

-- a druid's role from the form they're in right now (their buffs, read from the unit)
function mod.FormRole(key)
    if mod.ClassOf(key) ~= "DRUID" then return nil end
    local auras = mod.auras and mod.auras[key]
    if not auras then return nil end
    for name, role in pairs(FormNames()) do
        if name ~= "complete" and auras[name] then return role end
    end
    return nil
end

-- role, source ("set" | "form" | "talents" | "class")
function mod.PlayerRole(key)
    local set = M.db.playerRoles and M.db.playerRoles[key]
    if set and ROLE_NAME[set] then return set, "set" end
    local form = mod.FormRole(key)
    if form then return form, "form" end
    if MMT.IsSelf(key) then
        local own = mod.OwnTalentRole()
        if own then return own, "talents" end
    else
        local s = MMT.status and MMT.status[key]
        local hb = s and s.ext and s.ext.bpr
        -- a BPR message is newer than a heartbeat until the next heartbeat carries it (30 s)
        local t = told[key]
        if t and GetTime() - t[2] < 40 then hb = t[1] end
        if FROM_LETTER[hb or ""] then return FROM_LETTER[hb], "talents" end
    end
    local class = mod.ClassOf(key)
    return CLASS_ROLE[class or ""], "class"
end

---------------------------------------------------------------------------
-- Who a buff is for
---------------------------------------------------------------------------
local function Any(t) return type(t) == "table" and next(t) ~= nil end

function mod.HasFilter(e)
    local o = e.only
    return type(o) == "table" and (Any(o.roles) or Any(o.classes) or Any(o.mmt))
end

-- does buff entry e count for member key?
function mod.Applies(e, key)
    if not mod.HasFilter(e) then return true end
    local o = e.only
    local class = mod.ClassOf(key)
    if class and o.classes and o.classes[class] then return true end
    if o.mmt then
        for _, r in ipairs(MMT.MemberRoleList(key)) do if o.mmt[r] then return true end end
    end
    if o.roles then
        local role = mod.PlayerRole(key)
        if role and o.roles[role] then return true end
    end
    return false
end

-- "Melee, Tank, Warrior, Healer (MMT)" or nil
function mod.FilterText(e)
    if not mod.HasFilter(e) then return nil end
    local t = {}
    for _, r in ipairs(mod.PLAYER_ROLES) do if e.only.roles and e.only.roles[r[1]] then t[#t + 1] = r[2] end end
    for _, c in ipairs(mod.CLASSES) do
        if c ~= "ALL" and e.only.classes and e.only.classes[c] then t[#t + 1] = mod.ListLabel(c) end
    end
    local mmt = {}
    for r in pairs(e.only.mmt or {}) do mmt[#mmt + 1] = r end
    table.sort(mmt)
    for _, r in ipairs(mmt) do t[#t + 1] = r .. " (MMT role)" end
    return table.concat(t, ", ")
end

-- an entry's filter from imported / synced data, cleaned (or nil)
function mod.CleanFilter(o)
    if type(o) ~= "table" then return nil end
    local out = {}
    local function Copy(src, valid)
        if type(src) ~= "table" then return nil end
        local t
        for k, v in pairs(src) do
            if v == true and type(k) == "string" and valid(k) then t = t or {}; t[k] = true end
        end
        return t
    end
    out.roles = Copy(o.roles, function(k) return ROLE_NAME[k] ~= nil end)
    out.classes = Copy(o.classes, function(k) return TREES[k] ~= nil end)
    out.mmt = Copy(o.mmt, function(k) return k ~= "" end)
    if not (out.roles or out.classes or out.mmt) then return nil end
    return out
end
