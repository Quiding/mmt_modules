-- MMT Totems: preset manager (popup window): individual presets per shaman
-- and team presets; save the current totems, apply, delete, and edit a
-- preset's totems, sequence and icon.

local _, mod = ...
local MMT = MMT
local M = mod.M

local W, H = 470, 500
local dialog

local function AllShamans()
    local list = {}
    for _, key in ipairs(MMT.SortedMembers()) do
        if mod.IsShaman(key) then list[#list + 1] = key end
    end
    local own = mod.OwnKey()
    if mod.IsShaman(own) and not MMT.db.team[own] then table.insert(list, 1, own) end
    return list
end

local function Build()
    local UI, Hp = MMT.UI, MMT.ConfigHelpers
    local f = CreateFrame("Frame", "MMTTotemsPresets", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Fill(f, 0.06, 0.06, 0.07, 0.97)
    UI.Border(f, 0.3, 0.3, 0.3, 1)
    UI.CloseOnEscape(f)
    local title = UI.Label(f, "Totem presets", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end, 18)
    close:SetPoint("TOPRIGHT", -6, -6)

    local st = { mode = "SHAMAN", key = nil, edit = nil, member = nil }
    f.st = st
    local CW = W - 24
    local col = UI.Column(f, 12, -34, CW)
    local half = (CW - 8) / 2

    local status = Hp.StatusLine(f)
    status:SetPoint("BOTTOMLEFT", 12, 10)
    status:SetPoint("BOTTOMRIGHT", -12, 10)
    local function Status(t, bad) status.Show_(t, bad) end

    -- what: one shaman's presets or team presets -------------------------
    local refresh
    local modeDD = UI.Dropdown(f, half, "Presets", {
        { value = "SHAMAN", text = "Per shaman" },
        { value = "TEAM", text = "Team" },
    }, function() return st.mode end, function(v) st.mode = v; st.edit = nil; refresh() end)
    col:Add(modeDD, 0)
    local shamanDD = UI.Dropdown(f, half, "Shaman", function()
        local t = {}
        for _, k in ipairs(AllShamans()) do t[#t + 1] = { value = k, text = MMT.FirstName(k) } end
        return t
    end, function() return st.key end, function(v) st.key = v; st.edit = nil; refresh() end)
    shamanDD:SetPoint("LEFT", modeDD, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    local function Source()
        if st.mode == "TEAM" then return M.db.teamPresets end
        return st.key and (M.db.presets[st.key] or {}) or {}
    end

    -- list -----------------------------------------------------------------
    local list = Hp.List(f, CW, 6, 24, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        Hp.RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = UI.TextButton(row, "|cffff5555Delete|r", function()
            if st.mode == "TEAM" then mod.DeleteTeamPreset(row.name_) else mod.DeletePreset(st.key, row.name_) end
            if st.edit == row.name_ then st.edit = nil end
            Status(("Deleted \"%s\"."):format(row.name_))
            refresh()
        end, 50)
        row.del:SetPoint("RIGHT", -2, 0)
        row.edit = UI.TextButton(row, "Edit", function() st.edit = row.name_; st.member = nil; refresh() end, 40)
        row.edit:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        row.apply = UI.TextButton(row, "|cff55ff55Apply|r", function()
            if st.mode == "TEAM" then mod.ApplyTeamPreset(row.name_) else mod.ApplyPreset(st.key, row.name_) end
            Status(("Applied \"%s\"."):format(row.name_))
        end, 46)
        row.apply:SetPoint("RIGHT", row.edit, "LEFT", -4, 0)
        row.label = UI.Label(row, "")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row.apply, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        return row
    end, function(row, name)
        row.name_ = name
        local p = Source()[name]
        row.icon:SetTexture(p and p.icon or mod.PRESET_ICON)
        row.label:SetText((name == st.edit) and ("|cffffff00" .. name .. "|r") or name)
    end)
    col:Add(list, 6 * 24 + 6)

    -- save current -----------------------------------------------------------
    local nameBox = UI.EditBox(f, CW - 128, "New preset name", function() end)
    col:Add(nameBox, 0)
    local save = UI.Button(f, 120, "Save current", function()
        local ok, msg
        if st.mode == "TEAM" then ok, msg = mod.SaveTeamPreset(nameBox:GetText())
        else ok, msg = mod.SavePreset(st.key, nameBox:GetText()) end
        Status(msg, not ok)
        if ok then nameBox:SetText(""); nameBox:ClearFocus(); refresh() end
    end)
    save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    col:Space(UI.ROW + 8)

    -- editor -------------------------------------------------------------------
    local editTitle = col:Header("Edit preset")
    local function Entry()
        local p = st.edit and Source()[st.edit]
        if not p then return nil end
        if st.mode ~= "TEAM" then return p end
        if not st.member then return nil end
        p.members = p.members or {}
        p.members[st.member] = p.members[st.member] or { totems = {} }
        return p.members[st.member]
    end

    local iconBox = UI.EditBox(f, CW - 128, "Icon: spell / item name or ID", function(text)
        local p = st.edit and Source()[st.edit]
        if not p then return end
        local icon = mod.FindIcon(text)
        if not icon then Status("Icon not found.", true) return end
        p.icon = icon
        refresh()
    end)
    col:Add(iconBox, 0)
    local memberDD = UI.Dropdown(f, 120, "Shaman", function()
        local t = {}
        for _, k in ipairs(AllShamans()) do t[#t + 1] = { value = k, text = MMT.FirstName(k) } end
        return t
    end, function() return st.member end, function(v) st.member = v; refresh() end)
    memberDD:SetPoint("LEFT", iconBox, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    local dds = {}
    for i, el in ipairs(mod.ELEMENTS) do
        local dd = UI.Dropdown(f, half, el, function()
            local t = { { value = 0, text = "None" } }
            for _, id in ipairs(mod.ElementTotems(el)) do t[#t + 1] = { value = id, text = mod.TotemName(id) } end
            return t
        end, function()
            local e = Entry()
            return e and e.totems and e.totems[el] or 0
        end, function(v)
            local e = Entry()
            if not e then return end
            e.totems = e.totems or {}
            e.totems[el] = (v ~= 0) and v or nil
            refresh()
        end)
        if i % 2 == 1 then col:Add(dd, 0) else dd:SetPoint("LEFT", dds[i - 1], "RIGHT", 8, 0); col:Space(UI.ROW + 4) end
        dds[i] = dd
    end
    local seqBox = UI.EditBox(f, CW, "Sequence, e.g. Fire, Air, Water, Earth (Enter)", function(text)
        local e = Entry()
        if not e then return end
        e.sequence = text ~= "" and text or nil
        Status("Sequence saved in the preset.")
    end)
    col:Add(seqBox, UI.ROW + 4)

    refresh = function()
        if st.mode ~= "TEAM" and not st.key then st.key = AllShamans()[1] end
        shamanDD:SetShown(st.mode ~= "TEAM")
        modeDD.Refresh(); shamanDD.Refresh()
        local names = {}
        for name in pairs(Source()) do names[#names + 1] = name end
        table.sort(names)
        list:Render(names)
        local p = st.edit and Source()[st.edit]
        editTitle:SetText(p and ("Edit preset: |cffffff00" .. st.edit .. "|r") or "Edit preset (click Edit on a preset)")
        memberDD:SetShown(p ~= nil and st.mode == "TEAM")
        memberDD.Refresh()
        local e = Entry()
        local on = e ~= nil
        iconBox:SetShown(p ~= nil)
        for _, dd in ipairs(dds) do dd:SetShown(on); dd.Refresh() end
        seqBox:SetShown(on)
        if on and not seqBox:HasFocus() then seqBox:SetText(e.sequence or ""); seqBox:UpdatePlaceholder() end
        if p and st.mode == "TEAM" and not st.member then
            Status("Choose a shaman to edit their part of the team preset.")
        end
    end
    f.Refresh = refresh
    return f
end

function mod.OpenPresets()
    dialog = dialog or Build()
    dialog:SetScale((MMT.ConfigScale and MMT.ConfigScale()) or 1)
    dialog.Refresh()
    dialog:Show()
    dialog:Raise()
end
