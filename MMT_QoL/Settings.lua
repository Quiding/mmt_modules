-- MMT Quality of life: settings page and debug report.
-- One tab per feature (SettingsKit's mod.Tabs): its on/off checkbox (greyed
-- out with the reason when its addon isn't loaded), then its options (greyed
-- out while it is off); f.notes = lines for a column on the right.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

-- "Reset to defaults" (click twice), left of the core's "Sync to team" button
local function ResetButton(page, done)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        if M.OnProfileChanged then M.OnProfileChanged(M) end
        if done then done() end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", M.sync and -(176 + 8) or 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Puts every setting of this module back to the default of a new profile. Click twice.")
    return b
end

local function FeatureColumn(page, f, x, status)
    local col = UI.Column(page, x, 0, COL_W)
    col:Header(f.title)
    local main = col:Check(f.checkText,
        function() return M.db[f.key] and (f.sendOnly or (mod.AddonState(f.addon))) and true or false end,
        function(v)
            if not f.sendOnly and not (mod.AddonState(f.addon)) then return end
            M.db[f.key] = v
            if v and M.enabled and f.OnEnable then f.OnEnable() end
            if not v and f.OnDisable then f.OnDisable() end
        end, f.tip)

    local gated = {}
    local function Gate(w) gated[#gated + 1] = w; return w end
    local function Set(key) return function(v) if mod.Active(f) then M.db[key] = v end end end
    local ui = { status = status, col = col }
    function ui.Check(text, key, tip)
        return Gate(col:Check(text, function() return M.db[key] end, Set(key), tip))
    end
    function ui.Cycle(text, choices, key)
        return Gate(col:Cycle(text, choices, function() return M.db[key] end, Set(key)))
    end
    function ui.Button(text, onClick, tip)
        local b = col:Button(text, function() if mod.Active(f) then onClick() end end)
        if tip then UI.Tooltip(b, text, tip) end
        return Gate(b)
    end
    function ui.Confirm(text, onClick, tip)
        local b = H.ConfirmButton(page, COL_W, text, function() if mod.Active(f) then onClick() end end)
        col:Add(b, UI.ROW + 2)
        if tip then UI.Tooltip(b, text, tip) end
        return Gate(b)
    end
    function ui.Note(text) return col:Note(text) end
    f.Page(ui)
    if f.notes then
        local R = UI.Column(page, COL2_X, 0, COL_W)
        R:Header("How it works")
        for _, n in ipairs(f.notes) do R:Note(n) end
    end

    return function()
        local ok, why = mod.AddonState(f.addon)
        main:SetAlpha((ok or f.sendOnly) and 1 or 0.4)
        UI.Tooltip(main, f.checkText, ok and f.tip
            or f.sendOnly and (f.tip .. "\n\n" .. tostring(why) .. " This character only receives.")
            or ("Can't be switched on: " .. tostring(why)))
        local on = mod.Active(f)
        for _, w in ipairs(gated) do w:SetAlpha(on and 1 or 0.4) end
        if f.Refresh then f.Refresh() end
    end
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    ResetButton(page)

    local tabs = {}
    for _, f in ipairs(mod.features) do
        -- the tab of a feature whose addon isn't loaded is greyed and says why (SettingsKit)
        tabs[#tabs + 1] = { f.key, f.tabText or f.title, blocked = f.addon and not f.sendOnly and function()
            local ok, why = mod.AddonState(f.addon)
            if not ok then return (why or "") .. " This tab needs it." end
        end or nil }
    end
    local panels = mod.Tabs(page, tabs)
    local refresh = {}
    for _, f in ipairs(mod.features) do
        refresh[#refresh + 1] = FeatureColumn(panels[f.key], f, 0, status)
    end

    page.OnRefresh = function()
        for _, r in ipairs(refresh) do r() end
        local off = {}
        for _, f in ipairs(mod.features) do
            local ok, why = mod.AddonState(f.addon)
            if not ok and not f.sendOnly then off[#off + 1] = why end
        end
        status.Show_(#off > 0 and table.concat(off, " ") or "")
    end
    page.OnRefresh()
end

M.Report = function(_, add)
    local on = {}
    for _, f in ipairs(mod.features) do on[#on + 1] = ("%s=%s"):format(f.key, tostring(mod.Active(f))) end
    add(("-- Quality of life %s: %s asks waiting=%d"):format(mod.VERSION, table.concat(on, " "), mod.AskWaiting()))
    for _, f in ipairs(mod.features) do if f.Report then f.Report(add) end end
end
