-- MMT module: Quality of life.
-- Home for small team conveniences. Each feature is one file that calls
-- mod.Feature{...}: it gets its own on/off checkbox and options on the
-- settings page, its own message tags and lines in the debug report.
--
--   Ask.lua        "ask before applying": one dialog per sender and feature
--   Dejunk.lua     Dejunk's junk / not-junk lists, the same on the team
--   Baganator.lua  Baganator's items put into categories, the same on the team
--   ForeverAuras.lua  send ForeverAuras auras to the team (AurasWindow.lua: the window)
--   Settings.lua   settings page and debug report

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.4.2"

local M = MMT.NewModule({
    name = "QoL",
    title = "Quality of life",
    description = "Small team conveniences: Dejunk's junk lists and Baganator's category items stay the same on every character; send ForeverAuras auras to the team.",
    sync = true,
    defaults = {
        -- Dejunk
        dejunk = true,             -- sync the lists
        djAdd = true,              -- send / take items added to a list
        djRemove = true,           -- send / take items removed from a list
        djProfile = true,          -- the profile lists too (else only the global ones)
        djLive = true,             -- take changes through Dejunk's key binding buttons (else: after a /reload)
        djAsk = false,             -- ask before applying what the team sends
        djChat = true,             -- a chat line for each change taken
        -- Baganator
        baganator = true,
        bgAdd = true,
        bgRemove = true,
        bgScope = "ALL",           -- ALL categories | JUNK (only Baganator's Junk category)
        bgAsk = false,
        bgChat = true,
        junkLink = true,           -- Baganator's Junk <-> Dejunk's global junk list (on this character)
        -- ForeverAuras
        auras = true,              -- send / take auras
        waAsk = true,              -- a dialog before ForeverAuras' import window
        waFrom = "TEAM",           -- who may send: TEAM | LEADER (the FTL leader)
        waDock = true,             -- "Send to team" button above ForeverAuras' options
    },
})
mod.M = M

-- features in the order they were registered:
-- { key, title, addon, slash, tags = { TAG = fn(key, sender, body) }, commands = { word = fn() -> ok, err }, Page, Report }
mod.features = {}
local byTag = {}

function mod.Feature(f)
    mod.features[#mod.features + 1] = f
    for tag, fn in pairs(f.tags or {}) do byTag[tag] = { f = f, fn = fn } end
    return f
end

-- Is the addon loaded? false + why not
function mod.AddonState(name)
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local ok, loaded = pcall(IsLoaded, name)
    if ok and loaded then return true end
    local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    local ok2, _, _, _, _, reason = pcall(GetInfo, name)
    if ok2 and reason == "MISSING" then return false, name .. " is not installed." end
    if ok2 and reason == "DISABLED" then return false, name .. " is installed but switched off in the AddOns list." end
    return false, name .. " is not loaded on this character."
end

-- a feature works when the module and its checkbox are on and its addon is loaded
function mod.Active(f)
    return M.enabled and M.db[f.key] and (mod.AddonState(f.addon)) and true or false
end

-- "[Linen Cloth]" if the game knows the item yet, else "item 2589"
function mod.ItemText(id)
    id = tonumber(id)
    if not id then return "?" end
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, name, link = pcall(GetInfo, id)
    if ok and type(link) == "string" and not MMT.IsSecret(link) then return link end
    if ok and type(name) == "string" and not MMT.IsSecret(name) then return name end
    return "item " .. id
end

-- "1, 2, 3 and 4 more"
function mod.Summary(lines, max)
    max = max or 4
    local t = {}
    for i = 1, math.min(#lines, max) do t[i] = lines[i] end
    local s = table.concat(t, "\n")
    if #lines > max then s = s .. ("\n... and %d more"):format(#lines - max) end
    return s
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    if type(text) ~= "string" then return end
    local tag, body = text:match("^(Q[A-Z]+):(.*)$")
    local h = tag and byTag[tag]
    if not h or not mod.Active(h.f) then return end
    local ok, err = pcall(h.fn, key, sender, body)
    if not ok then M:Debug("%s from %s failed: %s", tag, tostring(key), tostring(err)) end
end)

M.OnEnable = function()
    for _, f in ipairs(mod.features) do if f.OnEnable then f.OnEnable() end end
end
M.OnDisable = function()
    for _, f in ipairs(mod.features) do if f.OnDisable then f.OnDisable() end end
end
M.OnProfileChanged = M.OnEnable
M.OnSyncReceived = M.OnEnable

SLASH_MMTQOL1 = "/mmtqol"
SlashCmdList.MMTQOL = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Quality of life is switched off (/mmt modules).") return end
    local which, cmd = msg:match("^(%a+)%s*(%a*)$")
    for _, f in ipairs(mod.features) do
        local fn = which == f.slash and f.commands and f.commands[cmd]
        if fn then
            local ok, err = fn()
            -- a command that opens something returns nothing
            if ok ~= nil or err ~= nil then MMT.Print("%s: %s", f.title, ok and "sent to the team." or tostring(err)) end
            return
        end
    end
    MMT.Print("Quality of life: /mmtqol dejunk send | reload, /mmtqol baganator send, /mmtqol auras. Settings: /mmt > Quality of life.")
    MMT.ToggleConfig("QoL")
end
