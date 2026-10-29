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
-- the look (settings > Look): icon size, columns, spacing come from M.db on every redraw;
-- the window never gets narrower than its top row of buttons
local MIN_W = PAD * 2 + 10 * (36 + 4) - 4
local function ReadLook()
    SIZE = math.max(20, math.min(64, tonumber(M.db.bagIconSize) or 36))
    COLS = math.max(4, math.min(24, tonumber(M.db.bagColumns) or 10))
    GAP = math.max(0, math.min(12, tonumber(M.db.bagSpacing) or 4))
end
local function GridW() return math.max(MIN_W, PAD * 2 + COLS * (SIZE + GAP) - GAP) - PAD * 2 end

-- background (plain colour, or a LibSharedMedia texture tinted by it) and a 1 px border
local skins = {}   -- [frame] = { bg = texture, edges = { 4 textures } }
local function SkinFrame(fr)
    local sk = skins[fr]
    if not sk then
        sk = { bg = fr:CreateTexture(nil, "BACKGROUND"), edges = {} }
        sk.bg:SetAllPoints()
        for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                               { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
            local t = fr:CreateTexture(nil, "BORDER")
            t:SetPoint(pts[1]); t:SetPoint(pts[2])
            if pts[3] then t:SetWidth(pts[3]) end
            if pts[4] then t:SetHeight(pts[4]) end
            sk.edges[i] = t
        end
        skins[fr] = sk
    end
    local c, a = M.db.bagBgColor or { r = 0.05, g = 0.05, b = 0.06 }, tonumber(M.db.bagBgAlpha) or 0.94
    local name = M.db.bagBgTexture
    local LSM = name and name ~= "FLAT" and LibStub and LibStub("LibSharedMedia-3.0", true)
    local file = LSM and LSM:Fetch("background", name, true)
    if file then
        sk.bg:SetTexture(file)
        sk.bg:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, a)
    else
        sk.bg:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, a)
    end
    local e = M.db.bagBorderColor or { r = 0.22, g = 0.22, b = 0.24 }
    for _, t in ipairs(sk.edges) do t:SetColorTexture(e.r or 0, e.g or 0, e.b or 0, 1) end
    return sk
end
mod.SkinFrame = SkinFrame

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
    -- characters outside the team (other profiles, old teams, other accounts): only with the
    -- setting on; this ruleset first, then the others by ruleset
    local rest, own = {}, mod.Ruleset() or ""
    for key in pairs(chars) do if not seen[key] and mod.Shown(key) then rest[#rest + 1] = key end end
    local function Order(key)
        local rs = mod.RulesetOf(key)
        return (not rs or rs == own) and "" or rs
    end
    table.sort(rest, function(a, b)
        local ra, rb = Order(a), Order(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
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
    for key, rec in pairs(mod.Chars()) do
        if mod.Shown(key) then
            for id, n in pairs(rec[place] or {}) do sum[id] = (sum[id] or 0) + n end
        end
    end
    return sum
end

local function NewSlotData(id, n, search)
    local name, link, quality, _, _, _, _, _, _, icon = mod.ItemInfo(id)
    if search ~= "" and not (name and name:lower():find(search, 1, true)) then return nil end
    local _, _, _, _, instIcon, class, subclass = MMT.Safe(GetInstant, id)
    return { id = id, count = n, name = name, link = link, quality = quality,
        icon = icon or instIcon or MMT.Safe(GetIcon, id) or 134400, class = class, subclass = subclass }
end

-- Filters (window panel / settings, M.db.bagFilters): per kind of item SHOW,
-- HIDE or ONLY (shown as "Include"), all at once. HIDE removes those; with one
-- or more kinds on Include an item must be at least one of them (the panel
-- says "Showing only: ..."). An item can be several kinds (a soulbound quest item).
--   BoE gear    weapons / armour, Bind on Equip, not bound yet
--   soulbound   Bind on Pickup / quest items, equipped bind-on-equip ones, and what
--               the owner's client counted as bound (s)
--   reagents    mod.IsReagent; quest items: Quest class or bind type 4; consumables: class 0
mod.FILTER_KINDS = {
    { key = "boe", text = "BoE gear" },
    { key = "bound", text = "Soulbound" },
    { key = "reagent", text = "Crafting reagents" },
    { key = "quest", text = "Quest items" },
    { key = "consumable", text = "Consumables" },
}
mod.FILTER_STATES = { SHOW = "Show", HIDE = "Hide", ONLY = "Include" }   -- ONLY: the saved name of Include
local NEXT_STATE = { SHOW = "HIDE", HIDE = "ONLY", ONLY = "SHOW" }

-- the filters, made from the single filter of 0.5.0 / 0.5.1 once
local OLD_FILTER = {
    NOBOE = { boe = "HIDE" }, NOBOUND = { bound = "HIDE" }, NOBOTH = { boe = "HIDE", bound = "HIDE" },
    BOE = { boe = "ONLY" }, BOUND = { bound = "ONLY" }, NOREAGENT = { reagent = "HIDE" }, REAGENT = { reagent = "ONLY" },
}
function mod.Filters()
    local t = M.db.bagFilters
    if type(t) ~= "table" then
        t = {}
        for k, v in pairs(OLD_FILTER[M.db.bagFilter or ""] or {}) do t[k] = v end
        M.db.bagFilters, M.db.bagFilter = t, nil
    end
    return t
end

function mod.FilterState(kind) return mod.Filters()[kind] or "SHOW" end
function mod.SetFilter(kind, state)
    mod.Filters()[kind] = (state == "HIDE" or state == "ONLY") and state or nil
    if mod.bags then mod.bags.offset = 0 end
    if mod.RefreshBags then mod.RefreshBags() end
end
function mod.CycleFilter(kind) mod.SetFilter(kind, NEXT_STATE[mod.FilterState(kind)]) end

-- how many filters are on (for the button)
function mod.FiltersOn()
    local n = 0
    for _, state in pairs(mod.Filters()) do if state ~= "SHOW" then n = n + 1 end end
    return n
end

-- the kinds on Include, by name ("BoE gear, Consumables"), or nil
function mod.IncludedText()
    local t = {}
    for _, k in ipairs(mod.FILTER_KINDS) do
        if mod.FilterState(k.key) == "ONLY" then t[#t + 1] = k.text end
    end
    return #t > 0 and table.concat(t, ", ") or nil
end

-- a crafting material: the game's "crafting reagent" flag, else the Trade Goods class (cloth, ore, herbs, ...)
function mod.IsReagent(id, class)
    local flag = select(17, mod.ItemInfo(id))
    return flag == true or class == 7
end

-- every kind an item is: { boe, bound, reagent, quest, consumable = true / false }
-- (who = a character key or the whole team, place = b / k / m / e)
function mod.ItemKinds(id, class, count, who, place)
    local bind = select(14, mod.ItemInfo(id))
    local bound = bind == 1 or bind == 4 or (place == "e" and bind == 2)
    if not bound and place == "b" then
        local n = 0
        if who ~= ALL and who ~= BYCHAR then
            local rec = mod.Chars()[who]
            n = rec and rec.s and rec.s[id] or 0
        else
            for key, rec in pairs(mod.Chars()) do if mod.Shown(key) then n = n + (rec.s and rec.s[id] or 0) end end
        end
        bound = n >= count
    end
    return {
        bound = bound,
        boe = not bound and bind == 2 and (class == 2 or class == 4),
        reagent = mod.IsReagent(id, class),
        quest = class == 12 or bind == 4,
        consumable = class == 0,
    }
end

local function Passes(is)
    local anyOnly, matchOnly = false, false
    for k, state in pairs(mod.Filters()) do
        if state == "HIDE" and is[k] then return false end
        if state == "ONLY" then
            anyOnly = true
            if is[k] then matchOnly = true end
        end
    end
    return not anyOnly or matchOnly
end

-- sorted slots { id, count, name, link, quality, icon } matching the search and the filter.
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
        if s and not Passes(mod.ItemKinds(id, s.class, n, who, place)) then s = nil end
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
    for _, b in ipairs((f.team and f.team:IsShown() and f.teamButtons) or {}) do
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
        UI.Fill(f, 0.07, 0.07, 0.08, 0.98)                          -- MMT's popups (lists, colours)
        UI.Border(f, UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.5)
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
-- who could give an item to a character: { { key, n }, ... } (tradeable ones in the bags)
function mod.Holders(id, to)
    local list = {}
    for _, key in ipairs(mod.BagOwners()) do
        if key ~= to and mod.SameRuleset(key, to) then   -- no trading across rulesets
            local n = mod.Tradeable(key, id)
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
    if to == s.owner or not mod.SameRuleset(s.owner, to) then return end
    -- only what can be traded (not soulbound, not promised to someone else)
    local n = mod.Tradeable(s.owner, s.id)
    if n <= 0 then return end
    if n ~= s.count then
        local one = {}
        for k, v in pairs(s) do one[k] = v end
        one.count = n
        s = one
    end
    if IsShiftKeyDown() and s.count > 1 then return AskAmount(s, to) end
    local cur = (((mod.Gives()[s.owner] or {})[to] or {})[s.id] or {}).n or 0
    mod.SetGive(s.owner, to, s.id, cur + s.count)
end
mod.DropSlot = Drop

local function CanDrag(s)
    local f = mod.bags
    if not (s and not s.planned and not s.outgoing and f and f.place == "b"
        and (f.who == BYCHAR or f.who == ALL or (s.owner and f.who == s.owner))) then return false end
    if s.owner then return mod.Tradeable(s.owner, s.id) > 0 end
    return #mod.Holders(s.id) > 0
end

-- why an item in the bags can't be given (nil = it can, or not a bags slot)
local function WhyNot(s)
    local f = mod.bags
    if not (s and f and f.place == "b") or s.planned or s.outgoing then return nil end
    if mod.NeverTradeable(s.id) then return "Soulbound (Bind on Pickup / quest item): can't be traded." end
    if s.owner then
        local rec = mod.Chars()[s.owner]
        local bound = rec and rec.s and rec.s[s.id] or 0
        if bound >= s.count then return "Soulbound: can't be traded." end
        if bound > 0 then return ("%d of these are soulbound: only %d can be given."):format(bound, s.count - bound) end
    elseif #mod.Holders(s.id) == 0 then
        return "Soulbound everywhere: can't be traded."
    end
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
    -- glow of a planned gift: the slot's border pulses gold, 1 px wider than the
    -- slot (over the quality colour, under the icon; green looked like an uncommon
    -- item's border, the action-button glow like a white box)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.glow:SetPoint("TOPLEFT", -1, 1)
    b.glow:SetPoint("BOTTOMRIGHT", 1, -1)
    b.glow:SetColorTexture(1, 0.8, 0.1, 1)
    local pulse = b.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.25); fade:SetDuration(0.7)
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
        else
            local why = WhyNot(s)
            if why then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(why, 1, 0.3, 0.3, true)
            end
            if CanDrag(s) then
                if not why then GameTooltip:AddLine(" ") end
                GameTooltip:AddLine("Drag onto a name in the team list (or another character's section) to plan a gift. Shift: how many.", 0.7, 0.7, 0.7, true)
            end
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
        d:SetSize(SIZE, SIZE)
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

-- a small refresh icon (grey like the cog): our own items and gold read again, everyone online asked for theirs
function mod.RefreshButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    tex:SetDesaturated(true)
    tex:SetVertexColor(0.7, 0.7, 0.7)
    b.tex = tex
    b:SetScript("OnEnter", function(self)
        tex:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh")
        GameTooltip:AddLine("Asks everyone in the team who is online for their items and gold now. Gold also updates by itself a few seconds after it changes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() tex:SetVertexColor(0.7, 0.7, 0.7); GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        if mod.RefreshAll() then MMT.Print("Team Inventory: asked the team for their items and gold.") end
    end)
    return b
end

-- " (PvP)" after a character of another ruleset than this one
local function RulesetTag(key)
    local rs, own = mod.RulesetOf(key), mod.Ruleset()
    if not rs or not own or rs == own then return "" end
    return " |cff888888(" .. mod.RulesetName(rs) .. ")|r"
end

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
            local gold = mod.Gold(key)
            out[#out + 1] = { name = OwnerText(key) .. (gold and ("  " .. mod.FormatGold(gold)) or ""), key = key, slots = planned }
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
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), MMT.FullDisplay(who)) .. RulesetTag(who)
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
        local l, t = mod.PinTop(self)
        if l then M.db.bagsPoint = { "TOPLEFT", "BOTTOMLEFT", l, t } end
    end)
    SkinFrame(f)   -- defaults like MMT's settings window; settings > Look
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

    local close = UI.TextButton(f, "x", function() f:Hide() end, 20)
    close:SetPoint("TOPRIGHT", -8, -8)

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
    f.refresh = mod.RefreshButton(f)
    f.refresh:SetPoint("RIGHT", cog, "LEFT", -4, 0)

    f.tabs = {}
    local prev
    for _, t in ipairs(TABS) do
        local b = UI.Button(f, 68, t[2], function() f.place, f.offset = t[1], 0; mod.RefreshBags() end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", PAD, -PAD - 28) end
        f.tabs[t[1]] = b
        prev = b
    end

    -- on the top row, between the character and the close button (clear of the tabs)
    -- filter: BoE gear / soulbound (same as the setting)
    f.filter = UI.Button(f, 106, "Filter", function()
        if f.filters:IsShown() then f.filters:Hide() else f.filters:Show() end
    end)
    f.filter:SetPoint("TOPRIGHT", -PAD, -PAD - 28)
    UI.Tooltip(f.filter, "Filter", "Show / hide / only: Bind on Equip weapons and armour, soulbound items (Bind on Pickup, quest items, and what each character's client reports as bound), crafting reagents (cloth, ore, herbs, leather, ...). They all apply at once.")
    -- the filters: one row per kind, click = Show -> Hide -> Include, right-click = Show;
    -- stays open; a line at the bottom says what Include leaves
    f.filters = CreateFrame("Frame", nil, f)
    f.filters:SetPoint("TOPRIGHT", f.filter, "BOTTOMRIGHT", 0, -2)
    f.filters:SetSize(206, 8 + #mod.FILTER_KINDS * 24 + 4)
    f.filters.only = f.filters:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.filters.only:SetPoint("TOPLEFT", 8, -8 - #mod.FILTER_KINDS * 24)
    f.filters.only:SetWidth(190)
    f.filters.only:SetJustifyH("LEFT")
    f.filters:SetFrameStrata("FULLSCREEN_DIALOG")
    f.filters:EnableMouse(true)
    UI.Fill(f.filters, 0.07, 0.07, 0.08, 0.98)
    UI.Border(f.filters, UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.5)
    f.filterRows = {}
    for i, k in ipairs(mod.FILTER_KINDS) do
        local b = UI.Button(f.filters, 194, "", function(_, button)
            if button == "RightButton" then mod.SetFilter(k.key, "SHOW") else mod.CycleFilter(k.key) end
        end)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 24)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        UI.Tooltip(b, k.text, "Click: Show -> Hide -> Include. Right-click: Show. Include: only the included kinds are shown (any of them); Hide always removes.")
        b.kind = k
        f.filterRows[i] = b
    end
    f.filters:Hide()

    f.search = UI.EditBox(f, 140, "Search", function(_, box) box:ClearFocus() end)
    f.search:SetPoint("TOPRIGHT", -72, -PAD)
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
    SkinFrame(f.team)
    f.team:EnableMouse(true)
    -- section titles like MMT's settings: gold text, a thin line under it
    local function Title(text)
        local fs = f.team:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetText(text)
        fs.line = f.team:CreateTexture(nil, "ARTWORK")
        fs.line:SetColorTexture(1, 1, 1, 0.08)
        fs.line:SetHeight(1)
        fs.line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
        fs.line:SetWidth(TEAM_W - 16)
        return fs
    end
    f.team.title = Title("Team")
    f.team.title:SetPoint("TOPLEFT", 8, -8)
    f.team.refresh = mod.RefreshButton(f.team)
    f.team.refresh:SetPoint("TOPRIGHT", -8, -7)
    f.team.tradesTitle = Title("Trades")
    f.team.empty = f.team:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.team.empty:SetJustifyH("LEFT")
    f.team.empty:SetWidth(TEAM_W - 16)
    f.team.empty:SetText("Drag an item onto a name above to give it.")
    f.teamButtons, f.pairRows = {}, {}
    f.team.totalLabel = UI.Label(f.team, "Total gold", "GameFontNormalSmall")
    f.team.total = UI.Label(f.team, "", "GameFontHighlightSmall")
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
    -- switched off in the settings: no panel (drops still work on a character's section, by character)
    if M.db.sidePanel == false then f.team:Hide() return end
    f.team:Show()
    local keys = {}
    for _, key in ipairs(MMT.SortedMembers()) do keys[#keys + 1] = key end
    local own = MMT.PlayerFull()
    local listed = false
    for _, key in ipairs(keys) do if key == own then listed = true end end
    if own and not listed and mod.Chars()[own] then table.insert(keys, 1, own) end   -- not in the team yet
    -- with "Characters" on all stored: the others after them
    if mod.CharsMode() ~= "TEAM" then
        local inList = {}
        for _, key in ipairs(keys) do inList[key] = true end
        for _, key in ipairs(mod.BagOwners()) do if not inList[key] then keys[#keys + 1] = key end end
    end
    local y = -30
    for i, key in ipairs(keys) do
        local b = f.teamButtons[i]
        if not b then
            -- a row like MMT's settings list: the one shown gets the blue bar
            b = CreateFrame("Button", nil, f.team)
            b:SetSize(TEAM_W - 12, TEAM_ROW - 2)
            b.bg = UI.Fill(b, 1, 1, 1, 0)
            b.bar = b:CreateTexture(nil, "ARTWORK")
            b.bar:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
            b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
            b.bar:SetWidth(2)
            b.label = UI.Label(b, "", "GameFontNormal")
            b.label:SetPoint("LEFT", 10, 0)
            b.count = UI.Label(b, "")
            b.count:SetPoint("RIGHT", -8, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
            b:SetScript("OnClick", function(self)
                f.who, f.offset = self.key, 0
                M.db.lastWho = self.key
                mod.RefreshBags()
            end)
            UI.Tooltip(b, "Team", "Click: this character's bags. Drop an item here: give it to them (Shift: how many).")
            f.teamButtons[i] = b
        end
        b.key = key
        local incoming = #mod.PlannedIn(key)
        local selected = f.who == key
        if selected then b.bar:Show() else b.bar:Hide() end
        b.bg:SetColorTexture(1, 1, 1, selected and 0.06 or 0)
        b.label:SetText(NameTag(key) .. RulesetTag(key) .. (incoming > 0 and ("  |cffffcc33+" .. incoming .. "|r") or ""))
        local gold = mod.Gold(key)
        b.count:SetText(gold and ("|cffcccccc" .. mod.FormatGold(gold) .. "|r") or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6, y)
        b:Show()
        y = y - TEAM_ROW
    end
    for i = #keys + 1, #f.teamButtons do f.teamButtons[i]:Hide() end
    -- everyone's gold added up (the characters listed above)
    local total = mod.TotalGold()
    f.team.total:ClearAllPoints()
    f.team.total:SetPoint("TOPRIGHT", -14, y - 2)
    f.team.totalLabel:ClearAllPoints()
    f.team.totalLabel:SetPoint("TOPLEFT", 16, y - 2)
    f.team.total:SetText(total and mod.FormatGold(total) or "?")
    y = y - 18

    y = y - 8
    f.team.tradesTitle:ClearAllPoints()
    f.team.tradesTitle:SetPoint("TOPLEFT", 8, y)
    y = y - 22
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

-- anchored by its top-left corner: the height follows the items (filters, search,
-- another character), so only the bottom edge moves - the buttons stay put
function mod.PinTop(f)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return nil end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    return l, t
end

local function Place(f)
    f:ClearAllPoints()
    local p = M.db.bagsPoint
    if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0) end
    f.pinned = false   -- pinned by the top once it has its size (OpenBags)
end

function mod.RefreshBags()
    local f = mod.bags
    if not f or not f:IsShown() then return end
    ReadLook()
    SkinFrame(f)
    SkinFrame(f.team)
    local countFont, countSize = M.db.bagFont, tonumber(M.db.bagCountSize) or 14
    local quality = M.db.bagQuality ~= false
    local who, place = f.who, f.place
    f.owner.label:SetText(OwnerText(who))
    local on = mod.FiltersOn()
    f.filter.label:SetText(on > 0 and ("|cffffd100Filter (" .. on .. ")|r") or "Filter")
    local COLOR = { SHOW = "|cff999999", HIDE = "|cffff6060", ONLY = "|cff40ff40" }
    for _, b in ipairs(f.filterRows) do
        local state = mod.FilterState(b.kind.key)
        b.label:SetText(("%s:  %s%s|r"):format(b.kind.text, COLOR[state], mod.FILTER_STATES[state]))
    end
    local only = mod.IncludedText()
    f.filters.only:SetText(only and ("|cff40ff40Showing only:|r " .. only) or "")
    f.filters:SetHeight(8 + #mod.FILTER_KINDS * 24 + 4 + (only and ((tonumber(f.filters.only:GetStringHeight()) or 12) + 6) or 0))
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
            local h = f.headers[nHead]
            if not h then
                h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                -- a thin line under it, like the section titles in MMT's settings
                h.line = f:CreateTexture(nil, "ARTWORK")
                h.line:SetColorTexture(1, 1, 1, 0.08)
                h.line:SetHeight(1)
                h.line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
                h.line:SetWidth(GridW())
                f.headers[nHead] = h
            end
            h.line:Show()
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", PAD, y - 3)
            h:SetWidth(GridW())
            h.line:SetWidth(GridW())
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
                    b:SetSize(SIZE, SIZE)
                    MMT.ApplyFont(b.count, countFont ~= "" and countFont or nil, countSize, "OUTLINE")
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", PAD + (c - 1) * (SIZE + GAP), y)
                    local r, g, bl = 0.2, 0.2, 0.2
                    if s then
                        b.icon:SetTexture(s.icon)
                        b.icon:Show()
                        b.count:SetText(s.count > 1 and s.count or "")
                        if s.quality then
                            local qr, qg, qb = MMT.Safe(QualityColor, s.quality)
                            if qr and s.quality > 1 and quality then r, g, bl = qr, qg, qb end
                        end
                    else
                        b.icon:Hide()
                        b.count:SetText("")
                    end
                    -- a gift going out: dimmed, the quality colour too (it shone through the faded icon)
                    if s and s.outgoing then r, g, bl = r * 0.35, g * 0.35, bl * 0.35 end
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
    for i = nHead + 1, #f.headers do f.headers[i]:Hide(); f.headers[i].line:Hide() end
    f:SetSize(GridW() + PAD * 2, -y + 26)

    local total = 0
    for _, s in ipairs(slots) do total = total + s.count end
    local note = ("%d different items, %d in all"):format(#slots, total)
    if maxOffset > 0 then note = note .. "  -  mouse wheel scrolls" end
    local team = who == ALL or who == BYCHAR
    local gold = team and mod.TotalGold() or (not team and mod.Gold(who))
    if gold then note = note .. "  -  " .. mod.FormatGold(gold) end
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
        if last == ALL or last == BYCHAR or (last and mod.Chars()[last] and mod.Shown(last)) then return last end
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
    -- an older saved point (or the default) is by the middle / right: pin it by the top now
    if not f.pinned then
        f.pinned = true
        local l, t = mod.PinTop(f)
        if l then M.db.bagsPoint = { "TOPLEFT", "BOTTOMLEFT", l, t } end
    end
end

-- key bindings (Bindings.xml, Options > Keybindings > AddOns): toggle the window
BINDING_HEADER_MMTTEAMINV = "MMT - Team Inventory"
BINDING_NAME_MMTTEAMINV_BAGS = "Team bags"
BINDING_NAME_MMTTEAMINV_BANK = "Team bank"
BINDING_NAME_MMTTEAMINV_BYCHAR = "Team bags, by character"
BINDING_NAME_MMTTEAMINV_ACCEPT = "Accept trade (planned gifts only)"
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
