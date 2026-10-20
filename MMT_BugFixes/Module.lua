-- MMT module: Bug Fixes.
-- Small runtime fixes for other MMT modules, each one switchable, until the
-- fix is in the module itself. Every fix has a matching patch in patches/
-- for the module's author.
--
--   CompareOverlap.lua  Item Compare's team tooltips are drawn under the game's
--                       "Equipped" comparison tooltips (patches/ItemCompare_overlap.patch).

local _, mod = ...
local MMT = MMT

local M = MMT.NewModule({
    name = "BugFixes",
    title = "Bug Fixes",
    description = "Runtime fixes for other MMT modules until they are fixed upstream.",
    defaults = {
        compareOverlap = true,
    },
})
mod.M = M

mod.fixes = {}   -- { key, title, note, report() }

local UI, H = MMT.UI, MMT.ConfigHelpers

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
    ResetButton(page)
    local col = MMT.UI.Column(page, 0, 0, MMT.ConfigHelpers.COL_W)
    col:Header("Bug Fixes")
    col:Note("Fixes for other MMT modules. Switch one off to see the original behaviour, or once the module has the fix itself.")
    for _, f in ipairs(mod.fixes) do
        col:Check(f.title, function() return M.db[f.key] end, function(v) M.db[f.key] = v end, f.note)
    end
end

M.Report = function(_, add)
    for _, f in ipairs(mod.fixes) do
        add(("Bug Fixes: %s=%s%s"):format(f.key, tostring(M.db[f.key]), f.report and ("  " .. f.report()) or ""))
    end
end
