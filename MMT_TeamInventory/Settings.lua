-- MMT Team Inventory: settings page (tabs: General / Team bags / Look) and debug report.

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

-- redraws the team bags after a look / filter change
local function Redraw() if mod.RefreshBags then mod.RefreshBags() end end

local function LookOpt(key)
    return function() return M.db[key] end, function(v) M.db[key] = v; Redraw() end
end

local function FontChoices()
    local t = { { value = "", text = "Game font" } }
    for _, f in ipairs(MMT.fonts or {}) do t[#t + 1] = { value = f.name, text = f.name } end
    return t
end

local FILTER_CHOICES = { { value = "SHOW", text = "Show" }, { value = "HIDE", text = "Hide" }, { value = "ONLY", text = "Include" } }

-- Tabs (SettingsKit.lua, shared with Cooldowns / Buffs / Totems):
-- General (tooltip, sharing) / Team bags (window, gifts, filters) / Look
M.Page = function(_, page)
    ResetButton(page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    local panels = mod.Tabs(page, { { "general", "General" }, { "bags", "Team bags" }, { "look", "Look" } })

    -- General ---------------------------------------------------------------
    local p = panels.general
    local L = UI.Column(p, 0, 0, COL_W)
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

    local R = UI.Column(p, COL2_X, 0, COL_W)
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

    -- Team bags -------------------------------------------------------------
    p = panels.bags
    L = UI.Column(p, 0, 0, COL_W)
    L:Header("Window")
    L:Check("Minimap button", function() return M.db.minimap end, function(v)
        M.db.minimap = v
        mod.SetupMinimap()
    end, "Left-click: team bags, right-click: team bank. Drag it around the minimap.")
    local gw, sw = Opt("openOn")
    L:Cycle("Open on", {
        { value = "LAST", text = "The last one viewed" },
        { value = "SELF", text = "This character" },
        { value = "ALL", text = "Whole team" },
        { value = "BYCHAR", text = "Whole team, by character" },
    }, gw, sw)
    L:Check("Group by category", function() return M.db.categories end, function(v)
        M.db.categories = v
        Redraw()
    end, "Consumables, Quest items, Weapons, Armor, Reagents, Trade goods, ... and Junk last.")
    L:Check("Use Baganator's categories", function() return M.db.baganatorCats end, function(v)
        M.db.baganatorCats = v
        Redraw()
    end, "With Baganator on: its category order, hidden and custom categories, priorities and the items you dragged into a category - read each time, so changes in Baganator show here too. Without it: the built-in categories.")
    local chars = L:Cycle("Characters", {
        { value = "TEAM", text = "The team" },
        { value = "RULESET", text = "All stored, this ruleset" },
        { value = "ALL", text = "All stored, every ruleset" },
    }, mod.CharsMode, function(v)
        M.db.otherChars = v ~= "TEAM" and v or false
        Redraw()
    end)
    UI.Tooltip(chars, "Characters", "Who the team bags and the gold show: the character list, the whole-team views, the panel and the total gold. All stored = also every other character this client has items of (other MMT profiles, old teams, other accounts' characters that were in a team with this account), on this ruleset (PvE, PvP, ...) or on all of them, grouped by the team they were last played in. Also at the bottom of the character list in the team bags. Characters of another ruleset can't be given items.")
    L:Check("Team and trades beside the window", function() return M.db.sidePanel ~= false end, function(v)
        M.db.sidePanel = v
        Redraw()
    end, "The panel next to the team bags: your team (click a name for their bags, drop an item on a name to give it) and the planned trades with their Trade buttons. Off: drop items on a character's section in \"by character\" instead.")
    L:Header("Planned gifts")
    local gg, sg = Opt("giveTrade")
    L:Check("Planned gifts go into the trade", gg, sg, "Drag an item onto another character in the team bags. The next time those two trade, the giver puts it into the trade window. Off: use the \"Planned items\" button under the trade window.")
    L:Note("Accepting takes a key press (the game blocks addons from accepting): bind \"Accept trade (planned gifts only)\" in Keybindings > MMT (Manage My Team) > Team Inventory - with ISBoxer one key for every character - or click \"Accept planned gifts\" under the trade window. It accepts only a trade that is nothing but the planned gifts.")
    L:Space(4)
    local half = math.floor((COL_W - 8) / 2)
    local ob = UI.Button(p, half, "Team bags", function() mod.OpenBags("b") end)
    L:Add(ob, 0)
    local ok = UI.Button(p, half, "Team bank", function() mod.OpenBags("k") end)
    ok:SetPoint("LEFT", ob, "RIGHT", 8, 0)

    R = UI.Column(p, COL2_X, 0, COL_W)
    R:Header("Filters")
    for _, k in ipairs(mod.FILTER_KINDS) do
        R:Cycle(k.text, FILTER_CHOICES, function() return mod.FilterState(k.key) end, function(v) mod.SetFilter(k.key, v) end)
    end
    R:Note("Also under Filter in the team bags. Hide removes those items; with one or more kinds on Include, only the included kinds are shown.")

    -- Look ------------------------------------------------------------------
    p = panels.look
    L = UI.Column(p, 0, 0, COL_W)
    L:Header("Window")
    L:Slider("Window size", 0.5, 1.5, 0.05, function() return M.db.bagsScale or 1 end, function(v)
        M.db.bagsScale = v
        if mod.bags then mod.bags:SetScale(v) end
    end, "%.2f")
    L:Cycle("Background", function() return mod.MediaChoices("background", "FLAT", "Flat") end, LookOpt("bagBgTexture"))
    L:Color("Background colour", function() return M.db.bagBgColor end, function(c)
        M.db.bagBgColor = { r = c.r, g = c.g, b = c.b }
        Redraw()
    end)
    local gb, sb = LookOpt("bagBgAlpha")
    L:Slider("Background opacity", 0, 1, 0.05, gb, sb, "%.2f")
    L:Color("Border colour", function() return M.db.bagBorderColor end, function(c)
        M.db.bagBorderColor = { r = c.r, g = c.g, b = c.b }
        Redraw()
    end)
    L:Note("The panel beside the window takes the same background and border. Textures come from LibSharedMedia (other addons such as Details bring many).")
    L:Header("Gold")
    local gsv, ssv = LookOpt("goldSilver")
    L:Check("Show silver", gsv, ssv, "Only how it's shown: the totals are always added up from the exact amounts.")
    local gcp, scp = LookOpt("goldCopper")
    L:Check("Show copper", gcp, scp, "Only how it's shown: the totals are always added up from the exact amounts.")

    R = UI.Column(p, COL2_X, 0, COL_W)
    R:Header("Items")
    local gi, si = LookOpt("bagIconSize")
    R:Slider("Icon size", 20, 64, 1, gi, si)
    local gc, sc = LookOpt("bagColumns")
    R:Slider("Columns", 4, 24, 1, gc, sc)
    local gp, sp = LookOpt("bagSpacing")
    R:Slider("Spacing", 0, 12, 1, gp, sp)
    local gq, sq = LookOpt("bagQuality")
    R:Check("Quality colour around items", gq, sq, "Green, blue, purple ... border for uncommon and better items.")
    R:Header("Count text")
    R:Cycle("Font", FontChoices, function() return M.db.bagFont or "" end, function(v)
        M.db.bagFont = (v ~= "") and v or nil
        Redraw()
    end)
    local gz, sz = LookOpt("bagCountSize")
    R:Slider("Size", 8, 24, 1, gz, sz)

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
    local open, partner = mod.TradeState()
    local gifts = 0
    for _, tos in pairs(mod.Gives()) do for _, items in pairs(tos) do for _, e in pairs(items) do if e.n > 0 then gifts = gifts + 1 end end end end
    add(("  planned gifts=%d giveTrade=%s acceptKey=%s trade open=%s partner=%s"):format(gifts, tostring(M.db.giveTrade),
        tostring(GetBindingKey and GetBindingKey("MMTTEAMINV_ACCEPT")), tostring(open), tostring(partner)))
    local mine = mod.Mine()
    for key, rec in pairs(mod.Chars()) do
        local c = {}
        for _, p in ipairs(mod.PLACES) do
            local k = 0
            for _ in pairs(rec[p] or {}) do k = k + 1 end
            c[#c + 1] = p .. "=" .. k
        end
        add(("  %s%s: %s rs=%s hash=%s %s"):format(MMT.FullDisplay(key), mine[key] and " (this account)" or "",
            table.concat(c, " "), tostring(mod.RulesetOf(key)), tostring(rec.hash), rec.time and MMT.Ago(rec.time) or "?"))
    end
end
