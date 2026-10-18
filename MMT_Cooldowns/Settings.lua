-- MMT Cooldowns: settings page (MODULES > Cooldowns in /mmt) and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local CLASS_NAMES = { ALL = "All classes (trinkets, potions)" }

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v; mod.window:Refresh() end
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
    Check(L, "Show the window", "shown")
    Check(L, "Lock position", "locked")
    Check(L, "Click-through", "clickThrough", "Mouse clicks go through the window (no tooltips, no dragging).")
    Check(L, "Members side by side", "vertical", "Off: one row per member. On: one column per member.")
    Check(L, "Include your own character", "includeSelf")
    Check(L, "Only online or grouped members", "onlyOnline")
    Check(L, "Show names", "showNames")
    Check(L, "Show timers", "showTimers")
    Check(L, "Glow while waiting for the buff", "glowActive", "Nature's Swiftness, Presence of Mind, ...: their cooldown starts when the buff is used.")
    Check(L, "Items only after first use", "itemsOnlyWhenSeen", "Trinkets and potions of other members show up once you have seen them used.")
    L:Header("Look")
    local gi, si = Opt("iconSize")
    L:Slider("Icon size", 16, 48, 1, gi, si)
    local gs, ss = Opt("scale")
    L:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gr, sr = Opt("readyAlpha")
    L:Slider("Ready opacity", 0, 1, 0.05, gr, sr, "%.2f")
    local gc, sc = Opt("cdAlpha")
    L:Slider("On cooldown opacity", 0, 1, 0.05, gc, sc, "%.2f")
    local gb, sb = Opt("bgAlpha")
    L:Slider("Background", 0, 1, 0.05, gb, sb, "%.2f")
    local half = (COL_W - 8) / 2
    local test = UI.Button(page, half, "Test (10 s)", function() mod.Test() end)
    L:Add(test, 0)
    local reset = UI.Button(page, half, "Reset position", function()
        M.db.point = { "CENTER", "CENTER", 200, 0 }
        mod.window:Refresh()
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)

    -- right: tracked lists ---------------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    local class = select(2, UnitClass("player")) or "ALL"
    R:Header("Tracked spells & items")
    local choices = {}
    for _, c in ipairs(mod.CLASSES) do
        local name = CLASS_NAMES[c] or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c
        choices[#choices + 1] = { value = c, text = name }
    end
    local list
    R:Cycle("Class", choices, function() return class end, function(v) class = v; list:Render(M.db.lists[class] or {}) end)

    local function Changed()
        mod.BuildIndex()
        mod.window:Refresh()
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
        row.cd = UI.Label(row, "")
        row.cd:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
        row.cd:SetTextColor(0.6, 0.6, 0.6)
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.cd, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.entry.t == "s" then GameTooltip:SetSpellByID(self.entry.id) else GameTooltip:SetItemByID(self.entry.id) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, e, index)
        row.entry, row.index = e, index
        row.icon:SetTexture(mod.EntryIcon(e))
        row.name:SetText(mod.EntryName(e))
        row.cd:SetText((e.cd or 0) .. "s")
    end)
    R:Add(list, 9 * 22 + 6)

    -- add: name / ID / shift-click a spell or item, and the cooldown in seconds
    local box, secs
    local function Add()
        local t, id = mod.ParseEntry(box:GetText())
        if not t then status.Show_("Unknown spell or item. Use its ID or shift-click it.", true) return end
        local cd = tonumber(secs:GetText()) or mod.BaseCooldown(t, id)
        if not cd then status.Show_("Enter the cooldown in seconds.", true) return end
        M.db.lists[class] = M.db.lists[class] or {}
        table.insert(M.db.lists[class], { t = t, id = id, cd = cd })
        box:SetText(""); secs:SetText("")
        box:ClearFocus(); secs:ClearFocus()
        status.Show_(("Added %s (%ds)."):format(mod.EntryName({ t = t, id = id }), cd))
        Changed()
    end
    local function Prefill()
        local t, id = mod.ParseEntry(box:GetText())
        local cd = t and mod.BaseCooldown(t, id)
        if cd and secs:GetText() == "" then secs:SetText(tostring(cd)); secs:UpdatePlaceholder() end
    end
    box = UI.EditBox(page, COL_W - 112, "Name, ID or shift-click", function() Add() end)
    secs = UI.EditBox(page, 50, "sec", function() Add() end)
    UI.AcceptItemLinks(box, Prefill)
    -- spell links (shift-click in the spellbook) go into the box too
    local function OnLink(link)
        if type(link) == "string" and link:find("|Hspell:", 1, true) and box:IsVisible() and box:HasFocus() then
            box:SetText(link); box:UpdatePlaceholder(); Prefill()
        end
    end
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnLink) end
    box:HookScript("OnEditFocusLost", Prefill)
    R:Add(box, 0)
    secs:SetPoint("LEFT", box, "RIGHT", 4, 0)
    local add = UI.Button(page, 54, "Add", Add)
    add:SetPoint("LEFT", secs, "RIGHT", 4, 0)
    R:Space(UI.ROW + 4)
    R:Note("Each client sends one short message when its character uses a tracked cooldown (needs Cooldowns on that client too). Group members are also seen directly.")
    R:Button("Send lists to team", function()
        mod.SendLists()
        status.Show_("Lists sent to the online team.")
    end)
    local def = H.ConfirmButton(page, COL_W, "Reset all lists to defaults", function()
        M.db.lists = MMT.CopyTable(mod.DEFAULT_LISTS)
        status.Show_("Lists reset.")
        Changed()
    end)
    R:Add(def, UI.ROW + 2)
    status = H.StatusLine(page)
    status:SetWidth(COL_W)
    R:Add(status, 30)

    page.OnRefresh = function() list:Render(M.db.lists[class] or {}) end
end

M.Report = function(_, add)
    local n = 0
    for _, l in pairs(M.db.lists or {}) do n = n + #l end
    add(("-- Cooldowns %s: shown=%s entries=%d"):format(mod.VERSION, tostring(M.db.shown), n))
    for key, cds in pairs(mod.cds) do
        local t = {}
        for ek, c in pairs(cds) do t[#t + 1] = ek .. (c.pending and "(buff)" or "") end
        if #t > 0 then add(("cooldowns %s: %s"):format(MMT.Repr(key), table.concat(t, " "))) end
    end
end
