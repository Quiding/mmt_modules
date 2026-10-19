-- MMT Buffs: settings page (MODULES > Buffs in /mmt) and debug report.
-- Tabs: Bars (what is shown) / Look (sizes, text, background, border,
-- missing buffs) / Buffs (the tracked lists, the All classes row, sharing).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Apply() mod.Apply() end

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v; Apply() end
end

-- checkbox for a setting (Opt can't be followed by more arguments)
local function Check(col, text, key, tip)
    local g, s = Opt(key)
    col:Check(text, g, s, tip)
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 0)
    status:SetWidth(H.PAGE_W)
    local panels = mod.Tabs(page, { { "bars", "Bars" }, { "look", "Look" }, { "lists", "Buffs" } })

    -- Bars ------------------------------------------------------------------
    local p = panels.bars
    local L = UI.Column(p, 0, 0, COL_W)
    L:Header("Window")
    Check(L, "Show the buffs", "shown")
    local ga, sa = Opt("attach")
    L:Cycle("Where", {
        { value = "OFF", text = "Own window" },
        { value = "RIGHT", text = "On the Cooldowns bars, right" },
        { value = "LEFT", text = "On the Cooldowns bars, left" },
    }, ga, sa)
    Check(L, "Lock position", "locked")
    Check(L, "Click-through", "clickThrough", "Mouse clicks go through the window (no tooltips, no dragging).")
    L:Cycle("Growth direction", {
        { value = "DOWN", text = "Top > Down" },
        { value = "UP", text = "Down > Top" },
        { value = "RIGHT", text = "Left > Right" },
        { value = "LEFT", text = "Right > Left" },
    }, function() return MMTIconBars.Growth(M.db) end, function(v)
        M.db.growth = v
        M.db.vertical = (v == "RIGHT" or v == "LEFT")
        Apply()
    end)
    Check(L, "Include your own character", "includeSelf")
    Check(L, "Only online or grouped members", "onlyOnline")
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
        Apply()
    end)
    Check(L, "Show timers", "showTimers")
    L:Space(6)
    local half = (COL_W - 8) / 2
    local test = UI.Button(p, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, 0)
    local reset = UI.Button(p, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", -200, 0 }
        Apply()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

    local R = UI.Column(p, COL2_X, 0, COL_W)
    R:Header("All classes buffs")
    R:Cycle("Show them", {
        { value = "ROW", text = "In one All row" },
        { value = "MEMBERS", text = "In each member's row" },
    }, function() return M.db.allBar and "ROW" or "MEMBERS" end,
       function(v) M.db.allBar = (v == "ROW"); Apply() end)
    local who
    local function WhoText()
        local n = 0
        for _ in pairs(M.db.allExclude) do n = n + 1 end
        return n == 0 and "All row members: everyone" or ("All row members: %d left out"):format(n)
    end
    who = UI.Button(p, COL_W, WhoText(), function(self)
        local items = {}
        for _, key in ipairs(MMT.SortedMembers()) do
            local out = M.db.allExclude[key]
            items[#items + 1] = { value = key, text = (out and "|cff888888[  ] " or "|cff55ff55[x] ") .. MMT.FullDisplay(key) .. "|r" }
        end
        UI.OpenList(self, items, nil, function(key)
            M.db.allExclude[key] = (not M.db.allExclude[key]) or nil
            who.label:SetText(WhoText())
            Apply()
        end)
    end)
    UI.Tooltip(who, "All classes row members", "Click a name to leave it out of (or add it back to) the All classes row.")
    R:Add(who, UI.ROW + 2)
    R:Note("The All row turns red / grey when anyone in it misses a buff, otherwise it shows the shortest time left.")
    R:Header("Share")
    local half2 = (COL_W - 8) / 2
    local sendAll = UI.Button(p, half2, "Send to team", function()
        mod.SendAll()
        status.Show_("Everything sent; the team is asked before taking it over.")
    end)
    UI.Tooltip(sendAll, "Send to team", "Sends every setting of this module (bars, look, lists, window position) to the online team. Each client is asked first.")
    R:Add(sendAll, 0)
    local ie = UI.Button(p, half2, "Import / Export...", function() mod.OpenTransfer() end)
    ie:SetPoint("LEFT", sendAll, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)


    -- Look ------------------------------------------------------------------
    local LL = mod.LookTab(panels.look, Opt, Apply)
    LL:Header("Buffs")
    LL:Cycle("Missing buffs", {
        { value = "PLAIN", text = "Normal icon" },
        { value = "RED", text = "Red" },
        { value = "GREY", text = "Grey" },
        { value = "PLAIN+", text = "Normal icon + glow" },
        { value = "RED+", text = "Red + glow" },
        { value = "GREY+", text = "Grey + glow" },
    }, function()
        return (M.db.allMissingLook or "PLAIN") .. (M.db.glowMissing and "+" or "")
    end, function(v)
        M.db.allMissingLook = v:gsub("%+$", "")
        M.db.glowMissing = v:find("+", 1, true) ~= nil
        Apply()
    end)
    local gac, sac = Opt("activeAlpha")
    LL:Slider("Active opacity", 0, 1, 0.05, gac, sac, "%.2f")
    local gm, sm = Opt("missingAlpha")
    LL:Slider("Missing opacity", 0, 1, 0.05, gm, sm, "%.2f")

    -- Buffs (lists) -------------------------------------------------------------
    local lp = panels.lists
    local LS = UI.Column(lp, 0, 0, COL_W)
    local class = select(2, UnitClass("player")) or "ALL"
    LS:Header("Tracked buffs")
    local list
    LS:Cycle("List", mod.ListChoices, function() return class end, function(v) class = v; list:Render(M.db.lists[class] or {}) end)

    local function Changed()
        mod.BuildIndex()
        mod.ScanGroup()
        Apply()
        list:Render(M.db.lists[class] or {})
    end
    local function Move(index, delta)
        local l = M.db.lists[class]
        local j = index + delta
        if not l or j < 1 or j > #l then return end
        l[index], l[j] = l[j], l[index]
        Changed()
    end

    list = H.List(lp, COL_W, 14, 22, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        H.RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = UI.TextButton(row, "x", function() table.remove(M.db.lists[class], row.index); Changed() end, 16)
        row.del:SetPoint("RIGHT", -2, 0)
        row.down = UI.TextButton(row, "v", function() Move(row.index, 1) end, 16)
        row.down:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
        row.up = UI.TextButton(row, "^", function() Move(row.index, -1) end, 16)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        -- on / off: switched-off entries stay in the list but aren't tracked
        row.toggle = UI.TextButton(row, "", function()
            local e = M.db.lists[class][row.index]
            if e then e.off = (not e.off) or nil; Changed() end
        end, 26)
        row.toggle:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
        UI.Tooltip(row.toggle, "On / off", "Switched-off entries stay in the list but aren't tracked.")
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.toggle, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.entry.id)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, e, index)
        row.entry, row.index = e, index
        row.icon:SetTexture(mod.EntryIcon(e))
        row.name:SetText(mod.EntryName(e))
        row.toggle.label:SetText(e.off and "|cff777777off|r" or "|cff55ff55on|r")
        row.icon:SetDesaturated(e.off and true or false)
        row.name:SetTextColor(e.off and 0.5 or 1, e.off and 0.5 or 1, e.off and 0.5 or 1)
    end)
    LS:Add(list, 14 * 22 + 6)

    local box
    local function Add()
        local id = mod.ParseEntry(box:GetText())
        if not id then status.Show_("Unknown spell. Use its ID or shift-click it in the spellbook.", true) return end
        M.db.lists[class] = M.db.lists[class] or {}
        table.insert(M.db.lists[class], { id = id })
        box:SetText("")
        box:ClearFocus()
        status.Show_(("Added %s."):format(mod.EntryName({ id = id })))
        Changed()
    end
    box = UI.EditBox(lp, COL_W - 58, "Buff name, ID or shift-click", function() Add() end)
    local function OnLink(link)
        if type(link) == "string" and link:find("|Hspell:", 1, true) and box:IsVisible() and box:HasFocus() then
            box:SetText(link); box:UpdatePlaceholder()
        end
    end
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnLink) end
    LS:Add(box, 0)
    local add = UI.Button(lp, 54, "Add", Add)
    add:SetPoint("LEFT", box, "RIGHT", 4, 0)

    local RS = UI.Column(lp, COL2_X, 0, COL_W)
    RS:Header("How lists work")
    RS:Note("Lists per class, MMT role or character: a member tracks all lists that fit (class, All classes, their roles, their character). Any rank and the group version (Prayer of Fortitude, Greater Blessings, ...) count.")
    RS:Button("Add preset entries", function()
        local preset = mod.DEFAULT_LISTS[class]
        if not preset then status.Show_("There is no preset for this list.", true) return end
        local n = mod.AddPreset(class, preset, function(e) return e.id end)
        status.Show_(n > 0 and ("Added %d preset entries."):format(n) or "This list already has every preset entry.")
        Changed()
    end)
    RS:Header("Lists")
    local def = H.ConfirmButton(lp, COL_W, "Reset all lists to defaults", function()
        M.db.lists = MMT.CopyTable(mod.DEFAULT_LISTS)
        status.Show_("Lists reset.")
        Changed()
    end)
    RS:Add(def, UI.ROW + 2)

    page.OnRefresh = function()
        list:Render(M.db.lists[class] or {})
        who.label:SetText(WhoText())
    end
end

M.Report = function(_, add)
    local n = 0
    for _, l in pairs(M.db.lists or {}) do n = n + #l end
    add(("-- Buffs %s: shown=%s attach=%s attached=%s entries=%d"):format(mod.VERSION, tostring(M.db.shown),
        tostring(M.db.attach), tostring(mod.Attached()), n))
    for key, t in pairs(mod.auras) do
        local names = {}
        for name in pairs(t) do names[#names + 1] = name end
        add(("buffs %s (unit): %s"):format(MMT.Repr(key), table.concat(names, ", ")))
    end
end
