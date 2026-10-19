-- MMT Whispers: settings page and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Opt(key)
    return function() return M.db[key] end, function(v) M.db[key] = v end
end

local function Check(col, text, key, tip)
    local g, s = Opt(key)
    col:Check(text, g, s, tip)
end

-- "Send them to": the group leader, a character or everyone with a role
local function TargetChoices()
    local t = { { value = "LEADER", text = "Group leader" }, { header = true, text = "Character" } }
    for _, key in ipairs(MMT.SortedMembers()) do t[#t + 1] = { value = "CHAR:" .. key, text = MMT.FullDisplay(key) } end
    local roles = MMT.SortedRoleNames()
    if #roles > 0 then
        t[#t + 1] = { header = true, text = "Everyone with the role" }
        for _, r in ipairs(roles) do t[#t + 1] = { value = "ROLE:" .. r, text = r } end
    end
    local cur = M.db.to
    local found
    for _, c in ipairs(t) do if c.value == cur then found = true end end
    if not found and cur then table.insert(t, 2, { value = cur, text = (cur:gsub("^%u+:", "")) .. " (not in the team)" }) end
    return t
end

local function ChatChoices()
    local t = {}
    for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
        local name = MMT.Safe(GetChatWindowInfo, i)
        if type(name) == "string" and name ~= "" then t[#t + 1] = { value = i, text = i .. ". " .. name } end
    end
    if #t == 0 then t[1] = { value = 1, text = "1. General" } end
    local found
    for _, c in ipairs(t) do if c.value == M.db.chatFrame then found = true end end
    if not found then table.insert(t, 1, { value = M.db.chatFrame, text = M.db.chatFrame .. ". (closed window)" }) end
    return t
end

local function ReceiverNames()
    local t = {}
    for key in pairs(mod.Receivers()) do t[#t + 1] = MMT.IsSelf(key) and "you" or MMT.FirstName(key) end
    table.sort(t)
    return #t > 0 and table.concat(t, ", ") or "nobody (not in a group?)"
end

M.Page = function(_, page)
    local status = H.StatusLine(page)
    status:SetPoint("BOTTOMLEFT", 0, 2)
    status:SetWidth(COL2_X + COL_W - 190)

    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Forwarding (on the alts)")
    Check(L, "Forward whispers", "forward", "Whispers your alts get from players outside the team are shown on the receiver.")
    local tg, ts = Opt("to")
    L:Cycle("Send them to", TargetChoices, tg, function(v) ts(v); status.Show_("Whispers now go to: " .. ReceiverNames()) end)
    Check(L, "Also what the alts whisper", "informs", "The receiver also sees what an alt whispered to someone, e.g. the text it passed on.")
    Check(L, "Battle.net whispers too", "bn", "Shown with the friend's character name or BattleTag, never the real name.")
    Check(L, "Keep automatic answers on the alt", "skipAddon", "Whispers starting with <...>, like \"<DBM> ... is busy fighting\".")
    L:Note("Keep whispers on the alt that contain (comma separated, Enter):")
    local ignore = UI.EditBox(page, COL_W, "e.g. wts, boost", function(text, box)
        M.db.ignore = text
        box:ClearFocus()
        status.Show_(text ~= "" and ("Ignored: " .. text) or "Nothing ignored.")
    end)
    ignore:SetText(M.db.ignore or "")
    L:Add(ignore, UI.ROW + 4)

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("On the receiver")
    local cg, cs = Opt("chatFrame")
    R:Cycle("Chat window", ChatChoices, cg, cs)
    Check(R, "Timestamps", "stamp")
    Check(R, "Sound for a whisper", "sound")
    local rg, rs = Opt("reply")
    R:Cycle("Reply (R) goes to", {
        { value = "ALT", text = "The alt (it passes it on)" },
        { value = "DIRECT", text = "The sender, from you" },
        { value = "NONE", text = "Don't change it" },
    }, rg, rs)
    Check(R, "Alts pass my whispers on", "relay", "Whisper an alt from the receiver: the alt whispers the text to whoever last whispered it.")
    R:Note("Whisper an alt to answer through it. \"@Name text\" (or \"@First Last: text\") picks someone else than the last one. /mmtw test shows example lines.")

    page.OnRefresh = function()
        if not ignore:HasFocus() then ignore:SetText(M.db.ignore or ""); ignore:UpdatePlaceholder() end
        status.Show_("Receiver now: " .. ReceiverNames())
    end
end

M.Report = function(_, add)
    add(("-- Whispers %s: forward=%s to=%s receivers=%s me=%s relay=%s reply=%s bn=%s sent=%d"):format(mod.VERSION,
        tostring(M.db.forward), tostring(M.db.to), ReceiverNames(), tostring(mod.IAmReceiver()),
        tostring(M.db.relay), tostring(M.db.reply), tostring(M.db.bn), mod.sent))
    local senders = {}
    for _, s in ipairs(mod.recentSenders) do senders[#senders + 1] = s.name .. (s.bn and "*" or "") end
    add("recent senders: " .. (#senders > 0 and table.concat(senders, ", ") or "-"))
    for _, s in ipairs(mod.shown) do
        add(("shown %s ago: %s from %s (%s)"):format(MMT.Ago(s.time), s.kind, MMT.FirstName(s.alt), s.name))
    end
end
