-- MMT Quality of life: the window for sending ForeverAuras auras.
-- A list of every aura (groups with what's inside them indented), "All auras"
-- on top, who gets them (one online member or the whole online team), Send.
-- Opened from the settings page, /mmtqol auras, or the "Send to team" button
-- we put above ForeverAuras' options window (it then sits beside that window).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local A = UI.ACCENT

local W, H, ROW_H, ROWS = 300, 500, 18, 18
local ALL = "\001all"     -- the "All auras" row
local win
local selected = ALL
local to                  -- team key, nil = the online team
local dockButton

local expanded = {}       -- [group id] = true: its auras are listed (groups start closed; kept while the game runs)
local shut = {}           -- [section row id] = true: "Loaded" / "Not loaded" closed (they start open, like ForeverAuras')
local SECTIONS = { loaded = "Loaded", unloaded = "Not loaded" }

-- the rows shown, like ForeverAuras' list: "Loaded" and "Not loaded" sections,
-- what's inside a closed group or section is left out (a filter shows every
-- match of the open sections)
local function Rows()
    local list = mod.AuraList()
    local filter = win and win.search:GetText():lower() or ""
    local out = { { id = ALL, depth = 0, text = ("All auras (%d)"):format(#list) } }
    local tops = {}
    for _, a in ipairs(list) do
        if a.section and a.depth == 0 then tops[a.section] = (tops[a.section] or 0) + 1 end
    end
    local closedAt   -- depth of the closed group whose auras are being skipped
    local section, sectionShut
    for _, a in ipairs(list) do
        if a.section ~= section then
            section = a.section
            local hid = "\001" .. tostring(section)
            sectionShut = section and shut[hid] or false
            closedAt = nil
            if section then
                out[#out + 1] = { id = hid, header = true, depth = 0, text = ("%s (%d)"):format(SECTIONS[section] or section, tops[section] or 0) }
            end
        end
        if sectionShut then
            -- skipped
        elseif filter ~= "" then
            if a.id:lower():find(filter, 1, true) then out[#out + 1] = a end
        elseif not (closedAt and a.depth > closedAt) then
            closedAt = nil
            out[#out + 1] = a
            if a.group and not expanded[a.id] then closedAt = a.depth end
        end
    end
    return out
end
mod.AurasRows = Rows

-- a group, or a section row ("\001loaded")
local function Toggle(id)
    if id:sub(1, 1) == "\001" then shut[id] = not shut[id] or nil
    else expanded[id] = not expanded[id] or nil end
end
mod.AurasToggle = Toggle

local function TargetText()
    if to then return "To: " .. MMT.FullDisplay(to) end
    return ("To: the online team (%d)"):format(#mod.OnlineOthers())
end

local function Render()
    if not win or not win:IsShown() then return end
    local rows = Rows()
    win.offset = math.max(0, math.min(win.offset, #rows - ROWS))
    for i, r in ipairs(win.rows) do
        local a = rows[i + win.offset]
        r.aura = a
        if a then
            local text = a.text or a.id
            if a.group then text = text .. ("  |cff888888(group, %d)|r"):format(a.inside) end
            r.text:SetText(text)
            r.text:SetPoint("LEFT", 20 + a.depth * 12, 0)
            local filtered = win.search:GetText() ~= ""
            r.toggle:SetShown(a.header or (a.group and not filtered) or false)
            if a.header then r.toggle.label:SetText(shut[a.id] and "+" or "-")
            else r.toggle.label:SetText(expanded[a.id] and "-" or "+") end
            r.toggle:SetPoint("LEFT", 2 + a.depth * 12, 0)
            if a.id == ALL then r.text:SetTextColor(A[1], A[2], A[3])
            elseif a.header then r.text:SetTextColor(1, 0.82, 0)
            else r.text:SetTextColor(1, 1, 1) end
            r.sel:SetShown(a.id == selected)
            r:Show()
        else
            r:Hide()
        end
    end
    win.more:SetText(#rows > ROWS and ("%d-%d of %d"):format(win.offset + 1, math.min(#rows, win.offset + ROWS), #rows) or "")
    if to and not MMT.IsOnline(to) then to = nil end
    win.target.label:SetText(TargetText())
end

local function Send()
    local ids
    if selected == ALL then ids = mod.TopAuras() else ids = { selected } end
    local ok, text = mod.SendAuras(ids, to)
    win.status:SetText(ok and text or ("Not sent: " .. tostring(text)))
    win.status:SetTextColor(ok and 0.6 or 1, ok and 1 or 0.4, ok and 0.6 or 0.4)
    if ok then MMT.Print("Quality of life: %s", text) end
end

local function Build()
    local f = CreateFrame("Frame", "MMTQoLAurasWindow", UIParent)
    f:SetSize(W, H)
    -- DIALOG like MMT's settings: MMT's dropdown lists (FULLSCREEN_DIALOG) open in front of it
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
    UI.Border(f, 0.22, 0.24, 0.28, 1)
    UI.CloseOnEscape(f)

    local title = UI.Label(f, "Send ForeverAuras auras", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -6)

    f.target = UI.Button(f, W - 20, "", function(self)
        local items = { { value = "", text = ("The online team (%d)"):format(#mod.OnlineOthers()) } }
        for _, key in ipairs(mod.OnlineOthers()) do items[#items + 1] = { value = key, text = MMT.FullDisplay(key) } end
        UI.OpenList(self, items, to or "", function(v) to = v ~= "" and v or nil; Render() end)
    end)
    f.target:SetPoint("TOPLEFT", 10, -32)
    UI.Tooltip(f.target, "Who gets them", "One team member or everybody of the team who is online.")

    f.search = UI.EditBox(f, W - 20, "Filter by name")
    f.search:SetPoint("TOPLEFT", 10, -58)
    f.search:HookScript("OnTextChanged", function() f.offset = 0; Render() end)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 10, -84)
    list:SetSize(W - 20, ROWS * ROW_H + 4)
    UI.Fill(list, 0.08, 0.08, 0.09, 1)
    UI.Border(list, 0.2, 0.2, 0.22, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta * 3; Render() end)
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 1, -2 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -1, -2 - (i - 1) * ROW_H)
        r.sel = UI.Fill(r, A[1], A[2], A[3], 0.2, "BORDER")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
        r.text = UI.Label(r, "")
        r.text:SetPoint("LEFT", 6, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        -- click selects (a section row opens / closes); double-click (or the +/- in front) opens / closes a group
        r:SetScript("OnClick", function(self)
            local a = self.aura
            if not a then return end
            if a.header then Toggle(a.id) else selected = a.id end
            Render()
        end)
        r:SetScript("OnDoubleClick", function(self)
            if self.aura and self.aura.group then Toggle(self.aura.id); Render() end
        end)
        r.toggle = UI.TextButton(r, "+", function() if r.aura then Toggle(r.aura.id); Render() end end, 16)
        r.toggle:SetPoint("LEFT", 2, 0)
        r.toggle:Hide()
        f.rows[i] = r
    end
    f.more = UI.Label(f, "")
    f.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -2, -3)
    f.more:SetTextColor(0.5, 0.5, 0.5)

    f.send = UI.Button(f, 120, "Send", Send)
    f.send:SetPoint("BOTTOMLEFT", 10, 10)
    UI.Tooltip(f.send, "Send", "The chosen aura (a group with everything inside it), or all of them. Each one who gets them is asked and sees ForeverAuras' import window.")

    f.status = UI.Label(f, "")
    f.status:SetPoint("BOTTOMLEFT", 10, 38)
    f.status:SetPoint("BOTTOMRIGHT", -10, 38)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(true)

    f.offset = 0
    f:SetScript("OnShow", Render)
    f:Hide()
    win = f
end

-- beside ForeverAuras' options when they're open, else where it was / the middle
local function Place()
    local api = mod.AurasAPI()
    local opts = api and api.GetConfigFrame and api:GetConfigFrame()
    win:ClearAllPoints()
    win.docked = opts and opts:IsShown() and true or false
    if win.docked then
        win:SetPoint("TOPLEFT", opts, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

function mod.OpenAuras()
    if not mod.Active(mod.AurasFeature) then
        local ok, why = mod.AddonState("ForeverAuras")
        MMT.Print("Quality of life: sending auras is %s", ok and "switched off (/mmt > Quality of life > ForeverAuras)." or why)
        return
    end
    if not win then Build() end
    if win:IsShown() then win:Hide() return end
    win.status:SetText("")
    Place()
    win:Show()
end

function mod.AurasClose()
    if win then win:Hide() end
    if dockButton then dockButton:Hide() end
end

-- the "Send to team" button above ForeverAuras' options window (their frame
-- only exists once the options opened: tried again after each OpenOptions)
local hooked
function mod.AurasDock()
    local fa = rawget(_G, "ForeverAuras")
    if not hooked and type(fa) == "table" and type(fa.OpenOptions) == "function" then
        hooked = true
        hooksecurefunc(fa, "OpenOptions", function() mod.AurasDock() end)
    end
    local api = mod.AurasAPI()
    local opts = api and api.GetConfigFrame and api:GetConfigFrame()
    if not opts then return end
    if not dockButton then
        dockButton = UI.Button(opts, 120, "Send to team", function() mod.OpenAuras() end)
        dockButton:SetPoint("BOTTOMRIGHT", opts, "TOPRIGHT", 0, 2)
        UI.Tooltip(dockButton, "Send to team (MMT)", "Send auras to a team member or the whole online team (MMT Quality of life).")
        -- the window opened beside the options closes with them
        opts:HookScript("OnHide", function() if win and win.docked then win:Hide() end end)
    end
    dockButton:SetShown(M.db.waDock and mod.Active(mod.AurasFeature) or false)
end
