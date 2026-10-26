-- MMT Pawn Compare: manage Pawn scales across the team.
--
-- A window lists the Pawn scales on this character (Pawn's own list,
-- PawnGetAllScalesEx) together with the scales the team shares (M.store.scales),
-- and who has each one. Ticked scales get their action, here and on the team:
--   del   own (custom) scales are deleted, PawnDeleteScale       PCMP_DEL:<names>
--   hide  Pawn's built-in scales (read only, can't be deleted)
--         are hidden for the character, PawnSetScaleVisible      PCMP_HIDE:<names>
--   show  hidden ones (with "Show hidden") are shown again       PCMP_SHOW:<names>
-- Names are escaped like the scale sync and joined by "~". The alts find a
-- scale by its name or its display name (the team shares display names) and
-- ask first while askDelete is on; their changed scales then reach the team
-- through the usual pcs / PCMP_S sync. Members offline at that moment get it
-- whispered when they are next seen online
-- (M.store.pendingDel[key] = { del = {[name]=true}, hide = {...}, show = {...}, time }).
-- Visibility is per character in Pawn (the scales themselves are account-wide);
-- on Forever Pawn has no automatic spec mode, so a hidden scale stays hidden.

local _, mod = ...
local MMT = MMT
local M = mod.M

local MAX_MSG = 240
local PENDING_DAYS = 14

local ACTIONS = {
    del = { tag = "PCMP_DEL", verb = "Delete", past = "deleted" },
    hide = { tag = "PCMP_HIDE", verb = "Hide", past = "hid" },
    show = { tag = "PCMP_SHOW", verb = "Show again", past = "showed" },
}
local ORDER = { "del", "hide", "show" }
local OPPOSITE = { hide = "show", show = "hide" }

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

-- this character's scale with that name or display name
function mod.FindScale(name)
    local byLabel
    for _, s in ipairs(mod.PawnScales() or {}) do
        if s.name == name then return s end
        if s.label == name then byLabel = byLabel or s end
    end
    return byLabel
end

-- a scale this character has that Pawn lets us delete
function mod.CanDelete(name)
    if not (mod.PawnReady() and PawnDoesScaleExist and PawnDeleteScale) then return false end
    local ok, exists = pcall(PawnDoesScaleExist, name)
    if not (ok and exists) then return false end
    return not (PawnScaleIsReadOnly and PawnScaleIsReadOnly(name))
end

-- the scale the action would change here ({ name, label }), or nil
function mod.Target(action, name)
    if action == "del" then return mod.CanDelete(name) and { name = name } or nil end
    if not PawnSetScaleVisible then return nil end
    local s = mod.FindScale(name)
    if s and s.visible == (action == "hide") then return s end
end

-- rows for the window: { name, label, own = Pawn info | nil, holders = { team keys }, builtin, action }
-- own scales that are shown in Pawn (with showHidden also the hidden ones,
-- custom and built-in), then what only the team has (always shown there). A
-- team scale is built-in when it has the name of one of Pawn's built-in scales
-- here (every Pawn has the same ones; the team only shares display names).
-- action: del for own scales, hide for built-in ones, show for hidden built-in ones.
-- Sorted: own (custom) scales first, then built-in ones; this character's before the team's, then by name.
function mod.ScaleRows(showHidden)
    local rows, byName, byLabel, builtin = {}, {}, {}, {}
    for _, s in ipairs(mod.PawnScales() or {}) do
        if s.provider then builtin[s.name] = true; builtin[s.label] = true end
        if s.visible or showHidden then
            local r = { name = s.name, label = s.label, own = s, holders = {}, builtin = s.provider,
                action = not s.provider and "del" or (s.visible and "hide" or "show") }
            rows[#rows + 1] = r
            byName[s.name] = r
            byLabel[s.label] = byLabel[s.label] or r
        end
    end
    for _, key in ipairs(MMT.SortedMembers()) do
        local rec = not MMT.IsSelf(key) and mod.ScalesOf(key)
        for _, sc in ipairs(rec and rec.scales or {}) do
            local r = byName[sc.name] or byLabel[sc.name]
            if not r then
                local b = builtin[sc.name] or false
                r = { name = sc.name, label = sc.name, holders = {}, builtin = b, action = b and "hide" or "del" }
                rows[#rows + 1] = r
                byName[sc.name] = r
            end
            r.holders[#r.holders + 1] = key
        end
    end
    table.sort(rows, function(a, b)
        if a.builtin ~= b.builtin then return not a.builtin end
        if (a.own ~= nil) ~= (b.own ~= nil) then return a.own ~= nil end
        return a.label:lower() < b.label:lower()
    end)
    return rows
end

---------------------------------------------------------------------------
-- Changing scales here
---------------------------------------------------------------------------
local function RefreshPawn(deleted)
    if PawnUICurrentScale and deleted[PawnUICurrentScale] then PawnUICurrentScale = nil end   -- as Pawn's own Delete does
    if PawnUIFrame and PawnUIFrame:IsShown() then
        if PawnUIFrame_ScaleSelector_Refresh then pcall(PawnUIFrame_ScaleSelector_Refresh) end
        if PawnUI_ScalesTab_Refresh then pcall(PawnUI_ScalesTab_Refresh) end
    end
end

-- runs the action on the scales (names or display names) here; returns the changed names
function mod.ApplyLocal(action, names)
    local done, deleted = {}, {}
    for _, name in ipairs(names) do
        local s = mod.Target(action, name)
        if s then
            local ok, res
            if action == "del" then
                ok, res = pcall(PawnDeleteScale, s.name)
                if ok and res then deleted[s.name] = true end
            else
                ok, res = pcall(PawnSetScaleVisible, s.name, action == "show")
            end
            if ok and res then done[#done + 1] = s.label or s.name end
        end
    end
    if #done > 0 then
        RefreshPawn(deleted)
        M:Debug("%s %d scale(s): %s", ACTIONS[action].past, #done, table.concat(done, ", "))
        mod.UpdateOwn(true)   -- the team gets the new scales through the usual sync
        MMT.Fire("PAWN_SCALES_CHANGED", MMT.PlayerFull())
    end
    return done
end

function mod.DeleteLocal(names) return mod.ApplyLocal("del", names) end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- messages for the names, each below the message limit
local function Messages(action, names)
    local tag = ACTIONS[action].tag .. ":"
    local msgs, cur = {}, nil
    for _, name in ipairs(names) do
        local e = mod.Escape(name)
        if #tag + #e <= MAX_MSG then
            if cur and #cur + 1 + #e <= MAX_MSG then
                cur = cur .. "~" .. e
            else
                if cur then msgs[#msgs + 1] = cur end
                cur = tag .. e
            end
        end
    end
    if cur then msgs[#msgs + 1] = cur end
    return msgs
end
mod.ActionMessages = Messages
function mod.DeleteMessages(names) return Messages("del", names) end

local function Pending()
    M.store.pendingDel = M.store.pendingDel or {}
    return M.store.pendingDel
end

-- asks the team to do the action; members offline now get it later.
-- Returns how many members were asked now and how many later.
function mod.SendAction(action, names)
    if #names == 0 then return 0, 0 end
    for i, msg in ipairs(Messages(action, names)) do
        C_Timer.After((i - 1) * 0.2, function() MMT.SendToTeam(msg, true) end)
    end
    local now, later = 0, 0
    for _, key in ipairs(MMT.SortedMembers()) do
        if not MMT.IsSelf(key) then
            if MMT.IsOnline(key) then
                now = now + 1
            else
                later = later + 1
                local p = Pending()[key] or {}
                p[action] = p[action] or {}
                for _, n in ipairs(names) do
                    p[action][n] = true
                    if OPPOSITE[action] and p[OPPOSITE[action]] then p[OPPOSITE[action]][n] = nil end
                end
                p.time = time()
                Pending()[key] = p
            end
        end
    end
    M:Debug("%s sent: %s (%d now, %d later)", action, table.concat(names, ", "), now, later)
    return now, later
end

function mod.SendDelete(names) return mod.SendAction("del", names) end

-- a member offline at the time came online: whisper what they missed
local function SendPending(key, sender)
    local p = Pending()[key]
    if not p then return end
    Pending()[key] = nil
    if time() - (p.time or 0) > PENDING_DAYS * 86400 then return end
    if p.names then p.del = p.names end   -- 0.4.0 format
    local msgs = {}
    for _, action in ipairs(ORDER) do
        local names = {}
        for n in pairs(p[action] or {}) do names[#names + 1] = n end
        table.sort(names)
        for _, msg in ipairs(Messages(action, names)) do msgs[#msgs + 1] = msg end
    end
    for i, msg in ipairs(msgs) do
        C_Timer.After((i - 1) * 0.2, function() MMT.SendAddon(msg, "WHISPER", sender) end)
    end
    M:Debug("pending scale changes whispered to %s", MMT.Repr(sender))
end

M:Listen("XP_RECEIVED", function(key, sender)
    if not MMT.IsSelf(key) then SendPending(key, sender) end
end)

---------------------------------------------------------------------------
-- Receiving: one dialog per sender at a time, later requests join it
---------------------------------------------------------------------------
local queue, showing = {}, nil

local function Apply(from, ops)
    local parts = {}
    for _, action in ipairs(ORDER) do
        local done = ops[action] and mod.ApplyLocal(action, ops[action]) or {}
        if #done > 0 then parts[#parts + 1] = ACTIONS[action].past .. " " .. table.concat(done, ", ") end
    end
    if #parts > 0 then
        MMT.Print("Pawn Compare: %s, as %s did.", table.concat(parts, "; "), MMT.FirstName(from))
    end
end

-- what of ops can still be done here (names that went away are left out), and how many
local function Doable(ops)
    local t, n = {}, 0
    for _, action in ipairs(ORDER) do
        for _, name in ipairs(ops[action] or {}) do
            if mod.Target(action, name) then
                t[action] = t[action] or {}
                table.insert(t[action], name)
                n = n + 1
            end
        end
    end
    return t, n
end

local function ShowNext()
    if showing or #queue == 0 then return end
    local q = table.remove(queue, 1)
    local ops, n = Doable(q.ops)
    if n == 0 then return ShowNext() end
    showing = q
    local function done()
        showing = nil
        C_Timer.After(0, ShowNext)
    end
    local lines = {}
    for _, action in ipairs(ORDER) do
        if ops[action] then
            local labels = {}
            for _, name in ipairs(ops[action]) do
                local s = mod.FindScale(name)
                labels[#labels + 1] = s and s.label or name
            end
            lines[#lines + 1] = ACTIONS[action].verb .. ": " .. table.concat(labels, ", ")
        end
    end
    MMT.UI.Confirm(("%s changed these Pawn scales and asks you to do the same:\n\n%s"):format(
        MMT.FullDisplay(q.from), table.concat(lines, "\n")), "Do it", function()
        Apply(q.from, ops)
        done()
    end, "Keep mine", done)
end

function mod.Receive(from, action, names)
    local ops, n = Doable({ [action] = names })
    if n == 0 then
        M:Debug("%s from %s: none of %s here", action, MMT.Repr(from), table.concat(names, ", "))
        return
    end
    if not M.db.askDelete then return Apply(from, ops) end
    for _, q in ipairs(queue) do
        if q.from == from then
            q.ops[action] = q.ops[action] or {}
            for _, name in ipairs(ops[action]) do table.insert(q.ops[action], name) end
            return
        end
    end
    queue[#queue + 1] = { from = from, ops = ops }
    ShowNext()
end

function mod.ReceiveDelete(from, names) return mod.Receive(from, "del", names) end

function mod.DeleteWaiting() return #queue + (showing and 1 or 0) end

local BY_TAG = {}
for action, a in pairs(ACTIONS) do BY_TAG[a.tag] = action end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local tag, body = text:match("^(PCMP_[A-Z]+):(.+)$")
    local action = tag and BY_TAG[tag]
    if not action or MMT.IsSelf(key) then return end
    local names = {}
    for part in body:gmatch("[^~]+") do names[#names + 1] = mod.Unescape(part) end
    mod.Receive(key, action, names)
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local UI = MMT.UI
local H = MMT.ConfigHelpers
local W, ROWS, ROW_H = 460, 14, 20
local win
local selected = {}
local showHidden = false   -- this session only

-- ticked rows as { action = { names } }, how many, how many of them are here
local function Selected()
    local ops, n, own = {}, 0, 0
    for _, r in ipairs(mod.ScaleRows(showHidden)) do
        if selected[r.name] then
            ops[r.action] = ops[r.action] or {}
            table.insert(ops[r.action], r.name)
            n = n + 1
            if r.own then own = own + 1 end
        end
    end
    return ops, n, own
end

local SUFFIX = { hide = " |cff888888(built-in: hide)|r", show = " |cff888888(hidden: show again)|r" }

-- runs the ticked actions here (and asks the team); returns a status line
local function Run(team)
    local ops = Selected()
    local here, now, later = 0, 0, 0
    for _, action in ipairs(ORDER) do
        if ops[action] then
            here = here + #mod.ApplyLocal(action, ops[action])
            if team then now, later = mod.SendAction(action, ops[action]) end
        end
    end
    wipe(selected)
    if not team then return ("Changed %d scale(s) here."):format(here) end
    return ("Changed %d here; asked %d online member(s), %d more when they come online."):format(here, now, later)
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
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above MMT's settings window (DIALOG, or FULLSCREEN_DIALOG from the game options)
    f:SetToplevel(true)
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
    local hidden = UI.Check(f, 130, "Show hidden", function() return showHidden end, function(v)
        showHidden = v and true or false
        f.Refresh()
    end, "Also list the scales that are hidden in Pawn on this character (Pawn's built-in ones included). Off: only scales that are shown here or on a team member.")
    hidden:SetPoint("TOPRIGHT", -34, -8)
    f.info = UI.Label(f, "")
    f.info:SetPoint("TOPLEFT", 12, -30)
    f.info:SetPoint("TOPRIGHT", -12, -30)
    f.info:SetJustifyH("LEFT")
    f.info:SetWordWrap(true)

    f.list = H.List(f, W - 24, ROWS, ROW_H, function(list, i)
        local row = CreateFrame("Frame", nil, list)
        H.RowBackground(row, i)
        row.check = UI.Check(row, 250, "", function() return row.r and selected[row.r.name] end, function(v)
            if row.r then selected[row.r.name] = v or nil end
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
            if r.action == "hide" then
                GameTooltip:AddLine("One of Pawn's built-in scales: it can't be deleted, so ticked it is hidden in Pawn (for the character).", 1, 0.82, 0, true)
            elseif r.action == "show" then
                GameTooltip:AddLine("Hidden in Pawn on this character: ticked it is shown again.", 1, 0.82, 0, true)
            else
                GameTooltip:AddLine("Ticked it is deleted.", 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        end)
        row.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, r)
        row.r = r
        local colour = r.builtin and "|cffbbbbbb" or "|cffffffff"
        row.check.label:SetText(colour .. r.label .. "|r" .. (SUFFIX[r.action] or ""))
        row.check.Refresh()
        row.who:SetText("|cff999999" .. Holders(r) .. "|r")
    end)
    f.list:SetPoint("TOPLEFT", 12, -62)

    f.status = H.StatusLine(f)
    f.status:SetPoint("BOTTOMLEFT", 12, 40)
    f.status:SetPoint("BOTTOMRIGHT", -12, 40)

    f.here = H.ConfirmButton(f, 140, "Apply here", function()
        f.status.Show_(Run(false))
        f.Refresh()
    end)
    f.here:SetPoint("BOTTOMLEFT", 12, 12)
    UI.Tooltip(f.here, "Apply here", "On this character only: deletes the ticked own scales, hides the ticked built-in ones, shows the ticked hidden ones again. Click twice.")

    f.team = H.ConfirmButton(f, 200, "Apply here and on the team", function()
        f.status.Show_(Run(true))
        f.Refresh()
    end)
    f.team:SetPoint("LEFT", f.here, "RIGHT", 8, 0)
    UI.Tooltip(f.team, "Apply here and on the team", "Does the same here and asks every team member to do it to the scales with the same names (they are asked first unless they switched that off). Members offline now are asked when they come online. Click twice.")

    local none = UI.Button(f, 80, "Untick all", function() wipe(selected); f.Refresh() end)
    none:SetPoint("BOTTOMRIGHT", -12, 12)

    f.Refresh = function()
        if not f:IsShown() then return end
        local rows = mod.ScaleRows(showHidden)
        local pawn = mod.PawnReady() and "" or (mod.PawnInstalled()
            and "|cffff5555Pawn is still loading.|r " or "|cffff5555Pawn is not loaded on this character:|r only the team's scales, changed on the team. ")
        f.info:SetText(pawn .. "|cff999999Ticked: own scales are deleted, Pawn's built-in ones hidden. Scroll with the mouse wheel. The team's scales are the ones visible in their Pawn.|r")
        if #rows == 0 then f.status.Show_("No Pawn scales here or on the team.") end
        f.list:Render(rows)
        local _, n, own = Selected()
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

-- owner = the button it opens from: same scale as MMT's settings window
function mod.OpenScales(owner)
    win = win or Build()
    local own, parent = owner and owner.GetEffectiveScale and owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if own and parent and parent > 0 then
        win:SetScale(own / parent)
    else
        win:SetScale((MMT.ConfigScale and MMT.ConfigScale()) or 1)
    end
    win:Raise()
    win:Show()
    win.Refresh()
    return win
end

function mod.CloseScales()
    if win then win:Hide() end
end
