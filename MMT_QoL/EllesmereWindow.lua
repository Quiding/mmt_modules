-- MMT Quality of life: the window for sending EllesmereUI profiles.
-- Your profiles in EllesmereUI's order (the active one marked), "Full account"
-- below them, who gets it (one online member or the whole online team), Send.
-- Opened from the settings page, /mmtqol eui, or the "Send to team" button we
-- put above EllesmereUI's options window (it then sits beside it and closes with it).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local A = UI.ACCENT

local W, ROW_H, ROWS = 280, 18, 14
local win
local selected            -- profile name or mod.EUI_FULL; nil = the active profile
local to                  -- team key, nil = the online team
local dockButton

local function Rows()
    local out = {}
    for _, p in ipairs(mod.EuiProfiles()) do out[#out + 1] = { id = p.name, active = p.active } end
    out[#out + 1] = { id = mod.EUI_FULL, text = "Full account (settings + active profile)" }
    return out
end
mod.EuiRows = Rows

local function Selected(rows)
    if selected then
        for _, r in ipairs(rows) do if r.id == selected then return selected end end
    end
    for _, r in ipairs(rows) do if r.active then return r.id end end
    return rows[1] and rows[1].id
end

local function Render()
    if not win or not win:IsShown() then return end
    local rows = Rows()
    local sel = Selected(rows)
    win.offset = math.max(0, math.min(win.offset, #rows - ROWS))
    for i, r in ipairs(win.rows) do
        local p = rows[i + win.offset]
        r.entry = p
        if p then
            r.text:SetText((p.text or p.id) .. (p.active and "  |cff888888(active)|r" or ""))
            if p.id == mod.EUI_FULL then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
            r.sel:SetShown(p.id == sel)
            r:Show()
        else
            r:Hide()
        end
    end
    if to and not MMT.IsOnline(to) then to = nil end
    win.target.label:SetText(to and ("To: " .. MMT.FullDisplay(to)) or ("To: the online team (%d)"):format(#mod.OnlineOthers()))
end

local function Send()
    local choice = Selected(Rows())
    if not choice then return end
    local ok, text = mod.SendEui(choice, to)
    win.status:SetText(ok and text or ("Not sent: " .. tostring(text)))
    win.status:SetTextColor(ok and 0.6 or 1, ok and 1 or 0.4, ok and 0.6 or 0.4)
    if ok then MMT.Print("Quality of life: %s", text) end
end

local function Build()
    local listH = ROWS * ROW_H + 4
    local f = CreateFrame("Frame", "MMTQoLEllesmereWindow", UIParent)
    f:SetSize(W, 58 + listH + 76)
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

    local title = UI.Label(f, "Send EllesmereUI profiles", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -6)

    f.target = UI.Button(f, W - 20, "", function(self)
        local items = { { value = "", text = ("The online team (%d)"):format(#mod.OnlineOthers()) } }
        for _, key in ipairs(mod.OnlineOthers()) do items[#items + 1] = { value = key, text = MMT.FullDisplay(key) } end
        UI.OpenList(self, items, to or "", function(v) to = v ~= "" and v or nil; Render() end)
    end)
    f.target:SetPoint("TOPLEFT", 10, -32)
    UI.Tooltip(f.target, "Who gets it", "One team member or everybody of the team who is online.")

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 10, -58)
    list:SetSize(W - 20, listH)
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
        r.text:SetPoint("LEFT", 8, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self) if self.entry then selected = self.entry.id; Render() end end)
        f.rows[i] = r
    end

    f.send = UI.Button(f, 120, "Send", Send)
    f.send:SetPoint("BOTTOMLEFT", 10, 10)
    UI.Tooltip(f.send, "Send", "The chosen profile, complete (every module, layout, Cooldown Manager spells), or the full account export. Each one who gets it is asked and sees EllesmereUI's import page.")

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

-- EllesmereUI's options window ("EllesmereUIFrame"), when it exists
local function Options() return rawget(_G, "EllesmereUIFrame") end

-- the part of it you SEE: EllesmereUIFrame is 1500 x 1154 with an empty margin (room for its
-- shadow and glow); the panel is its child "EllesmereUIClickArea", 1300 x 946, centred.
-- Anchoring to the outer frame left our button floating up and right of the panel.
local function Visible()
    local area = rawget(_G, "EllesmereUIClickArea")
    if area and area.IsShown and area:IsShown() then return area end
    return Options()
end

local function Place()
    local opts = Options()
    win:ClearAllPoints()
    win.docked = opts and opts:IsShown() and true or false
    if win.docked then
        -- MMT_qStyles' Classic draws the windows' borders outside them: keep the two borders apart
        win:SetPoint("TOPLEFT", Visible(), "TOPRIGHT", 4 + ((QStyles and QStyles.WindowGap and tonumber(QStyles.WindowGap())) or 0), 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

function mod.OpenEui()
    if not mod.Active(mod.EuiFeature) then
        local ok, why = mod.AddonState("EllesmereUI")
        MMT.Print("Quality of life: sending EllesmereUI profiles is %s", ok and "switched off (/mmt > Quality of life > EllesmereUI)." or why)
        return
    end
    if not win then
        Build()
        if QStyles and QStyles.OnChange then QStyles.OnChange(function() if win:IsShown() and win.docked then Place() end end) end
    end
    if win:IsShown() then win:Hide() return end
    win.status:SetText("")
    Place()
    win:Show()
end

function mod.EuiClose()
    if win then win:Hide() end
    if dockButton then dockButton:Hide() end
end

-- the "Send to team" button above EllesmereUI's options window. The window
-- is built on its first open (one frame after EllesmereUI:Show), so we look
-- again after each Show / Toggle and a moment later.
local hooked
function mod.EuiDock()
    local e = mod.EuiAPI()
    if not hooked and type(e) == "table" then
        hooked = true
        local function Again()
            mod.EuiDock()
            if C_Timer and C_Timer.After then C_Timer.After(0.5, mod.EuiDock) end
        end
        if type(e.Show) == "function" then hooksecurefunc(e, "Show", Again) end
        if type(e.Toggle) == "function" then hooksecurefunc(e, "Toggle", Again) end
    end
    local opts = Options()
    if not opts then return end
    if not dockButton then
        dockButton = UI.Button(opts, 120, "Send to team", function() mod.OpenEui() end)
        UI.Tooltip(dockButton, "Send to team (MMT)", "Send an EllesmereUI profile to a team member or the whole online team (MMT Quality of life).")
        -- the window opened beside the options closes with them
        opts:HookScript("OnHide", function() if win and win.docked then win:Hide() end end)
    end
    -- above the visible panel's top right (placed again on each open: the panel can be built later)
    dockButton:ClearAllPoints()
    dockButton:SetPoint("BOTTOMRIGHT", Visible(), "TOPRIGHT", 0, 2)
    dockButton:SetShown(M.db.euDock and mod.Active(mod.EuiFeature) or false)
end
