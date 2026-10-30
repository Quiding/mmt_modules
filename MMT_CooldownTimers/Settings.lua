-- MMT Cooldowns: settings page (MODULES > Cooldowns in /mmt) and debug report.
-- Tabs: Bars (what is shown) / Look (sub-tabs Window: sizes, text, background, border; Icons; Timer) /
-- Spells & items (the tracked lists and sharing) / Specs / Frames (FramesTab.lua).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Apply() mod.window:Refresh() end

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v; Apply() end
end

-- checkbox for a setting (Opt can't be followed by more arguments)
local function Check(col, text, key, tip)
    local g, s = Opt(key)
    col:Check(text, g, s, tip)
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 0)
    status:SetWidth(H.PAGE_W)
    local panels = mod.Tabs(page, { { "bars", "Bars" }, { "look", "Look" }, { "lists", "Spells & items" }, { "specs", "Specs" }, { "frames", "Frames" } })
    mod.ShareBar(page, status)
    mod.SpecsTab(panels.specs, status, function()
        mod.BuildIndex()
        Apply()
        mod.ShareCheck()
        mod.KnownCheck()
    end)

    mod.FramesTab(panels.frames, Opt, status, {
        choices = {
            { value = "WINDOW", text = "In the window" },
            { value = "FRAMES", text = "Beside the party frames" },
        },
        get = function() return M.db.onFrames and "FRAMES" or "WINDOW" end,
        set = function(v) M.db.onFrames = (v == "FRAMES"); Apply() end,
    })

    -- Bars ------------------------------------------------------------------
    local p = panels.bars
    local L = UI.Column(p, 0, 0, COL_W)
    L:Header("Window")
    Check(L, "Show the window", "shown")
    Check(L, "Lock position", "locked")
    Check(L, "Click-through", "clickThrough", "Mouse clicks go through the window (no tooltips, no dragging).")
    L:Cycle("Growth direction", {
        { value = "DOWN", text = "Top > Down" },
        { value = "UP", text = "Down > Top" },
        { value = "RIGHT", text = "Left > Right" },
        { value = "LEFT", text = "Right > Left" },
    }, function() return MMTIconBars.Growth(M.db) end, function(v)
        M.db.growth = v
        M.db.vertical = (v == "RIGHT" or v == "LEFT")
        Apply()
    end)
    Check(L, "Include your own character", "includeSelf")
    Check(L, "Only online or grouped members", "onlyOnline")
    L:Cycle("Preview", {
        { value = "OFF", text = "Off" },
        { value = "REAL", text = "The team as it is" },
        { value = "MIXED", text = "Mixed classes" },
        { value = "ALL", text = "All classes (made-up names)" },
    }, function() return mod.preview or "OFF" end, function(v) mod.SetPreview(v ~= "OFF" and v or nil) end)
    L:Cycle("Names", {
        { value = "OFF", text = "Off" },
        { value = "FIRST", text = "First name" },
        { value = "FULL", text = "First and last name" },
    }, function()
        if not M.db.showNames then return "OFF" end
        return M.db.fullNames and "FULL" or "FIRST"
    end, function(v)
        M.db.showNames = v ~= "OFF"
        M.db.fullNames = v == "FULL"
        Apply()
    end)
    Check(L, "Show timers", "showTimers")
    L:Space(6)
    local half = (COL_W - 8) / 2
    local test = UI.Button(p, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, UI.ROW + 4)   -- Reset position sits beside it, Arrange icons below
    local reset = UI.Button(p, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", 200, 0 }
        Apply()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)
    -- arrange mode (session only): every tracked icon shows, drag them to reorder
    local arrange
    arrange = UI.Button(p, COL_W, "", function() mod.ToggleArrange() end)
    local function ArrangeText() arrange.label:SetText(mod.Arranging("MMTCooldowns") and "Stop arranging icons" or "Arrange icons (drag to reorder)") end
    ArrangeText()
    L:Add(arrange, UI.ROW + 2)
    UI.Tooltip(arrange, "Arrange icons", "Every member's row shows everything their lists track (the hide options wait), with dots on the icons: drag one along its row to move it in its list, or onto a Buff Timers bar to show it there (and back). Buff Timers' bars arrange at the same time. Until you click again or /reload. Also /mmtct arrange.")

    local R = UI.Column(p, COL2_X, 0, COL_W)
    R:Header("Icons")
    Check(R, "Glow while waiting for the buff", "glowActive", "Nature's Swiftness, Presence of Mind, ...: their cooldown starts when the buff is used.")
    Check(R, "Glow while the spell's buff is up", "showBuffs", "Berserking, Evasion, trinkets, ...: the icon glows with the buff's time left, then shows the cooldown.")
    Check(R, "Hide cooldowns that are ready", "hideReady", "Icons only appear while on cooldown.")
    Check(R, "Hide what you don't have", "hideUnknown", "Spells a character hasn't learned yet - yours and, as their clients tell us, the team's - and items you don't carry (your own row).")
    Check(R, "Others' items only after first use", "hideUnseenItems", "Trinkets and potions of other members show up once you have seen them used.")
    R:Note("Each client sends one short message when its character uses a tracked cooldown (needs Cooldowns on that client too). Group members are also seen directly.")


    -- Look ------------------------------------------------------------------
    -- sub-tabs: Window (sizes, text, background, border), Icons (opacity, ...), Timer (TimerTab.lua)
    local look = mod.Tabs(panels.look, { { "window", "Window" }, { "icons", "Icons" }, { "timer", "Timer" } }, { key = "look", bottom = 0 })
    mod.LookTab(look.window, Opt, Apply, { timer = false })
    mod.TimerTab(look.timer, Opt, Apply)
    local LL = UI.Column(look.icons, 0, 0, COL_W)
    LL:Header("Opacity")
    local gr, sr = Opt("readyAlpha")
    LL:Slider("Ready", 0, 1, 0.05, gr, sr, "%.2f")
    local gc, sc = Opt("cdAlpha")
    LL:Slider("On cooldown", 0, 1, 0.05, gc, sc, "%.2f")

    -- Spells & items ----------------------------------------------------------
    local lp = panels.lists
    local LS = UI.Column(lp, 0, 0, COL_W)
    local class = mod.OwnListKey()
    LS:Header("Tracked spells & items")
    local list
    LS:Cycle("List", mod.ListChoices, function() return class end, function(v) class = v; list:Render(M.db.lists[class] or {}) end)

    local EditSeconds
    local function Changed()
        mod.BuildIndex()
        Apply()
        mod.ShareCheck()   -- our running cooldowns that just became tracked
        mod.KnownCheck()   -- which of the tracked spells we haven't learned (Known.lua)
        list:Render(M.db.lists[class] or {})
    end
    -- one number box, shown over the seconds of the row being changed
    local secsEdit
    EditSeconds = function(row)
        local e = row.entry
        if not e then return end
        if not secsEdit then
            secsEdit = UI.EditBox(lp, 44, "sec", function(text, box)
                local entry = box.entry
                if entry then
                    local n = tonumber(text)
                    entry.cd = (n and n >= 0) and math.floor(n + 0.5) or mod.BaseCooldown(entry.t, entry.id) or entry.cd
                    status.Show_(("%s: %ds."):format(mod.EntryName(entry), entry.cd or 0))
                end
                box.entry = nil
                box:ClearFocus()
                box:Hide()
                Changed()
            end)
            secsEdit:SetFrameStrata("DIALOG")
            secsEdit:HookScript("OnEditFocusLost", function(box) box.entry = nil; box:Hide() end)
        end
        secsEdit.entry = e
        secsEdit:ClearAllPoints()
        secsEdit:SetPoint("RIGHT", row.cd, "RIGHT", 2, 0)
        secsEdit:SetText(tostring(e.cd or ""))
        secsEdit:Show()
        secsEdit:SetFocus()
        secsEdit:HighlightText()
    end

    list = H.List(lp, COL_W, 14, 22, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        H.RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", mod.DragGrip(row), "RIGHT", 4, 0)   -- dots: drag to reorder
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = UI.TextButton(row, "x", function() table.remove(M.db.lists[class], row.index); Changed() end, 16)
        row.del:SetPoint("RIGHT", -2, 0)
        -- on / off: switched-off entries stay in the list but aren't tracked
        row.toggle = UI.TextButton(row, "", function()
            local e = M.db.lists[class][row.index]
            if e then e.off = (not e.off) or nil; Changed() end
        end, 26)
        row.toggle:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        UI.Tooltip(row.toggle, "On / off", "Switched-off entries stay in the list but aren't tracked.")
        -- the seconds: click to change them (EditSeconds)
        row.cd = UI.TextButton(row, "", function() EditSeconds(row) end, 40)
        row.cd:SetPoint("RIGHT", row.toggle, "LEFT", -4, 0)
        UI.Tooltip(row.cd, "Cooldown in seconds", "Click to change. Used for a member whose client hasn't told us the real length yet (their own talents and reductions); empty = the spell's base cooldown.")
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.cd, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.entry.t == "s" then GameTooltip:SetSpellByID(self.entry.id) else GameTooltip:SetItemByID(self.entry.id) end
            GameTooltip:AddLine("Drag to move it in the list.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, e, index)
        row.entry, row.index = e, index
        row.icon:SetTexture(mod.EntryIcon(e))
        row.name:SetText(mod.EntryName(e))
        row.cd.label:SetText("|cff999999" .. (e.cd or 0) .. "s|r")
        row.toggle.label:SetText(e.off and "|cff777777off|r" or "|cff55ff55on|r")
        row.icon:SetDesaturated(e.off and true or false)
        row.name:SetTextColor(e.off and 0.5 or 1, e.off and 0.5 or 1, e.off and 0.5 or 1)
    end)
    LS:Add(list, 14 * 22 + 6)
    -- drag a row to reorder the list (SettingsKit); an open seconds box closes first
    mod.DragReorder(list, function() return M.db.lists[class] end, function()
        if secsEdit then secsEdit:ClearFocus() end
        Changed()
    end)

    -- add: name / ID / shift-click a spell or item, and the cooldown in seconds
    local box, secs
    -- picked from the search list, else a link / ID / known name, else the name index
    local function Parse()
        local text = box:GetText()
        if box.picked and box.picked.text == text then return box.picked.t, box.picked.id end
        local t, id = mod.ParseEntry(text)
        if t then return t, id end
        return mod.FindByName(text, true)
    end
    local function Add()
        local t, id = Parse()
        if not t then status.Show_("Unknown spell or item: pick it from the list, use its ID or shift-click it.", true) return end
        local cd = tonumber(secs:GetText()) or mod.BaseCooldown(t, id)
        if not cd then status.Show_("Enter the cooldown in seconds.", true) return end
        M.db.lists[class] = M.db.lists[class] or {}
        table.insert(M.db.lists[class], { t = t, id = id, cd = cd })
        box.picked = nil
        box:SetText(""); secs:SetText("")
        box:ClearFocus(); secs:ClearFocus()
        status.Show_(("Added %s (%ds)."):format(mod.EntryName({ t = t, id = id }), cd))
        Changed()
    end
    local function Prefill()
        local t, id = Parse()
        local cd = t and mod.BaseCooldown(t, id)
        if cd and secs:GetText() == "" then secs:SetText(tostring(cd)); secs:UpdatePlaceholder() end
    end
    box = UI.EditBox(lp, COL_W - 112, "Name, ID or shift-click", function() Add() end)
    secs = UI.EditBox(lp, 50, "sec", function() Add() end)
    UI.AcceptItemLinks(box, Prefill)
    -- spell links (shift-click in the spellbook) go into the box too
    mod.AcceptSpellLinks(box, Prefill)
    box:HookScript("OnEditFocusLost", Prefill)
    mod.AttachSearch(box, { items = true, onPick = function() Prefill() end })
    LS:Add(box, 0)
    secs:SetPoint("LEFT", box, "RIGHT", 4, 0)
    local add = UI.Button(lp, 54, "Add", Add)
    add:SetPoint("LEFT", secs, "RIGHT", 4, 0)

    local RS = UI.Column(lp, COL2_X, 0, COL_W)
    RS:Header("How lists work")
    RS:Note("Lists per class, MMT role or character: a member tracks all lists that fit (class, All classes, their roles, their character). The cooldown seconds fill in by themselves when the game knows them; click them in the list to change. A team member's own client sends the real length (talents) with each use, and it is remembered. Drag an entry to reorder.")
    mod.PresetBox(RS, lp, function() return class end, mod.EntryKey, Changed, status)
    RS:Header("Lists")
    local def = H.ConfirmButton(lp, COL_W, "Reset all lists to defaults", function()
        M.db.lists = MMT.CopyTable(mod.DEFAULT_LISTS)
        status.Show_("Lists reset.")
        Changed()
    end)
    RS:Add(def, UI.ROW + 2)

    page.OnRefresh = function()
        list:Render(M.db.lists[class] or {})
        ArrangeText()
    end
end

M.Report = function(_, add)
    mod.SpecReport(add)
    local n = 0
    for _, l in pairs(M.db.lists or {}) do n = n + #l end
    add(("-- Cooldowns %s: shown=%s entries=%d onFrames=%s (%s) frames: %s"):format(mod.VERSION, tostring(M.db.shown), n,
        tostring(M.db.onFrames), tostring(M.db.framesSide), mod.FramesFound()))
    for key, cds in pairs(mod.cds) do
        local t = {}
        for ek, c in pairs(cds) do t[#t + 1] = ek .. (c.pending and "(buff)" or "") end
        if #t > 0 then add(("cooldowns %s: %s"):format(MMT.Repr(key), table.concat(t, " "))) end
    end
end
