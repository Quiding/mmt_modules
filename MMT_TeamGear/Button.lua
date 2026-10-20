-- MMT Team Gear: a button on the character panel. Click: the team list,
-- pick a member to see their gear. Shift-drag moves the button (kept per
-- profile), right-click opens the settings.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

local SIZE = 24

-- the team as a list for MMT.UI.OpenList: class-coloured names, grey when no gear is stored
-- with "Other teams" on: "Team 1 (this team)", its members indented, "Team 2 (<profile>)", ...
function mod.MemberItems()
    local items = { { value = "__ALL__", text = "|cffffd100Whole team|r" } }
    local groups = mod.Groups()
    local grouped = M.db.others
    for _, grp in ipairs(groups) do
        if grouped and #grp.keys > 0 then
            items[#items + 1] = { header = true, text = grp.title .. (grp.note and ("  |cff999999(" .. grp.note .. ")|r") or "") }
        end
        for _, key in ipairs(grp.keys) do
            local class, level = mod.ClassOf(key)
            local r, g, b = mod.ClassColor(class)
            if not mod.Equipment(key) then r, g, b = r * 0.5, g * 0.5, b * 0.5 end
            local text = ("%s|cff%02x%02x%02x%s|r%s"):format(grouped and "|cff666666-|r " or "", r * 255, g * 255, b * 255, MMT.FullDisplay(key),
                level and ("  |cff999999" .. level .. "|r") or "")
            items[#items + 1] = { value = key, text = text }
        end
    end
    if #items == 1 then items[2] = { header = true, text = "No team members yet" } end
    return items
end

function mod.OpenMemberList(owner)
    UI.OpenList(owner, mod.MemberItems(), mod.window and mod.window:IsShown() and mod.window.key or nil,
        function(key) if key == "__ALL__" then mod.OpenOverview() else mod.Open(key) end end)
end

local function Place(b)
    b:ClearAllPoints()
    local p = M.db.buttonPoint
    if type(p) == "table" and p[1] then b:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", p[1], p[2])
    else b:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 44, -5) end
end

local function Build()
    local b = CreateFrame("Button", "MMTTeamGearButton", CharacterFrame)
    b:SetSize(SIZE, SIZE)
    b:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Border(b, 0.3, 0.3, 0.3, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x = self:GetLeft() - CharacterFrame:GetLeft()
        local y = self:GetTop() - CharacterFrame:GetTop()
        M.db.buttonPoint = { math.floor(x + 0.5), math.floor(y + 0.5) }
        Place(self)
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then MMT.ToggleConfig("TeamGear") return end
        mod.OpenMemberList(self)
    end)
    UI.Tooltip(b, "Team Gear", "Click: see a team member's gear, or the whole team at once. Shift-drag: move this button. Right-click: settings.")
    return b
end

-- creates / shows / hides the button for the current settings
function mod.SetupButton()
    if not CharacterFrame then return end
    if not M.db.button then
        if mod.button then mod.button:Hide() end
        return
    end
    mod.button = mod.button or Build()
    Place(mod.button)
    mod.button:Show()
end

function mod.ResetButton()
    M.db.buttonPoint = nil
    if mod.button then Place(mod.button) end
end

-- the character panel can load after us
M:On("ADDON_LOADED", function()
    if not mod.button and CharacterFrame then mod.SetupButton() end
end)
