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

-- a window's cogwheel: its own settings in a small popup next to the row (one at a time)
local popups = {}
function mod.HideTargetOptions(except)
    for id, p in pairs(popups) do if id ~= except then p:Hide() end end
end
local FONT_CHOICES = {
    { value = "INHERIT", text = "Like Fonts & Colour" },
    { value = "ON", text = "The style's font" },
    { value = "OFF", text = "MMT's font" },
}
function mod.TargetOptions(owner, t)
    mod.HideTargetOptions(t.id)
    local p = popups[t.id]
    if p and p:IsShown() then p:Hide() return end
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:SetWidth(240)
        p.widgets = {}
        local A = UI.ACCENT
        UI.Fill(p, 0.06, 0.06, 0.07, 0.97)
        UI.Border(p, A[1], A[2], A[3], 0.6)
        local title = UI.Label(p, t.title, "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetPoint("RIGHT", -26, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        local close = UI.TextButton(p, "x", function() p:Hide() end, 18)
        close:SetPoint("TOPRIGHT", -4, -4)
        local C = UI.Column(p, 10, -30, 220)
        local function Part(key) return function() return mod.TargetOpt(t.id, key, true) ~= false end,
            function(v) mod.SetTargetOpt(t.id, key, v and true or false) end end
        if t.play then
            C:Check("Background", Part("bg"))
            C:Check("Edges", Part("edges"))
            C:Check("Accent colour", Part("accent"))
            C:Note("Its own opacity, fonts and size stay as set in its own settings.")
        else
            local dd = C:Cycle("Font", FONT_CHOICES, function() return mod.TargetOpt(t.id, "font", "INHERIT") end,
                function(v) mod.SetTargetOpt(t.id, "font", v) end)
            -- the drop-down list above this popup (both FULLSCREEN_DIALOG)
            if dd and dd.HookScript then
                dd:HookScript("OnClick", function()
                    local l = rawget(_G, "MMTDropdownList")
                    if l and l:IsShown() then l:SetFrameLevel(p:GetFrameLevel() + 10) end
                end)
            end
            C:Note("\"Like Fonts & Colour\" follows \"Use the style's font\" there.")
        end
        p:SetHeight(-C.y + 8)
        UI.CloseOnEscape(p)
        popups[t.id] = p
    end
    local parent, own = UIParent:GetEffectiveScale(), owner:GetEffectiveScale()
    p:SetScale((parent > 0) and own / parent or 1)
    p:SetFrameLevel(owner:GetFrameLevel() + 20)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
    for _, w in ipairs(p.widgets) do if w.Refresh then w.Refresh() end end
    p:Show()
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

    -- Windows: what gets the style, one by one (Targets.lua) ------------------------------------------------------
    local y2 = TOP - topH - 8
    local ROW_H, COLS = 20, 2
    local perCol = math.ceil(#mod.TARGETS / COLS)
    local wt, W = Tile(page, 0, y2, H.PAGE_W, 60 + perCol * ROW_H + 50, "Windows", "Interface\\Icons\\Spell_Holy_MagicalSentry")
    local colW = math.floor((H.PAGE_W - 30 - 12) / COLS)
    local startY = W.y
    local rows = {}
    for i, t in ipairs(mod.TARGETS) do
        local c, r = math.floor((i - 1) / perCol), (i - 1) % perCol
        local row = CreateFrame("Frame", nil, wt)
        row:SetSize(colW, ROW_H)
        row:SetPoint("TOPLEFT", wt, "TOPLEFT", W.x + c * (colW + 12), startY - r * ROW_H)
        if r % 2 == 0 then UI.Fill(row, 1, 1, 1, 0.03) end
        row.toggle = UI.TextButton(row, "", function()
            mod.SetTargetOpt(t.id, "on", not mod.TargetOn(t.id))
            if page.OnRefresh then page.OnRefresh() end
        end, 40)
        row.toggle:SetPoint("RIGHT", -2, 0)
        row.gear = CreateFrame("Button", nil, row)
        row.gear:SetSize(14, 14)
        row.gear:SetPoint("RIGHT", row.toggle, "LEFT", -4, 0)
        row.gear.icon = row.gear:CreateTexture(nil, "ARTWORK")
        row.gear.icon:SetAllPoints()
        row.gear.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        row.gear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.gear.icon:SetDesaturated(true)
        row.gear.icon:SetAlpha(0.75)
        row.gear:SetScript("OnClick", function() mod.TargetOptions(row, t) end)
        UI.Tooltip(row.gear, "Settings", t.play and "Background, edges and accent of this window, one by one." or "The font of this window.")
        row.gear:HookScript("OnEnter", function(self) self.icon:SetDesaturated(false) self.icon:SetAlpha(1) end)
        row.gear:HookScript("OnLeave", function(self) self.icon:SetDesaturated(true) self.icon:SetAlpha(0.75) end)
        row.label = UI.Label(row, t.title)
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetPoint("RIGHT", row.gear, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(t.title)
            if t.tip then GameTooltip:AddLine(t.tip, 1, 1, 1, true) end
            GameTooltip:AddLine("Off: this window keeps MMT's own look.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.target = t
        rows[#rows + 1] = row
    end
    W.y = startY - perCol * ROW_H - 8
    W:Note("ElvUI and EllesmereUI light up the widget under the mouse; Modern Blizzard and Classic use the game's own window art. "
        .. "The Quest Tracker, Info window and live tracker get the style in ElvUI and EllesmereUI (Classic's art is too heavy for a see-through window). "
        .. "Cooldown / Buff Timers and Totem bars have their own Look tab.")
    wt:SetHeight(-W.y + 10)
    local function RefreshRows()
        for _, row in ipairs(rows) do
            local on = mod.TargetOn(row.target.id)
            row.toggle.label:SetText(on and "|cff55ff55on|r" or "|cff777777off|r")
            row.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
    end

    page.OnRefresh = function()
        local S = mod.STYLES[mod.Opt("style")]
        desc:SetText(S and S.description or "MMT's own flat look.")
        classicBg:SetShown(mod.Opt("style") == "CLASSIC")
        -- Classic keeps MMT's (the game's) font: the option does nothing then
        local noFont = S and not S.font
        fontCheck.label:SetText(noFont and "Use the style's font (Classic keeps it)" or "Use the style's font")
        fontCheck.label:SetTextColor(noFont and 0.45 or 1, noFont and 0.45 or 1, noFont and 0.45 or 1)
        RefreshRows()
    end
    page:HookScript("OnHide", function() if mod.HideTargetOptions then mod.HideTargetOptions() end end)
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
    if mod.HudReport then add(mod.HudReport()) end
    local off = {}
    for _, t in ipairs(mod.TARGETS) do
        if not mod.TargetOn(t.id) then off[#off + 1] = t.id end
        local o = mod.M.store and mod.M.store.targets and mod.M.store.targets[t.id]
        if o then for k, v in pairs(o) do if k ~= "on" then off[#off + 1] = t.id .. "." .. k .. "=" .. tostring(v) end end end
    end
    add("windows off / changed: " .. (#off > 0 and table.concat(off, " ") or "none"))
end
