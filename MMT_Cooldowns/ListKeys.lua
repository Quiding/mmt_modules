-- Which tracked lists apply to a member. M.db.lists is keyed by
--   a class token ("MAGE") or "ALL",
--   "ROLE:<role name>" (MMT roles, /mmt > Roles),
--   "CHAR:<team key>" (one character).
-- MMT_Cooldowns and MMT_Buffs ship the same copy of this file (KEEP BOTH
-- IDENTICAL). It needs mod.CLASSES and mod.M.

local _, mod = ...
local MMT = MMT

local CLASS_NAMES = { ALL = "All classes" }

local function IsClass(k)
    for _, c in ipairs(mod.CLASSES) do if c == k then return true end end
    return false
end

function mod.ValidListKey(k)
    if type(k) ~= "string" then return false end
    return IsClass(k) or (k:match("^ROLE:.+") ~= nil) or (k:match("^CHAR:.+") ~= nil)
end

function mod.ClassOf(key)
    if MMT.IsSelf(key) then return select(2, UnitClass("player")) end
    local m = MMT.db.team[key]
    return m and m.class
end

-- list keys for a member, in order: class, [ALL], roles, character
function mod.ListKeysFor(key, withAll)
    local keys = {}
    local class = mod.ClassOf(key)
    if class then keys[#keys + 1] = class end
    if withAll then keys[#keys + 1] = "ALL" end
    for _, role in ipairs(MMT.MemberRoleList(key)) do keys[#keys + 1] = "ROLE:" .. role end
    keys[#keys + 1] = "CHAR:" .. key
    return keys
end

-- entries for a member from all their lists; id(e) removes doubles
function mod.CollectEntries(key, withAll, id)
    local out, seen = {}, {}
    for _, lk in ipairs(mod.ListKeysFor(key, withAll)) do
        for _, e in ipairs(mod.M.db.lists[lk] or {}) do
            local k = id(e)
            if k and not seen[k] then seen[k] = true; out[#out + 1] = e end
        end
    end
    return out
end

function mod.ListLabel(k)
    local role = k:match("^ROLE:(.+)$")
    if role then return "Role: " .. role end
    local char = k:match("^CHAR:(.+)$")
    if char then return MMT.FullDisplay(char) end
    return CLASS_NAMES[k] or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[k]) or k
end

-- dropdown choices: classes, roles, characters (with the number of entries)
function mod.ListChoices()
    local lists = mod.M.db.lists
    local function Item(k)
        local n = lists[k] and #lists[k] or 0
        return { value = k, text = mod.ListLabel(k) .. (n > 0 and ("  |cff888888(" .. n .. ")|r") or "") }
    end
    local t = { { header = true, text = "Classes" } }
    for _, c in ipairs(mod.CLASSES) do t[#t + 1] = Item(c) end
    local roles = MMT.SortedRoleNames()
    if #roles > 0 then
        t[#t + 1] = { header = true, text = "Roles" }
        for _, r in ipairs(roles) do t[#t + 1] = Item("ROLE:" .. r) end
    end
    t[#t + 1] = { header = true, text = "Characters" }
    for _, key in ipairs(MMT.SortedMembers()) do t[#t + 1] = Item("CHAR:" .. key) end
    return t
end
