-- MMT Styles: what gets the style, window by window ("Windows" list on the page).
--
-- Every texture / font string Skin.lua records belongs to a window: the frame
-- right below UIParent it sits in. Its global name says which entry of
-- mod.TARGETS it is (else "other"). A switched-off entry is painted as if the
-- style were None (mod.Gate), so it keeps MMT's own look while the rest is
-- styled. Per entry (M.store.targets[id], account-wide like the rest of the look):
--   on    = false: not styled
--   font  = "INHERIT" (the Fonts & Colour setting) | "ON" | "OFF"
--   play windows (Hud.lua): bg / edges / accent = false switch that part off
-- Default: everything on, as before. module = the MMT module the window belongs to
-- (the list hides it while that module is missing or switched off).

local _, mod = ...

mod.TARGETS = {
    { id = "settings", title = "Settings window", tip = "MMT's settings window, its drop-down lists and colour picker, and the small windows beside it (side windows, Exclusion List, buy list editor).",
        names = { "MMTConfigFrame", "MMTDropdownList", "MMTColorPopup", "MMTAutomationsMiscFrame", "MMTDistanceFormatFrame",
            "MMTXPLookFrame", "MMTBuyEditorFrame", "MMTExclusionListFrame" } },
    { id = "dialogs", title = "Dialogs", tip = "Yes / no questions, the reload window, copy / text windows and the sync window.",
        names = { "MMTConfirmFrame", "MMTReloadFrame", "MMTCopyFrame", "MMTTextFrame", "MMTSyncReceiveFrame" } },
    { id = "mail", title = "MMT Auto-Mailing", tip = "The window beside the mailbox.", names = { "MMTMailWindow" } },
    { id = "death", title = "Death panel", names = { "MMTDeathPanel" } },
    { id = "itemcompare", module = "ItemCompare", title = "Item Compare tooltips", names = { "MMTCompareTip" } },
    { id = "teambags", module = "TeamInventory", title = "Team Inventory", tip = "Team bags, the amount dialog and the transfer dialog.",
        names = { "MMTTeamBagsWindow", "MMTTeamBagsAmount", "MMTTransferDialog" } },
    { id = "teamgear", module = "TeamGear", title = "Team Gear", names = { "MMTTeamGearWindow", "MMTTeamGearOverview" } },
    { id = "pawn", module = "PawnCompare", title = "Pawn Compare scales", names = { "MMTPawnScalesWindow" } },
    { id = "qol", module = "QoL", title = "Send windows (ForeverAuras / EllesmereUI)", names = { "MMTQoLAurasWindow", "MMTQoLEllesmereWindow" } },
    { id = "totems", module = "Totems", title = "Totem presets", names = { "MMTTotemsPresets" } },
    { id = "questtracker", module = "QuestTracker", title = "Quest Tracker", play = true, tip = "Background, edges and accent; its own opacity and fonts stay." },
    { id = "infowindow", title = "Info window", play = true, tip = "Background and edges; the bars keep their colours, its own opacity stays." },
    { id = "livetracker", module = "Statistics", title = "Statistics live tracker", play = true, tip = "Background, edges and accent (top line, title); its own size stays." },
    { id = "other", title = "Other MMT windows", tip = "Every other window built from MMT's widgets, e.g. the Info window's column settings." },
}

local byId, byName = {}, {}
for _, t in ipairs(mod.TARGETS) do
    byId[t.id] = t
    for _, n in ipairs(t.names or {}) do byName[n] = t.id end
end
mod.TARGET_BY_ID = byId

function mod.TargetOpt(id, key, default)
    local s = mod.M.store
    local t = s and s.targets and s.targets[id]
    local v = t and t[key]
    if v == nil then return default end
    return v
end

function mod.SetTargetOpt(id, key, value)
    local s = mod.M.store
    if not s then return end
    s.targets = s.targets or {}
    s.targets[id] = s.targets[id] or {}
    s.targets[id][key] = value
    mod.Apply()
end

-- shown in the Windows list: the core's own windows always, a module's while that module is
-- installed and switched on (Manage modules)
function mod.TargetAvailable(t)
    if not t.module then return true end
    local m = MMT and MMT.modules and MMT.modules[t.module]
    return m and m.enabled and true or false
end

function mod.TargetOn(id) return mod.TargetOpt(id, "on", true) ~= false end

-- the window an object sits in -> its entry (cached: windows don't move to another parent)
local cache = setmetatable({}, { __mode = "k" })
function mod.TargetOf(obj)
    if not obj then return "other" end
    local id = cache[obj]
    if id then return id end
    local f, n = obj, 0
    while n < 30 do
        n = n + 1
        local p = f.GetParent and f:GetParent()
        if not p or p == UIParent then break end
        f = p
    end
    local name = f.GetName and f:GetName()
    id = (name and byName[name]) or "other"
    cache[obj] = id
    return id
end

-- the style for this object: nil (MMT's own look) when its window is switched off
function mod.Gate(S, obj)
    if not S then return nil end
    if mod.TargetOn(mod.TargetOf(obj)) then return S end
    return nil
end

-- the style's font for this object's window (font = INHERIT | ON | OFF)
function mod.TargetFonts(obj)
    local v = mod.TargetOpt(mod.TargetOf(obj), "font", "INHERIT")
    if v == "ON" then return true elseif v == "OFF" then return false end
    return mod.Opt("fonts") and true or false
end
