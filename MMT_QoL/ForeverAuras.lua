-- MMT Quality of life: send ForeverAuras auras to the team.
--
-- ForeverAuras (Forever's WeakAuras) has a public API for this,
-- ForeverAurasAPI (ForeverAuras/API.lua):
--   :GetAuras()            every aura by id: parent, children, icon
--   :ExportAura(id)        its import string ("!WA:2!..."), a group with everything inside it
--   :DecodeAuraString(s)   the table an import string holds (nil if it isn't one)
--   :ImportAura(s, cb)     opens ForeverAuras' own import window (the one that
--                          shows what an update changes); cb(accepted, id) once
--                          it closes. One import window at a time, not in combat.
-- Its own sharing (chat links) only works from a link in chat, one aura at a
-- time, so we send the export strings ourselves (Bulk.lua, tags QWAH / QWA /
-- QWAR). The receiver is always shown what came (a dialog unless switched off,
-- then ForeverAuras' import window for each aura, one after the other).

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local sent = 0

local function API() return rawget(_G, "ForeverAurasAPI") end
mod.AurasAPI = API

---------------------------------------------------------------------------
-- The auras here: a tree list for the send window
---------------------------------------------------------------------------
-- { { id, depth, group = true|nil, inside = auras inside it, section }, ... }:
-- groups before their children, like ForeverAuras' own list: the top level
-- split into "loaded" (ForeverAuras.IsAuraLoaded(id) ~= nil: loaded or on
-- standby; a group when any aura inside it is) and "unloaded", each sorted by
-- name. section = nil when this ForeverAuras can't tell (one plain list then).
function mod.AuraList()
    local api = API()
    if not (api and api.GetAuras) then return {} end
    local ok, auras = pcall(api.GetAuras, api)
    if not ok or type(auras) ~= "table" then return {} end
    local out = {}
    local function Count(id, seen)
        local a = auras[id]
        local n = 0
        for _, c in ipairs(a and a.children or {}) do
            if auras[c] and not seen[c] then seen[c] = true; n = n + 1 + Count(c, seen) end
        end
        return n
    end
    local function Add(id, depth, seen, section)
        local a = auras[id]
        if not a or seen[id] then return end
        seen[id] = true
        local isGroup = type(a.children) == "table"
        out[#out + 1] = { id = id, depth = depth, group = isGroup or nil, inside = isGroup and Count(id, {}) or 0, icon = a.icon, section = section }
        for _, c in ipairs(isGroup and a.children or {}) do Add(c, depth + 1, seen, section) end
    end
    local fa = rawget(_G, "ForeverAuras")
    local IsLoaded = type(fa) == "table" and type(fa.IsAuraLoaded) == "function" and fa.IsAuraLoaded
    local loaded, unloaded = {}, {}
    for id, a in pairs(auras) do
        if type(id) == "string" and (a.parent == nil or not auras[a.parent]) then
            local okL, state = true, true
            if IsLoaded then okL, state = pcall(IsLoaded, id) end
            if okL and state ~= nil then loaded[#loaded + 1] = id else unloaded[#unloaded + 1] = id end
        end
    end
    local function byName(a, b) return a:lower() < b:lower() end
    table.sort(loaded, byName)
    table.sort(unloaded, byName)
    local seen = {}
    for _, id in ipairs(loaded) do Add(id, 0, seen, IsLoaded and "loaded" or nil) end
    for _, id in ipairs(unloaded) do Add(id, 0, seen, "unloaded") end
    return out
end

-- top-level ids (everything else is inside one of them)
function mod.TopAuras()
    local t = {}
    for _, a in ipairs(mod.AuraList()) do if a.depth == 0 then t[#t + 1] = a.id end end
    return t
end

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------
local bulk

-- ids = aura ids (a group brings everything inside it), to = team key or nil (the online team)
-- -> true, text for the player | false, why not
function mod.SendAuras(ids, to)
    if not mod.Active(F) then return false, "switched off, or ForeverAuras isn't loaded." end
    local api = API()
    if not (api and api.ExportAura) then return false, "this ForeverAuras has no export API (ForeverAurasAPI)." end
    local entries = {}
    for _, id in ipairs(ids or {}) do
        local ok, s = pcall(api.ExportAura, api, id)
        if ok and type(s) == "string" and s ~= "" then entries[#entries + 1] = { name = id, str = s } end
    end
    if #entries == 0 then return false, "nothing to send (no such aura)." end
    local ok, text = bulk:Send(entries, to)
    if ok then sent = sent + #entries end
    return ok, text
end

-- a whole transfer is here: what it holds, then ask / import
local function Process(t, entries)
    local api = API()
    if not (api and api.ImportAura and api.DecodeAuraString) then return end
    local here = {}
    if api.GetAuras then
        local ok, all = pcall(api.GetAuras, api)
        if ok and type(all) == "table" then here = all end
    end
    local items, lines = {}, {}
    for _, e in ipairs(entries) do
        if e.str:match("^![FW]A:%d+!") then
            local ok, d = pcall(api.DecodeAuraString, api, e.str)
            if ok and type(d) == "table" and d.m == "d" and type(d.d) == "table" then
                local name = type(d.d.id) == "string" and d.d.id or e.name
                local kids = type(d.c) == "table" and #d.c or 0
                items[#items + 1] = { str = e.str, label = name }
                lines[#lines + 1] = name .. (kids > 0 and (" (group, " .. kids .. " inside)") or "")
                    .. (here[name] and " - you have one by this name" or "")
            end
        end
    end
    if #items == 0 then
        bulk:Reply(t, "N:not an aura")
        MMT.Print("Quality of life: what %s sent isn't a ForeverAuras aura (nothing imported).", MMT.FullDisplay(t.from))
        return
    end
    local function Go() bulk:Queue(t, items) end
    if M.db.waAsk then
        mod.Ask(t.from, F, lines, Go, function() bulk:Reply(t, "N:ignored") end)
    else
        MMT.Print("Quality of life: %d aura(s) from %s: opening ForeverAuras' import window.", #items, MMT.FullDisplay(t.from))
        Go()
    end
end

bulk = mod.Bulk({
    tag = "QWA", noun = "aura(s)", plural = "auras", where = "ForeverAuras' import window",
    fromKey = "waFrom", settings = "Quality of life > ForeverAuras",
    process = Process,
    ready = function() local api = API(); return api and api.ImportAura and mod.Active(F) or false end,
    open = function(item, done)
        local api = API()
        return api:ImportAura(item.str, function(accepted) done(accepted) end)
    end,
    busy = { ["another import is still open"] = true },
})
mod.AurasBulk = bulk

F = mod.Feature({
    key = "auras", slash = "auras", addon = "ForeverAuras", title = "ForeverAuras",
    checkText = "Send and take ForeverAuras auras",
    tip = "Send one aura, a group (with everything inside it) or all of them to a team member or the whole online team. What comes in opens in ForeverAuras' own import window (it shows what an update changes).",
    askText = function(who, n)
        return ("%s sends you %d ForeverAuras aura(s). Each opens in ForeverAuras' import window:"):format(who, n)
    end,
    askAccept = "Import",
    notes = {
        "Pick an aura, a group (everything inside it comes along) or \"All auras\", and one online team member or the whole online team, then Send.",
        "The others get a dialog (Import / Ignore), then ForeverAuras' own import window for each aura, one after the other - the same window as pasting an import string, so an aura they already have shows what changes. You hear back when they import.",
        "Auras are a few KB each; a big group or \"all\" can be 100 KB and more. The team's messages share about 800 bytes a second, so that takes a minute or two, longer to several members at once. Only members who are online get them.",
    },
    tags = bulk.tags,
    commands = { [""] = function() mod.OpenAuras() end },
    OnEnable = function()
        if mod.AurasDock then mod.AurasDock() end
        bulk:Next()
    end,
    Refresh = function() if mod.AurasDock then mod.AurasDock() end end,
    OnDisable = function()
        if mod.AurasClose then mod.AurasClose() end
    end,
    Page = function(ui)
        ui.Button("Open the send window", function() mod.OpenAuras() end,
            "Pick an aura, a group or all of them, and who gets them. Also /mmtqol auras, or the \"Send to team\" button above ForeverAuras' options.")
        ui.Check("\"Send to team\" on ForeverAuras' options", "waDock", "A button above ForeverAuras' options window opens the send window beside it.")
        ui.Check("Ask before importing", "waAsk", "A dialog lists the auras a team member sent, Import or Ignore. Off: they go straight to ForeverAuras' import window, which always asks too.")
        ui.Cycle("Who may send me auras", { { value = "TEAM", text = "Anyone in the team" }, { value = "LEADER", text = "Only the FTL leader" } }, "waFrom")
    end,
    Report = function(add)
        local st = bulk.stats
        local queued, importing = bulk:Waiting()
        add(("ForeverAuras: api=%s auras=%d sent=%d received=%d imported=%d declined=%d failed=%d incoming=%d queued=%d importing=%s from=%s"):format(
            tostring(API() ~= nil), #mod.AuraList(), sent, st.received, st.imported, st.declined, st.failed, bulk:Count(), queued,
            importing, tostring(M.db.waFrom)))
    end,
})
mod.AurasFeature = F

M:On("PLAYER_REGEN_ENABLED", function() bulk:InCombatEnded() end)
