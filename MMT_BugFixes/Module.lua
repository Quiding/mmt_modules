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

M.Page = function(_, page)
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
