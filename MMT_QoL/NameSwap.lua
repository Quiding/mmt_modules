-- MMT Quality of life: a profile with other names.
--
-- An MMT profile export (MMT settings > Profiles) carries the team's names: the team list,
-- and module settings kept per character (Buff Timers' roles and specs, Totems' calls,
-- Cooldown Timers' "CHAR:" lists, ...). This window renames the members in a COPY of a
-- profile - your current one, or an export pasted into it:
--   * Export without names: every member becomes Class + number (Paladin1, Paladin2, ...)
--   * Export with these names: the names typed in the boxes (empty box = name kept)
--   * Make a profile with these names: the same, as a new profile on this account
-- An export made here is a normal MMT export (MMT's own Import takes it too). Pasting one
-- (Paladin1, ...) and typing the new characters' names gives the profile for a new team.
--
-- Parts (the list on the right): MMT's core settings, the role items (the items on each role)
-- and each module's settings can be left out of an export / a new profile (M.db.nxSkip);
-- with "keep mine", a new profile takes the left-out parts from your current profile as they are.
--
-- Renaming: a member's key ("First-Last") is replaced wherever it appears as a whole name
-- (keys and texts, "CHAR:First-Last" too); a first name alone only where a key or text
-- is exactly that name (a first name inside a longer text could be a word).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local function Trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end

-- "First Last" / "First-Last" / "First" -> key, first, last (as MMT's team keys)
function mod.NxKey(text)
    text = Trim(text)
    if text == "" then return nil end
    local first, last = text:match("^(%S+)%s+(.+)$")
    if first then
        last = last:gsub("%s+", "-")
        return first .. "-" .. last, first, last
    end
    first, last = text:match("^([^-]+)-(.+)$")
    if first then return text, first, last end
    return text, text, nil
end

-- the members of a profile's data, in team order: { key, first, class }
function mod.NxMembers(data)
    local t = {}
    for key, m in pairs(type(data) == "table" and type(data.team) == "table" and data.team or {}) do
        if type(key) == "string" and type(m) == "table" then
            t[#t + 1] = { key = key, first = type(m.name) == "string" and m.name or nil, class = m.class, order = tonumber(m.order) or 999 }
        end
    end
    table.sort(t, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.key < b.key end)
    return t
end

local function ClassWord(class)
    local loc = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local w = type(loc) == "string" and loc or (type(class) == "string" and class:sub(1, 1) .. class:sub(2):lower()) or "Member"
    return (w:gsub("[^%w]", ""))
end

-- Paladin1, Paladin2, Mage1, ... (in team order): [key] = placeholder
function mod.NxPlaceholders(members)
    local n, out = {}, {}
    for _, m in ipairs(members) do
        local w = ClassWord(m.class)
        n[w] = (n[w] or 0) + 1
        out[m.key] = w .. n[w]
    end
    return out
end

-- a byte that belongs to a name (letters, digits, - and ', any non-ASCII byte)
local function IsNameChar(c)
    return c ~= "" and (c:find("^[%w%-']") ~= nil or c:byte() >= 128)
end

-- every whole-name occurrence of word in s replaced by repl
local function ReplaceWord(s, word, repl)
    if not s:find(word, 1, true) then return s end
    local out, i = {}, 1
    while true do
        local a, b = s:find(word, i, true)
        if not a then break end
        if not IsNameChar(s:sub(a - 1, a - 1)) and not IsNameChar(s:sub(b + 1, b + 1)) then
            out[#out + 1] = s:sub(i, a - 1)
            out[#out + 1] = repl
        else
            out[#out + 1] = s:sub(i, b)
        end
        i = b + 1
    end
    out[#out + 1] = s:sub(i)
    return table.concat(out)
end

-- a renamed deep copy of a profile's data, and the renamed profile name.
-- map[oldKey] = new name text ("First-Last", "First Last" or "First"); members not in it keep theirs
function mod.NxRename(data, map, profileName)
    local members = mod.NxMembers(data)
    local firstCount = {}
    for _, m in ipairs(members) do if m.first then firstCount[m.first] = (firstCount[m.first] or 0) + 1 end end
    local reps, final, exact, newOf = {}, {}, {}, {}
    local n = 0
    for _, m in ipairs(members) do
        local key, first, last = mod.NxKey(map[m.key])
        if key and key ~= m.key then
            n = n + 1
            local tok = "\001" .. n .. "\001"
            final[tok] = key
            reps[#reps + 1] = { old = m.key, tok = tok }
            newOf[m.key] = { key = key, first = first, last = last }
            -- a first name standing alone (only when no other member has it)
            if m.first and m.first ~= m.key and firstCount[m.first] == 1 then exact[m.first] = first end
        end
    end
    table.sort(reps, function(a, b) return #a.old > #b.old end)   -- "Anna-Smith" before "Anna"
    local function Str(s)
        if exact[s] then return exact[s] end
        for _, r in ipairs(reps) do s = ReplaceWord(s, r.old, r.tok) end
        if s:find("\001", 1, true) then s = s:gsub("\001%d+\001", final) end
        return s
    end
    local seen = {}
    local function Copy(v, depth)
        if type(v) == "string" then return Str(v) end
        if type(v) ~= "table" then return v end
        if seen[v] or depth > 40 then return nil end
        seen[v] = true
        local t = {}
        for k, x in pairs(v) do
            local nk = type(k) == "string" and Str(k) or k
            t[nk] = Copy(x, depth + 1)
        end
        seen[v] = nil
        return t
    end
    local out = Copy(data, 0)
    -- the team records: name / last name of the new character
    for _, nw in pairs(newOf) do
        local m = out.team and out.team[nw.key]
        if type(m) == "table" then m.name, m.last = nw.first, nw.last end
    end
    return out, profileName and Str(profileName) or nil
end

-- the new names make sense: no two members end up with one name. Returns true, or false + why
function mod.NxCheck(data, map)
    local used = {}
    for _, m in ipairs(mod.NxMembers(data)) do
        local key = mod.NxKey(map[m.key]) or m.key
        if used[key] then return false, ("Two members would both be called %s."):format(key) end
        used[key] = true
    end
    return true
end

-- what always goes along: the team and the role names (who has which role)
local KEEP = { team = true, roles = true, modules = true }

-- the parts of a profile's data that can be left out: { id, text, tip }
function mod.NxParts(data)
    local t = {}
    if type(data) ~= "table" then return t end
    local core = false
    for k in pairs(data) do if not KEEP[k] then core = true break end end
    if core then t[#t + 1] = { id = "core", text = "MMT core settings", tip = "Info window, automations (quests, gossip, merchant, invites, mail, trade, ...), distance window, FTL and the other settings on MMT's own pages. The team and its roles always go along." } end
    if type(data.roles) == "table" and next(data.roles) then
        t[#t + 1] = { id = "roleitems", text = "Role items", tip = "The items on each role (Loot Distribution, trade, mail, the Role items panel). Left out: the roles stay, with empty item lists." }
    end
    local mods = {}
    for name in pairs(type(data.modules) == "table" and data.modules or {}) do
        local m = MMT.modules and MMT.modules[name]
        local title = (m and m.title) or name
        mods[#mods + 1] = { id = "m:" .. name, text = title, tip = ("The settings of the module %s."):format(title) }
    end
    table.sort(mods, function(a, b) return a.text:lower() < b.text:lower() end)
    for _, m in ipairs(mods) do t[#t + 1] = m end
    return t
end

-- the left-out parts taken away from data (changed in place)
function mod.NxStrip(data, skip)
    if type(skip) ~= "table" then return data end
    if skip.core then
        for k in pairs(data) do if not KEEP[k] then data[k] = nil end end
    end
    if skip.roleitems and type(data.roles) == "table" then
        for _, r in pairs(data.roles) do if type(r) == "table" then r.rules = {} end end
    end
    if type(data.modules) == "table" then
        for name in pairs(data.modules) do if skip["m:" .. name] then data.modules[name] = nil end end
    end
    return data
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

-- the left-out parts filled in from mine (copies, names as they are; changed in place)
function mod.NxFill(data, skip, mine)
    if type(skip) ~= "table" or type(mine) ~= "table" then return data end
    if skip.core then
        for k, v in pairs(mine) do if not KEEP[k] then data[k] = DeepCopy(v) end end
    end
    if skip.roleitems and type(mine.roles) == "table" then
        data.roles = type(data.roles) == "table" and data.roles or {}
        for name, r in pairs(mine.roles) do
            if type(r) == "table" then
                data.roles[name] = type(data.roles[name]) == "table" and data.roles[name] or {}
                data.roles[name].rules = DeepCopy(r.rules or {})
            end
        end
    end
    for id in pairs(skip) do
        local name = type(id) == "string" and id:match("^m:(.+)$")
        if name and type(mine.modules) == "table" and mine.modules[name] ~= nil then
            data.modules = type(data.modules) == "table" and data.modules or {}
            data.modules[name] = DeepCopy(mine.modules[name])
        end
    end
    return data
end

-- "MMT1:..." (MMT's own export format, its Import takes it); skip = parts left out
function mod.NxExport(data, map, profileName, skip)
    local ok, why = mod.NxCheck(data, map)
    if not ok then return nil, why end
    local out, pname = mod.NxRename(data, map, profileName)
    mod.NxStrip(out, skip)
    return "MMT1:" .. MMT.Serialize({ name = pname or "Team", data = out })
end

-- the new profile's data: renamed, left-out parts away (or, keepMine, from mine as they are)
function mod.NxProfileData(data, map, skip, keepMine, mine)
    local out = mod.NxRename(data, map)
    mod.NxStrip(out, skip)
    if keepMine then mod.NxFill(out, skip, mine) end
    return out
end

-- the current profile's data, Class + number for everyone
function mod.NxAnonMap(data)
    return mod.NxPlaceholders(mod.NxMembers(data))
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W, ROW_H, ROWS = 470, 24, 8
local PW, PARTS = 230, 18      -- the parts column: width, most rows
local win, F
local source          -- { data, name, pasted = true/nil }
local names = {}      -- [oldKey] = typed text

local function Source()
    if source then return source end
    return { data = MMT.db, name = MMT.CurrentProfileName and MMT.CurrentProfileName() or "Profile" }
end

local function Status(text, bad)
    if not win then return end
    win.status:SetText(text or "")
    if bad then win.status:SetTextColor(1, 0.45, 0.35) else win.status:SetTextColor(0.55, 0.85, 0.55) end
end

local Render
local function Members() return mod.NxMembers(Source().data) end
local function Skip() M.db.nxSkip = type(M.db.nxSkip) == "table" and M.db.nxSkip or {} return M.db.nxSkip end

Render = function()
    if not win or not win:IsShown() then return end
    local src = Source()
    win.src:SetText(src.pasted and ("From the pasted export (profile \"%s\")"):format(src.name)
        or ("From your current profile \"%s\""):format(src.name))
    local list = Members()
    win.offset = math.max(0, math.min(win.offset, #list - ROWS))
    for i, r in ipairs(win.rows) do
        local m = list[i + win.offset]
        r.member = m
        if m then
            local c = m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
            r.old:SetText(m.key)
            if c then r.old:SetTextColor(c.r, c.g, c.b) else r.old:SetTextColor(1, 1, 1) end
            r.box:SetText(names[m.key] or "")
            r.box.UpdatePlaceholder()
            r:Show()
        else
            r:Hide()
        end
    end
    win.empty:SetText(#list == 0 and "No team members in this profile." or "")
    win.count:SetText(#list > ROWS and ("%d-%d of %d, scroll for more"):format(win.offset + 1, math.min(win.offset + ROWS, #list), #list) or "")
    if win.pname:GetText() == "" and not win.pname:HasFocus() then win.pname.UpdatePlaceholder() end
    local parts = mod.NxParts(src.data)
    for i, c in ipairs(win.parts) do
        local part = parts[i]
        c.part = part
        if part then
            c.label:SetText(part.text)
            c.Refresh()
            c:Show()
        else
            c:Hide()
        end
    end
    win.partsMore:SetText(#parts > PARTS and ("|cffff9966%d more not shown|r"):format(#parts - PARTS) or "")
end

local function ShowText(text)
    win.text.edit:SetText(text)
    win.text.edit:SetFocus()
    win.text.edit:HighlightText()
end

local function ProfileName()
    local typed = Trim(win.pname:GetText())
    return typed ~= "" and typed or nil
end

local function ExportAnon()
    local src = Source()
    local str = mod.NxExport(src.data, mod.NxAnonMap(src.data), ProfileName() or src.name, Skip())
    ShowText(str)
    Status("Exported without names (Class + number). Ctrl+C to copy.")
end

local function ExportNamed()
    local src = Source()
    local str, why = mod.NxExport(src.data, names, ProfileName() or src.name, Skip())
    if not str then Status(why, true) return end
    ShowText(str)
    Status("Exported with the names in the boxes (empty box = name kept). Ctrl+C to copy.")
end

local function MakeProfile()
    local src = Source()
    local ok, why = mod.NxCheck(src.data, names)
    if not ok then Status(why, true) return end
    local pname = ProfileName()
    if not pname then Status("Type a name for the new profile first.", true) return end
    if MMTDB and MMTDB.profiles and MMTDB.profiles[pname] then
        Status(("There is a profile called \"%s\" already: pick another name."):format(pname), true) return
    end
    local data = mod.NxProfileData(src.data, names, Skip(), M.db.nxKeepMine, MMT.db)
    MMT.ImportProfile(pname, data, M.db.nxSwitch and true or false)
    Status(("Profile \"%s\" made%s."):format(pname, M.db.nxSwitch and " and switched to" or " (MMT settings > Profiles)"))
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

local function ReadPasted()
    local name, data = MMT.ParseExport(win.text.edit:GetText() or "")
    if not name then Status("Paste an MMT profile export into the box below first.", true) return end
    source = { data = data, name = name, pasted = true }
    wipe(names)
    win.offset = 0
    win.text.edit:SetText("")
    Status(("Read \"%s\": %d member(s). Type their new names."):format(name, #mod.NxMembers(data)))
    Render()
end

local function UseMine()
    source = nil
    wipe(names)
    win.offset = 0
    Status("")
    Render()
end

local function FillPlaceholders()
    for k, v in pairs(mod.NxAnonMap(Source().data)) do names[k] = v end
    Render()
end

local function Build()
    local f = CreateFrame("Frame", "MMTQoLNameSwap", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER")
    UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
    UI.Border(f, 0.22, 0.24, 0.28, 1)
    UI.CloseOnEscape(f)

    local title = UI.Label(f, "Profile export / import - with other names", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -6)

    f.src = UI.Label(f, "")
    f.src:SetPoint("TOPLEFT", 10, -32)
    f.src:SetWidth(W - 150)
    f.src:SetJustifyH("LEFT")
    f.src:SetWordWrap(false)
    local mine = UI.Button(f, 120, "Use my profile", UseMine)
    mine:SetPoint("TOPRIGHT", -10, -28)
    UI.Tooltip(mine, "Use my profile", "Start again from your current MMT profile (instead of a pasted export).")

    local head1 = UI.Label(f, "|cff999999Member now|r")
    head1:SetPoint("TOPLEFT", 12, -56)
    local head2 = UI.Label(f, "|cff999999New name (empty = keep)|r")
    head2:SetPoint("TOPLEFT", 200, -56)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 10, -72)
    list:SetSize(W - 20, ROWS * ROW_H + 4)
    UI.Fill(list, 0.08, 0.08, 0.09, 1)
    UI.Border(list, 0.2, 0.2, 0.22, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta; Render() end)
    f.empty = UI.Label(list, "")
    f.empty:SetPoint("TOPLEFT", 8, -8)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, list)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
        r.old = UI.Label(r, "")
        r.old:SetPoint("LEFT", 6, 0)
        r.old:SetWidth(176)
        r.old:SetJustifyH("LEFT")
        r.old:SetWordWrap(false)
        r.box = UI.EditBox(r, W - 216, "e.g. Anna Smith", function(_, box) box:ClearFocus() end)
        r.box:SetPoint("LEFT", 188, 0)
        r.box:HookScript("OnTextChanged", function(box)
            if r.member then
                local t = Trim(box:GetText())
                names[r.member.key] = t ~= "" and t or nil
            end
        end)
        UI.Tooltip(r.box, "New name", "First name, or first and last name (\"Anna Smith\" or \"Anna-Smith\"). Empty: this member keeps the name.")
        f.rows[i] = r
    end
    f.count = UI.Label(f, "")
    f.count:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -3)
    f.count:SetTextColor(0.6, 0.6, 0.6)

    local fill = UI.Button(f, 150, "Fill Class + number", FillPlaceholders)
    fill:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -154, -18)
    UI.Tooltip(fill, "Fill Class + number", "Puts Paladin1, Paladin2, Mage1, ... into the boxes (team order).")
    local clear = UI.Button(f, 150, "Clear the boxes", function() wipe(names); Render() end)
    clear:SetPoint("LEFT", fill, "RIGHT", 4, 0)

    f.pname = UI.EditBox(f, 220, "New profile name", function(_, box) box:ClearFocus() end)
    f.pname:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -46)
    UI.Tooltip(f.pname, "Profile name", "The name of the new profile (Make a profile), or the profile name inside an export (empty: the current one's).")
    local switch = UI.Check(f, 220, "Switch to it", function() return M.db.nxSwitch end, function(v) M.db.nxSwitch = v end,
        "After Make a profile: this character uses the new profile right away. Off: it waits in MMT settings > Profiles.")
    switch:SetPoint("LEFT", f.pname, "RIGHT", 10, 0)

    local anon = UI.Button(f, 146, "Export without names", ExportAnon)
    anon:SetPoint("TOPLEFT", f.pname, "BOTTOMLEFT", 0, -8)
    UI.Tooltip(anon, "Export without names", "Every member becomes Class + number (Paladin1, Paladin2, ...) - in the team, and in every module setting kept per character. The boxes don't matter for this one.")
    local named = UI.Button(f, 146, "Export with these names", ExportNamed)
    named:SetPoint("LEFT", anon, "RIGHT", 6, 0)
    UI.Tooltip(named, "Export with these names", "The export with the names typed in the boxes (empty box = the name stays).")
    local make = UI.Button(f, 146, "Make a profile", MakeProfile)
    make:SetPoint("LEFT", named, "RIGHT", 6, 0)
    UI.Tooltip(make, "Make a profile", "A new MMT profile on this account: a copy of this one with the names in the boxes - e.g. your team set up again for new characters.")

    f.text = UI.TextArea(f, W - 20, 70)
    f.text:SetPoint("TOPLEFT", anon, "BOTTOMLEFT", 0, -8)
    local read = UI.Button(f, 180, "Read the pasted export", ReadPasted)
    read:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -6)
    UI.Tooltip(read, "Read the pasted export", "Paste an MMT profile export (Ctrl+V) into the box above, then click this: its members are listed to give them names.")

    f.status = UI.Label(f, "")
    f.status:SetPoint("TOPLEFT", read, "BOTTOMLEFT", 0, -6)
    f.status:SetWidth(W - 20)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(true)

    -- the parts column (right): ticked = goes along
    local px = W + 4
    local head3 = UI.Label(f, "|cff999999Goes along (untick to leave out)|r")
    head3:SetPoint("TOPLEFT", px, -56)
    f.parts = {}
    for i = 1, PARTS do
        local c
        c = UI.Check(f, PW - 20, "", function() return c.part and not Skip()[c.part.id] end,
            function(v) if c.part then Skip()[c.part.id] = (not v) or nil end end)
        c:SetPoint("TOPLEFT", px, -72 - (i - 1) * 20)
        c:SetScript("OnEnter", function(self)
            if not self.part then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.part.text)
            GameTooltip:AddLine(self.part.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.parts[i] = c
    end
    f.partsMore = UI.Label(f, "")
    f.partsMore:SetPoint("TOPLEFT", px, -72 - PARTS * 20)
    local keep = UI.Check(f, PW - 20, "New profile: left-out parts from mine", function() return M.db.nxKeepMine end,
        function(v) M.db.nxKeepMine = v end,
        "Make a profile: the parts you left out are taken from your current profile as they are (your own settings, your own role items) instead of the defaults. Exports always leave them out.")
    keep:SetPoint("TOPLEFT", px, -72 - PARTS * 20 - 18)

    f:SetSize(W + PW, math.max(72 + ROWS * ROW_H + 4 + 46 + 24 + 8 + 24 + 8 + 70 + 6 + 24 + 40, 72 + PARTS * 20 + 18 + 30))
    f.offset = 0
    f:SetScript("OnShow", Render)
    f:Hide()
    win = f
end

function mod.OpenNx()
    if not win then Build() end
    win:Show()
    Render()
end
mod.NxFrame = function() return win end

F = mod.Feature({
    key = "nx", icon = "INV_Scroll_03", slash = "names", slashAlias = "export", title = "Profile export / import", tabText = "Export / Import",
    checkText = "Profile export / copy with other names",
    tip = "A window to export your MMT profile without the team's names (Paladin1, Paladin2, ...) or with names you type, and to make a profile for new characters from yours or from a pasted export.",
    notes = {
        "An MMT profile has the team's names in it: the team list, and module settings kept per character (Buff Timers' roles and specs, Totems' calls, Cooldown Timers' character lists, ...). The window renames them all in a copy; your profile stays as it is.",
        "Export without names: every member becomes Class + number. Export with these names: the names in the boxes. Both make a normal MMT export: MMT's own Import (Profiles) takes them.",
        "Make a profile: the copy with the new names as a new profile on this account - your team set up again for new characters. Paste an export and Read it to name ITS members instead.",
        "A first name alone is only replaced where a setting is exactly that name, so a word in a text that happens to be a first name stays.",
    },
    commands = { [""] = function() mod.OpenNx() end },
    Page = function(ui)
        ui.Button("Open the window", function() mod.OpenNx() end, "Also /mmtqol names.")
    end,
    Report = function(add)
        add(("Names: window=%s source=%s typed=%d"):format(tostring(win ~= nil), source and "pasted" or "current",
            (function() local n = 0 for _ in pairs(names) do n = n + 1 end return n end)()))
    end,
})
