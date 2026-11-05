-- MMT Cooldown / Buff Timers: the stance / form each member is in (warrior stances, druid forms, stealth,
-- shadowform, ... = whatever the game puts on the stance bar). Shared by both modules: each ships this
-- same file, the newest VERSION of the lib part (MMTStanceLib) wins, and it works while either is on.
--   * Buff Timers lists: the entry { stance = true } (type "stance" in a list's add box) shows the member's
--     stance icon where the list puts it - per class / spec / character list, "Only for" counts (Window.lua)
--   * its own window (M.db.stance.where = WINDOW, MMTIconBars window "MMTStance"): every member with one
-- Settings (M.db.stance, one table) live in Cooldown Timers' profile settings when that addon is loaded
-- (even switched off), else in Buff Timers'; both settings pages show the same "Stance" tab.
-- Others' stances: each client sends "MST:<spellID>" (0 = none) once per change, and its heartbeat
-- carries it (stn from Cooldown Timers, stb from Buff Timers while Cooldown Timers is off).
-- Identical in MMT_CooldownTimers and MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M

local VERSION = 3
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

    -- member key's stance: { id, texture, name } or nil (no stance / not known)
    function lib.Data(key)
        local id = lib.StanceOf(key)
        if not id or id <= 0 then return nil end
        -- the spell's own icon first: for the ACTIVE form the game's form icon is a generic
        -- "active" picture (a paladin's aura showed a blue spark, not the aura)
        local texture = lib.IconOf and lib.IconOf(id)
        if not texture and MMT.IsSelf(key) then texture = select(2, lib.Own()) end
        texture = texture or 134400
        local name = lib.NameOf and lib.NameOf(id)
        if type(name) ~= "string" then name = nil end
        return { id = id, texture = texture, name = name }
    end

    -- the own window's icon for member key, or nil
    function lib.Icons(key)
        local d = lib.Data(key)
        if not d then return nil end
        return { { texture = d.texture, state = "ready", readyAlpha = 1, spell = d.id,
            tip = d.name and ("Stance / form: " .. d.name) or nil } }
    end

    ---------------------------------------------------------------------------
    -- Its own window
    ---------------------------------------------------------------------------
    function lib.WindowWanted()
        local c = lib.Cfg()
        return c ~= nil and c.where == "WINDOW" and lib.AnyOn()
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

    function lib.Apply()
        if lib.window then lib.window:Refresh() end
    end

    -- the redraw after a stance changed somewhere: the Buff Timers bars (list entries) and the window
    function lib.Redraw()
        if MMTIconBars then MMTIconBars.Refresh("MMTBuffs"); MMTIconBars.Refresh("MMTCooldowns") end
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
    local H = MMT.ConfigHelpers
    local W, X2 = H.TILE_W, H.TILE_W + H.TILE_GAP
    local function G(k) return function() local c = MMTStanceLib.Cfg(); return c and c[k] end end
    local function S(k) return function(v) MMTStanceLib.Set(k, v) end end
    mod.TileStack(panel, 0, 0, W, {
        { "Own Window", "Ability_Warrior_DefensiveStance", function(L)
            L:Cycle("Stance window", {
                { value = "OFF", text = "Off" },
                { value = "WINDOW", text = "On: every member with a stance" },
            }, function() local c = MMTStanceLib.Cfg(); return c and (c.where == "WINDOW" and "WINDOW" or "OFF") end, S("where"))
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
            L:Button("Reset position", function()
                MMTStanceLib.Set("point", MMTStanceLib.DEFAULTS.point)
                status.Show_("Stance window back in the middle of the screen.")
            end)
        end },
    })
    mod.TileStack(panel, X2, 0, W, {
        { "In the Buff Timers Lists", "Spell_Holy_WordFortitude", function(R)
            R:Note("Type stance in a Buff Timers list's add box (Buffs tab): that list's members get their stance / form as an icon in their row, where you drag it. Add it to the lists you want (e.g. Warrior: Fury) and leave it out of the others (Paladin); the cog limits it to classes / specs like a buff.")
        end },
        { "How It Works", "INV_Misc_Book_09", function(R)
            R:Note("Warrior stances, druid forms, stealth, shadowform - whatever the game puts on the member's stance bar; nothing for a member in no stance. Each client tells the team once when its stance changes (needs Cooldown or Buff Timers on). The window settings are the same on both modules' pages.")
        end },
    })
end
