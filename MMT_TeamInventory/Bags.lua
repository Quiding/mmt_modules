-- MMT Team Inventory: "Team bags" - a bag window for any character's stored
-- items, like Baganator shows other characters. One slot per item (with the
-- character's total of it), not their real bag layout: only counts are synced.
-- Pick a character (or the whole team), Bags / Bank / Mail, search by name.
-- Grouped like Baganator's default categories (Classic order), or one grid.
-- Opened from the minimap button (left: bags, right: bank) or /mmtinv bags|bank.
-- By character, Bags tab: drag an item onto another character to plan a gift
-- (Give.lua); it shows glowing at the receiver until it was traded.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local COLS, SIZE, GAP, PAD, TOP = 10, 36, 4, 10, 66
-- the item area grows with the items; it scrolls only when the window would
-- not fit on the screen any more
local function MaxHeight(f)
    local screen = (tonumber(UIParent:GetHeight()) or 768) / math.max(0.1, tonumber(f:GetScale()) or 1)
    return math.max(4 * (36 + 4), screen - TOP - 80)
end
local ALL = "__ALL__"          -- whole team, added up
local BYCHAR = "__BYCHAR__"    -- whole team, one section per character
local TABS = { { "b", "Bags" }, { "k", "Bank" }, { "m", "Mail" }, { "e", "Equipped" } }

local HEADER_H = 18
-- the side panel: the team (drop targets) and the trades to do
local TEAM_W, TEAM_ROW = 200, 22
local TRADE_W, CANCEL_W, MINI = 50, 16, 20   -- Trade button, "x", item icons of a trade
local MINI_COLS = math.floor((TEAM_W - 16 + 2) / (MINI + 2))

-- Baganator's default categories, in its Classic order: { id, name, test(slot) }
-- (classID / subclassID from GetItemInfoInstant, known before the item's name)
local HEARTHSTONE = { [6948] = true }
mod.CATEGORIES = {
    { "hearth", "Hearthstone", function(s) return HEARTHSTONE[s.id] end },
    { "consumable", "Consumables", function(s) return s.class == 0 end },
    { "quest", "Quest items", function(s) return s.class == 12 end },
    { "weapon", "Weapons", function(s) return s.class == 2 end },
    { "armor", "Armor", function(s) return s.class == 4 end },
    { "reagent", "Reagents", function(s) return s.class == 5 end },
    { "tradegoods", "Trade goods", function(s) return s.class == 7 end },
    { "recipe", "Recipes", function(s) return s.class == 9 end },
    { "gem", "Gems", function(s) return s.class == 3 end },
    { "projectile", "Projectiles", function(s) return s.class == 6 end },
    { "container", "Containers", function(s) return s.class == 1 end },
    { "quiver", "Quivers", function(s) return s.class == 11 end },
    { "key", "Keys", function(s) return s.class == 13 end },
    { "misc", "Miscellaneous", function(s) return s.class == 15 end },
    { "other", "Other", function() return true end },
}
local JUNK = { "junk", "Junk" }   -- grey items, last (checked first)

function mod.CategoryOf(s)
    if s.quality == 0 then return JUNK[1], JUNK[2] end
    for _, c in ipairs(mod.CATEGORIES) do
        if c[3](s) then return c[1], c[2] end
    end
end

-- slots -> { { id, name, slots }, ... } in category order, empty ones left out
function mod.Group(slots)
    local by, order = {}, {}
    for _, c in ipairs(mod.CATEGORIES) do order[#order + 1] = c[1]; by[c[1]] = { id = c[1], name = c[2], slots = {} } end
    order[#order + 1] = JUNK[1]; by[JUNK[1]] = { id = JUNK[1], name = JUNK[2], slots = {} }
    for _, s in ipairs(slots) do
        local id = mod.CategoryOf(s)
        table.insert(by[id].slots, s)
    end
    local out = {}
    for _, id in ipairs(order) do if #by[id].slots > 0 then out[#out + 1] = by[id] end end
    return out
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local QualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local function InsertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- characters for the picker: this team first (team order), then the rest
function mod.BagOwners()
    local list, seen = {}, {}
    local chars = mod.Chars()
    local own = MMT.PlayerFull()
    if own and chars[own] then list[1] = own; seen[own] = true end
    for _, key in ipairs(MMT.SortedMembers()) do
        if chars[key] and not seen[key] then list[#list + 1] = key; seen[key] = true end
    end
    local rest = {}
    for key in pairs(chars) do if not seen[key] then rest[#rest + 1] = key end end
    table.sort(rest)
    for _, key in ipairs(rest) do list[#list + 1] = key end
    return list
end

-- { [itemID] = count } of one place for a character, or summed over everyone
local function Contents(who, place)
    if who ~= ALL and who ~= BYCHAR then
        local rec = mod.Chars()[who]
        return rec and rec[place] or {}
    end
    local sum = {}
    for _, rec in pairs(mod.Chars()) do
        for id, n in pairs(rec[place] or {}) do sum[id] = (sum[id] or 0) + n end
    end
    return sum
end

local function NewSlotData(id, n, search)
    local name, link, quality, _, _, _, _, _, _, icon = MMT.Safe(GetInfo, id)
    if search ~= "" and not (name and name:lower():find(search, 1, true)) then return nil end
    local _, _, _, _, instIcon, class, subclass = MMT.Safe(GetInstant, id)
    return { id = id, count = n, name = name, link = link, quality = quality,
        icon = icon or instIcon or MMT.Safe(GetIcon, id) or 134400, class = class, subclass = subclass }
end

-- sorted slots { id, count, name, link, quality, icon } matching the search.
-- One character's bags: planned gifts (Give.lua) leave the giver and show at
-- the receiver as their own slots { planned = giver }.
function mod.BagSlots(who, place, search)
    search = (search or ""):lower()
    local char = who ~= ALL and who ~= BYCHAR
    local plans = char and place == "b" and mod.PlannedOut
    local slots = {}
    for id, n in pairs(Contents(who, place)) do
        if plans then n = n - math.min(n, mod.PlannedOut(who, id)) end
        local s = n > 0 and NewSlotData(id, n, search)
        -- the whole team added up: no owner (a drop asks / finds who has it)
        if s then s.owner = char and who or nil; slots[#slots + 1] = s end
    end
    if plans then
        for _, p in ipairs(mod.PlannedIn(who)) do
            local s = NewSlotData(p.id, p.n, search)
            if s then s.owner, s.planned = who, p.from; slots[#slots + 1] = s end
        end
        -- what leaves: still shown at the giver, dimmed, with the receiver's name
        for _, p in ipairs(mod.PlannedOutList(who)) do
            local s = NewSlotData(p.id, p.n, search)
            if s then s.owner, s.outgoing = who, p.to; slots[#slots + 1] = s end
        end
    end
    table.sort(slots, function(a, b)
        -- planned gifts first: coming in, then going out
        local ra, rb = a.planned and 0 or a.outgoing and 1 or 2, b.planned and 0 or b.outgoing and 1 or 2
        if ra ~= rb then return ra < rb end
        if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
        if (a.name or "") ~= (b.name or "") then return (a.name or "~") < (b.name or "~") end
        return a.id < b.id
    end)
    return slots
end

---------------------------------------------------------------------------
-- Planning gifts: drag an item (Bags tab, one character or by character) onto
-- a name in the team list beside the window, or onto another character's
-- section in "by character"
---------------------------------------------------------------------------
-- the character under the cursor: a name in the team list, else a section (f.bands)
local function KeyAtCursor(f)
    for _, b in ipairs(f.teamButtons or {}) do
        if b:IsShown() and b.key and b:IsMouseOver() == true then return b.key end
    end
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    x, y = x / s, y / s
    local left, right, top = f:GetLeft(), f:GetRight(), f:GetTop()
    if not (left and right and top) or x < left or x > right then return nil end
    local ly = y - top
    for _, band in ipairs(f.bands or {}) do
        if ly <= band.top and ly > band.bottom then return band.key end
    end
end

-- the icon that follows the cursor while dragging
local dragIcon
local function DragIcon()
    if dragIcon then return dragIcon end
    dragIcon = CreateFrame("Frame", nil, UIParent)
    dragIcon:SetSize(SIZE, SIZE)
    dragIcon:SetFrameStrata("TOOLTIP")
    dragIcon.tex = dragIcon:CreateTexture(nil, "ARTWORK")
    dragIcon.tex:SetAllPoints()
    dragIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragIcon:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
    dragIcon:Hide()
    return dragIcon
end

-- Shift + drop: how many (Enter = OK, Esc = cancel)
local amountBox
local function AskAmount(s, to)
    if not amountBox then
        local f = CreateFrame("Frame", "MMTTeamBagsAmount", UIParent)
        f:SetSize(220, 64)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.97)
        UI.Border(f, 0.35, 0.35, 0.35, 1)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("TOPLEFT", 8, -8)
        f.text:SetPoint("TOPRIGHT", -8, -8)
        f.text:SetJustifyH("LEFT")
        f.box = UI.EditBox(f, 80, "", function(text) f.accept(text) end)
        f.box:SetPoint("BOTTOMLEFT", 8, 8)
        f.ok = UI.Button(f, 60, "OK", function() f.accept(f.box:GetText()) end)
        f.ok:SetPoint("LEFT", f.box, "RIGHT", 6, 0)
        f.box:HookScript("OnEscapePressed", function() f:Hide() end)
        f:Hide()
        amountBox = f
    end
    local f = amountBox
    f.text:SetText(("Give how many %s to %s? (up to %d)"):format(s.name or ("item " .. s.id), MMT.FullDisplay(to), s.count))
    f.box:SetText(tostring(s.count))
    f.accept = function(text)
        local n = math.min(s.count, math.floor(tonumber(text) or 0))
        f:Hide()
        if n > 0 then
            local cur = (((mod.Gives()[s.owner] or {})[to] or {})[s.id] or {}).n or 0
            mod.SetGive(s.owner, to, s.id, cur + n)
        end
    end
    f:ClearAllPoints()
    local x, y = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / sc + 8, y / sc + 8)
    f:Show()
    f.box:SetFocus()
end

-- a drop: plan the whole stack (Shift: ask how many)
-- who could give an item to a character: { { key, n }, ... } (bags, minus what they already give away)
function mod.Holders(id, to)
    local list = {}
    for _, key in ipairs(mod.BagOwners()) do
        if key ~= to then
            local rec = mod.Chars()[key]
            local n = (rec and rec.b and rec.b[id] or 0) - mod.PlannedOut(key, id)
            if n > 0 then list[#list + 1] = { key = key, n = n } end
        end
    end
    return list
end

local Drop
-- a drop from "Whole team": the only character who has it, or ask which one
local function DropFromTeam(s, to)
    local holders = mod.Holders(s.id, to)
    if #holders == 0 then return end
    local function From(h)
        local one = {}
        for k, v in pairs(s) do one[k] = v end
        one.owner, one.count = h.key, h.n
        Drop(one, to)
    end
    if #holders == 1 then return From(holders[1]) end
    local items = { { header = true, text = ("|cffffd100Who gives it to %s?|r"):format(MMT.FirstName(to)) } }
    for _, h in ipairs(holders) do items[#items + 1] = { value = h.key, text = ("%s  |cff888888(%d)|r"):format(MMT.FullDisplay(h.key), h.n) } end
    local anchor = mod.bags and mod.bags.team or UIParent
    UI.OpenList(anchor, items, nil, function(key)
        for _, h in ipairs(holders) do if h.key == key then From(h) end end
    end)
end

function Drop(s, to)
    if not to then return end
    if not s.owner then return DropFromTeam(s, to) end
    if to == s.owner then return end
    if IsShiftKeyDown() and s.count > 1 then return AskAmount(s, to) end
    local cur = (((mod.Gives()[s.owner] or {})[to] or {})[s.id] or {}).n or 0
    mod.SetGive(s.owner, to, s.id, cur + s.count)
end
mod.DropSlot = Drop

local function CanDrag(s)
    local f = mod.bags
    return s and not s.planned and not s.outgoing and f and f.place == "b"
        and (f.who == BYCHAR or f.who == ALL or (s.owner and f.who == s.owner))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function NewSlot(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    -- glow of a planned gift (like the cooldown icons' glow)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(SIZE * 1.8, SIZE * 1.8)
    local pulse = b.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.3); fade:SetDuration(0.6)
    b.pulse = pulse
    b.glow:Hide()
    -- the other character of a planned gift (giver on a glowing one, receiver on a dimmed one)
    b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.tag:SetPoint("TOPLEFT", 1, -1)
    b.tag:SetPoint("TOPRIGHT", -1, -1)
    b.tag:SetJustifyH("LEFT")
    b.tag:SetWordWrap(false)
    MMT.ApplyFont(b.tag, nil, 9, "OUTLINE")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnEnter", function(self)
        local s = self.slot
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, s.link or ("item:" .. s.id))
        if s.planned or s.outgoing then
            local from, to = s.planned or s.owner, s.outgoing or s.owner
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Planned: %s gives %d to %s."):format(MMT.FullDisplay(from), s.count, MMT.FullDisplay(to)), 0.3, 1, 0.3, true)
            GameTooltip:AddLine(("%s trades %s: it goes into the trade window by itself. Right-click: cancel."):format(MMT.FirstName(from), MMT.FirstName(to)), 0.7, 0.7, 0.7, true)
        elseif CanDrag(s) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag onto a name in the team list (or another character's section) to plan a gift. Shift: how many.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        local s = self.slot
        if not s then return end
        if button == "RightButton" then
            if s.planned then mod.SetGive(s.planned, s.owner, s.id, 0)
            elseif s.outgoing then mod.SetGive(s.owner, s.outgoing, s.id, 0) end
        elseif IsShiftKeyDown() then
            pcall(InsertLink, s.link or ("item:" .. s.id))
        end
    end)
    b:SetScript("OnDragStart", function(self)
        if not CanDrag(self.slot) then return end
        local d = DragIcon()
        d.tex:SetTexture(self.slot.icon)
        d:Show()
        self.dragging = self.slot
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        local s = self.dragging
        self.dragging = nil
        if dragIcon then dragIcon:Hide() end
        if s and mod.bags then Drop(s, KeyAtCursor(mod.bags)) end
    end)
    return b
end

-- the categories in use: Baganator's (when on and readable), else the built-in ones
function mod.Categorize(slots)
    if M.db.baganatorCats ~= false and mod.BaganatorGroups then
        local g = mod.BaganatorGroups(slots)
        if g then return g, true end
    end
    return mod.Group(slots), false
end

-- slots in category order (quality / name order kept inside a category)
local function ByCategory(slots)
    local out = {}
    for _, g in ipairs((mod.Categorize(slots))) do
        for _, s in ipairs(g.slots) do out[#out + 1] = s end
    end
    return out
end

local OwnerText

-- a character's first name in their class colour
local function NameTag(key)
    local class = mod.ClassOf and mod.ClassOf(key)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local hex = c and ("%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) or "ffffff"
    return "|cff" .. hex .. MMT.FirstName(key) .. "|r"
end

-- "by character": { { name = class-coloured name, key, slots }, ... } in the picker's
-- order; planned gifts first (coming in, then going out)
function mod.ByCharacter(place, search)
    local out = {}
    for _, key in ipairs(mod.BagOwners()) do
        local slots = mod.BagSlots(key, place, search)
        if #slots > 0 then
            local planned, rest = {}, {}
            for _, s in ipairs(slots) do
                if s.planned or s.outgoing then planned[#planned + 1] = s else rest[#rest + 1] = s end
            end
            for _, s in ipairs(ByCategory(rest)) do planned[#planned + 1] = s end
            out[#out + 1] = { name = OwnerText(key), key = key, slots = planned }
        end
    end
    return out
end

function OwnerText(who)
    if who == ALL then return "Whole team" end
    if who == BYCHAR then return "Whole team, by character" end
    local r, g, b = 1, 1, 1
    local class = mod.ClassOf and mod.ClassOf(who)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then r, g, b = c.r, c.g, c.b end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), MMT.FullDisplay(who))
end

local function Build()
    local f = CreateFrame("Frame", "MMTTeamBagsWindow", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        M.db.bagsPoint = { p, rp, x, y }
    end)
    UI.Fill(f, 0.05, 0.05, 0.06, 0.95)
    UI.Border(f, 0.25, 0.25, 0.25, 1)
    UI.CloseOnEscape(f)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, (self.offset or 0) - delta)
        mod.RefreshBags()
    end)

    f.owner = UI.Button(f, 200, "", function(self)
        local items = { { value = ALL, text = "|cffffd100Whole team|r" },
                        { value = BYCHAR, text = "|cffffd100Whole team, by character|r" } }
        for _, key in ipairs(mod.BagOwners()) do items[#items + 1] = { value = key, text = OwnerText(key) } end
        UI.OpenList(self, items, f.who, function(v)
            f.who, f.offset = v, 0
            M.db.lastWho = v   -- for "Open on: last viewed"
            mod.RefreshBags()
        end)
    end)
    f.owner:SetPoint("TOPLEFT", PAD, -PAD)
    UI.Tooltip(f.owner, "Character", "Whose items to show. Whole team: everyone's added up.")

    local close = UI.TextButton(f, "x", function() f:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)

    -- cog: the Team Inventory settings (own flat white gear, coloured like the "x")
    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(16, 16)
    cog:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local tex = cog:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\MMT_TeamInventory\\Media\\Cog.png")
    tex:SetVertexColor(0.6, 0.6, 0.6)
    cog:SetScript("OnEnter", function(self)
        tex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Settings")
        GameTooltip:AddLine("Team Inventory settings (/mmt).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() tex:SetVertexColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
    cog:SetScript("OnClick", function() MMT.ToggleConfig("TeamInventory") end)
    f.cog = cog

    f.tabs = {}
    local prev
    for _, t in ipairs(TABS) do
        local b = UI.Button(f, 68, t[2], function() f.place, f.offset = t[1], 0; mod.RefreshBags() end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", PAD, -PAD - 28) end
        f.tabs[t[1]] = b
        prev = b
    end

    -- on the top row, between the character and the close button (clear of the tabs)
    f.search = UI.EditBox(f, 140, "Search", function(_, box) box:ClearFocus() end)
    f.search:SetPoint("TOPRIGHT", -54, -PAD)
    f.search:HookScript("OnTextChanged", function() f.offset = 0; mod.RefreshBags() end)

    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.info:SetPoint("BOTTOMLEFT", PAD, 8)
    f.info:SetPoint("BOTTOMRIGHT", -PAD, 8)
    f.info:SetJustifyH("LEFT")

    f.slots, f.headers = {}, {}

    -- the side panel, in every view: the team (click = their bags, drop an
    -- item on a name = a planned gift) and the trades to do
    f.team = CreateFrame("Frame", nil, f)
    f.team:SetWidth(TEAM_W)
    UI.Fill(f.team, 0.05, 0.05, 0.06, 0.95)
    UI.Border(f.team, 0.25, 0.25, 0.25, 1)
    f.team:EnableMouse(true)
    f.team.title = f.team:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.team.title:SetPoint("TOPLEFT", 8, -8)
    f.team.title:SetText("Team")
    f.team.tradesTitle = f.team:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.team.tradesTitle:SetText("Trades")
    f.team.empty = f.team:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.team.empty:SetJustifyH("LEFT")
    f.team.empty:SetWidth(TEAM_W - 16)
    f.team.empty:SetText("Drag an item onto a name above to give it.")
    f.teamButtons, f.pairRows = {}, {}
    -- keep the panel on screen while the window is dragged
    f:HookScript("OnDragStart", function(self) self.isMoving = true end)
    f:HookScript("OnDragStop", function(self) self.isMoving = false; mod.PlaceTeam(self) end)
    f:HookScript("OnUpdate", function(self)
        if self.isMoving then mod.PlaceTeam(self) end
    end)
    f.who, f.place, f.offset = false, false, 0   -- set by OpenBags
    f:Hide()   -- new frames start shown: hidden until placed
    return f
end

-- the side panel: right of the window, or left of it when the screen ends there
function mod.PlaceTeam(f)
    if not f.team then return end
    local right, es = tonumber(f:GetRight()), tonumber(f:GetEffectiveScale())
    local screen, ues = tonumber(UIParent:GetRight()), tonumber(UIParent:GetEffectiveScale())
    local left = (right and es and screen and ues and (right + TEAM_W + 2) * es > screen * ues) or false
    if left == f.team.left and f.team.placed then return end
    f.team.left, f.team.placed = left, true
    f.team:ClearAllPoints()
    if left then f.team:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
    else f.team:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, 0) end
end

local function MiniIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(MINI, MINI)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, -1)
    MMT.ApplyFont(b.count, nil, 9, "OUTLINE")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%s gives %d to %s. Right-click: cancel."):format(MMT.FirstName(self.from), self.n, MMT.FirstName(self.to)), 0.3, 1, 0.3, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then mod.SetGive(self.from, self.to, self.id, 0) end
    end)
    return b
end

-- one trade: "Giver > Receiver   [Trade] x", then its items as small icons
local function PairRow(f, i)
    local r = f.pairRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.team)
    r:SetWidth(TEAM_W - 12)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("TOPLEFT", 2, -4)
    r.label:SetWidth(TEAM_W - 12 - TRADE_W - CANCEL_W - 8)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.cancel = UI.TextButton(r, "x", function() mod.CancelGifts(r.from, r.to) end, CANCEL_W)
    r.cancel:SetPoint("TOPRIGHT", 0, 0)
    UI.Tooltip(r.cancel, "Cancel", "Cancels these planned gifts: the items go back to the giver.")
    r.trade = UI.Button(r, TRADE_W, "Trade", function() mod.RequestTrade(r.from, r.to) end)
    r.trade:SetHeight(TEAM_ROW - 4)
    r.trade:SetPoint("TOPRIGHT", -CANCEL_W - 2, 0)
    UI.Tooltip(r.trade, "Trade now", "The giver's client opens the trade with the receiver and puts the planned items in; with 'Accept trades of planned gifts' on, both accept by themselves. They need to be in a group, or see each other's nameplate.")
    r.icons = {}
    f.pairRows[i] = r
    return r
end

-- the side panel: the team (names) and the trades to do (one block per pair)
function mod.RefreshTeam(f)
    local keys = {}
    for _, key in ipairs(MMT.SortedMembers()) do keys[#keys + 1] = key end
    local own = MMT.PlayerFull()
    local listed = false
    for _, key in ipairs(keys) do if key == own then listed = true end end
    if own and not listed and mod.Chars()[own] then table.insert(keys, 1, own) end   -- not in the team yet
    local y = -24
    for i, key in ipairs(keys) do
        local b = f.teamButtons[i]
        if not b then
            b = UI.Button(f.team, TEAM_W - 12, "", function(self)
                f.who, f.offset = self.key, 0
                M.db.lastWho = self.key
                mod.RefreshBags()
            end)
            b:SetHeight(TEAM_ROW - 2)
            UI.Tooltip(b, "Team", "Click: this character's bags. Drop an item here: give it to them (Shift: how many).")
            f.teamButtons[i] = b
        end
        b.key = key
        local incoming = #mod.PlannedIn(key)
        b.label:SetText((f.who == key and "|cffffd100>|r " or "") .. NameTag(key)
            .. (incoming > 0 and ("  |cff33ff33+" .. incoming .. "|r") or ""))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6, y)
        b:Show()
        y = y - TEAM_ROW
    end
    for i = #keys + 1, #f.teamButtons do f.teamButtons[i]:Hide() end

    y = y - 8
    f.team.tradesTitle:ClearAllPoints()
    f.team.tradesTitle:SetPoint("TOPLEFT", 8, y)
    y = y - 16
    local trades = mod.GiftPairs()
    f.team.empty:SetShown(#trades == 0)
    if #trades == 0 then
        f.team.empty:ClearAllPoints()
        f.team.empty:SetPoint("TOPLEFT", 8, y)
        y = y - 28
    end
    for i, p in ipairs(trades) do
        local r = PairRow(f, i)
        r.from, r.to = p.from, p.to
        r.label:SetText(NameTag(p.from) .. " |cff888888>|r " .. NameTag(p.to))
        for j, it in ipairs(p.items) do
            local ic = r.icons[j] or MiniIcon(r)
            r.icons[j] = ic
            ic.from, ic.to, ic.id, ic.n = p.from, p.to, it.id, it.n
            local _, _, _, _, instIcon = MMT.Safe(GetInstant, it.id)
            ic.icon:SetTexture(MMT.Safe(GetIcon, it.id) or instIcon or 134400)
            ic.count:SetText(it.n > 1 and it.n or "")
            ic:ClearAllPoints()
            ic:SetPoint("TOPLEFT", 2 + ((j - 1) % MINI_COLS) * (MINI + 2), -TEAM_ROW - math.floor((j - 1) / MINI_COLS) * (MINI + 2))
            ic:Show()
        end
        for j = #p.items + 1, #r.icons do r.icons[j]:Hide() end
        local h = TEAM_ROW + math.ceil(#p.items / MINI_COLS) * (MINI + 2) + 6
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r:Show()
        y = y - h
    end
    for i = #trades + 1, #f.pairRows do f.pairRows[i]:Hide() end
    f.team:SetHeight(-y + 6)
    mod.PlaceTeam(f)
end

local function Place(f)
    f:ClearAllPoints()
    local p = M.db.bagsPoint
    if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0) end
end

function mod.RefreshBags()
    local f = mod.bags
    if not f or not f:IsShown() then return end
    local who, place = f.who, f.place
    f.owner.label:SetText(OwnerText(who))
    for p, b in pairs(f.tabs) do
        if p == place then b.label:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
        else b.label:SetTextColor(0.8, 0.8, 0.8) end
    end
    local slots = mod.BagSlots(who, place, f.search:GetText())
    -- lines: a header per category (when grouped), then its slots, COLS per row
    local lines = {}
    local groups
    if who == BYCHAR then groups = mod.ByCharacter(place, f.search:GetText())
    elseif M.db.categories ~= false then groups = mod.Categorize(slots)
    else groups = { { slots = slots } } end
    for _, g in ipairs(groups) do
        if g.name then lines[#lines + 1] = { header = g.name .. "  |cff888888" .. #g.slots .. "|r", key = g.key } end
        for i = 1, #g.slots, COLS do
            local row = {}
            for j = i, math.min(i + COLS - 1, #g.slots) do row[#row + 1] = g.slots[j] end
            lines[#lines + 1] = { row = row, key = g.key }
        end
    end
    if #lines == 0 then lines[1] = { row = {} } end
    local function H(line) return line.header and HEADER_H or (SIZE + GAP) end
    local MAX_H = MaxHeight(f)
    -- scrolled by line; the last page is a full one
    local maxOffset, rest = #lines, 0
    while maxOffset > 0 and rest + H(lines[maxOffset]) <= MAX_H do
        rest = rest + H(lines[maxOffset])
        maxOffset = maxOffset - 1
    end
    f.offset = math.min(f.offset or 0, maxOffset)
    local y, nSlot, nHead = -TOP, 0, 0
    -- drop zones: the y range of each character's section (by character)
    f.bands = {}
    for li = f.offset + 1, #lines do
        local line = lines[li]
        if -TOP - y + H(line) > MAX_H then break end
        if line.key then
            local last = f.bands[#f.bands]
            if last and last.key == line.key then last.bottom = y - H(line)
            else f.bands[#f.bands + 1] = { key = line.key, top = y, bottom = y - H(line) } end
        end
        if line.header then
            nHead = nHead + 1
            local h = f.headers[nHead] or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f.headers[nHead] = h
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", PAD, y - 3)
            h:SetWidth(COLS * (SIZE + GAP) - GAP)
            h:SetJustifyH("LEFT")
            h:SetWordWrap(false)
            h:SetText(line.header)
            h:Show()
            y = y - HEADER_H
        else
            for c = 1, COLS do
                local s = line.row[c]
                if s or #line.row == 0 then
                    nSlot = nSlot + 1
                    local b = f.slots[nSlot] or NewSlot(f)
                    f.slots[nSlot] = b
                    b.slot = s
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", PAD + (c - 1) * (SIZE + GAP), y)
                    local r, g, bl = 0.2, 0.2, 0.2
                    if s then
                        b.icon:SetTexture(s.icon)
                        b.icon:Show()
                        b.count:SetText(s.count > 1 and s.count or "")
                        if s.quality then
                            local qr, qg, qb = MMT.Safe(QualityColor, s.quality)
                            if qr and s.quality > 1 then r, g, bl = qr, qg, qb end
                        end
                    else
                        b.icon:Hide()
                        b.count:SetText("")
                    end
                    b.bg:SetColorTexture(r, g, bl, 1)
                    local other = s and (s.planned or s.outgoing)
                    b.tag:SetText(other and NameTag(other) or "")
                    b.icon:SetDesaturated(s and s.outgoing and true or false)
                    b.icon:SetAlpha(s and s.outgoing and 0.45 or 1)
                    if s and s.planned then
                        if not b.glow:IsShown() then b.glow:Show(); b.pulse:Play() end
                    elseif b.glow:IsShown() then
                        b.pulse:Stop(); b.glow:Hide()
                    end
                    b:Show()
                end
            end
            y = y - (SIZE + GAP)
        end
    end
    for i = nSlot + 1, #f.slots do f.slots[i]:Hide() end
    for i = nHead + 1, #f.headers do f.headers[i]:Hide() end
    f:SetSize(PAD * 2 + COLS * (SIZE + GAP) - GAP, -y + 26)

    local total = 0
    for _, s in ipairs(slots) do total = total + s.count end
    local note = ("%d different items, %d in all"):format(#slots, total)
    if maxOffset > 0 then note = note .. "  -  mouse wheel scrolls" end
    if who ~= ALL and place == "b" and maxOffset == 0 then note = note .. "  -  drag items onto a name to give" end
    local team = who == ALL or who == BYCHAR
    local rec = not team and mod.Chars()[who]
    if rec and rec.time then note = note .. "  -  updated " .. MMT.Ago(rec.time) end
    if (place == "k" or place == "m") and #slots == 0 and not team then
        note = place == "k" and "Nothing known: open the bank once on that character." or "Nothing known: open the mailbox once on that character."
    end
    f.info:SetText(note)
    mod.RefreshTeam(f)
end

-- whose items the window opens on ("Open on" setting)
function mod.StartWho()
    local open = M.db.openOn or "LAST"
    local own = MMT.PlayerFull()
    if open == "ALL" then return ALL end
    if open == "BYCHAR" then return BYCHAR end
    if open == "LAST" then
        local last = M.db.lastWho
        if last == ALL or last == BYCHAR or (last and mod.Chars()[last]) then return last end
    end
    return own or ALL
end

-- place = "b" bags | "k" bank | "m" mail | "e" equipped; a second call with the same view closes it
function mod.OpenBags(place, who)
    mod.bags = mod.bags or Build()
    local f = mod.bags
    place = place or "b"
    if f:IsShown() and f.place == place and (not who or who == f.who) then f:Hide() return end
    f.place = place
    -- already open (bags -> bank): stay on the same character
    f.who = who or (f:IsShown() and f.who) or mod.StartWho()
    f.offset = 0
    f:SetScale(tonumber(M.db.bagsScale) or 1)
    if not f:IsShown() or not f:GetPoint(1) then Place(f) end
    f:Show()
    f:Raise()
    mod.RefreshBags()
end

-- key bindings (Bindings.xml, Options > Keybindings > AddOns): toggle the window
BINDING_HEADER_MMTTEAMINV = "MMT - Team Inventory"
BINDING_NAME_MMTTEAMINV_BAGS = "Team bags"
BINDING_NAME_MMTTEAMINV_BANK = "Team bank"
BINDING_NAME_MMTTEAMINV_BYCHAR = "Team bags, by character"
function MMTTeamInventory_Toggle(place, who)
    if not M.enabled then MMT.Print("Team Inventory is switched off (/mmt modules).") return end
    mod.OpenBags(place, who)
end

-- item names arrive later than the counts: redraw once they do
local pending
M:On("GET_ITEM_INFO_RECEIVED", function()
    if pending or not (mod.bags and mod.bags:IsShown()) then return end
    pending = true
    C_Timer.After(0.3, function() pending = false; mod.RefreshBags() end)
end)

---------------------------------------------------------------------------
-- Minimap button: left-click bags, right-click bank, drag to move it
---------------------------------------------------------------------------
local function PlaceMinimap(b)
    local a = math.rad(tonumber(M.db.minimapAngle) or 200)
    local r = (Minimap:GetWidth() / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMinimap()
    local b = CreateFrame("Button", "MMTTeamBagsMinimapButton", Minimap)
    b:SetSize(28, 28)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then mod.OpenBags("k") else mod.OpenBags("b") end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            M.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceMinimap(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    UI.Tooltip(b, "Team Inventory", "Left-click: team bags. Right-click: team bank. Drag: move this button.")
    return b
end

function mod.SetupMinimap()
    if not Minimap then return end
    if not M.db.minimap then
        if mod.minimap then mod.minimap:Hide() end
        return
    end
    mod.minimap = mod.minimap or BuildMinimap()
    PlaceMinimap(mod.minimap)
    mod.minimap:Show()
end
