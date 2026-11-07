-- MMT Styles: settings page and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers

-- "Reset to defaults" (click twice), left of the core's Sync button (it sends this account's look, Module.lua)
local function ResetButton(page, done)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        mod.ResetSettings()
        if M.OnProfileChanged then M.OnProfileChanged(M) end
        if done then done() end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", M.sync and -(176 + 8) or 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Back to MMT's own look, with the style's fonts and accent colour switched on for when you pick one. Click twice.")
    return b
end

-- tiles of one row get the height of the tallest one's content
local function FitRow(row)
    local h = 0
    for _, r in ipairs(row) do h = math.max(h, -(tonumber(r[2].y) or -290) + 10) end
    for _, r in ipairs(row) do r[1]:SetHeight(h) end
    return h
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    ResetButton(page, function() status.Show_("Back to MMT's own look.") end)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local TOP = H.Intro(page, "Another look for MMT's settings and windows. Saved for your account: every character and profile gets the same look, switched right away (no /reload).")

    -- Style (left) -------------------------------------------------------------------------------------------
    local lt, L = Tile(page, 0, TOP, TILE_W, 300, "Style", "Interface\\Icons\\INV_Misc_Ribbon_01")
    L:Cycle("Style", mod.StyleChoices, function() return mod.Opt("style") end, function(v)
        mod.SetStyle(v)
        status.Show_(v == "NONE" and "MMT's own look again." or ("Style: " .. mod.StyleTitle(v) .. "."))
        if page.OnRefresh then page.OnRefresh() end
    end)
    local desc = L:Note(mod.STYLES.ELLESMERE.description)   -- the longest: room for every one
    L:Note("Also /mmtstyle none | elvui | ellesmere | modern | classic.")
    -- only for Classic: shown while it is the style (last in the tile, so nothing moves up into a gap)
    local classicBg = L:Cycle("Classic: window background", mod.ClassicBgChoices, function() return mod.Opt("classicBg") end, function(v)
        mod.SetOpt("classicBg", v)
        status.Show_("Classic background changed.")
    end)

    -- Fonts & Colour (right) ------------------------------------------------------------------------------------
    local rt, R = Tile(page, X2, TOP, TILE_W, 300, "Fonts & Colour", "Interface\\Icons\\INV_Inscription_Tradeskill01")
    local fontCheck = R:Check("Use the style's font", function() return mod.Opt("fonts") end, function(v) mod.SetOpt("fonts", v and true or false) end,
        "Labels, buttons and edit boxes get the style's font (a little bigger). Off: MMT's fonts stay.")
    R:Check("Keep the game's own font", function() return mod.Opt("gameFont") end, function(v) mod.SetOpt("gameFont", v and true or false) end,
        "When another addon changes all game text (EllesmereUI's \"Apply to All Game Text\", ElvUI), MMT's windows keep the game's own font. "
        .. "Works with any style, None too. The style's font, when it's used, wins.")
    R:Check("Use the style's accent colour", function() return mod.Opt("accent") end, function(v) mod.SetOpt("accent", v and true or false) end,
        "Check marks, slider knobs, the selected page in the list, dropdown values, highlighted rows and the tiles' titles get the style's colour instead of MMT's blue.")
    local topH = FitRow({ { lt, L }, { rt, R } })

    -- What gets the style / what keeps its look (second row) ------------------------------------------------------
    local y2 = TOP - topH - 8
    local gt, G = Tile(page, 0, y2, TILE_W, 150, "What Gets the Style", "Interface\\Icons\\Spell_Holy_MagicalSentry")
    G:Note("MMT's settings window, its dropdown lists, colour picker and dialogs, and every window built from MMT's widgets: "
        .. "Team bags, Team Gear, Pawn scales, the ForeverAuras / EllesmereUI send windows, Totem presets, Import / Export, "
        .. "Item Compare's tooltips, the death panel, the MMT Auto-Mailing window, the Info window's column settings and more.")
    G:Note("ElvUI and EllesmereUI light up the widget under the mouse; Modern Blizzard and Classic use the game's own window art.")
    local kt, K = Tile(page, X2, y2, TILE_W, 150, "What Keeps Its Look", "Interface\\Icons\\INV_Misc_Spyglass_02")
    K:Note("Cooldown / Buff Timers and Totem bars: they have their own Look tab. The windows you play with keep MMT's look: "
        .. "the Info window, the distance display, the Quest Tracker and Statistics' live tracker. Coloured pieces like item quality borders. Secure buttons (Totems) keep the colour look in Classic.")
    FitRow({ { gt, G }, { kt, K } })

    page.OnRefresh = function()
        local S = mod.STYLES[mod.Opt("style")]
        desc:SetText(S and S.description or "MMT's own flat look.")
        classicBg:SetShown(mod.Opt("style") == "CLASSIC")
        -- Classic keeps MMT's (the game's) font: the option does nothing then
        local noFont = S and not S.font
        fontCheck.label:SetText(noFont and "Use the style's font (Classic keeps it)" or "Use the style's font")
        fontCheck.label:SetTextColor(noFont and 0.45 or 1, noFont and 0.45 or 1, noFont and 0.45 or 1)
    end
    mod.ScanConfig()
end

M.Report = function(_, add)
    local c = mod.Counts()
    add(("style=%s (shown: %s) fonts=%s accent=%s gameFont=%s (game text: %s, client: %s)"):format(tostring(mod.Opt("style")), QStyles.Current(),
        tostring(mod.Opt("fonts")), tostring(mod.Opt("accent")), tostring(mod.Opt("gameFont")), tostring(rawget(_G, "STANDARD_TEXT_FONT")), mod.ClientFont()))
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
