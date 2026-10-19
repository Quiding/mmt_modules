-- Settings helpers shared by MMT_Cooldowns and MMT_Buffs (they ship the same
-- copy of this file: KEEP BOTH IDENTICAL):
--   mod.Tabs(page, { {id, text}, ... })  -> panels[id]   tab buttons like /mmt > Help
--   mod.ShareBar(page, status)             bottom bar on every tab: Import / Export
--                                          left, the core's "Sync to team" right
--   mod.LookTab(panel, Opt, apply)         -> left column, for the module's own look options
-- Opt(key) returns getter, setter for M.db[key]; apply() redraws.

local _, mod = ...
local MMT = MMT

local current = {}   -- [page] = selected tab id (kept while the game runs)
local BOTTOM = 50    -- room below the tabs' panels: status line + share bar

function mod.Tabs(page, list)
    local UI = MMT.UI
    local W = MMT.ConfigHelpers.PAGE_W
    local panels, buttons = {}, {}
    local bw = math.floor((W - 8 * (#list - 1)) / #list)
    local function Show(id)
        current[mod] = id
        for k, p in pairs(panels) do p:SetShown(k == id) end
        for k, b in pairs(buttons) do
            if k == id then b.label:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
            else b.label:SetTextColor(0.7, 0.7, 0.7) end
        end
    end
    for i, t in ipairs(list) do
        local b = UI.Button(page, bw, t[2], function() Show(t[1]) end)
        b:SetPoint("TOPLEFT", (i - 1) * (bw + 8), 0)
        buttons[t[1]] = b
        local p = CreateFrame("Frame", nil, page)
        p:SetPoint("TOPLEFT", 0, -30)
        p:SetSize(W, math.max(100, (page:GetHeight() or 560) - 30 - BOTTOM))
        panels[t[1]] = p
    end
    Show(current[mod] and panels[current[mod]] and current[mod] or list[1][1])
    return panels
end

-- the share bar at the bottom of the page, like the tab buttons at the top:
-- Import / Export in the bottom left; the core puts its "Sync to team"
-- button (sync = true in NewModule) in the bottom right after M.Page
function mod.ShareBar(page, status)
    local UI = MMT.UI
    local W = MMT.ConfigHelpers.PAGE_W
    local ie = UI.Button(page, 176, "Import / Export...", function() mod.OpenTransfer() end)
    ie:SetPoint("BOTTOMLEFT", 0, 2)
    UI.Tooltip(ie, "Import / Export", "Choose parts and copy them as a text string, or paste one to take it over.")
    status:ClearAllPoints()
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(W)
    return ie
end

-- shift-clicking a spell (spellbook, chat link) while box has focus puts the
-- link into it. This client sends links through ChatFrameUtil.InsertLink (the
-- old ChatEdit_InsertLink is only a fallback), so hook whichever exists, once.
local spellBoxes, spellHooked = {}, false
local function OnInsertLink(link)
    if type(link) ~= "string" or not link:find("|Hspell:", 1, true) then return end
    for box, onLink in pairs(spellBoxes) do
        if box:IsVisible() and box:HasFocus() then
            box:SetText(link)
            if box.UpdatePlaceholder then box:UpdatePlaceholder() end
            if onLink then onLink(link, box) end
            return
        end
    end
end
function mod.AcceptSpellLinks(box, onLink)
    spellBoxes[box] = onLink or false
    if spellHooked then return end
    spellHooked = true
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
    elseif ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
end

-- preset picker for the list editor: a dropdown + Add to list / Replace list.
-- listKey() = the list being edited, id(e) tells entries apart, changed() redraws
function mod.PresetBox(col, parent, listKey, id, changed, status)
    local UI, H = MMT.UI, MMT.ConfigHelpers
    local COL_W = H.COL_W
    local chosen, chosenFor
    local function Current()
        if chosenFor ~= listKey() or not chosen then chosen, chosenFor = mod.DefaultPreset(listKey()), listKey() end
        return chosen
    end
    col:Header("Presets")
    col:Cycle("Preset", function() return mod.PresetChoices(listKey()) end, Current,
        function(v) chosen, chosenFor = v, listKey() end)
    local half = (COL_W - 8) / 2
    local add = UI.Button(parent, half, "Add to list", function()
        local p = mod.PresetByKey(Current())
        if not p then return end
        local n = mod.ApplyPreset(listKey(), p.key, false, id)
        status.Show_(n > 0 and ("Added %d entries from \"%s\"."):format(n, p.name) or "The list already has every entry of that preset.")
        changed()
    end)
    UI.Tooltip(add, "Add to list", "Adds the preset's entries this list doesn't have yet (on or off as in the preset). Your own entries stay.")
    col:Add(add, 0)
    local replace = H.ConfirmButton(parent, half, "Replace list", function()
        local p = mod.PresetByKey(Current())
        if not p then return end
        mod.ApplyPreset(listKey(), p.key, true, id)
        status.Show_(("The list is now \"%s\"."):format(p.name))
        changed()
    end)
    replace:SetPoint("LEFT", add, "RIGHT", 8, 0)
    col:Space(UI.ROW + 2)
end

-- texture choices from LibSharedMedia (brought by other addons), plus a plain one
function mod.MediaChoices(kind, plainValue, plainText)
    local t = { { value = plainValue, text = plainText } }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List(kind)) do
            if name ~= "None" then t[#t + 1] = { value = name, text = name } end
        end
    end
    return t
end

local function FontChoices()
    local t = { { value = "", text = "Game font" } }
    for _, f in ipairs(MMT.fonts or {}) do t[#t + 1] = { value = f.name, text = f.name } end
    return t
end

local function Color(col, text, M, key, apply)
    col:Color(text, function() return M.db[key] end, function(c)
        M.db[key] = { r = c.r, g = c.g, b = c.b }
        apply()
    end)
end

-- sizes, text, background, border, member rows; returns the left column
function mod.LookTab(panel, Opt, apply)
    local UI, H = MMT.UI, MMT.ConfigHelpers
    local M = mod.M
    local COL_W, COL2_X = H.COL_W, H.COL2_X

    local L = UI.Column(panel, 0, 0, COL_W)
    L:Header("Size")
    local gi, si = Opt("iconSize")
    L:Slider("Icon size", 16, 64, 1, gi, si)
    local gs, ss = Opt("scale")
    L:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gsp, ssp = Opt("spacing")
    L:Slider("Icon spacing", 0, 20, 1, gsp, ssp)
    local grg, srg = Opt("rowGap")
    L:Slider("Row spacing", 0, 30, 1, grg, srg)
    L:Header("Text")
    L:Cycle("Font", FontChoices, function() return M.db.font or "" end, function(v)
        M.db.font = (v ~= "") and v or nil
        apply()
    end)
    local gt, st = Opt("timerSize")
    L:Slider("Timer size", 8, 32, 1, gt, st)
    Color(L, "Timer colour", M, "timerColor", apply)
    local gn, sn = Opt("nameSize")
    L:Slider("Name size", 8, 20, 1, gn, sn)

    local R = UI.Column(panel, COL2_X, 0, COL_W)
    R:Header("Background")
    R:Cycle("Texture", function() return mod.MediaChoices("background", "FLAT", "Flat") end, Opt("bgTexture"))
    Color(R, "Colour", M, "bgColor", apply)
    local gti, sti = Opt("bgTint")
    R:Slider("Colour strength", 0, 1, 0.05, gti, sti, "%.2f")
    local gb, sb = Opt("bgAlpha")
    R:Slider("Opacity", 0, 1, 0.05, gb, sb, "%.2f")
    R:Header("Border")
    R:Cycle("Texture", function() return mod.MediaChoices("border", "NONE", "None") end, Opt("borderTexture"))
    Color(R, "Colour", M, "borderColor", apply)
    local gz, sz = Opt("borderSize")
    R:Slider("Size", 4, 32, 1, gz, sz)
    R:Header("Member rows")
    Color(R, "Row background", M, "rowColor", apply)
    local gr, sr = Opt("rowAlpha")
    R:Slider("Row opacity", 0, 1, 0.05, gr, sr, "%.2f")
    R:Note("Textures come from LibSharedMedia (other addons such as Details bring many).")
    return L
end
