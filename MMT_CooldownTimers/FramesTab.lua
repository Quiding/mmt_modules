-- MMT Cooldown / Buff Timers: the "Frames" settings tab - each member's icons beside
-- their party / raid frame (IconBars v14, cfg.onFrames). Identical in MMT_CooldownTimers and
-- MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

-- the unit frames found right now: "EllesmereUI (5)" or "none"
function mod.FramesFound()
    local _, _, count = MMTIconBars.UnitFrames()
    local parts = {}
    for _, p in ipairs(MMTIconBars.PROVIDERS) do
        if count[p.name] then parts[#parts + 1] = ("%s (%d)"):format(p.name, count[p.name]) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- where = { choices, get, set }: the module's own "Show the icons" cycle; returns both columns
function mod.FramesTab(panel, Opt, status, where)
    local L = UI.Column(panel, 0, 0, COL_W)
    L:Header("Party frames")
    L:Cycle("Show the icons", where.choices, where.get, where.set)
    local gs, ss = Opt("framesSide")
    L:Cycle("Side of the frame", {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "TOP", text = "Above" },
        { value = "BOTTOM", text = "Below" },
    }, gs, ss)
    local gf, sf = Opt("framesFit")
    L:Check("Icons as high as the frame", gf, sf, "Each member's icons take the height of their party / raid frame (the icon size below is then only for the All bar).")
    local gz, sz = Opt("framesIconSize")
    L:Slider("Icon size", 12, 100, 1, gz, sz)
    local gx, sx = Opt("framesX")
    L:Slider("X offset", -100, 100, 1, gx, sx)
    local gy, sy = Opt("framesY")
    L:Slider("Y offset", -100, 100, 1, gy, sy)
    local go, so = Opt("framesOthers")
    L:Cycle("Members without a frame", {
        { value = "WINDOW", text = "In the window" },
        { value = "HIDE", text = "Hidden" },
    }, go, so)

    local R = UI.Column(panel, COL2_X, 0, COL_W)
    R:Header("How it works")
    R:Note("Each member's icons sit beside their party or raid frame and follow it when the frames are re-sorted or moved. Frames: EllesmereUI's party / raid frames, Blizzard's party and raid frames. Members outside your group have no frame.")
    local check = UI.Button(panel, COL_W, "Which frames are found?", function()
        status.Show_("Unit frames found: " .. mod.FramesFound() .. ".")
    end)
    R:Add(check, UI.ROW + 2)
    return L, R
end
