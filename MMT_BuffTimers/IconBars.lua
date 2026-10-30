-- MMTIconBars: a movable window with one row of icons per team member, in
-- MMT's flat style. Shared by MMT_Cooldowns and MMT_Buffs: both ship this
-- same file and the newest version wins (like an embedded library), so
-- KEEP BOTH COPIES IDENTICAL and raise VERSION when changing it.
--
--   local w = MMTIconBars.NewWindow{
--       name   = "MMTCooldowns",           -- global frame name, also the id for extras
--       cfg    = function() return M.db end, -- layout settings, read fresh every time
--       rows   = function() return rows end, -- { { key, icons = { icon, ... } }, ... }
--                                            -- a row may have label (+ color {r,g,b}) instead of a key
--       config = function() ... end,         -- right-click (open settings)
--       active = function() return M.enabled end, -- optional: hidden while false
--   }
--   w:Refresh()          rebuild from rows()
--   w:SetShown(on)
--
-- icon = { texture, state, start, duration, count, spell, item, tip,
--          tally, tallyPos (corner, e.g. "BOTTOMLEFT"), tallySize, tallyColor {r,g,b}  (v12: a
--          second number in its own corner, e.g. how many members have a buff),
--          missingAlpha, glowMissing, activeAlpha (override the window's cfg for
--          "missing" / "buff"),
--          tint = { r, g, b }, desaturate = true,
--          glow = true (glow regardless of state),
--          after = { state, start, duration } (state to switch to when a "buff" runs out,
--                  e.g. a spell's buff, then its cooldown),
--          drag = { group, id, move = fn(src, dst, after) } (v13, see "Dragging icons") }
--   state: "ready" | "cd" (start/duration) | "active" (glow) | "buff" (start/duration
--          optional, count) | "missing"
--
-- cfg fields: shown, locked, clickThrough, growth ("DOWN" top > down, "UP" down > top,
--   "RIGHT" left > right, "LEFT" right > left; older profiles: vertical), iconSize, spacing, rowGap,
--   iconZoom (% cut off each edge of the icon, default 8), showNames, fullNames, nameSize, showTimers, timerSize, readyAlpha, cdAlpha, missingAlpha, activeAlpha,
--   glowActive, glowMissing, scale, bgAlpha, point = { point, relPoint, x, y },
--   font (MMT font name), timerColor {r,g,b}, bgTexture / borderTexture (LibSharedMedia
--   names, "FLAT" / "NONE"), bgColor, borderColor {r,g,b}, borderSize, rowColor, rowAlpha,
--   bgTint (0..1: how strongly bgColor / rowColor colour a texture; Flat always takes the colour)
--
-- Extras: other modules can add icons to a window's rows:
--   MMTIconBars.SetExtra(windowName, id, fn(key) -> icons | nil, side "LEFT"|"RIGHT")
--   MMTIconBars.SetExtra(windowName, id, nil)   removes it
--
-- Dragging icons (v13): an icon with `drag` can be dragged along its own row (modules give icons
-- `drag` only in their arrange mode: MMTIconBars.SetArrange(windowName, on), MMTIconBars.Arranging(name),
-- session only; such icons take the mouse even with clickThrough and show a dotted grip). It only lands among icons of the same `group` (any value compared with ==, e.g. the list
-- table the entries come from): a line shows the spot, dropped past the group it goes to the group's
-- nearest end. On release move(src, dst, after) gets the dragged icon's drag table and that of the
-- group icon it lands before (after = false) or after (after = true); `id` tells icons apart (the
-- dragged one is dimmed, dropping it on its own spot does nothing). Dragging an icon without `drag`
-- moves the window like its background (when unlocked).
--
-- Party / raid frames (v14): cfg.onFrames puts each member's row beside that member's unit frame
-- (EllesmereUI's party / raid frames, Blizzard's compact party / raid frames, Blizzard's party
-- frames + PlayerFrame; lib.UnitFrames() finds them), cfg.allOnFrames does the same for label rows
-- (e.g. an All bar: above the top frame). Fields: framesSide ("RIGHT" | "LEFT" | "TOP" | "BOTTOM"),
-- framesX, framesY (offsets, + = right / up), framesIconSize (0 = iconSize), framesOthers ("WINDOW":
-- members without a frame stay in the window | "HIDE"), allX, allY. The rows are our own frames on
-- UIParent, placed at the unit frame's screen position (read, never anchored: the unit frames are
-- secure, and anchoring to them would make our frames protected in combat); a poll every 0.25 s
-- follows re-sorts, roster changes and moved frames. Rows of several windows on the same frame and
-- side line up one after the other, by def.frameOrder (lower = nearer the frame); label rows go last.

local VERSION = 14
if MMTIconBars and (MMTIconBars.version or 0) >= VERSION then return end

local lib = MMTIconBars or {}
MMTIconBars = lib
lib.version = VERSION
lib.windows = lib.windows or {}
lib.extras = lib.extras or {}   -- [windowName] = { [id] = { fn, side } }
lib.arrange = lib.arrange or {}  -- [windowName] = true while its icons are being arranged (session only)

function lib.Arranging(name) return lib.arrange[name] and true or false end
function lib.SetArrange(name, on)
    lib.arrange[name] = on and true or nil
    local w = lib.windows[name]
    if w then w:Refresh() end
end

local MMT = MMT

local function ClassColor(key)
    local m = MMT.db and MMT.db.team and MMT.db.team[key]
    local c = m and m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- "First" or "First Last" (WoW: Forever characters have two names)
function lib.MemberName(key, full)
    if full then return MMT.FullDisplay(key) end
    return MMT.FirstName(key)
end

local FLAT = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

-- LibSharedMedia texture (other addons bring it), nil for FLAT / NONE / unknown
local function Media(kind, name)
    if not name or name == "" or name == "FLAT" or name == "NONE" then return nil end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return LSM and LSM:Fetch(kind, name, true) or nil
end

-- background (+ border) of a frame; returns the inner padding the border needs
local function Skin(f, bgTex, color, alpha, edgeName, edgeColor, edgeSize, tint)
    color = color or {}
    local file = Media("background", bgTex)
    -- a real texture: blend white (its own colours) towards the colour by tint
    local r, g, b = color.r or 0, color.g or 0, color.b or 0
    if file then
        tint = math.max(0, math.min(1, tint or 1))
        r, g, b = 1 + (r - 1) * tint, 1 + (g - 1) * tint, 1 + (b - 1) * tint
    end
    local edge = Media("border", edgeName)
    if not f.SetBackdrop then
        f.bg:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, alpha or 0)
        return 0
    end
    if f.bg then f.bg:Hide() end
    local size = edge and (edgeSize or 12) or nil
    local inset = edge and math.floor(size / 4 + 0.5) or 0
    f:SetBackdrop({ bgFile = file or FLAT, edgeFile = edge, tile = false,
        edgeSize = size, insets = { left = inset, right = inset, top = inset, bottom = inset } })
    f:SetBackdropColor(r, g, b, alpha or 0)
    if edge then
        edgeColor = edgeColor or {}
        f:SetBackdropBorderColor(edgeColor.r or 1, edgeColor.g or 1, edgeColor.b or 1, 1)
    end
    return inset
end
lib.Media = Media

-- direction the members are added in; older profiles only have "vertical"
function lib.Growth(c)
    local g = c.growth
    if g == "DOWN" or g == "UP" or g == "RIGHT" or g == "LEFT" then return g end
    return c.vertical and "RIGHT" or "DOWN"
end

-- the frame is pinned at the edge it grows away from
local ANCHOR = { DOWN = "TOPLEFT", RIGHT = "TOPLEFT", UP = "BOTTOMLEFT", LEFT = "TOPRIGHT" }
lib.ANCHOR = ANCHOR

-- where a frame is now, as { anchor, anchor, x, y } relative to the same corner of UIParent
function lib.PointAt(f, anchor)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return nil end
    local ratio = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    local W, H = UIParent:GetRight() * ratio, UIParent:GetTop() * ratio
    local x = anchor:find("RIGHT") and (r - W) or l
    local y = anchor:find("BOTTOM") and b or (t - H)
    return { anchor, anchor, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function FormatTime(t)
    if t >= 3600 then return ("%dh"):format(math.floor(t / 3600 + 0.5)) end
    if t >= 60 then return ("%dm"):format(math.floor(t / 60 + 0.5)) end
    if t >= 10 then return tostring(math.floor(t + 0.5)) end
    return ("%.1f"):format(t)
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local IconDragStart, IconDragStop   -- below ("Dragging icons")
local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    local pulse = b.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.3); fade:SetDuration(0.5)
    b.pulse = pulse
    b.glow:Hide()
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.timer = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.timer:SetPoint("CENTER", 0, 0)
    b.count = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tally = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- dotted grip (2 x 3 dots on a dark patch, top left) on icons that can be dragged
    b.grip = CreateFrame("Frame", nil, over)
    b.grip:SetSize(8, 12)
    b.grip:SetPoint("TOPLEFT", 1, -1)
    local patch = b.grip:CreateTexture(nil, "ARTWORK")
    patch:SetAllPoints()
    patch:SetColorTexture(0, 0, 0, 0.55)
    for col = 0, 1 do
        for r = 0, 2 do
            local d = b.grip:CreateTexture(nil, "OVERLAY")
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", 1 + col * 4, -1 - r * 4)
            d:SetColorTexture(1, 1, 1, 0.9)
        end
    end
    b.grip:Hide()
    b:SetScript("OnEnter", function(self)
        local i = self.data
        if not i then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if i.spell then GameTooltip:SetSpellByID(i.spell)
        elseif i.item then GameTooltip:SetItemByID(i.item)
        else GameTooltip:SetText(i.tip or "?") end
        if self.key then GameTooltip:AddLine(MMT.FullDisplay(self.key), ClassColor(self.key)) end
        if i.tip and (i.spell or i.item) then GameTooltip:AddLine(i.tip, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) IconDragStart(self) end)
    b:SetScript("OnDragStop", function(self) IconDragStop(self) end)
    return b
end

-- remaining seconds of a timed icon, or nil
local function Remaining(i)
    if i.start and i.duration and i.duration > 0 then
        local r = i.start + i.duration - GetTime()
        if r > 0 then return r end
    end
end

local drag   -- { src = drag table, row, key, window } while an icon is dragged

-- alpha, glow and timer text of one icon (called on every tick)
local function Paint(b, c)
    local i = b.data
    local state, rem = i.state, Remaining(i)
    if state == "buff" and i.after and not rem then
        -- the buff ran out: show what comes after it (the cooldown)
        local a = i.after
        i.state, i.start, i.duration, i.glow, i.after = a.state, a.start, a.duration, nil, nil
        if i.state == "cd" and Remaining(i) then b.cd:SetCooldown(i.start, i.duration); b.cd:Show() else b.cd:Hide() end
        return Paint(b, c)
    end
    if state == "cd" and not rem then state = "ready" end
    local alpha, glow = 1, false
    if state == "ready" then alpha = c.readyAlpha or 1
    elseif state == "cd" then alpha = c.cdAlpha or 1
    elseif state == "missing" then
        -- extras from another module bring their own look for "missing"
        alpha = i.missingAlpha or c.missingAlpha or 0.3
        if i.glowMissing ~= nil then glow = i.glowMissing else glow = c.glowMissing end
    elseif state == "buff" then alpha = i.activeAlpha or c.activeAlpha or 1
    elseif state == "active" then glow = c.glowActive end
    if i.glow then glow = true end
    if drag and i.drag and i.drag.id == drag.src.id and b:GetParent() == drag.row then alpha = alpha * 0.4 end
    b:SetAlpha(alpha)
    if glow then
        if not b.glow:IsShown() then b.glow:Show(); b.pulse:Play() end
    elseif b.glow:IsShown() then
        b.pulse:Stop(); b.glow:Hide()
    end
    if c.showTimers and rem and (state == "cd" or state == "buff") then
        b.timer:SetText(FormatTime(rem))
        local tc = c.timerColor
        if tc then b.timer:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1) end
        b.timer:Show()
    else
        b.timer:Hide()
    end
end

local function Setup(b, i, key, c)
    b.data, b.key = i, key
    b.tex:SetTexture(i.texture or 134400)
    local t = i.tint
    b.tex:SetVertexColor(t and t[1] or 1, t and t[2] or 1, t and t[3] or 1)
    if b.tex.SetDesaturated then b.tex:SetDesaturated(i.desaturate and true or false) end
    local z = math.max(0, math.min(40, tonumber(c.iconZoom) or 8)) / 100
    b.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    local size = c.iconSize or 28
    b:SetSize(size, size)
    b.glow:SetSize(size * 1.8, size * 1.8)
    b.glow:SetVertexColor(i.state == "missing" and 1 or 0.3, i.state == "missing" and 0.2 or 0.9, i.state == "missing" and 0.2 or 1)
    MMT.ApplyFont(b.timer, c.font, c.timerSize or 13, "OUTLINE")
    MMT.ApplyFont(b.count, c.font, math.max(8, math.floor((c.timerSize or 13) * 0.8)), "OUTLINE")
    b.count:SetText((i.count and i.count > 1) and i.count or "")
    if i.tally then
        local pos = i.tallyPos or "BOTTOMLEFT"
        b.tally:ClearAllPoints()
        b.tally:SetPoint(pos, pos:find("LEFT") and 1 or -1, pos:find("TOP") and -1 or 1)
        MMT.ApplyFont(b.tally, c.font, i.tallySize or 12, "OUTLINE")
        local tc = i.tallyColor
        b.tally:SetTextColor(tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1)
        b.tally:SetText(i.tally)
        b.tally:Show()
    else
        b.tally:SetText("")
        b.tally:Hide()
    end
    if (i.state == "cd" or i.state == "buff") and Remaining(i) then
        b.cd:SetCooldown(i.start, i.duration)
        b.cd:Show()
    else
        b.cd:Hide()
    end
    b:EnableMouse(not c.clickThrough or i.drag ~= nil)
    b.grip:SetShown(i.drag ~= nil)
    Paint(b, c)
    b:Show()
end

---------------------------------------------------------------------------
-- Dragging icons
---------------------------------------------------------------------------
local function InGroup(b, group) return b.data and b.data.drag and b.data.drag.group == group end

-- where the dragged icon would land: the group icon it goes next to, after (true) or before it
local function Target(d)
    local row = d.row
    local icons = {}
    for _, b in ipairs(row.icons) do if b:IsShown() and b.data then icons[#icons + 1] = b end end
    local scale = row:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    -- gap = how many icons lie before the cursor
    local gap = 0
    for k, b in ipairs(icons) do
        local l, r, t, bt = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
        if l and r and t and bt then
            if row.vertical then
                if cy < (t + bt) / 2 then gap = k end
            elseif cx > (l + r) / 2 then gap = k end
        end
    end
    -- only between icons of its group: past them = the group's nearest end
    local group, first, last = d.src.group
    for k, b in ipairs(icons) do
        if InGroup(b, group) then first = first or k; last = k end
    end
    if not first then return end
    gap = math.max(first - 1, math.min(last, gap))
    if gap >= last then return icons[last], true end
    for k = gap + 1, last do
        if InGroup(icons[k], group) then return icons[k], false end
    end
end

-- dropping there leaves it where it is
local function NoMove(d, dst, after)
    if dst.data.drag.id == d.src.id then return true end
    local icons = {}
    for _, b in ipairs(d.row.icons) do if b:IsShown() and InGroup(b, d.src.group) then icons[#icons + 1] = b end end
    for k, b in ipairs(icons) do
        if b == dst then
            local nb = icons[after and k + 1 or k - 1]
            return nb and nb.data.drag.id == d.src.id
        end
    end
end

local driver = CreateFrame("Frame")
driver:Hide()

local function DropLine(row)
    if row.drop then return row.drop end
    local l = CreateFrame("Frame", nil, row)
    l:SetFrameLevel(row:GetFrameLevel() + 20)
    l.tex = l:CreateTexture(nil, "OVERLAY")
    l.tex:SetAllPoints()
    l.tex:SetColorTexture(1, 0.82, 0, 1)
    l:Hide()
    row.drop = l
    return l
end

local function ShowLine(d)
    local line = DropLine(d.row)
    local dst, after = Target(d)
    if not dst or NoMove(d, dst, after) then line:Hide() return end
    local c = d.window.def.cfg()
    local size, half = d.row.iconSize or c.iconSize or 28, (c.spacing or 2) / 2
    line:ClearAllPoints()
    if d.row.vertical then
        line:SetSize(size, 2)
        line:SetPoint("CENTER", dst, after and "BOTTOM" or "TOP", 0, after and -half or half)
    else
        line:SetSize(2, size)
        line:SetPoint("CENTER", dst, after and "RIGHT" or "LEFT", after and half or -half, 0)
    end
    line:Show()
end

local function Repaint(w)
    local c = w.def.cfg()
    if not c then return end
    for _, row in ipairs(w.rows) do
        for _, b in ipairs(row.icons) do if b:IsShown() and b.data then Paint(b, c) end end
    end
    for _, row in ipairs(w.frows or {}) do
        if row:IsShown() and row.fc then
            for _, b in ipairs(row.icons) do if b:IsShown() and b.data then Paint(b, row.fc) end end
        end
    end
end

local function FinishDrag()
    local d = drag
    if not d then return end
    drag = nil
    driver:Hide()
    if d.row.drop then d.row.drop:Hide() end
    Repaint(d.window)
    -- the row shows someone else now (team changed while dragging): nothing to drop on
    if d.row.key ~= d.key or not d.row:IsShown() then return end
    local dst, after = Target(d)
    if dst and not NoMove(d, dst, after) then d.src.move(d.src, dst.data.drag, after) end
end

driver:SetScript("OnUpdate", function()
    if not drag then driver:Hide() return end
    -- the button came up somewhere OnDragStop didn't see
    if not IsMouseButtonDown("LeftButton") then FinishDrag() return end
    ShowLine(drag)
end)

function IconDragStart(b)
    local row = b:GetParent()
    local w = row.window
    local c = w.def.cfg()
    if b.data and b.data.drag and c and not drag then
        GameTooltip:Hide()
        drag = { src = b.data.drag, row = row, key = row.key, window = w }
        Repaint(w)
        driver:Show()
        return
    end
    if row.framed then return end   -- beside a unit frame: nothing to move
    w.frame:GetScript("OnDragStart")(w.frame)   -- like the background: moves the window
end

function IconDragStop(b)
    if drag then FinishDrag() return end
    local row = b:GetParent()
    if row.framed then return end
    local f = row.window.frame
    f:GetScript("OnDragStop")(f)
end
function lib.IsDragging() return drag ~= nil end

---------------------------------------------------------------------------
-- Party / raid frames (v14)
---------------------------------------------------------------------------
-- (global look-ups with rawget: a missing global stays missing)
local function G(name) return rawget(_G, name) end

local function Children(hdr, out)
    if type(hdr) ~= "table" then return end
    for i = 1, 40 do
        local b = rawget(hdr, i)
        if not b and hdr.GetAttribute then b = hdr:GetAttribute("child" .. i) end
        if type(b) ~= "table" then break end
        out[#out + 1] = b
    end
end

local function Named(out, name) local f = G(name); if type(f) == "table" then out[#out + 1] = f end end

-- unit frame addons, in this order: a unit's first shown frame wins
local PROVIDERS = {
    { name = "EllesmereUI", frames = function(out)
        -- EllesmereUIRaidFrames: party header (+ the static self button of "Show Self First"),
        -- raid: one header per group or one flat header (Merge Groups); EUI_NameSort only re-sorts them
        Named(out, "ERFPartySelfButton")
        Children(G("ERFPartyHeader"), out)
        Children(G("ERFFlatHeader"), out)
        for g = 1, 8 do Children(G("ERFGroupHeader" .. g), out) end
    end },
    { name = "Blizzard raid frames", frames = function(out)
        for i = 1, 5 do Named(out, "CompactPartyFrameMember" .. i) end
        for i = 1, 40 do Named(out, "CompactRaidFrame" .. i) end
        for g = 1, 8 do for i = 1, 5 do Named(out, "CompactRaidGroup" .. g .. "Member" .. i) end end
    end },
    { name = "Blizzard party frames", frames = function(out)
        local pf = G("PartyFrame")
        for i = 1, 4 do
            local f = type(pf) == "table" and rawget(pf, "MemberFrame" .. i) or nil
            if f then out[#out + 1] = f else Named(out, "PartyMemberFrame" .. i) end
        end
        Named(out, "PlayerFrame")
    end },
}
lib.PROVIDERS = PROVIDERS

local unitKeys = {}   -- [unit] = team key (until the roster changes)

local function KeyOf(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local k = unitKeys[unit]
    if k then return k end
    local ok, real = pcall(function() return UnitExists(unit) and true or false end)
    if not ok or not real then return nil end
    local _, _, key = MMT.SplitUnit(unit)
    if type(key) ~= "string" or (MMT.IsSecret and MMT.IsSecret(key)) or key == UNKNOWNOBJECT then return nil end
    if MMT.Resolve then key = MMT.Resolve(key) or key end
    unitKeys[unit] = key
    return key
end

local function UnitOfFrame(f)
    local u = f.GetAttribute and f:GetAttribute("unit")
    if type(u) ~= "string" then u = rawget(f, "unit") or rawget(f, "displayedUnit") end
    return u
end

-- every shown unit frame with a player: [team key] = frame, the top one (highest, then leftmost),
-- and how many each addon gave ([provider name] = n)
function lib.UnitFrames()
    local byKey, count, top, topY, topX = {}, {}, nil, nil, nil
    for _, p in ipairs(PROVIDERS) do
        local list = {}
        pcall(p.frames, list)
        for _, f in ipairs(list) do
            local ok, shown = pcall(f.IsVisible, f)
            local key = ok and shown and KeyOf(UnitOfFrame(f))
            if key and not byKey[key] then
                byKey[key] = f
                count[p.name] = (count[p.name] or 0) + 1
                local s = f:GetEffectiveScale()
                local l, t = f:GetLeft(), f:GetTop()
                if l and t then
                    l, t = l * s, t * s
                    if not top or t > topY + 0.5 or (math.abs(t - topY) <= 0.5 and l < topX) then top, topY, topX = f, t, l end
                end
            end
        end
    end
    return byKey, top, count
end

local GAP = 2
local SIDES = { RIGHT = true, LEFT = true, TOP = true, BOTTOM = true }

-- puts a row beside a unit frame, `before` px further out (rows nearer the frame); returns the room it takes
local function Place(row, uf, side, before, x, y)
    local ok, l, b, w, h = pcall(uf.GetRect, uf)
    if not ok or not (l and b and w and h) then return 0 end
    local k = uf:GetEffectiveScale() / row:GetEffectiveScale()
    l, b, w, h = l * k, b * k, w * k, h * k
    local rw, rh = row.fw or 0, row.fh or 0
    local px, py
    if side == "LEFT" then px, py = l - GAP - before - rw, b + (h - rh) / 2
    elseif side == "TOP" then px, py = l, b + h + GAP + before
    elseif side == "BOTTOM" then px, py = l, b - GAP - before - rh
    else px, py = l + w + GAP + before, b + (h - rh) / 2 end
    px, py = math.floor(px + x + 0.5), math.floor(py + y + 0.5)
    if row.px ~= px or row.py ~= py then
        row.px, row.py = px, py
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", px, py)
    end
    return ((side == "LEFT" or side == "RIGHT") and rw or rh) + GAP
end

-- every window's frame rows to their places
function lib.PlaceFramed()
    local list = {}
    for _, w in pairs(lib.windows) do if w.frows then list[#list + 1] = w end end
    table.sort(list, function(a, b)
        local x, y = a.def.frameOrder or 9, b.def.frameOrder or 9
        if x ~= y then return x < y end
        return a.def.name < b.def.name
    end)
    local taken = {}   -- [unit frame] = { [side] = room used by rows nearer the frame }
    for pass = 1, 2 do   -- member rows first; label rows (an All bar) above whatever sits on top
        for _, w in ipairs(list) do
            local c = w.def.cfg()
            for _, row in ipairs(w.frows) do
                if c and row.unitFrame and row:IsShown() and ((pass == 2) == (row.label == true)) then
                    local side = row.label and "TOP" or (SIDES[c.framesSide] and c.framesSide or "RIGHT")
                    local x = tonumber(row.label and c.allX or c.framesX) or 0
                    local y = tonumber(row.label and c.allY or c.framesY) or 0
                    local t = taken[row.unitFrame] or {}
                    taken[row.unitFrame] = t
                    t[side] = (t[side] or 0) + Place(row, row.unitFrame, side, t[side] or 0, x, y)
                end
            end
        end
    end
end

-- frame rows tick here (the window itself may be hidden: everyone is on a frame)
local fdrive = CreateFrame("Frame")
fdrive:Hide()
local builtFor   -- frames + units the frame rows were last built for

function lib.CheckFrames()
    local any = false
    for _, w in pairs(lib.windows) do if w.onFrames then any = true end end
    if not any then fdrive:Hide() return end
    local byKey, top = lib.UnitFrames()
    local parts = {}
    for k, f in pairs(byKey) do parts[#parts + 1] = k .. "=" .. tostring(f) end
    table.sort(parts)
    local sig = table.concat(parts, ",") .. "|" .. tostring(top)
    if sig ~= builtFor and not drag then   -- (while an icon is dragged: after it)
        builtFor = sig
        for _, w in pairs(lib.windows) do if w.onFrames then w:Refresh() end end
        return
    end
    lib.PlaceFramed()
end

do
    local paintT, pollT = 0, 0
    fdrive:SetScript("OnUpdate", function(_, e)
        paintT, pollT = paintT + (e or 0.1), pollT + (e or 0.1)
        if paintT >= 0.1 then
            paintT = 0
            for _, w in pairs(lib.windows) do
                for _, row in ipairs(w.frows or {}) do
                    if row:IsShown() and row.fc then
                        for _, b in ipairs(row.icons) do if b:IsShown() and b.data then Paint(b, row.fc) end end
                    end
                end
            end
        end
        if pollT >= 0.25 then
            pollT = 0
            lib.CheckFrames()
        end
    end)
end

-- the roster changed: units may belong to someone else now
local roster = CreateFrame("Frame")
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE" }) do pcall(roster.RegisterEvent, roster, ev) end
roster:SetScript("OnEvent", function() unitKeys = {}; builtFor = nil end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function lib.NewWindow(def)
    local w = setmetatable({ def = def, rows = {}, frows = {} }, Window)
    local f = CreateFrame("Frame", def.name, UIParent, BACKDROP)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f:SetScript("OnDragStart", function(self) if not def.cfg().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local c = def.cfg()
        local p = lib.PointAt(self, ANCHOR[lib.Growth(c)])
        if not p then
            local point, _, relPoint, x, y = self:GetPoint()
            p = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
        end
        c.point = p
        w.placed = p
    end)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" and def.config then def.config() end end)
    f:Hide()
    w.frame = f
    -- timers and expiry
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        local c = def.cfg()
        if not c then return end
        for _, row in ipairs(w.rows) do
            for _, b in ipairs(row.icons) do if b:IsShown() and b.data then Paint(b, c) end end
        end
    end)
    lib.windows[def.name] = w
    return w
end

function Window:Row(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, self.frame, BACKDROP)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.icons = {}
    row.window, row.framed = self, false
    row:RegisterForDrag("LeftButton")
    local f = self.frame
    row:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
    row:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    row:SetScript("OnMouseUp", function(_, button) f:GetScript("OnMouseUp")(f, button) end)
    self.rows[i] = row
    return row
end

-- icons of a row including the other modules' extras
local function WithExtras(name, key, icons)
    local ex = lib.extras[name]
    if not ex then return icons end
    local left, right = {}, {}
    for _, e in pairs(ex) do
        local ok, list = pcall(e.fn, key)
        if ok and type(list) == "table" then
            for _, i in ipairs(list) do
                if e.side == "LEFT" then left[#left + 1] = i else right[#right + 1] = i end
            end
        end
    end
    if #left == 0 and #right == 0 then return icons end
    local all = {}
    for _, i in ipairs(left) do all[#all + 1] = i end
    for _, i in ipairs(icons) do all[#all + 1] = i end
    for _, i in ipairs(right) do all[#all + 1] = i end
    return all
end

-- a row beside a unit frame (on UIParent, placed by lib.PlaceFramed)
function Window:FrameRow(i)
    local row = self.frows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("MEDIUM")
    row.icons, row.window, row.framed = {}, self, true
    row:Hide()
    self.frows[i] = row
    return row
end

-- list = { { row = a rows() entry, frame = its unit frame }, ... }; c nil = hide them all
function Window:LayoutFramed(list, c)
    self.frows = self.frows or {}
    local used = 0
    if c and #list > 0 then
        local size = tonumber(c.framesIconSize) or 0
        if size <= 0 then size = c.iconSize or 28 end
        local gap = c.spacing or 2
        local fc = setmetatable({ iconSize = size }, { __index = c })
        for _, it in ipairs(list) do
            local r = it.row
            local icons = r.key and WithExtras(self.def.name, r.key, r.icons or {}) or (r.icons or {})
            if #icons > 0 then
                used = used + 1
                local row = self:FrameRow(used)
                row.key, row.vertical, row.unitFrame, row.label = r.key or r.label, false, it.frame, r.key == nil
                row.fc, row.iconSize = fc, size
                for j, data in ipairs(icons) do
                    local b = row.icons[j] or NewIcon(row)
                    row.icons[j] = b
                    Setup(b, data, r.key, fc)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", (j - 1) * (size + gap), 0)
                end
                for j = #icons + 1, #row.icons do row.icons[j]:Hide(); row.icons[j].data = nil end
                row.fw, row.fh = #icons * size + (#icons - 1) * gap, size
                row:SetSize(row.fw, row.fh)
                row:EnableMouse(false)
                row:Show()
            end
        end
    end
    for i = used + 1, #self.frows do
        local row = self.frows[i]
        row:Hide()
        row.unitFrame = nil
    end
    lib.PlaceFramed()
end

function Window:Refresh()
    local def, f = self.def, self.frame
    local c = def.cfg()
    if not c or not c.shown or (def.active and not def.active()) then
        f:Hide()
        self.onFrames = false
        self:LayoutFramed({})
        return
    end
    local ok, rows = pcall(def.rows)
    if not ok then rows = {} end
    -- members with a party / raid frame get their row beside it (v14); the others stay here
    local framed = {}
    self.onFrames = (c.onFrames or c.allOnFrames) and true or false
    if self.onFrames then
        local byKey, top = lib.UnitFrames()
        local keep = {}
        for _, r in ipairs(rows) do
            local uf
            if r.key then uf = c.onFrames and byKey[r.key] or nil else uf = c.allOnFrames and top or nil end
            if uf then framed[#framed + 1] = { row = r, frame = uf }
            elseif not (r.key and c.onFrames and c.framesOthers == "HIDE") then keep[#keep + 1] = r end
        end
        rows = keep
        fdrive:Show()
    end
    self:LayoutFramed(framed, c)
    local size, gap = c.iconSize or 28, c.spacing or 2
    local growth = lib.Growth(c)
    local rowGap, vertical = c.rowGap or 4, (growth == "RIGHT" or growth == "LEFT")
    -- down > top / right > left: the same layout, members in reverse order
    if growth == "UP" or growth == "LEFT" then
        local rev = {}
        for i = #rows, 1, -1 do rev[#rev + 1] = rows[i] end
        rows = rev
    end
    local nameH = c.showNames and ((c.nameSize or 11) + 3) or 0
    -- frame background / border first: the border decides the padding
    local PAD = 4 + Skin(f, c.bgTexture, c.bgColor, c.bgAlpha or 0.4, c.borderTexture, c.borderColor, c.borderSize, c.bgTint)

    -- name column width (horizontal layout: names left of the icons)
    local nameW = 0
    local used = 0
    for i, r in ipairs(rows) do
        local row = self:Row(i)
        MMT.ApplyFont(row.name, c.font, c.nameSize or 11, "OUTLINE")
        Skin(row, c.bgTexture, c.rowColor, c.rowAlpha or 0, nil, nil, nil, c.bgTint)
        row.name:SetText(r.label or lib.MemberName(r.key, c.fullNames))
        if r.color then row.name:SetTextColor(r.color[1], r.color[2], r.color[3])
        else row.name:SetTextColor(ClassColor(r.key)) end
        if c.showNames and not vertical then nameW = math.max(nameW, row.name:GetStringWidth() + 6) end
    end

    local x, y, maxW, maxH = PAD, -PAD, 0, 0
    for i, r in ipairs(rows) do
        local row = self:Row(i)
        row.key, row.vertical, row.iconSize = r.key or r.label, vertical, size
        local icons = r.key and WithExtras(def.name, r.key, r.icons or {}) or (r.icons or {})
        -- vertical: a column as wide as the name, icons centred in it
        local colW = vertical and math.max(size, c.showNames and (row.name:GetStringWidth() + 2) or 0) or 0
        local colX = vertical and math.floor((colW - size) / 2 + 0.5) or 0
        for j, data in ipairs(icons) do
            local b = row.icons[j] or NewIcon(row)
            row.icons[j] = b
            Setup(b, data, r.key, c)
            b:ClearAllPoints()
            if vertical then
                b:SetPoint("TOPLEFT", colX, -nameH - (j - 1) * (size + gap))
            else
                b:SetPoint("TOPLEFT", nameW + (j - 1) * (size + gap), 0)
            end
        end
        for j = #icons + 1, #row.icons do row.icons[j]:Hide(); row.icons[j].data = nil end
        local n = math.max(1, #icons)
        local w, h
        row.name:ClearAllPoints()
        if vertical then
            w = colW
            h = nameH + n * size + (n - 1) * gap
            row.name:SetPoint("TOP", 0, 0)
        else
            w = nameW + n * size + (n - 1) * gap
            h = size
            row.name:SetPoint("LEFT", 0, 0)
        end
        row.name:SetShown(c.showNames and true or false)
        row:SetSize(w, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", x, y)
        row:EnableMouse(not c.clickThrough)
        row:Show()
        if vertical then
            x = x + w + rowGap
            maxH = math.max(maxH, h)
        else
            y = y - h - rowGap
            maxW = math.max(maxW, w)
        end
        used = i
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end

    if used == 0 then f:Hide() return end
    -- the growth direction changed: keep the window where it is, pinned at the new edge
    local anchor = ANCHOR[growth]
    local p = c.point
    if p and p[1] ~= anchor and f:IsShown() then
        local np = lib.PointAt(f, anchor)
        if np then c.point = np end
    end
    if vertical then f:SetSize(x - rowGap + PAD, maxH + 2 * PAD)
    else f:SetSize(maxW + 2 * PAD, -y - rowGap + PAD) end
    f:SetScale(c.scale or 1)
    f:EnableMouse(not c.clickThrough)
    -- position only when it changed (profile switch, reset, direction), never while dragging
    p = c.point
    if p and p ~= self.placed then
        self.placed = p
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    f:Show()
end

function Window:Hide()
    self.frame:Hide()
    self.onFrames = false
    self:LayoutFramed({})
end

function lib.SetExtra(windowName, id, fn, side)
    lib.extras[windowName] = lib.extras[windowName] or {}
    lib.extras[windowName][id] = fn and { fn = fn, side = side or "RIGHT" } or nil
    local w = lib.windows[windowName]
    if w then w:Refresh() end
end

function lib.Refresh(windowName)
    local w = lib.windows[windowName]
    if w then w:Refresh() end
end
