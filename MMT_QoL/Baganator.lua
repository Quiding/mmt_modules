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
-- Layout (bgLayout): the order of the categories and the sections they sit in
-- (category_display_order + category_sections), 3 s after the last change:
--   QBGO:<entry>;...   entry = default_x | c:<name> | s:<section name>[,<colour>] | __end | ----
-- Taken: custom categories and sections matched by name (sections made when missing),
-- ours the sender doesn't show kept at the end; then Baganator is told the way its
-- own settings page does (its CallbackRegistry: SettingChanged + RefreshStateChange).

local _, mod = ...
local MMT = MMT
local M = mod.M

local JUNK = "default_junk"
local BULK = 10
local MSG_MAX = 240

local F
local snap, snapMods, snapProfile   -- snap["<item>\t<category key>"] = true
local ticker, ticks = nil, 0
local changedHere          -- we changed the table in place (junk link): compare it on the next tick
local catchUp = true       -- junk link: Junk items not on Dejunk's junk list yet, put on (after login, after the team's)
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
    if mod.BaganatorLayoutTick then pcall(mod.BaganatorLayoutTick, p, name) end
    ticks = ticks + 1
    local mods = p.category_modifications
    if snap and name == snapProfile and rawequal(mods, snapMods) and ticks % 5 ~= 0 and not changedHere then return end
    changedHere = false
    if not snap or name ~= snapProfile then Resnap(); catchUp = true return end   -- first look / another Baganator profile
    -- junk link: what's in Junk (also from the team, or from before the link) on Dejunk's junk list
    if catchUp and M.db.junkLink and mod.DejunkCatchUp then
        local m = type(mods) == "table" and mods[JUNK]
        local items = {}
        for item in pairs(type(m) == "table" and type(m.addedItems) == "table" and m.addedItems or {}) do
            -- (one put in just now, not in snap yet, goes through the link below: that one is sent)
            local id = tostring(item):match("^i:(%d+)$")
            if id and snap[item .. "	" .. JUNK] then items[#items + 1] = id end
        end
        if mod.DejunkCatchUp(items) ~= nil then catchUp = false end
    end

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
    -- junk link: into / out of Junk here = on / off Dejunk's global junk list
    if M.db.junkLink and mod.DejunkFromHere then
        local link = {}
        for k in pairs(now) do
            local item, src = k:match("^i:(%d+)\t(.*)$")
            if item and src == JUNK and not snap[k] then link[#link + 1] = { "+", item } end
        end
        for k in pairs(snap) do
            local item, src = k:match("^i:(%d+)\t(.*)$")
            if item and src == JUNK and not now[k] then link[#link + 1] = { "-", item } end
        end
        if #link <= BULK then
            for _, l in ipairs(link) do mod.DejunkFromHere(l[1], l[2]) end
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
                if src == JUNK then catchUp = true end
            end
            if snap then snap[item .. "\t" .. src] = true end
        end
    end
    if n > 0 then Refresh() end
    bg.taken = bg.taken + n
    return n
end

-- junk link: off Dejunk's junk list here = out of Baganator's Junk. Left out of
-- snap, so the next tick sends it to the team like a change made in Baganator.
function mod.BaganatorUnjunk(id)
    if not mod.Active(F) then return false end
    local p = Profile()
    local m = p and type(p.category_modifications) == "table" and p.category_modifications[JUNK]
    local item = "i:" .. tostring(id)
    if type(m) ~= "table" or type(m.addedItems) ~= "table" or not m.addedItems[item] then return false end
    m.addedItems[item] = nil
    if next(m.addedItems) == nil then m.addedItems = nil end
    changedHere = true
    Refresh()
    return true
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

---------------------------------------------------------------------------
-- The layout: order and sections
---------------------------------------------------------------------------
local SECTION_END, DIVIDER = "__end", "----"
local layout = { sent = nil, profile = nil, pending = nil, pendingAt = 0 }
local LAYOUT_QUIET = 3

local function LayoutText(p)
    local parts = {}
    local secs = type(p.category_sections) == "table" and p.category_sections or {}
    for _, src in ipairs(type(p.category_display_order) == "table" and p.category_display_order or {}) do
        if type(src) ~= "string" then
            -- nothing
        elseif src == SECTION_END or src == DIVIDER or src:match("^default_") then
            parts[#parts + 1] = src
        elseif src:match("^_") then
            local s = secs[src:sub(2)]
            local name = type(s) == "table" and type(s.name) == "string" and s.name or src:sub(2)
            local colour = type(s) == "table" and type(s.color) == "string" and s.color or nil
            parts[#parts + 1] = "s:" .. Esc(name) .. (colour and ("," .. colour) or "")
        else
            local id = CatId(p, src)
            if id then parts[#parts + 1] = id end
        end
    end
    return table.concat(parts, ";")
end
mod.BaganatorLayoutText = LayoutText

-- tell Baganator the way its own settings page does
local function LayoutChanged()
    local reg = Baganator and Baganator.CallbackRegistry
    if reg and reg.TriggerEvent then
        pcall(reg.TriggerEvent, reg, "SettingChanged", "category_sections")
        pcall(reg.TriggerEvent, reg, "SettingChanged", "category_display_order")
        local R = Baganator.Constants and Baganator.Constants.RefreshReason or {}
        pcall(reg.TriggerEvent, reg, "RefreshStateChange", { [R.Searches or 16] = true, [R.Layout or 32] = true })
    end
    Refresh()
end

-- every tick: our layout changed? sent once it has been still for a few seconds
local function LayoutTick(p, name)
    if not M.db.bgLayout then layout.sent = nil return end
    local text = LayoutText(p)
    if layout.sent == nil or layout.profile ~= name then
        layout.sent, layout.profile, layout.pending = text, name, nil
        return
    end
    if text == layout.sent then layout.pending = nil return end
    local now = GetTime()
    if layout.pending ~= text then layout.pending, layout.pendingAt = text, now return end
    if now - layout.pendingAt < LAYOUT_QUIET then return end
    layout.sent, layout.pending = text, nil
    MMT.SendLong("QBGO:" .. text)
    bg.layoutSent = (bg.layoutSent or 0) + 1
end
mod.BaganatorLayoutTick = LayoutTick

local function ApplyLayout(from, body)
    local p, name = Profile()
    if not p then return false end
    if body == LayoutText(p) then return false end
    local secs = type(p.category_sections) == "table" and p.category_sections or {}
    local byName, top = {}, 0
    for k, s in pairs(secs) do
        if type(s) == "table" and s.name then byName[s.name] = k end
        top = math.max(top, tonumber(k) or 0)
    end
    local order, seen, newSecs, missing = {}, {}, {}, {}
    for e in body:gmatch("[^;]+") do
        if e == SECTION_END or e == DIVIDER then
            order[#order + 1] = e
        elseif e:match("^default_") then
            if not seen[e] then order[#order + 1] = e; seen[e] = true end
        elseif e:match("^s:") then
            local sname, colour = e:sub(3):match("^([^,]*),?(.*)$")
            sname = Unesc(sname)
            local key = byName[sname]
            if not key then top = top + 1; key = tostring(top); byName[sname] = key end
            newSecs[key] = { name = sname, color = colour ~= "" and colour or (type(secs[key]) == "table" and secs[key].color or nil) }
            order[#order + 1] = "_" .. key
        elseif e:match("^c:") then
            local src = FindSrc(p, e)
            if src and not seen[src] then order[#order + 1] = src; seen[src] = true
            elseif not src then missing[#missing + 1] = CatName(e) end
        end
    end
    -- ours the sender doesn't show: kept, at the end
    for _, src in ipairs(type(p.category_display_order) == "table" and p.category_display_order or {}) do
        if type(src) == "string" and not seen[src] and src ~= SECTION_END and src ~= DIVIDER and not src:match("^_") then
            order[#order + 1] = src; seen[src] = true
        end
    end
    p.category_display_order = order
    p.category_sections = newSecs
    layout.sent, layout.profile, layout.pending = LayoutText(p), name, nil   -- not sent back
    LayoutChanged()
    bg.layoutTaken = (bg.layoutTaken or 0) + 1
    if M.db.bgChat then
        MMT.Print("Baganator from %s: category order and sections taken%s.", MMT.FullDisplay(from),
            #missing > 0 and (" (not here: " .. table.concat(missing, ", ") .. ")") or "")
    end
    return true
end
mod.BaganatorApplyLayout = ApplyLayout

local function OnLayout(from, _, body)
    if not (mod.Active(F) and M.db.bgLayout) then return end
    if M.db.bgAsk then
        mod.Ask(from, F, { "their category order and sections" }, function() ApplyLayout(from, body) end)
    else
        ApplyLayout(from, body)
    end
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
    key = "baganator", icon = "INV_Misc_Bag_08", slash = "baganator", addon = "Baganator", title = "Baganator categories", tabText = "Baganator",
    checkText = "Sync Baganator's categories",
    tip = "Items you put into a Baganator category by hand (or take out of it) go into the same category on the team's characters, right away. Custom categories are matched by name.",
    tags = { QBG = OnChange, QBGL = OnAll, QBGF = OnSetup, QBGO = OnLayout },
    commands = { send = SendAll },
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
        ui.Check("Send and take the layout", "bgLayout", "The order of the categories and the sections they sit in (Baganator > Categories, dragging them around): sent 3 seconds after your last change, and taken from the team. Custom categories and sections go by name; a category the other side doesn't have stays, at the end.")
        ui.Check("Link Junk with Dejunk's junk list", "junkLink", "Items you put into Baganator's Junk go on Dejunk's global junk list (so Dejunk sells them), and items you take off Dejunk's junk list (or out of Junk) leave both. Both syncs then send it to the team. Needs Dejunk; the Dejunk sync on to reach the team's Dejunk.")
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
        add(("Baganator: profile=%s items in categories=%d watching=%s scope=%s sent=%d taken=%d layout=%s sent/taken %d/%d missing=%s"):format(
            tostring(name), n, tostring(snap ~= nil), tostring(M.db.bgScope), bg.sent, bg.taken,
            tostring(M.db.bgLayout), bg.layoutSent or 0, bg.layoutTaken or 0, #missing > 0 and table.concat(missing, ", ") or "-"))
    end,
})
