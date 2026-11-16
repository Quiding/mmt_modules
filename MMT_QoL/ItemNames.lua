-- MMT Quality of life: items by name onto a role.
--
-- MMT roles only take exact items (or broad rules: a quality, a type, an item group). Some
-- kinds of item are many items with one way of naming them - WoW: Forever's mage scrolls
-- ("Scroll: LOWER PING WHOMEVER", Classes: Mage, Requires Comprehension), "Essence of ..." -
-- so this keeps a short list of name rules, each with a role: every item whose name starts
-- with the text (or, with a "*" in front, has it anywhere in the name; no case) goes on that
-- role through the Role items panel's own path (mod.MailAdd: shared with the team), and Loot
-- Distribution hands it to the role from then on. Items are found
--   - in the loot window, on LOOT_READY - before Loot Distribution hands out the loot (it
--     works on LOOT_OPENED), so even the first of a new item goes to the role;
--   - in this character's bags (also what was looted or traded), a moment after they change;
--   - among the mage scrolls already seen on the team (KNOWN), for a rule that takes them.
-- The name is read from the link or the loot slot, so no item data is needed.
-- With nrDejunk an item put on a role also comes off Dejunk's (global) junk list, so Dejunk
-- doesn't sell it (mod.DejunkFromHere: the team's lists follow when the Dejunk sync is on).
--
-- Settings: nr<i>Text / nr<i>Role for the rules i = 1..RULES (flat keys: they sync like the rest).

local _, mod = ...
local MMT = MMT
local M = mod.M

local RULES = 6
mod.NAME_RULES = RULES
-- mage scrolls seen on the team so far (more are found in the loot window and the bags)
local KNOWN = {
    { 211780, "Scroll: KWYJIBO" }, { 211785, "Scroll: CWAL" }, { 211786, "Scroll: CHAP BALK WELLES" },
    { 211787, "Scroll: LOWER PING WHOMEVER" }, { 211853, "Scroll: VOCE WELL" }, { 211854, "Scroll: OMIT KESA" },
    { 213543, "Scroll: UPDOG" }, { 213544, "Scroll: TOPAZ YORAK" }, { 213545, "Scroll: PEATCHY ATTAX" },
    { 213546, "Scroll: SHOOBEEDOOP" }, { 213547, "Scroll: THAW WORDS" }, { 281018, "Scroll: RARE SERVICHI RADAR" },
}

local F
local nr = { added = 0, seen = 0, unjunked = 0 }
mod.nr = nr

local function ItemID(link) return link and tonumber(tostring(link):match("item:(%d+)")) end
local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- the item's name from a link ("[Scroll: CWAL]") or a plain name
local function NameOf(x)
    if type(x) ~= "string" or MMT.IsSecret(x) then return nil end
    return x:match("|h%[(.-)%]|h") or x
end

local function RoleExists(role)
    if not role or role == "" then return false end
    for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do if r == role then return true end end
    return false
end

-- the rules in use: { { text, role, anywhere } } (a text and a role that exists)
function mod.NameRules()
    local t = {}
    for i = 1, RULES do
        local text, role = Trim(M.db["nr" .. i .. "Text"]), M.db["nr" .. i .. "Role"]
        local anywhere = text:sub(1, 1) == "*"
        if anywhere then text = Trim(text:sub(2)) end
        if text ~= "" and RoleExists(role) then t[#t + 1] = { text = text:lower(), role = role, anywhere = anywhere } end
    end
    return t
end

-- the role a name (or link) goes on, by the first rule that takes it, or nil
function mod.NameRole(nameOrLink, rules)
    local name = NameOf(nameOrLink)
    if not name then return nil end
    name = name:lower()
    for _, r in ipairs(rules or mod.NameRules()) do
        if r.anywhere and name:find(r.text, 1, true) or name:sub(1, #r.text) == r.text then return r.role end
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
    if not M.db.nrDejunk or not mod.DejunkFromHere then return end
    local ok, done = pcall(mod.DejunkFromHere, "-", tostring(id))
    if ok and done then nr.unjunked = nr.unjunked + 1 end
end

-- one item onto a role, unless it's there already: true when added
local function Put(role, id, link)
    if not role or not id then return false end
    Unjunk(id)
    if OnRole(role, id) then return false end
    if not mod.MailAdd(role, id) then return false end
    nr.added = nr.added + 1
    if M.db.nrChat then MMT.Print("Quality of life: %s goes on the role %s (by its name).", link or mod.ItemText(id), role) end
    return true
end

-- one item seen somewhere (link, and the name when the link has none): true when added
function mod.NameConsider(link, name, rules)
    if not mod.Active(F) then return false end
    local role = mod.NameRole(link, rules) or (name and mod.NameRole(name, rules))
    if not role then return false end
    nr.seen = nr.seen + 1
    return Put(role, ItemID(link), type(link) == "string" and link or nil)
end

-- the known mage scrolls a rule takes; returns how many went on now
function mod.NameSeed()
    if not mod.Active(F) then return 0 end
    local rules, n = mod.NameRules(), 0
    if #rules == 0 then return 0 end
    for _, k in ipairs(KNOWN) do
        local role = mod.NameRole(k[2], rules)
        if role and Put(role, k[1]) then n = n + 1 end
    end
    return n
end

-- the loot window, before Loot Distribution hands it out
M:On("LOOT_READY", function()
    if not mod.Active(F) or type(GetNumLootItems) ~= "function" then return end
    local rules = mod.NameRules()
    if #rules == 0 then return end
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        if link then mod.NameConsider(link, GetLootSlotInfo and select(2, GetLootSlotInfo(slot)), rules) end
    end
end)

-- this character's bags (and the known scrolls); returns how many went on now
function mod.NameBags()
    if not mod.Active(F) then return 0 end
    local rules = mod.NameRules()
    if #rules == 0 then return 0 end
    local n = mod.NameSeed()
    for bag = 0, (MMT.BAGS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and mod.NameConsider(info.hyperlink, nil, rules) then n = n + 1 end
        end
    end
    return n
end

local bagsDue = false
local function BagsLater()
    if bagsDue or not mod.Active(F) then return end
    bagsDue = true
    C_Timer.After(2, function() bagsDue = false; pcall(mod.NameBags) end)
end
M:On("BAG_UPDATE_DELAYED", BagsLater)
M:On("PLAYER_ENTERING_WORLD", BagsLater)

local function RoleChoices(key)
    return function()
        local t = { { value = "", text = "(no role)" } }
        for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do t[#t + 1] = { value = r, text = r } end
        local cur = M.db[key]
        if cur and cur ~= "" and not RoleExists(cur) then t[#t + 1] = { value = cur, text = cur .. " (missing)" } end
        return t
    end
end

local boxes = {}
F = mod.Feature({
    key = "nrules", icon = "INV_Scroll_03", slash = "byname", title = "Items by name to a role", tabText = "By name",
    checkText = "Put items on a role by their name",
    tip = "Every item whose name starts with a text you give (\"Scroll:\" - the mage scrolls, \"Essence of\", ...) goes on a role's items, so Loot Distribution gives it to that role and \"Mail to team\" sends it there.",
    notes = {
        "MMT roles only take exact items, and some kinds of item are many items - every mage scroll (\"Scroll: ...\") is an item of its own. Each rule here gives a text and a role: an item whose name starts with the text (no case; put a * in front to find it anywhere in the name) goes on the role as soon as it is in the loot window (before Loot Distribution hands the loot out) or in this character's bags - the same as dropping it on the Role items panel, so the whole team gets the change. The first rule that fits wins.",
        "Make the roles first (MMT settings > Roles) and give them to the characters who should get the items.",
    },
    commands = {
        [""] = function()
            if not mod.Active(F) then MMT.Print("Quality of life: Items by name is off.") return end
            if #mod.NameRules() == 0 then MMT.Print("Quality of life: no name rule with a role yet (By name tab).") return end
            MMT.Print("Quality of life: %d item(s) put on their role by name now.", mod.NameBags())
        end,
    },
    OnEnable = function() BagsLater() end,
    Refresh = function()
        for i, box in pairs(boxes) do
            if not box:HasFocus() then box:SetText(M.db["nr" .. i .. "Text"] or "") end
        end
    end,
    Page = function(ui)
        local col = ui.col
        local W = tonumber(col.width) or 300
        local textW = math.floor(W * 0.5)
        col:Add(MMT.UI.Label(col.parent, "Name starts with ... goes to the role"), 16)
        for i = 1, RULES do
            local tk, rk = "nr" .. i .. "Text", "nr" .. i .. "Role"
            local function Take(box)
                M.db[tk] = Trim(box:GetText())
                box:SetText(M.db[tk])
            end
            local box = MMT.UI.EditBox(col.parent, textW - 4, i == 1 and "e.g. Scroll:" or "e.g. Essence of", function(_, b) Take(b); b:ClearFocus() end)
            box:HookScript("OnEditFocusLost", function(b) Take(b) end)
            box:SetText(M.db[tk] or "")
            MMT.UI.Tooltip(box, "Name starts with",
                "Items whose name starts with this go on the role beside it (no case). A * in front: anywhere in the name (*Essence). Empty: rule not used. Enter or click away to keep it.")
            boxes[i] = box
            local y = col.y
            col:Add(box, MMT.UI.ROW + 2)
            local dd = MMT.UI.Dropdown(col.parent, W - textW, "", RoleChoices(rk),
                function() return M.db[rk] end, function(v) if mod.Active(F) then M.db[rk] = v end end)
            dd:ClearAllPoints()
            dd:SetPoint("TOPLEFT", col.parent, "TOPLEFT", (tonumber(col.x) or 0) + textW, y)
        end
        ui.Button("Put them on their roles now", function() F.commands[""]() end,
            "The items in your bags (and the known mage scrolls) that a rule takes, now. Also /mmtqol byname. (It happens by itself too.)")
        ui.Check("Take them off Dejunk's junk list", "nrDejunk", "An item put on a role here is taken off Dejunk's (global) junk list, so Dejunk doesn't sell it. With the Dejunk sync on, the team's lists follow.")
        ui.Check("Chat line for each item", "nrChat", "Says which item went on which role.")
    end,
    Report = function(add)
        local r = {}
        for _, x in ipairs(mod.NameRules()) do r[#r + 1] = (x.anywhere and "*" or "") .. x.text .. ">" .. x.role end
        add(("Items by name: on=%s rules=%s dejunk=%s seen=%d added=%d unjunked=%d"):format(tostring(M.db.nrules),
            table.concat(r, ","), tostring(M.db.nrDejunk), nr.seen, nr.added, nr.unjunked))
    end,
})
mod.NameFeature = F
