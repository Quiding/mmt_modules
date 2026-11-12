-- MMT Quality of life: RestedXP Guides with the party - it waits for the party
-- before its next step, and its objective lines show the team's counts.
--
-- Waiting (rxWait). RestedXP moves to its next step as soon as the step is done on THIS
-- character. With this feature a character whose step is done holds there
-- until every team member in the group who is on the same guide has done
-- that step too (or is past it); then they all move on.
--
-- How RestedXP advances (RXPGuides.lua, its update loop): addon.UpdateStepCompletion()
-- marks the step completed and sets addon.loadNextStep; the next frame calls
-- addon.SetStep(progress + 1). We post-hook UpdateStepCompletion (hooksecurefunc
-- on RestedXP's own table, nothing of Blizzard's) and clear loadNextStep while
-- someone is behind; setting it again later lets RestedXP go on by itself.
-- Clicking a step or the arrows in RestedXP's window still works as before.
--
-- Steps are compared by RestedXP's stepId (the line in the guide), so class or
-- race-only steps (missing in the others' guides) don't make anyone wait.
--   QRX:<stepId>:<done 0|1>:<guide key>   my guide and step, sent on every change
--   QRQ:                                  "send me your step" (group joined, enabled)
--
-- Team counts (rxCount). A "complete" objective line of the current step shows the
-- group's team members on that quest: TOTAL (default) puts the sum in place of
-- RestedXP's own count ("Linen Cloth: 23/30") - for kills (shared by the group) the
-- count of who needs the most ("Kobold Vermin slain: 5/10 (Bob)"), LOWEST adds the lowest
-- ("7/10 (team 6/10)"), EACH adds the others' ("7/10 (Bob 10, Cara 6)"), OFF
-- leaves it; the tooltip always gets each member's count. The counts come
-- from MMT's Quest Tracker, which already syncs every member's quest log
-- (M.store.quests[key].quests[questID].obj[i] = { have, need, done }); its
-- objectives are in the game's order, like RestedXP's element.obj. We post-hook
-- addon.UpdateQuestCompletionData(ref) (it rebuilds element.text from the
-- quest log each time) and run it again when the Quest Tracker gets new data.
--
-- Item lines (".collect": "Snickerfang Jowl: 0/3", and the Blasted Lands list) count
-- bags, not quest objectives: the members' counts come from MMT's Team Inventory, which
-- shares the bags (M.store.chars[key].b[itemID], .k the bank). We post-hook addon.Call
-- (RestedXP runs every line's function through it) and change those lines' text after
-- RestedXP wrote it; a ticker runs the lines again so the others' looting shows.

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local others = {}        -- [team key] = { guide, stepId, done, time }
local held = nil         -- { guide, stepId, since, said } while we hold a finished step
local hooked = false
local ticker
local skipOnce = false   -- /mmtqol rxp go: let this one step through
local passed = nil       -- { guide, stepId }: released by hand or the time limit, not held again
local rxs = { holds = 0, released = 0, sent = 0, got = 0 }
mod.rxs = rxs

local function RXP()
    local a = rawget(_G, "RXP")
    if type(a) == "table" and type(a.SetStep) == "function" and type(a.UpdateStepCompletion) == "function" then return a end
end

-- my guide key, current step index and its stepId (nil when no guide is loaded)
local function Current()
    local a = RXP()
    local guide = a and a.currentGuide
    if not guide or guide.empty or type(guide.key) ~= "string" or type(guide.steps) ~= "table" then return nil end
    local ok, index = pcall(a.GetGuideProgress)
    index = ok and tonumber(index)
    local step = index and guide.steps[index]
    if not step or not step.stepId then return nil end
    return guide, index, step.stepId
end

-- stepId -> index in this guide (cached per guide table)
local indexCache = setmetatable({}, { __mode = "k" })
local function IndexOf(guide, stepId)
    local map = indexCache[guide]
    if not map then
        map = {}
        for i, s in ipairs(guide.steps) do if s.stepId then map[tostring(s.stepId)] = i end end
        indexCache[guide] = map
    end
    return map[tostring(stepId)]
end

local function Send(done)
    local guide, _, stepId = Current()
    if not guide then return end
    MMT.SendToTeam(("QRX:%s:%d:%s"):format(tostring(stepId), done and 1 or 0, mod.Esc(guide.key)), true)
    rxs.sent = rxs.sent + 1
end

-- team members in my group, connected, whose last report is about my guide
local function Grouped(key)
    local unit = MMT.UnitForMember and MMT.UnitForMember(key)
    if not unit then return nil end
    local ok, on = pcall(UnitIsConnected, unit)
    if ok and on == false then return nil end
    return unit
end

-- the members my finished step waits for: same guide, behind me or on my step and not done
local function Behind()
    local guide, index = Current()
    if not guide then return {} end
    local l = {}
    for key, s in pairs(others) do
        if not MMT.IsSelf(key) and s.guide == guide.key and Grouped(key) then
            local theirs = IndexOf(guide, s.stepId)
            -- a step our guide doesn't have (their class / race only): no wait
            if theirs and (theirs < index or (theirs == index and not s.done)) then l[#l + 1] = key end
        end
    end
    table.sort(l)
    return l
end

local function Names(keys)
    local t = {}
    for i, k in ipairs(keys) do t[i] = MMT.ShownName and MMT.ShownName(k) or (k:match("^[^-]+") or k) end
    return table.concat(t, ", ")
end

local function Release(why, force)
    local a = RXP()
    if not held then return end
    if force then passed = { guide = held.guide, stepId = held.stepId } end
    M:Debug("RestedXP: step %s released (%s)", tostring(held.stepId), why)
    if held.said and M.db.rxChat then MMT.Print("|cff88ccffRestedXP:|r everyone is done, next step.") end
    local guide, _, stepId = Current()
    local still = guide and guide.key == held.guide and stepId == held.stepId
    held = nil
    rxs.released = rxs.released + 1
    -- only while RestedXP is still on that step (else it would skip one)
    if a and still then a.loadNextStep = true end
end

-- after RestedXP's own completion check: hold the step while someone is behind
local function AfterCompletion()
    local a = RXP()
    if not a or not a.loadNextStep or not mod.Active(F) or not M.db.rxWait or not IsInGroup() then return end
    local guide, index, stepId = Current()
    if not guide then return end
    -- only a finished current step is held (another step shown beside it - a sticky one - finishing
    -- doesn't make the current one "done"; its objectives are held one by one, AfterObjective)
    if not guide.steps[index].completed then return end
    if skipOnce then skipOnce = false return end
    if passed and passed.guide == guide.key and passed.stepId == stepId then return end
    local behind = Behind()
    if #behind == 0 then
        if held then held = nil end
        return
    end
    a.loadNextStep = false
    if not (held and held.guide == guide.key and held.stepId == stepId) then
        held = { guide = guide.key, stepId = stepId, index = index, since = GetTime() }
        rxs.holds = rxs.holds + 1
        Send(true)
        if M.db.rxChat then
            MMT.Print("|cff88ccffRestedXP:|r step %d done - waiting for %s.", index, Names(behind))
            held.said = true
        end
        M:Debug("RestedXP: holding step %d (%s) for %s", index, tostring(stepId), Names(behind))
    end
end

-- while holding: go on once nobody is behind any more, or after the time limit
local function Check()
    if not held then return end
    local guide, _, stepId = Current()
    -- moved on some other way (a click in RestedXP's window, another guide): forget the hold
    if not guide or guide.key ~= held.guide or stepId ~= held.stepId then held = nil return end
    if not mod.Active(F) or not M.db.rxWait or not IsInGroup() then Release("off or not grouped") return end
    local limit = (tonumber(M.db.rxTimeout) or 0) * 60
    if limit > 0 and GetTime() - held.since >= limit then Release("time limit", true) return end
    if #Behind() == 0 then Release("everyone done") end
end

local function OnStep(from, _, body)
    local stepId, done, key = body:match("^([^:]+):([01]):(.*)$")
    if not stepId then return end
    others[from] = { guide = mod.Unesc(key), stepId = stepId, done = done == "1", time = GetTime() }
    rxs.got = rxs.got + 1
    Check()
end

local lastAnswer = 0
local function OnAsk()
    if GetTime() - lastAnswer < 2 then return end
    lastAnswer = GetTime()
    Send(held ~= nil)
end

local function Ask()
    if mod.Active(F) and IsInGroup() then MMT.SendToTeam("QRQ:", true) end
end

---------------------------------------------------------------------------
-- Team counts on the objective lines
---------------------------------------------------------------------------
local refs = setmetatable({}, { __mode = "k" })   -- [element] = the ref RestedXP updates it with
local HoldObjective
local MemberLines

-- the Quest Tracker's synced quest logs, or nil (module missing or off)
local function QuestData()
    local mods = rawget(MMT, "modules")
    local qt = type(mods) == "table" and mods.QuestTracker
    local store = type(qt) == "table" and qt.enabled and qt.store
    return type(store) == "table" and type(store.quests) == "table" and store.quests or nil
end

-- me and the group's team members on that quest: { key, have, need, self }, me first;
-- nil unless someone besides me has it
local function TeamCounts(questID, objIndex, cap)
    local db = QuestData()
    if not db then return nil end
    local rows, others = {}, 0
    for key, rec in pairs(db) do
        local me = MMT.IsSelf(key)
        local q = type(rec) == "table" and type(rec.quests) == "table" and rec.quests[questID]
        local o = q and type(q.obj) == "table" and q.obj[objIndex]
        if o and (me or Grouped(key)) then
            local need = tonumber(o.need) or 0
            if cap then need = math.min(need, cap) end
            local have = math.min(tonumber(o.have) or 0, need)
            if q.state == 1 or o.done then have = need end
            rows[#rows + 1] = { key = key, have = have, need = need, self = me }
            if not me then others = others + 1 end
        end
    end
    if others == 0 then return nil end
    table.sort(rows, function(x, y)
        if x.self ~= y.self then return x.self end
        return x.key < y.key
    end)
    return rows
end

-- a "slay" objective (the game's type "monster"): the group gets the kill together, so a
-- sum means nothing - who needs the most does. RestedXP just read the objectives (cached).
local function IsKill(el)
    local a = RXP()
    if not (a and type(a.GetQuestObjectives) == "function") then return false end
    local ok, objs = pcall(a.GetQuestObjectives, el.questId, el.step and el.step.index)
    local o = ok and type(objs) == "table" and objs[el.obj]
    return type(o) == "table" and o.type == "monster"
end

-- Waiting, objective by objective: an objective done here stays open (unticked, its step stays)
-- while a team member in the group who has the quest still needs it. This holds every step
-- RestedXP shows - also the ones beside the current step (sticky), which finish on their own
-- without RestedXP moving on. The Quest Tracker's new data runs it again (RefreshObjectives).
local heldObj = setmetatable({}, { __mode = "k" })    -- [element] = names waited for
local passedObj = setmetatable({}, { __mode = "k" })  -- [element] = true: let go by hand
HoldObjective = function(ref, el, rows)
    if not el.completed or not M.db.rxWait or not IsInGroup() or passedObj[el] then heldObj[el] = nil return end

    local behind = {}
    for _, r in ipairs(rows) do if not r.self and r.have < r.need then behind[#behind + 1] = r.key end end
    if #behind == 0 then
        if heldObj[el] and M.db.rxChat then MMT.Print("|cff88ccffRestedXP:|r everyone has %s.", el.title or "it") end
        heldObj[el] = nil
        return
    end
    -- undo RestedXP's tick: not completed, not skipped (its step check reads both)
    el.completed, el.skip = false, false
    local a = RXP()
    if a and a.SetElementIncomplete then pcall(a.SetElementIncomplete, ref) end
    local names = Names(behind)
    if heldObj[el] ~= names then
        if not heldObj[el] then rxs.holds = rxs.holds + 1 end
        if M.db.rxChat then MMT.Print("|cff88ccffRestedXP:|r %s done - waiting for %s.", el.title or "objective", names) end
        heldObj[el] = names
    end
end

-- Go on now: every objective waited on counts as done here
local function PassObjectives()
    local n = 0
    for el in pairs(heldObj) do passedObj[el] = true; heldObj[el] = nil; n = n + 1 end
    return n
end

-- each member's count, a line each (the line's tooltip)
function MemberLines(rows)
    local lines = {}
    for _, r in ipairs(rows) do
        local c = r.have >= r.need and "|cff55ff55" or "|cffffffff"
        lines[#lines + 1] = ("   %s: %s%d/%d|r"):format(Names({ r.key }), c, r.have, r.need)
    end
    return table.concat(lines, "\n")
end

local function AfterObjective(ref)
    local el = type(ref) == "table" and ref.element
    if type(el) ~= "table" or el.tag ~= "complete" or not el.obj or type(el.questId) ~= "number" then return end
    if (tonumber(el.flags) or 0) % 2 == 1 then return end   -- a line RestedXP doesn't show
    refs[el] = ref
    if not mod.Active(F) or not (el.step and el.step.active) then return end
    local rows = TeamCounts(el.questId, el.obj, el.objMax)
    if not rows then heldObj[el] = nil return end
    HoldObjective(ref, el, rows)
    local style = M.db.rxCount
    if style == "OFF" or type(el.text) ~= "string" or not el.text:find("%S") then return end
    el.text = mod.RestedXPCountText(el.text, rows, style, IsKill(el))
    el.tooltipText = (type(el.tooltipText) == "string" and (el.tooltipText .. "\n") or "") .. MemberLines(rows)
    local a = RXP()
    if a and a.UpdateStepText then a.UpdateStepText(ref) end
end

-- RestedXP's line with the team's counts (rows: TeamCounts, me first)
local BLUE = "|cff88ccff"

-- the line with its last "have/need" (RestedXP's own count) replaced, or nil when it has none
local function SwapCount(text, count)
    local s, e, at, stop = 1, nil, nil, nil
    while true do
        s, e = text:find("%d+/%d+", s)
        if not s then break end
        at, stop, s = s, e, e + 1
    end
    if at then return text:sub(1, at - 1) .. count .. text:sub(stop + 1) end
end

-- kill objectives: the count of whoever needs the most, and who ("you" for this character)
local function Neediest(text, rows)
    local low
    for _, r in ipairs(rows) do if not low or r.have < low.have then low = r end end
    local who, same = {}, true
    for _, r in ipairs(rows) do
        if r.have ~= low.have then same = false end
        if r.have == low.have then who[#who + 1] = r.self and "you" or Names({ r.key }) end
    end
    local count = ("%s%d/%d|r"):format(BLUE, low.have, low.need)
    local tag = ""
    if not same then
        tag = #who > 2 and ("%s +%d"):format(who[1], #who - 1) or table.concat(who, ", ")
        tag = (" %s(%s)|r"):format(BLUE, tag)
    end
    local swapped = SwapCount(text, count)
    if swapped then return swapped .. tag end
    return ("%s %s(team %d/%d%s)|r"):format(text, BLUE, low.have, low.need, same and "" or (", " .. (#who > 2 and ("%s +%d"):format(who[1], #who - 1) or table.concat(who, ", "))))
end

function mod.RestedXPCountText(text, rows, style, kill)
    if style == "LOWEST" then
        local low
        for _, r in ipairs(rows) do if not low or r.have < low.have then low = r end end
        return ("%s %s(team %d/%d)|r"):format(text, BLUE, low.have, low.need)
    elseif style == "EACH" then
        local t = {}
        for _, r in ipairs(rows) do if not r.self then t[#t + 1] = ("%s %d"):format(Names({ r.key }), r.have) end end
        return ("%s %s(%s)|r"):format(text, BLUE, table.concat(t, ", "))
    end
    -- TOTAL: kills - who needs the most; anything else - the sum, both in place of RestedXP's own count
    if kill then return Neediest(text, rows) end
    local have, need = 0, 0
    for _, r in ipairs(rows) do have, need = have + r.have, need + r.need end
    return SwapCount(text, ("%s%d/%d|r"):format(BLUE, have, need))
        or ("%s %s(team %d/%d)|r"):format(text, BLUE, have, need)
end

-- the Quest Tracker got new data: rebuild the current step's objective lines
local refreshQueued = false
local function RefreshObjectives()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function()
        refreshQueued = false
        local a = RXP()
        if not a or not mod.Active(F) then return end
        for el, ref in pairs(refs) do
            if el.step and el.step.active then pcall(a.UpdateQuestCompletionData, ref) end
        end
    end)
end

---------------------------------------------------------------------------
-- Item lines: the team's bag counts (Team Inventory)
---------------------------------------------------------------------------
-- Team Inventory's shared bags, or nil (module missing or off)
local function TeamBags()
    local mods = rawget(MMT, "modules")
    local ti = type(mods) == "table" and mods.TeamInventory
    local store = type(ti) == "table" and ti.enabled and ti.store
    return type(store) == "table" and type(store.chars) == "table" and store.chars or nil
end

-- a member's count of the items ("8391" or "8391,8392": RestedXP's element.ids)
local function BagCount(rec, ids, bank)
    local n = 0
    for s in tostring(ids):gmatch("%d+") do
        local id = tonumber(s)
        n = n + (type(rec.b) == "table" and tonumber(rec.b[id]) or 0)
        if bank then n = n + (type(rec.k) == "table" and tonumber(rec.k[id]) or 0) end
    end
    return n
end

-- me (mine: RestedXP's own count) and the group's team members whose bags are shared:
-- rows like TeamCounts, me first; nil unless someone besides me is there
local function TeamItemCounts(ids, mine, need, bank)
    local chars = TeamBags()
    if not chars or not need or need <= 0 then return nil end
    local rows = { { key = (MMT.PlayerFull and MMT.PlayerFull()) or "", have = math.min(mine or 0, need), need = need, self = true } }
    for key, rec in pairs(chars) do
        if type(rec) == "table" and not MMT.IsSelf(key) and Grouped(key) then
            rows[#rows + 1] = { key = key, have = math.min(BagCount(rec, ids, bank), need), need = need }
        end
    end
    if #rows < 2 then return nil end
    table.sort(rows, function(x, y)
        if x.self ~= y.self then return x.self end
        return x.key < y.key
    end)
    return rows
end
mod.RestedXPItemCounts = TeamItemCounts

local BLASTED = { 8396, 8394, 8392, 8393, 8391 }   -- RestedXP's Blasted Lands list (functions.lua)
local itemText = setmetatable({}, { __mode = "k" })    -- [element] = the text we last gave it
local itemRefs = setmetatable({}, { __mode = "k" })    -- [ref] = its tag, to run it again

-- the text of an item line with the team's counts, or nil when it stays as it is
function mod.RestedXPItemText(tag, el, style)
    local text = el.text
    if tag == "blastedLands" then
        local byName = {}
        local a = RXP()
        for _, id in ipairs(BLASTED) do
            local n = GetItemInfo and GetItemInfo(id)
            if n then byName[n] = id end
            n = a and type(a.GetItemName) == "function" and a.GetItemName(id)
            if n then byName[n] = id end
        end
        local out, any = {}, false
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local name, have, need = line:match("^%- (.-): (%d+)/(%d+)%s*$")
            local rows = name and byName[name] and TeamItemCounts(byName[name], tonumber(have), tonumber(need), false)
            if rows then any = true end
            out[#out + 1] = rows and mod.RestedXPCountText(line, rows, style, false) or line
        end
        return any and table.concat(out, "\n") or nil
    end
    local need = tonumber(el.numRequired) or 0
    if el.hideText or el.textOnly or need >= 1000000 then return nil end   -- not shown / "collect them all"
    local rows = TeamItemCounts(el.ids or el.id, tonumber(el.count) or 0, need, el.includeBank)
    if not rows then return nil end
    -- the item line is the last one (the guide's own words may come first)
    local head, line = text:match("^(.*\n)(.-)$")
    if not line then head, line = "", text end
    return head .. mod.RestedXPCountText(line, rows, style, false), rows
end

local function AfterItems(tag, ref)
    local el = type(ref) == "table" and ref.element
    if type(el) ~= "table" or not mod.Active(F) or not (el.step and el.step.active) then return end
    itemRefs[ref] = tag
    local style = M.db.rxCount
    if style == "OFF" or type(el.text) ~= "string" or not el.text:find("%S") then return end
    local text, rows = mod.RestedXPItemText(tag, el, style)
    if not text then return end
    el.text = text
    if rows then el.tooltipText = (type(el.tooltipText) == "string" and (el.tooltipText .. "\n") or "") .. MemberLines(rows) end
    -- RestedXP redraws a line only when its own count changed: ours may change alone
    if itemText[el] ~= text then
        itemText[el] = text
        local a = RXP()
        if a and a.UpdateStepText then a.UpdateStepText(ref) end
    end
end

-- the others' bags changed (Team Inventory gets them): run the shown item lines again
local function RefreshItems()
    local a = RXP()
    if not a or not mod.Active(F) or M.db.rxCount == "OFF" or not TeamBags() then return end
    for ref, tag in pairs(itemRefs) do
        local el = ref.element
        if type(el) == "table" and el.step and el.step.active and type(ref.callback) == "function" then
            a.Call(tag, ref.callback, ref, "WindowUpdate")
        else
            itemRefs[ref] = nil
        end
    end
end

local function Hook()
    if hooked then return true end
    local a = RXP()
    if not a then return false end
    if type(a.UpdateQuestCompletionData) == "function" then
        hooksecurefunc(a, "UpdateQuestCompletionData", function(ref)
            local ok, err = pcall(AfterObjective, ref)
            if not ok then M:Debug("RestedXP team count: %s", tostring(err)) end
        end)
    end
    if type(a.Call) == "function" then
        hooksecurefunc(a, "Call", function(tag, _, ref)
            if tag ~= "collect" and tag ~= "blastedLands" then return end
            local ok, err = pcall(AfterItems, tag, ref)
            if not ok then M:Debug("RestedXP team item count: %s", tostring(err)) end
        end)
    end
    hooksecurefunc(a, "UpdateStepCompletion", function()
        local ok, err = pcall(AfterCompletion)
        if not ok then M:Debug("RestedXP hold: %s", tostring(err)) end
    end)
    -- a new step: tell the team (done = 0)
    hooksecurefunc(a, "SetStep", function()
        if not mod.Active(F) then return end
        C_Timer.After(0, function() pcall(Send, false) end)
    end)
    hooked = true
    return true
end

F = mod.Feature({
    key = "rxp", icon = "Spell_Nature_Sleep", iconPath = [[Interface\AddOns\RXPGuides\Textures\rxp_logo-64]], slash = "rxp", addon = "RXPGuides", title = "RestedXP with the party", tabText = "RestedXP",
    checkText = "RestedXP Guides with the party",
    tip = "RestedXP Guides waits for the party before its next step, and its objective lines show the team's counts (see the options).",
    notes = {
        "Waiting: a quest objective you've done stays open (and its step with it) while a team member in your group who has the quest still needs it - also on steps RestedXP shows beside the current one. Other steps: each character tells the team its guide and step, and a finished step waits until everyone on the same guide has done it or is past it.",
        "Only team members in your group who have this module on and RestedXP on the same guide count. Steps only for one class or race don't make anyone wait. Clicking a step or RestedXP's arrows still moves at once; /mmtqol rxp go lets the step you're waiting on go now.",
        "Team counts: objective lines count the whole group - by default the team's total in place of yours (\"Linen Cloth: 23/30\"); kills are shared by the group, so they show who needs the most (\"Kobold Vermin slain: 5/10 (Bob)\"). Or the lowest, or each member's; the line's tooltip shows each one's. They come from MMT's Quest Tracker, which has to be on (it shares the quest logs).",
        "Item lines (\"Snickerfang Jowl: 0/3\", the Blasted Lands list) count what is in the bags: the others' counts come from MMT's Team Inventory, which has to be on.",
    },
    tags = { QRX = OnStep, QRQ = OnAsk },
    OnEnable = function()
        Hook()
        if not ticker and C_Timer and C_Timer.NewTicker then
            local n = 0
            ticker = C_Timer.NewTicker(1, function()
                Check()
                n = n + 1
                if n % 3 == 0 then pcall(RefreshItems) end
            end)
        end
        Ask()
        C_Timer.After(1, function() if mod.Active(F) then pcall(Send, false) end end)
    end,
    OnDisable = function()
        if ticker then ticker:Cancel(); ticker = nil end
        if held then Release("switched off") end
    end,
    Page = function(ui)
        ui.Check("Wait for the party before the next step", "rxWait", "RestedXP goes to its next step only when every team member in your group on the same guide has done the step too.")
        ui.Cycle("Objective counts", { { value = "TOTAL", text = "Team total" }, { value = "LOWEST", text = "Mine + lowest" },
            { value = "EACH", text = "Mine + each" }, { value = "OFF", text = "Only mine" } }, "rxCount")
        ui.Note("Team total: 23/30 for three of you; kills (shared) show who needs the most: 5/10 (Bob). Mine + lowest: 7/10 (team 6/10). Mine + each: 7/10 (Bob 10, Cara 6).")
        -- the counts come from the Quest Tracker: say so while it's off or missing (F.Refresh)
        F.qtWarn = ui.Note("MMT's Quest Tracker is off or not installed on this character: the objective counts need it (it shares the quest logs).")
        F.qtWarn:SetTextColor(1, 0.6, 0.2)
        ui.Check("Chat line while waiting", "rxChat", "Says who you wait for when your step is done, and when everyone is.")
        ui.Cycle("Stop waiting after", { { value = 0, text = "Never" }, { value = 2, text = "2 minutes" },
            { value = 5, text = "5 minutes" }, { value = 10, text = "10 minutes" } }, "rxTimeout")
        ui.Button("Go on now", function() F.commands.go() end, "Lets the step and objectives you're waiting on go now (/mmtqol rxp go).")
    end,
    Report = function(add)
        local guide, index, stepId = Current()
        local n, h = 0, 0
        for _ in pairs(refs) do n = n + 1 end
        for _ in pairs(heldObj) do h = h + 1 end
        add(("RestedXP: wait=%s count=%s questData=%s objectives=%d (held %d) hooked=%s guide=%s step=%s (%s) held=%s behind=%s holds=%d released=%d sent=%d got=%d"):format(
            tostring(M.db.rxWait), tostring(M.db.rxCount), tostring(QuestData() ~= nil), n, h, tostring(hooked), guide and guide.key or "-", tostring(index), tostring(stepId),
            held and tostring(held.index) or "no", Names(Behind()), rxs.holds, rxs.released, rxs.sent, rxs.got))
        for key, s in pairs(others) do
            add(("  %s: %s step %s done=%s %ds ago grouped=%s"):format(key, tostring(s.guide), tostring(s.stepId),
                tostring(s.done), GetTime() - s.time, tostring(Grouped(key) ~= nil)))
        end
    end,
})

-- settings page refresh: the Quest Tracker note
function F.Refresh()
    if F.qtWarn then F.qtWarn:SetShown(M.db.rxCount ~= "OFF" and QuestData() == nil) end
end

F.commands = {
    go = function()
        local objs = PassObjectives()
        if objs > 0 then RefreshObjectives() end
        if held then Release("by hand", true)
        elseif objs == 0 then skipOnce = true; MMT.Print("RestedXP: not waiting; the next finished step goes on at once.") end
    end,
}

M:On("GROUP_ROSTER_UPDATE", function() Check(); RefreshObjectives() end)
M:Listen("QUESTS_CHANGED", function() RefreshObjectives() end)
M:On("GROUP_JOINED", function() C_Timer.After(2, Ask) end)

-- for the tests
mod.RestedXP = { HeldObjectives = function() local n = 0 for _ in pairs(heldObj) do n = n + 1 end return n end, QuestData = QuestData, TeamCounts = TeamCounts, Behind = Behind, Check = Check, AfterCompletion = AfterCompletion, others = others,
    Held = function() return held end }
