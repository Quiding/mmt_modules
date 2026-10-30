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

mod.VERSION = "0.2.7"

local M = MMT.NewModule({
    name = "qStyles",   -- the addon folder is MMT_qStyles
    title = "Styles",
    description = "Another look for MMT's settings window and the windows of MMT and its modules: ElvUI-like, EllesmereUI-like or Classic (the game's old window art), switched right away.",
    defaults = {},
})
mod.M = M

mod.DEFAULTS = {
    style = "NONE",    -- NONE | ELVUI | ELLESMERE | CLASSIC
    fonts = true,      -- the style's font on MMT's labels and edit boxes
    accent = true,     -- the style's accent colour instead of MMT's blue
    classicBg = "ROCK", -- Classic's window background: ROCK | MARBLE | TOOLTIP | DARK (Art.lua)
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

M.OnEnable = function()
    mod.Apply()
end

M.OnDisable = function()
    mod.Apply()   -- Current() is nil now: everything goes back
end

-- /mmtstyle [none | elvui | ellesmere | classic]
local NAMES = { none = "NONE", elvui = "ELVUI", elv = "ELVUI", ellesmere = "ELLESMERE", ellesmereui = "ELLESMERE", eui = "ELLESMERE", classic = "CLASSIC" }
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
        MMT.Print("/mmtstyle - settings, /mmtstyle none | elvui | ellesmere | classic - switch the style, /mmtstyle frame - what the style did to the window under the mouse")
        return
    end
    if not M.enabled then MMT.Print("Styles is switched off (/mmt > Manage modules).") return end
    mod.SetStyle(key)
    MMT.Print("Style: %s.", mod.StyleTitle(key))
end
