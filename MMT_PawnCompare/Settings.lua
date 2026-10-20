-- MMT Pawn Compare: settings page (MODULES > Pawn Compare in /mmt) and the
-- module's part of the debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v end
end

local function ScaleNames(rec)
    local t = {}
    for _, sc in ipairs(rec.scales) do t[#t + 1] = sc.name end
    return table.concat(t, ", ")
end

-- "Reset to defaults" (click twice), left of the core's "Sync to team" button
local function ResetButton(page, done)
    local b = H.ConfirmButton(page, 150, "Reset to defaults", function()
        for k in pairs(M.db) do M.db[k] = nil end
        for k, v in pairs(M.defaults or {}) do M.db[k] = MMT.CopyTable(v) end
        if M.OnProfileChanged then M.OnProfileChanged(M) end
        if done then done() end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
        MMT.Print("%s: settings reset to defaults.", M.title)
    end)
    b:SetPoint("BOTTOMRIGHT", M.sync and -(176 + 8) or 0, 2)
    UI.Tooltip(b, "Reset to defaults", "Puts every setting of this module back to the default of a new profile. Click twice.")
    return b
end

M.Page = function(_, page)
    ResetButton(page)
    local L = UI.Column(page, 0, 0, COL_W)
    local status

    L:Header("Pawn Compare")
    L:Note("Adds Pawn scores to the Item Compare tooltips: the hovered item is scored with each member's own Pawn scales and compared with what they have equipped.")
    local state = UI.Label(page, "")
    state:SetWidth(COL_W)
    state:SetJustifyH("LEFT")
    state:SetWordWrap(true)
    L:Add(state, 46)

    local gc, sc = Opt("showInCompare")
    L:Check("Show Pawn scores in Item Compare", gc, sc)
    local ga, sa = Opt("allScales")
    L:Check("Show every scale of the member", ga, sa, "Off: only their first visible Pawn scale.")
    local gp, sp = Opt("showPercent")
    L:Check("Show the change in percent", gp, sp)
    local gu, su = Opt("hideUnusable")
    L:Check("Skip classes that can't use the item", gu, su, "No values for members whose class can never use it, e.g. a bow for a shaman or plate for a mage. Mail and plate count from the start for the classes that learn them at 40.")
    local gt, st = Opt("teamTooltip")
    L:Cycle("Team in the item tooltip", {
        { value = "REPLACE", text = "Replace Pawn's lines" },
        { value = "ADD", text = "Add below Pawn's lines" },
        { value = "OFF", text = "Off" },
    }, gt, st)
    local gg, sg = Opt("greetOnLogin")
    L:Check("Message in chat on login", gg, sg)
    L:Space(4)
    status = H.StatusLine(page)
    status:SetWidth(COL_W)
    L:Add(status, 30)

    -- right: stored scales ------------------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Team scales")
    R:Note("The scales visible in Pawn on each character, stored here so offline members and clients without Pawn can be compared too.")
    local lines, lineKeys = {}, {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(COL_W, 18)
        local fs = UI.Label(row, "")
        fs:SetPoint("LEFT")
        fs:SetPoint("RIGHT")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        MMT.HoverMember(row, function() return lineKeys[i] end, function(tip, key)
            local rec = mod.ScalesOf(key)
            if not rec then tip:AddLine("No scales stored yet", 0.7, 0.7, 0.7) return end
            if rec.noPawn then tip:AddLine("Pawn is not installed on this character", 1, 0.5, 0.3) end
            for _, s in ipairs(rec.scales) do
                local n = 0
                for _ in pairs(s.values) do n = n + 1 end
                tip:AddLine(("%s (%d stats)"):format(s.name, n), 0.8, 0.8, 0.8)
            end
            tip:AddLine("Updated " .. MMT.Ago(rec.time), 0.6, 0.6, 0.6)
        end)
        R:Add(row, 18)
        lines[i] = fs
    end
    R:Space(6)
    R:Button("Send my scales to the team", function()
        mod.UpdateOwn(false)
        mod.SendScales()
        status.Show_("Your scales were sent.")
    end)
    R:Button("Request scales from team", function()
        mod.RequestAll()
        status.Show_("Asked the online team for their scales.")
    end)
    local clear = H.ConfirmButton(page, COL_W, "Clear stored scales", function()
        mod.Clear()
        status.Show_("Stored scales cleared. They fill in again as members come online.")
        MMT.RefreshConfig()
    end)
    R:Add(clear, UI.ROW + 2)

    page.OnRefresh = function()
        local pawn = mod.PawnInstalled() and "|cff55ff55found|r" or "|cffff5555NOT installed|r (stored scales, approximate stats)"
        local ic = mod.ItemCompareActive() and "|cff55ff55on|r" or "|cffff5555OFF|r - switch it on, Pawn Compare needs it"
        state:SetText("Pawn: " .. pawn .. "\nItem Compare: " .. ic)

        local members = MMT.SortedMembers()
        for i, fs in ipairs(lines) do
            local key = members[i]
            lineKeys[i] = key
            if key then
                local rec = mod.ScalesOf(key)
                local info
                if rec and #rec.scales > 0 then info = ScaleNames(rec)
                elseif rec and rec.noPawn then info = "no Pawn"
                else info = "no data yet" end
                local colour = MMT.IsOnline(key) and "|cffffffff" or "|cff999999"
                fs:SetText(("%s%s|r  |cff888888%s|r"):format(colour, MMT.FirstName(key), info))
            elseif i == 1 then
                fs:SetText("|cff888888No team members yet.|r")
            else
                fs:SetText("")
            end
        end
    end
    M:Listen("PAWN_SCALES_CHANGED", function() if page:IsVisible() then page.OnRefresh() end end)
end

M.Report = function(_, add)
    add(("-- Pawn Compare %s  pawn=%s itemCompare=%s own hash=%s"):format(mod.VERSION,
        tostring(mod.PawnInstalled()), tostring(mod.ItemCompareActive()), tostring(mod.OwnHash())))
    for key, rec in pairs(M.store.scales or {}) do
        add(("scales %s: %d (%s), hash %s, %s%s"):format(MMT.Repr(key), #rec.scales, ScaleNames(rec),
            tostring(rec.hash), MMT.Ago(rec.time), rec.noPawn and ", no Pawn" or ""))
    end
end
