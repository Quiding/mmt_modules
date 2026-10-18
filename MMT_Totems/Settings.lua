-- MMT Totems: settings page (MODULES > Totems in /mmt) and debug report.

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
    local status
    -- left: bars -------------------------------------------------------------
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Totem bars")
    Check(L, "Show the totem bars", "shown")
    Check(L, "Lock position", "locked")
    Check(L, "Ungrouped bars (move each bar)", "ungrouped", "Each shaman's bar moves on its own, e.g. next to their unit frame.")
    Check(L, "Vertical", "vertical", "Icons in a column instead of a row.")
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
    local gi, si = Opt("iconSize")
    L:Slider("Icon size", 16, 64, 1, gi, si)
    local gs, ss = Opt("scale")
    L:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gin, sin = Opt("inactiveAlpha")
    L:Slider("No totem down: opacity", 0, 1, 0.05, gin, sin, "%.2f")
    local gb, sb = Opt("bgAlpha")
    L:Slider("Background", 0, 1, 0.05, gb, sb, "%.2f")
    local go, so = Opt("alpha")
    L:Slider("Overall opacity", 0.1, 1, 0.05, go, so, "%.2f")
    local gsp, ssp = Opt("spacing")
    L:Slider("Icon spacing", 0, 20, 1, gsp, ssp)
    Check(L, "Show timers", "showTimers")
    local gt, stt = Opt("timerSize")
    L:Slider("Timer size", 8, 32, 1, gt, stt)
    L:Color("Timer colour", function() return M.db.timerColor end, function(c)
        M.db.timerColor = { r = c.r, g = c.g, b = c.b }
        mod.UpdateIcons()
    end)
    local half = (COL_W - 8) / 2
    local test = UI.Button(page, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, 0)
    local reset = UI.Button(page, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", 0, -150 }
        M.db.barPoints = {}
        mod.Refresh()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

    -- right: casting, presets, sharing ----------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Casting")
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
    keyButton = UI.Button(page, COL_W, "", function(self, button)
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
    R:Add(keyButton, UI.ROW + 2)
    Check(R, "Spam-safe sequence", "spamSafe", "/castsequence reset=3 with an empty step at the end, so mashing the key doesn't restart the sequence.")

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
    R:Cycle("Sequence of", Shamans, function() return seqKey end, function(v)
        seqKey = v
        seqBox:SetText(mod.Sequence(v)); seqBox:UpdatePlaceholder()
    end)
    seqBox = UI.EditBox(page, COL_W, "Fire, Air, Water, Earth  (Enter)", function(text, box)
        if not seqKey then status.Show_("Choose a shaman first.", true) return end
        mod.SetSequence(seqKey, text)
        box:ClearFocus()
        status.Show_(("Sequence for %s: %s"):format(MMT.FirstName(seqKey), mod.Sequence(seqKey)))
    end)
    R:Add(seqBox, UI.ROW + 4)

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

    R:Header("Text & spacing")
    local gns, sns = Opt("nameSize")
    R:Slider("Name size", 8, 20, 1, gns, sns)
    local grg, srg = Opt("rowGap")
    R:Slider("Bar spacing", 0, 30, 1, grg, srg)

    R:Header("Share")
    local half2 = (COL_W - 8) / 2
    local send = UI.Button(page, half2, "Send to team", function()
        mod.SendAll()
        status.Show_("Chosen totems, sequences and presets sent.")
    end)
    UI.Tooltip(send, "Send to team", "Sends every shaman's chosen totems, sequences and all presets to the online team.")
    R:Add(send, 0)
    local ie = UI.Button(page, half2, "Import / Export...", function() mod.OpenTransfer() end)
    ie:SetPoint("LEFT", send, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)
    status = H.StatusLine(page)
    status:SetWidth(COL_W)
    R:Add(status, 30)

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
