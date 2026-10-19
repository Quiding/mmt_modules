-- MMT Whispers: the receiver's side. Puts the alts' whispers (MWF, see
-- Forward.lua) together and shows them in the chosen chat window:
--   [Sender] to [Alt]: text          a whisper the alt got
--   [Alt] to [Sender]: text          what the alt whispered
-- Both names are clickable. The R key (reply) then goes to the alt, which
-- passes the text on, or straight to the sender ("reply" setting).

local _, mod = ...
local MMT = MMT
local M = mod.M

local KINDS = {
    W = "WHISPER", I = "WHISPER_INFORM", B = "BN_WHISPER", b = "BN_WHISPER_INFORM", N = "WHISPER",
}
local RECENT = 10

mod.shown = {}   -- the last lines shown, for the debug report: { time, alt, kind, name }

local function PlayerLink(name, text)
    return ("|Hplayer:%s|h[%s]|h"):format(name, text)
end

-- "Anna-Smith" / "Anna Smith" -> "Anna Smith"
local function Pretty(name)
    return (MMT.StripRealm(name):gsub("-", " "))
end

local function Stamp()
    local fmt = CHAT_TIMESTAMP_FORMAT
    if type(fmt) ~= "string" or fmt == "" then fmt = "%H:%M " end
    return BetterDate and BetterDate(fmt, time()) or date(fmt)
end

function mod.ChatFrame()
    return _G["ChatFrame" .. (tonumber(M.db.chatFrame) or 1)] or DEFAULT_CHAT_FRAME
end

-- R (reply) goes to name
function mod.SetReply(name)
    if not name or name == "" or MMT.IsSecret(name) then return end
    local set = (ChatFrameUtil and ChatFrameUtil.SetLastTellTarget) or ChatEdit_SetLastTellTarget
    if set then pcall(set, name, "WHISPER") end
end

-- altKey / altName: the alt (team key, name as the game reported it);
-- noReply: leave the reply target alone (test lines)
function mod.Show(altKey, altName, kind, flags, name, text, noReply)
    local info = ChatTypeInfo and ChatTypeInfo[KINDS[kind] or "WHISPER"] or { r = 1, g = 0.5, b = 1 }
    local alt = PlayerLink(altName, MMT.FirstName(altKey))
    local bn = kind == "B" or kind == "b"
    local other = bn and ("[" .. name .. "]") or PlayerLink(name, Pretty(name))
    local gm = flags and flags:find("G", 1, true) and "<GM> " or ""
    local line
    if kind == "W" or kind == "B" then line = ("%s%s to %s: %s"):format(gm, other, alt, text)
    elseif kind == "I" or kind == "b" then line = ("%s to %s: %s"):format(alt, other, text)
    else line = ("%s: %s"):format(alt, text) end
    if M.db.stamp then line = Stamp() .. line end
    mod.ChatFrame():AddMessage(line, info.r, info.g, info.b)

    if kind == "W" or kind == "B" then
        if M.db.sound and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
        if not noReply then
            if M.db.reply == "ALT" then mod.SetReply(altName)
            elseif M.db.reply == "DIRECT" and not bn then mod.SetReply(name) end
        end
    end
    table.insert(mod.shown, 1, { time = time(), alt = altKey, kind = kind, name = name })
    while #mod.shown > RECENT do table.remove(mod.shown) end
end

local buffers = {}   -- [team key] = { id, total, got, parts }

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local id, idx, total, chunk = text:match("^MWF:(%d+):(%d+):(%d+):(.*)$")
    if not id or MMT.IsSelf(key) then return end
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > 10 or idx < 1 or idx > total then return end
    local buf = buffers[key]
    if not buf or buf.id ~= id then
        buf = { id = id, total = total, got = 0, parts = {} }
        buffers[key] = buf
    end
    if not buf.parts[idx] then buf.parts[idx] = chunk; buf.got = buf.got + 1 end
    if buf.got < buf.total then return end
    buffers[key] = nil
    local kind, flags, name, msg = table.concat(buf.parts):match("^(%a):(%a*):([^:]*):(.*)$")
    if kind and KINDS[kind] then mod.Show(key, sender, kind, flags, name, msg) end
end)
