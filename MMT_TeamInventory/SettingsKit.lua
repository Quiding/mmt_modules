-- Settings helpers shared by MMT_Cooldowns and MMT_Buffs (they ship the same
-- copy of this file: KEEP BOTH IDENTICAL):
--   mod.Tabs(page, { {id, text}, ... })  -> panels[id]   tab buttons like /mmt > Help
--   mod.ShareBar(page, status)             bottom bar on every tab: Import / Export,
--                                          Reset to defaults, the core's "Sync to team"
--   mod.ResetSettings()                    every setting of the module back to its default
--   mod.LookTab(panel, Opt, apply)         -> left column, for the module's own look options
--   mod.DragReorder(list, getData, moved)  drag the rows of a ConfigHelpers.List to reorder its data
--   mod.DragGrip(row)                      -> the dotted handle at a draggable row's left edge
--   mod.MoveTab(frame, opts)               -> the move tab above a movable window's top-left corner
-- Opt(key) returns getter, setter for M.db[key]; apply() redraws.

local _, mod = ...
local MMT = MMT

local current = {}   -- [page] = selected tab id (kept while the game runs)
local BOTTOM = 50    -- room below the tabs' panels: status line + share bar

function mod.Tabs(page, list)
    local UI = MMT.UI
    local W = MMT.ConfigHelpers.PAGE_W
    local panels, buttons = {}, {}
    local bw = math.floor((W - 8 * (#list - 1)) / #list)
    local function Show(id)
        current[mod] = id
        for k, p in pairs(panels) do p:SetShown(k == id) end
        for k, b in pairs(buttons) do
            if k == id then b.label:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            else b.label:SetTextColor(0.7, 0.7, 0.7) end
        end
    end
    for i, t in ipairs(list) do
        local b = UI.Button(page, bw, t[2], function() Show(t[1]) end)
        b:SetPoint("TOPLEFT", (i - 1) * (bw + 8), 0)
        buttons[t[1]] = b
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -30)
        p:SetSize(W, math.max(100, (page:GetHeight() or 560) - 30 - BOTTOM))
        panels[t[1]] = p
    end
    Show(current[mod] and panels[current[mod]] and current[mod] or list[1][1])
    return panels
end

-- the share bar at the bottom of the page, like the tab buttons at the top:
-- Import / Export in the bottom left; the core puts its "Sync to team"
-- button (sync = true in NewModule) in the bottom right after M.Page
function mod.ShareBar(page, status)
    local UI = MMT.UI
    local W = MMT.ConfigHelpers.PAGE_W
    local ie = UI.Button(page, 176, "Import / Export...", function() mod.OpenTransfer() end)
    ie:SetPoint("BOTTOMLEFT", 0, 2)
    UI.Tooltip(ie, "Import / Export", "Choose parts and copy them as a text string, or paste one to take it over.")
    local reset = MMT.ConfigHelpers.ConfirmButton(page, 150, "Reset to defaults", function()
        mod.ResetSettings()
        status.Show_("Every setting is back to its default.")
    end)
    reset:SetPoint("LEFT", ie, "RIGHT", 8, 0)
    UI.Tooltip(reset, "Reset to defaults", "Puts every setting of this module (all tabs, lists, window position) back to the default of a new profile. Click twice.")
    status:ClearAllPoints()
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(W)
    return ie
end

-- every setting back to the default (the same table, so the core's profile keeps it)
function mod.ResetSettings()
    local M = mod.M
    for k in pairs(M.db) do M.db[k] = nil end
    for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
    if M.OnProfileChanged then M.OnProfileChanged(M) end
    if MMT.RefreshConfig then MMT.RefreshConfig() end
    MMT.Print("%s: settings reset to defaults.", M.title)
end

-- shift-clicking a spell (spellbook, chat link) while box has focus puts the
-- link into it. This client sends links through ChatFrameUtil.InsertLink (the
-- old ChatEdit_InsertLink is only a fallback), so hook whichever exists, once.
local spellBoxes, spellHooked = {}, false
local function OnInsertLink(link)
    if type(link) ~= "string" or not link:find("|Hspell:", 1, true) then return end
    for box, onLink in pairs(spellBoxes) do
        if box:IsVisible() and box:HasFocus() then
            box:SetText(link)
            if box.UpdatePlaceholder then box:UpdatePlaceholder() end
            if onLink then onLink(link, box) end
            return
        end
    end
end
function mod.AcceptSpellLinks(box, onLink)
    spellBoxes[box] = onLink or false
    if spellHooked then return end
    spellHooked = true
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
end

-- preset picker for the list editor: a dropdown + Add to list / Replace list.
-- listKey() = the list being edited, id(e) tells entries apart, changed() redraws
function mod.PresetBox(col, parent, listKey, id, changed, status)
    local UI, H = MMT.UI, MMT.ConfigHelpers
    local COL_W = H.COL_W
    local chosen, chosenFor
    local function Current()
        if chosenFor ~= listKey() or not chosen then chosen, chosenFor = mod.DefaultPreset(listKey()), listKey() end
        return chosen
    end
    col:Header("Presets")
    col:Cycle("Preset", function() return mod.PresetChoices(listKey()) end, Current,
        function(v) chosen, chosenFor = v, listKey() end)
    local half = (COL_W - 8) / 2
    local add = UI.Button(parent, half, "Add to list", function()
        local p = mod.PresetByKey(Current())
        if not p then return end
        local n = mod.ApplyPreset(listKey(), p.key, false, id)
        status.Show_(n > 0 and ("Added %d entries from \"%s\"."):format(n, p.name) or "The list already has every entry of that preset.")
        changed()
    end)
    UI.Tooltip(add, "Add to list", "Adds the preset's entries this list doesn't have yet (on or off as in the preset). Your own entries stay.")
    col:Add(add, 0)
    local replace = H.ConfirmButton(parent, half, "Replace list", function()
        local p = mod.PresetByKey(Current())
        if not p then return end
        mod.ApplyPreset(listKey(), p.key, true, id)
        status.Show_(("The list is now \"%s\"."):format(p.name))
        changed()
    end)
    replace:SetPoint("LEFT", add, "RIGHT", 8, 0)
    col:Space(UI.ROW + 2)
end

-- texture choices from LibSharedMedia (brought by other addons), plus a plain one
function mod.MediaChoices(kind, plainValue, plainText)
    local t = { { value = plainValue, text = plainText } }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List(kind)) do
            if name ~= "None" then t[#t + 1] = { value = name, text = name } end
        end
    end
    return t
end

local function FontChoices()
    local t = { { value = "", text = "Game font" } }
    for _, f in ipairs(MMT.fonts or {}) do t[#t + 1] = { value = f.name, text = f.name } end
    return t
end

local function Color(col, text, M, key, apply)
    col:Color(text, function() return M.db[key] end, function(c)
        M.db[key] = { r = c.r, g = c.g, b = c.b }
        apply()
    end)
end

-- sizes, text, background, border, member rows; returns the left column
function mod.LookTab(panel, Opt, apply)
    local UI, H = MMT.UI, MMT.ConfigHelpers
    local M = mod.M
    local COL_W, COL2_X = H.COL_W, H.COL2_X

    local L = UI.Column(panel, 0, 0, COL_W)
    L:Header("Size")
    local gi, si = Opt("iconSize")
    L:Slider("Icon size", 16, 64, 1, gi, si)
    local gz, sz = Opt("iconZoom")
    L:Slider("Icon zoom", 0, 30, 1, function() return gz() or 8 end, sz, "%d%%")
    local gs, ss = Opt("scale")
    L:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gsp, ssp = Opt("spacing")
    L:Slider("Icon spacing", 0, 20, 1, gsp, ssp)
    local grg, srg = Opt("rowGap")
    L:Slider("Row spacing", 0, 30, 1, grg, srg)
    L:Header("Text")
    L:Cycle("Font", FontChoices, function() return M.db.font or "" end, function(v)
        M.db.font = (v ~= "") and v or nil
        apply()
    end)
    local gt, st = Opt("timerSize")
    L:Slider("Timer size", 8, 32, 1, gt, st)
    Color(L, "Timer colour", M, "timerColor", apply)
    local gn, sn = Opt("nameSize")
    L:Slider("Name size", 8, 20, 1, gn, sn)

    local R = UI.Column(panel, COL2_X, 0, COL_W)
    R:Header("Background")
    R:Cycle("Texture", function() return mod.MediaChoices("background", "FLAT", "Flat") end, Opt("bgTexture"))
    Color(R, "Colour", M, "bgColor", apply)
    local gti, sti = Opt("bgTint")
    R:Slider("Colour strength", 0, 1, 0.05, gti, sti, "%.2f")
    local gb, sb = Opt("bgAlpha")
    R:Slider("Opacity", 0, 1, 0.05, gb, sb, "%.2f")
    R:Header("Border")
    R:Cycle("Texture", function() return mod.MediaChoices("border", "NONE", "None") end, Opt("borderTexture"))
    Color(R, "Colour", M, "borderColor", apply)
    local gz, sz = Opt("borderSize")
    R:Slider("Size", 4, 32, 1, gz, sz)
    R:Header("Member rows")
    Color(R, "Row background", M, "rowColor", apply)
    local gr, sr = Opt("rowAlpha")
    R:Slider("Row opacity", 0, 1, 0.05, gr, sr, "%.2f")
    R:Note("Textures come from LibSharedMedia.")
    return L, R
end

-- The move tab (like MMT's XP window): a small tab above the top-left corner of a movable
-- window, shown while it can be moved and the mouse is over the window (or opts.always());
-- dragging it runs the window's own move code. opts = { locked = fn -> true when it can't
-- move, start = fn, stop = fn, always = fn (optional), tip = text (optional) }.
-- Load this file before the windows that use it.
function mod.MoveTab(frame, opts)
    local A = MMT.UI and type(MMT.UI.ACCENT) == "table" and MMT.UI.ACCENT or { 0.31, 0.70, 1.00 }
    local tab = CreateFrame("Frame", nil, frame)
    tab:SetSize(40, 12)
    tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
    tab:SetFrameLevel(frame:GetFrameLevel() + 10)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local line = tab:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(A[1], A[2], A[3], 0.8)
    for c = 0, 4 do
        for r = 0, 1 do
            local d = tab:CreateTexture(nil, "ARTWORK")
            d:SetSize(2, 2)
            d:SetPoint("CENTER", (c - 2) * 5, r == 0 and 2 or -2)
            d:SetColorTexture(1, 1, 1, 0.8)
        end
    end
    local moving = false
    tab:EnableMouse(true)
    tab:RegisterForDrag("LeftButton")
    tab:SetScript("OnDragStart", function()
        if opts.locked() then return end
        moving = true
        opts.start()
    end)
    tab:SetScript("OnDragStop", function()
        if not moving then return end
        moving = false
        opts.stop()
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to move")
        GameTooltip:AddLine(opts.tip or "Lock its position in its settings.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:Hide()
    -- shown or not, checked a few times a second while the window is shown
    local wait = 0
    frame:HookScript("OnUpdate", function(_, elapsed)
        wait = wait + elapsed
        if wait < 0.15 then return end
        wait = 0
        local want = moving or (not opts.locked() and ((opts.always and opts.always())
            or frame:IsMouseOver(14, 0, 0, 0) or tab:IsMouseOver()))
        tab:SetShown(want and true or false)
    end)
    return tab
end

-- Moves data[from] so it ends up before what is now data[slot] (slot = 1 .. #data + 1).
-- Returns its new index, or nil when nothing moves.
function mod.MoveEntry(data, from, slot)
    if not data[from] or slot == from or slot == from + 1 or slot < 1 or slot > #data + 1 then return end
    local e = table.remove(data, from)
    local to = (slot > from) and slot - 1 or slot
    table.insert(data, to, e)
    return to
end

-- The dotted handle (2 x 3 dots, 6 x 10 px) at the left edge of a draggable row: anchor the row's
-- content to its right. DragReorder lights it while the cursor is on the row.
local GRIP_DIM, GRIP_LIT = 0.35, 0.9
function mod.DragGrip(row)
    local g = CreateFrame("Frame", nil, row)
    g:SetSize(6, 10)
    g:SetPoint("LEFT", 3, 0)
    g.dots = {}
    for c = 0, 1 do
        for r = 0, 2 do
            local d = g:CreateTexture(nil, "ARTWORK")
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", c * 4, -r * 4)
            d:SetColorTexture(1, 1, 1, GRIP_DIM)
            g.dots[#g.dots + 1] = d
        end
    end
    row.grip = g
    return g
end

local function LightGrip(row, on)
    if not row.grip then return end
    for _, d in ipairs(row.grip.dots) do d:SetColorTexture(1, 1, 1, on and GRIP_LIT or GRIP_DIM) end
end

-- Drag to reorder the rows of an MMT.ConfigHelpers.List (fixed row pool + mouse-wheel offset).
-- Rows need row.index (their data index, set in fillRow). getData() -> the table to reorder;
-- moved(from, to) runs after an entry moved (redraw, ...). A line shows where it lands; holding
-- the cursor above / below the list scrolls it.
function mod.DragReorder(list, getData, moved)
    local UI = MMT.UI
    local rows = list.rows
    local rh = list:GetHeight() / #rows
    local marker = list:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
    marker:SetHeight(2)
    marker:Hide()
    local from, nextScroll
    -- where the cursor is: data slot it would land before, visible row gap, distance from the top
    local function Slot()
        local top = list:GetTop()
        local data = getData()
        if not top or not data then return end
        local _, y = GetCursorPosition()
        local dy = top - y / list:GetEffectiveScale()
        local gap = math.max(0, math.min(#rows, math.floor(dy / rh + 0.5)))
        local slot = math.max(1, math.min(#data + 1, list.offset + gap + 1))
        return slot, slot - list.offset - 1, dy
    end
    local function Dim()
        for _, row in ipairs(rows) do row:SetAlpha((from and row.index == from) and 0.4 or 1) end
    end
    local function Stop()
        list:SetScript("OnUpdate", nil)
        marker:Hide()
        from = nil
        Dim()
    end
    local function Update()
        local slot, gap, dy = Slot()
        if not slot then return end
        -- scroll while the cursor is past the top / bottom edge
        local now = GetTime()
        if (dy < 0 or dy > list:GetHeight()) and (not nextScroll or now >= nextScroll) then
            nextScroll = now + 0.15
            list:GetScript("OnMouseWheel")(list, dy < 0 and 1 or -1)
            Dim()
            slot, gap = Slot()
        end
        if slot == from or slot == from + 1 then marker:Hide() return end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -gap * rh + 1)
        marker:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -gap * rh + 1)
        marker:Show()
    end
    for _, row in ipairs(rows) do
        row:RegisterForDrag("LeftButton")
        row:HookScript("OnEnter", function(self) LightGrip(self, true) end)
        row:HookScript("OnLeave", function(self) LightGrip(self, false) end)
        row:SetScript("OnDragStart", function(self)
            if not self.index then return end
            GameTooltip:Hide()
            from, nextScroll = self.index, nil
            Dim()
            list:SetScript("OnUpdate", Update)
        end)
        row:SetScript("OnDragStop", function()
            local data, f = getData(), from
            local slot = f and Slot()
            Stop()
            local to = slot and data and mod.MoveEntry(data, f, slot)
            if to then moved(f, to) end
        end)
    end
    list:HookScript("OnHide", Stop)
end
