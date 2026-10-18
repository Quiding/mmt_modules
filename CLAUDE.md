# CLAUDE.md – Quiding's MMT modules

## What this is
Modules (plugins) for **MMT – Manage My Team**, a multiboxing addon for
World of Warcraft: Forever (interface `16001`, Lua 5.1 WoW API).
- MMT core (NOT ours, written by a friend): https://github.com/bnetworking/MMT
- This repo (ours): https://github.com/Quiding/quiding_mmt_modules (branch `main`)

## Repo layout – IMPORTANT
This git repo lives **directly in `Interface/AddOns`**, which also contains many
other addons (Pawn, Details, Questie, the MMT core, the friend's MMT_* modules...).
`.gitignore` ignores everything (`/*`) and whitelists only our files:
`.gitignore`, `.gitattributes`, `README.md`, `CLAUDE.md`, and each of OUR module folders.
- `MMT`, `MMT_ItemCompare`, `MMT_LootDistribution`, `MMT_QuestTracker` belong to the
  friend: never edit or commit them. Read them for reference only.
- **New module:** create `MMT_<Name>/`, add `!/MMT_<Name>/` to `.gitignore`, list it in README.md.
- Before committing, run `git status` and make sure no other addon's files are staged.

## Git workflow
After each meaningful change: `git add -A`, commit with a short clear message, `git push`.

## Writing MMT modules
A module is its own addon folder `MMT_<Name>` whose `.toc` has
`## Interface: 16001`, `## Dependencies: MMT`, `## X-MMT-Module: 1`, `## X-MMT-Title: <Title>`.
The core finds it automatically (shown under /mmt > MODULES). A NEW folder needs a full
game restart; changes to existing files only need `/reload`.

Use ONLY the documented API (see /mmt help > "Writing modules" / "Team communication",
source in `MMT/Help.lua` and `MMT/Modules.lua`) so core updates don't break us:
- `local M = MMT.NewModule{ name, title, description, defaults }`
- `M.db` per-profile settings – always read `M.db.x` fresh, never cache `M.db` in a local
  (the core replaces it on profile change). `M.store` = account-wide storage.
- `M.OnEnable`, `M.OnDisable` (stop timers/hide frames), `M.OnProfileChanged`
- `M:On(event, fn)`, `M:Listen(callback, fn)` – only fire while the module is on
- `M:Heartbeat(key, fn)` – tiny values only, no `:` `,` `=`; heartbeat message is capped at 255 bytes
- `M.Page = function(self, page)` settings page (use `MMT.UI.Column`, `MMT.ConfigHelpers.COL_W`)
- `M.Report = function(self, add)` lines for /mmt debug dump; `M:Debug(fmt, ...)`
- Comm: `MMT.SendToTeam(msg, onlyOnline)`, `MMT.SendAddon(msg, "WHISPER", sender)`,
  receive via `M:Listen("TEAM_MESSAGE", function(key, sender, text) end)`.
  Messages < 250 bytes, prefixed with OUR OWN tag (taken by core: XP, XP2, BYE, PING, PONG,
  SYNC, EQREQ, EQD, EQS, QNQ, QNA, LH, LHGO, QTREQ, QTS, QTD, QTAB).
- Helpers: `MMT.Print`, `MMT.FirstName(key)`, `MMT.FullDisplay(key)`, `MMT.SortedMembers()`,
  `MMT.IsOnline(key)`, `MMT.IsSelf(key)`, `MMT.PlayerFull()`, `MMT.HoverMember`, read-only `MMT.status[key]`.
- Do not write to `MMT.db` or other core internals.

## Modules
### MMT_PawnCompare (v0.2.0)
- Files: `Module.lua` (module, lifecycle, `/mmtpc`), `Scales.lua` (own Pawn scales, team sync,
  `M.store.scales[key]`), `Score.lua` (item stats + Pawn value formula), `Tooltip.lua`
  (adds lines to Item Compare's tips), `ItemTooltip.lua` (team list in GameTooltip),
  `Settings.lua` (page + debug report).
- `## OptionalDeps: Pawn, MMT_ItemCompare` (load order). Needs Item Compare active
  (`MMT.ModuleActive("ItemCompare")`), warns in chat/page if it is off or Pawn is missing.
- Integration without editing ItemCompare: `hooksecurefunc("CreateFrame")` catches the
  `MMTCompareTip<n>` frames, `OnShow` adds the lines. Member = parsed from `tip.header.text`,
  equipped item = `tip:GetItem()`, hovered item = GameTooltip's item.
- Scores: Pawn's `PawnGetItemData(link).Stats` if Pawn is loaded, else `GetItemStats` mapped to
  Pawn stat names (approximate). Value = sum(stat*weight), SpeedBaseline, unusable (-1000000),
  normalization like Pawn. Sockets ignored. A hovered 2H is compared vs MH + OH on the main-hand tip; the OH comes
  from Item Compare's stored equipment (`MMTDB.moduleData.ItemCompare.equipment[key].items[17]`, read only).
- ItemTooltip: hooks the same GameTooltip Set* methods as Pawn, installed at PLAYER_LOGIN after
  Pawn's, so our lines follow Pawn's. `teamTooltip` = REPLACE wraps the global
  `PawnAddValuesToTooltip` to skip GameTooltip (only for equippable items while own scales exist).
  Rings/trinkets: vs the weaker slot; 1H: MH, or OH if a weapon is there; 2H: MH + OH.
- Comm: heartbeat `pcs=<scale hash>`, `pcn=1` (no Pawn); `PCMP_REQ`, chunked `PCMP_S:id:i:n:data`.
- Ideas: ring/trinket best-slot pick, showing own-scale scores without ItemCompare.

### MMT_BugFixes (v0.1.0)
- Runtime fixes for OTHER modules (friend's), never editing their files. Each fix = one file +
  a `M.db` toggle registered in `mod.fixes` (shown on the page and in the debug report) + an
  upstream patch in `patches/` (made with `git diff --no-index` against a copy) for the friend.
- `CompareOverlap.lua`: ItemCompare anchors MMTCompareTip1 at GameTooltip's side, under the
  ShoppingTooltip1/2 ("Equipped"). We re-anchor tip 1 past their outer edge (or below them
  if off screen) after each layout. Patch: `patches/ItemCompare_overlap.patch`.
  Remove the fix once the friend ships the patch.

### MMT_Cooldowns (v0.2.2) / MMT_Buffs (v0.2.0) – ports of ema_cooldowns / ema_buffs
- **This client forbids `COMBAT_LOG_EVENT_UNFILTERED`** (WoW: Forever runs on the modern client:
  registering it raises ADDON_ACTION_FORBIDDEN, blamed on MMT). Never register it. Values can be
  "secret" (`MMT.IsSecret`), guard unit/aura/spell data with it.
- **Old globals don't exist here**: no `GetSpellInfo`, `GetSpellCooldown`, `UnitBuff`, ...
  Use `Compat.lua` (`mod.SpellInfo`, `mod.SpellIcon`, `mod.SpellCooldown`, `mod.Buff`,
  `mod.ItemSpell`; C_Spell / C_UnitAuras first, old globals as fallback, "secret" handled).
  Same file in MMT_Cooldowns and MMT_Buffs, keep identical.
- **No addon messages for live data** (user's decision: would flood comms). Cooldowns:
  `UNIT_SPELLCAST_SUCCEEDED` on party/raid units (spell ID -> name) + duration from the list;
  "after buff" spells (NS, EM, PoM, Inner Focus) start when the buff is gone (`UNIT_AURA` +
  `UnitBuff`); own character via `GetSpellCooldown`/`GetItemCooldown`. Buffs: `UnitBuff` on
  group units (exact). Buffs of members outside the group can't be tracked.
- Exception agreed with the user: Cooldowns `Share.lua` sends ONE message per use of a tracked
  cooldown (`MCDU:<s|i><id>:<rem>/<dur>` or `:a` for after-buff spells), from own state changes
  on SPELL/BAG_UPDATE_COOLDOWN. Never periodic.
  Comm is only "Send lists to team" (`MCDL` / `MBFL`, chunked).
- Lists in `M.db.lists[CLASS|ALL]`; Cooldowns entry `{t="s"|"i", id, cd}`, Buffs `{id}`.
- `IconBars.lua` = shared window lib `MMTIconBars` (embedded-lib pattern, newest VERSION wins).
  **Both copies must stay identical** (`cmp MMT_Cooldowns/IconBars.lua MMT_Buffs/IconBars.lua`);
  bump VERSION on change (now 2: row `label`/`color`, icon `tint`/`desaturate`). Buffs attaches to Cooldowns via `MMTIconBars.SetExtra("MMTCooldowns", ...)`.
- Buffs "All classes" row (`allBar`, `allMissingLook`, `allExclude`): ALL-list buffs aggregated
  over the team, removed from member rows; stays in the Buffs window even when attached.
- Combat-log names -> team keys: `MMT.Resolve(MMT.NameFromGUID(guid, name))`, cached per GUID.

## Syntax check (no Lua installed)
`pip install --target <scratch>/py luaparser`, then `ast.parse()` every `*.lua` of our modules.

## Testing
The user tests in game. Errors are caught by BugSack/!BugGrabber; ask the user to paste them.
`/mmt debug` + `/mmt debug dump` gives a report.
