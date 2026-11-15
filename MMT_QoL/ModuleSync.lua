-- MMT Quality of life: the settings of every module to the team in one go.
--
-- The core's Profiles > Sync to team sends the module settings only in guild mode
-- with every receiver in the guild; otherwise each module page has its own Sync
-- button, one dialog per module on every client. This sends the settings of every
-- loaded module that shares its settings (sync = true) as one transfer (Bulk.lua,
-- with progress bars), asked once on the other side, then applied like the core's
-- module sync (MMT.ImportModuleSettings: the module's syncExclude keys stay, its
-- OnProfileChanged / OnSyncReceived run). A module that isn't loaded there is kept
-- in the profile for when it is (MMT.StoreModuleSettings).
--
-- Wire: Bulk "QMS", one entry per module: <ModuleName>=<escaped MMT.Serialize(settings)>

local _, mod = ...
local MMT = MMT
local M = mod.M

local F, bulk
local sent = 0

local function Title(name)
    local m = MMT.modules and MMT.modules[name]
    return m and m.title or name
end

-- { { name, label, str } } of every loaded module that shares its settings
function mod.ModuleSyncEntries()
    local out = {}
    for _, m in ipairs(MMT.SyncableModules and MMT.SyncableModules() or {}) do
        local ok, data = pcall(m.SyncData, m)
        if ok and type(data) == "table" then
            out[#out + 1] = { name = m.name, label = m.title or m.name, str = mod.Esc(MMT.Serialize(data)) }
        end
    end
    return out
end

function mod.SendAllModules(to)
    local entries = mod.ModuleSyncEntries()
    local ok, text = bulk:Send(entries, to)
    if ok then sent = sent + 1 end
    MMT.Print("Quality of life: %s", ok and text or ("module settings not sent: " .. tostring(text)))
    return ok, text
end

local function Apply(t, entries)
    local n, bad = 0, {}
    for _, e in ipairs(entries) do
        local data = MMT.Deserialize(mod.Unesc(e.str))
        local ok = false
        if type(data) == "table" then
            if MMT.modules and MMT.modules[e.name] then
                ok = MMT.ImportModuleSettings(e.name, data, MMT.FullDisplay(t.from))
            elseif MMT.StoreModuleSettings then
                ok = MMT.StoreModuleSettings(e.name, data)
            end
        end
        if ok then n = n + 1 else bad[#bad + 1] = Title(e.name) end
    end
    bulk:Reply(t, ("D:%d:%d"):format(n, #entries))
    MMT.Print("Quality of life: settings of %d of %d modules from %s applied%s.", n, #entries, MMT.FullDisplay(t.from),
        #bad > 0 and (" (not: " .. table.concat(bad, ", ") .. ")") or "")
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

local function Process(t, entries)
    if #entries == 0 then bulk:Reply(t, "N:nothing in it") return end
    local lines = {}
    for _, e in ipairs(entries) do
        local here = MMT.modules and MMT.modules[e.name]
        lines[#lines + 1] = Title(e.name) .. (here and "" or " (not loaded here: kept for later)")
    end
    if M.db.msAsk then
        mod.Ask(t.from, F, lines, function() bulk:Reply(t, "A"); Apply(t, entries) end, function() bulk:Reply(t, "N:ignored") end)
    else
        Apply(t, entries)
    end
end

bulk = mod.Bulk({
    tag = "QMS", bars = "msBars", noun = "module settings", plural = "module settings", where = "MMT",
    fromKey = "msFrom", settings = "Quality of life > Module settings",
    process = Process,
    ready = function() return true end,
    open = function() return false, "not used" end,
})
mod.ModuleSyncBulk = bulk

F = mod.Feature({
    key = "msync", icon = "INV_Misc_EngGizmos_20", slash = "modules", title = "Module settings to the team", tabText = "All modules",
    checkText = "Send and take every module's settings",
    tip = "One button sends the settings of every MMT module (Buffs, Cooldowns, Quest Tracker, ...) to the online team in one transfer, asked once on each client. Needs this on there too.",
    askText = function(who, n)
        return ("%s sends you the settings of %d modules. They replace yours (positions kept where a module keeps them):"):format(who, n)
    end,
    askAccept = "Apply",
    notes = {
        "Profiles > Sync to team sends the module settings only when everybody is in your guild (guild channel); otherwise every module page has its own Sync button. This sends them all at once.",
        "Every loaded module that shares its settings goes along, with what it keeps per client left alone (its own exclusions). A module the other client doesn't have loaded is kept in its profile for later.",
        "Tens of KB: about a minute per member at the team's ~800 bytes a second. Only members who are online get it.",
    },
    tags = bulk.tags,
    commands = { [""] = function() return mod.SendAllModules() end },
    Page = function(ui)
        ui.Button("Send all module settings to the team", function() mod.SendAllModules() end,
            "The settings of every module (sync = true) to every online team member, in one transfer. Also /mmtqol modules.")
        ui.Check("Progress bars while sending / receiving", "msBars", "The same small window as for EllesmereUI profiles: a bar per member.")
        ui.Check("Ask before applying", "msAsk", "A dialog lists the modules a team member sent, Apply or Ignore. Off: applied right away.")
        ui.Cycle("Who may send me module settings", { { value = "TEAM", text = "Anyone in the team" }, { value = "LEADER", text = "Only the FTL leader" } }, "msFrom")
    end,
    Report = function(add)
        add(("Module settings: modules=%d sent=%d incoming=%d ask=%s from=%s"):format(#mod.ModuleSyncEntries(), sent, bulk:Count(),
            tostring(M.db.msAsk), tostring(M.db.msFrom)))
    end,
})
mod.ModuleSyncFeature = F
