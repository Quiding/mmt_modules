-- MMT Buffs: weapon enchants. An entry { weapon = "MH" } / { weapon = "OH" } counts
-- ANY enchant on that weapon: shaman imbues (Windfury / Flametongue / Rockbiter /
-- Frostbrand Weapon), rogue poisons, oils, sharpening stones. They aren't auras, so
-- they can't be read from another member's unit:
--   own character   C_Item.GetWeaponEnchantInfo (Forever: imbues are their own enchant
--                   type beside the temporary one), old GetWeaponEnchantInfo as fallback
--   other members   ONE message when theirs changes (put on, replaced, gone, weapon
--                   swapped) - never periodic:  MBW:<MH>;<OH>  with each part
--                   "0" = none | "x" = no weapon there | "<rem>/<dur>/<icon>/<name>"
--                   MBWQ = "send me yours" (at login), answered by whisper.
-- Members we never heard from (older version, offline) show nothing.

local _, mod = ...
local MMT = MMT
local M = mod.M

local SLOTS = { MH = 16, OH = 17 }

mod.weapons = {}   -- [teamKey] = { MH = false (no weapon) | { endTime, dur, icon, name } | nil (none), OH = ... }

-- "main hand" / "mh" / "off hand" / "oh" (the add box) -> "MH" / "OH"
function mod.ParseWeapon(text)
    text = (text or ""):lower():gsub("[%s%-_]", "")
    if text == "mh" or text == "mainhand" or text == "mainhandenchant" then return "MH" end
    if text == "oh" or text == "offhand" or text == "offhandenchant" then return "OH" end
    return nil
end

local function Readable(v) return v ~= nil and not MMT.IsSecret(v) end

-- is there a weapon in the slot (a shield or held-in-off-hand item can't take an enchant)
local function HasWeapon(inv)
    local id = GetInventoryItemID("player", inv)
    if not id then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local classID = info and select(6, info(id))
    return classID == nil or classID == 2
end

-- the enchant's name from the weapon's tooltip ("Windfury 3 (5 min)" -> "Windfury 3"), or nil
local function EnchantName(inv)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", inv)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local t = line.leftText
        if Readable(t) and type(t) == "string" then
            local name = t:match("^(.-) %(%d+ %a+%)") or t:match("^(.-) %(%d+%a*%)$")
            if name and name ~= "" and #name < 40 then return name end
        end
    end
end

-- own weapons: slot -> { left, icon, id } | false (no weapon) | nil (no enchant)
local function ReadOwn()
    local out = {}
    for slot, inv in pairs(SLOTS) do
        if not HasWeapon(inv) then
            out[slot] = false
        else
            local best
            local ws = Enum and Enum.WeaponSlot and (slot == "MH" and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand)
            if ws and C_Item and C_Item.GetWeaponEnchantInfo then
                local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
                if ok and type(list) == "table" then
                    for _, e in ipairs(list) do
                        if Readable(e.hasEnchant) and e.hasEnchant and Readable(e.timeLeft) and e.timeLeft > 0 then
                            local left = e.timeLeft / 1000
                            -- an imbue wins over an oil / stone on the same weapon, else the longer one
                            local imbue = Enum.ItemEnchantType and Readable(e.enchantType) and e.enchantType == Enum.ItemEnchantType.Imbue
                            if not best or (imbue and not best.imbue) or (imbue == best.imbue and left > best.left) then
                                best = { left = left, imbue = imbue,
                                    id = Readable(e.enchantID) and e.enchantID or 0,
                                    icon = Readable(e.enchantIconID) and e.enchantIconID ~= 0 and e.enchantIconID or nil }
                            end
                        end
                    end
                end
            elseif GetWeaponEnchantInfo then
                local hasMH, mhLeft, _, mhID, hasOH, ohLeft, _, ohID = GetWeaponEnchantInfo()
                local has, left, id = hasMH, mhLeft, mhID
                if slot == "OH" then has, left, id = hasOH, ohLeft, ohID end
                if Readable(has) and has and Readable(left) and left > 0 then
                    best = { left = left / 1000, id = Readable(id) and id or 0 }
                end
            end
            if best then
                best.icon = best.icon or GetInventoryItemTexture("player", inv)
                best.name = EnchantName(inv)
            end
            out[slot] = best
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Own state, and the one message when it changes
---------------------------------------------------------------------------
local own = {}        -- slot -> { endTime, dur, icon, name, id } | false | nil
local function Part(s)
    if s == false then return "x" end
    if not s then return "0" end
    local name = (s.name or ""):gsub("[;/:|]", "")
    return ("%d/%d/%d/%s"):format(math.max(1, math.floor(s.endTime - GetTime() + 0.5)), math.floor(s.dur + 0.5),
        tonumber(s.icon) or 0, name)
end
function mod.OwnWeaponMessage() return "MBW:" .. Part(own.MH) .. ";" .. Part(own.OH) end

local sendQueued = false
local function QueueSend()
    if sendQueued then return end
    sendQueued = true
    C_Timer.After(1, function()   -- main + off hand put on together: one message
        sendQueued = false
        if M.enabled then MMT.SendToTeam(mod.OwnWeaponMessage(), true) end
    end)
end

function mod.ScanWeapons(quiet)
    local now, changed = GetTime(), false
    local read = ReadOwn()
    for slot in pairs(SLOTS) do
        local r, o = read[slot], own[slot]
        if r == false or r == nil then
            if o ~= r then changed = true end
            own[slot] = r
        else
            local endTime = now + r.left
            -- new, another enchant, or put on again (its end moved out): a new duration
            if not o or o.id ~= r.id or endTime > o.endTime + 5 then
                own[slot] = { endTime = endTime, dur = r.left, icon = r.icon, name = r.name, id = r.id }
                changed = true
            else
                o.endTime = endTime
                o.name = o.name or r.name
            end
        end
    end
    local me = MMT.PlayerFull and MMT.PlayerFull()
    if me then mod.weapons[me] = own end
    if changed then
        if not quiet then QueueSend() end
        mod.Refresh()
    end
end

-- state of weapon entry e for a member: like mod.State
function mod.WeaponState(key, e)
    local w = mod.weapons[key]
    if not w then return nil end
    if not MMT.IsSelf(key) and not MMT.IsOnline(key) then return nil end
    local s = w[e.weapon]
    if s == false then return nil end   -- no weapon there (shield, 2H in the main hand only)
    if s and s.endTime > GetTime() then
        return "buff", s.endTime - s.dur, s.dur, nil, s.name, (s.icon and s.icon ~= 0) and s.icon or nil
    end
    return "missing"
end

local function ParsePart(p)
    if p == "x" then return false end
    local rem, dur, icon, name = p:match("^(%d+)/(%d+)/(%d+)/(.*)$")
    if not rem then return nil end
    rem, dur = tonumber(rem), tonumber(dur)
    return { endTime = GetTime() + rem, dur = math.max(dur, rem), icon = tonumber(icon), name = name ~= "" and name or nil }
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    if text == "MBWQ" then
        MMT.SendAddon(mod.OwnWeaponMessage(), "WHISPER", sender)
        return
    end
    local mh, oh = text:match("^MBW:([^;]*);(.*)$")
    if mh then
        mod.weapons[key] = { MH = ParsePart(mh), OH = ParsePart(oh) }
        mod.Refresh()
    end
end)

-- events (WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED are Forever's; registered with
-- pcall: not every one exists on every client) + a slow re-read for an enchant running out
local frame = CreateFrame("Frame")
for _, ev in ipairs({ "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event, unit)
    if not M.enabled or (event == "UNIT_INVENTORY_CHANGED" and unit ~= "player") then return end
    mod.ScanWeapons()
end)

local ticker
function mod.StartWeapons()
    mod.ScanWeapons(true)
    if not ticker then ticker = C_Timer.NewTicker(5, function() if M.enabled then mod.ScanWeapons() end end) end
    C_Timer.After(8, function()
        if not M.enabled then return end
        MMT.SendToTeam(mod.OwnWeaponMessage(), true)
        MMT.SendToTeam("MBWQ", true)
    end)
end

function mod.StopWeapons()
    if ticker then ticker:Cancel() ticker = nil end
end
