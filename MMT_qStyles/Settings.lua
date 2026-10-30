-- MMT Styles: settings page and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

-- "Reset to defaults" (click twice), bottom right (no Sync button: the style is per account)
local function ResetButton(page, done)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        mod.ResetSettings()
        if done then done() end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Back to MMT's own look, with the style's fonts and accent colour switched on for when you pick one. Click twice.")
    return b
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    ResetButton(page, function() status.Show_("Back to MMT's own look.") end)

    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Style")
    L:Cycle("Style", mod.StyleChoices, function() return mod.Opt("style") end, function(v)
        mod.SetStyle(v)
        status.Show_(v == "NONE" and "MMT's own look again." or ("Style: " .. mod.StyleTitle(v) .. "."))
    end)
    local desc = L:Note(mod.STYLES.ELLESMERE.description)   -- the longest: room for every one
    local fontCheck = L:Check("Use the style's font", function() return mod.Opt("fonts") end, function(v) mod.SetOpt("fonts", v and true or false) end,
        "Labels, buttons and edit boxes get the style's font (a little bigger). Off: MMT's fonts stay.")
    L:Check("Use the style's accent colour", function() return mod.Opt("accent") end, function(v) mod.SetOpt("accent", v and true or false) end,
        "Check marks, slider knobs, the selected page in the list, dropdown values and highlighted rows get the style's colour instead of MMT's blue.")
    L:Cycle("Classic: window background", mod.ClassicBgChoices, function() return mod.Opt("classicBg") end, function(v)
        mod.SetOpt("classicBg", v)
        status.Show_(mod.Opt("style") == "CLASSIC" and "Classic background changed." or "Used when the style is Classic.")
    end)
    L:Space(8)
    L:Note("Saved for your account: every character and profile gets the same look. Switches right away, no /reload. Also /mmtstyle none | elvui | ellesmere | modern | classic.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("What gets the style")
    R:Note("MMT's settings window, its dropdown lists, colour picker and dialogs, and every window built from MMT's widgets: "
        .. "Team bags, Team Gear, Pawn scales, the ForeverAuras / EllesmereUI send windows, Totem presets, Import / Export, "
        .. "Item Compare's tooltips, the death panel and more.")
    R:Note("ElvUI and EllesmereUI light up the widget under the mouse; Modern Blizzard and Classic use the game's own window art.")
    R:Header("What keeps its look")
    R:Note("Cooldown / Buff Timers and Totem bars: they have their own Look tab. MMT's XP window and distance display "
        .. "(built before Styles loads). Coloured pieces like item quality borders. Secure buttons (Totems) keep the colour look in Classic.")

    page.OnRefresh = function()
        local S = mod.STYLES[mod.Opt("style")]
        desc:SetText(S and S.description or "MMT's own flat look.")
        -- Classic keeps MMT's (the game's) font: the option does nothing then
        local noFont = S and not S.font
        fontCheck.label:SetText(noFont and "Use the style's font (Classic keeps it)" or "Use the style's font")
        fontCheck.label:SetTextColor(noFont and 0.45 or 1, noFont and 0.45 or 1, noFont and 0.45 or 1)
    end
    mod.ScanConfig()
end

M.Report = function(_, add)
    local c = mod.Counts()
    add(("style=%s (shown: %s) fonts=%s accent=%s"):format(tostring(mod.Opt("style")), QStyles.Current(),
        tostring(mod.Opt("fonts")), tostring(mod.Opt("accent"))))
    add(("tracked: fills=%d edges=%d fonts=%d colours=%d texts=%d headers=%d widgets=%d"):format(c.fills, c.borders, c.fonts,
        c.colors, c.texts, c.headers, c.widgets))
    local bgs = {}
    for _, b in ipairs(mod.CLASSIC_BGS) do bgs[#bgs + 1] = b.value .. "=" .. tostring(mod.HasFile(b.file)) end
    add(("classic background=%s (shown: %s) files: %s"):format(tostring(mod.Opt("classicBg")), mod.ClassicBg().value, table.concat(bgs, " ")))
    local hooks = {}
    for name, ok in pairs(mod.hooked) do hooks[#hooks + 1] = name .. (ok and "" or "(missing)") end
    table.sort(hooks)
    add("hooks: " .. table.concat(hooks, " "))
end
