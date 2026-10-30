-- MMT Cooldown / Buff Timers: the Look > Timer sub-tab - the timer text, the countdown circle that runs
-- round the icon, and other colours for both once only a few seconds are left (IconBars v19: timerColor,
-- swipeColor / swipeAlpha, soonSecs / urgentSecs + their colours). Identical in MMT_CooldownTimers and
-- MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X

local function Color(col, text, key, apply)
    col:Color(text, function() return M.db[key] end, function(c)
        M.db[key] = { r = c.r, g = c.g, b = c.b }
        apply()
    end)
end

function mod.TimerTab(panel, Opt, apply)
    local L = UI.Column(panel, 0, 0, COL_W)
    L:Header("Timer text")
    local gt, st = Opt("timerSize")
    L:Slider("Size", 8, 32, 1, gt, st)
    Color(L, "Colour", "timerColor", apply)
    L:Header("Countdown circle")
    Color(L, "Colour", "swipeColor", apply)
    local ga, sa = Opt("swipeAlpha")
    L:Slider("Opacity", 0, 1, 0.05, ga, sa, "%.2f")
    L:Note("The dark circle that runs round an icon while it counts down.")

    local R = UI.Column(panel, COL2_X, 0, COL_W)
    R:Header("Little time left")
    local gs, ss = Opt("soonSecs")
    R:Slider("Soon: below seconds (0 = off)", 0, 120, 1, gs, ss)
    Color(R, "Soon: timer colour", "soonTextColor", apply)
    Color(R, "Soon: circle colour", "soonSwipeColor", apply)
    local gu, su = Opt("urgentSecs")
    R:Slider("Urgent: below seconds (0 = off)", 0, 60, 1, gu, su)
    Color(R, "Urgent: timer colour", "urgentTextColor", apply)
    Color(R, "Urgent: circle colour", "urgentSwipeColor", apply)
    R:Note("When both apply, urgent wins.")
    return L, R
end
