-- MMT Quality of life: no taskbar icon flashing.
--
-- Our own take on the idea of the old "!NoFlash" addon (that one has no
-- license, so none of its code is used here). The game flashes the WoW icon on
-- the taskbar through one global function, FlashClientIcon(): Blizzard's UI
-- calls it for whispers, ready checks, invites, queues, entering combat, and
-- addons call it too (RXPGuides keeps its own copy of the function from when
-- it loads). We put a wrapper in its place when this file loads - before
-- RXPGuides and the others take their copy ("M" loads before "R") - and the
-- wrapper decides:
--   * feature off (or the module off): straight through, nothing looked at.
--   * on: where it comes from, from the call stack (keywords like ReadyCheck,
--     ChatFrame, LFG, PVP; a non-Blizzard AddOns folder = an addon); when the
--     stack says nothing, one frame later from the events seen right then
--     (READY_CHECK, CHAT_MSG_WHISPER, PARTY_INVITE_REQUEST, ...). Each source
--     has a checkbox (all blocked by default); a source let through flashes
--     only on the FTL leader (nfWhere LEADER, the group leader when no FTL
--     leader is known, always when solo), on every character or nowhere.
-- Swapping a Blizzard global means the Blizzard code calling it goes on
-- "tainted" (insecure) after the call. FlashClientIcon is no protected
-- function and none of its callers do protected things after it, so this is
-- harmless in practice (the old addon did the same for years); if it ever
-- shows up as "blocked action" in BugSack, switching the QoL module's addon
-- off in the AddOns list removes the wrapper completely. A flash the game
-- makes itself, outside the Lua UI, can't be stopped by any addon.

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local nf = { wrapped = false, passed = 0, blocked = {}, allowed = {}, last = nil }
mod.nf = nf

-- the sources, in the order of the checkboxes; keywords looked for in the call stack (plain text)
local SOURCES = {
    { id = "whisper", key = "nfWhisper", text = "Whispers", words = { "ChatFrame", "ChatHistory", "MessageEventHandler", "BNToast" } },
    { id = "ready", key = "nfReady", text = "Ready checks", words = { "ReadyCheck" } },
    { id = "group", key = "nfGroup", text = "Group invites, LFG and role checks", words = { "LFG", "LFD", "RolePoll", "PartyInvite", "GroupFinder", "QueueStatus" } },
    { id = "pvp", key = "nfPvp", text = "Battleground and PvP queues", words = { "PVP", "Battlefield", "Battleground" } },
    { id = "combat", key = "nfCombat", text = "Entering combat", words = { "SetInCombat" } },
    { id = "addons", key = "nfAddons", text = "Addons (RXPGuides and others)" },
    { id = "other", key = "nfOther", text = "Anything else" },
}
local byId = {}
for _, s in ipairs(SOURCES) do byId[s.id] = s; nf.blocked[s.id] = 0; nf.allowed[s.id] = 0 end
mod.NoFlashSources = SOURCES

-- events that come with a flash, for a stack that tells nothing (UIParent_OnEvent and the like)
local EVENTS = {
    CHAT_MSG_WHISPER = "whisper", CHAT_MSG_BN_WHISPER = "whisper",
    READY_CHECK = "ready",
    PARTY_INVITE_REQUEST = "group", GROUP_INVITE_CONFIRMATION = "group", LFG_PROPOSAL_SHOW = "group",
    LFG_ROLE_CHECK_SHOW = "group", ROLE_POLL_BEGIN = "group", LFG_LIST_APPLICATION_STATUS_UPDATED = "group",
    UPDATE_BATTLEFIELD_STATUS = "pvp", BATTLEFIELD_MGR_ENTRY_INVITE = "pvp", PVP_ROLE_POPUP_SHOW = "pvp",
    PLAYER_REGEN_DISABLED = "combat",
}
local seen = {}   -- [source id] = GetTime() of its last event
local NEAR = 0.1  -- an event this close to the flash (s) explains it

-- the stack without our own lines
local function Stack()
    if type(debugstack) ~= "function" then return "" end
    local ok, s = pcall(debugstack)
    if not ok or type(s) ~= "string" then return "" end
    local keep = {}
    for line in s:gmatch("[^\n]+") do
        if not line:find("NoFlash.lua", 1, true) then keep[#keep + 1] = line end
    end
    return table.concat(keep, "\n")
end

-- the AddOns folder a line is in, nil for Blizzard's own (Interface/FrameXML, AddOns/Blizzard_*)
local function AddonOf(line)
    local name = line:match("AddOns[\\/]([^\\/]+)[\\/]")
    if not name or name:find("^Blizzard_") then return nil end
    return name
end

-- source id from the stack, or nil; and who called (the first line, shortened)
function mod.NoFlashClassify(stack)
    local first = stack:match("^[^\n]+") or "?"
    for _, s in ipairs(SOURCES) do
        for _, w in ipairs(s.words or {}) do
            if stack:find(w, 1, true) then return s.id, first end
        end
    end
    for line in stack:gmatch("[^\n]+") do
        local addon = AddonOf(line)
        if addon then return "addons", addon end
    end
    return nil, first
end

local function ByEvent(at)
    local best, diff
    for id, t in pairs(seen) do
        local d = math.abs(t - at)
        if d <= NEAR and (not diff or d < diff) then best, diff = id, d end
    end
    return best
end

-- does an allowed flash show on this character?
local function FlashesHere()
    local where = M.db.nfWhere
    if where == "OFF" then return false end
    if where == "ALL" then return true end
    local leader = MMT.FTLLeader and MMT.FTLLeader()
    if leader then return MMT.IsSelf(leader) and true or false end
    if IsInGroup and IsInGroup() then return UnitIsGroupLeader and UnitIsGroupLeader("player") and true or false end
    return true
end
mod.NoFlashHere = FlashesHere

local original

local function Decide(id, who, ...)
    local s = byId[id] or byId.other
    local let = M.db[s.key] and FlashesHere()
    if let then nf.allowed[s.id] = nf.allowed[s.id] + 1 else nf.blocked[s.id] = nf.blocked[s.id] + 1 end
    nf.last = ("%s %s (%s)"):format(let and "let through" or "stopped", s.id, tostring(who))
    M:Debug("No flash: %s", nf.last)
    if M.db.nfLog then MMT.Print("No flash: %s.", nf.last) end
    if let then return original(...) end
end

local function OnFlash(...)
    if not mod.Active(F) then
        nf.passed = nf.passed + 1
        return original(...)
    end
    local ok, id, who = pcall(function() return mod.NoFlashClassify(Stack()) end)
    if not ok then return original(...) end   -- never break the caller: the flash goes through
    if id then return Decide(id, who, ...) end
    -- the stack says nothing: what happened around it (the event may reach us after the flash)
    local at = GetTime()
    local args = { n = select("#", ...), ... }
    local function Later() Decide(ByEvent(at) or "other", who, unpack(args, 1, args.n)) end
    if C_Timer and C_Timer.After then C_Timer.After(0, Later) else Later() end
end

-- the wrapper, at file load (see the top)
original = rawget(_G, "FlashClientIcon")
if type(original) == "function" then
    FlashClientIcon = function(...) return OnFlash(...) end
    nf.wrapped = true
end

if CreateFrame then
    local ev = CreateFrame("Frame")
    for name in pairs(EVENTS) do pcall(ev.RegisterEvent, ev, name) end   -- an event this client doesn't know is skipped
    ev:SetScript("OnEvent", function(_, event) seen[EVENTS[event]] = GetTime() end)
end
-- for the test: an event seen now
function mod.NoFlashSeen(event) if EVENTS[event] then seen[EVENTS[event]] = GetTime() end end

F = mod.Feature({
    key = "noflash", icon = "Spell_Nature_Sleep", title = "No flash",
    -- no addon: a local feature
    checkText = "Stop the taskbar icon from flashing",
    tip = "The WoW icon on the taskbar no longer flashes on this character for what you don't tick below. What you tick still flashes - only on the FTL leader unless you choose otherwise, so one ready check doesn't flash five windows.",
    notes = {
        "The game flashes the taskbar icon through one function; this feature puts itself in front of it and lets through only the sources you tick (none by default).",
        "Where a flash comes from is read from the call stack (ready check, chat, LFG, PvP, an addon's folder) or, if that says nothing, from what just happened (a whisper, an invite, a ready check).",
        "A flash the game makes itself, outside the interface code, can't be stopped by any addon. \"A chat line for each flash\" shows what was stopped or let through and from where - also in /mmt debug dump.",
        "Settings are part of the MMT profile: Sync to team gives the whole team the same choices. Uninstall the separate !NoFlash addon if you use this.",
    },
    Page = function(ui)
        ui.Cycle("Let ticked flashes through on", { { value = "LEADER", text = "Only the FTL leader" },
            { value = "ALL", text = "Every character" }, { value = "OFF", text = "No character" } }, "nfWhere")
        ui.Note("Flash for:")
        for _, s in ipairs(SOURCES) do ui.Check(s.text, s.key) end
        ui.Check("A chat line for each flash", "nfLog", "Says which flashes were stopped or let through, and where they came from.")
    end,
    Report = function(add)
        local t = {}
        for _, s in ipairs(SOURCES) do t[#t + 1] = ("%s %d/%d"):format(s.id, nf.blocked[s.id], nf.allowed[s.id]) end
        add(("No flash: wrapped=%s here=%s where=%s passed(off)=%d stopped/let through: %s last=%s"):format(tostring(nf.wrapped),
            tostring(FlashesHere()), tostring(M.db.nfWhere), nf.passed, table.concat(t, " "), tostring(nf.last or "-")))
    end,
})
