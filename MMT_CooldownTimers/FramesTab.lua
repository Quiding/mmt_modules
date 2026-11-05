-- MMT Cooldown / Buff Timers: the "Frames" settings tab - each member's icons beside
-- their party / raid frame (IconBars v14, cfg.onFrames). Identical in MMT_CooldownTimers and
-- MMT_BuffTimers: keep both copies the same.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers

-- the unit frames found right now: "EllesmereUI (5)" or "none"
function mod.FramesFound()
    local _, _, count = MMTIconBars.UnitFrames()
    local parts = {}
    for _, p in ipairs(MMTIconBars.PROVIDERS) do
        if count[p.name] then parts[#parts + 1] = ("%s (%d)"):format(p.name, count[p.name]) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- where = { choices, get, set [, more = { {title, icon, build(col, tile)}, ... }] }: the module's own
-- "Show the icons" cycle, and tiles of its own below Party Frames (MMT 1.0.0 tiles, SettingsKit's TileStack)
function mod.FramesTab(panel, Opt, status, where)
    local W, X2 = H.TILE_W, H.TILE_W + H.TILE_GAP
    local left = {
        { "Party Frames", "INV_Misc_Spyglass_02", function(L)
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
            local size = L:Slider("Icon size", 12, 100, 1, gz, sz)
            -- greyed while every row takes its frame's height (Buff Timers: still the All bar's size above the frames)
            local refresh = size.Refresh
            size.Refresh = function(...)
                if refresh then refresh(...) end
                local used = not M.db.framesFit or M.db.allOnFrames
                size:SetAlpha(used and 1 or 0.4)
                local bar = size.GetChildren and size:GetChildren()
                if bar and bar.EnableMouse then
                    bar:EnableMouse(used and true or false)
                    if bar.EnableMouseWheel then bar:EnableMouseWheel(used and true or false) end
                end
            end
            local gx, sx = Opt("framesX")
            L:Slider("X offset", -100, 100, 1, gx, sx)
            local gy, sy = Opt("framesY")
            L:Slider("Y offset", -100, 100, 1, gy, sy)
            local go, so = Opt("framesOthers")
            L:Cycle("Members without a frame", {
                { value = "WINDOW", text = "In the window" },
                { value = "HIDE", text = "Hidden" },
            }, go, so)
        end },
    }
    for _, it in ipairs(where.more or {}) do left[#left + 1] = it end
    mod.TileStack(panel, 0, 0, W, left)
    mod.TileStack(panel, X2, 0, W, {
        { "How It Works", "INV_Misc_Book_09", function(R)
            R:Note("Each member's icons sit beside their party or raid frame and follow it when the frames are re-sorted or moved. Frames: EllesmereUI's party / raid frames, Blizzard's party and raid frames. Members outside your group have no frame.")
            R:Button("Which frames are found?", function()
                status.Show_("Unit frames found: " .. mod.FramesFound() .. ".")
            end)
        end },
    })
end

-- The Look > Window sub-tab only matters while something can show in the window. state() returns
-- "ALL" (in use), "SOME", text (partly: the line under it says what still uses it) or "NONE", text
-- (greyed, an overlay takes the clicks and says why). Redrawn on every settings change (REFRESH).
function mod.WindowShade(panel, state)
    local cover = CreateFrame("Frame", nil, panel)
    cover:SetAllPoints()
    cover:SetFrameLevel((panel.GetFrameLevel and panel:GetFrameLevel() or 1) + 50)
    cover:EnableMouse(true)
    cover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Window", 1, 1, 1)
        GameTooltip:AddLine(self.why or "", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local line = UI.Label(panel, "")
    line:SetPoint("BOTTOMLEFT", 0, 4)
    line:SetWidth(H.PAGE_W)
    line:SetJustifyH("LEFT")
    line:SetTextColor(1, 0.82, 0)
    local function Update()
        local s, why = state()
        cover.why = why
        cover:SetShown(s == "NONE")
        panel:SetAlpha(s == "NONE" and 0.4 or 1)
        line:SetText(s ~= "ALL" and why or "")
    end
    Update()
    panel:HookScript("OnShow", Update)
    M:Listen("REFRESH", Update)
end
