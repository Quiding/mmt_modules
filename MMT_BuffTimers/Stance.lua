-- MMT Cooldown / Buff Timers: one icon per member with the stance / form they're in (warrior stances,
-- druid forms, stealth, shadowform, ... = whatever the game puts on the stance bar). Shared by both
-- modules: each ships this same file, the newest VERSION of the lib part wins (like IconBars), and it
-- works while either module is on.
--
-- Settings (M.db.stance, one table) live in Cooldown Timers' profile settings when that addon is loaded
-- (even switched off), else in Buff Timers'; both settings pages show the same "Stance" tab. Where:
--   OFF | WINDOW (own MMTIconBars window "MMTStance") | CD / BUFF (first icon on the Cooldown / Buff
--   Timers bars, IconBars extra anchored "^"; that bar not shown -> the own window instead)
-- Others' stances: each client sends "MST:<spellID>" (0 = none) once per change, and its heartbeat
-- carries it (stn from Cooldown Timers, stb from Buff Timers while Cooldown Timers is off).
-- Identical in MMT_CooldownTimers and MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M

local VERSION = 1
local lib = rawget(_G, "MMTStanceLib")
if not lib or (lib.version or 0) < VERSION then
    lib = lib or {}
    MMTStanceLib = lib
    lib.version = VERSION
    lib.mods = lib.mods or {}         -- [module name] = { M = M, mod = mod }
    lib.told = lib.told or {}         -- [team key] = { id, time } from MST messages

    lib.DEFAULTS = {
        where = "OFF", shown = true, locked = false, clickThrough = false, iconSize = 28, showNames = true,
        fullNames = false, nameSize = 11, growth = "DOWN", spacing = 2, rowGap = 4, scale = 1, bgAlpha = 0.4,
        point = { "CENTER", "CENTER", 0, -150 },
    }
    local DEFAULTS = lib.DEFAULTS
    local WINDOWS = { CD = "MMTCooldowns", BUFF = "MMTBuffs" }
    lib.WINDOWS = WINDOWS

    local function Loaded(name) local e = lib.mods[name]; return e and e.M.db and e end
    local function Active(name) return MMT.ModuleActive and MMT.ModuleActive(name) and true or false end

    -- the module whose settings hold the stance settings
    function lib.Host() return Loaded("CooldownTimers") or Loaded("BuffTimers") end

    -- the stance settings (missing fields read from the defaults)
    function lib.Cfg()
        local h = lib.Host()
        if not h then return nil end
        local t = h.M.db.stance
        if type(t) ~= "table" then t = {}; h.M.db.stance = t end
        if getmetatable(t) == nil then setmetatable(t, { __index = DEFAULTS }) end
        return t
    end

    -- a setting changed on either page: into every loaded module's copy (stays right if the host changes)
    function lib.Set(k, v)
        for _, e in pairs(lib.mods) do
            if e.M.db then
                e.M.db.stance = type(e.M.db.stance) == "table" and e.M.db.stance or {}
                e.M.db.stance[k] = MMT.CopyTable(v)
            end
        end
        lib.Apply()
    end

    -- a whole table (import) or none (reset) for every copy
    function lib.SetAll(t)
        for _, e in pairs(lib.mods) do
            if e.M.db then e.M.db.stance = MMT.CopyTable(t or {}) end
        end
        lib.Apply()
    end

    function lib.AnyOn() return Active("CooldownTimers") or Active("BuffTimers") end

    ---------------------------------------------------------------------------
    -- Who is in which stance
    ---------------------------------------------------------------------------
    -- this character's stance: spell ID (0 = none), icon
    function lib.Own()
        local ok, i = pcall(function() return GetShapeshiftForm and GetShapeshiftForm() end)
        i = ok and tonumber(i) or 0
        if i > 0 and GetShapeshiftFormInfo then
            local icon, _, _, spellID = GetShapeshiftFormInfo(i)
            return tonumber(spellID) or 0, icon
        end
        return 0, nil
    end

    -- a member's stance spell ID: own read live, others the newest of message / heartbeat
    function lib.StanceOf(key)
        if MMT.IsSelf(key) then return (lib.Own()) end
        local t = lib.told[key]
        if t and GetTime() - t[2] < 40 then return t[1] end
        local s = MMT.status and MMT.status[key]
        local ext = s and s.ext
        local hb = ext and tonumber(ext.stn or ext.stb)
        if hb then return hb end
        return t and t[1] or nil
    end

    -- the icon for member key, or nil (no stance / not known)
    function lib.Icons(key, look)
        local id = lib.StanceOf(key)
        if not id or id <= 0 then return nil end
        local texture
        if MMT.IsSelf(key) then texture = select(2, lib.Own()) end
        texture = texture or (lib.IconOf and lib.IconOf(id)) or 134400
        local name = lib.NameOf and lib.NameOf(id)
        if type(name) ~= "string" then name = nil end
        return { { texture = texture, state = "ready", readyAlpha = 1, spell = id, oid = "stance", anchor = "^",
            look = look, tip = name and ("Stance / form: " .. name) or nil } }
    end

    ---------------------------------------------------------------------------
    -- Where it shows
    ---------------------------------------------------------------------------
    -- the bars it's on now ("MMTCooldowns" / "MMTBuffs"), or nil (own window / off)
    function lib.Target()
        local c = lib.Cfg()
        local w = c and WINDOWS[c.where]
        if w and MMTIconBars.CanHost(w) then return w end
        return nil
    end

    function lib.WindowWanted()
        local c = lib.Cfg()
        return c ~= nil and c.where ~= "OFF" and lib.Target() == nil and lib.AnyOn()
    end

    local function Rows()
        local rows = {}
        local seen = {}
        local list = {}
        local own = MMT.PlayerFull and MMT.PlayerFull()
        if own then list[1] = own; seen[own] = true end
        for _, key in ipairs(MMT.SortedMembers()) do if not seen[key] then list[#list + 1] = key end end
        for _, key in ipairs(list) do
            local icons = lib.Icons(key)
            if icons then rows[#rows + 1] = { key = key, icons = icons } end
        end
        return rows
    end

    -- the icon rides on both modules' bars as an extra that answers only while that bar is the target
    -- (so a bar that stops showing - module off, attached elsewhere - hands it to the window at once)
    lib.extraOn = lib.extraOn or {}
    function lib.Apply()
        if not MMTIconBars then return end
        for _, w in pairs(WINDOWS) do
            if not lib.extraOn[w] then
                lib.extraOn[w] = true
                MMTIconBars.SetExtra(w, "stance", function(key)
                    if not lib.AnyOn() or MMTStanceLib.Target() ~= w then return nil end
                    return MMTStanceLib.Icons(key)
                end, "LEFT")
            else
                MMTIconBars.Refresh(w)
            end
        end
        if lib.window then lib.window:Refresh() end
    end

    -- the redraw after a stance changed somewhere
    function lib.Redraw()
        local t = lib.Target()
        if t then MMTIconBars.Refresh(t) end
        if lib.window then lib.window:Refresh() end
    end

    function lib.OnMessage(key, text)
        local id = type(text) == "string" and tonumber(text:match("^MST:(%d+)$"))
        if id and not MMT.IsSelf(key) then
            lib.told[key] = { id, GetTime() }
            lib.Redraw()
        end
    end

    -- own changes: one message, a redraw
    lib.sent = lib.sent
    local function OwnChanged()
        local id = lib.Own()
        if id ~= lib.sent and lib.AnyOn() then
            lib.sent = id
            MMT.SendToTeam("MST:" .. id, true)
        end
        lib.Redraw()
    end
    lib.OwnChanged = OwnChanged
    if not lib.events then
        lib.events = CreateFrame("Frame")
        for _, ev in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD" }) do
            pcall(lib.events.RegisterEvent, lib.events, ev)
        end
    end
    lib.events:SetScript("OnEvent", function() lib.OwnChanged() end)

    function lib.Window()
        if lib.window or not MMTIconBars then return lib.window end
        lib.window = MMTIconBars.NewWindow({
            name = "MMTStance",
            frameOrder = 3,
            cfg = function() return lib.Cfg() end,
            rows = Rows,
            active = function() return lib.WindowWanted() end,
        })
        return lib.window
    end

    -- a module registers itself (both do; Cooldown Timers' settings win as the host)
    function lib.Register(M2, mod2)
        lib.mods[M2.name] = { M = M2, mod = mod2 }
        lib.IconOf = lib.IconOf or mod2.SpellIconAny or mod2.SpellIcon
        lib.NameOf = lib.NameOf or function(id) return (mod2.SpellInfo(id)) end
        lib.Window()
    end
end

lib.Register(M, mod)

-- the team's stance messages; the heartbeat says ours (Buff Timers only while Cooldown Timers is off)
M:Listen("TEAM_MESSAGE", function(key, _, text) MMTStanceLib.OnMessage(key, text) end)
M:Heartbeat(M.name == "CooldownTimers" and "stn" or "stb", function()
    if M.name ~= "CooldownTimers" and MMT.ModuleActive and MMT.ModuleActive("CooldownTimers") then return nil end
    return tostring((MMTStanceLib.Own()))
end)
M:Listen("STATUS_CHANGED", function() MMTStanceLib.Redraw() end)
M:Listen("REFRESH", function() MMTStanceLib.Apply() end)
-- switched on / off, another profile: the icon goes where it should now
for _, fn in ipairs({ "OnEnable", "OnDisable", "OnProfileChanged" }) do
    local old = M[fn]
    M[fn] = function(...)
        if old then old(...) end
        MMTStanceLib.Apply()
        if fn == "OnEnable" then MMTStanceLib.OwnChanged() end
    end
end

-- a reset of the Stance tab (or everything) on either page resets the shared settings (SettingsKit ResetKeys)
function mod.AfterReset(keys)
    if not keys then MMTStanceLib.SetAll(nil) return end
    for _, k in ipairs(keys) do if k == "stance" then MMTStanceLib.SetAll(nil) return end end
end

-- the "Stance" settings tab (the same settings on both pages)
function mod.StanceTab(panel, status)
    local UI, H = MMT.UI, MMT.ConfigHelpers
    local COL_W, COL2_X = H.COL_W, H.COL2_X
    local function G(k) return function() local c = MMTStanceLib.Cfg(); return c and c[k] end end
    local function S(k) return function(v) MMTStanceLib.Set(k, v) end end
    local L = UI.Column(panel, 0, 0, COL_W)
    L:Header("Stance / form")
    L:Cycle("Show it", {
        { value = "OFF", text = "Off" },
        { value = "WINDOW", text = "In its own window" },
        { value = "CD", text = "On the Cooldown Timers bars" },
        { value = "BUFF", text = "On the Buff Timers bars" },
    }, G("where"), S("where"))
    L:Header("Own window")
    L:Check("Show the window", G("shown"), S("shown"))
    L:Check("Lock position", G("locked"), S("locked"))
    L:Slider("Icon size", 16, 64, 1, G("iconSize"), S("iconSize"))
    L:Cycle("Names", {
        { value = "OFF", text = "Off" },
        { value = "FIRST", text = "First name" },
        { value = "FULL", text = "First and last name" },
    }, function()
        local c = MMTStanceLib.Cfg()
        if not (c and c.showNames) then return "OFF" end
        return c.fullNames and "FULL" or "FIRST"
    end, function(v)
        MMTStanceLib.Set("showNames", v ~= "OFF")
        MMTStanceLib.Set("fullNames", v == "FULL")
    end)
    local reset = UI.Button(panel, COL_W, "Reset position", function()
        MMTStanceLib.Set("point", MMTStanceLib.DEFAULTS.point)
        status.Show_("Stance window back in the middle of the screen.")
    end)
    L:Add(reset, UI.ROW + 2)

    local R = UI.Column(panel, COL2_X, 0, COL_W)
    R:Header("How it works")
    R:Note("One icon per member with the stance or form they're in: warrior stances, druid forms, stealth, shadowform - whatever the game puts on their stance bar. Nothing shows for a member in no stance.")
    R:Note("On the Cooldown Timers or Buff Timers bars it's the first icon of each member's row; while those bars aren't shown (module off, attached elsewhere) it uses its own window.")
    R:Note("The same settings on both modules' pages; it works while either module is on. Each client tells the team once when its stance changes.")
    return L, R
end
