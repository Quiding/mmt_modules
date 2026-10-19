-- MMT Totems: chosen totems and cast sequences, shared with the team.
-- Every client keeps them for every shaman (profile: M.db.selected /
-- M.db.sequences), so you can choose a totem for any shaman and that
-- shaman's client sets it up for casting. Messages (only on a change):
--   MTTS:<element>:<spellID or 0>:<teamKey>     chosen totem
--   MTTQ:<teamKey>=<sequence>                   element order
-- Everything at once goes with the core's "Sync to team" (sync = true).

local _, mod = ...
local MMT = MMT
local M = mod.M


function mod.Selected(key, element)
    local s = M.db.selected[key]
    local id = s and s[element]
    return (id and id ~= 0) and id or nil
end

function mod.Sequence(key)
    local s = M.db.sequences[key]
    return (s and s ~= "") and s or mod.DEFAULT_SEQUENCE
end

local function Changed(key)
    if MMT.IsSelf(key) then mod.UpdateSecure() end
    mod.UpdateIcons()
    if MMT.RefreshConfig then MMT.RefreshConfig() end
end

-- quiet = don't tell the team (they get it in the same batch some other way)
function mod.SetSelected(key, element, id, quiet)
    if not mod.TOTEMS[element] then return end
    id = tonumber(id) or 0
    M.db.selected[key] = M.db.selected[key] or {}
    M.db.selected[key][element] = id ~= 0 and id or nil
    if not quiet then MMT.SendToTeam(("MTTS:%s:%d:%s"):format(element, id, key), true) end
    Changed(key)
end

function mod.SetSequence(key, text, quiet)
    text = (text or ""):gsub("[\r\n=]", " ")
    M.db.sequences[key] = text ~= "" and text or nil
    if not quiet then MMT.SendToTeam(("MTTQ:%s=%s"):format(key, text), true) end
    Changed(key)
end

-- takes over an imported set; chosen totems / sequences are merged per shaman
function mod.TakeOver(data, what)
    local n = 0
    if (not what or what.totems) and type(data.selected) == "table" then
        for key, t in pairs(data.selected) do
            if type(key) == "string" and type(t) == "table" then
                local clean = {}
                for el, id in pairs(t) do
                    if mod.TOTEMS[el] and type(id) == "number" then clean[el] = id end
                end
                M.db.selected[key] = clean
                n = n + 1
            end
        end
    end
    if (not what or what.totems) and type(data.sequences) == "table" then
        for key, s in pairs(data.sequences) do
            if type(key) == "string" and type(s) == "string" then M.db.sequences[key] = s; n = n + 1 end
        end
    end
    if (not what or what.presets) and type(data.presets) == "table" then
        M.db.presets = mod.CleanPresets(data.presets)
        n = n + 1
    end
    if (not what or what.presets) and type(data.teamPresets) == "table" then
        M.db.teamPresets = mod.CleanTeamPresets(data.teamPresets)
        n = n + 1
    end
    mod.UpdateSecure()
    mod.Refresh()
    return n > 0
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    local el, id, target = text:match("^MTTS:(%a+):(%d+):(.+)$")
    if el then mod.SetSelected(target, el, id, true) return end
    local qkey, seq = text:match("^MTTQ:([^=]+)=(.*)$")
    if qkey then mod.SetSequence(qkey, seq, true) return end

end)
