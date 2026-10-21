-- MMT Whispers: the alts' side.
-- A whisper from outside the team goes on to the receiver(s) ("Send them
-- to" on the settings page). A whisper FROM a receiver is passed on to
-- whoever last whispered this alt; "@Name text" (or "@First Last: text")
-- picks someone else. Messages, only when a whisper comes in or goes out:
--   MWF:<id>:<part>:<total>:<data>   data = "<kind>:<flags>:<name>:<text>"
--     kind  W whisper to this alt     I this alt whispered <name>
--           B Battle.net whisper      b this alt whispered a Battle.net friend
--           N a note for the receiver (nobody to pass the text on to, ...)
--     flags G = from a Game Master
-- Texts and names can be "secret" (chat lockdown in encounters, M+, PvP):
-- those stay on the alt.

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 200
local RECENT = 5

mod.recentSenders = {}   -- newest first: { name, bn = bnetAccountID }
mod.sent = 0             -- whispers forwarded this session

local function Secret(v) return v ~= nil and MMT.IsSecret(v) end

---------------------------------------------------------------------------
-- Who gets the whispers
---------------------------------------------------------------------------
function mod.LeaderKey()
    if not IsInGroup() then return nil end
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        if UnitExists(u) and MMT.Safe(UnitIsGroupLeader, u) then
            if UnitIsUnit(u, "player") then return MMT.PlayerFull() end
            local _, _, key = MMT.SplitUnit(u)
            return key and MMT.Resolve(key)
        end
    end
end

-- set of team keys (yourself included) the whispers go to
function mod.Receivers()
    local to, out = M.db.to or "LEADER", {}
    if to == "FTL" then
        -- MMT's FTL leader: the character you play ({FTL} in macros)
        local key = MMT.FTLLeader and MMT.FTLLeader()
        if type(key) == "string" then out[MMT.IsSelf(key) and MMT.PlayerFull() or key] = true end
    elseif to == "LEADER" then
        local key = mod.LeaderKey()
        if key then out[key] = true end
    elseif to:sub(1, 5) == "CHAR:" then
        out[to:sub(6)] = true
    elseif to:sub(1, 5) == "ROLE:" then
        local role = to:sub(6)
        for _, key in ipairs(MMT.SortedMembers()) do
            for _, r in ipairs(MMT.MemberRoleList(key)) do
                if r == role then out[key] = true end
            end
        end
    end
    return out
end

function mod.IAmReceiver()
    for key in pairs(mod.Receivers()) do
        if MMT.IsSelf(key) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Sending on
---------------------------------------------------------------------------
-- returns how many receivers it went to
function mod.SendOn(kind, flags, name, text)
    local data = ("%s:%s:%s:%s"):format(kind, flags or "", ((name or ""):gsub(":", "")), text)
    local id = tostring(math.random(1000, 9999))
    local total = math.max(1, math.ceil(#data / CHUNK))
    local n = 0
    local function Part(i) return ("MWF:%s:%d:%d:%s"):format(id, i, total, data:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    if M.db.to == "FTL" and MMT.SendToLeader then
        -- the core whispers the leader it knows, or asks the team "@L:" if that one is offline
        for i = 1, total do
            if MMT.SendToLeader(Part(i), "ALERT") ~= true then return 0 end
        end
        if kind ~= "N" then mod.sent = mod.sent + 1 end
        return 1
    end
    for key in pairs(mod.Receivers()) do
        if not MMT.IsSelf(key) and MMT.IsOnline(key) then
            n = n + 1
            local target = MMT.WhisperTarget and MMT.WhisperTarget(key) or key
            for i = 1, total do
                MMT.SendAddon(Part(i), "WHISPER", target)
            end
        end
    end
    if n > 0 and kind ~= "N" then mod.sent = mod.sent + 1 end
    return n
end

-- whispers that stay on the alt
function mod.Skip(text)
    if M.db.skipAddon and text:find("^%s*<[^>]+>") then return true end
    local low = text:lower()
    for word in (M.db.ignore or ""):gmatch("[^,]+") do
        word = word:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if word ~= "" and low:find(word, 1, true) then return true end
    end
    return false
end

local function Remember(name, bn)
    local list = mod.recentSenders
    for i = #list, 1, -1 do
        if list[i].name == name then table.remove(list, i) end
    end
    table.insert(list, 1, { name = name, bn = bn })
    while #list > RECENT do table.remove(list) end
end

-- the recent sender whose name starts with it ("anna", "anna smith"), or nil
local function Recent(name)
    local want = MMT.NormKey(name)
    for _, s in ipairs(mod.recentSenders) do
        if MMT.NormKey(s.name):sub(1, #want) == want then return s end
    end
end

-- a team member: whispered the way the core whispers them ("First Last" on this client)
local function Member(name)
    local key = MMT.Resolve and MMT.Resolve(name)
    if key then return { name = MMT.WhisperTarget and MMT.WhisperTarget(key) or name } end
end

-- "@anna hi" -> a recent sender starting with "anna", a team member, or the name as typed
local function Pick(name)
    return Recent(name) or Member(name) or { name = name }
end

---------------------------------------------------------------------------
-- Passing the receiver's text on
---------------------------------------------------------------------------
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function mod.PassOn(text)
    local name, rest = text:match("^@([^:]+):%s*(.+)$")
    if not name then
        -- characters here have two names: "@Alash Erelia hey" is for Alash Erelia when
        -- that's someone known (a recent sender or a team member), else the first word
        local first, last, more = text:match("^@(%S+)%s+(%S+)%s+(.+)$")
        local two = first and (first .. " " .. last)
        if two and (Recent(two) or Member(two)) then name, rest = two, more
        else name, rest = text:match("^@(%S+)%s+(.+)$") end
    end
    local target = name and Pick(name) or mod.recentSenders[1]
    local msg = name and rest or text
    if not target then
        mod.SendOn("N", "", "", "Nobody has whispered me yet. Start with @Name to choose who gets it.")
        return false
    end
    local ok
    if target.bn and BNSendWhisper then ok = pcall(BNSendWhisper, target.bn, msg)
    else ok = pcall(SendChat, msg, "WHISPER", nil, target.name) end
    if ok then Remember(target.name, target.bn) end
    return ok
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Battle.net friend -> a name that can travel (never the real name)
local function BNName(id)
    local info = id and C_BattleNet and C_BattleNet.GetAccountInfoByID and MMT.Safe(C_BattleNet.GetAccountInfoByID, id)
    if type(info) ~= "table" then return "Battle.net friend" end
    local game = info.gameAccountInfo
    local name = game and game.characterName
    if not name or name == "" or Secret(name) then
        name = info.battleTag and not Secret(info.battleTag) and info.battleTag:match("^[^#]+") or "Battle.net friend"
    end
    return name .. " (BN)"
end

M:On("CHAT_MSG_WHISPER", function(text, sender, _, _, _, flag)
    if Secret(text) or Secret(sender) or not text or not sender then return end
    if MMT.Resolve(sender) or MMT.IsSelf(sender) then
        -- from the team: the receiver whispering this alt = pass it on
        if M.db.relay and mod.Receivers()[MMT.Resolve(sender)] and not mod.IAmReceiver() then mod.PassOn(text) end
        return
    end
    if mod.Skip(text) then return end   -- stays on the alt, and isn't who an answer goes to
    Remember(sender)
    if not M.db.forward or mod.IAmReceiver() then return end
    mod.SendOn("W", (flag == "GM" or flag == "DEV") and "G" or "", sender, text)
end)

M:On("CHAT_MSG_WHISPER_INFORM", function(text, target)
    if Secret(text) or Secret(target) or not text or not target then return end
    if MMT.Resolve(target) or not (M.db.forward and M.db.informs) or mod.IAmReceiver() then return end
    mod.SendOn("I", "", target, text)
end)

M:On("CHAT_MSG_BN_WHISPER", function(text, ...)
    if not (M.db.forward and M.db.bn) or Secret(text) or not text then return end
    local id = select(12, ...)
    if Secret(id) then return end
    if mod.Skip(text) then return end
    local name = BNName(id)
    Remember(name, id)
    if mod.IAmReceiver() then return end
    mod.SendOn("B", "", name, text)
end)

M:On("CHAT_MSG_BN_WHISPER_INFORM", function(text, ...)
    if not (M.db.forward and M.db.bn and M.db.informs) or Secret(text) or not text then return end
    local id = select(12, ...)
    if Secret(id) or mod.IAmReceiver() then return end
    mod.SendOn("b", "", BNName(id), text)
end)
