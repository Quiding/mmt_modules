-- MMT Team Inventory: settings page and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

-- "Reset to defaults" (click twice), left of the core's "Sync to team" button
local function ResetButton(page)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", M.sync and -(176 + 8) or 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Puts every setting of this module back to the default of a new profile. Click twice.")
    return b
end

local function Opt(key)
    return function() return M.db[key] end, function(v) M.db[key] = v end
end

local function Known()
    local n, items = 0, 0
    for _, rec in pairs(mod.Chars()) do
        n = n + 1
        for _, p in ipairs(mod.PLACES) do for _ in pairs(rec[p] or {}) do items = items + 1 end end
    end
    return n, items
end

M.Page = function(_, page)
    ResetButton(page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)

    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Item tooltip")
    local gt, st = Opt("tooltip")
    L:Check("Show the team's counts", gt, st, "Below the item's tooltip: how many each character has (bags, bank, mail, equipped) and the total.")
    local go, so = Opt("onlyShift")
    L:Check("Only while Shift is held", go, so)
    local ge, se = Opt("equipped")
    L:Check("Count equipped items", ge, se)
    local gs, ss = Opt("withSyndicator")
    L:Cycle("With Baganator / Syndicator", {
        { value = "OTHERS", text = "Only my other accounts" },
        { value = "ALL", text = "Every character" },
        { value = "OFF", text = "Leave it to Syndicator" },
    }, gs, ss)
    local gl, sl = Opt("limit")
    L:Slider("Characters listed at most", 3, 30, 1, gl, sl)

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("How it works")
    R:Note("Each client counts its own bags, equipped items, and - while you have them open - its bank and mailbox, and shares them with the team. Every client keeps the whole team's counts, also for members who are offline.")
    R:Note("Open the bank and the mailbox once on each character so they are counted.")
    R:Note("Baganator / Syndicator already list the characters of the account you're on; by default this adds the characters of your other accounts below it, and the total counts all of them.")
    R:Button("Send my items to the team", function()
        mod.SendSnapshot()
        status.Show_("Your items were sent to the team.")
    end)
    R:Button("Ask the team for theirs", function()
        mod.RequestAll()
        status.Show_("Asked the team for their items.")
    end)
    page.OnRefresh = function()
        local n, items = Known()
        status.Show_(("Known: %d characters, %d item stacks.%s"):format(n, items,
            mod.HasSyndicator() and "  Syndicator found." or ""))
    end
    page.OnRefresh()
end

M.Report = function(_, add)
    local n, items = Known()
    local bank, mail = mod.ScanState()
    add(("-- Team Inventory %s: tooltip=%s syndicator=%s (%s) chars=%d stacks=%d bankOpen=%s mailOpen=%s"):format(
        mod.VERSION, tostring(M.db.tooltip), tostring(mod.HasSyndicator()), tostring(M.db.withSyndicator),
        n, items, tostring(bank), tostring(mail)))
    local mine = mod.Mine()
    for key, rec in pairs(mod.Chars()) do
        local c = {}
        for _, p in ipairs(mod.PLACES) do
            local k = 0
            for _ in pairs(rec[p] or {}) do k = k + 1 end
            c[#c + 1] = p .. "=" .. k
        end
        add(("  %s%s: %s hash=%s %s"):format(MMT.FullDisplay(key), mine[key] and " (this account)" or "",
            table.concat(c, " "), tostring(rec.hash), rec.time and MMT.Ago(rec.time) or "?"))
    end
end
