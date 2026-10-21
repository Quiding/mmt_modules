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
`.gitignore`, `.gitattributes`, `README.md`, `CLAUDE.md`, `tests/`, `media/` (README pictures / gifs), and each of OUR module folders.
- `MMT`, `MMT_ItemCompare`, `MMT_LootDistribution`, `MMT_QuestTracker` belong to the
  friend: never edit or commit them. Read them for reference only.
- **New module:** create `MMT_<Name>/`, add `!/MMT_<Name>/` to `.gitignore`, list it in README.md.
- Before committing, run `git status` and make sure no other addon's files are staged.

## Git workflow
After each meaningful change: `git add -A`, commit with a short clear message, `git push`.
Changes go to the `dev` branch (since 2026-10-21, the user's choice); `main` only gets them when the user says so.

Every module .toc has `## X-Repository: https://github.com/Quiding/mmt_modules` (link in /mmt > MODULES).

## Writing MMT modules
A module is its own addon folder `MMT_<Name>` whose `.toc` has
`## Interface: 16001`, `## Dependencies: MMT`, `## X-MMT-Module: 1`, `## X-MMT-Title: <Title>`.
The core finds it automatically (shown under /mmt > MODULES). New folders and changed files
only need a `/reload` on this client (no game restart).

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
### MMT_PawnCompare (v0.3.0)
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
- `Proficiency.lua`: `mod.CanUse(key, link)` from GetItemInfoInstant classID/subclassID and Classic weapon /
  armor skills per class (mail/plate count before 40); `hideUnusable` skips those members (test_proficiency.py).
- Ideas: ring/trinket best-slot pick, showing own-scale scores without ItemCompare.

### MMT_Cooldowns (v0.8.3) / MMT_Buffs (v0.7.2) – ports of ema_cooldowns / ema_buffs
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
- Share.lua also sends `MCDU:<ek>:r` when an own cooldown becomes ready > 1.5 s early (Cold Snap,
  Preparation); a newly tracked running cooldown is announced (lists changed: `mod.ShareCheck()`);
  `MCDQ` = "send me your running cooldowns" (after taking over lists), answered by whisper.
- `showBuffs`: a tracked spell/item's buff = buff with the SAME NAME as the cast on the user
  (player / group unit via `unitOf`, else the time from MCDU); helpful auras first, then harmful ones
  (`mod.Debuff` in Compat: Death Wish is a debuff on the warrior). Icon: state "buff" + glow,
  `after` = the cooldown.
- Lists in `M.db.lists[key]`, key = class token | "ALL" | "RACE:<race token>" | "ROLE:<MMT role>" | "CHAR:<team key>"
  (`ListKeys.lua`, identical in both: `ListKeysFor`, `CollectEntries` with de-dup, `ListChoices`,
  `ValidListKey`, `RaceOf`, `AddPreset`). Cooldowns entry `{t="s"|"i", id, cd, off}`, Buffs `{id, off}`;
  `off` = in the list but not tracked. Races: own `UnitRace`, others from the heartbeat `race=<token>`
  (registered by Cooldowns only), cached in `M.store.races`. `DEFAULT_LISTS` = the presets
  (Cooldowns: class extras + `RACE:*` racials all `off`). Sync / export carry `off` ("-" suffix).
- Only register events that exist on this client (e.g. NO `LEARNED_SPELL_IN_TAB`, NO
  `COMBAT_LOG_EVENT_UNFILTERED`); `RegisterEvent` errors on unknown ones. Check another installed
  addon (EllesmereUI) uses an event before relying on it.
- Always create FontStrings WITH a template (e.g. "GameFontHighlightSmall"): SetText before a
  font is set errors ("Font not set"). The test stub enforces this.
- Settings of Cooldowns / Buffs are tabbed (`SettingsKit.lua`, identical in all three: `mod.Tabs`,
  `mod.LookTab`, `mod.ShareBar` = Import/Export bottom left under every tab, the core's Sync button bottom right (panels leave
  BOTTOM = 50 px), `mod.PresetBox`, `mod.AcceptSpellLinks(box, onLink)`): Bars / Look / lists.
  Status line just above the share bar.
- Name search: `Search.lua` (identical in Cooldowns / Buffs): the game finds
  spells BY NAME only if the character knows them, so `mod.AttachSearch(box, {items, onPick})` builds a
  session index of all names over ID ranges 1-60000, 400000-440000, 1250000-1330000 (ticker, 3000 per
  step, presets' IDs win for duplicate names) and shows a popup; `box.picked` = the chosen {t, id, text};
  `mod.FindByName` for typed exact names. Items: bags + equipped only. Test: test_search.py.
- Spell links: this client inserts shift-clicked links via `ChatFrameUtil.InsertLink`;
  `ChatEdit_InsertLink` is only a fallback. Hook through `mod.AcceptSpellLinks`.
- Presets: `Presets.lua` in each (`mod.PRESETS` {key, group = class | "RACE" | "ALL", race, name,
  entries}; `mod.DEFAULT_LISTS` built from them). Data from Wowhead Forever (nether.wowhead.com
  tooltips; 40xxxx IDs that aren't talents are Season of Discovery runes, leave them out).
  `ListKeys.lua`: `PresetChoices`, `PresetByKey`, `DefaultPreset`, `ApplyPreset(listKey, key, replace, id)`.
- Settings pages are ~564 px high: check both columns still fit when adding widgets.
- `IconBars.lua` = shared window lib `MMTIconBars` (embedded-lib pattern, newest VERSION wins).
  **Both copies must stay identical** (`IconBars`, `Compat`, `Transfer`, `ListKeys`: `cmp` each pair);
  bump VERSION on change (now 11: v11 cfg `iconZoom` = % cut off each icon edge, default 8, also used by Totems slots; v7 backdrop/border/row colours, font, timerColor; v5 icon/cfg `activeAlpha`; row `label`/`color`, icon `tint`/`desaturate`/`glow`/`after`, cfg `fullNames` + `lib.MemberName`). Buffs attaches to Cooldowns via `MMTIconBars.SetExtra("MMTCooldowns", ...)`.
- Buffs: group buffs count as the single one (`GROUP` in Lists.lua: Prayer of Fortitude ->
  Fortitude, Gift of the Wild, Arcane Brilliance, Prayers, Greater Blessings); `mod.Canonical(name)`
  on every scanned buff and in `BuffName`; `EntryName` keeps the entry's own name.
- Buffs missing look `allMissingLook` (PLAIN/RED/GREY) + `glowMissing` apply to ALL buff icons
  (`Look()` in Window.lua). "All classes" row (`allBar`, `allExclude`): ALL-list buffs aggregated
  over the team, removed from member rows; stays in the Buffs window even when attached.
- Growth direction `growth` (DOWN/UP/RIGHT/LEFT; older profiles: `vertical`): `MMTIconBars.Growth(c)`,
  reversed member order for UP/LEFT, frame pinned at `ANCHOR[growth]` (`lib.PointAt`), also in Totems.
- Settings sync = the CORE's (`sync = true` in NewModule; Totems `syncExclude = { "keybind" }`):
  button bottom right of the page, `/mmt sync <module>`, the core sends M.db, asks the receiver,
  replaces M.db, runs OnProfileChanged then `M.OnSyncReceived` (Cooldowns: ShareCheck +
  RequestRunning; Buffs: ScanGroup + Apply). No own Send-to-team messages any more (MCDA / MBFA /
  MTTA / MCDL / MBFL / MTTP were removed before release). Tests: `CORE_SYNC(M, data, from)` stub.
- Import/export: `Transfer.lua` = shared lib `MMTTransfer` (identical in both, newest VERSION
  wins): own serializer + base64 + checksum, `PREFIX:sum:data` (MMTCD1 / MMTBF1), never
  loadstring. Dialog with a checkbox per section. Sections + validation in each `Export.lua`.
  Test it with lupa's Lua 5.1 (`pip install --target <scratch>/py lupa`, `from lupa.lua51 import LuaRuntime`).

### MMT_Totems (v0.4.3) – port of ema_totems
- Bars per shaman (`Bars.lua`, own frames, NOT IconBars: own slots + `MMTTotemsSequenceButton` are
  secure). ALL layout/attribute/binding changes only out of combat (`pending` + PLAYER_REGEN_ENABLED);
  in combat only textures/cooldowns/timers. Key: override binding + Bindings.xml CLICK entry
  under its OWN header MMTTOTEMS (header "MMT" belongs to Item Compare; declaring it twice warns).
  Never re-apply bindings on UPDATE_BINDINGS (setting an override fires it: loop).
- Totems: own `GetTotemInfo`; others `MTT:<slot>:<rem>/<dur>:<name>` / `MTT:<slot>:0` per change
  (PLAYER_TOTEM_UPDATE), + group `UNIT_SPELLCAST_SUCCEEDED`. Chosen totems `MTTS:<el>:<id>:<key>`,
  sequences `MTTQ:<key>=<text>`; everything at once via the core sync.
- Learned totems: own via IsPlayerSpell / IsSpellKnown (all missing -> show all); others send
  `MTTK:<ids>` at login / on learning, stored in `M.store.known[key]`; no list yet -> show all.
  Chooser + preset editor filter by it, own casting skips unlearned chosen totems.
- Looks like the IconBars rows: name LEFT of the icons in one shared name column (grouped;
  own width ungrouped), above them when vertical; same timer text (tenths under 10 s).
- Slots: `mod.SlotShown(key, element)` (Known.lua): `hiddenElements`, `hideNoItem` (totem items
  5175-5178, own via GetItemCount on BAG_UPDATE_DELAYED; others from `MTTK:<ids>;<letters EFWA>`,
  `M.store.items[key]`, no ";" = older client = unknown), `hideUnlearned`. Sequence skips no-item elements.
- Sequence editor = four element buttons ("<>" swaps, right-click leaves one out), `mod.SequenceOrder` / `mod.SequenceText` in Data.lua; stored as text.
- Profile data: `selected[key][element]`, `sequences[key]`, `presets[key][name]`, `teamPresets[name]`.
- Shared files: `Compat.lua`, `Transfer.lua`, `SettingsKit.lua` (identical with Cooldowns / Buffs).
- Settings tabs Bars / Look (`mod.LookTab` + inactiveAlpha, alpha) / Casting & presets; one status line.
- Look like IconBars: `Skin`/`Media` copied into Bars.lua (BackdropTemplate container + bars).
  Grouped: frame bg+border, `rowColor`/`rowAlpha` per bar, `bgTint` on textures; ungrouped: each bar gets bg+border
  (content inset by the border). Font = `M.db.font` via `MMT.ApplyFont`. Export "look" has the same keys.
- Test: `tests/test_totems.py` loads every file of the TOC in Lua 5.1 with stubbed WoW API
  (secure frames throw in combat) and runs two clients passing messages.

### MMT_Whispers (v0.1.3) – like EMA Talk (credit EMA / EbonyFaye in descriptions; EMA is "All Rights Reserved": never copy its code)
- Files: `Module.lua` (defaults, `/mmtw`), `Forward.lua` (alts: CHAT_MSG_WHISPER / _INFORM / BN_WHISPER / BN_WHISPER_INFORM,
  `mod.Receivers()` from `to` = LEADER (group, default) | FTL (`MMT.FTLLeader()`, sent with `MMT.SendToLeader`) | CHAR:<key> | ROLE:<role>;
  profiles that got FTL as default in 0.1.1/0.1.2 go back to LEADER once (`toLeader` flag), pass-on of the receiver's whispers,
  `mod.recentSenders`), `Display.lua` (receiver: MWF assembly, `mod.Show`, `mod.SetReply`), `Settings.lua`.
- Comm: `MWF:<id>:<part>:<total>:<kind>:<flags>:<name>:<text>` (kinds W I B b N, flag G = GM) by WHISPER to
  online receivers only. Secret texts/names stay on the alt. Skipped whispers (`<...>`, ignore words) aren't
  remembered as reply targets. `sync = true`, `syncExclude = { "chatFrame" }`.
- Reply target: `ChatFrameUtil.SetLastTellTarget` (fallback `ChatEdit_SetLastTellTarget`), pcall; sending:
  `C_ChatInfo.SendChatMessage` (fallback `SendChatMessage`), BN via `BNSendWhisper`.
- Test: `tests/test_whispers.py` (two clients, Anna = leader/receiver, Bob = alt).

### MMT_TeamGear (v0.1.0)
- Files: `Module.lua` (data: reads Item Compare's `MMTDB.moduleData.ItemCompare.equipment[key]` READ ONLY,
  members, class/level from `MMT.status`, `UnitOf` for the model, `/mmtgear`), `Window.lua` (inspect-like
  window `MMTTeamGearWindow`, slots LEFT/RIGHT/BOTTOM, `mod.ItemData`, redraw on GET_ITEM_INFO_RECEIVED and
  Item Compare's `EQUIPMENT_CHANGED`), `Button.lua` (button on `CharacterFrame`, shift-drag, `buttonPoint`
  offsets from its TOPLEFT; member list via `MMT.UI.OpenList`), `Settings.lua`. Sends nothing.
- Item Compare's store is account-wide per character and never pruned (only its Clear), so `mod.Groups()`
  lists: this team, other profiles' teams (`MMTDB.profiles[name].team`, read only, skips `MMT.profileName`),
  then every other stored character (`others` setting, default off; headers "Team N (<profile>)",
  members indented with "-"). `mod.AllKeys()` = that order for < >.
- Looks: real appearance can't be cached (no API). Heartbeat `tgl=<raceID>.<sex>`, units in sight read
  directly, `M.store.looks[key]`; out of sight `mod.Mannequin`: DressUpModel `SetCustomRace(race, sex - 2)`,
  `Undress`, `TryOn` each stored item (after OnModelLoaded / 0.1 s).
- `Overview.lua`: whole team at once (`mod.OpenOverview`, list entry `__ALL__`, `/mmtgear all`), rows of
  17 slot icons (no shirt/tabard), same `mod.AllKeys()` order, max 20 rows.
- New frames start SHOWN: `f:Hide()` at the end of Build, and place a window when it has no point yet
  (`not f:GetPoint(1)`), or it is "shown" without an anchor and invisible (test stub frames start shown too).
- Never add frames to `UISpecialFrames` (taints the game menu): `MMT.UI.CloseOnEscape`.
- Test: `tests/test_teamgear.py` (stand-in frames: read optional fields with `rawget`).

### MMT_TeamInventory (v0.4.2)
- Files: `Module.lua` (store `M.store.chars[key] = {b, k, m, e = {[itemID] = n}, hash, time}`, `M.store.mine[key]`
  = characters of this account, `mod.CountOf`), `Scan.lua` (bags incl. ReagentBag/Keyring, bank =
  `Enum.BagIndex.CharacterBankTab_1..9` (fallback Bank + 5..11) ONLY while open, mail only while
  `MailFrame` is shown; never rescan after closing: it would read as empty), `Sync.lua`, `Tooltip.lua`, `Settings.lua`.
- Comm: heartbeat `tiv=<hash>`, `TIVREQ` (whisper, 60 s cooldown), `TIVS:<hash>#b=id x n,...;k=...` via
  `MMT.SendLong` (BULK), `TIVD:<hash>#b13446=4;k...` deltas to the team (snapshot if > 240 bytes).
- Tooltip: `TooltipDataProcessor.AddTooltipPostCall(Item)` installed at PLAYER_LOGIN (after Syndicator's, so
  below its block); fallback OnTooltipSetItem. With Syndicator (`withSyndicator`): OTHERS = only characters
  not in `mine`, total over everyone; ALL; OFF. Syndicator's own data is private (no injection into it).
- `Bags.lua`: team bags window `MMTTeamBagsWindow` (character picker incl. `__ALL__` = summed, `__BYCHAR__` = a section per character in category order, tabs b/k/m/e,
  search, `mod.CATEGORIES` = Baganator's default Classic order by GetItemInfoInstant classID, quality 0 = Junk
  last; lines = headers + rows of 10; the window grows to fit, scrolls by line only past the screen height) and the own minimap button
  `MMTTeamBagsMinimapButton` (`minimapAngle`, left bags / right bank, drag). Keys: `Bindings.xml` (own header
  MMTTEAMINV) -> global `MMTTeamInventory_Toggle(place, who)`.
- `BaganatorCats.lua`: with Baganator on, `mod.BaganatorGroups(slots)` reads `BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE]`
  (category_display_order, custom_categories, category_modifications priority / addedItems "i:<id>",
  category_hidden) READ ONLY on every draw; default_* searches rebuilt like Baganator's Forever defaults
  (its definitions are private); matching = `Syndicator.Search.CheckItem(GetBaseInfo{...}, search)`, highest
  priority wins (prio = offset + (mod.priority+1)*200, ties by order). Auto categories skipped. Any problem: nil
  -> built-in `mod.Group`. Setting `baganatorCats`.
- `Give.lua`: planned gifts. Bags tab, one character or BYCHAR: drag a slot (`OnDragStart/Stop`; drop zones =
  the side panel `f.team` beside the window (`mod.RefreshTeam`: `f.teamButtons` = every team member, click = their
  bags, "+n" incoming; then `f.pairRows` = one block per `mod.GiftPairs` pair with Trade, "x" (`mod.CancelGifts`) and
  small item icons (right-click cancels one); `mod.PlaceTeam` flips it left at the screen edge, also while the window
  is dragged (OnUpdate while `isMoving`)), then `f.bands` per character section; Shift = amount box `MMTTeamBagsAmount`); `M.store.gives[from][to][id] = {n, t}`
  (t = GetServerTime, newest wins, n = 0 kept a week as tombstone). `TIVG:<id>:<n>:<t>:<from>:<to>` to the team,
  whispered to a member the first time they're seen online (XP_RECEIVED). `mod.BagSlots` (one char, "b"):
  giver's count minus `PlannedOut` plus dimmed `outgoing` slots (receiver's name), receiver gets glowing `planned`
  slots (giver's name, `b.tag`); both first in BYCHAR, right-click cancels. The panel's "Trade" button: `TIVT:<from>:<to>` -> the giver's client
  `InitiateTrade(unit)` (works from an addon message, user-tested with party1), unit from `mod.UnitOf`
  (partyN / raidN, then friendly nameplates, matched by `MMT.SplitUnit` key: same first names!); not found -> `TIVN` whispered back.
  Trade: TRADE_SHOW -> `mod.FillTrade` after the CORE's own Trade.lua fill (it precomputes free slots: we wait
  2.2 s when `MMT.db.trade.enabled`, read only), Split/PickupContainerItem + ClickTradeButton, skips bound/locked,
  counts what's already in the trade. Completion: our trade slots read every 0.25 s while open, applied on
  UI_INFO_MESSAGE == ERR_TRADE_COMPLETE (TRADE_ACCEPT_UPDATE etc. not confirmed on this client). Setting `giveTrade`;
  `autoAccept`: the watcher calls `AcceptTrade` (works from a timer, per the user) when `mod.TradeIsPlanned()`: only
  planned items each side (<= plan), giver has nothing left to add (`Steps` empty), no gold, slot 7 empty, unchanged
  1.5 s; a change re-arms it. Game confirmation popups stay manual;
  "Planned items" button under TradeFrame.
- Tests: `tests/test_teaminventory.py` (two clients, incl. gifts + trade), `tests/test_teambags.py` (window, Baganator categories, drag, stand-ins).

### Reset to defaults (every module)
- Cooldowns / Buffs / Totems: `mod.ResetSettings()` + the button in `mod.ShareBar` (SettingsKit), between
  Import / Export and the core's Sync button. Others: a local `ResetButton(page, done)` in their settings
  (left of the Sync button when `M.sync`, else bottom right). Both use `H.ConfirmButton` (click twice), wipe
  `M.db` IN PLACE (the core holds that table), copy `M.defaults`, run OnProfileChanged.

## Tests (no Lua installed: Python + lupa's Lua 5.1, the same Lua as WoW)
`tests/run_all.py` (from Interface/AddOns): syntax of every module file, shared files identical,
and every `tests/test_*.py` (stubbed WoW API; Totems runs two clients passing messages).
Setup: `pip install --target <scratch>/py lupa luaparser`, `PYTHONPATH=<scratch>/py`.
Run it before every commit; add a test when fixing a bug. It also lints `local a, b = x and f()`
(keeps only f's first value: bit us twice).

## Testing
The user tests in game. Errors are caught by BugSack/!BugGrabber; ask the user to paste them.
`/mmt debug` + `/mmt debug dump` gives a report.
