-- MMT module: Styles.
-- Another look for MMT's settings window and every window built from MMT's
-- widgets (the core's and the modules'): ElvUI-like or EllesmereUI-like, or
-- None = MMT's own look. Nothing of the core is edited: Skin.lua hooks
-- MMT.UI's builders (hooksecurefunc) and keeps the original colours, fonts and
-- anchors of everything it changes, so None puts them back.
--
--   Styles.lua    the styles (colours, fonts, edges)
--   Skin.lua      the hooks, painting, the public QStyles API for modules
--   Settings.lua  settings page and debug report
--
-- The choice is ACCOUNT-wide (M.store): a look belongs to the screen and the
-- player, not to a team profile (like the core's window scale).

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.3.3"

local M = MMT.NewModule({
    name = "qStyles",   -- the addon folder is MMT_qStyles
    title = "Styles",
    description = "Another look for MMT's settings window and the windows of MMT and its modules: ElvUI-like, EllesmereUI-like or Classic (the game's old window art), switched right away.",
    defaults = {},
})
mod.M = M

mod.DEFAULTS = {
    style = "NONE",    -- NONE | ELVUI | ELLESMERE | MODERN | CLASSIC
    fonts = true,      -- the style's font on MMT's labels and edit boxes
    accent = true,     -- the style's accent colour instead of MMT's blue
    classicBg = "ROCK", -- Classic's window background: ROCK | MARBLE | TOOLTIP | DARK (Art.lua)
    gameFont = false,  -- MMT keeps the game's own font when an addon swaps all game text (Skin.lua GameFace)
}

function mod.Opt(key)
    local s = M.store
    if not s then return mod.DEFAULTS[key] end
    if s[key] == nil then return mod.DEFAULTS[key] end
    return s[key]
end

function mod.SetOpt(key, value)
    if not M.store then return end
    M.store[key] = value
    mod.Apply()
end

-- the style shown now: nil = MMT's own look
function mod.Current()
    if not M.enabled then return nil end
    return mod.STYLES[mod.Opt("style")]
end

function mod.SetStyle(key)
    if not mod.STYLES[key] and key ~= "NONE" then return false end
    mod.SetOpt("style", key)
    return true
end

function mod.ResetSettings()
    if not M.store then return end
    for k in pairs(mod.DEFAULTS) do M.store[k] = nil end
    mod.Apply()
end

-- A UI addon the player uses: its style is offered ONCE (only while no style was ever picked here).
-- EllesmereUI first when both are loaded. The answer is remembered in M.store.offered[addon].
local OFFERS = { { addon = "EllesmereUI", style = "ELLESMERE" }, { addon = "ElvUI", style = "ELVUI" } }

local function Loaded(addon)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, addon)
    return ok and loaded and true or false
end

function mod.OfferStyle()
    local s = M.store
    if not (M.enabled and s) or s.style ~= nil then return end   -- a style was picked (None too): never ask
    if not (MMT.UI and MMT.UI.Confirm) or (InCombatLockdown and InCombatLockdown()) then return end
    s.offered = s.offered or {}
    for _, o in ipairs(OFFERS) do
        if Loaded(o.addon) and not s.offered[o.addon] then
            s.offered[o.addon] = true
            local title = mod.StyleTitle(o.style)
            MMT.UI.Confirm(("%s is installed. Give MMT's settings and windows the %s style?\n\n"
                .. "|cff999999You can change it any time: /mmt > Styles, or /mmtstyle.|r"):format(o.addon, title),
                "Use " .. title, function()
                    mod.SetStyle(o.style)
                    MMT.Print("Style: %s. Change it under /mmt > Styles.", title)
                end, "No thanks")
            return
        end
    end
end

M.OnEnable = function()
    mod.Apply()
    -- a moment after login, when the other addons' windows are set up
    if C_Timer and C_Timer.After then C_Timer.After(5, function() pcall(mod.OfferStyle) end) end
end

M.OnDisable = function()
    mod.Apply()   -- Current() is nil now: everything goes back
end

-- /mmtstyle [none | elvui | ellesmere | modern | classic]
local NAMES = { none = "NONE", elvui = "ELVUI", elv = "ELVUI", ellesmere = "ELLESMERE", ellesmereui = "ELLESMERE", eui = "ELLESMERE", classic = "CLASSIC", modern = "MODERN", blizzard = "MODERN" }
SLASH_MMTQSTYLES1 = "/mmtstyle"
SlashCmdList.MMTQSTYLES = function(msg)
    local arg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        MMT.ToggleConfig(M.name)
        return
    end
    if arg == "frame" then
        local lines = mod.Describe()
        if #lines == 0 then MMT.Print("Styles: no frame under the mouse.") end
        for _, l in ipairs(lines) do MMT.Print("Styles: %s", l) end
        return
    end
    local key = NAMES[arg]
    if not key then
        MMT.Print("/mmtstyle - settings, /mmtstyle none | elvui | ellesmere | modern | classic - switch the style, /mmtstyle frame - what the style did to the window under the mouse")
        return
    end
    if not M.enabled then MMT.Print("Styles is switched off (/mmt > Manage modules).") return end
    mod.SetStyle(key)
    MMT.Print("Style: %s.", mod.StyleTitle(key))
end
