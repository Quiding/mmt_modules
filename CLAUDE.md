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
### MMT_PawnCompare (v0.2.2)
- Files: `Module.lua` (module, lifecycle, `/mmtpc`), `Scales.lua` (own Pawn scales, team sync,
  `M.store.scales[key]`), `Score.lua` (item stats + Pawn value formula), `Tooltip.lua`
  (adds lines to Item Compare's tips), `ItemTooltip.lua` (team list in GameTooltip),
  `Settings.lua` (page + debug report).
- `## OptionalDeps: Pawn, MMT_ItemCompare` (load order). Needs Item Compare active
  (`MMT.ModuleActive("ItemCompare")`), warns in chat/page if it is off or Pawn is missing.
- Integration without editing ItemCompare: `hooksecurefunc("CreateFrame")` catches the
  `MMTCompareTip<n>` frames; lines are added ONCE when Item Compare sets the header text
  (`hooksecurefunc(tip.header.text, "SetText")`), flag reset on `SetOwner` / OnTooltipCleared.
  Not Show/OnShow: the game shows the tip several times while loading the item, before the
  name is in the header (gave missing lines, then 3x duplicates). Simulation test:
  `tests/test_pawn_tooltip.py` replays Item Compare's render order. Member = parsed from `tip.header.text`,
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

### MMT_BugFixes (v0.1.1)
- Runtime fixes for OTHER modules (friend's), never editing their files. Each fix = one file +
  a `M.db` toggle registered in `mod.fixes` (shown on the page and in the debug report) + an
  upstream patch in `patches/` (made with `git diff --no-index` against a copy) for the friend.
- `CompareOverlap.lua`: ItemCompare anchors MMTCompareTip1 at GameTooltip's side, under the
  ShoppingTooltip1/2 ("Equipped"). We re-anchor tip 1 past their outer edge (or below them
  if off screen) after each layout. Patch: `patches/ItemCompare_overlap.patch`.
  The friend merged it in Item Compare 1.0.2: the fix checks the version and does nothing there.

### MMT_Cooldowns (v0.5.3) / MMT_Buffs (v0.4.6) – ports of ema_cooldowns / ema_buffs
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
  on SPELL/BAG_UPDATE_COOLDOWN, + `:b<rem>/<dur>` for the buff the use gave. Never periodic.
- `showBuffs`: a tracked spell/item's buff = buff with the SAME NAME as the cast on the user
  (player / group unit via `unitOf`, else the time from MCDU). Icon: state "buff" + glow,
  `after` = the cooldown.
  Comm is only "Send lists to team" (`MCDL` / `MBFL`, chunked).
- Lists in `M.db.lists[key]`, key = class token | "ALL" | "ROLE:<MMT role>" | "CHAR:<team key>"
  (`ListKeys.lua`, identical in both: `ListKeysFor`, `CollectEntries` with de-dup, `ListChoices`,
  `ValidListKey`). Cooldowns entry `{t="s"|"i", id, cd}`, Buffs `{id}`. Sync escapes list keys.
- Always create FontStrings WITH a template (e.g. "GameFontHighlightSmall"): SetText before a
  font is set errors ("Font not set"). The test stub enforces this.
- Settings pages are ~564 px high: check both columns still fit when adding widgets.
- `IconBars.lua` = shared window lib `MMTIconBars` (embedded-lib pattern, newest VERSION wins).
  **Both copies must stay identical** (`IconBars`, `Compat`, `Transfer`, `ListKeys`: `cmp` each pair);
  bump VERSION on change (now 5: icon/cfg `activeAlpha`; row `label`/`color`, icon `tint`/`desaturate`/`glow`/`after`, cfg `fullNames` + `lib.MemberName`). Buffs attaches to Cooldowns via `MMTIconBars.SetExtra("MMTCooldowns", ...)`.
- Buffs: group buffs count as the single one (`GROUP` in Lists.lua: Prayer of Fortitude ->
  Fortitude, Gift of the Wild, Arcane Brilliance, Prayers, Greater Blessings); `mod.Canonical(name)`
  on every scanned buff and in `BuffName`; `EntryName` keeps the entry's own name.
- Buffs missing look `allMissingLook` (PLAIN/RED/GREY) + `glowMissing` apply to ALL buff icons
  (`Look()` in Window.lua). "All classes" row (`allBar`, `allExclude`): ALL-list buffs aggregated
  over the team, removed from member rows; stays in the Buffs window even when attached.
- Import/export: `Transfer.lua` = shared lib `MMTTransfer` (identical in both, newest VERSION
  wins): own serializer + base64 + checksum, `PREFIX:sum:data` (MMTCD1 / MMTBF1), never
  loadstring. Dialog with a checkbox per section. Sections + validation in each `Export.lua`.
  Test it with lupa's Lua 5.1 (`pip install --target <scratch>/py lupa`, `from lupa.lua51 import LuaRuntime`).

### MMT_Totems (v0.1.2) – port of ema_totems
- Bars per shaman (`Bars.lua`, own frames, NOT IconBars: own slots + `MMTTotemsSequenceButton` are
  secure). ALL layout/attribute/binding changes only out of combat (`pending` + PLAYER_REGEN_ENABLED);
  in combat only textures/cooldowns/timers. Key: override binding + Bindings.xml CLICK entry
  under its OWN header MMTTOTEMS (header "MMT" belongs to Item Compare; declaring it twice warns).
  Never re-apply bindings on UPDATE_BINDINGS (setting an override fires it: loop).
- Totems: own `GetTotemInfo`; others `MTT:<slot>:<rem>/<dur>:<name>` / `MTT:<slot>:0` per change
  (PLAYER_TOTEM_UPDATE), + group `UNIT_SPELLCAST_SUCCEEDED`. Chosen totems `MTTS:<el>:<id>:<key>`,
  sequences `MTTQ:<key>=<text>`, "Send to team" `MTTP` (MMTTransfer string, chunked).
- Profile data: `selected[key][element]`, `sequences[key]`, `presets[key][name]`, `teamPresets[name]`.
- Shared files: `Compat.lua`, `Transfer.lua` (identical with Cooldowns / Buffs).
- Test: `tests/test_totems.py` loads every file of the TOC in Lua 5.1 with stubbed WoW API
  (secure frames throw in combat) and runs two clients passing messages.

## Tests (no Lua installed: Python + lupa's Lua 5.1, the same Lua as WoW)
`tests/run_all.py` (from Interface/AddOns): syntax of every module file, shared files identical,
and every `tests/test_*.py` (stubbed WoW API; Totems runs two clients passing messages).
Setup: `pip install --target <scratch>/py lupa luaparser`, `PYTHONPATH=<scratch>/py`.
Run it before every commit; add a test when fixing a bug.

## Testing
The user tests in game. Errors are caught by BugSack/!BugGrabber; ask the user to paste them.
`/mmt debug` + `/mmt debug dump` gives a report.
