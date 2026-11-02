-- MMT Totems: settings page (MODULES > Totems in /mmt) and debug report.
-- Tabs: Bars (what is shown) / Look (SettingsKit.lua: sizes, text, background,
-- border) / Casting (sequence key and sequences) / Calls.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v; mod.Refresh() end
end

local function Check(col, text, key, tip)
    local g, s = Opt(key)
    col:Check(text, g, s, tip)
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 0)
    status:SetWidth(H.PAGE_W)
    local panels = mod.Tabs(page, { { "bars", "Bars" }, { "look", "Look" }, { "casting", "Casting" }, { "calls", "Calls" } })
    mod.ShareBar(page, status)

    -- Bars ------------------------------------------------------------------
    local p = panels.bars
    local L = UI.Column(p, 0, 0, COL_W)
    L:Header("Totem bars")
    Check(L, "Show the totem bars", "shown")
    Check(L, "Lock position", "locked")
    Check(L, "Ungrouped bars (move each bar)", "ungrouped", "Each shaman's bar moves on its own, e.g. next to their unit frame.")
    L:Cycle("Growth direction", {
        { value = "DOWN", text = "Top > Down" },
        { value = "UP", text = "Down > Top" },
        { value = "RIGHT", text = "Left > Right" },
        { value = "LEFT", text = "Right > Left" },
    }, function() return mod.Growth(M.db) end, function(v)
        M.db.growth = v
        M.db.vertical = (v == "RIGHT" or v == "LEFT")
        mod.Refresh()
    end)
    Check(L, "Include your own character", "includeSelf")
    Check(L, "Only online or grouped shamans", "onlyOnline")
    Check(L, "Only timers (no casting / choosing)", "onlyTimers", "Passive mode: the bars only show totems and timers.")
    L:Cycle("Order", {
        { value = "TEAM", text = "Team order" },
        { value = "NAME_ASC", text = "Name A-Z" },
        { value = "NAME_DESC", text = "Name Z-A" },
        { value = "ROLE", text = "Role (tank, healer, dps)" },
    }, Opt("order"))
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
        mod.Refresh()
    end)
    Check(L, "Show timers", "showTimers")
    L:Space(6)
    local half = (COL_W - 8) / 2
    local test = UI.Button(p, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, UI.ROW + 4)   -- Reset position sits beside it, Practice shaman below
    local reset = UI.Button(p, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", 0, -150 }
        M.db.barPoints = {}
        mod.Refresh()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)
    local practice
    practice = UI.Button(p, COL_W, "", function() mod.SetPractice(not mod.practice) end)
    local function PracticeText()
        practice.label:SetText(mod.practice and "Remove the practice shaman" or "Practice shaman (until /reload)")
    end
    PracticeText()
    L:Add(practice, UI.ROW + 2)
    UI.Tooltip(practice, "Practice shaman", "A made-up shaman bar to set up the look, totems and presets on a client with no shaman around. It knows every totem and carries every item; nothing about it is sent to the team, and what you choose for it is wiped when it goes. Also /mmtt practice.")

    local RB = UI.Column(p, COL2_X, 0, COL_W)
    RB:Header("How the bars work")
    RB:Note("One bar per shaman: the totem that is down with its time left, else the chosen one, else the last one used. Right-click a slot to choose a totem, left-click a slot on your own bar to cast it. Right-click the background for these settings.")
    RB:Note("Ungrouped: each bar moves on its own and gets the background and border itself. Size, colours and textures are on the Look tab.")
    RB:Header("Totem slots")
    Check(RB, "Hide without the totem item", "hideNoItem", "Hide an element when that shaman doesn't carry its totem (Earth / Fire / Water / Air Totem) in the bags.")
    Check(RB, "Hide with no totem learned", "hideUnlearned", "Hide an element when that shaman hasn't learned any of its totems yet.")
    for _, el in ipairs(mod.ELEMENTS) do
        RB:Check("Always hide " .. el, function() return M.db.hiddenElements[el] and true or false end,
            function(v) M.db.hiddenElements[el] = v or nil; mod.Refresh() end)
    end

    -- Look ------------------------------------------------------------------
    local LL = mod.LookTab(panels.look, Opt, mod.Refresh)
    LL:Header("Opacity")
    local gin, sin = Opt("inactiveAlpha")
    LL:Slider("No totem down: opacity", 0, 1, 0.05, gin, sin, "%.2f")
    local go, so = Opt("alpha")
    LL:Slider("Overall opacity", 0.1, 1, 0.05, go, so, "%.2f")

    -- Casting & presets ---------------------------------------------------------
    local cp = panels.casting
    local C = UI.Column(cp, 0, 0, COL_W)
    C:Header("Casting")
    -- key capture: click, then press the key
    local keyButton
    local capturing = false
    local function KeyText()
        local k = M.db.keybind
        return (k and k ~= "") and GetBindingText(k) or "not set"
    end
    local function StopCapture()
        capturing = false
        keyButton:EnableKeyboard(false)
        keyButton.label:SetText("Sequence key: " .. KeyText())
    end
    keyButton = UI.Button(cp, COL_W, "", function(self, button)
        if button == "RightButton" then
            local ok, err = mod.SetKey(nil)
            status.Show_(ok and "Sequence key removed." or err, not ok)
            StopCapture()
            return
        end
        if InCombatLockdown() then status.Show_("Keys can't be changed in combat.", true) return end
        capturing = true
        keyButton.label:SetText("Press a key...  (Esc = cancel)")
        keyButton:EnableKeyboard(true)
        if keyButton.SetPropagateKeyboardInput then keyButton:SetPropagateKeyboardInput(false) end
    end)
    keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    keyButton:SetScript("OnKeyDown", function(self, key)
        if not capturing then return end
        if key == "ESCAPE" then StopCapture() return end
        if MODIFIER_KEYS[key] then return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local ok, msg = mod.SetKey(combo)
        status.Show_(ok and ("Totem sequence is now on " .. GetBindingText(combo) .. ".") or msg, not ok)
        StopCapture()
    end)
    UI.Tooltip(keyButton, "Totem sequence key", "Click, then press a key (Alt, Ctrl, Shift work). Right-click removes it. Also in Esc > Options > Keybindings > MMT (Manage My Team) > Totems.")
    C:Add(keyButton, UI.ROW + 2)
    Check(C, "Spam-safe sequence", "spamSafe", "/castsequence reset=3 with an empty step at the end, so mashing the key doesn't restart the sequence.")

    -- sequence per shaman
    local seqKey
    local function Shamans()
        local t = {}
        for _, k in ipairs(MMT.SortedMembers()) do if mod.IsShaman(k) then t[#t + 1] = { value = k, text = MMT.FirstName(k) } end end
        local own = mod.OwnKey()
        if mod.IsShaman(own) and not MMT.db.team[own] then table.insert(t, 1, { value = own, text = MMT.FirstName(own) }) end
        return t
    end
    -- the sequence as four buttons: "<>" between two swaps them,
    -- right-click leaves an element out of the sequence (or takes it back)
    local ShowSequence
    C:Cycle("Sequence of", Shamans, function() return seqKey end, function(v)
        seqKey = v
        ShowSequence()
    end)
    local SEQ_COLOR = { Fire = { 1, 0.45, 0.2 }, Air = { 0.6, 0.85, 1 }, Water = { 0.3, 0.6, 1 }, Earth = { 0.85, 0.65, 0.35 } }
    local SW = 16
    local EW = math.floor((COL_W - 3 * SW) / 4)
    local seqRow = CreateFrame("Frame", nil, cp)
    seqRow:SetSize(COL_W, UI.ROW)
    local order, used = mod.SequenceOrder(mod.DEFAULT_SEQUENCE)
    local function Save()
        if not seqKey then status.Show_("Choose a shaman first.", true) return end
        mod.SetSequence(seqKey, mod.SequenceText(order, used))
        status.Show_(("Sequence for %s: %s"):format(MMT.FirstName(seqKey), mod.Sequence(seqKey)))
        ShowSequence()
    end
    local elButtons = {}
    for i = 1, 4 do
        local b = UI.Button(seqRow, EW, "", function(self, button)
            local el = order[i]
            if button == "RightButton" then
                used[el] = not used[el] or nil
                if not next(used) then used[el] = true; status.Show_("The sequence needs at least one element.", true) return end
                Save()
            end
        end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetPoint("LEFT", (i - 1) * (EW + SW), 0)
        UI.Tooltip(b, "Sequence", "Click <> to swap two elements. Right-click leaves an element out of the sequence (greyed) or takes it back.")
        elButtons[i] = b
        if i < 4 then
            local swap = UI.TextButton(seqRow, "<>", function()
                order[i], order[i + 1] = order[i + 1], order[i]
                Save()
            end, SW)
            swap:SetPoint("LEFT", b, "RIGHT", 0, 0)
        end
    end
    ShowSequence = function()
        order, used = mod.SequenceOrder(seqKey and mod.Sequence(seqKey) or mod.DEFAULT_SEQUENCE)
        for i, b in ipairs(elButtons) do
            local el, c = order[i], SEQ_COLOR[order[i]]
            b.label:SetText(el)
            if used[el] then b.label:SetTextColor(c[1], c[2], c[3]) else b.label:SetTextColor(0.4, 0.4, 0.4) end
        end
    end
    ShowSequence()
    C:Add(seqRow, UI.ROW + 4)

    -- the per-shaman presets (P button) are gone since 0.5.2: the Calls are the sets
    local R = UI.Column(cp, COL2_X, 0, COL_W)
    R:Header("Sets of totems")
    R:Note("From level 20 the Calls (Elements, Ancestors, Spirits) are each shaman's totem sets: pick the Call on the bar with its icon, then right-click a slot to choose that Call's totem - or set all three on the Calls tab. Below level 20 the sequence key above drops the chosen totems.")


    -- Calls -----------------------------------------------------------------
    -- each shaman's Call of the Elements / Ancestors / Spirits: one totem per element,
    -- set here for anyone; that shaman's client puts them on Blizzard's totem bar
    local kp = panels.calls
    local K = UI.Column(kp, 0, 0, COL_W)
    K:Header("Calls of")
    local callKey
    local RefreshCalls
    K:Cycle("Shaman", Shamans, function() return callKey end, function(v)
        callKey = v
        RefreshCalls()
    end)
    local ICON, IGAP = 30, 6
    local callIcons = {}
    for call, c in ipairs(mod.CALLS) do
        local row = CreateFrame("Frame", nil, kp)
        row:SetSize(COL_W, ICON + 18)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 0, 0)
        label:SetText(c.name)
        row.label = label
        callIcons[call] = { row = row }
        for i, el in ipairs(mod.ELEMENTS) do
            local b = CreateFrame("Button", nil, row)
            b:SetSize(ICON, ICON)
            b:SetPoint("TOPLEFT", (i - 1) * (ICON + IGAP), -14)
            UI.Fill(b, 0.12, 0.12, 0.12, 1)
            UI.Border(b, 0.3, 0.3, 0.3, 1)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.empty = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            b.empty:SetPoint("CENTER")
            b.empty:SetText(el:sub(1, 1))
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", function(self, button)
                if not callKey then status.Show_("Choose a shaman first.", true) return end
                if button == "RightButton" then mod.SetCallTotem(callKey, call, el, 0)
                else mod.OpenCallMenu(self, callKey, call, el) end
                RefreshCalls()
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(("%s - %s"):format(c.name, el))
                local id = callKey and mod.CallTotem(callKey, call, el)
                GameTooltip:AddLine(id and (mod.TotemName(id) or ("Spell " .. id)) or "none", 1, 1, 1)
                GameTooltip:AddLine("Click: choose. Right-click: none.", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            callIcons[call][el] = b
        end
        K:Add(row, ICON + 22)
    end
    RefreshCalls = function()
        local own = callKey and MMT.IsSelf(callKey)
        for call, c in ipairs(mod.CALLS) do
            local known = not own or mod.KnowsCall(call)
            callIcons[call].row.label:SetText(c.name .. (known and "" or "  |cff888888(not learned yet)|r"))
            for _, el in ipairs(mod.ELEMENTS) do
                local b = callIcons[call][el]
                local id = callKey and mod.CallTotem(callKey, call, el)
                local icon = id and mod.TotemIcon(id)
                if icon then b.icon:SetTexture(icon); b.icon:Show(); b.empty:Hide()
                else b.icon:Hide(); b.empty:Show() end
                b.icon:SetDesaturated(not known)
            end
        end
    end

    local KR = UI.Column(kp, COL2_X, 0, COL_W)
    KR:Header("How it works")
    KR:Note("Each Call drops one totem per element: Call of the Elements from level 20, of the Ancestors from 30, of the Spirits from 40. Set them here for any shaman; that shaman's client puts them on Blizzard's totem bar (out of combat). Below level 20 the sequence key does the job.")
    KR:Button("Copy Elements to the other two", function()
        if not callKey then return end
        mod.CopyCall(callKey, 1, 2)
        mod.CopyCall(callKey, 1, 3)
        RefreshCalls()
        status.Show_(("%s: all three Calls are now the same."):format(MMT.FirstName(callKey)))
    end)
    KR:Button("Put mine on my totem bar now", function()
        local n = mod.PushCalls()
        status.Show_(InCombatLockdown() and "In combat: after the fight." or ("%d totem(s) changed on your totem bar."):format(n))
    end)

    page.OnRefresh = function()
        PracticeText()
        if not callKey then
            local first = Shamans()[1]
            callKey = first and first.value
        end
        RefreshCalls()
        if not capturing then keyButton.label:SetText("Sequence key: " .. KeyText()) end
        if not seqKey then
            local first = Shamans()[1]
            seqKey = first and first.value
        end
        ShowSequence()
    end
end

M.Report = function(_, add)
    add(("-- Totems %s: shown=%s shamans=%s key=%s"):format(mod.VERSION, tostring(M.db.shown),
        table.concat(mod.Shamans(), ","), tostring(M.db.keybind)))
    add("sequence macro: " .. tostring(mod.SequenceMacro(mod.OwnKey())))
    for key, t in pairs(mod.active) do
        local parts = {}
        for el, a in pairs(t) do parts[#parts + 1] = el .. "=" .. tostring(a.name) end
        if #parts > 0 then add(("totems %s: %s"):format(MMT.Repr(key), table.concat(parts, " "))) end
    end
end
