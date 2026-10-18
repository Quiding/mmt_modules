-- MMT Totems: which totems a shaman has learned.
-- Your own: the game's spell checks. Other shamans: their client sends its
-- list once at login and when it learns a totem (stored account-wide in
-- M.store.known, so it stays while they are offline):
--   MTTK:<spellID>,<spellID>,...
-- A shaman whose list hasn't arrived yet shows every totem.

local _, mod = ...
local MMT = MMT
local M = mod.M

local function KnownApi(id)
    local any = false
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }) do
        if fn then
            any = true
            local ok, known = pcall(fn, id)
            if ok and known == true then return true end
        end
    end
    return not any   -- no way to tell on this client: don't hide anything
end

local function OwnKnown()
    local t = {}
    for _, list in pairs(mod.TOTEMS) do
        for _, id in ipairs(list) do
            if mod.SpellInfo(id) and KnownApi(id) then t[#t + 1] = id end
        end
    end
    table.sort(t)
    return t
end

-- does this member know this totem? (true when we can't tell)
function mod.KnowsTotem(key, id)
    if MMT.IsSelf(key) then return KnownApi(id) end
    local known = M.store.known and M.store.known[key]
    if not known then return true end
    return known[id] == true
end

-- has a member's list of learned totems arrived?
function mod.HasKnownList(key)
    if MMT.IsSelf(key) then return true end
    return M.store.known and M.store.known[key] ~= nil
end

local lastSent
local function Send(target)
    if select(2, UnitClass("player")) ~= "SHAMAN" then return end
    local list = table.concat(OwnKnown(), ",")
    if not target and list == lastSent then return end
    lastSent = list
    local msg = "MTTK:" .. list
    if target then MMT.SendAddon(msg, "WHISPER", target) else MMT.SendToTeam(msg, true) end
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(2, function()
        queued = false
        if M.enabled then Send() end
        mod.UpdateSecure()
    end)
end

M:On("SPELLS_CHANGED", Queue)
M:On("LEARNED_SPELL_IN_TAB", Queue)
M:On("PLAYER_ENTERING_WORLD", function() lastSent = nil; Queue() end)

local answered = {}
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local list = text:match("^MTTK:([%d,]*)$")
    if not list or MMT.IsSelf(key) then return end
    local known = {}
    for id in list:gmatch("%d+") do known[tonumber(id)] = true end
    M.store.known = M.store.known or {}
    M.store.known[key] = known
    -- they just logged in (or learned something): make sure they have ours
    if not answered[key] then answered[key] = true; Send(sender) end
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end)
