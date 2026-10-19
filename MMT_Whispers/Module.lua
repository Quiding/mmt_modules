-- MMT module: Whispers.
-- Whispers your alts get show up on the character you play (the receiver),
-- and you answer them through the alt. Idea from EMA's Talk module, written
-- new for MMT.
--
--   Forward.lua   the alts: send whispers on to the receiver (MWF), pass the
--                 receiver's whispers on to whoever whispered the alt
--   Display.lua   the receiver: puts them in a chat window, sets the reply target
--   Settings.lua  settings page and debug report

local _, mod = ...
local MMT = MMT

mod.VERSION = "0.1.0"

local M = MMT.NewModule({
    name = "Whispers",
    title = "Whispers",
    description = "Whispers to your alts show up on the character you play; answer them through the alt. Inspired by EMA's Talk module (EbonyFaye).",
    sync = true,                   -- the core's "Sync to team" sends M.db ...
    syncExclude = { "chatFrame" }, -- ... except the chat window (each client has its own)
    defaults = {
        forward = true,            -- alts send whispers on to the receiver
        to = "LEADER",             -- LEADER | CHAR:<team key> | ROLE:<MMT role>
        informs = true,            -- also what the alts whisper to others
        bn = false,                -- Battle.net whispers too
        skipAddon = true,          -- "<DBM> ..." style automatic answers stay on the alt
        ignore = "",               -- comma separated: whispers containing one stay on the alt
        relay = true,              -- whispering an alt from the receiver passes it on
        chatFrame = 1,             -- receiver: ChatFrame<n>
        stamp = true,
        sound = true,
        reply = "ALT",             -- R key: ALT (through the alt) | DIRECT (from you) | NONE
    },
})
mod.M = M

SLASH_MMTWHISPERS1 = "/mmtw"
SLASH_MMTWHISPERS2 = "/mmtwhispers"
SlashCmdList.MMTWHISPERS = function(msg)
    msg = (msg or ""):lower()
    if not M.enabled then MMT.Print("Whispers is switched off (/mmt modules).") return end
    if msg == "test" then
        local own = MMT.PlayerFull()
        mod.Show(own, UnitName("player"), "W", "", "Somebody", "This is how a forwarded whisper looks.", true)
        mod.Show(own, UnitName("player"), "I", "", "Somebody", "And this is what your alt answered.", true)
    else
        MMT.Print("Whispers: /mmtw test shows two example lines. Settings: /mmt > Whispers.")
        MMT.ToggleConfig("Whispers")
    end
end
