-- MMT Buffs: settings page (MODULES > Buffs in /mmt) and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v; mod.Apply() end
end

-- checkbox for a setting (Opt can't be followed by more arguments)
local function Check(col, text, key, tip)
    local g, s = Opt(key)
    col:Check(text, g, s, tip)
end

M.Page = function(_, page)
    local status
    -- left: window ------------------------------------------------------
    local L = UI.Column(page, 0, 0, COL_W)
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
    Check(L, "Members side by side", "vertical", "Off: one row per member. On: one column per member.")
    Check(L, "Include your own character", "includeSelf")
    Check(L, "Only online or grouped members", "onlyOnline")
    Check(L, "Show names", "showNames")
    Check(L, "Show timers", "showTimers")
    Check(L, "Glow when a buff is missing", "glowMissing")
    L:Header("Look")
    local gi, si = Opt("iconSize")
    L:Slider("Icon size", 16, 48, 1, gi, si)
    local gs, ss = Opt("scale")
    L:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gm, sm = Opt("missingAlpha")
    L:Slider("Missing opacity", 0, 1, 0.05, gm, sm, "%.2f")
    local gb, sb = Opt("bgAlpha")
    L:Slider("Background", 0, 1, 0.05, gb, sb, "%.2f")
    L:Header("Text")
    local gts, sts = Opt("timerSize")
    L:Slider("Timer size", 8, 28, 1, gts, sts)
    local gns, sns = Opt("nameSize")
    L:Slider("Name size", 8, 20, 1, gns, sns)
    local half = (COL_W - 8) / 2
    local test = UI.Button(page, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, 0)
    local reset = UI.Button(page, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", -200, 0 }
        mod.Apply()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

    -- right: tracked lists ---------------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    local class = select(2, UnitClass("player")) or "ALL"
    R:Header("Tracked buffs")
    R:Note("Lists per class, MMT role or character: a member tracks all lists that fit. Any rank and the group version (Prayer of Fortitude, ...) count.")
    local list
    R:Cycle("List", mod.ListChoices, function() return class end, function(v) class = v; list:Render(M.db.lists[class] or {}) end)

    local function Changed()
        mod.BuildIndex()
        mod.ScanGroup()
        mod.Apply()
        list:Render(M.db.lists[class] or {})
    end
    local function Move(index, delta)
        local l = M.db.lists[class]
        local j = index + delta
        if not l or j < 1 or j > #l then return end
        l[index], l[j] = l[j], l[index]
        Changed()
    end

    list = H.List(page, COL_W, 9, 22, function(parent, i)
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
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
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
    end)
    R:Add(list, 9 * 22 + 6)

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
    box = UI.EditBox(page, COL_W - 58, "Buff name, ID or shift-click", function() Add() end)
    local function OnLink(link)
        if type(link) == "string" and link:find("|Hspell:", 1, true) and box:IsVisible() and box:HasFocus() then
            box:SetText(link); box:UpdatePlaceholder()
        end
    end
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnLink) end
    R:Add(box, 0)
    local add = UI.Button(page, 54, "Add", Add)
    add:SetPoint("LEFT", box, "RIGHT", 4, 0)
    R:Space(UI.ROW + 4)
    R:Button("Send lists to team", function()
        mod.SendLists()
        status.Show_("Lists sent to the online team.")
    end)
    R:Button("Import / Export...", function() mod.OpenTransfer() end)
    local def = H.ConfirmButton(page, COL_W, "Reset all lists to defaults", function()
        M.db.lists = MMT.CopyTable(mod.DEFAULT_LISTS)
        status.Show_("Lists reset.")
        Changed()
    end)
    R:Add(def, UI.ROW + 2)

    -- All classes row ----------------------------------------------------
    R:Header("All classes row")
    local gb2, sb2 = Opt("allBar")
    R:Check("Show the All classes row", gb2, sb2, "One row for the \"All classes\" buffs of the whole team; they leave the members' own rows.")
    local gl, sl = Opt("allMissingLook")
    R:Cycle("Someone misses it", {
        { value = "RED", text = "Red" },
        { value = "GREY", text = "Grey" },
    }, gl, sl)
    local who
    local function WhoText()
        local n = 0
        for _ in pairs(M.db.allExclude) do n = n + 1 end
        return n == 0 and "Members: everyone" or ("Members: %d left out"):format(n)
    end
    who = UI.Button(page, COL_W, WhoText(), function(self)
        local items = {}
        for _, key in ipairs(MMT.SortedMembers()) do
            local out = M.db.allExclude[key]
            items[#items + 1] = { value = key, text = (out and "|cff888888[  ] " or "|cff55ff55[x] ") .. MMT.FullDisplay(key) .. "|r" }
        end
        UI.OpenList(self, items, nil, function(key)
            M.db.allExclude[key] = (not M.db.allExclude[key]) or nil
            who.label:SetText(WhoText())
            mod.Apply()
        end)
    end)
    UI.Tooltip(who, "All classes row members", "Click a name to leave it out of (or add it back to) the All classes row.")
    R:Add(who, UI.ROW + 2)

    status = H.StatusLine(page)
    status:SetWidth(COL_W)
    R:Add(status, 30)

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
