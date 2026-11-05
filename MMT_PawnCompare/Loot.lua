-- MMT Pawn Compare: master loot to the character an item is the biggest upgrade for.
--
-- Plugs into Loot Distribution (core module, 1.4.0 or newer) through
-- MMT.RegisterLootChooser: as master looter, every gear item Loot Distribution
-- would hand out is offered here first, with the team members that can take
-- it right now (loot candidate, room in the bags, no failed hand-out).
--
-- Each character counts with ONE Pawn scale: M.db.lootScale[key] = scale name
-- (chosen on the Loot tab, shared with the Sync button), else their first
-- visible scale. The item goes to the member with the biggest upgrade in
-- percent over what they wear in that slot (same comparison as the item
-- tooltip: weaker ring / trinket, 2H against main + off hand). An empty slot
-- beats any percentage (the bigger value first among empty slots).
-- Left out: classes that can never use the item, members below its required
-- level, an item the scale marks unusable, members without stored scales or
-- equipment, items not loaded yet. Below the minimum gain (M.db.lootMinGain %)
-- it is an upgrade for nobody: the item goes by Loot Distribution's roles and
-- round robin as before. Equal percentages: team order.

local _, mod = ...
local MMT = MMT
local M = mod.M

local SAME = 0.05   -- percentage points that count as equal

-- the scale a member's loot is judged by (nil: no scales stored)
function mod.LootScale(key)
    local rec = mod.ScalesOf(key)
    if not rec or #rec.scales == 0 then return nil end
    local want = M.db.lootScale and M.db.lootScale[key]
    for _, sc in ipairs(rec.scales) do
        if sc.name == want then return sc end
    end
    return rec.scales[1]
end

local function Level(key)
    if MMT.IsSelf(key) then return UnitLevel("player") end
    local s = MMT.status and MMT.status[key]
    return s and s.level
end

local function MinLevel(link)
    local info = MMT.ItemInfo or GetItemInfo
    local lvl = select(5, info(link))
    return tonumber(lvl)
end

-- what the item is worth to one member: { key, scale, gain, old, pct } or nil, why
function mod.LootUpgrade(key, link, loc, stats, minLevel)
    if not mod.CanUse(key, link) then return nil, "class can't use it" end
    local lvl = Level(key)
    if minLevel and lvl and lvl < minLevel then return nil, ("needs level %d"):format(minLevel) end
    local scale = mod.LootScale(key)
    if not scale then return nil, "no Pawn scale" end
    if not mod.HasEquipment(key) then return nil, "equipment unknown" end
    local gain, old = mod.Gain(key, loc, stats, scale)
    if gain == "unusable" then return nil, "scale can't use it" end
    if gain == "loading" then return nil, "equipped item not loaded" end
    local pct = old > 0 and gain / old * 100 or nil
    return { key = key, scale = scale, gain = gain, old = old, pct = pct }
end

-- an upgrade that counts: above the minimum percentage, or an empty slot the item fills
local function Counts(u)
    if u.pct then return u.gain > 0 and u.pct >= math.max(M.db.lootMinGain or 0, SAME) end
    return u.gain > 0   -- empty slot (or nothing of value there)
end

-- a ranks before b?
local function Before(a, b)
    if (a.pct == nil) ~= (b.pct == nil) then return a.pct == nil end
    if a.pct == nil then
        if math.abs(a.gain - b.gain) > 0.05 then return a.gain > b.gain end
    elseif math.abs(a.pct - b.pct) > SAME then
        return a.pct > b.pct
    end
    return a.order < b.order   -- equal: team order
end

-- every member of keys with what the item does for them, best first:
-- list of { key, scale, gain, old, pct, counts } and { [key] = why } for those left out.
-- nil, why when the item can't be judged at all.
function mod.LootRanking(link, keys)
    local loc = mod.EquipLoc(link)
    if not (loc and mod.SLOTS[loc]) then return nil, "not equippable" end
    local stats = mod.ItemStats(link)
    if not stats then return nil, "item not loaded" end
    local minLevel = MinLevel(link)
    local list, skipped = {}, {}
    for i, key in ipairs(keys) do
        local u, why = mod.LootUpgrade(key, link, loc, stats, minLevel)
        if u then
            u.order, u.counts = i, Counts(u)
            list[#list + 1] = u
        else
            skipped[key] = why
        end
    end
    table.sort(list, function(a, b)
        if a.counts ~= b.counts then return a.counts end
        return Before(a, b)
    end)
    return list, skipped
end

function mod.UpgradeText(u)
    if not u.pct then return ("empty slot, %s %.1f"):format(u.scale.name, u.gain) end
    return ("%+.0f%% %s"):format(u.pct, u.scale.name)
end

-- the member to give the item to, and the reason for the chat line; nil = nobody gains enough
function mod.BestLootRecipient(link, candidates)
    local list, why = mod.LootRanking(link, candidates)
    if not list then return nil, why end
    local best = list[1]
    if not (best and best.counts) then return nil, "an upgrade for nobody" end
    return best.key, "Pawn: " .. mod.UpgradeText(best)
end

function mod.LootActive()
    return M.enabled and M.db.lootByUpgrade and mod.PawnReady() or false
end

---------------------------------------------------------------------------
-- Loot Distribution's hook
---------------------------------------------------------------------------
local registered = false
function mod.RegisterLoot()
    if registered then return true end
    if type(MMT.RegisterLootChooser) ~= "function" then return false end
    MMT.RegisterLootChooser({
        name = "PawnCompare",
        title = "Pawn Compare (biggest upgrade)",
        active = mod.LootActive,
        choose = function(link, candidates, info)
            if info and info.isQuest then return nil end
            local key, reason = mod.BestLootRecipient(link, candidates)
            M:Debug("loot %s -> %s (%s)", tostring(link), key and MMT.Repr(key) or "rules", tostring(reason))
            return key, reason
        end,
    })
    registered = true
    return true
end

function mod.LootHookAvailable()
    return type(MMT.RegisterLootChooser) == "function"
end

mod.RegisterLoot()

-- "/mmtpc loot <item>": who would get it, and why the others wouldn't
function mod.PrintLootRanking(link)
    local list, skipped = mod.LootRanking(link, MMT.SortedMembers())
    if not list then MMT.Print("Pawn Compare: %s: %s.", link, tostring(skipped)) return end
    MMT.Print("Pawn Compare: %s by upgrade%s:", link, mod.LootActive() and "" or " (loot by upgrade is off)")
    for i, u in ipairs(list) do
        MMT.Print("  %d. %s %s%s", i, MMT.FirstName(u.key), mod.UpgradeText(u), u.counts and "" or " |cff888888(not enough)|r")
    end
    for key, why in pairs(skipped) do MMT.Print("  - %s: %s", MMT.FirstName(key), why) end
end
