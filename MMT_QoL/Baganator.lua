-- MMT Quality of life: Baganator's category items, the same on the whole team.
--
-- Items put into a category by hand live in Baganator's profile:
-- BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE].category_modifications
-- [category].addedItems["i:<itemID>" | "p:<petID>"] = true. Baganator has no
-- API to add items to a category, but it reads that table on every redraw and
-- its public Baganator.API.RequestItemButtonsRefresh / RequestLayoutUpdate
-- redraw the bags. So:
--   * changes here: Baganator replaces the table on every change (Config.Set
--     with a copy); a 1 s check of the table (and a full compare every 5 s)
--     sends the difference: QBG:+i:2589=default_junk;-i:2589=default_other
--   * changes from the team: written into that table, then the refresh.
-- Categories go by key for Baganator's own ("default_junk") and by name for
-- custom ones ("c:<name>", %XX escaped): their keys differ per character.
-- Whole setup: Baganator's own import (Baganator.API.ImportString) with an
-- export built like its "Export categories" (QBGF).

local _, mod = ...
local MMT = MMT
local M = mod.M

local JUNK = "default_junk"
local BULK = 10
local MSG_MAX = 240

local F
local snap, snapMods, snapProfile   -- snap["<item>\t<category key>"] = true
local ticker, ticks = nil, 0
local bg = { sent = 0, taken = 0, missing = {} }
mod.bg = bg

local function Profile()
    local cfg = rawget(_G, "BAGANATOR_CONFIG")
    local name = rawget(_G, "BAGANATOR_CURRENT_PROFILE")
    local p = type(cfg) == "table" and type(cfg.Profiles) == "table" and cfg.Profiles[name]
    if type(p) ~= "table" then return nil end
    return p, name
end
mod.BaganatorProfile = Profile

local function Esc(s) return (s:gsub("[%%;=,:]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- category key here -> the name the team knows it by
local function CatId(p, src)
    if type(src) ~= "string" then return nil end
    if src:match("^default_") then return src end
    local c = type(p.custom_categories) == "table" and p.custom_categories[src]
    if type(c) == "table" and type(c.name) == "string" then return "c:" .. Esc(c.name) end
end

-- and back (a custom one shown in the bags wins over a stale copy)
local function FindSrc(p, id)
    if id:match("^default_") then return id end
    local name = id:match("^c:(.*)$")
    if not name then return nil end
    name = Unesc(name)
    local order, found = {}, nil
    for _, s in ipairs(type(p.category_display_order) == "table" and p.category_display_order or {}) do order[s] = true end
    for src, c in pairs(type(p.custom_categories) == "table" and p.custom_categories or {}) do
        if type(c) == "table" and c.name == name then
            if order[src] then return src end
            found = found or src
        end
    end
    return found
end

local function CatName(id)
    if id == JUNK then return "Junk" end
    local d = id:match("^default_(.*)$")
    if d then return (d:gsub("_", " "):gsub("^%l", string.upper)) end
    return Unesc(id:sub(3))
end

local function Snapshot(p)
    local set = {}
    for src, m in pairs(type(p.category_modifications) == "table" and p.category_modifications or {}) do
        if type(m) == "table" and type(m.addedItems) == "table" then
            for item in pairs(m.addedItems) do set[item .. "\t" .. src] = true end
        end
    end
    return set
end

local function InScope(id) return M.db.bgScope ~= "JUNK" or id == JUNK end

local function Wanted(sign, id)
    if sign == "+" and not M.db.bgAdd then return false end
    if sign == "-" and not M.db.bgRemove then return false end
    return InScope(id)
end

local function Refresh()
    local api = Baganator and Baganator.API
    if not api then return end
    if api.RequestItemButtonsRefresh then pcall(api.RequestItemButtonsRefresh) end
    if api.RequestLayoutUpdate then pcall(api.RequestLayoutUpdate) end
end

local function SendOps(tag, ops)
    local msg = ""
    for _, op in ipairs(ops) do
        if #msg + #op + 1 > MSG_MAX - #tag - 1 then
            MMT.SendToTeam(tag .. ":" .. msg, true)
            msg = ""
        end
        msg = msg == "" and op or (msg .. ";" .. op)
    end
    if msg ~= "" then MMT.SendToTeam(tag .. ":" .. msg, true) end
end

local function Resnap()
    local p, name = Profile()
    if p then snap, snapMods, snapProfile = Snapshot(p), p.category_modifications, name
    else snap = nil end
end

local function Tick()
    if not mod.Active(F) then snap = nil return end
    local p, name = Profile()
    if not p then snap = nil return end
    ticks = ticks + 1
    local mods = p.category_modifications
    if snap and name == snapProfile and rawequal(mods, snapMods) and ticks % 5 ~= 0 then return end
    if not snap or name ~= snapProfile then Resnap() return end   -- first look / another Baganator profile

    local now = Snapshot(p)
    local ops = {}
    for k in pairs(now) do
        if not snap[k] then
            local item, src = k:match("^(.-)\t(.*)$")
            local id = CatId(p, src)
            if id and Wanted("+", id) then ops[#ops + 1] = "+" .. item .. "=" .. id end
        end
    end
    for k in pairs(snap) do
        if not now[k] then
            local item, src = k:match("^(.-)\t(.*)$")
            local id = CatId(p, src)   -- nil: the category was deleted, nothing to send
            if id and Wanted("-", id) then table.insert(ops, 1, "-" .. item .. "=" .. id) end
        end
    end
    snap, snapMods = now, mods
    if #ops == 0 then return end
    if #ops > BULK then
        MMT.Print("Quality of life: %d Baganator category changes at once (an import or a reset) were not sent to the team. /mmtqol baganator send sends all your category items.", #ops)
        return
    end
    SendOps("QBG", ops)
    bg.sent = bg.sent + #ops
    M:Debug("Baganator sent %s", table.concat(ops, ";"))
end
mod.BaganatorTick = Tick

-- ops = { {sign, item, id} }: "-" before "+" (a move is "-" from the old one, "+" to the new one)
local function Apply(from, ops)
    local p = Profile()
    if not p then return 0 end
    if type(p.category_modifications) ~= "table" then p.category_modifications = {} end
    local mods = p.category_modifications
    local n = 0
    local function take(src, item)
        local m = mods[src]
        if type(m) ~= "table" or type(m.addedItems) ~= "table" or not m.addedItems[item] then return false end
        m.addedItems[item] = nil
        if next(m.addedItems) == nil then m.addedItems = nil end
        if snap then snap[item .. "\t" .. src] = nil end
        return true
    end
    for _, op in ipairs(ops) do
        local sign, item, id = op[1], op[2], op[3]
        local src = FindSrc(p, id)
        if not src then
            if not bg.missing[id] then
                bg.missing[id] = true
                MMT.Print("Quality of life: %s puts items into the Baganator category \"%s\", which this character doesn't have.", MMT.FullDisplay(from), CatName(id))
            end
        elseif sign == "-" then
            if take(src, item) then n = n + 1 end
        else
            -- like Baganator: an item is in one category only
            for s in pairs(mods) do if s ~= src then take(s, item) end end
            if type(mods[src]) ~= "table" then mods[src] = {} end
            mods[src].addedItems = mods[src].addedItems or {}
            if not mods[src].addedItems[item] then
                mods[src].addedItems[item] = true
                n = n + 1
            end
            if snap then snap[item .. "\t" .. src] = true end
        end
    end
    if n > 0 then Refresh() end
    bg.taken = bg.taken + n
    return n
end

local function ItemOf(item)
    local id = item:match("^i:(%d+)$")
    if id then return mod.ItemText(id) end
    return "pet " .. (item:match("^p:(%d+)$") or item)
end

local function Take(from, ops, lines)
    if #ops == 0 then return end
    if not lines then
        lines = {}
        for _, op in ipairs(ops) do
            lines[#lines + 1] = ("%s %s %s %s"):format(op[1], ItemOf(op[2]), op[1] == "+" and "to" or "from", CatName(op[3]))
        end
    end
    local function apply()
        local n = Apply(from, ops)
        if n > 0 and M.db.bgChat then
            if #lines == 1 then MMT.Print("Baganator from %s: %s", MMT.FullDisplay(from), lines[1])
            else MMT.Print("Baganator from %s: %d category changes.", MMT.FullDisplay(from), n) end
        end
    end
    if M.db.bgAsk then mod.Ask(from, F, lines, apply) else apply() end
end

local function Parse(body, all)
    local ops = {}
    for op in body:gmatch("[^;]+") do
        local sign, item, id = op:match("^([%+%-])([ip]:%d+)=(.+)$")
        if sign and (all or Wanted(sign, id)) and InScope(id) then ops[#ops + 1] = { sign, item, id } end
    end
    table.sort(ops, function(a, b) return a[1] == "-" and b[1] == "+" end)
    return ops
end

local function OnChange(from, _, body) Take(from, Parse(body)) end

-- all category items of the sender: added here when not already in that category
local function OnAll(from, _, body)
    local p = Profile()
    if not p then return end
    local have = Snapshot(p)
    local ops, missing = {}, 0
    for _, op in ipairs(Parse(body, true)) do
        local src = op[1] == "+" and FindSrc(p, op[3])
        if not src then missing = missing + 1
        elseif not have[op[2] .. "\t" .. src] then ops[#ops + 1] = op end
    end
    if #ops == 0 then
        if M.db.bgChat then MMT.Print("Baganator items from %s: nothing new.", MMT.FullDisplay(from)) end
        return
    end
    Take(from, ops, { ("+ %d item(s) into categories%s"):format(#ops, missing > 0 and (" (%d in categories you don't have)"):format(missing) or "") })
end

local function SendAll()
    if not mod.Active(F) then return false, "switched off, or Baganator isn't loaded." end
    local p = Profile()
    if not p then return false, "Baganator isn't ready yet." end
    local ops = {}
    for k in pairs(Snapshot(p)) do
        local item, src = k:match("^(.-)\t(.*)$")
        local id = CatId(p, src)
        if id and InScope(id) then ops[#ops + 1] = "+" .. item .. "=" .. id end
    end
    if #ops == 0 then return false, "you have no items put into categories" .. (M.db.bgScope == "JUNK" and " (Junk only)." or ".") end
    table.sort(ops)
    MMT.SendLong("QBGL:" .. table.concat(ops, ";"))
    return true, #ops
end

-- the whole category setup, built like Baganator's "Export categories"
local function ExportTable(p)
    local function copy(t)
        if type(t) ~= "table" then return t end
        local r = {}
        for k, v in pairs(t) do r[k] = copy(v) end
        return r
    end
    local e = { version = 3, addon = "Baganator", kind = "categories", categories = {}, modifications = {}, hidden = {},
                sections = copy(p.category_sections or {}), order = copy(p.category_display_order or {}) }
    for src, c in pairs(p.custom_categories or {}) do
        if type(c) == "table" then e.categories[#e.categories + 1] = { name = c.name, search = c.search, source = src } end
    end
    for src, m in pairs(p.category_modifications or {}) do
        if type(m) == "table" then
            local items, pets, hideIn = {}, {}, {}
            for item in pairs(m.addedItems or {}) do
                local t, id = item:match("^(.):(%d+)$")
                if t == "i" then items[#items + 1] = tonumber(id) elseif t == "p" then pets[#pets + 1] = tonumber(id) end
            end
            for where, on in pairs(type(m.hideIn) == "table" and m.hideIn or {}) do if on then hideIn[#hideIn + 1] = where end end
            e.modifications[#e.modifications + 1] = { source = src, items = #items > 0 and items or nil, pets = #pets > 0 and pets or nil,
                group = m.group, color = m.color, showGroupPrefix = m.showGroupPrefix, priority = m.priority, hideIn = hideIn }
        end
    end
    for src, hidden in pairs(p.category_hidden or {}) do if hidden then e.hidden[#e.hidden + 1] = src end end
    return e
end
mod.BaganatorExport = ExportTable

local function SendSetup()
    if not mod.Active(F) then return false, "switched off, or Baganator isn't loaded." end
    local p = Profile()
    if not p then return false, "Baganator isn't ready yet." end
    local E = C_EncodingUtil
    if not (E and E.SerializeCBOR and E.CompressString and E.EncodeBase64) then return false, "this client can't pack it (no C_EncodingUtil)." end
    local ok, s = pcall(function() return "BGR!1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(ExportTable(p)))) end)
    if not ok or type(s) ~= "string" then return false, "packing failed: " .. tostring(s) end
    MMT.SendLong("QBGF:" .. s)
    return true, #s
end
mod.BaganatorSendSetup = SendSetup

local function OnSetup(from, _, text)
    if not text:match("^BGR!1!") then return end
    local api = Baganator and Baganator.API
    if not (api and api.ImportString) then return end
    -- replaces the whole category layout: always asked, whatever "ask" says
    mod.Ask(from, F, { "their whole Baganator category setup (categories, order, sections, items): replaces yours" }, function()
        local ok, err = pcall(api.ImportString, text, "MMT")
        if not ok then MMT.Print("Quality of life: Baganator didn't take the setup from %s: %s", MMT.FullDisplay(from), tostring(err)) return end
        -- the import adds the custom categories again under new keys: drop the old, now unused ones
        if SlashCmdList and SlashCmdList.Baganator then pcall(SlashCmdList.Baganator, "removeunusedcategories") end
        Resnap()   -- not a change to send on
        Refresh()
        MMT.Print("Quality of life: Baganator category setup from %s applied.", MMT.FullDisplay(from))
    end)
end

F = mod.Feature({
    key = "baganator", slash = "baganator", addon = "Baganator", title = "Baganator categories",
    checkText = "Sync Baganator's categories",
    tip = "Items you put into a Baganator category by hand (or take out of it) go into the same category on the team's characters, right away. Custom categories are matched by name.",
    tags = { QBG = OnChange, QBGL = OnAll, QBGF = OnSetup },
    SendAll = SendAll,
    OnEnable = function()
        snap = nil
        if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, Tick) end
        Tick()
    end,
    OnDisable = function()
        if ticker then ticker:Cancel(); ticker = nil end
        snap = nil
    end,
    Page = function(ui)
        ui.Check("Send and take additions", "bgAdd", "Items put into a category.")
        ui.Check("Send and take removals", "bgRemove", "Items taken out of a category (back to where Baganator sorts them).")
        ui.Cycle("Categories", { { value = "ALL", text = "Every category" }, { value = "JUNK", text = "Junk only" } }, "bgScope")
        ui.Check("Ask before taking changes", "bgAsk", "A dialog shows what a team member changed, Apply or Ignore. Off: taken right away.")
        ui.Check("Chat line for each change taken", "bgChat")
        ui.Button("Send my category items", function()
            local ok, res = SendAll()
            ui.status.Show_(ok and ("%d category item(s) sent; the team adds what it doesn't have."):format(res) or ("Not sent: " .. tostring(res)), not ok)
        end, "Sends every item you put into a category once (Junk only when that's chosen). The others add them; nothing is removed.")
        ui.Confirm("Send my whole category setup", function()
            local ok, res = SendSetup()
            ui.status.Show_(ok and "Your Baganator category setup was sent; each character is asked before it replaces theirs." or ("Not sent: " .. tostring(res)), not ok)
        end, "Categories, their order, sections, hidden ones and items, through Baganator's own import. Replaces the setup of the others (each is asked first). Click twice.")
    end,
    Report = function(add)
        local p, name = Profile()
        local n = 0
        for _ in pairs(p and Snapshot(p) or {}) do n = n + 1 end
        local missing = {}
        for id in pairs(bg.missing) do missing[#missing + 1] = CatName(id) end
        add(("Baganator: profile=%s items in categories=%d watching=%s scope=%s sent=%d taken=%d missing=%s"):format(
            tostring(name), n, tostring(snap ~= nil), tostring(M.db.bgScope), bg.sent, bg.taken,
            #missing > 0 and table.concat(missing, ", ") or "-"))
    end,
})
