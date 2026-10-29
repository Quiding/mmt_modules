-- MMT Totems: which totems a shaman has learned, and which totem items
-- (Earth / Fire / Water / Air Totem) they carry - in Classic you can't drop
-- a totem without its item.
-- Your own: the game's spell checks and your bags. Other shamans: their
-- client sends both once at login and when something changes (stored
-- account-wide in M.store.known / M.store.items, so it stays while they
-- are offline):
--   MTTK:<spellID>,<spellID>,...;<elements with their item, e.g. EFWA>
-- (older clients send no ";..." part: their items count as unknown).
-- A shaman whose list hasn't arrived yet shows every totem.

local _, mod = ...
local MMT = MMT
local M = mod.M

local LETTER = { Earth = "E", Fire = "F", Water = "W", Air = "A" }

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

local function OwnHasItem(element)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return true end
    local ok, n = pcall(fn, mod.TOTEM_ITEM[element])
    -- can't tell (error, hidden value): don't hide anything
    if not ok or type(n) ~= "number" or MMT.IsSecret(n) then return true end
    return n > 0
end

local function OwnItems()
    local s = ""
    for _, el in ipairs(mod.ELEMENTS) do if OwnHasItem(el) then s = s .. LETTER[el] end end
    return s
end

-- does this member know this totem? (true when we can't tell)
function mod.KnowsTotem(key, id)
    if MMT.IsSelf(key) then return KnownApi(id) end
    local known = M.store.known and M.store.known[key]
    if not known then return true end
    return known[id] == true
end

-- does this member carry the totem item of an element? (true when we can't tell)
function mod.HasTotemItem(key, element)
    if MMT.IsSelf(key) then return OwnHasItem(element) end
    local items = M.store.items and M.store.items[key]
    if not items then return true end
    return items[element] == true
end

-- has a member's list of learned totems arrived?
function mod.HasKnownList(key)
    if MMT.IsSelf(key) then return true end
    return M.store.known and M.store.known[key] ~= nil
end

-- does the slot of this element belong on this member's bar?
function mod.SlotShown(key, element)
    local c = M.db
    if c.hiddenElements[element] then return false end
    if c.hideNoItem and not mod.HasTotemItem(key, element) then return false end
    if c.hideUnlearned and mod.HasKnownList(key) then
        local any = false
        local own = MMT.IsSelf(key)
        for _, id in ipairs(mod.TOTEMS[element]) do
            -- another shaman: their client's list (it only has totems that exist there), so this
            -- client needs no spell data for it (a warrior often has none: the bar disappeared)
            if (not own or mod.SpellInfo(id)) and mod.KnowsTotem(key, id) then any = true break end
        end
        if not any then return false end
    end
    return true
end

local lastSent
local function Message()
    return "MTTK:" .. table.concat(OwnKnown(), ",") .. ";" .. OwnItems()
end

local function Send(target)
    if select(2, UnitClass("player")) ~= "SHAMAN" then return end
    local msg = Message()
    if not target and msg == lastSent then return end
    lastSent = msg
    if target then MMT.SendAddon(msg, "WHISPER", target) else MMT.SendToTeam(msg, true) end
end

-- own spells or bags changed: tell the team if it matters, redo the bars
local lastLayout
local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(2, function()
        queued = false
        if not M.enabled then return end
        Send()
        local now = Message()
        if now ~= lastLayout then lastLayout = now; mod.Refresh() end
        mod.UpdateSecure()
    end)
end

M:On("SPELLS_CHANGED", Queue)   -- also fires when a spell is learned (LEARNED_SPELL_IN_TAB doesn't exist here)
M:On("BAG_UPDATE_DELAYED", Queue)
M:On("PLAYER_ENTERING_WORLD", function() lastSent = nil; Queue() end)

local answered = {}
M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local list, items = text:match("^MTTK:([%d,]*);?(%a*)$")
    if not list or MMT.IsSelf(key) then return end
    local known = {}
    for id in list:gmatch("%d+") do known[tonumber(id)] = true end
    M.store.known = M.store.known or {}
    M.store.known[key] = known
    M.store.items = M.store.items or {}
    if text:find(";", 1, true) then
        local has = {}
        for el, letter in pairs(LETTER) do has[el] = items:find(letter, 1, true) ~= nil end
        M.store.items[key] = has
    else
        M.store.items[key] = nil   -- older client: unknown
    end
    -- they just logged in (or something changed): make sure they have ours
    if not answered[key] then answered[key] = true; Send(sender) end
    mod.Refresh()
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end)
