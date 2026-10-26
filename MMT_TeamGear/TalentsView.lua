-- MMT Team Gear: the Talents view of the gear window: the three trees side by
-- side, each talent on its grid place with its rank, like the talent frame.
-- Talents with points are lit (gold when full), the others grey. Hover for the
-- spell's tooltip. The data comes from Talents.lua.

local _, mod = ...
local MMT = MMT
local UI = MMT.UI

local PAD, TOP, HEAD = 12, 58, 20
local MAX_STEP = 44

local function NewTalent(parent)
    local b = CreateFrame("Button", nil, parent)
    UI.Fill(b, 0.1, 0.1, 0.1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.rank:SetPoint("BOTTOMRIGHT", 2, -2)
    b:SetScript("OnEnter", function(self)
        local t = self.talent
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (t.spell and t.spell > 0 and pcall(GameTooltip.SetSpellByID, GameTooltip, t.spell)) then
            GameTooltip:SetText(t.name or "Talent")
        end
        GameTooltip:AddLine(("Rank %d/%d"):format(t.rank, t.max), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", PAD, -TOP)
    p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    p.buttons = {}
    p.heads = {}
    for i = 1, 3 do
        local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetJustifyH("CENTER")
        p.heads[i] = h
    end
    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.note:SetPoint("CENTER")
    p.note:SetWidth(360)
    p:Hide()
    return p
end

local function Paint(b, t, size)
    b.talent = t
    b:SetSize(size, size)
    local tex = t.icon and t.icon > 0 and t.icon
        or (t.spell and t.spell > 0 and C_Spell and C_Spell.GetSpellTexture and MMT.Safe(C_Spell.GetSpellTexture, t.spell))
        or 134400
    b.icon:SetTexture(tex)
    local on = t.rank > 0
    b.icon:SetDesaturated(not on)
    b.icon:SetAlpha(on and 1 or 0.45)
    b.rank:SetText(on and (t.rank .. "/" .. t.max) or "")
    if t.rank >= t.max then b.rank:SetTextColor(1, 0.82, 0) else b.rank:SetTextColor(0.1, 1, 0.1) end
    b:Show()
end

-- draws key's talents into the window's talent panel
function mod.PaintTalents(f, key)
    mod.talentPanel = mod.talentPanel or Build(f)
    local p = mod.talentPanel
    p:Show()
    for _, b in ipairs(p.buttons) do b:Hide(); b.talent = nil end
    local data = mod.TalentsOf(key)
    if not data then
        for _, h in ipairs(p.heads) do h:SetText("") end
        p.note:SetText("No talents known yet. They arrive when this character is online with Team Gear on.")
        return
    end
    p.note:SetText("")
    local class = mod.ClassOf(key)
    local points = mod.TreePoints(data)
    local cols, rows = 1, 1
    for _, t in ipairs(data.talents) do
        cols = math.max(cols, t.col + 1)
        rows = math.max(rows, t.row + 1)
    end
    local w, h = mod.WINDOW_W - 2 * PAD, mod.WINDOW_H - TOP - PAD   -- the window has a fixed size
    local colW = w / 3
    local step = math.floor(math.min(MAX_STEP, (colW - 8) / cols, (h - HEAD - 4) / rows))
    local size = step - 6
    for i = 1, 3 do
        local head = p.heads[i]
        head:ClearAllPoints()
        head:SetPoint("TOP", p, "TOPLEFT", colW * (i - 0.5), 0)
        head:SetText(("%s  |cffffffff%d|r"):format(mod.TreeName(data, class, i), points[i]))
    end
    for n, t in ipairs(data.talents) do
        local b = p.buttons[n] or NewTalent(p)
        p.buttons[n] = b
        local left = colW * (t.tree - 1) + (colW - cols * step) / 2 + 3
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p, "TOPLEFT", left + t.col * step, -(HEAD + 4 + t.row * step))
        Paint(b, t, size)
    end
end

function mod.HideTalents(f)
    if mod.talentPanel then mod.talentPanel:Hide() end
end
