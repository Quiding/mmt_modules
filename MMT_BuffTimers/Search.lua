-- Name search for the list editors (the same file in MMT_Cooldowns and
-- MMT_Buffs: KEEP BOTH IDENTICAL).
--
-- The game finds a spell by name only when your character knows it, so the
-- add box searches its own index: every spell name of the Classic, Season of
-- Discovery and WoW: Forever ID ranges, built in the background the first
-- time someone types (about a second, only while the game runs, nothing is
-- saved). Items: the ones in your bags and on your character.
--
--   mod.AttachSearch(box, { items = bool, onPick = fn(t, id, name) })
--       a popup under box with the matches while you type; t = "s" | "i"
--   mod.FindByName(text, items) -> t, id   exact name, once the index is built

local _, mod = ...
local MMT = MMT

local RANGES = { { 1, 60000 }, { 400000, 440000 }, { 1250000, 1330000 } }
local PER_STEP = 3000
local MAX_RESULTS = 12

local index        -- [lower-case name] = { name, id }
local names        -- lower-case names, for the substring search
local building, built, progress = false, false, 0
local waiting = {} -- popups to redraw when the index is done

local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (mod.SpellInfo(id)) end

-- a "Teaches <spell>" trainer spell (generic WoW-logo icon) or one without an icon
local function Generic(id)
    local icon = mod.SpellIcon(id)
    return icon == nil or icon == mod.GENERIC_ICON
end

-- the first spell with a name wins, except that a real spell beats a trainer spell of
-- the same name (864 "Seal of Righteousness" teaches it); the presets' IDs always win
local function AddSpell(id, preset)
    local ok, name = pcall(GetName, id)
    if not ok or type(name) ~= "string" or name == "" or MMT.IsSecret(name) then return end
    local key = name:lower()
    local have = index[key]
    if not have then
        index[key] = { name = name, id = id, preset = preset }
        names[#names + 1] = key
    elseif not have.preset and Generic(have.id) and not Generic(id) then
        have.id = id
    end
end

local function Build()
    if building or built then return end
    building = true
    index, names = {}, {}
    -- the presets' spells first: their IDs win for names that exist more than once
    for _, p in ipairs(mod.PRESETS or {}) do
        for _, e in ipairs(p.entries or {}) do
            if e.t ~= "i" and type(e.id) == "number" then AddSpell(e.id, true) end
        end
    end
    local r, id = 1, RANGES[1][1]
    local total, done = 0, 0
    for _, range in ipairs(RANGES) do total = total + range[2] - range[1] + 1 end
    -- the callback gets its own ticker: stop it from there
    C_Timer.NewTicker(0.01, function(ticker)
        if built then if ticker then ticker:Cancel() end return end
        local stop = id + PER_STEP
        while id < stop do
            if id > RANGES[r][2] then
                r = r + 1
                if not RANGES[r] then
                    if ticker then ticker:Cancel() end
                    building, built, progress = false, true, 1
                    for popup in pairs(waiting) do popup.Update() end
                    wipe(waiting)
                    return
                end
                id = RANGES[r][1]
            end
            AddSpell(id)
            id, done = id + 1, done + 1
        end
        progress = done / total
        for popup in pairs(waiting) do popup.Update() end
    end)
end

---------------------------------------------------------------------------
-- Items you carry or wear
---------------------------------------------------------------------------
local function OwnItems()
    local list, seen = {}, {}
    local function Add(itemID)
        if not itemID or seen[itemID] then return end
        seen[itemID] = true
        local fn = (C_Item and C_Item.GetItemNameByID) or function(i) return (GetItemInfo(i)) end
        local ok, name = pcall(fn, itemID)
        if ok and type(name) == "string" and name ~= "" then list[#list + 1] = { name = name, id = itemID } end
    end
    for slot = 1, 19 do Add(MMT.Safe(GetInventoryItemID, "player", slot)) end
    local C = C_Container
    for bag = 0, 4 do
        local n = C and C.GetContainerNumSlots and MMT.Safe(C.GetContainerNumSlots, bag) or 0
        for slot = 1, n do Add(MMT.Safe(C.GetContainerItemID, bag, slot)) end
    end
    return list
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
-- matches for text: starting with it first, then containing it, shorter first
function mod.Search(text, withItems)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    if #text < 2 then return out end
    local starts, contains = {}, {}
    local function Consider(t, name, id)
        local low = name:lower()
        local at = low:find(text, 1, true)
        if at == 1 then starts[#starts + 1] = { t = t, name = name, id = id }
        elseif at then contains[#contains + 1] = { t = t, name = name, id = id } end
    end
    if withItems then
        for _, it in ipairs(OwnItems()) do Consider("i", it.name, it.id) end
    end
    if built then
        for _, key in ipairs(names) do
            local e = index[key]
            Consider("s", e.name, e.id)
        end
    end
    local function ByLength(a, b)
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.name < b.name
    end
    table.sort(starts, ByLength)
    table.sort(contains, ByLength)
    for _, list in ipairs({ starts, contains }) do
        for _, e in ipairs(list) do
            if #out >= MAX_RESULTS then return out end
            out[#out + 1] = e
        end
    end
    return out
end

function mod.FindByName(text, withItems)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if withItems then
        for _, it in ipairs(OwnItems()) do
            if it.name:lower() == text then return "i", it.id end
        end
    end
    local e = built and index[text]
    if e then return "s", e.id end
    return nil
end

---------------------------------------------------------------------------
-- Popup
---------------------------------------------------------------------------
local ROW_H = 20

local function Icon(t, id)
    if t == "i" then
        local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        return fn and MMT.Safe(fn, id) or 134400
    end
    return mod.SpellIcon(id) or 134400
end

function mod.AttachSearch(box, opts)
    local UI = MMT.UI
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetClampedToScreen(true)
    UI.Fill(p, 0.07, 0.07, 0.08, 0.98)
    UI.Border(p, 0.3, 0.3, 0.3, 1)
    p:Hide()
    p.rows = {}
    local function Row(i)
        local r = p.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, p)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 4, ROW_H - 4)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            if not self.entry then return end
            local e = self.entry
            p:Hide()
            box.picked = { t = e.t, id = e.id, text = e.name }
            box:SetText(e.name)
            if box.UpdatePlaceholder then box:UpdatePlaceholder() end
            if opts.onPick then opts.onPick(e.t, e.id, e.name) end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = (self.entry.t == "i" and "item:" or "spell:") .. self.entry.id
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.rows[i] = r
        return r
    end

    function p.Update()
        local text = box:GetText() or ""
        if not box:HasFocus() or #text < 2 or (box.picked and box.picked.text == text) then p:Hide() return end
        if not built then Build(); waiting[p] = true end
        local results = mod.Search(text, opts.items)
        local lines = {}
        for _, e in ipairs(results) do lines[#lines + 1] = e end
        local note
        if not built then note = ("Looking through the spells... %d%%"):format(math.floor(progress * 100))
        elseif #lines == 0 then note = "Nothing found. A spell ID or shift-click works too." end
        local n = #lines + (note and 1 or 0)
        for i = 1, n do
            local r = Row(i)
            local e = lines[i]
            r.entry = e
            if e then
                r.icon:SetTexture(Icon(e.t, e.id))
                r.icon:Show()
                r.text:SetText(("%s  |cff888888%s %d|r"):format(e.name, e.t == "i" and "item" or "spell", e.id))
            else
                r.icon:Hide()
                r.text:SetText("|cff999999" .. note .. "|r")
            end
            r:Show()
        end
        for i = n + 1, #p.rows do p.rows[i]:Hide() end
        local own, parent = box:GetEffectiveScale(), UIParent:GetEffectiveScale()
        p:SetScale((own and parent and parent > 0) and own / parent or 1)
        p:SetSize(math.max(box:GetWidth() + 60, 240), n * ROW_H + 4)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
        p:Show()
    end

    box:HookScript("OnTextChanged", function(_, userInput)
        if userInput then box.picked = nil end
        p.Update()
    end)
    box:HookScript("OnEditFocusGained", function() p.Update() end)
    -- a click on a row takes the focus first: hide a moment later
    box:HookScript("OnEditFocusLost", function() C_Timer.After(0.3, function() if not box:HasFocus() then p:Hide() end end) end)
    box:HookScript("OnHide", function() p:Hide() end)
    return p
end
