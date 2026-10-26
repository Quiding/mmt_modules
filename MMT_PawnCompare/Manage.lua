-- MMT Pawn Compare: manage Pawn scales across the team.
--
-- A window lists every Pawn scale on this character (Pawn's own list,
-- PawnGetAllScalesEx) together with the scales the team shares (M.store.scales),
-- and who has each one. Ticked scales are deleted here with Pawn's own
-- PawnDeleteScale, and on the team with a message:
--   PCMP_DEL:<name>~<name>...   (names escaped like the scale sync)
-- The alts delete the same scales by name (asking first while askDelete is on),
-- then their changed scales reach the team through the usual pcs / PCMP_S sync.
-- Members offline at that moment get it whispered when they are next seen
-- online (M.store.pendingDel[key] = { names = { [name] = true }, time }).
-- Pawn's built-in scales (from a scale provider) are read only: they can only
-- be hidden in Pawn, never deleted.

local _, mod = ...
local MMT = MMT
local M = mod.M

local MAX_MSG = 240
local PENDING_DAYS = 14

---------------------------------------------------------------------------
-- Pawn's scales on this character
---------------------------------------------------------------------------
-- list of { name, label, visible, provider } or nil when Pawn isn't ready
function mod.PawnScales()
    if not (mod.PawnReady() and PawnGetAllScalesEx) then return nil end
    local ok, list = pcall(PawnGetAllScalesEx)
    if not ok or type(list) ~= "table" then return nil end
    local t = {}
    for _, info in ipairs(list) do
        t[#t + 1] = { name = info.Name, label = info.LocalizedName or info.Name,
            visible = info.IsVisible and true or false, provider = info.IsProvider and true or false }
    end
    return t
end

-- a scale this character has that Pawn lets us delete
function mod.CanDelete(name)
    if not (mod.PawnReady() and PawnDoesScaleExist and PawnDeleteScale) then return false end
    local ok, exists = pcall(PawnDoesScaleExist, name)
    if not (ok and exists) then return false end
    return not (PawnScaleIsReadOnly and PawnScaleIsReadOnly(name))
end

-- rows for the window: { name, label, own = Pawn info | nil, holders = { team keys }, deletable }
-- own custom scales (shown or hidden), Pawn's built-in ones only while shown,
-- then what only the team has. Sorted: own first, then by name.
function mod.ScaleRows()
    local rows, byName, byLabel = {}, {}, {}
    for _, s in ipairs(mod.PawnScales() or {}) do
        if not s.provider or s.visible then
            local r = { name = s.name, label = s.label, own = s, holders = {}, deletable = not s.provider }
            rows[#rows + 1] = r
            byName[s.name] = r
            byLabel[s.label] = byLabel[s.label] or r
        end
    end
    for _, key in ipairs(MMT.SortedMembers()) do
        local rec = not MMT.IsSelf(key) and mod.ScalesOf(key)
        for _, sc in ipairs(rec and rec.scales or {}) do
            -- the team shares Pawn's display name: the same as the name for own scales
            local r = byName[sc.name] or byLabel[sc.name]
            if not r then
                r = { name = sc.name, label = sc.name, holders = {}, deletable = true }
                rows[#rows + 1] = r
                byName[sc.name] = r
            end
            r.holders[#r.holders + 1] = key
        end
    end
    table.sort(rows, function(a, b)
        if (a.own ~= nil) ~= (b.own ~= nil) then return a.own ~= nil end
        return a.label:lower() < b.label:lower()
    end)
    return rows
end

---------------------------------------------------------------------------
-- Deleting
---------------------------------------------------------------------------
local function RefreshPawn(deleted)
    if PawnUICurrentScale and deleted[PawnUICurrentScale] then PawnUICurrentScale = nil end   -- as Pawn's own Delete does
    if PawnUIFrame and PawnUIFrame:IsShown() then
        if PawnUIFrame_ScaleSelector_Refresh then pcall(PawnUIFrame_ScaleSelector_Refresh) end
        if PawnUI_ScalesTab_Refresh then pcall(PawnUI_ScalesTab_Refresh) end
    end
end

-- deletes the scales (names) here; returns the list of deleted names
function mod.DeleteLocal(names)
    local done, set = {}, {}
    for _, name in ipairs(names) do
        if mod.CanDelete(name) then
            local ok, res = pcall(PawnDeleteScale, name)
            if ok and res then done[#done + 1] = name; set[name] = true end
        end
    end
    if #done > 0 then
        RefreshPawn(set)
        M:Debug("deleted %d scale(s): %s", #done, table.concat(done, ", "))
        mod.UpdateOwn(true)   -- the team gets the new scales through the usual sync
        MMT.Fire("PAWN_SCALES_CHANGED", MMT.PlayerFull())
    end
    return done
end

-- PCMP_DEL messages for the names, each below the message limit
local function Messages(names)
    local msgs, cur = {}, nil
    for _, name in ipairs(names) do
        local e = mod.Escape(name)
        if #"PCMP_DEL:" + #e <= MAX_MSG then
            if cur and #cur + 1 + #e <= MAX_MSG then
                cur = cur .. "~" .. e
            else
                if cur then msgs[#msgs + 1] = cur end
                cur = "PCMP_DEL:" .. e
            end
        end
    end
    if cur then msgs[#msgs + 1] = cur end
    return msgs
end
mod.DeleteMessages = Messages

local function Pending()
    M.store.pendingDel = M.store.pendingDel or {}
    return M.store.pendingDel
end

-- asks the team to delete the scales; members offline now get it later.
-- Returns how many members were asked now and how many later.
function mod.SendDelete(names)
    if #names == 0 then return 0, 0 end
    for i, msg in ipairs(Messages(names)) do
        C_Timer.After((i - 1) * 0.2, function() MMT.SendToTeam(msg, true) end)
    end
    local now, later = 0, 0
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) then
            if MMT.IsOnline(key) then
                now = now + 1
            else
                later = later + 1
                local p = Pending()[key] or { names = {} }
                for _, n in ipairs(names) do p.names[n] = true end
                p.time = time()
                Pending()[key] = p
            end
        end
    end
    M:Debug("delete sent: %s (%d now, %d later)", table.concat(names, ", "), now, later)
    return now, later
end

-- a member offline at the time came online: whisper what they missed
local function SendPending(key, sender)
    local p = Pending()[key]
    if not p then return end
    Pending()[key] = nil
    if time() - (p.time or 0) > PENDING_DAYS * 86400 then return end
    local names = {}
    for n in pairs(p.names) do names[#names + 1] = n end
    table.sort(names)
    for i, msg in ipairs(Messages(names)) do
        C_Timer.After((i - 1) * 0.2, function() MMT.SendAddon(msg, "WHISPER", sender) end)
    end
    M:Debug("pending delete whispered to %s", MMT.Repr(sender))
end

M:Listen("XP_RECEIVED", function(key, sender)
    if not MMT.IsSelf(key) then SendPending(key, sender) end
end)

---------------------------------------------------------------------------
-- Receiving: one dialog per sender at a time, later requests join it
---------------------------------------------------------------------------
local queue, showing = {}, nil

local function Apply(from, names)
    local done = mod.DeleteLocal(names)
    if #done > 0 then
        MMT.Print("Pawn Compare: deleted the Pawn scale(s) %s, as %s did.", table.concat(done, ", "), MMT.FirstName(from))
    end
end

local function ShowNext()
    if showing or #queue == 0 then return end
    local q = table.remove(queue, 1)
    -- what still exists by now
    local names = {}
    for _, n in ipairs(q.names) do if mod.CanDelete(n) then names[#names + 1] = n end end
    if #names == 0 then return ShowNext() end
    showing = q
    local function done()
        showing = nil
        C_Timer.After(0, ShowNext)
    end
    MMT.UI.Confirm(("%s deleted these Pawn scales and asks you to delete them too:\n\n%s"):format(
        MMT.FullDisplay(q.from), table.concat(names, ", ")), "Delete", function()
        Apply(q.from, names)
        done()
    end, "Keep", done)
end

function mod.ReceiveDelete(from, names)
    local mine = {}
    for _, n in ipairs(names) do if mod.CanDelete(n) then mine[#mine + 1] = n end end
    if #mine == 0 then
        M:Debug("delete from %s: none of %s here", MMT.Repr(from), table.concat(names, ", "))
        return
    end
    if not M.db.askDelete then return Apply(from, mine) end
    for _, q in ipairs(queue) do
        if q.from == from then
            for _, n in ipairs(mine) do q.names[#q.names + 1] = n end
            return
        end
    end
    queue[#queue + 1] = { from = from, names = mine }
    ShowNext()
end

function mod.DeleteWaiting() return #queue + (showing and 1 or 0) end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local body = text:match("^PCMP_DEL:(.+)$")
    if not body or MMT.IsSelf(key) then return end
    local names = {}
    for part in body:gmatch("[^~]+") do names[#names + 1] = mod.Unescape(part) end
    mod.ReceiveDelete(key, names)
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local UI = MMT.UI
local H = MMT.ConfigHelpers
local W, ROWS, ROW_H = 460, 14, 20
local win
local selected = {}

local function Selected(onlyOwn)
    local t = {}
    for _, r in ipairs(mod.ScaleRows()) do
        if selected[r.name] and r.deletable and (not onlyOwn or r.own) then t[#t + 1] = r.name end
    end
    return t
end

local function Holders(r)
    local t = {}
    if r.own then t[1] = r.own.visible and "you" or "you (hidden)" end
    for _, key in ipairs(r.holders) do t[#t + 1] = MMT.FirstName(key) end
    return table.concat(t, ", ")
end

local function Build()
    local f = CreateFrame("Frame", "MMTPawnScalesWindow", UIParent)
    f:SetSize(W, 120 + ROWS * ROW_H)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
    UI.Border(f, 0.31, 0.70, 1.00, 0.5)
    UI.CloseOnEscape(f)

    local title = UI.Label(f, "Pawn scales", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    f.info = UI.Label(f, "")
    f.info:SetPoint("TOPLEFT", 12, -30)
    f.info:SetPoint("TOPRIGHT", -12, -30)
    f.info:SetJustifyH("LEFT")
    f.info:SetWordWrap(true)

    f.list = H.List(f, W - 24, ROWS, ROW_H, function(list, i)
        local row = CreateFrame("Frame", nil, list)
        H.RowBackground(row, i)
        row.check = UI.Check(row, 230, "", function() return row.r and selected[row.r.name] end, function(v)
            if row.r and row.r.deletable then selected[row.r.name] = v or nil end
            f.Refresh()
        end)
        row.check:SetPoint("LEFT", 2, 0)
        row.who = UI.Label(row, "")
        row.who:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        row.who:SetPoint("RIGHT", -4, 0)
        row.who:SetJustifyH("LEFT")
        row.who:SetWordWrap(false)
        row.check:HookScript("OnEnter", function(self)
            local r = row.r
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(r.label)
            if r.name ~= r.label then GameTooltip:AddLine(r.name, 0.6, 0.6, 0.6) end
            GameTooltip:AddLine("Has it: " .. Holders(r), 1, 1, 1, true)
            if not r.deletable then
                GameTooltip:AddLine("One of Pawn's built-in scales: it can't be deleted, only hidden in Pawn.", 1, 0.5, 0.3, true)
            end
            GameTooltip:Show()
        end)
        row.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, r)
        row.r = r
        local colour = r.deletable and "|cffffffff" or "|cff888888"
        row.check.label:SetText(colour .. r.label .. "|r" .. (r.deletable and "" or " |cff888888(built-in)|r"))
        row.check.Refresh()
        row.who:SetText("|cff999999" .. Holders(r) .. "|r")
    end)
    f.list:SetPoint("TOPLEFT", 12, -62)

    f.status = H.StatusLine(f)
    f.status:SetPoint("BOTTOMLEFT", 12, 40)
    f.status:SetPoint("BOTTOMRIGHT", -12, 40)

    f.here = H.ConfirmButton(f, 140, "Delete here", function()
        local names = Selected(true)
        local done = mod.DeleteLocal(names)
        wipe(selected)
        f.status.Show_(#done > 0 and ("Deleted here: " .. table.concat(done, ", ")) or "Nothing deleted.", #done == 0)
        f.Refresh()
    end)
    f.here:SetPoint("BOTTOMLEFT", 12, 12)
    UI.Tooltip(f.here, "Delete here", "Deletes the ticked scales in Pawn on this character only. Click twice.")

    f.team = H.ConfirmButton(f, 200, "Delete here and on the team", function()
        local names = Selected(false)
        local done = mod.DeleteLocal(names)
        local now, later = mod.SendDelete(names)
        wipe(selected)
        f.status.Show_(("Deleted %d here; asked %d online member(s), %d more when they come online."):format(#done, now, later))
        f.Refresh()
    end)
    f.team:SetPoint("LEFT", f.here, "RIGHT", 8, 0)
    UI.Tooltip(f.team, "Delete here and on the team", "Deletes the ticked scales here and asks every team member to delete the scales with the same names (they are asked first unless they switched that off). Members offline now are asked when they come online. Click twice.")

    local none = UI.Button(f, 80, "Untick all", function() wipe(selected); f.Refresh() end)
    none:SetPoint("BOTTOMRIGHT", -12, 12)

    f.Refresh = function()
        if not f:IsShown() then return end
        local rows = mod.ScaleRows()
        local pawn = mod.PawnReady() and "" or (mod.PawnInstalled()
            and "|cffff5555Pawn is still loading.|r " or "|cffff5555Pawn is not loaded on this character:|r only the team's scales can be deleted, on the team. ")
        f.info:SetText(pawn .. "|cff999999Tick scales to delete them in Pawn. Scroll with the mouse wheel. The team's scales are the ones visible in their Pawn.|r")
        if #rows == 0 then f.status.Show_("No Pawn scales here or on the team.") end
        f.list:Render(rows)
        local n, own = #Selected(false), #Selected(true)
        f.here:SetEnabled(own > 0)
        f.here:SetAlpha(own > 0 and 1 or 0.4)
        f.team:SetEnabled(n > 0)
        f.team:SetAlpha(n > 0 and 1 or 0.4)
    end
    f:SetScript("OnShow", f.Refresh)
    M:Listen("PAWN_SCALES_CHANGED", function() f.Refresh() end)
    f:SetPoint("CENTER")
    f:Hide()
    return f
end

function mod.OpenScales()
    win = win or Build()
    win:Show()
    win.Refresh()
    return win
end

function mod.CloseScales()
    if win then win:Hide() end
end
