-- MMT Pawn Compare: settings page (MODULES > Pawn Compare in /mmt) and the
-- module's part of the debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers

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

-- tiles of one row get the height of the tallest one's content
local function FitRow(row)
    local h = 0
    for _, r in ipairs(row) do h = math.max(h, -(tonumber(r[2].y) or -290) + 10) end
    for _, r in ipairs(row) do r[1]:SetHeight(h) end
    return h
end

-- Loot by Upgrade tab: switch, minimum gain and the scale each character's loot is judged by.
-- Returns its refresh function.
function mod.LootPage(panel, status)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local IN = TILE_W - 16

    local lt, L = Tile(panel, 0, 0, TILE_W, 300, "Master Loot by Upgrade", "Interface\\Icons\\INV_Misc_Coin_02")
    local gl, sl = Opt("lootByUpgrade")
    L:Check("Give gear to the biggest upgrade", gl, sl,
        "As master looter, Loot Distribution hands each gear item to the team member it is the biggest upgrade for, judged by the Pawn scale chosen for them on the right. Needs Pawn and Loot Distribution 1.4.0 or newer.")
    local gm, sm = Opt("lootMinGain")
    L:Slider("Minimum upgrade (%)", 0, 25, 1, gm, sm)
    L:Note("Upgrade = percent over what the member wears in that slot (the weaker ring or trinket; a two-hander against both hands). An empty slot beats any percentage. Equal: team order.")
    L:Note("Left out: classes that can't use the item, members below its level, members without scales or known equipment, and members the game doesn't offer the item to or whose bags are full. An upgrade for nobody: the roles and round robin decide as before. Bind on Pickup and quest items are never part of it.")
    local state = UI.Label(lt, "")
    state:SetWidth(IN)
    state:SetJustifyH("LEFT")
    state:SetWordWrap(true)
    L:Add(state, 44)

    local rt, R = Tile(panel, X2, 0, TILE_W, 300, "Scale per Character", "Interface\\Icons\\INV_Misc_Book_09")
    R:Note("The Pawn scale each character's loot is judged by. Default: their first visible scale. Shared with the team by the Sync button.")
    local members = MMT.SortedMembers()
    for i = 1, math.min(#members, 10) do
        local key = members[i]
        local cycle = R:Cycle(MMT.FirstName(key), function()
            local rec = mod.ScalesOf(key)
            local list = {}
            for _, sc in ipairs(rec and rec.scales or {}) do list[#list + 1] = { value = sc.name, text = sc.name } end
            if #list == 0 then list[1] = { value = "", text = "no scales yet" } end
            return list
        end, function()
            local sc = mod.LootScale(key)
            return sc and sc.name or ""
        end, function(v)
            M.db.lootScale = M.db.lootScale or {}
            M.db.lootScale[key] = (v ~= "") and v or nil
        end)
        MMT.HoverMember(cycle, function() return key end)
    end
    if #members == 0 then R:Note("No team members yet.") end
    FitRow({ { lt, L }, { rt, R } })

    return function()
        local why
        if not mod.LootHookAvailable() then why = "|cffff5555Loot Distribution 1.4.0 or newer is needed|r (switched on, with Master Looter)."
        elseif not mod.PawnReady() then why = "|cffff5555Pawn is not loaded on this character.|r"
        elseif not M.db.lootByUpgrade then why = "|cff888888Off: Loot Distribution's roles decide.|r"
        else why = "|cff55ff55On|r while this character is master looter. Check an item: /mmtpc loot <item>." end
        state:SetText(why)
    end
end

M.Page = function(_, page)
    ResetButton(page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 32)
    status:SetWidth(H.PAGE_W)
    local Tile, TILE_W, X2 = H.Tile, H.TILE_W, H.TILE_W + H.TILE_GAP
    local IN = TILE_W - 16
    local TOP = H.Intro(page, "Adds Pawn scores to the Item Compare tooltips: the hovered item is scored with each member's own Pawn scales and compared with what they have equipped.")

    local panels = H.TabStrip(page, TOP, {
        { "tips", "Tooltips and Scales", "INV_Misc_Spyglass_03" }, { "loot", "Loot by Upgrade", "INV_Misc_Coin_02" } }, 50)
    local tips = panels.tips

    -- Tooltips (left) ------------------------------------------------------------------------------------
    local lt, L = Tile(tips, 0, 0, TILE_W, 330, "Tooltips", "Interface\\Icons\\INV_Misc_Note_01")
    local state = UI.Label(lt, "")
    state:SetWidth(IN)
    state:SetJustifyH("LEFT")
    state:SetWordWrap(true)
    L:Add(state, 40)
    local gc, sc = Opt("showInCompare")
    L:Check("Show Pawn scores in Item Compare", gc, sc)
    local ga, sa = Opt("allScales")
    L:Check("Show every scale of the member", ga, sa, "Off: only their first visible Pawn scale.")
    local gp, sp = Opt("showPercent")
    L:Check("Show the change in percent", gp, sp)
    local gu, su = Opt("hideUnusable")
    L:Check("Skip classes that can't use the item", gu, su, "No values for members whose class can never use it, e.g. a bow for a shaman or plate for a mage. Mail and plate count from the start for the classes that learn them at 40.")
    local go, so = Opt("hideOffline")
    L:Check("Don't show offline team members", go, so, "Leaves members who are offline out of the team list in the item tooltip and out of the Pawn lines in Item Compare's tooltips. Off: their stored scales and gear are still compared.")
    local gt, st = Opt("teamTooltip")
    L:Cycle("Team in the item tooltip", {
        { value = "REPLACE", text = "Replace Pawn's lines" },
        { value = "ADD", text = "Add below Pawn's lines" },
        { value = "OFF", text = "Off" },
    }, gt, st)
    local gg, sg = Opt("greetOnLogin")
    L:Check("Message in chat on login", gg, sg)
    local gd, sd = Opt("askDelete")
    L:Check("Ask before changing scales for the team", gd, sd, "When a team member deletes or hides Pawn scales here and on the team, ask before doing the same on this character. Off: it is done right away. Also done right away while \"Auto-accept synced settings\" is on (MMT > Profiles).")

    -- Team scales (right) -----------------------------------------------------------------------------------
    local rt, R = Tile(tips, X2, 0, TILE_W, 330, "Team Scales", "Interface\\Icons\\INV_Misc_Book_09")
    R:Note("The scales visible in Pawn on each character, stored here so offline members and clients without Pawn can be compared too.")
    local lines, lineKeys = {}, {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, rt)
        row:SetSize(IN, 18)
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
    local clear = H.ConfirmButton(rt, IN, "Clear stored scales", function()
        mod.Clear()
        status.Show_("Stored scales cleared. They fill in again as members come online.")
        MMT.RefreshConfig()
    end)
    R:Add(clear, UI.ROW + 2)
    R:Space(6)
    R:Button("Pawn scales: list / delete...", function(self) mod.OpenScales(self) end)
    local manageNote = UI.Label(rt, "")
    manageNote:SetWidth(IN)
    manageNote:SetJustifyH("LEFT")
    manageNote:SetWordWrap(true)
    manageNote:SetTextColor(0.6, 0.6, 0.6)
    R:Add(manageNote, 30)
    FitRow({ { lt, L }, { rt, R } })

    local LootRefresh = mod.LootPage(panels.loot, status)

    page.OnRefresh = function()
        LootRefresh()
        local pawn = mod.PawnInstalled() and "|cff55ff55found|r" or "|cffff5555NOT installed|r (stored scales, approximate stats)"
        local ic = mod.ItemCompareActive() and "|cff55ff55on|r" or "|cffff5555OFF|r - switch it on, Pawn Compare needs it"
        state:SetText("Pawn: " .. pawn .. "\nItem Compare: " .. ic)
        manageNote:SetText(mod.PawnReady() and "Every Pawn scale here and on the team; delete them here and on the alts."
            or "|cffff5555Pawn is not loaded here:|r the list shows the team's scales; they can be deleted on the team.")

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
    for key, p in pairs(M.store.pendingDel or {}) do
        local t = {}
        for _, action in ipairs({ "names", "del", "hide", "show" }) do
            for n in pairs(p[action] or {}) do t[#t + 1] = action .. " " .. n end
        end
        add(("scale changes waiting for %s: %s"):format(MMT.Repr(key), table.concat(t, ", ")))
    end
    add(("loot by upgrade=%s active=%s hook=%s minGain=%s%%"):format(tostring(M.db.lootByUpgrade),
        tostring(mod.LootActive()), tostring(mod.LootHookAvailable()), tostring(M.db.lootMinGain)))
    for _, key in ipairs(MMT.SortedMembers()) do
        local sc = mod.LootScale(key)
        add(("  loot scale %s: %s%s"):format(MMT.Repr(key), sc and sc.name or "none",
            (M.db.lootScale or {})[key] and "" or " (first)"))
    end
    if mod.DeleteWaiting() > 0 then add(("scale change dialogs waiting: %d"):format(mod.DeleteWaiting())) end
end
