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
-- e = equipped, s = soulbound ones in the bags, hash, time }, and M.store.mine[key] = true for characters of
-- this account (Syndicator already lists those in its own tooltip lines).

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.5.1"
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
    syncExclude = { "minimapAngle", "bagsPoint", "bagsScale", "lastWho", "bagFilter" },   -- belong to each screen
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
        autoAccept = true,     -- accept a trade that holds nothing but planned gifts (both sides)
        sidePanel = true,      -- the team / trades panel beside the team bags
        bagFilter = "ALL",     -- team bags: ALL | NOBOE | NOBOUND | NOBOTH | BOE / BOUND (only those) | NOREAGENT | REAGENT
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
    mod.ScanAll()
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
