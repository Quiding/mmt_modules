-- MMT Totems: settings page (MODULES > Totems in /mmt) and debug report.
-- Tabs: Bars (what is shown) / Look (SettingsKit.lua: sizes, text, background,
-- border) / Casting & presets (sequence key and sequences, presets, sharing).

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
    local panels = mod.Tabs(page, { { "bars", "Bars" }, { "look", "Look" }, { "casting", "Casting & presets" } })
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
    L:Add(test, 0)
    local reset = UI.Button(p, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", 0, -150 }
        M.db.barPoints = {}
        mod.Refresh()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

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
    UI.Tooltip(keyButton, "Totem sequence key", "Click, then press a key (Alt, Ctrl, Shift work). Right-click removes it. Also in Esc > Options > Keybindings > AddOns.")
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
    local seqBox
    C:Cycle("Sequence of", Shamans, function() return seqKey end, function(v)
        seqKey = v
        seqBox:SetText(mod.Sequence(v)); seqBox:UpdatePlaceholder()
    end)
    seqBox = UI.EditBox(cp, COL_W, "Fire, Air, Water, Earth  (Enter)", function(text, box)
        if not seqKey then status.Show_("Choose a shaman first.", true) return end
        mod.SetSequence(seqKey, text)
        box:ClearFocus()
        status.Show_(("Sequence for %s: %s"):format(MMT.FirstName(seqKey), mod.Sequence(seqKey)))
    end)
    C:Add(seqBox, UI.ROW + 4)

    local R = UI.Column(cp, COL2_X, 0, COL_W)
    R:Header("Presets")
    Check(R, "Use presets", "showPresets")
    Check(R, "P button on each bar", "showBarPresets")
    Check(R, "TP (team presets) button", "showTeamPreset")
    Check(R, "Only show them on mouse-over", "presetsOnHover")
    R:Cycle("P button position", {
        { value = "START", text = "Before the totems" },
        { value = "END", text = "After the totems" },
    }, Opt("presetSide"))
    R:Button("Manage presets...", function() mod.OpenPresets() end)


    page.OnRefresh = function()
        if not capturing then keyButton.label:SetText("Sequence key: " .. KeyText()) end
        if not seqKey then
            local first = Shamans()[1]
            seqKey = first and first.value
        end
        if seqKey and not seqBox:HasFocus() then seqBox:SetText(mod.Sequence(seqKey)); seqBox:UpdatePlaceholder() end
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
