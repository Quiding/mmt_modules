-- MMT Quality of life: send EllesmereUI profiles to the team.
--
-- EllesmereUI's public profile functions (EllesmereUI/EllesmereUI_Profiles.lua):
--   EllesmereUI.GetProfileList()          profileOrder, profiles
--   EllesmereUI.GetActiveProfileName()
--   EllesmereUI.ExportProfile(name)       a complete profile string ("!EUI_..."): every
--                                         module, layout, Cooldown Manager spells, overrides
--   EllesmereUI.ExportFullAccountData()   account-wide settings + the active profile
--   EllesmereUI.ImportProfileInteractive{ importString, profileName, source, callback }
--                                         opens EllesmereUI's own import page (modules, name,
--                                         UI scale); callback(accepted). Not in combat, one at a time.
--   EllesmereUI.DecodeImportStringAsync / IsFullAccountPayload / ImportFullAccountData
--                                         full account strings: that import page doesn't
--                                         take them, EllesmereUI's paste flow shows a typed
--                                         "Confirm" popup, then ImportFullAccountData (reloads).
--                                         We do the same with its own ShowConfirmPopup.
-- EllesmereUI has no player-to-player sending: the strings go through Bulk.lua
-- (tags QEUH / QEU / QEUR). Entry names: "P|<profile>" or "F|<active profile>".

local _, mod = ...
local MMT = MMT
local M = mod.M

local F
local sent = 0
mod.EUI_FULL = "\001full"

local function EUI() return rawget(_G, "EllesmereUI") end
mod.EuiAPI = EUI

-- { { name, active = true|nil }, ... } in EllesmereUI's order
function mod.EuiProfiles()
    local e = EUI()
    if not (e and e.GetProfileList) then return {} end
    local ok, order, profiles = pcall(e.GetProfileList)
    if not ok or type(order) ~= "table" then return {} end
    local active = e.GetActiveProfileName and select(2, pcall(e.GetActiveProfileName))
    local out = {}
    for _, name in ipairs(order) do
        if type(name) == "string" and (type(profiles) ~= "table" or profiles[name] ~= nil) then
            out[#out + 1] = { name = name, active = name == active or nil }
        end
    end
    return out
end

local function ActiveName()
    local e = EUI()
    local ok, name = pcall(e.GetActiveProfileName)
    return ok and type(name) == "string" and name or "Default"
end

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------
local bulk

-- choice = profile name or mod.EUI_FULL, to = team key or nil (the online team)
function mod.SendEui(choice, to)
    if not mod.Active(F) then return false, "switched off, or EllesmereUI isn't loaded." end
    local e = EUI()
    local entry
    if choice == mod.EUI_FULL then
        if not e.ExportFullAccountData then return false, "this EllesmereUI has no full account export." end
        local ok, s = pcall(e.ExportFullAccountData)
        if not ok or type(s) ~= "string" or s == "" then return false, "EllesmereUI's export failed: " .. tostring(s) end
        local active = ActiveName()
        entry = { name = "F|" .. active, str = s, label = "Full account (" .. active .. ")" }
    else
        if not e.ExportProfile then return false, "this EllesmereUI has no profile export." end
        local ok, s = pcall(e.ExportProfile, choice)
        if not ok or type(s) ~= "string" or s == "" then return false, "EllesmereUI couldn't export \"" .. tostring(choice) .. "\": " .. tostring(s) end
        entry = { name = "P|" .. choice, str = s, label = choice }
    end
    local ok, text = bulk:Send({ entry }, to)
    if ok then sent = sent + 1 end
    return ok, text
end

local FULL_TEXT = "%s sends you a FULL ACCOUNT EllesmereUI export. It replaces your account-wide EllesmereUI settings with theirs (Quality of Life, HoverCast bindings, Cooldown Manager spell setups, unlock anchors, UI scale, spec assignments) and installs their profile \"%s\" - a profile of yours with that name is replaced. Your other profiles keep their settings. The game reloads."

local function Process(t, entries)
    local e = EUI()
    if not e then return end
    local have = {}
    for _, p in ipairs(mod.EuiProfiles()) do have[p.name] = true end
    local items, lines, full = {}, {}, false
    for _, x in ipairs(entries) do
        local kind, name = x.name:match("^([PF])|(.*)$")
        if kind and x.str:sub(1, 5) == "!EUI_" then
            items[#items + 1] = { str = x.str, kind = kind, pname = name,
                label = kind == "F" and ("Full account (" .. name .. ")") or name }
            if kind == "F" then
                full = true
                lines[#lines + 1] = "FULL ACCOUNT settings + profile \"" .. name .. "\" (replaces your account-wide settings, reloads)"
            else
                lines[#lines + 1] = "profile \"" .. name .. "\"" .. (have[name] and " - you have one by this name" or "")
            end
        end
    end
    if #items == 0 then
        bulk:Reply(t, "N:not an EllesmereUI profile")
        MMT.Print("Quality of life: what %s sent isn't an EllesmereUI profile (nothing imported).", MMT.FullDisplay(t.from))
        return
    end
    local function Go() bulk:Queue(t, items) end
    -- a full account replaces everything: always asked, whatever "ask" says
    if M.db.euAsk or full then
        mod.Ask(t.from, F, lines, Go, function() bulk:Reply(t, "N:ignored") end)
    else
        MMT.Print("Quality of life: EllesmereUI profile from %s: opening EllesmereUI's import page.", MMT.FullDisplay(t.from))
        Go()
    end
end

-- a full account string: decoded, then EllesmereUI's own typed "Confirm" popup
local function OpenFull(item, done)
    local e = EUI()
    if not (e.ImportFullAccountData and e.IsFullAccountPayload and e.ShowConfirmPopup) then
        return false, "this EllesmereUI can't import a full account"
    end
    local function Show(payload, err)
        if not payload or not e.IsFullAccountPayload(payload) then
            MMT.Print("Quality of life: the full account export from %s couldn't be read: %s", MMT.FullDisplay(item.batch.from), tostring(err or "not a full account export"))
            done(false)
            return
        end
        e:ShowConfirmPopup({
            title = "Import Full Account Data",
            message = FULL_TEXT:format(MMT.FullDisplay(item.batch.from), item.pname),
            disclaimer = "This cannot be undone. Export your own profile as a backup first.",
            typeToConfirm = "Confirm",
            confirmText = "Import & Reload",
            cancelText = "Cancel",
            onConfirm = function()
                done(true)   -- the reply goes out before the reload
                e.ImportFullAccountData(payload)
            end,
            onCancel = function() done(false) end,
        })
    end
    if e.DecodeImportStringAsync then
        e.DecodeImportStringAsync(item.str, Show)
    else
        Show(e.DecodeImportString(item.str))
    end
    return true
end

bulk = mod.Bulk({
    tag = "QEU", noun = "EllesmereUI profile(s)", plural = "EllesmereUI profiles", where = "EllesmereUI's import page",
    fromKey = "euFrom", settings = "Quality of life > EllesmereUI",
    process = Process,
    ready = function() return EUI() ~= nil and mod.Active(F) end,
    open = function(item, done)
        if InCombatLockdown() then return false, "in combat" end
        if item.kind == "F" then return OpenFull(item, done) end
        local e = EUI()
        if not e.ImportProfileInteractive then return false, "this EllesmereUI has no import API" end
        return e.ImportProfileInteractive({
            importString = item.str, profileName = item.pname,
            source = "MMT (" .. MMT.FullDisplay(item.batch.from) .. ")",
            callback = function(accepted) done(accepted) end,
        })
    end,
    busy = { ["an interactive import is already pending"] = true },
})
mod.EuiBulk = bulk

F = mod.Feature({
    key = "eui", slash = "eui", addon = "EllesmereUI", title = "EllesmereUI profiles", tabText = "EllesmereUI",
    checkText = "Send and take EllesmereUI profiles",
    tip = "Send one of your EllesmereUI profiles (complete: every module, layout, Cooldown Manager spells) or your full account export to a team member or the whole online team. What comes in opens EllesmereUI's own import page.",
    askText = function(who, n)
        return ("%s sends you %d EllesmereUI export(s). Each opens in EllesmereUI:"):format(who, n)
    end,
    askAccept = "Import",
    notes = {
        "Pick a profile (or \"Full account\") and one online team member or the whole online team, then Send.",
        "A profile opens EllesmereUI's own import page on the other side: they pick the modules and the profile name there, like pasting the export string. A full account export (account-wide settings + your active profile) shows EllesmereUI's typed \"Confirm\" warning and reloads; it is always asked first.",
        "A profile is tens of KB, about a minute per member at the team's ~800 bytes a second, longer to several at once. Only members who are online get it.",
    },
    tags = bulk.tags,
    commands = { [""] = function() mod.OpenEui() end },
    OnEnable = function()
        if mod.EuiDock then mod.EuiDock() end
        bulk:Next()
    end,
    Refresh = function() if mod.EuiDock then mod.EuiDock() end end,
    OnDisable = function() if mod.EuiClose then mod.EuiClose() end end,
    Page = function(ui)
        ui.Button("Open the send window", function() mod.OpenEui() end,
            "Pick a profile or the full account, and who gets it. Also /mmtqol eui, or the \"Send to team\" button above EllesmereUI's options.")
        ui.Check("\"Send to team\" on EllesmereUI's options", "euDock", "A button above EllesmereUI's options window opens the send window beside it.")
        ui.Check("Ask before importing", "euAsk", "A dialog says what a team member sent, Import or Ignore. Off: profiles go straight to EllesmereUI's import page, which always asks too. A full account is always asked.")
        ui.Cycle("Who may send me profiles", { { value = "TEAM", text = "Anyone in the team" }, { value = "LEADER", text = "Only the FTL leader" } }, "euFrom")
    end,
    Report = function(add)
        local st = bulk.stats
        local queued, importing = bulk:Waiting()
        add(("EllesmereUI: api=%s profiles=%d sent=%d received=%d imported=%d declined=%d failed=%d incoming=%d queued=%d importing=%s from=%s"):format(
            tostring(EUI() ~= nil), #mod.EuiProfiles(), sent, st.received, st.imported, st.declined, st.failed, bulk:Count(), queued,
            importing, tostring(M.db.euFrom)))
    end,
})
mod.EuiFeature = F

M:On("PLAYER_REGEN_ENABLED", function() bulk:InCombatEnded() end)
