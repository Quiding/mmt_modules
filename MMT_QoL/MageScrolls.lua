-- MMT Quality of life: mage scrolls onto a role.
--
-- WoW: Forever's mage scrolls ("Scroll: LOWER PING WHOMEVER", Classes: Mage, Requires
-- Comprehension) each have a name and item of their own, and MMT roles only take exact
-- items. So every such item this client sees goes on the role (e.g. "Mage scrolls") through
-- the Role items panel's own path (mod.MailAdd: shared with the team), and Loot Distribution
-- hands it to that role from then on:
--   - the scrolls already known (KNOWN), when the feature starts and when it looks again;
--   - the loot window, on LOOT_READY - before Loot Distribution hands out the loot (it
--     works on LOOT_OPENED), so even the first of a new scroll goes to the role;
--   - this character's bags (also what was looted or traded), a moment after they change.
-- An item counts when its name starts with "Scroll: " (read from the link or the loot slot,
-- so no item data is needed). With scDejunk a scroll is also taken off Dejunk's (global)
-- junk list, so Dejunk doesn't sell it (mod.DejunkFromHere: the team's lists follow when
-- the Dejunk sync is on).

local _, mod = ...
local MMT = MMT
local M = mod.M

local PREFIX = "Scroll: "
-- seen on the team so far (more are learned from the loot window and the bags)
local KNOWN = { 211780, 211785, 211786, 211787, 211853, 211854, 213543, 213544, 213545, 213546, 213547, 281018 }

local F
local sc = { added = 0, seen = 0 }
mod.sc = sc

local function ItemID(link) return link and tonumber(tostring(link):match("item:(%d+)")) end

-- is it a mage scroll? by the name in the link ("[Scroll: CWAL]") or a plain name
function mod.IsMageScroll(nameOrLink)
    if type(nameOrLink) ~= "string" or MMT.IsSecret(nameOrLink) then return false end
    local name = nameOrLink:match("|h%[(.-)%]|h") or nameOrLink
    return name:sub(1, #PREFIX) == PREFIX
end

-- the role it goes on (the saved one while it exists)
function mod.ScrollRole()
    for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do
        if r == M.db.scRole then return r end
    end
    return nil
end

local function OnRole(role, id)
    local r = MMT.db and MMT.db.roles and MMT.db.roles[role]
    for _, rule in ipairs(type(r) == "table" and type(r.rules) == "table" and r.rules or {}) do
        if rule.type == "item" and rule.itemID == id then return true end
    end
    return false
end

-- off Dejunk's junk list (nothing when it isn't on it, or Dejunk isn't here)
local function Unjunk(id)
    if not M.db.scDejunk or not mod.DejunkFromHere then return end
    local ok, done = pcall(mod.DejunkFromHere, "-", tostring(id))
    if ok and done then sc.unjunked = (sc.unjunked or 0) + 1 end
end

-- one item (ID or link) onto the role, unless it's there already: true when added
local function Put(item, link)
    local role = mod.ScrollRole()
    local id = tonumber(item) or ItemID(item)
    if not role or not id then return false end
    Unjunk(id)
    if OnRole(role, id) then return false end
    if not mod.MailAdd(role, id) then return false end
    sc.added = sc.added + 1
    if M.db.scChat then MMT.Print("Quality of life: %s goes on the role %s (mage scroll).", link or mod.ItemText(id), role) end
    return true
end

-- the known scrolls; returns how many went on now
function mod.ScrollSeed()
    if not mod.Active(F) or not mod.ScrollRole() then return 0 end
    local n = 0
    for _, id in ipairs(KNOWN) do if Put(id) then n = n + 1 end end
    return n
end

-- one item seen somewhere: on the role if it's a mage scroll
function mod.ScrollConsider(link, name)
    if not mod.Active(F) then return false end
    if not (mod.IsMageScroll(link) or mod.IsMageScroll(name)) then return false end
    sc.seen = sc.seen + 1
    return Put(link, type(link) == "string" and link or nil)
end

-- the loot window, before Loot Distribution hands it out
M:On("LOOT_READY", function()
    if not mod.Active(F) or type(GetNumLootItems) ~= "function" then return end
    mod.ScrollSeed()
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local name = GetLootSlotInfo and select(2, GetLootSlotInfo(slot))
        if link then mod.ScrollConsider(link, name) end
    end
end)

-- this character's bags
function mod.ScrollBags()
    if not mod.Active(F) then return 0 end
    local n = mod.ScrollSeed()
    for bag = 0, (MMT.BAGS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and mod.ScrollConsider(info.hyperlink) then n = n + 1 end
        end
    end
    return n
end

local bagsDue = false
local function BagsLater()
    if bagsDue or not mod.Active(F) then return end
    bagsDue = true
    C_Timer.After(2, function() bagsDue = false; pcall(mod.ScrollBags) end)
end
M:On("BAG_UPDATE_DELAYED", BagsLater)
M:On("PLAYER_ENTERING_WORLD", BagsLater)

local function RoleChoices()
    local t = { { value = "", text = "(choose a role)" } }
    for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do t[#t + 1] = { value = r, text = r } end
    local cur = M.db.scRole
    if cur and cur ~= "" and not mod.ScrollRole() then t[#t + 1] = { value = cur, text = cur .. " (missing)" } end
    return t
end

F = mod.Feature({
    key = "mscroll", icon = "INV_Scroll_03", slash = "scrolls", title = "Mage scrolls to a role", tabText = "Mage scrolls",
    checkText = "Put every mage scroll on a role",
    tip = "Every \"Scroll: ...\" item (the mage scrolls that need Comprehension) goes on a role's items, so Loot Distribution gives them to that role and \"Mail to team\" sends them there.",
    notes = {
        "Each mage scroll is an item of its own, and roles only take exact items, so this puts each one on the role you pick: the ones already seen on the team right away, and any other as soon as it shows up in the loot window (before Loot Distribution hands the loot out) or in this character's bags. The same as dropping it on the Role items panel, so the whole team gets the change.",
        "Make the role first (MMT settings > Roles, e.g. \"Mage scrolls\") and give it to your mage.",
    },
    commands = {
        [""] = function()
            if not mod.Active(F) then MMT.Print("Quality of life: Mage scrolls is off.") return end
            if not mod.ScrollRole() then MMT.Print("Quality of life: pick the role for mage scrolls first (Mage scrolls tab).") return end
            MMT.Print("Quality of life: %d mage scroll(s) put on the role %s now.", mod.ScrollBags(), mod.ScrollRole())
        end,
    },
    OnEnable = function() BagsLater() end,
    Page = function(ui)
        ui.Cycle("Role", RoleChoices, "scRole")
        ui.Button("Put them on the role now", function() F.commands[""]() end,
            "The known mage scrolls and the ones in your bags, now. Also /mmtqol scrolls. (It happens by itself too.)")
        ui.Check("Take them off Dejunk's junk list", "scDejunk", "A mage scroll on Dejunk's (global) junk list is taken off it, so Dejunk doesn't sell it. With the Dejunk sync on, the team's lists follow.")
        ui.Check("Chat line for each scroll", "scChat", "Says which scroll went on the role.")
    end,
    Report = function(add)
        add(("Mage scrolls: on=%s role=%s dejunk=%s seen=%d added=%d unjunked=%d"):format(tostring(M.db.mscroll), tostring(mod.ScrollRole()),
            tostring(M.db.scDejunk), sc.seen, sc.added, sc.unjunked or 0))
    end,
})
mod.ScrollFeature = F
