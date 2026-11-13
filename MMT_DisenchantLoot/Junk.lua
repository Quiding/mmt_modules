-- MMT Disenchant Loot: items not worth disenchanting are junk on every character.
--
-- Junk = in the bags, not bound (soulbound quest rewards etc. never), counts by
-- quality and kind, has a disenchant value below the line (Module.lua
-- mod.Verdict) and is not an upgrade by Pawn (PawnIsItemAnUpgrade).
--   Baganator: junk plugin "Dejunk + Disenchant Loot" = Dejunk's junk plus these
--     (Baganator shows one junk plugin: pick it in Baganator's settings).
--   Vendor: sold when a merchant opens (sellOn), 10 at a time.
--   Tooltip: one line with both values and where the item goes (tipOn).

local _, mod = ...
local MMT = MMT
local M = mod.M

local function IsUpgrade(link)
    local getData, isUpgrade = rawget(_G, "PawnGetItemData"), rawget(_G, "PawnIsItemAnUpgrade")
    if type(getData) ~= "function" or type(isUpgrade) ~= "function" then return false end
    local ok, item = pcall(getData, link)
    if not ok or not item then return false end
    local ok2, up = pcall(isUpgrade, item)
    return ok2 and up and true or false
end
mod.IsUpgrade = IsUpgrade

-- is the bag item junk by our rule?
function mod.IsJunk(bag, slot)
    if not (M.enabled and M.db.junkOn) then return false end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isBound or info.hasNoValue or not info.hyperlink then return false end
    if mod.Verdict(info.hyperlink) ~= "JUNK" then return false end
    return not IsUpgrade(info.hyperlink)
end

---------------------------------------------------------------------------
-- Baganator
---------------------------------------------------------------------------
mod.PLUGIN_ID = "mmt_disenchant"

local function DejunkSays(bag, slot)
    local api = rawget(_G, "DejunkApi")
    if not (api and api.IsJunk) then return false end
    local ok, junk = pcall(api.IsJunk, api, bag, slot)
    return ok and junk and true or false
end

function mod.PluginJunk(bag, slot)
    if DejunkSays(bag, slot) then return true end
    local ok, junk = pcall(mod.IsJunk, bag, slot)
    return ok and junk or false
end

function mod.RefreshBags()
    local B = rawget(_G, "Baganator")
    if B and B.API and B.API.RequestItemButtonsRefresh then pcall(B.API.RequestItemButtonsRefresh) end
end

function mod.PluginActive()
    local B = rawget(_G, "Baganator")
    if not (B and B.API and B.API.IsJunkPluginActive) then return nil end
    local ok, on = pcall(B.API.IsJunkPluginActive, mod.PLUGIN_ID)
    return ok and on or false
end

local pluginDone = false
function mod.RegisterPlugin()
    if pluginDone then return true end
    local B = rawget(_G, "Baganator")
    if not (B and B.API and B.API.RegisterJunkPlugin) then return false end
    B.API.RegisterJunkPlugin("Dejunk + Disenchant Loot", mod.PLUGIN_ID, function(bag, slot) return mod.PluginJunk(bag, slot) end)
    local api = rawget(_G, "DejunkApi")
    if api and api.AddListener and api.Events then
        api:AddListener(function(event) if event ~= api.Events.BagsUpdated then mod.RefreshBags() end end)
    end
    pluginDone = true
    return true
end
mod.RegisterPlugin()

---------------------------------------------------------------------------
-- Selling at a vendor
---------------------------------------------------------------------------
local BATCH, INTERVAL = 10, 0.3
local merchantOpen = false
mod.lastSale = nil   -- { count, value, time } for the report

local function JunkSlots()
    local list = {}
    for bag = 0, (MMT.BAGS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked and mod.IsJunk(bag, slot) then
                local sell = select(11, (MMT.ItemInfo or GetItemInfo)(info.hyperlink)) or 0
                list[#list + 1] = { bag = bag, slot = slot, link = info.hyperlink, value = sell * (info.stackCount or 1) }
            end
        end
    end
    return list
end
mod.JunkSlots = JunkSlots

local function SellRun(total)
    if not (merchantOpen and M.enabled and M.db.sellOn and M.db.junkOn) then return end
    local list = JunkSlots()
    if #list == 0 then
        if total.count > 0 then
            MMT.Print("Disenchant Loot: sold %d %s for %s.", total.count, total.count == 1 and "item" or "items", mod.Money(total.value))
            mod.lastSale = { count = total.count, value = total.value, time = GetTime() }
        end
        return
    end
    for i = 1, math.min(BATCH, #list) do
        local it = list[i]
        local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        if info and info.hyperlink == it.link then
            C_Container.UseContainerItem(it.bag, it.slot)
            total.count, total.value = total.count + 1, total.value + it.value
            M:Debug("sold %s (%s)", it.link, mod.Money(it.value))
        end
    end
    total.rounds = total.rounds + 1
    if total.rounds < 20 then C_Timer.After(INTERVAL, function() SellRun(total) end) end
end

M:On("MERCHANT_SHOW", function()
    merchantOpen = true
    if M.db.sellOn and M.db.junkOn then
        C_Timer.After(0.6, function() SellRun({ count = 0, value = 0, rounds = 0 }) end)
    end
end)
M:On("MERCHANT_CLOSED", function() merchantOpen = false end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function TipLine(tt)
    if not (M.enabled and (M.db.tipOn or M.db.tipMats)) or not tt or not tt.GetItem then return end
    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok or type(link) ~= "string" then return end
    local verdict, de, sell = mod.Verdict(link)
    local shown = verdict and M.db.tipOn
    if shown then
        local where = verdict == "DE" and ("|cff66ccffto " .. mod.EnchanterText() .. "|r") or "|cff999999junk|r"
        tt:AddLine(("Disenchant %s / vendor %s: %s"):format(mod.Money(de), mod.Money(sell), where), 1, 0.82, 0.5)
    end
    if M.db.tipMats then mod.TipMaterials(tt, link, not shown) end
end

local function Pct(n)
    local s = ("%.1f"):format(n):gsub("%.0$", "")
    return s .. "%"
end

-- one line per material: "  80%  1-2 Strange Dust        12s"
function mod.TipMaterials(tt, link, withHeader)
    local list = mod.Breakdown(link)
    if not list or #list == 0 then return end
    if withHeader then tt:AddLine("Disenchants into:", 1, 0.82, 0.5) end
    for _, e in ipairs(list) do
        local count = e.min == e.max and tostring(e.min) or (e.min .. "-" .. e.max)
        tt:AddDoubleLine(("  %s  %s %s"):format(Pct(e.chance), count, mod.MatName(e.id)),
            e.price and mod.Money(e.price) or "|cff888888no price|r", 0.85, 0.85, 0.85, 0.85, 0.85, 0.85)
    end
end
mod.TipLine = TipLine

local TDP = rawget(_G, "TooltipDataProcessor")
if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
        if tt == GameTooltip or tt == rawget(_G, "ItemRefTooltip") then TipLine(tt) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", TipLine)
    local ref = rawget(_G, "ItemRefTooltip")
    if ref then pcall(ref.HookScript, ref, "OnTooltipSetItem", TipLine) end
end
