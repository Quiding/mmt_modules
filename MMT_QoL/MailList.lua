-- MMT Quality of life: role items beside your bags (was "Mail list").
-- A small panel docked to the open bags (Baganator's backpack window, else the
-- game's bags) shows one MMT role's items: pick the role in its dropdown, drop
-- an item on it (or shift-click one into its box) and that item is on the role.
-- Trading with a team member hands over what their role wants, and MMT's
-- "Mail to team" at the mailbox mails every item a member's role wants to
-- that member - e.g. a role made just for mailing ("Mail Bank") on the bank alt.
-- The lists ARE MMT's role items (MMT settings > Roles shows the same):
-- MMT.AddRule / MMT.RemoveRule. Loot Distribution goes by them too.
-- Nothing is created until the bags are first open with the feature on.
-- Team Inventory's team bags window (MMTTeamBagsWindow) counts as bags too: with
-- both open the panel sits beside the one opened last, on the side away from the
-- team bags' member list. An item dragged out of the team bags onto the panel goes
-- on the role (Team Inventory calls panel.mmtAcceptItem(itemID)).
-- Team sync (mlSync): MMT core shares roles only with a whole profile sync, so
-- what is added / taken off here goes to the team together, 5 seconds after the last
-- change (at most 30 s after the first; MailQueue / MailFlush), so adding a pile of items
-- is one message per role (the one mailing needs the list): QML:<+|->:<role>:<i<itemID>|n<name>>,...  ("+" makes the role
-- on a member who hasn't got it; who has which role isn't sent). Item entries
-- only - other rules (all grey items, ...) stay on the Roles page.

local _, mod = ...
local MMT = MMT
local M = mod.M

local W, ROW_H, ROWS = 236, 18, 10
local F
local panel, tab, ticker
local dockedTo            -- the bag frame the panel sits beside
local bagNames            -- Baganator's backpack frame names (one per skin), found once
local lastScan = -100
local MSG_MAX = 240
local ml = { sent = 0, got = 0, added = 0, removed = 0 }
mod.ml = ml

---------------------------------------------------------------------------
-- The lists (MMT's roles)
---------------------------------------------------------------------------
local function Roles() return MMT.SortedRoleNames and MMT.SortedRoleNames() or {} end

local function RoleData(role)
    local db = MMT.db
    local r = role and db and type(db.roles) == "table" and db.roles[role]
    return type(r) == "table" and r or nil
end

-- the chosen role: the saved one while it exists, else the first
function mod.MailRole()
    local roles = Roles()
    for _, r in ipairs(roles) do if r == M.db.mlRole then return r end end
    return roles[1]
end

-- the role's entries (MMT's rules, items and others): { rule, index }
function mod.MailEntries(role)
    local r = RoleData(role)
    local t = {}
    for i, rule in ipairs(r and type(r.rules) == "table" and r.rules or {}) do t[#t + 1] = { rule = rule, index = i } end
    return t
end

-- the team members who have the role (who its items get mailed to), by name
function mod.MailMembers(role)
    local t = {}
    local team = MMT.db and MMT.db.team
    if not role or type(team) ~= "table" then return t end
    for key in pairs(team) do
        if MMT.HasRole(key, role) then t[#t + 1] = MMT.ShownName and MMT.ShownName(key) or (key:match("^[^-]+") or key) end
    end
    table.sort(t)
    return t
end

-- the entries whose text has query (plain text, any case; "" = all of them)
local function Plain(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", ""):lower())
end
function mod.MailFilter(entries, query)
    query = tostring(query or ""):match("^%s*(.-)%s*$")
    if query == "" then return entries end
    query = query:lower()
    local t = {}
    for _, e in ipairs(entries) do
        local r = e.rule or {}
        local text = MMT.DescribeRule and (MMT.DescribeRule(r)) or ""
        local hay = Plain(text) .. " " .. Plain(r.name) .. " " .. tostring(r.itemID or "")
        if hay:find(query, 1, true) then t[#t + 1] = e end
    end
    return t
end

local function ItemID(x)
    return tonumber(x) or (type(x) == "string" and tonumber(x:match("item:(%d+)"))) or nil
end

-- an item (ID, link or exact name) onto the role: true, or false + why
function mod.MailAdd(role, item)
    if not role then return false, "Make a role first (MMT settings > Roles)." end
    local id = ItemID(item)
    local rule
    if id then
        rule = { type = "item", itemID = id, name = MMT.ItemInfo and (MMT.ItemInfo(id)) or nil }
    elseif type(item) == "string" and MMT.RuleFromText then
        rule = MMT.RuleFromText(item)       -- an exact item name
    end
    if not rule then return false, "Drop or shift-click an item." end
    local ok, err = MMT.AddRule(role, rule)
    if ok then mod.MailQueue("+", role, rule) end
    return ok, err
end

function mod.MailRemove(role, index)
    local r = RoleData(role)
    local rule = r and r.rules[index]
    if not rule then return end
    MMT.RemoveRule(role, index)
    mod.MailQueue("-", role, rule)
end

---------------------------------------------------------------------------
-- The team: changes sent as they happen, the whole lists on request
---------------------------------------------------------------------------
local function Esc(s) return (tostring(s):gsub("[%%:,;=|%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- an item entry as sent ("i2589" / "n<name>"), nil for other rules
local function Token(rule)
    if type(rule) ~= "table" or rule.type ~= "item" then return nil end
    if rule.itemID then return "i" .. rule.itemID end
    if type(rule.name) == "string" and rule.name ~= "" then return "n" .. Esc(rule.name) end
end

local function FromToken(t)
    local id = t:match("^i(%d+)$")
    if id then
        id = tonumber(id)
        return { type = "item", itemID = id, name = MMT.ItemInfo and (MMT.ItemInfo(id)) or nil }
    end
    local name = t:match("^n(.+)$")
    if name then return { type = "item", name = Unesc(name) } end
end

local function Same(a, b)
    if a.type ~= "item" or b.type ~= "item" then return false end
    if a.itemID or b.itemID then return a.itemID == b.itemID end
    return type(a.name) == "string" and type(b.name) == "string" and a.name:lower() == b.name:lower()
end

-- QML:<sign>:<role>:<token>,<token>,... in messages of up to MSG_MAX
function mod.MailSend(sign, role, rules, force)
    if not role or not (force or (M.db.mlSync and mod.Active(F))) then return 0 end
    local head = ("QML:%s:%s:"):format(sign, Esc(role))
    local msg, n = "", 0
    for _, rule in ipairs(rules) do
        local t = Token(rule)
        if t then
            if msg ~= "" and #head + #msg + #t + 1 > MSG_MAX then
                MMT.SendToTeam(head .. msg, true); ml.sent = ml.sent + 1
                msg = ""
            end
            msg = msg == "" and t or (msg .. "," .. t)
            n = n + 1
        end
    end
    if msg ~= "" then MMT.SendToTeam(head .. msg, true); ml.sent = ml.sent + 1 end
    return n
end

-- changes made here wait QUIET seconds after the last one (at most MAX_WAIT after the first)
-- and then go out together: per role, the adds and the removals, each in as few messages as fit.
-- An item added and taken off again in that time only sends its last change.
local QUIET, MAX_WAIT = 5, 30
local queue, queueOrder, queueGen, queueFirst = {}, {}, 0, nil
ml.queued = 0

function mod.MailFlush()
    if not next(queue) then return 0 end
    local q, order = queue, queueOrder
    queue, queueOrder, queueFirst, ml.queued = {}, {}, nil, 0
    local n = 0
    for _, role in ipairs(order) do
        local byToken = q[role]
        if byToken then
            local add, remove = {}, {}
            for _, t in ipairs(byToken.order) do
                local e = byToken[t]
                if e.sign == "+" then add[#add + 1] = e.rule else remove[#remove + 1] = e.rule end
            end
            -- forced: they were checked when queued (and switching the feature off sends what waits)
            n = n + mod.MailSend("-", role, remove, true) + mod.MailSend("+", role, add, true)
        end
    end
    ml.flushes = (ml.flushes or 0) + 1
    ml.lastFlush = n
    if n > 0 and M.db.mlChat then
        MMT.Print("Role items: %d change%s sent to the team.", n, n == 1 and "" or "s")
    end
    return n
end

function mod.MailQueue(sign, role, rule)
    if not role or not (M.db.mlSync and mod.Active(F)) then return end
    local t = Token(rule)
    if not t then return end
    local r = queue[role]
    if not r then r = { order = {} }; queue[role] = r; queueOrder[#queueOrder + 1] = role end
    if not r[t] then r.order[#r.order + 1] = t; ml.queued = ml.queued + 1 end
    r[t] = { sign = sign, rule = rule }
    local now = GetTime and GetTime() or 0
    queueFirst = queueFirst or now
    queueGen = queueGen + 1
    local gen = queueGen
    local wait = math.max(0, math.min(QUIET, MAX_WAIT - (now - queueFirst)))
    C_Timer.After(wait, function() if gen == queueGen then mod.MailFlush() end end)
end

-- every role's item entries to the team (they add what they lack; nothing is taken off)
function mod.MailSendAll()
    mod.MailFlush()
    local roles, items = 0, 0
    for _, role in ipairs(Roles()) do
        local r = RoleData(role)
        local n = mod.MailSend("+", role, r and r.rules or {}, true)
        if n > 0 then roles, items = roles + 1, items + n end
    end
    return roles, items
end

local function OnSync(key, _, body)
    local sign, role, list = tostring(body):match("^([%+%-]):([^:]+):(.*)$")
    if not sign or not M.db.mlSync then return end
    role = Unesc(role)
    ml.got = ml.got + 1
    if sign == "+" and not RoleData(role) and MMT.AddRole then MMT.AddRole(role) end
    local r = RoleData(role)
    if not r then return end
    local done = {}
    for t in list:gmatch("[^,]+") do
        local rule = FromToken(t)
        if rule then
            if sign == "+" then
                if MMT.AddRule(role, rule) then done[#done + 1] = rule; ml.added = ml.added + 1 end
            else
                for i = #r.rules, 1, -1 do
                    if Same(r.rules[i], rule) then
                        MMT.RemoveRule(role, i); done[#done + 1] = rule; ml.removed = ml.removed + 1
                        break
                    end
                end
            end
        end
    end
    if #done > 0 and M.db.mlChat then
        local who = MMT.ShownName and MMT.ShownName(key) or tostring(key)
        local what = #done == 1 and (done[1].itemID and mod.ItemText(done[1].itemID) or tostring(done[1].name))
            or (#done .. " items")
        MMT.Print("Role items from %s: %s %s %s.", who, what, sign == "+" and "added to" or "taken off", role)
    end
end

---------------------------------------------------------------------------
-- Which bags are open
---------------------------------------------------------------------------
local function Open(f) return type(f) == "table" and f.IsVisible and f:IsVisible() end

local function BaganatorFrames()
    if not (mod.AddonState("Baganator")) then return {} end
    -- one backpack frame per Baganator skin, named after it: found by name once they exist
    if not bagNames or (#bagNames == 0 and GetTime() - lastScan > 10) then
        lastScan = GetTime()
        bagNames = {}
        for name, v in pairs(_G) do
            -- only the windows themselves (on UIParent): their parts are named after them too
            if type(name) == "string" and type(v) == "table" and (name:find("^Baganator_SingleViewBackpackViewFrame")
                or name:find("^Baganator_CategoryViewBackpackViewFrame")) and type(v.GetParent) == "function" then
                local ok, parent = pcall(v.GetParent, v)
                if ok and parent == UIParent then bagNames[#bagNames + 1] = name end
            end
        end
    end
    local t = {}
    for _, name in ipairs(bagNames) do t[#t + 1] = rawget(_G, name) end
    return t
end

-- my own open bags: Baganator's backpack, else the game's (all bags in one, else the backpack)
local function OwnBags()
    for _, f in ipairs(BaganatorFrames()) do if Open(f) then return f end end
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if Open(combined) then return combined end
    local backpack = rawget(_G, "ContainerFrame1")
    if Open(backpack) then return backpack end
    return nil
end

-- the open bag frame to dock beside: my bags or Team Inventory's team bags - with both
-- open, the one opened last
local openedAt = setmetatable({}, { __mode = "k" })   -- [frame] = GetTime() it was first seen open
function mod.MailBagFrame()
    local own = OwnBags()
    local team = rawget(_G, "MMTTeamBagsWindow")
    if not Open(team) then team = nil end
    for _, f in ipairs({ own, team }) do if not openedAt[f] then openedAt[f] = GetTime() end end
    for f in pairs(openedAt) do if f ~= own and f ~= team then openedAt[f] = nil end end
    if own and team then return (openedAt[team] > openedAt[own]) and team or own end
    return own or team
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local Render

local function Status(text, bad)
    if not panel then return end
    panel.status:SetText(text or "")
    if bad then panel.status:SetTextColor(1, 0.45, 0.35) else panel.status:SetTextColor(0.55, 0.85, 0.55) end
end

local function Add(item)
    local role = mod.MailRole()
    local ok, err = mod.MailAdd(role, item)
    if ok then
        local id = ItemID(item)
        Status(("%s is on %s."):format(id and mod.ItemText(id) or tostring(item), role))
    else
        Status(err, true)
    end
    Render()
    return ok
end

local function AddFromCursor()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then Status("Drag an item from your bags onto this.", true) return end
    ClearCursor()
    Add(id)
end

-- the list itself takes a dropped item too (dragged, or picked up and clicked onto it);
-- a plain click there does nothing
local function DropHere()
    if GetCursorInfo() == "item" then AddFromCursor() end
end

local function Build()
    if panel then return end
    local UI = MMT.UI
    local A = UI.ACCENT

    local p = CreateFrame("Frame", "MMTQoLMailList", UIParent)
    p:SetSize(W, 120 + ROWS * ROW_H)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    UI.Fill(p, 0.05, 0.05, 0.06, 0.96)
    UI.Border(p, 0.22, 0.24, 0.28, 1)
    p:Hide()
    p.offset = 0
    panel = p
    -- an item dragged out of Team Inventory's team bags (not the cursor: its own drag)
    p.mmtAcceptItem = function(itemID) return Add(itemID) end

    local title = UI.Label(p, "MMT role items", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -7)
    local hide = UI.TextButton(p, "-", function() M.db.mlOpen = false; mod.MailDock() end)
    hide:SetPoint("TOPRIGHT", -2, -3)
    UI.Tooltip(hide, "Fold away", "A small \"Role items\" button on top of the bags opens it again (or /mmtqol roles).")

    p.role = UI.Dropdown(p, W - 16, "Role",
        function()
            local t = {}
            for _, r in ipairs(Roles()) do t[#t + 1] = { value = r, text = r } end
            return t
        end,
        function() return mod.MailRole() end,
        function(v) M.db.mlRole = v; Status(""); Render() end)
    p.role:SetPoint("TOPLEFT", 8, -26)
    UI.Tooltip(p.role, "Role", "Which role's items to show and add to. The team member who has the role gets them in a trade and by MMT's \"Mail to team\" at the mailbox. Roles and who has them: MMT settings > Roles.")

    p.to = UI.Label(p, "")
    p.to:SetPoint("TOPLEFT", p.role, "BOTTOMLEFT", 0, -4)
    p.to:SetWidth(W - 16)
    p.to:SetJustifyH("LEFT")
    p.to:SetWordWrap(false)

    p.drop = UI.Button(p, W - 16, "Drop an item here", AddFromCursor)
    p.drop:SetScript("OnReceiveDrag", AddFromCursor)
    p.drop:SetPoint("TOPLEFT", p.to, "BOTTOMLEFT", 0, -5)
    UI.Tooltip(p.drop, "Add an item", "Drag an item from your bags onto this button - or onto the list below - to put it on the role.")

    p.box = UI.EditBox(p, W - 64, "Or shift-click an item", function(text, box)
        if text ~= "" and Add(text) then box:SetText(""); box:ClearFocus() end
    end)
    p.box:SetPoint("TOPLEFT", p.drop, "BOTTOMLEFT", 0, -4)
    UI.AcceptItemLinks(p.box, function(link) Status(link .. " - press Enter or Add.") end)
    UI.Tooltip(p.box, "Add an item", "Click into the box, then shift-click an item (bags, loot, chat links, ...). Item IDs and exact item names work too.")
    local add = UI.Button(p, 44, "Add", function() p.box:GetScript("OnEnterPressed")(p.box) end)
    add:SetPoint("LEFT", p.box, "RIGHT", 4, 0)

    -- search: only the list's entries whose text has it (name, any part, any case)
    p.search = UI.EditBox(p, W - 38, "Search the list", function(_, box) box:ClearFocus() end)
    p.search:SetPoint("TOPLEFT", p.box, "BOTTOMLEFT", 0, -6)
    p.search:HookScript("OnTextChanged", function() p.offset = 0; Render() end)
    UI.Tooltip(p.search, "Search", "Shows only the items on this role's list whose name has what you type. Esc or the x clears it.")
    p.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    local clear = UI.TextButton(p, "x", function() p.search:SetText(""); p.search:ClearFocus() end, 18)
    clear:SetPoint("LEFT", p.search, "RIGHT", 4, 0)
    UI.Tooltip(clear, "Clear the search")

    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -4)
    list:SetSize(W - 16, ROWS * ROW_H + 4)
    UI.Fill(list, 0.08, 0.08, 0.09, 1)
    UI.Border(list, 0.2, 0.2, 0.22, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) p.offset = p.offset - delta * 3; Render() end)
    list:EnableMouse(true)
    list:SetScript("OnReceiveDrag", DropHere)
    list:SetScript("OnMouseUp", DropHere)
    p.list = list
    p.empty = UI.Label(list, "")
    p.empty:SetPoint("TOPLEFT", 6, -6)
    p.empty:SetWidth(W - 28)
    p.empty:SetJustifyH("LEFT")
    p.empty:SetTextColor(0.5, 0.5, 0.5)

    p.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(W - 20, ROW_H)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 4, 0)
        r.text = UI.Label(r, "")
        r.text:SetPoint("LEFT", 22, 0)
        r.text:SetPoint("RIGHT", -22, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.remove = UI.TextButton(r, "x", function()
            if r.entry then mod.MailRemove(mod.MailRole(), r.entry.index); Status(""); Render() end
        end, 18)
        r.remove:SetPoint("RIGHT", 0, 0)
        r:SetScript("OnReceiveDrag", DropHere)
        r:SetScript("OnClick", DropHere)
        r:SetScript("OnEnter", function(self)
            local rule = self.entry and self.entry.rule
            if not rule then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if rule.type == "item" and rule.itemID then
                GameTooltip:SetItemByID(rule.itemID)
            else
                GameTooltip:SetText((MMT.DescribeRule(rule)))
            end
            GameTooltip:AddLine("x on the right takes it off the list.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.rows[i] = r
    end

    p.count = UI.Label(p, "")
    p.count:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -5)
    p.count:SetTextColor(0.6, 0.6, 0.6)
    p.status = UI.Label(p, "")
    p.status:SetPoint("TOPLEFT", p.count, "BOTTOMLEFT", 0, -3)
    p.status:SetWidth(W - 16)
    p.status:SetJustifyH("LEFT")
    p.status:SetWordWrap(false)
    p:SetHeight(26 + 22 + 16 + 25 + 24 + 6 + ((UI.ROW or 24) + 2) + ROWS * ROW_H + 4 + 34)

    -- folded away: a small button beside the bags
    -- in a named (empty) holder: Styles tells its windows apart by the name of the frame on UIParent
    local holder = CreateFrame("Frame", "MMTQoLMailListTab", UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("TOPLEFT")
    tab = UI.Button(holder, 80, "Role items", function() M.db.mlOpen = true; mod.MailDock() end)
    tab.label:SetTextColor(A[1], A[2], A[3])
    tab:SetClampedToScreen(true)
    UI.Tooltip(tab, "MMT role items", "Shows which items each role gets (trade, mail and loot), and adds items to it.")
    tab:Hide()
end

Render = function()
    if not panel or not panel:IsShown() then return end
    local role = mod.MailRole()
    panel.role.Refresh()
    if not role then
        panel.to:SetText("|cffff9966No roles yet: make one in MMT settings > Roles.|r")
    else
        local who = mod.MailMembers(role)
        panel.to:SetText(#who > 0 and ("|cff999999Who has it:|r " .. table.concat(who, ", "))
            or "|cffff9966Nobody has this role yet (MMT settings > Roles).|r")
    end
    local all = mod.MailEntries(role)
    local query = panel.search and panel.search:GetText() or ""
    local entries = mod.MailFilter(all, query)
    local maxOff = math.max(0, #entries - ROWS)
    panel.offset = math.min(math.max(panel.offset, 0), maxOff)
    for i, r in ipairs(panel.rows) do
        local e = entries[panel.offset + i]
        r.entry = e
        if e then
            local text, icon, cr, cg, cb = MMT.DescribeRule(e.rule)
            r.text:SetText(text)
            r.text:SetTextColor(cr or 1, cg or 1, cb or 1)
            r.icon:SetTexture(icon or "Interface\\Buttons\\WHITE8x8")
            if icon then r.icon:SetVertexColor(1, 1, 1) else r.icon:SetVertexColor(0.3, 0.3, 0.3) end
            r:Show()
        else
            r:Hide()
        end
    end
    local empty = ""
    if role and #all == 0 then empty = "Nothing on this list yet: drop an item here."
    elseif role and #entries == 0 then empty = "Nothing on this list matches the search." end
    panel.empty:SetText(empty)
    local more = maxOff > 0 and ("  (%d-%d, scroll for more)"):format(panel.offset + 1, math.min(panel.offset + ROWS, #entries)) or ""
    local count = #entries == #all and ("%d on the list"):format(#all) or ("%d of %d match"):format(#entries, #all)
    panel.count:SetText(role and (count .. more) or "")
end
mod.MailFrames = function() return panel, tab end
mod.MailRender = function() if Render then Render() end end

-- the panel beside the bag frame, on the side with room (in screen pixels: the bag
-- frame has its own scale); kept on screen
-- which side the panel goes: left of the bags when there's room; beside the team bags,
-- away from their member list (on their right, or left when the screen has no room)
local function RightSide(frame, bag)
    local list = bag == rawget(_G, "MMTTeamBagsWindow") and rawget(bag, "team") or nil
    if type(list) == "table" and list:IsShown() then return list.left and true or false end
    local left = bag:GetLeft()
    local roomLeft = left and left * bag:GetEffectiveScale() or 0
    return roomLeft < (frame:GetWidth() + 12) * frame:GetEffectiveScale()
end

local function Place(frame, bag)
    frame:ClearAllPoints()
    if RightSide(frame, bag) then
        frame:SetPoint("TOPLEFT", bag, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("TOPRIGHT", bag, "TOPLEFT", -4, 0)
    end
    frame:SetFrameStrata(bag:GetFrameStrata())
    frame:SetFrameLevel(bag:GetFrameLevel() + 10)
end

-- the folded button: on top of the bag frame's top right corner, always on screen
local function PlaceTab(bag)
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMRIGHT", bag, "TOPRIGHT", 0, 2)
    tab:SetFrameStrata(bag:GetFrameStrata())
    tab:SetFrameLevel(bag:GetFrameLevel() + 10)
end

-- show / hide / move the panel with the bags (a 0.2 s check: a few IsVisible calls)
function mod.MailDock()
    local bag = mod.Active(F) and M.db.mlDock and mod.MailBagFrame() or nil
    if not bag then
        if panel then panel:Hide(); tab:Hide() end
        dockedTo = nil
        return
    end
    Build()
    local wasShown = panel:IsShown()
    local side = RightSide(panel, bag)
    if bag ~= dockedTo or side ~= panel.side then
        dockedTo, panel.side = bag, side
        Place(panel, bag)
        PlaceTab(bag)
    end
    panel:SetShown(M.db.mlOpen and true or false)
    tab:SetShown(not M.db.mlOpen)
    if panel:IsShown() and not wasShown then Status(""); Render() end
end

F = mod.Feature({
    key = "mlist", icon = "INV_Letter_15", slash = "roles", slashAlias = "mail", title = "Role items", tabText = "Role items",
    checkText = "Role items beside the bags",
    tip = "A small panel beside your bags (Baganator's or the game's) shows an MMT role's items - what whoever has the role gets in a trade, by \"Mail to team\" and from Loot Distribution - and adds items to it.",
    notes = {
        "Pick a role in the dropdown, then drop an item from your bags on the panel (or click its box and shift-click an item): it goes on that role's items. The x on a line takes it off.",
        "These are MMT's own roles (MMT settings > Roles shows the same). Trading with a team member hands over what their role wants, and at a mailbox MMT's \"Mail to team\" mails it to them - a role made just for that (e.g. \"Bank\" on your bank character) works well. Loot Distribution goes by the roles too: with the role's member away, Loot Distribution's \"Role members have no room\" decides (\"Next team member with room\" hands it out as usual).",
        "Changes made here go to the online team together, 5 seconds after your last one (the one at the mailbox needs the list), so adding many items is one message; a role a member doesn't have yet is made for them. Who has which role isn't sent. \"Send all role items\" gets everyone level once.",
        "MMT Team Inventory's team bags count as bags too: the panel sits beside them (beside the bags opened last when both are open), and an item dragged out of them onto the panel goes on the role.",
        "With the bags only a small \"Role items\" button shows, on top of them: it opens the panel (or /mmtqol roles with the bags open); \"-\" folds it again. It stays the way you left it: open or folded the next time the bags open.",
    },
    tags = { QML = OnSync },
    commands = {
        send = function()
            local roles, items = mod.MailSendAll()
            MMT.Print("Role items: sent %d item(s) of %d role(s) to the team.", items, roles)
        end,
        [""] = function()
            M.db.mlOpen = not M.db.mlOpen
            mod.MailDock()
            if not mod.MailBagFrame() then MMT.Print("Role items: open your bags - it sits beside them.") end
        end,
    },
    OnEnable = function()
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(0.2, function() pcall(mod.MailDock) end)
        end
    end,
    OnDisable = function()
        mod.MailFlush()
        if ticker then ticker:Cancel(); ticker = nil end
        if panel then panel:Hide(); tab:Hide() end
        dockedTo = nil
    end,
    Refresh = function() mod.MailDock(); if Render then Render() end end,
    Page = function(ui)
        ui.Check("Show it beside the bags", "mlDock", "The panel opens and closes with your bags (Baganator's backpack window, else the game's bags).")
        ui.Note("Roles and who has them: MMT settings > Roles. The \"Role items\" button on top of the bags (or /mmtqol roles) opens the panel.")
        ui.Check("Share changes with the team", "mlSync", "An item added to or taken off a role here goes on or off the same role on every online team member - all your changes together, 5 seconds after the last one (the one at the mailbox needs it). MMT's own Roles page doesn't send its changes - use \"Send all role items\" or MMT's profile sync for those.")
        ui.Check("Chat line for the team's changes", "mlChat", "Says what a team member added or took off.")
        ui.Button("Send all role items to the team", function() F.commands.send() end, "Every role's items to the online team: they add what they don't have yet (nothing is taken off). Also /mmtqol roles send.")
    end,
    Report = function(add)
        local bag = mod.MailBagFrame()
        local role = mod.MailRole()
        local function Where(f)
            if not f then return "not built" end
            return ("%s at %s,%s"):format(tostring(f:IsShown()), tostring(f.GetLeft and f:GetLeft()), tostring(f.GetTop and f:GetTop()))
        end
        add(("Role items: dock=%s open=%s role=%s entries=%d bag=%s (left %s) baganatorFrames=%d panel=%s tab=%s"):format(
            tostring(M.db.mlDock), tostring(M.db.mlOpen), tostring(role), #mod.MailEntries(role),
            bag and (bag.GetName and bag:GetName() or "?") or "none", tostring(bag and bag:GetLeft()),
            bagNames and #bagNames or -1, Where(panel), Where(tab)))
        add(("  sync=%s sent=%d got=%d added=%d removed=%d waiting=%d batches=%d lastBatch=%s"):format(tostring(M.db.mlSync), ml.sent, ml.got,
            ml.added, ml.removed, ml.queued, ml.flushes or 0, tostring(ml.lastFlush or "-")))
    end,
})

M:Listen("ROLES_CHANGED", function() mod.MailRender() end)
-- logging out / a loading screen within the 5 seconds: send what waits now
M:On("PLAYER_LEAVING_WORLD", function() mod.MailFlush() end)
M:Listen("TEAM_CHANGED", function() mod.MailRender() end)
M:Listen("PROFILE_CHANGED", function() mod.MailRender() end)
local itemQueued = false
M:On("GET_ITEM_INFO_RECEIVED", function()
    if itemQueued or not (panel and panel:IsShown()) then return end
    itemQueued = true
    C_Timer.After(0.3, function() itemQueued = false; mod.MailRender() end)
end)
