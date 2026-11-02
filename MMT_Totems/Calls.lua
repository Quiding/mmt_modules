-- MMT Totems: the three Calls (WoW: Forever shamans: Call of the Elements at 20,
-- of the Ancestors at 30, of the Spirits at 40). Each drops one totem per element;
-- which ones is set on Blizzard's totem bar (MultiCastActionBarFrame).
--
-- Every client keeps every shaman's three Calls (M.db.calls[key][call][element] =
-- spell ID), so you can set them for any shaman; that shaman's client puts them on
-- its Blizzard totem bar with SetMultiCastSpell (tested in game: allowed from an
-- addon, not in combat - it waits for the end of combat). Action slots: 132 +
-- element slot (Fire 1, Earth 2, Water 3, Air 4) + 4 per Call.
--   MTTC:<call>:<element>:<spellID or 0>:<teamKey>   one totem of one Call (on a change)
-- Everything at once goes with the core's "Sync to team".
-- The first time, a shaman's own client takes over what is already on its bar.

local _, mod = ...
local MMT = MMT
local M = mod.M

mod.CALLS = {
    { name = "Call of the Elements", short = "Elements" },
    { name = "Call of the Ancestors", short = "Ancestors" },
    { name = "Call of the Spirits", short = "Spirits" },
}

local function Action(call, element) return 132 + mod.TOTEM_SLOT[element] + 4 * (call - 1) end
mod.CallAction = Action

function mod.CallTotem(key, call, element)
    local c = M.db.calls and M.db.calls[key]
    local id = c and c[call] and c[call][element]
    return (id and id ~= 0) and id or nil
end

-- this character knows that Call (the game finds a spell by name only when it's known)
function mod.KnowsCall(call)
    local c = mod.CALLS[call]
    return c and mod.SpellInfo(c.name) ~= nil or false
end

-- the highest rank of a totem this character knows (the bar casts the ID it gets)
local function BestRank(id)
    local name = mod.TotemName(id)
    local _, _, best = mod.SpellInfo(name or id)
    return best or id
end

---------------------------------------------------------------------------
-- Onto Blizzard's totem bar (own client, out of combat)
---------------------------------------------------------------------------
local pending = false
function mod.PushCalls()
    local own = mod.OwnKey()
    if not (own and mod.IsShaman(own)) or not SetMultiCastSpell then return 0 end
    if InCombatLockdown() then pending = true return 0 end
    pending = false
    local n = 0
    for call = 1, #mod.CALLS do
        if mod.KnowsCall(call) then
            for _, el in ipairs(mod.ELEMENTS) do
                local id = mod.CallTotem(own, call, el)
                if id and mod.KnowsTotem(own, id) then
                    id = BestRank(id)
                    local action = Action(call, el)
                    local _, current = MMT.Safe(GetActionInfo, action)
                    if current ~= id and pcall(SetMultiCastSpell, action, id) then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- what's on this character's bar now -> its Calls (the first time only)
function mod.ReadCalls()
    local own = mod.OwnKey()
    if not (own and mod.IsShaman(own)) or (M.db.calls[own] and next(M.db.calls[own])) then return false end
    local t, any = {}, false
    for call = 1, #mod.CALLS do
        for _, el in ipairs(mod.ELEMENTS) do
            local kind, id = MMT.Safe(GetActionInfo, Action(call, el))
            if kind == "spell" and type(id) == "number" and not MMT.IsSecret(id) then
                t[call] = t[call] or {}
                t[call][el] = id
                any = true
            end
        end
    end
    if not any then return false end
    M.db.calls[own] = t
    for call, els in pairs(t) do
        for el, id in pairs(els) do MMT.SendToTeam(("MTTC:%d:%s:%d:%s"):format(call, el, id, own), true) end
    end
    return true
end

-- quiet = don't tell the team (they got it some other way)
function mod.SetCallTotem(key, call, element, id, quiet)
    if not (mod.CALLS[call] and mod.TOTEMS[element]) then return end
    id = tonumber(id) or 0
    M.db.calls[key] = M.db.calls[key] or {}
    M.db.calls[key][call] = M.db.calls[key][call] or {}
    M.db.calls[key][call][element] = id ~= 0 and id or nil
    if not quiet then MMT.SendToTeam(("MTTC:%d:%s:%d:%s"):format(call, element, id, key), true) end
    if MMT.IsSelf(key) then mod.PushCalls() end
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

-- the same totems in all three Calls (e.g. to start from the chosen ones)
function mod.CopyCall(key, from, to)
    for _, el in ipairs(mod.ELEMENTS) do mod.SetCallTotem(key, to, el, mod.CallTotem(key, from, el) or 0) end
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    local call, el, id, target = text:match("^MTTC:(%d):(%a+):(%d+):(.+)$")
    if call then mod.SetCallTotem(target, tonumber(call), el, id, true) end
end)

M:On("PLAYER_REGEN_ENABLED", function() if pending then mod.PushCalls() end end)
-- a Call or a totem rank learned: put them on the bar
M:On("SPELLS_CHANGED", function()
    if M.enabled then C_Timer.After(1, function() if M.enabled then mod.PushCalls() end end) end
end)

-- after login (the bar and the spells are there by then): take over / push
function mod.StartCalls()
    C_Timer.After(3, function()
        if not M.enabled then return end
        mod.ReadCalls()
        mod.PushCalls()
    end)
end

---------------------------------------------------------------------------
-- Choosing a totem for a Call (settings, Calls tab)
---------------------------------------------------------------------------
local function IconText(icon, text)
    return ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(tostring(icon or mod.PRESET_ICON), text)
end

function mod.OpenCallMenu(owner, key, call, element)
    local items = { { value = 0, text = "None" } }
    local current = mod.CallTotem(key, call, element)
    for _, id in ipairs(mod.ElementTotems(element, key, current)) do
        local text = mod.TotemName(id) or ("Spell " .. id)
        if not mod.KnowsTotem(key, id) then text = text .. " |cff888888(not learned)|r" end
        items[#items + 1] = { value = id, text = IconText(mod.TotemIcon(id), text) }
    end
    MMT.UI.OpenList(owner, items, current or 0, function(id) mod.SetCallTotem(key, call, element, id) end)
end
