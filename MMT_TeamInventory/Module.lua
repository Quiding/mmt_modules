-- MMT module: Team Inventory.
-- Hover an item: the tooltip shows how many your team has, on every account
-- and character (bags, bank, mail, equipped), also while they are offline.
-- Each client counts its own items and shares them with the team; everything
-- is kept account-wide, so every client knows the whole team.
--
--   Scan.lua      counts this character's items (bank and mail only while open)
--   Sync.lua      shares them: hash on the heartbeat, a full copy when it
--                 differs, then only the changes (tag TIV)
--   Tooltip.lua   the lines in the item tooltip, next to Syndicator's
--   Give.lua      planned gifts: drag an item onto another character in the
--                 team bags, it goes into the trade window when they trade (TIVG)
--   Bags.lua      "Team bags": any character's stored items in a bag window,
--                 and the minimap button (left: bags, right: bank)
--   Settings.lua  settings page and debug report
--
-- Stored in M.store.chars[teamKey] = { b = {[itemID] = n}, k = bank, m = mail,
-- e = equipped, s = soulbound ones in the bags, hash, time, gold, rs = ruleset }, and M.store.mine[key] = true
-- for characters of this account (Syndicator already lists those in its own tooltip lines).

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.9.5"
mod.PLACES = { "b", "k", "m", "e" }
-- what is synced: the places + "s" = how many of each item in the bags are soulbound
-- (not a place: never counted in totals; older clients ignore the letter)
mod.SYNC_PLACES = { "b", "k", "m", "e", "s" }
mod.PLACE_NAMES = { b = "bags", k = "bank", m = "mail", e = "equipped" }

local M = MMT.NewModule({
    name = "TeamInventory",
    title = "Team Inventory",
    description = "The item tooltip shows how many your team has, across all your accounts and characters.",
    sync = true,
    syncExclude = { "minimapAngle", "bagsPoint", "bagsScale", "lastWho", "bagFilter", "bagFilters" },   -- belong to each screen
    defaults = {
        tooltip = true,        -- lines in the item tooltip
        equipped = true,       -- count equipped items too
        withSyndicator = "OTHERS",  -- Syndicator shown: OTHERS (other accounts only) | ALL | OFF (leave the tooltip to it)
        limit = 10,            -- characters listed at most
        onlyShift = false,     -- only while Shift is held
        minimap = true,        -- minimap button: left-click team bags, right-click team bank
        minimapAngle = 200,
        bagsScale = 1,
        categories = true,     -- team bags grouped by category (false = one grid)
        baganatorCats = true,  -- with Baganator on: its categories (order, custom ones, priorities)
        giveTrade = true,      -- planned gifts (drag in the team bags) go into the trade window by themselves
        sidePanel = true,      -- the team / trades panel beside the team bags
        otherChars = false,    -- team bags + gold: false = the team | "RULESET" = every stored character of this ruleset | "ALL" = every one
        -- team bags look (settings > Look); defaults = MMT's settings window
        bagIconSize = 36, bagColumns = 10, bagSpacing = 4, bagQuality = true,
        bagBgTexture = "FLAT", bagBgColor = { r = 0.05, g = 0.05, b = 0.06 }, bagBgAlpha = 0.94,
        bagBorderColor = { r = 0.22, g = 0.22, b = 0.24 }, bagCountSize = 14,
        goldSilver = true, goldCopper = true,   -- gold amounts show silver / copper (display only)   -- bagFont = MMT font name (nil = game font)
        -- bagFilters = { boe / bound / reagent / quest / consumable = "HIDE" | "ONLY" (Include) } (team bags; mod.Filters())
        openOn = "LAST",       -- team bags open on: LAST viewed | SELF | ALL (whole team) | BYCHAR (by character)
    },
})
mod.M = M

function mod.Chars()
    M.store.chars = M.store.chars or {}
    return M.store.chars
end

function mod.Mine()
    M.store.mine = M.store.mine or {}
    return M.store.mine
end

-- Syndicator (Baganator's data addon) is there and shows its own tooltip lines
function mod.HasSyndicator()
    return Syndicator and Syndicator.API and Syndicator.API.GetInventoryInfoByItemID and true or false
end

-- a team member (or this character); others are only shown with "Characters outside the team"
function mod.InTeam(key)
    if MMT.IsSelf(key) then return true end
    for _, k in ipairs(MMT.SortedMembers()) do if k == key then return true end end
    return false
end

-- Rulesets: Forever has no realms, characters are unique per ruleset (PvE, PvP, ...),
-- and team keys ("First-Last") carry no realm. Read like Syndicator / EllesmereUI do;
-- other clients: the realm. Stored per character as rec.rs (own: here; others: the
-- heartbeat tir, or ours when one of their messages reaches us - so the same ruleset).
mod.RULESET_NAMES = { PvE = "PvE", PvP = "PvP", RP = "RP", RPPvP = "RP-PvP", HC = "Hardcore" }
local ownRuleset
function mod.Ruleset()
    if ownRuleset then return ownRuleset end
    local R = Enum and Enum.GameRule
    local rules = C_GameRules and C_GameRules.IsGameRuleActive
    local rs
    if R and rules and (R.PvPRuleset or R.RPRuleset or R.HardcoreRuleset) then
        local function On(rule) return rule ~= nil and MMT.Safe(rules, rule) == true end
        local pvp, rp = On(R.PvPRuleset), On(R.RPRuleset)
        rs = On(R.HardcoreRuleset) and "HC" or (pvp and rp and "RPPvP") or (pvp and "PvP") or (rp and "RP") or "PvE"
    else
        rs = GetNormalizedRealmName and MMT.Safe(GetNormalizedRealmName)
        if not rs or rs == "" or MMT.IsSecret(rs) then rs = ((MMT.Safe(GetRealmName) or ""):gsub("%s", "")) end
        if rs == "" then return nil end
    end
    ownRuleset = rs
    return rs
end
function mod.RulesetName(rs) return rs and (mod.RULESET_NAMES[rs] or rs) or "?" end

-- older records have no rs: Syndicator's own saved data (this account's characters,
-- "First Last-PvE") tells it when exactly one ruleset matches
local function FromSyndicator(key)
    local data = type(SYNDICATOR_DATA) == "table" and type(SYNDICATOR_DATA.Characters) == "table" and SYNDICATOR_DATA.Characters
    if not data then return nil end
    local name = key:gsub("%-", " ") .. "-"
    local found
    for rs in pairs(mod.RULESET_NAMES) do
        if data[name .. rs] ~= nil then
            if found then return nil end
            found = rs
        end
    end
    return found
end

-- a character's ruleset, or nil when not known
function mod.RulesetOf(key)
    if MMT.IsSelf(key) then return mod.Ruleset() end
    local rec = mod.Chars()[key]
    if not rec then return nil end
    if not rec.rs then rec.rs = FromSyndicator(key) end
    return rec.rs
end
-- could be on the same ruleset (unknown counts as yes)
function mod.SameRuleset(a, b)
    local ra = a and mod.RulesetOf(a) or mod.Ruleset()
    local rb = b and mod.RulesetOf(b) or mod.Ruleset()
    return not ra or not rb or ra == rb
end

-- "Characters" setting: "TEAM" | "RULESET" | "ALL" (true from before 0.9.0 = RULESET)
function mod.CharsMode()
    local v = M.db.otherChars
    if v == "ALL" then return "ALL" end
    if v then return "RULESET" end
    return "TEAM"
end
function mod.Shown(key)
    if mod.InTeam(key) then return true end
    local mode = mod.CharsMode()
    if mode == "ALL" then return true end
    return mode == "RULESET" and mod.SameRuleset(key)
end


-- known gold of a character in copper, or nil; the total of every shown character
function mod.Gold(key)
    local rec = mod.Chars()[key]
    return rec and tonumber(rec.gold)
end
function mod.TotalGold()
    local sum, any = 0, false
    for key, rec in pairs(mod.Chars()) do
        if tonumber(rec.gold) and mod.Shown(key) then sum, any = sum + rec.gold, true end
    end
    return any and sum or nil
end

-- "1,234g 56s 78c" with coin icons, every coin that isn't 0 (so the rows add up to the total);
-- silver / copper can be left out (settings > Look), the amounts and totals stay exact
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"
local function Thousands(n)
    local s = tostring(n)
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
end
function mod.FormatGold(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Thousands(g) .. GOLD end
    local silver, cop = M.db.goldSilver ~= false, M.db.goldCopper ~= false
    if s > 0 and silver then parts[#parts + 1] = s .. SILVER end
    if c > 0 and cop then parts[#parts + 1] = c .. COPPER end
    if #parts == 0 then parts[1] = cop and (c .. COPPER) or (silver and (s .. SILVER)) or ("0" .. GOLD) end
    return table.concat(parts, " ")
end

-- one character's counts of an item: total, { place = n }
function mod.CountOf(key, itemID)
    local rec = mod.Chars()[key]
    if not rec then return 0 end
    local total, parts = 0, {}
    for _, p in ipairs(mod.PLACES) do
        local n = rec[p] and rec[p][itemID] or 0
        if p == "e" and not M.db.equipped then n = 0 end
        if n > 0 then parts[p] = n; total = total + n end
    end
    return total, parts
end

M.OnEnable = function()
    local key = MMT.PlayerFull()
    if key then mod.Mine()[key] = true end
    local rec = mod.Own()
    if rec then rec.rs = mod.Ruleset() or rec.rs end
    mod.ScanAll()
    mod.ScanGold()
    mod.SetupMinimap()
end

M.OnDisable = function()
    if mod.minimap then mod.minimap:Hide() end
    if mod.bags then mod.bags:Hide() end
end

M.OnProfileChanged = function()
    mod.SetupMinimap()
    if mod.RefreshBags then mod.RefreshBags() end
end

SLASH_MMTTEAMINV1 = "/mmtinv"
SlashCmdList.MMTTEAMINV = function(msg)
    if not M.enabled then MMT.Print("Team Inventory is switched off (/mmt modules).") return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "bags" or msg == "bank" or msg == "mail" then
        mod.OpenBags(({ bags = "b", bank = "k", mail = "m" })[msg])
    elseif msg == "send" then
        mod.SendSnapshot()
        MMT.Print("Team Inventory: your items were sent to the team.")
    elseif msg == "request" then
        mod.RequestAll()
        MMT.Print("Team Inventory: asked the team for their items.")
    else
        MMT.Print("Team Inventory: /mmtinv bags | bank | mail | send | request. Open your bank and mailbox once on each character so they're counted.")
    end
end
