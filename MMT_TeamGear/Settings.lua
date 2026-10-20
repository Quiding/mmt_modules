-- MMT Team Gear: settings page and debug report.

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

M.Page = function(_, page)
    ResetButton(page, function() mod.SetupButton() end)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Team Gear")
    L:Check("Button on the character panel", function() return M.db.button end, function(v)
        M.db.button = v
        mod.SetupButton()
    end, "Click it to pick a team member. Shift-drag moves it.")
    L:Button("Put the button and windows back", function()
        mod.ResetButton()
        M.db.windowPoint, M.db.overviewPoint = nil, nil
        if mod.window then mod.window:Hide() end
        if mod.overview then mod.overview:Hide() end
    end)
    L:Check("Show yourself in the list", function() return M.db.includeSelf end, function(v) M.db.includeSelf = v end)
    L:Check("Also show other teams", function() return M.db.others end, function(v) M.db.others = v end,
        "Item Compare keeps every character it ever stored on this account. The list then shows Team 1 (this team), Team 2, ... (your other profiles' teams) and Other characters (former members), each with its members below it.")
    L:Check("Item names beside the slots", function() return M.db.names end, function(v)
        M.db.names = v
        if mod.window and mod.window:IsShown() then mod.Refresh() end
    end)
    L:Slider("Gear window size", 0.5, 1.5, 0.05, function() return M.db.windowScale or 1 end, function(v)
        M.db.windowScale = v
        if mod.window then mod.window:SetScale(v) end
    end, "%.2f")
    L:Slider("Whole team window size", 0.5, 1.5, 0.05, function() return M.db.overviewScale or 1 end, function(v)
        M.db.overviewScale = v
        if mod.overview then mod.overview:SetScale(v) end
    end, "%.2f")
    L:Button("Show a member's gear...", function(self) mod.OpenMemberList(self) end)
    L:Button("Show the whole team", function() mod.OpenOverview() end)

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Where the items come from")
    R:Note("Item Compare keeps every member's equipped items, also while they are offline, and updates them when they change gear. This module only shows them and sends nothing itself.")
    local warn = R:Note("")
    page.OnRefresh = function()
        if mod.HasItemCompare() then
            warn:SetText("|cff66ff66Item Compare is on.|r")
        else
            warn:SetText("|cffff6666Item Compare is off or missing:|r switch it on under /mmt > MODULES, otherwise there is no gear to show.")
        end
    end
    page.OnRefresh()
    R:Note("Hover a slot for the tooltip, Shift-click to link the item in chat, Ctrl-click to try it on. /mmtgear <name> opens a member directly.")
end

M.Report = function(_, add)
    local n, with = 0, 0
    for _, key in ipairs(mod.Members()) do
        n = n + 1
        if mod.Equipment(key) then with = with + 1 end
    end
    add(("-- Team Gear %s: itemCompare=%s button=%s members=%d withGear=%d"):format(mod.VERSION,
        tostring(mod.HasItemCompare()), tostring(mod.button and mod.button:IsShown() or false), n, with))
    local f = mod.window
    if f then
        local p, _, rp, x, y = f:GetPoint(1)
        add(("window: shown=%s key=%s strata=%s at %s %s %s %s model: %s"):format(tostring(f:IsShown()), tostring(f.key),
            tostring(f:GetFrameStrata()), tostring(p), tostring(rp), tostring(x), tostring(y), tostring(mod.modelInfo)))
        local rec = f.key and mod.Equipment(f.key)
        for slot = 1, 19 do
            local s = rec and rec.items[slot]
            if s then add(("  slot %d: %s  enchant=%s"):format(slot, s, tostring(mod.EnchantName(s)))) end
        end
    end
end
