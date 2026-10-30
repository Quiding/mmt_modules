-- MMT Styles: the styles. Each one only says colours, edges and fonts; Skin.lua
-- decides what they go on. Recreated from scratch (no code or art of ElvUI /
-- EllesmereUI is copied; EllesmereUI is "all rights reserved"): flat colour
-- textures, WoW's own fonts, and fonts other addons register with
-- LibSharedMedia (looked up by name, never copied).
--
-- Fields:
--   panel / control   {r, g, b}: dark fills (windows, lists / buttons, boxes)
--   panelTop          {r, g, b}: panels get a vertical gradient to this at the top
--   panelAlpha(a)     alpha of a panel from MMT's alpha (controlAlpha the same)
--   border            {r, g, b, a} of window edges, controlBorder of small frames
--   accentBorder      "BLACK" | "ACCENT": what MMT's accent-coloured edges become
--   inner             {r, g, b, a}: a second line just inside each edge (or nil)
--   shadow            { {r, g, b, a}, ... }: lines outside window edges, 1 px each
--   round             edges stop 1 px short of the corners (soft corners)
--   pixel             edges exactly one screen pixel thick (PixelUtil)
--   track             {r, g, b, a}: slider track
--   accent()          r, g, b
--   font()            font file; fontDelta = size added; fontFlags (nil = keep); noShadow
--   plainText / buttonText   {r, g, b, a} for MMT's plain white labels / button labels (nil = keep)
--   headerText        {r, g, b, a} | "ACCENT" for section headers, headerUpper = in capitals,
--                     headerLine = the line under them ({r, g, b, a} | "ACCENT")
--   hover             { edge = {r, g, b, a} | "ACCENT", label = {r, g, b, a} }: the widget under the mouse
--   chevron           dropdowns get a drawn chevron instead of MMT's "v"
--   art               Classic: the game's own window textures (Art.lua) instead of colours

local _, mod = ...

local function LSMFont(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, path = pcall(LSM.Fetch, LSM, "font", name, true)
    return ok and path or nil
end

local ARIAL_NARROW = "Fonts\\ARIALN.TTF"

-- EllesmereUI's accent when it is loaded (its public table), else the bronze it
-- starts with on Forever
local function EllesmereAccent()
    local E = EllesmereUI
    local c = type(E) == "table" and type(E.ELLESMERE_GREEN) == "table" and E.ELLESMERE_GREEN
    if c and tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then return c.r, c.g, c.b end
    return 220 / 255, 167 / 255, 127 / 255
end

mod.STYLES = {
    ELVUI = {
        key = "ELVUI",
        title = "ElvUI",
        description = "Flat dark panels, 1 pixel black edges with a faint line inside, a narrow outlined font.",
        panel = { 0.06, 0.06, 0.06 },
        panelAlpha = function(a) return math.min(a, 0.9) end,
        control = { 0.1, 0.1, 0.1 },
        controlAlpha = function(a) return a end,
        border = { 0, 0, 0, 1 },
        controlBorder = { 0, 0, 0, 1 },
        accentBorder = "BLACK",
        inner = { 1, 1, 1, 0.07 },
        pixel = true,
        track = { 0.1, 0.1, 0.1, 1 },
        accent = function() return 0.09, 0.52, 0.82 end,
        font = function() return LSMFont("PT Sans Narrow") or ARIAL_NARROW end,
        fontDelta = 2,
        fontFlags = "OUTLINE",
        noShadow = true,
        headerText = "ACCENT",
        headerLine = "ACCENT",
        hover = { edge = "ACCENT" },
        chevron = true,
    },
    ELLESMERE = {
        key = "ELLESMERE",
        title = "EllesmereUI",
        description = "Warm dark glassy panels with a soft light at the top, faint white edges with soft corners and a shadow, EllesmereUI's accent and font.",
        panel = { 0.069, 0.058, 0.047 },
        panelTop = { 0.105, 0.092, 0.08 },
        panelAlpha = function(a) return a * 0.94 end,
        control = { 0.103, 0.095, 0.088 },
        controlAlpha = function(a) return math.min(a, 0.9) end,
        border = { 1, 1, 1, 0.10 },
        controlBorder = { 1, 1, 1, 0.25 },
        accentBorder = "ACCENT",
        shadow = { { 0, 0, 0, 0.45 }, { 0, 0, 0, 0.2 } },
        round = true,
        track = { 1, 1, 1, 0.10 },
        accent = EllesmereAccent,
        font = function() return LSMFont("Expressway") or ARIAL_NARROW end,
        fontDelta = 2,
        plainText = { 1, 1, 1, 0.8 },
        buttonText = { 1, 1, 1, 0.7 },
        headerText = { 1, 1, 1, 0.45 },
        headerUpper = true,
        hover = { edge = { 1, 1, 1, 0.45 }, label = { 1, 1, 1, 1 } },
        chevron = true,
    },
    CLASSIC = {
        key = "CLASSIC",
        title = "Classic",
        description = "The game's own old window art: stone dialog backgrounds with carved borders, red buttons, the yellow check mark, the metal slider knob, gold text.",
        art = true,
        panel = { 0, 0, 0 },
        panelAlpha = function(a) return math.min(1, a) end,
        control = { 0.05, 0.05, 0.05 },
        controlAlpha = function(a) return a end,
        border = { 0.6, 0.6, 0.6, 1 },
        controlBorder = { 0.6, 0.6, 0.6, 1 },
        accentBorder = "ACCENT",
        track = { 0.2, 0.2, 0.2, 1 },
        accent = function() return 1, 0.82, 0 end,
        buttonText = { 1, 0.82, 0, 1 },
        headerLine = { 1, 0.82, 0, 0.25 },
    },
}

mod.ORDER = { "NONE", "ELVUI", "ELLESMERE", "CLASSIC" }

function mod.StyleTitle(key)
    local s = mod.STYLES[key]
    return s and s.title or "None (MMT's own look)"
end

function mod.StyleChoices()
    local t = {}
    for _, key in ipairs(mod.ORDER) do t[#t + 1] = { value = key, text = mod.StyleTitle(key) } end
    return t
end
