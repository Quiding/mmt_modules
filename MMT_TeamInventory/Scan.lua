-- MMT Team Inventory: counts this character's items by item ID.
-- Bags (and keyring / reagent bag) and equipped items are always readable;
-- the bank only while it is open, the mailbox only while it is open: their
-- last counts are kept until the next visit.

local _, mod = ...
local MMT = MMT
local M = mod.M

local B = Enum and Enum.BagIndex or {}
local BAGS, BANK = {}, {}
for _, k in ipairs({ "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag", "Keyring" }) do
    if B[k] then BAGS[#BAGS + 1] = B[k] end
end
if #BAGS == 0 then BAGS = { 0, 1, 2, 3, 4 } end
for i = 1, 9 do
    if B["CharacterBankTab_" .. i] then BANK[#BANK + 1] = B["CharacterBankTab_" .. i] end
end
if #BANK == 0 then   -- older bank: the bank itself and its bag slots
    BANK = { B.Bank or -1 }
    for i = 5, 11 do BANK[#BANK + 1] = i end
end
mod.BAG_INDEXES, mod.BANK_INDEXES = BAGS, BANK

local C = C_Container or {}
local bankOpen, mailOpen = false, false

local function CountBags(list)
    local t = {}
    for _, bag in ipairs(list) do
        local n = C.GetContainerNumSlots and MMT.Safe(C.GetContainerNumSlots, bag) or 0
        for slot = 1, n do
            local info = C.GetContainerItemInfo and MMT.Safe(C.GetContainerItemInfo, bag, slot)
            local id = type(info) == "table" and info.itemID
            if id then t[id] = (t[id] or 0) + (info.stackCount or 1) end
        end
    end
    return t
end

local function CountEquipped()
    local t = {}
    for slot = 1, 19 do
        local id = MMT.Safe(GetInventoryItemID, "player", slot)
        if id then t[id] = (t[id] or 0) + 1 end
    end
    return t
end

local function CountMail()
    local t = {}
    local n = MMT.Safe(GetInboxNumItems) or 0
    local max = ATTACHMENTS_MAX_RECEIVE or 16
    for i = 1, n do
        for a = 1, max do
            local _, id, _, count = MMT.Safe(GetInboxItem, i, a)
            if id then t[id] = (t[id] or 0) + (count or 1) end
        end
    end
    return t
end

-- this character's record (made on first use)
function mod.Own()
    local key = MMT.PlayerFull()
    if not key then return nil end
    local chars = mod.Chars()
    chars[key] = chars[key] or { b = {}, k = {}, m = {}, e = {} }
    chars[key].class = select(2, UnitClass("player")) or chars[key].class
    return chars[key], key
end

-- reads what can be read now; returns true when something changed
function mod.ScanAll()
    local rec = mod.Own()
    if not rec then return false end
    local new = { b = CountBags(BAGS), e = CountEquipped() }
    if bankOpen then new.k = CountBags(BANK) end
    if mailOpen then new.m = CountMail() end
    local changed = false
    for p, t in pairs(new) do
        if mod.Encode({ [p] = t }) ~= mod.Encode({ [p] = rec[p] or {} }) then
            mod.NoteChange(p, rec[p] or {}, t)
            rec[p] = t
            changed = true
        end
    end
    if changed then
        rec.hash = mod.Hash(rec)
        rec.time = time()
        mod.OwnChanged()
        if mod.RefreshBags then mod.RefreshBags() end   -- the open team bags show it at once
    end
    return changed
end

-- bag updates come in bursts: one scan a moment after the last one
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        if M.enabled then mod.ScanAll() end
    end)
end
mod.ScanSoon = Soon

M:On("BAG_UPDATE_DELAYED", Soon)
M:On("PLAYER_ENTERING_WORLD", Soon)
M:On("PLAYER_EQUIPMENT_CHANGED", Soon)
M:On("PLAYERBANKSLOTS_CHANGED", Soon)
M:On("BANKFRAME_OPENED", function() bankOpen = true; Soon() end)
-- closed: not read again (it may read as empty now), the last counts stay
M:On("BANKFRAME_CLOSED", function() bankOpen = false end)
-- the inbox also "updates" at login (new mail notice) while it can't be read: only with the mailbox open
M:On("MAIL_INBOX_UPDATE", function()
    if MailFrame and MailFrame:IsShown() then mailOpen = true; Soon() end
end)
M:On("MAIL_CLOSED", function() mailOpen = false end)

-- for the debug report
function mod.ScanState() return bankOpen, mailOpen end
