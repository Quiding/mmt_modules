-- MMT Totems: chosen totems and cast sequences, shared with the team.
-- Every client keeps them for every shaman (profile: M.db.selected /
-- M.db.sequences), so you can choose a totem for any shaman and that
-- shaman's client sets it up for casting. Messages (only on a change):
--   MTTS:<element>:<spellID or 0>:<teamKey>     chosen totem
--   MTTQ:<teamKey>=<sequence>                   element order
--   MTTP:<id>:<part>:<total>:<data>             "Send to team": chosen totems,
--                                               sequences and presets at once

local _, mod = ...
local MMT = MMT
local M = mod.M

local CHUNK = 200

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

---------------------------------------------------------------------------
-- Send everything (chosen totems, sequences, presets) to the team
---------------------------------------------------------------------------
function mod.SendTotemsOnly()
    local data = { selected = M.db.selected, sequences = M.db.sequences,
                   presets = M.db.presets, teamPresets = M.db.teamPresets }
    local payload = MMTTransfer.Encode("MTTP1", data)
    local id = tostring(math.random(100000, 999999))
    local total = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, total do
        local msg = ("MTTP:%s:%d:%d:%s"):format(id, i, total, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
        C_Timer.After((i - 1) * 0.2, function() MMT.SendToTeam(msg, true) end)
    end
    M:Debug("sent all (%d bytes, %d parts)", #payload, total)
end

-- takes over a received or imported set; chosen totems / sequences are merged per shaman
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

local buffers = {}

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if MMT.IsSelf(key) then return end
    local el, id, target = text:match("^MTTS:(%a+):(%d+):(.+)$")
    if el then mod.SetSelected(target, el, id, true) return end
    local qkey, seq = text:match("^MTTQ:([^=]+)=(.*)$")
    if qkey then mod.SetSequence(qkey, seq, true) return end

    local pid, idx, total, chunk = text:match("^MTTP:(%d+):(%d+):(%d+):(.*)$")
    if not pid then return end
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > 60 or idx < 1 or idx > total then return end
    local buf = buffers[key]
    if not buf or buf.id ~= pid then
        buf = { id = pid, total = total, got = 0, parts = {} }
        buffers[key] = buf
    end
    if not buf.parts[idx] then buf.parts[idx] = chunk; buf.got = buf.got + 1 end
    if buf.got < buf.total then return end
    buffers[key] = nil
    local data = MMTTransfer.Decode("MTTP1", table.concat(buf.parts))
    if not data then return end
    -- ask first (like MMT's own profile sync): presets would be replaced
    MMT.UI.Confirm(("%s sent you their chosen totems, sequences and presets.\n\nTake them over? Your presets are replaced.")
        :format(MMT.FullDisplay(key)), "Take them over", function()
        if mod.TakeOver(data) then
            MMT.Print("Totems: chosen totems, sequences and presets taken over from %s.", MMT.FullDisplay(key))
        end
    end, "Keep mine")
end)
