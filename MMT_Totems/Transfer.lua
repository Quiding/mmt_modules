-- MMTTransfer: export / import of module settings as a text string.
-- Shared by MMT_Cooldowns and MMT_Buffs: both ship this same file and the
-- newest version wins, so KEEP BOTH COPIES IDENTICAL and raise VERSION.
--
-- A string looks like  MMTCD1:<checksum>:<base64 data>
-- The data is our own small format (strings, numbers, booleans, tables),
-- parsed by hand: nothing pasted is ever run as Lua code.
--
--   MMTTransfer.Open{
--       title = "Cooldowns", prefix = "MMTCD1",
--       sections = { { id = "lists", label = "Tracked lists", get = fn() -> data,
--                      set = fn(data) -> ok, err }, ... },
--       legacy = { { id, label, set }, ... },   -- (v5) sections of older strings: imported when present, no checkbox
--   }

local VERSION = 5
if MMTTransfer and (MMTTransfer.version or 0) >= VERSION then return end

local lib = MMTTransfer or {}
MMTTransfer = lib
lib.version = VERSION

local MMT = MMT

---------------------------------------------------------------------------
-- Serializer
---------------------------------------------------------------------------
local function Ser(v, out, depth)
    if depth > 20 then error("too deep") end
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. ("%.10g"):format(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local tk, tx = type(k), type(x)
            if (tk == "string" or tk == "number") and (tx == "string" or tx == "number" or tx == "boolean" or tx == "table") then
                Ser(k, out, depth + 1)
                Ser(x, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

function lib.Serialize(v)
    local out = {}
    Ser(v, out, 0)
    return table.concat(out)
end

-- returns value, next position (errors on bad input)
local function De(s, pos, depth)
    if depth > 20 then error("too deep") end
    local c = s:sub(pos, pos)
    if c == "s" then
        local len, rest = s:match("^(%d+):()", pos + 1)
        len = tonumber(len)
        if not len or rest + len - 1 > #s then error("bad string") end
        return s:sub(rest, rest + len - 1), rest + len
    elseif c == "n" then
        local num, rest = s:match("^([%-%d%.eE+]+);()", pos + 1)
        if not tonumber(num) then error("bad number") end
        return tonumber(num), rest
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        while s:sub(pos, pos) ~= "}" do
            if pos > #s then error("unfinished table") end
            local k, x
            k, pos = De(s, pos, depth + 1)
            x, pos = De(s, pos, depth + 1)
            if type(k) == "table" then error("bad key") end
            t[k] = x
        end
        return t, pos + 1
    end
    error("bad data")
end

function lib.Deserialize(s)
    local ok, v, pos = pcall(De, s, 1, 0)
    if not ok then return nil end
    if pos ~= #s + 1 then return nil end
    return v
end

---------------------------------------------------------------------------
-- Base64 (so the string survives chat, edit boxes and pasting)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:sub(i, i)] = i - 1 end

local function Encode64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Decode64(s)
    s = s:gsub("[^%w%+/=]", "")
    if #s % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q = s:sub(i, i + 3)
        local v1, v2, v3, v4 = DEC[q:sub(1, 1)], DEC[q:sub(2, 2)], DEC[q:sub(3, 3)], DEC[q:sub(4, 4)]
        if not v1 or not v2 then return nil end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if q:sub(3, 3) ~= "=" then
            if not v3 then return nil end
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if q:sub(4, 4) ~= "=" then
            if not v4 then return nil end
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

local function Checksum(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- table -> "PREFIX:checksum:base64"
function lib.Encode(prefix, data)
    local raw = lib.Serialize(data)
    return ("%s:%d:%s"):format(prefix, Checksum(raw), Encode64(raw))
end

-- string -> table, or nil and a reason
function lib.Decode(prefix, text)
    text = (text or ""):gsub("%s", "")
    local p, sum, body = text:match("^([%w]+):(%d+):(.+)$")
    if not p then return nil, "That is not an export string." end
    if p ~= prefix then return nil, ("This string is for another module (%s)."):format(p) end
    local raw = Decode64(body)
    if not raw or Checksum(raw) ~= tonumber(sum) then return nil, "The string is damaged or incomplete." end
    local data = lib.Deserialize(raw)
    if type(data) ~= "table" then return nil, "The string could not be read." end
    return data
end

---------------------------------------------------------------------------
-- Dialog
---------------------------------------------------------------------------
local dialog

local function Build()
    local UI = MMT.UI
    local f = CreateFrame("Frame", "MMTTransferDialog", UIParent)
    f:SetSize(440, 400)
    f:SetPoint("CENTER")
    -- above MMT's settings window (DIALOG, or FULLSCREEN_DIALOG when it is pinned on top)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Fill(f, 0.06, 0.06, 0.07, 0.97)
    UI.Border(f, 0.3, 0.3, 0.3, 1)
    UI.CloseOnEscape(f)

    f.title = UI.Label(f, "", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    local close = UI.TextButton(f, "x", function() f:Hide() end, 18)
    close:SetPoint("TOPRIGHT", -6, -6)

    local hint = UI.Label(f, "Choose what to export or import:")
    hint:SetPoint("TOPLEFT", 12, -32)
    hint:SetTextColor(0.6, 0.6, 0.6)

    f.checks = {}
    f.area = UI.TextArea(f, 416, 170)
    f.status = UI.Label(f, "")
    f.status:SetPoint("BOTTOMLEFT", 12, 40)
    f.status:SetPoint("BOTTOMRIGHT", -12, 40)
    f.status:SetJustifyH("LEFT")

    local function Status(text, bad)
        f.status:SetText(text or "")
        if bad then f.status:SetTextColor(1, 0.4, 0.4) else f.status:SetTextColor(0.6, 0.9, 0.6) end
    end

    local export = UI.Button(f, 132, "Export", function()
        local data = { sections = {} }
        local names = {}
        for _, s in ipairs(f.def.sections) do
            if f.selected[s.id] then
                local ok, v = pcall(s.get)
                if ok and v ~= nil then data.sections[s.id] = v; names[#names + 1] = s.label end
            end
        end
        if #names == 0 then Status("Tick at least one part to export.", true) return end
        local text = lib.Encode(f.def.prefix, data)
        f.area.edit:SetText(text)
        f.area.edit:SetFocus()
        f.area.edit:HighlightText()
        Status(("Exported: %s. Press Ctrl+C to copy."):format(table.concat(names, ", ")))
    end)
    export:SetPoint("BOTTOMLEFT", 12, 10)

    local import = UI.Button(f, 132, "Import", function()
        local data, err = lib.Decode(f.def.prefix, f.area.edit:GetText())
        if not data then Status(err, true) return end
        local secs = type(data.sections) == "table" and data.sections or {}
        local done, failed, skipped = {}, {}, {}
        for _, s in ipairs(f.def.sections) do
            if secs[s.id] ~= nil then
                if f.selected[s.id] then
                    local ok, res, why = pcall(s.set, secs[s.id])
                    if ok and res ~= false then done[#done + 1] = s.label
                    else failed[#failed + 1] = s.label .. (why and (" (" .. why .. ")") or "") end
                else
                    skipped[#skipped + 1] = s.label
                end
            end
        end
        -- (v5) sections an older version exported under other names
        for _, s in ipairs(f.def.legacy or {}) do
            if secs[s.id] ~= nil then
                local ok, res, why = pcall(s.set, secs[s.id])
                if ok and res ~= false then done[#done + 1] = s.label
                else failed[#failed + 1] = s.label .. (why and (" (" .. why .. ")") or "") end
            end
        end
        if #done == 0 and #failed == 0 then
            Status(#skipped > 0 and ("Nothing ticked that the string contains (%s)."):format(table.concat(skipped, ", "))
                or "The string contains nothing for this module.", true)
            return
        end
        local text = #done > 0 and ("Imported: " .. table.concat(done, ", ") .. ".") or ""
        if #failed > 0 then text = text .. " Not imported: " .. table.concat(failed, ", ") .. "." end
        Status(text, #failed > 0)
        if f.def.after then pcall(f.def.after) end
        if MMT.RefreshConfig then MMT.RefreshConfig() end
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)

    local clear = UI.Button(f, 132, "Clear", function() f.area.edit:SetText(""); Status("") end)
    clear:SetPoint("LEFT", import, "RIGHT", 8, 0)

    f.Status = Status
    return f
end

function lib.Open(def)
    dialog = dialog or Build()
    local f = dialog
    f.def = def
    f.selected = {}
    f.title:SetText(def.title .. ": Import / Export")
    for _, c in ipairs(f.checks) do c:Hide() end
    local y = -54
    for i, s in ipairs(def.sections) do
        f.selected[s.id] = true
        local c = f.checks[i]
        if not c then
            c = MMT.UI.Check(f, 200, "", function() return f.selected[c.id] end, function(v) f.selected[c.id] = v end)
            f.checks[i] = c
        end
        c.id = s.id
        c.label:SetText(s.label)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 12 + ((i - 1) % 2) * 210, y - math.floor((i - 1) / 2) * 22)
        c.Refresh()
        c:Show()
    end
    local rows = math.ceil(#def.sections / 2)
    f.area:ClearAllPoints()
    f.area:SetPoint("TOPLEFT", 12, y - rows * 22 - 8)
    f.area:SetPoint("BOTTOMRIGHT", -12, 58)
    f.area.edit:SetWidth(416 - 12)
    f.area.edit:SetText("")
    f.Status("Export: tick the parts and press Export. Import: paste a string and press Import.")
    -- same size as MMT's settings window
    f:SetScale((MMT.ConfigScale and MMT.ConfigScale()) or 1)
    f:SetFrameLevel(100)
    f:Show()
    f:Raise()
end
