-- MMT module: Pawn Compare (skeleton / test version).
--
-- Uses only the documented MMT module API (see /mmt help > Writing modules
-- and Team communication), so core updates shouldn't break it.
--
-- Test it:
--   1. /mmt  -> MODULES -> Pawn Compare should be listed with a settings page.
--   2. Press "Say hello to team" (or /mmtpc hello): every team client running
--      this module answers, and the answers are printed in chat.
--   3. /mmt debug dump contains a "Pawn Compare" section.

local _, mod = ...
local MMT = MMT

-- message tags: unique prefix so we never clash with core/other modules
local TAG_HELLO = "PCMP_HI"
local TAG_REPLY = "PCMP_OK"

local M = MMT.NewModule({
    name = "PawnCompare",
    title = "Pawn Compare",
    description = "Compare items for every team member using Pawn scales (early test version).",
    defaults = {
        greetOnLogin = true,
    },
})
mod.M = M

local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("MMT_PawnCompare", "Version") or "?"

local function PawnLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return isLoaded and isLoaded("Pawn") and true or false
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
M.OnEnable = function()
    if M.db.greetOnLogin then  -- always read M.db fresh (it changes with the profile)
        MMT.Print("Pawn Compare %s loaded. Pawn %s.", VERSION, PawnLoaded() and "found" or "not found")
    end
    M:Debug("enabled")
end

M.OnDisable = function()
    M:Debug("disabled")
end

---------------------------------------------------------------------------
-- Team test: hello / reply over the core's team communication
---------------------------------------------------------------------------
function mod.SayHello()
    MMT.SendToTeam(TAG_HELLO .. ":" .. VERSION, true)
    MMT.Print("Pawn Compare: hello sent to the team, waiting for answers...")
end

M:Listen("TEAM_MESSAGE", function(key, sender, text)
    local v = text:match("^" .. TAG_HELLO .. ":(.*)$")
    if v then
        MMT.SendAddon(TAG_REPLY .. ":" .. VERSION .. ":" .. (PawnLoaded() and "1" or "0"), "WHISPER", sender)
        return
    end
    local rv, pawn = text:match("^" .. TAG_REPLY .. ":([^:]*):(%d)$")
    if rv then
        MMT.Print("Pawn Compare: %s answered (module %s, Pawn %s).",
            MMT.FullDisplay(key), rv, pawn == "1" and "found" or "not found")
    end
end)

SLASH_MMTPAWNCOMPARE1 = "/mmtpc"
SlashCmdList.MMTPAWNCOMPARE = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Pawn Compare is switched off (/mmt modules).") return end
    if msg == "hello" then
        mod.SayHello()
    else
        MMT.Print("Pawn Compare %s - Pawn %s. /mmtpc hello = test team communication.",
            VERSION, PawnLoaded() and "found" or "not found")
    end
end

---------------------------------------------------------------------------
-- Settings page (MODULES > Pawn Compare in /mmt)
---------------------------------------------------------------------------
M.Page = function(_, page)
    local col = MMT.UI.Column(page, 0, 0, MMT.ConfigHelpers.COL_W)
    col:Header("Pawn Compare")
    col:Note("Early test version. Pawn: " .. (PawnLoaded() and "found." or "not found."))
    col:Check("Message in chat on login",
        function() return M.db.greetOnLogin end,
        function(v) M.db.greetOnLogin = v end)
    col:Button("Say hello to team", function() mod.SayHello() end)
end

---------------------------------------------------------------------------
-- Debug report (/mmt debug dump)
---------------------------------------------------------------------------
M.Report = function(_, add)
    add(("Pawn Compare %s: enabled=%s pawn=%s greetOnLogin=%s"):format(
        VERSION, tostring(M.enabled), tostring(PawnLoaded()), tostring(M.db.greetOnLogin)))
end
