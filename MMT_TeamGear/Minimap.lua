-- MMT Team Gear: the minimap button (left-click: pick a member, right-click:
-- the whole team, drag: move it around the minimap) and the key binding for
-- the whole-team window (Bindings.xml, texts here).

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI

BINDING_HEADER_MMT_TEAMGEAR = "Team Gear"
BINDING_NAME_MMTTEAMGEAR_ALL = "Whole team's gear"

-- key binding: the whole-team window, open / closed
function MMTTeamGear_ToggleOverview()
    if not M.enabled then MMT.Print("Team Gear is switched off (/mmt modules).") return end
    if mod.overview and mod.overview:IsShown() then mod.overview:Hide() return end
    mod.OpenOverview()
end

local function Place(b)
    local a = math.rad(tonumber(M.db.minimapAngle) or 220)
    local r = (Minimap:GetWidth() / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function Build()
    local b = CreateFrame("Button", "MMTTeamGearMinimapButton", Minimap)
    b:SetSize(28, 28)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then MMTTeamGear_ToggleOverview() else mod.OpenMemberList(self) end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            M.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Place(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    UI.Tooltip(b, "Team Gear", "Left-click: pick a team member. Right-click: the whole team. Drag: move this button.")
    return b
end

function mod.SetupMinimap()
    if not Minimap then return end
    if not (M.enabled and M.db.minimap) then
        if mod.minimap then mod.minimap:Hide() end
        return
    end
    mod.minimap = mod.minimap or Build()
    Place(mod.minimap)
    mod.minimap:Show()
end
