-- MMT Team Gear: each member's talents, for the Talents view of the gear window.
--
-- Each client reads its own talents. On WoW: Forever they are ONE trait tree
-- (C_ClassTalents / C_Traits) whose three classic trees are trait groups
-- (C_Traits.GetGroupDisplayInfoByTreeID, in orderIndex order; the node's
-- groupIDs say which one it belongs to). Without groups the three bands of node
-- columns are the trees (like Buff Timers' Specs.lua). The classic talent API
-- (GetTalentTabInfo / GetTalentInfo) is used where it has points (Forever has
-- it too, but every rank reads 0). A
-- talent's place on the grid (row, column inside its tree) comes from the node
-- positions.
--
-- Sent only when they change (respec, a point spent; never periodic):
--   TGT:<hash>#<tree name>~<tree name>~<tree name>#<talent>;<talent>;...
--   talent = <tree>.<row>.<col>.<rank>.<max>.<spellID>.<icon>[.<name>]
--   (the name only from the classic API, which has no spell ID)
-- by MMT.SendLong, plus heartbeat "tgt=<hash>"; a client whose stored hash
-- differs asks once with TGTQ (whispered, at most once a minute) and gets the
-- same TGT whispered back. Kept per character in M.store.talents[key] =
-- { hash, text, time } so offline members still show their last known talents.

local _, mod = ...
local MMT = MMT
local M = mod.M

-- classic tree names, in tree order (when the client gives none)
mod.TREE_NAMES = {
    WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}

local MAX_LINE = 20   -- rows / columns past this are a misread position

local function Store()
    M.store.talents = M.store.talents or {}
    return M.store.talents
end

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function Num(v)
    if v == nil or MMT.IsSecret(v) then return nil end
    return tonumber(v)
end

-- text that goes on the wire between our separators
local function Clean(s)
    if type(s) ~= "string" or MMT.IsSecret(s) then return "" end
    return (s:gsub("[%.;#~:|]", ""))
end

---------------------------------------------------------------------------
-- Reading this character's talents
---------------------------------------------------------------------------
-- one axis of a tree's grid: the first line and the step between lines. The
-- step is the smallest gap above a quarter of the median gap (a few nodes sit
-- slightly off their line).
local function Axis(values)
    local sorted = {}
    for i, v in ipairs(values) do sorted[i] = v end
    table.sort(sorted)
    local gaps = {}
    for i = 2, #sorted do
        local d = sorted[i] - sorted[i - 1]
        if d > 0 then gaps[#gaps + 1] = d end
    end
    if #gaps == 0 then return sorted[1] or 0, 1 end
    table.sort(gaps)
    local least = gaps[math.floor(#gaps / 2) + 1] / 4
    for _, d in ipairs(gaps) do
        if d > least then return sorted[1], d end
    end
    return sorted[1], gaps[#gaps]
end

-- a position's line (from 0); a position far past the grid with an extra zero
-- in the game's data is read at a tenth of it
local function Line(v, first, step)
    local n = math.floor((v - first) / step + 0.5)
    if n > MAX_LINE then
        local tenth = math.floor((v / 10 - first) / step + 0.5)
        if tenth >= 0 and tenth <= MAX_LINE then n = tenth end
    end
    return math.max(0, math.min(n, MAX_LINE))
end

-- nodes (GetNodeInfo tables) -> three lists by the bands of node columns
local function Bands(nodes)
    local xs, seen = {}, {}
    for _, n in ipairs(nodes) do
        if not seen[n.posX] then seen[n.posX] = true; xs[#xs + 1] = n.posX end
    end
    table.sort(xs)
    if #xs < 3 then return nil end
    local step
    for i = 2, #xs do
        local d = xs[i] - xs[i - 1]
        if not step or d < step then step = d end
    end
    local band, bandOf = 1, { [xs[1]] = 1 }
    for i = 2, #xs do
        if xs[i] - xs[i - 1] > step * 2 then band = band + 1 end
        bandOf[xs[i]] = band
    end
    if band ~= 3 then return nil end
    local trees = { {}, {}, {} }
    for _, n in ipairs(nodes) do table.insert(trees[bandOf[n.posX]], n) end
    return trees
end

local function SpellOf(config, info)
    local entryID = type(info.activeEntry) == "table" and info.activeEntry.entryID or info.entryIDs[1]
    local entry = entryID and MMT.Safe(C_Traits.GetEntryInfo, config, entryID)
    local def = type(entry) == "table" and entry.definitionID and C_Traits.GetDefinitionInfo
        and MMT.Safe(C_Traits.GetDefinitionInfo, entry.definitionID)
    if type(def) ~= "table" then return nil end
    local spell = Num(def.spellID)
    local icon = Num(def.overrideIcon)
    if (not icon or icon == 0) and spell then
        icon = C_Spell and C_Spell.GetSpellTexture and Num(MMT.Safe(C_Spell.GetSpellTexture, spell))
    end
    return spell, icon
end

local function ReadTraits()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
        and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo) then return nil end
    local config = Num(MMT.Safe(C_ClassTalents.GetActiveConfigID))
    if not config then return nil end
    local cinfo = MMT.Safe(C_Traits.GetConfigInfo, config)
    local tree = type(cinfo) == "table" and type(cinfo.treeIDs) == "table" and cinfo.treeIDs[1]
    if type(tree) ~= "number" then return nil end
    local ids = MMT.Safe(C_Traits.GetTreeNodes, tree)
    if type(ids) ~= "table" then return nil end

    local names, order = {}, {}
    local groups = C_Traits.GetGroupDisplayInfoByTreeID and MMT.Safe(C_Traits.GetGroupDisplayInfoByTreeID, tree)
    if type(groups) == "table" and #groups >= 3 then
        table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        for i = 1, 3 do
            order[groups[i].groupID] = i
            names[i] = Clean(groups[i].displayName)
        end
    end

    local nodes, byTree, grouped = {}, { {}, {}, {} }, false
    for _, id in ipairs(ids) do
        local info = MMT.Safe(C_Traits.GetNodeInfo, config, id)
        if type(info) == "table" and info.isVisible ~= false and type(info.entryIDs) == "table" and info.entryIDs[1]
            and Num(info.posX) and Num(info.posY) then
            nodes[#nodes + 1] = info
            for _, g in ipairs(type(info.groupIDs) == "table" and info.groupIDs or {}) do
                if order[g] then table.insert(byTree[order[g]], info); grouped = true break end
            end
        end
    end
    if not grouped then
        byTree = Bands(nodes)
        if not byTree then return nil end
        names = {}
    end

    local talents = {}
    for t = 1, 3 do
        local xs, ys = {}, {}
        for i, n in ipairs(byTree[t]) do xs[i], ys[i] = n.posX, n.posY end
        local x0, dx = Axis(xs)
        local y0, dy = Axis(ys)
        for _, n in ipairs(byTree[t]) do
            local spell, icon = SpellOf(config, n)
            talents[#talents + 1] = {
                tree = t, row = Line(n.posY, y0, dy), col = Line(n.posX, x0, dx),
                rank = Num(n.activeRank) or Num(n.ranksPurchased) or 0, max = Num(n.maxRanks) or 1,
                spell = spell or 0, icon = icon or 0,
            }
        end
    end
    if #talents == 0 then return nil end
    return { names = names, talents = talents, source = "traits" }
end

local function ReadClassic()
    local tabs = GetNumTalentTabs and Num(MMT.Safe(GetNumTalentTabs))
    if not tabs or tabs < 3 or not (GetTalentTabInfo and GetNumTalents and GetTalentInfo) then return nil end
    local names, talents = {}, {}
    for t = 1, 3 do
        local a, b = MMT.Safe(GetTalentTabInfo, t)
        names[t] = Clean(type(a) == "string" and a or b)   -- classic: name first; later clients: id, name
        for i = 1, Num(MMT.Safe(GetNumTalents, t)) or 0 do
            local name, icon, tier, column, rank, max = MMT.Safe(GetTalentInfo, t, i)
            if type(name) == "string" and Num(tier) and Num(column) then
                talents[#talents + 1] = {
                    tree = t, row = Num(tier) - 1, col = Num(column) - 1, rank = Num(rank) or 0, max = Num(max) or 1,
                    spell = 0, icon = Num(icon) or 0, name = Clean(name),
                }
            end
        end
    end
    if #talents == 0 then return nil end
    return { names = names, talents = talents, source = "classic" }
end

local function Sorted(data)
    table.sort(data.talents, function(a, b)
        if a.tree ~= b.tree then return a.tree < b.tree end
        if a.row ~= b.row then return a.row < b.row end
        return a.col < b.col
    end)
    return data
end

local function Spent(data)
    local n = 0
    for _, t in ipairs(data and data.talents or {}) do n = n + t.rank end
    return n
end

-- this character's talents { names, talents, source }, or nil. The classic
-- API only when it has points: Forever has it too, but every rank reads 0.
function mod.ReadOwnTalents()
    local ok, classic = pcall(ReadClassic)
    if not ok then mod.talentError, classic = classic, nil end
    if Spent(classic) > 0 then return Sorted(classic) end
    local ok2, traits = pcall(ReadTraits)
    if not ok2 then mod.talentError, traits = traits, nil end
    local data = traits or classic
    return data and Sorted(data) or nil
end

---------------------------------------------------------------------------
-- Text on the wire
---------------------------------------------------------------------------
function mod.TalentText(data)
    local parts = {}
    for i, t in ipairs(data.talents) do
        local s = ("%d.%d.%d.%d.%d.%d.%d"):format(t.tree, t.row, t.col, t.rank, t.max, t.spell, t.icon)
        if t.name and t.name ~= "" then s = s .. "." .. t.name end
        parts[i] = s
    end
    local n = data.names or {}
    return ("%s~%s~%s#%s"):format(n[1] or "", n[2] or "", n[3] or "", table.concat(parts, ";"))
end

function mod.ParseTalents(text)
    local names, list = text:match("^([^#]*)#(.*)$")
    if not names then return nil end
    local data = { names = {}, talents = {} }
    local i = 0
    for name in (names .. "~"):gmatch("([^~]*)~") do
        i = i + 1
        if i <= 3 and name ~= "" then data.names[i] = name end
    end
    for part in list:gmatch("[^;]+") do
        local t, r, c, rank, max, spell, icon, name = part:match("^(%d)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.?(.*)$")
        if t and tonumber(t) >= 1 and tonumber(t) <= 3 then
            data.talents[#data.talents + 1] = {
                tree = tonumber(t), row = math.min(tonumber(r), MAX_LINE), col = math.min(tonumber(c), MAX_LINE),
                rank = tonumber(rank), max = tonumber(max), spell = tonumber(spell), icon = tonumber(icon),
                name = name ~= "" and name or nil,
            }
        end
    end
    return data
end

---------------------------------------------------------------------------
-- Telling the team
---------------------------------------------------------------------------
local own, ownText       -- read this session (nil = read again)
local sentText           -- what the team has from us (heartbeat hash)

local function OwnText()
    if not ownText then
        own = mod.ReadOwnTalents()
        ownText = own and mod.TalentText(own) or false
    end
    return ownText or nil
end

local function Send(target)
    local text = OwnText()
    if not text then return end
    sentText = text
    MMT.SendLong(("TGT:%d#%s"):format(Hash(text), text), target, "BULK")
end

M:Heartbeat("tgt", function()
    local text = sentText or OwnText()
    return text and tostring(Hash(text)) or nil
end)

-- talents read again; the team gets them when they changed since the first read
-- (that one only goes on the heartbeat: whoever lacks it asks)
local pending = false
function mod.TalentsChanged()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        ownText = nil
        if not M.enabled then return end
        local text = OwnText()
        if text and sentText and text ~= sentText then Send()
        elseif text then sentText = text end
        if mod.window and mod.window:IsShown() and MMT.IsSelf(mod.window.key or "") then mod.Refresh() end
    end)
end

local events = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
    "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function() mod.TalentsChanged() end)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local asked = {}

M:Listen("XP_RECEIVED", function(key, sender, status)
    if MMT.IsSelf(key) then return end
    local hash = tonumber(status and status.ext and status.ext.tgt)
    if not hash then return end
    local rec = Store()[key]
    if rec and rec.hash == hash then return end
    if asked[key] and GetTime() - asked[key] < 60 then return end
    asked[key] = GetTime()
    MMT.SendAddon("TGTQ", "WHISPER", sender)
end)

local parsed = setmetatable({}, { __mode = "k" })   -- [stored record] = parsed talents

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "TGTQ" then Send(sender) return end
    local hash, body = text:match("^TGT:(%d+)#(.*)$")
    if not hash or not mod.ParseTalents(body) then return end
    Store()[key] = { hash = tonumber(hash), text = body, time = time() }
    if mod.window and mod.window:IsShown() and mod.window.key == key then mod.Refresh() end
end)

---------------------------------------------------------------------------
-- Any member's talents
---------------------------------------------------------------------------
-- { names = { tree names }, talents = { {tree, row, col, rank, max, spell, icon, name} }, time } or nil
function mod.TalentsOf(key)
    if MMT.IsSelf(key) then
        OwnText()
        return own
    end
    local rec = Store()[key]
    if type(rec) ~= "table" or type(rec.text) ~= "string" then return nil end
    local data = parsed[rec]
    if not data then
        data = mod.ParseTalents(rec.text)
        if not data then return nil end
        data.time = rec.time
        parsed[rec] = data
    end
    return data
end

-- points per tree { a, b, c }
function mod.TreePoints(data)
    local p = { 0, 0, 0 }
    for _, t in ipairs(data and data.talents or {}) do p[t.tree] = p[t.tree] + t.rank end
    return p
end

-- the name of tree i for a member (the one they sent, else the classic one)
function mod.TreeName(data, class, i)
    local n = data and data.names and data.names[i]
    if n and n ~= "" then return n end
    local t = class and mod.TREE_NAMES[class]
    return t and t[i] or ("Tree " .. i)
end

-- "Retribution 5 / 11 / 35" (named after the tree with the most points), or nil
function mod.TalentSummary(key)
    local data = mod.TalentsOf(key)
    if not data then return nil end
    local p = mod.TreePoints(data)
    local best, most = nil, 0
    for i = 1, 3 do if p[i] > most then best, most = i, p[i] end end
    if not best then return "no talent points spent" end
    return ("%s %d / %d / %d"):format(mod.TreeName(data, mod.ClassOf(key), best), p[1], p[2], p[3])
end

function mod.TalentReport(add)
    local data = mod.TalentsOf(MMT.PlayerFull())
    add(("talents: own=%s source=%s talents=%d sent=%s stored=%d"):format(tostring(mod.TalentSummary(MMT.PlayerFull())),
        tostring(data and data.source), data and #data.talents or 0, tostring(sentText and Hash(sentText)),
        (function() local n = 0 for _ in pairs(Store()) do n = n + 1 end return n end)()))
end
