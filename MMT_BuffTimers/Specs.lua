-- Each member's talent spec, for spec lists. With "Use spec lists" on
-- (M.db.specLists), a member whose spec is known tracks the list
-- "SPEC:<CLASS>:<SPEC>" (e.g. "SPEC:PALADIN:HOLY") INSTEAD of their class list, so a
-- Holy and a Retribution paladin track different things. Spec unknown (below
-- talent level, older client) -> the class list. A spec list starts as that spec's
-- preset (Presets.lua, same keys).
--
-- The spec = the talent tree with the most points: each client reads its own and
-- tells the team on MMT's heartbeat ("cts=<tree>" from Cooldown Timers, "bts=<tree>"
-- from Buff Timers while Cooldown Timers is off), plus ONE message "MSPC:<tree>"
-- right when it changes (respec, dual spec swap) - never periodic. A druid in the
-- Feral tree counts as the bear tank spec while their player role is Tank (Buff
-- Timers' Roles.lua: bear form or set by hand).
--
-- MMT_CooldownTimers and MMT_BuffTimers ship the same copy of this file (KEEP BOTH
-- IDENTICAL). It needs mod.M, mod.ClassOf (ListKeys.lua) and mod.PresetByKey.

local _, mod = ...
local MMT = MMT
local M = mod.M

-- talent trees in tab order -> spec key (the keys of the spec presets)
mod.SPEC_TREES = {
    WARRIOR = { "ARMS", "FURY", "PROT" }, PALADIN = { "HOLY", "PROT", "RET" }, HUNTER = { "BM", "MM", "SURV" },
    ROGUE = { "ASSA", "COMBAT", "SUB" }, PRIEST = { "DISC", "HOLY", "SHADOW" }, SHAMAN = { "ELE", "ENH", "RESTO" },
    MAGE = { "ARCANE", "FIRE", "FROST" }, WARLOCK = { "AFF", "DEMO", "DESTRO" }, DRUID = { "BALANCE", "FERAL", "RESTO" },
}

-- every spec of a class, in order (the druid's bear tank next to feral cat)
function mod.SpecsOf(class)
    local t = {}
    for _, s in ipairs(mod.SPEC_TREES[class] or {}) do
        t[#t + 1] = s
        if class == "DRUID" and s == "FERAL" then t[#t + 1] = "BEAR" end
    end
    return t
end

---------------------------------------------------------------------------
-- This character's talents
---------------------------------------------------------------------------
local function Readable(v) return v ~= nil and not MMT.IsSecret(v) end

-- points per tree, or nil. Classic talent tabs where the client has them; on
-- Forever the talents are one trait tree, whose three classic trees are the
-- three bands of node columns (left to right = tab order).
function mod.TreePoints()
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

-- this character's talent tree with the most points (1-3), or nil (no points yet)
local cache, cacheTime
function mod.OwnTree()
    if cacheTime and GetTime() - cacheTime < 10 then return cache end
    cacheTime = GetTime()
    local points = mod.TreePoints()
    cache = nil
    if points then
        local most = 0
        for i = 1, 3 do
            if points[i] > most then cache, most = i, points[i] end
        end
    end
    return cache
end

---------------------------------------------------------------------------
-- Telling the team (one module does it: Cooldown Timers, else Buff Timers)
---------------------------------------------------------------------------
local HB = (M.name == "CooldownTimers") and "cts" or "bts"
local function Speaks()
    return HB == "cts" or not (MMT.ModuleActive and MMT.ModuleActive("CooldownTimers"))
end

M:Heartbeat(HB, function()
    if not Speaks() then return nil end
    local tree = mod.OwnTree()
    return tree and tostring(tree) or nil
end)

local sent
local function TalentsChanged()
    cacheTime = nil
    C_Timer.After(1, function()
        if not M.enabled then return end
        cacheTime = nil
        local tree = mod.OwnTree()
        if tree and tree ~= sent then
            sent = tree
            if Speaks() then MMT.SendToTeam("MSPC:" .. tree, true) end
            if mod.Refresh then mod.Refresh() end
        end
    end)
end
local frame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", TalentsChanged)
function mod.OwnSpecSent() sent = mod.OwnTree() end   -- at enable: the heartbeat says it

local told = {}   -- [key] = { tree, time }: newer than their last heartbeat for 40 s
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local tree = tonumber(text:match("^MSPC:(%d)$"))
    if tree and tree >= 1 and tree <= 3 and not MMT.IsSelf(key) then
        told[key] = { tree, GetTime() }
        if mod.Refresh then mod.Refresh() end
    end
end)

---------------------------------------------------------------------------
-- Any member's spec
---------------------------------------------------------------------------
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- talent tree (1-3) of a member, or nil
function mod.TreeOf(key)
    if mod.preview == "ALL" or mod.preview == "MIXED" then return Hash(key) % 3 + 1 end   -- made up
    if MMT.IsSelf(key) then return mod.OwnTree() end
    local t = told[key]
    if t and GetTime() - t[2] < 40 then return t[1] end
    local s = MMT.status and MMT.status[key]
    local ext = s and s.ext
    local tree = ext and tonumber(ext.cts or ext.bts)
    return (tree and tree >= 1 and tree <= 3) and tree or nil
end

-- "PALADIN:HOLY" for a member, or nil (spec unknown)
function mod.SpecOf(key)
    local class = mod.ClassOf(key)
    local trees = class and mod.SPEC_TREES[class]
    local tree = trees and mod.TreeOf(key)
    if not tree then return nil end
    local spec = trees[tree]
    if spec == "FERAL" and mod.PlayerRole and mod.PlayerRole(key) == "TANK" then spec = "BEAR" end
    return class .. ":" .. spec
end

-- the spec lists not made yet start as their spec's preset
function mod.EnsureSpecLists()
    local lists = M.db.lists
    for class in pairs(mod.SPEC_TREES) do
        for _, spec in ipairs(mod.SpecsOf(class)) do
            local lk = "SPEC:" .. class .. ":" .. spec
            if lists[lk] == nil then
                local p = mod.PresetByKey(class .. ":" .. spec)
                if p then mod.AddPreset(lk, p.entries, mod.EntryKey) end
            end
        end
    end
end
