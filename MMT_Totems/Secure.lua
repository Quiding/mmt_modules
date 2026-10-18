-- MMT Totems: casting. Secure buttons can't be changed in combat, so every
-- change waits for the end of combat (PLAYER_REGEN_ENABLED).
--   * your slot buttons: left-click casts the totem of that slot (the chosen
--     one, else the active / last one),
--   * MMTTotemsSequenceButton: /castsequence of your totems in your element
--     order (spam-safe: reset=3 with a ", null" step at the end),
--   * the key: your own key from the settings page (override binding) and/or
--     Esc > Options > Keybindings > AddOns > "Totem sequence" (Bindings.xml).

local _, mod = ...
local MMT = MMT
local M = mod.M

-- own binding group: "MMT" is Item Compare's, declaring it twice gives a LUA_WARNING
BINDING_HEADER_MMTTOTEMS = "MMT - Totems"
_G["BINDING_NAME_CLICK MMTTotemsSequenceButton:LeftButton"] = "Totem sequence (MMT Totems)"

local seq = CreateFrame("Button", "MMTTotemsSequenceButton", UIParent, "SecureActionButtonTemplate")
seq:RegisterForClicks("AnyUp", "AnyDown")
seq.icon = seq:CreateTexture(nil, "ARTWORK")
seq.icon:SetAllPoints()
seq.icon:SetTexture(mod.PRESET_ICON)
seq.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local hl = seq:CreateTexture(nil, "HIGHLIGHT")
hl:SetAllPoints()
hl:SetColorTexture(1, 1, 1, 0.2)
seq:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Cast totem sequence")
    GameTooltip:AddLine(self.macroText or "No totems chosen yet.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
seq:SetScript("OnLeave", function() GameTooltip:Hide() end)
seq:Hide()
mod.sequenceButton = seq

local keyOwner = CreateFrame("Frame")
local pending = false

-- name of the totem a slot casts for a member
function mod.CastTotem(key, element)
    local id = mod.Selected(key, element)
    local name = id and mod.KnowsTotem(key, id) and mod.TotemName(id)   -- not learned yet: skip
    if name then return name end
    name = mod.ActiveTotem(key, element)
    if name and name ~= "Test" then return name end
    return (mod.LastTotem(key, element))
end

-- the /castsequence line for a member, or nil
function mod.SequenceMacro(key)
    local names = {}
    for _, element in ipairs(mod.ParseSequence(mod.Sequence(key))) do
        -- no totem item in the bags: the totem can't be dropped, it would stall the sequence
        local n = mod.HasTotemItem(key, element) and mod.CastTotem(key, element)
        if n then names[#names + 1] = n end
    end
    if #names == 0 then return nil end
    if M.db.spamSafe then
        return ("/castsequence reset=3 %s, null"):format(table.concat(names, ", "))
    end
    return ("/castsequence reset=10/combat %s"):format(table.concat(names, ", "))
end

function mod.UpdateSecure()
    if InCombatLockdown() then pending = true return end
    pending = false
    local c = M.db
    local key = mod.OwnKey()
    local bar = mod.bars[key]
    local passive = not (M.enabled and c) or c.onlyTimers

    if bar then
        for element, s in pairs(bar.slots) do
            local name = not passive and mod.CastTotem(key, element)
            s:SetAttribute("*type1", name and "macro" or nil)
            s:SetAttribute("*macrotext1", name and ("/cast " .. name) or nil)
        end
    end
    local macro = not passive and mod.SequenceMacro(key) or nil
    seq.macroText = macro
    seq:SetAttribute("type", macro and "macro" or nil)
    seq:SetAttribute("macrotext", macro)

    ClearOverrideBindings(keyOwner)
    if not passive and c.keybind and c.keybind ~= "" then
        SetOverrideBindingClick(keyOwner, false, c.keybind, "MMTTotemsSequenceButton", "LeftButton")
    end
end

M:On("PLAYER_REGEN_ENABLED", function() if pending then mod.UpdateSecure() end end)

-- key = "ALT-T" etc. or nil to remove; returns ok, message
function mod.SetKey(key)
    if InCombatLockdown() then return false, "Keys can't be changed in combat." end
    M.db.keybind = key or ""
    mod.UpdateSecure()
    return true
end
