-- MMT Buffs: settings page (MODULES > Buffs in /mmt) and debug report.
-- Tabs: Bars (what is shown) / Look (sizes, text, background, border,
-- missing buffs) / Buffs (the tracked lists, the All bar, sharing) /
-- Roles (each member's player role for "Only for", Roles.lua).

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

---------------------------------------------------------------------------
-- "Only for" popup (the cog of a buff in the list editor)
---------------------------------------------------------------------------
local filterPopup

-- closes the popup (another list, tab or page, the list changed)
function mod.CloseFilter()
    if filterPopup then filterPopup:Hide() end
end

local function Ticked(e, kind, k)
    return e.only and e.only[kind] and e.only[kind][k] and true or false
end

local function Tick(e, kind, k, on)
    e.only = e.only or {}
    e.only[kind] = e.only[kind] or {}
    e.only[kind][k] = on or nil
    if not next(e.only[kind]) then e.only[kind] = nil end
    if not next(e.only) then e.only = nil end
end

-- e = the list entry (changed in place); changed() redraws the list and the bars
function mod.OpenFilter(e, owner, changed)
    local UI = MMT.UI
    if filterPopup then filterPopup:Hide() end
    local f = CreateFrame("Frame", nil, UIParent)
    filterPopup = f
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    -- belongs to UIParent: same scale as the settings window it opens from
    local own, parent = owner and owner.GetEffectiveScale and owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
    f:SetScale((own and parent and parent > 0) and own / parent or 1)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    UI.Fill(f, 0.07, 0.07, 0.08, 0.98)
    UI.Border(f, UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.5)
    UI.CloseOnEscape(f)
    local W = 160
    local title = UI.Label(f, "Only for: " .. mod.EntryName(e), "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -10)
    local note = UI.Label(f, "Nothing ticked: everyone. Ticked: members matching any of them; the others don't count as missing it. Specs: set on the Specs tab, else from the talents.")
    note:SetPoint("TOPLEFT", 10, -28)
    note:SetWidth(3 * W + 20)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.6, 0.6, 0.6)
    local close = UI.TextButton(f, "x", function() f:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -4, -4)
    local function Column(x, header, items, kind)
        local h = UI.Label(f, header, "GameFontNormal")
        h:SetPoint("TOPLEFT", x, -58)
        local y = -78
        for _, it in ipairs(items) do
            local c = UI.Check(f, W - 10, it[2], function() return Ticked(e, kind, it[1]) end, function(v)
                Tick(e, kind, it[1], v)
                if changed then changed() end
            end)
            c:SetPoint("TOPLEFT", x, y)
            c.Refresh()
            y = y - 20
        end
        return y
    end
    local classes = {}
    for _, c in ipairs(mod.CLASSES) do if c ~= "ALL" then classes[#classes + 1] = { c, mod.ListLabel(c) } end end
    local roles = {}
    for _, r in ipairs(MMT.SortedRoleNames and MMT.SortedRoleNames() or {}) do roles[#roles + 1] = { r, r } end
    local y1 = Column(10, "Player roles", mod.PLAYER_ROLES, "roles")
    local y2 = Column(10 + W, "Classes", classes, "classes")
    local y3 = Column(10 + 2 * W, "MMT roles", roles, "mmt")
    if #roles == 0 then
        local none = UI.Label(f, "None yet: /mmt > Roles.")
        none:SetPoint("TOPLEFT", 10 + 2 * W, -78)
        none:SetTextColor(0.6, 0.6, 0.6)
    end
    -- specs (set by hand on the Specs tab, else the talents), three columns below
    local top = math.min(y1, y2, y3) - 8
    local sh = UI.Label(f, "Specs", "GameFontNormal")
    sh:SetPoint("TOPLEFT", 10, top)
    local specs = mod.AllSpecs()
    local per = math.ceil(#specs / 3)
    local y4 = top
    for i, sp in ipairs(specs) do
        local col, row = math.floor((i - 1) / per), (i - 1) % per
        local c = UI.Check(f, W - 10, sp[2], function() return Ticked(e, "specs", sp[1]) end, function(v)
            Tick(e, "specs", sp[1], v)
            if changed then changed() end
        end)
        c:SetPoint("TOPLEFT", 10 + col * W, top - 20 - row * 20)
        c.Refresh()
        y4 = math.min(y4, top - 20 - (row + 1) * 20)
    end
    f:SetSize(3 * W + 20, -y4 + 10)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", 4, 0)
    f:Show()
    return f
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 0)
    status:SetWidth(H.PAGE_W)
    local panels = mod.Tabs(page, { { "bars", "Bars" }, { "look", "Look" }, { "lists", "Buffs" }, { "roles", "Roles" }, { "specs", "Specs" } })
    mod.ShareBar(page, status)

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
    Check(L, "Hide buffs not learned yet", "hideUnlearned", "A class buff a character hasn't learned yet (Inner Fire, a seal, an armor) leaves their row; a buff cast on others (Fortitude, Blessings, ...) only shows while someone here has learned it. Each client tells the team what it hasn't learned; flasks and world buffs always show.")
    Check(L, "One blessing per paladin", "blessingLimit", "A member can have one blessing from each paladin: once they have as many blessings as there are paladins in the group, the other blessings tracked for them don't count as missing. Blessings from paladins outside the group don't use up a slot. Salvation isn't a blessing on Forever and always counts.")
    Check(L, "Hide buffs nobody here can cast", "hideNoCaster", "A class buff (Fortitude, Mark of the Wild, Blessings, Arcane Intellect, ...) only shows when someone of that class is in your group or online in your team. World buffs, flasks and food always show.")
    L:Cycle("Preview", {
        { value = "OFF", text = "Off" },
        { value = "REAL", text = "The team as it is" },
        { value = "MIXED", text = "Mixed classes" },
        { value = "ALL", text = "All classes (made-up names)" },
    }, function() return mod.preview or "OFF" end, function(v) mod.SetPreview(v ~= "OFF" and v or nil) end)
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
    R:Header("All bar")
    R:Cycle("Show its buffs", {
        { value = "ROW", text = "In one All bar" },
        { value = "MEMBERS", text = "In each member's row" },
    }, function() return M.db.allBar and "ROW" or "MEMBERS" end,
       function(v) M.db.allBar = (v == "ROW"); Apply() end)
    local who
    local function WhoText()
        local n = 0
        for _ in pairs(M.db.allExclude) do n = n + 1 end
        return n == 0 and "All bar members: everyone" or ("All bar members: %d left out"):format(n)
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
    UI.Tooltip(who, "All bar members", "Click a name to leave it out of (or add it back to) the All bar.")
    R:Add(who, UI.ROW + 2)
    R:Note("The All bar turns red / grey when anyone in it misses a buff, otherwise it shows the shortest time left.")


    -- Look ------------------------------------------------------------------
    local LL, LR = mod.LookTab(panels.look, Opt, Apply)
    LR:Header("All bar counter")
    local gcp, scp = Opt("allCount")
    LR:Cycle("Have / checked (while missing)", {
        { value = "OFF", text = "Off" },
        { value = "BOTTOMLEFT", text = "Bottom left" },
        { value = "BOTTOMRIGHT", text = "Bottom right" },
        { value = "TOPLEFT", text = "Top left" },
        { value = "TOPRIGHT", text = "Top right" },
    }, gcp, scp)
    local gcs, scs = Opt("allCountSize")
    LR:Slider("Counter size", 8, 24, 1, gcs, scs)
    LR:Color("Counter colour", function() return M.db.allCountColor end, function(c)
        M.db.allCountColor = { r = c.r, g = c.g, b = c.b }
        Apply()
    end)
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

    -- Roles -----------------------------------------------------------------------
    local rp = panels.roles
    local RL = UI.Column(rp, 0, 0, COL_W)
    RL:Header("Player roles")
    local function Who()
        local t, seen = {}, {}
        local own = MMT.PlayerFull()
        if own then t[1] = own; seen[own] = true end
        for _, key in ipairs(MMT.SortedMembers()) do if not seen[key] then t[#t + 1] = key end end
        return t
    end
    local SOURCE = { form = "form", talents = "talents", class = "class" }
    for i, key in ipairs(Who()) do
        if i > 12 then break end
        RL:Cycle(MMT.FullDisplay(key), function()
            local auto
            local saved = M.db.playerRoles[key]
            M.db.playerRoles[key] = nil
            local role, src = mod.PlayerRole(key)
            M.db.playerRoles[key] = saved
            auto = role and ("Auto: " .. mod.ROLE_NAME[role] .. " (" .. (SOURCE[src] or src) .. ")") or "Auto"
            local c = { { value = "AUTO", text = auto } }
            for _, r in ipairs(mod.PLAYER_ROLES) do c[#c + 1] = { value = r[1], text = r[2] } end
            return c
        end, function() return M.db.playerRoles[key] or "AUTO" end, function(v)
            M.db.playerRoles[key] = (v ~= "AUTO") and v or nil
            Apply()
        end)
    end
    local RR = UI.Column(rp, COL2_X, 0, COL_W)
    RR:Header("How roles work")
    RR:Note("A buff's cog (Buffs tab) can limit it to player roles, classes or MMT roles: members it isn't for don't count as missing it - e.g. Blessing of Might only for Melee and Tank.")
    RR:Note("Auto: a druid's form right now (Cat Melee, Bear Tank, Moonkin Caster, Tree of Life Healer), else the talent tree with the most points (each client tells the team, also right after a respec or dual spec swap), else the class.")
    RR:Note("Set a role here to override it for that character.")
    RR:Header("Why?")
    RR:Note("One character can play two specs: a druid who is feral in one fight and balance in the next. With Blessing of Might \"Only for: Melee, Tank\" it's tracked while they're feral (cat or bear form, or feral talents) and left alone while they're a boomkin - nothing to swap by hand. Class or MMT-role lists can't tell the two apart: it's the same character.")

    -- Specs (Specs.lua) ---------------------------------------------------------------
    mod.SpecsTab(panels.specs, status, function() mod.BuildIndex() mod.ScanGroup() Apply() end)

    -- Buffs (lists) -------------------------------------------------------------
    local lp = panels.lists
    -- another tab, another settings page or the window closed: the popup goes too
    lp:HookScript("OnHide", mod.CloseFilter)
    page:HookScript("OnHide", mod.CloseFilter)
    local LS = UI.Column(lp, 0, 0, COL_W)
    local class = mod.OwnListKey()
    LS:Header("Tracked buffs")
    local list
    LS:Cycle("List", mod.ListChoices, function() return class end, function(v)
        class = v
        mod.CloseFilter()
        list:Render(M.db.lists[class] or {})
    end)

    local function Changed()
        mod.BuildIndex()
        mod.ScanGroup()
        Apply()
        mod.KnownCheck()   -- which of the tracked class buffs we haven't learned (Known.lua)
        list:Render(M.db.lists[class] or {})
    end

    list = H.List(lp, COL_W, 14, 22, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        H.RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", mod.DragGrip(row), "RIGHT", 4, 0)   -- dots: drag to reorder
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = UI.TextButton(row, "x", function() mod.CloseFilter(); table.remove(M.db.lists[class], row.index); Changed() end, 16)
        row.del:SetPoint("RIGHT", -2, 0)
        -- on / off: switched-off entries stay in the list but aren't tracked
        row.toggle = UI.TextButton(row, "", function()
            local e = M.db.lists[class][row.index]
            if e then e.off = (not e.off) or nil; Changed() end
        end, 26)
        row.toggle:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        UI.Tooltip(row.toggle, "On / off", "Switched-off entries stay in the list but aren't tracked.")
        -- cog: who this buff is for (player roles, classes, MMT roles)
        row.cog = CreateFrame("Button", nil, row)
        row.cog:SetSize(14, 14)
        row.cog:SetPoint("RIGHT", row.toggle, "LEFT", -2, 0)
        row.cog.tex = row.cog:CreateTexture(nil, "ARTWORK")
        row.cog.tex:SetAllPoints()
        row.cog.tex:SetTexture("Interface\\Icons\\Trade_Engineering")
        row.cog.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.cog:SetScript("OnClick", function(self)
            local e = M.db.lists[class] and M.db.lists[class][row.index]
            if e then mod.OpenFilter(e, self, Changed) end
        end)
        row.cog:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Only for...")
            local e = row.entry
            GameTooltip:AddLine(e and mod.FilterText(e) or "Everyone. Click to limit it to player roles, classes or MMT roles.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.cog, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if mod.IsPattern(self.entry) then
                GameTooltip:SetText(self.entry.name)
                GameTooltip:AddLine("Any buff whose name matches (* = any text): the icon shows the one that's up.", 1, 1, 1, true)
            elseif mod.IsWeapon(self.entry) then
                GameTooltip:SetText(mod.EntryName(self.entry))
                GameTooltip:AddLine("Any enchant on that weapon: shaman imbues, poisons, oils, sharpening stones. Members send theirs when it changes (they need this version).", 1, 1, 1, true)
            else
                GameTooltip:SetSpellByID(self.entry.id)
            end
            GameTooltip:AddLine("Drag to move it in the list.", 0.6, 0.6, 0.6)
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
        -- the cog lights up while the buff is only for some
        local limited = mod.HasFilter(e)
        -- only in the All bar (class / race / role / character lists are specific already); elsewhere
        -- only while it still has a filter (set before), so it can be cleared
        row.cog:SetShown(class == "ALL" or limited)
        row.cog.tex:SetDesaturated(not limited)
        row.cog.tex:SetAlpha(limited and 1 or 0.45)
    end)
    LS:Add(list, 14 * 22 + 6)
    -- drag a row to reorder the list (SettingsKit)
    mod.DragReorder(list, function() return M.db.lists[class] end, function()
        mod.CloseFilter()
        Changed()
    end)

    local box
    -- picked from the search list, else a link / ID / known name, else the name index
    local function Parse()
        local text = box:GetText()
        if box.picked and box.picked.text == text then return box.picked.id end
        return mod.ParseEntry(text) or select(2, mod.FindByName(text, false))
    end
    local function Add()
        local weapon = mod.ParseWeapon(box:GetText())
        local pattern = not weapon and mod.ParsePattern(box:GetText())
        local id = not weapon and not pattern and Parse()
        if not id and not pattern and not weapon then status.Show_("Unknown spell: pick it from the list, use its ID or shift-click it in the spellbook - or a name with * (Seal of *), or main hand / off hand.", true) return end
        local entry = weapon and { weapon = weapon } or pattern and { name = pattern } or { id = id }
        M.db.lists[class] = M.db.lists[class] or {}
        table.insert(M.db.lists[class], entry)
        box.picked = nil
        box:SetText("")
        box:ClearFocus()
        status.Show_(("Added %s."):format(mod.EntryName(entry)))
        Changed()
    end
    box = UI.EditBox(lp, COL_W - 58, "Buff name, ID, shift-click or Seal of *", function() Add() end)
    mod.AcceptSpellLinks(box)
    mod.AttachSearch(box, { items = false })
    LS:Add(box, 0)
    local add = UI.Button(lp, 54, "Add", Add)
    add:SetPoint("LEFT", box, "RIGHT", 4, 0)

    local RS = UI.Column(lp, COL2_X, 0, COL_W)
    RS:Header("How lists work")
    RS:Note("Lists per class, MMT role or character: a member tracks all lists that fit (class, All bar, their roles, their character). The cog of a buff in the All bar limits it to player roles, classes or MMT roles. Any rank and the group version (Prayer of Fortitude, Greater Blessings, ...) count. Type Seal of * for any seal, main hand / off hand for that weapon's enchant (imbue, poison, oil). Drag a buff to reorder.")
    mod.PresetBox(RS, lp, function() return class end, mod.EntryKey, Changed, status)
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
    -- buffs not learned yet (Known.lua): own, and as the team told us
    local own = {}
    for _, id in ipairs(mod.OwnUnlearned() or {}) do own[#own + 1] = tostring(mod.SpellInfo(id) or id) end
    for _, p in ipairs(mod.OwnUnlearnedPatterns()) do own[#own + 1] = p end
    add(("unlearned (own): %s  [spellbook %d spells, imbues %s]"):format(#own > 0 and table.concat(own, ", ") or "-",
        mod.SpellbookCount(), tostring(mod.OwnCanImbue())))
    for key, rec in pairs(M.store.unlearned or {}) do
        local t = {}
        for id in pairs(rec.ids or {}) do t[#t + 1] = tostring(mod.SpellInfo(id) or id) end
        for p in pairs(rec.patterns or {}) do t[#t + 1] = p end
        add(("unlearned %s: %s"):format(MMT.Repr(key), #t > 0 and table.concat(t, ", ") or "-"))
    end
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
