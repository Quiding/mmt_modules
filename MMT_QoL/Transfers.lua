-- MMT Quality of life: progress bars for big transfers (Bulk.lua), sending and receiving.
--
-- A small window, one bar per transfer and member:
--   "To Anna Smith: Healer (12 / 40 KB)"   - the receiver whispers its progress back (QEUR P)
--   "From Bob Stone: Healer (30 / 40 KB)"  - from the parts that arrived
-- A receiver without this version says nothing until it imports: its bar follows
-- the time estimate (marked "~"). Finished bars go after a few seconds; the window
-- hides when none is left. Drag it anywhere; the place is kept (M.store.xferPos).
--
-- mod.Xfer(id, label, bytes, out) -> row (made or found)
-- mod.XferProgress(id, done)            bytes so far
-- mod.XferEstimate(id, seconds)         no word from the other side yet: time-based
-- mod.XferDone(id, text, ok)            finished (ok) / stopped (ok == false)

local _, mod = ...
local MMT = MMT
local M = mod.M

local W, BAR_H, GAP, KEEP = 260, 16, 3, 6
local rows, order = {}, {}
local frame

local function Save()
    local p = frame and { frame:GetPoint(1) }
    if p and p[1] then M.store.xferPos = { p[1], p[3], p[4], p[5] } end
end

local function Build()
    local f = CreateFrame("Frame", "MMTQoLTransfers", UIParent)
    f:SetSize(W + 12, 30)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Save() end)
    local pos = M.store and M.store.xferPos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    if MMT.UI and MMT.UI.Fill then MMT.UI.Fill(f, 0.05, 0.05, 0.06, 0.85) end
    if MMT.UI and MMT.UI.Border then MMT.UI.Border(f, 0.22, 0.24, 0.28, 1) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 6, -5)
    f.title:SetText("MMT transfers")
    f:Hide()
    f:SetScript("OnUpdate", function(self, el)
        self.acc = (self.acc or 0) + el
        if self.acc < 0.2 then return end
        self.acc = 0
        mod.XferTick()
    end)
    return f
end

local function Text(r)
    local kb = r.bytes and r.bytes > 0 and (" (%s / %s)"):format(mod.KB(math.floor(r.done or 0)), mod.KB(r.bytes)) or ""
    local state = r.text or (r.est and "~" or "")
    return ("%s%s%s"):format(r.label, kb, state ~= "" and ("  " .. state) or "")
end

local function Layout()
    if not frame then return end
    local y = -20
    for _, id in ipairs(order) do
        local r = rows[id]
        r.bar:ClearAllPoints()
        r.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, y)
        r.bar:Show()
        y = y - BAR_H - GAP
    end
    frame:SetHeight(-y + 4)
    frame:SetShown(#order > 0)
end

local function Paint(r)
    local frac = (r.bytes and r.bytes > 0) and math.min(1, (r.done or 0) / r.bytes) or 0
    if r.finished then frac = 1 end
    r.bar:SetValue(frac)
    r.bar.text:SetText(Text(r))
    if r.finished == false then r.bar:SetStatusBarColor(0.7, 0.25, 0.25)
    elseif r.finished then r.bar:SetStatusBarColor(0.25, 0.65, 0.3)
    elseif r.out then r.bar:SetStatusBarColor(0.2, 0.45, 0.8)
    else r.bar:SetStatusBarColor(0.75, 0.55, 0.15) end
end

local function NewBar()
    local b = CreateFrame("StatusBar", nil, frame)
    b:SetSize(W, BAR_H)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.14, 0.9)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    return b
end

local spare = {}

function mod.Xfer(id, label, bytes, out)
    local r = rows[id]
    if r then
        r.bytes = bytes or r.bytes
        return r
    end
    frame = frame or Build()
    r = { id = id, label = label, bytes = bytes, done = 0, out = out, start = GetTime() }
    r.bar = table.remove(spare) or NewBar()
    rows[id] = r
    order[#order + 1] = id
    Paint(r)
    Layout()
    return r
end

function mod.XferProgress(id, done)
    local r = rows[id]
    if not r or r.finished ~= nil then return end
    r.est = nil
    r.heard, r.last = true, GetTime()
    if done > (r.done or 0) then r.done = done end
    Paint(r)
end

-- no word from the other side: fill by the expected time, up to 95 %
function mod.XferEstimate(id, seconds)
    local r = rows[id]
    if r then r.estSecs, r.est = math.max(1, seconds or 1), true end
end

function mod.XferDone(id, text, ok)
    local r = rows[id]
    if not r then return end
    if r.finished ~= nil and ok ~= false then return end
    r.finished = ok ~= false
    if r.finished then r.done = r.bytes or r.done end
    r.est, r.text, r.gone = nil, text, GetTime() + KEEP
    Paint(r)
end

local function Remove(id)
    local r = rows[id]
    rows[id] = nil
    for i, x in ipairs(order) do if x == id then table.remove(order, i) break end end
    r.bar:Hide()
    spare[#spare + 1] = r.bar
    Layout()
end

function mod.XferTick()
    local now = GetTime()
    for _, id in ipairs({ unpack(order) }) do
        local r = rows[id]
        if r.gone and now >= r.gone then
            Remove(id)
        elseif r.est and not r.heard and r.finished == nil then
            -- (an older client doesn't say how far it is: "sent" once well past the estimate)
            if now - r.start > r.estSecs * 3 + 30 then mod.XferDone(id, "sent", true)
            else
                r.done = (r.bytes or 0) * math.min(0.95, (now - r.start) / r.estSecs)
                Paint(r)
            end
        elseif r.finished == nil and now - (r.last or r.start) > 600 then
            mod.XferDone(id, "no answer", false)
        end
    end
end

function mod.XferRows() return rows, order end
