-- MMT Buffs: who a buff is for.
--
-- Every tracked buff can be limited ("Only for", the cog in the list editor) to
-- classes, specs and / or MMT roles: e.only = { classes = { WARRIOR = true },
-- specs = { ["PALADIN:RET"] = true }, mmt = { Healer = true } } (specs: Specs.lua -
-- set by hand, else the talents; MMT roles: /mmt > Roles). Nothing ticked = for
-- everyone; otherwise a member counts when they match ANY ticked one. Members it
-- isn't for don't count as missing it.
-- (Until 0.22 there were also Buff Timers' own player roles, e.only.roles: ignored
-- now, and dropped on import / sync.)

local _, mod = ...
local MMT = MMT

local CLASS_OK = {}
for _, c in ipairs(mod.CLASSES) do if c ~= "ALL" then CLASS_OK[c] = true end end

local function Any(t) return type(t) == "table" and next(t) ~= nil end

function mod.HasFilter(e)
    local o = e.only
    return type(o) == "table" and (Any(o.classes) or Any(o.specs) or Any(o.mmt))
end

-- does buff entry e count for member key?
function mod.Applies(e, key)
    if not mod.HasFilter(e) then return true end
    local o = e.only
    local class = mod.ClassOf(key)
    if class and o.classes and o.classes[class] then return true end
    if o.specs and mod.SpecOf then
        local spec = mod.SpecOf(key)
        if spec and o.specs[spec] then return true end
        -- spec not known yet (no talents, older client): any ticked spec of their class counts
        if not spec and class then
            for s in pairs(o.specs) do
                if s:sub(1, #class + 1) == class .. ":" then return true end
            end
        end
    end
    if o.mmt then
        for _, r in ipairs(MMT.MemberRoleList(key)) do if o.mmt[r] then return true end end
    end
    return false
end

-- "Warrior, Paladin: Retribution, Healer (MMT role)" or nil
function mod.FilterText(e)
    if not mod.HasFilter(e) then return nil end
    local t = {}
    for _, c in ipairs(mod.CLASSES) do
        if c ~= "ALL" and e.only.classes and e.only.classes[c] then t[#t + 1] = mod.ListLabel(c) end
    end
    for _, sp in ipairs(mod.AllSpecs and mod.AllSpecs() or {}) do
        if e.only.specs and e.only.specs[sp[1]] then t[#t + 1] = sp[2] end
    end
    local mmt = {}
    for r in pairs(e.only.mmt or {}) do mmt[#mmt + 1] = r end
    table.sort(mmt)
    for _, r in ipairs(mmt) do t[#t + 1] = r .. " (MMT role)" end
    return table.concat(t, ", ")
end

-- an entry's filter from imported / synced data, cleaned (or nil)
function mod.CleanFilter(o)
    if type(o) ~= "table" then return nil end
    local out = {}
    local function Copy(src, valid)
        if type(src) ~= "table" then return nil end
        local t
        for k, v in pairs(src) do
            if v == true and type(k) == "string" and valid(k) then t = t or {}; t[k] = true end
        end
        return t
    end
    out.classes = Copy(o.classes, function(k) return CLASS_OK[k] ~= nil end)
    out.specs = Copy(o.specs, function(k) return k:match("^%u+:%u+$") ~= nil end)
    out.mmt = Copy(o.mmt, function(k) return k ~= "" end)
    if not (out.classes or out.specs or out.mmt) then return nil end
    return out
end
