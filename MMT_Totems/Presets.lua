-- MMT Totems: presets.
--   individual: M.db.presets[teamKey][name] = { totems = { Fire = id, ... }, sequence, icon }
--   team:       M.db.teamPresets[name] = { members = { [teamKey] = { totems, sequence } }, icon }
-- Applying one sets the chosen totems / sequence like choosing them by hand
-- (the team is told, each shaman's client sets up its casting).

local _, mod = ...
local MMT = MMT
local M = mod.M

local function CopyTotems(t)
    local out = {}
    for _, el in ipairs(mod.ELEMENTS) do
        if t and type(t[el]) == "number" and t[el] ~= 0 then out[el] = t[el] end
    end
    return out
end

local function CleanIcon(icon)
    if type(icon) == "number" then return icon end
    if type(icon) == "string" and icon ~= "" then return icon end
    return mod.PRESET_ICON
end

local function CleanEntry(e)
    if type(e) ~= "table" then return nil end
    return { totems = CopyTotems(e.totems), sequence = type(e.sequence) == "string" and e.sequence or nil, icon = CleanIcon(e.icon) }
end

-- validated copies (for received / imported data)
function mod.CleanPresets(data)
    local out = {}
    for key, list in pairs(type(data) == "table" and data or {}) do
        if type(key) == "string" and type(list) == "table" then
            out[key] = {}
            for name, e in pairs(list) do
                if type(name) == "string" and name ~= "" then out[key][name] = CleanEntry(e) end
            end
        end
    end
    return out
end

function mod.CleanTeamPresets(data)
    local out = {}
    for name, p in pairs(type(data) == "table" and data or {}) do
        if type(name) == "string" and name ~= "" and type(p) == "table" then
            local members = {}
            for key, e in pairs(type(p.members) == "table" and p.members or {}) do
                if type(key) == "string" then
                    local c = CleanEntry(e)
                    if c then c.icon = nil; members[key] = c end
                end
            end
            out[name] = { members = members, icon = CleanIcon(p.icon) }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Individual presets
---------------------------------------------------------------------------
-- saves a shaman's current totems + sequence; returns ok, message
function mod.SavePreset(key, name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not key then return false, "Choose a shaman first." end
    if name == "" then return false, "Enter a preset name." end
    M.db.presets[key] = M.db.presets[key] or {}
    local old = M.db.presets[key][name]
    M.db.presets[key][name] = { totems = CopyTotems(M.db.selected[key]), sequence = M.db.sequences[key],
        icon = old and old.icon or mod.PRESET_ICON }
    return true, ("Preset \"%s\" saved for %s."):format(name, MMT.FirstName(key))
end

function mod.ApplyPreset(key, name)
    local p = M.db.presets[key] and M.db.presets[key][name]
    if not p then return end
    for _, el in ipairs(mod.ELEMENTS) do mod.SetSelected(key, el, p.totems and p.totems[el] or 0) end
    if p.sequence then mod.SetSequence(key, p.sequence) end
    MMT.Print("Totems: preset \"%s\" applied to %s.", name, MMT.FirstName(key))
end

function mod.DeletePreset(key, name)
    if M.db.presets[key] then M.db.presets[key][name] = nil end
end

---------------------------------------------------------------------------
-- Team presets
---------------------------------------------------------------------------
function mod.SaveTeamPreset(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Enter a preset name." end
    local members, n = {}, 0
    for _, key in ipairs(MMT.SortedMembers()) do
        if mod.IsShaman(key) and (M.db.selected[key] or M.db.sequences[key]) then
            members[key] = { totems = CopyTotems(M.db.selected[key]), sequence = M.db.sequences[key] }
            n = n + 1
        end
    end
    local own = mod.OwnKey()
    if not members[own] and mod.IsShaman(own) and (M.db.selected[own] or M.db.sequences[own]) then
        members[own] = { totems = CopyTotems(M.db.selected[own]), sequence = M.db.sequences[own] }
        n = n + 1
    end
    if n == 0 then return false, "No shaman has chosen totems yet." end
    local old = M.db.teamPresets[name]
    M.db.teamPresets[name] = { members = members, icon = old and old.icon or mod.PRESET_ICON }
    return true, ("Team preset \"%s\" saved (%d shaman%s)."):format(name, n, n == 1 and "" or "s")
end

function mod.ApplyTeamPreset(name)
    local p = M.db.teamPresets[name]
    if not p or not p.members then return end
    for key, e in pairs(p.members) do
        for _, el in ipairs(mod.ELEMENTS) do mod.SetSelected(key, el, e.totems and e.totems[el] or 0) end
        if e.sequence then mod.SetSequence(key, e.sequence) end
    end
    MMT.Print("Totems: team preset \"%s\" applied.", name)
end

function mod.DeleteTeamPreset(name)
    M.db.teamPresets[name] = nil
end

-- icon from a spell / item name or ID, or a texture path; nil if not found
function mod.FindIcon(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if text:find("\\", 1, true) then return text end
    local n = tonumber(text)
    local icon = mod.SpellIcon(n or text)
    if icon then return icon end
    local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return n and fn and fn(n) or nil
end
