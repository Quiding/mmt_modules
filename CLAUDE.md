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
`.gitignore`, `.gitattributes`, `.pkgmeta`, `README.md`, `CLAUDE.md`, `tests/`, `tools/`, `media/` (README pictures / gifs), and each of OUR module folders.
- `MMT`, `MMT_ItemCompare`, `MMT_LootDistribution`, `MMT_QuestTracker`, `MMT_ItemBar`, `MMT_Statistics` (every `MMT*`
  folder in MMT-src) belong to the friend: never edit or commit them. Read them for reference only.
- **New module:** create `MMT_<Name>/`, add `!/MMT_<Name>/` to `.gitignore`, a move-folders line to `.pkgmeta`, list it in README.md.
- Before committing, run `git status` and make sure no other addon's files are staged.
- Downloads hold only the `MMT_*` folders: `.gitattributes` `export-ignore`s tests/, media/, tools/, CLAUDE.md and the
  git / packager files (GitHub's Download ZIP, release archives). CurseForge zip: `python tools/make_release.py [ref]`
  (git archive of every MMT_* folder -> `dist/QMMTModules-<date>-<sha>.zip`, prints each module's version);
  `.pkgmeta` (package-as QMMTModules + move-folders, one line per module) is for CurseForge's packager if it's ever
  hooked up - add new modules there too.

## Git workflow
After each meaningful change: `git add -A`, commit with a short clear message, `git push`.
Changes go to the `dev` branch (since 2026-10-21, the user's choice); `main` only gets them when the user says so.

## Game folder
WoW: Forever runs from **`D:\Games\World of Warcraft\_forever_\Interface\AddOns`** (this clone). The old
`_classic_beta_` folder is retired (since 2026-10-25): no sync hooks any more, don't update or use it.
- The friend's MMT core + modules (`MMT`, `MMT_ItemCompare`, `MMT_LootDistribution`, `MMT_QuestTracker`, `MMT_ItemBar`)
  are NTFS **junctions** to `D:\Games\MMT-src\<name>` (a clone of github.com/bnetworking/MMT): update them with
  `git -C D:/Games/MMT-src pull`. Never edit them there either. (Until 2026-10-26 `_forever_` had plain copies by
  mistake, so pulls only reached `_classic_beta_`; the old copies are in `D:\Games\MMT-forever-old-copies`.) A new
  module in MMT-src needs its own junction: `New-Item -ItemType Junction -Path <AddOns>\<name> -Target D:\Games\MMT-src\<name>`.
  **`D:\Games\Update-MMT.ps1`** (2026-10-29) does both: `git pull` in MMT-src, then a junction for every `MMT*` folder
  there (new modules too); a real folder in the way is MOVED to `D:\Games\MMT-forever-old-copies\<date>`, never deleted
  (`-NoPull` = links only). Needed on 2026-10-29: something unknown (on 2026-10-27 18:13) had replaced the junctions with
  plain MMT 0.9.27 copies, and deleting through a junction removed `MMT/Media/*.tga` from MMT-src's working tree.

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
- Key bindings (core's CreateModules.md "Key bindings", core 0.9.31+): `Bindings.xml` in the module folder, NOT in
  the TOC; `category="BINDING_CATEGORY_MMT"` on every binding (the core sets the group title "MMT (Manage My Team)");
  the first binding gets an own header `MMT_<NAME>` (never "MMT": the core's); texts in Lua:
  `BINDING_HEADER_MMT_<NAME> = "<Title>"`, `BINDING_NAME_<binding name>`. Never rename a binding name (players'
  keys are saved by it). Bindings.xml changes need a game restart. `tests/run_all.py` lints all of this.
- Comm: `MMT.SendToTeam(msg, onlyOnline)`, `MMT.SendAddon(msg, "WHISPER", sender)`,
  receive via `M:Listen("TEAM_MESSAGE", function(key, sender, text) end)`.
  Messages < 250 bytes, prefixed with OUR OWN tag (taken by core: XP, XP2, BYE, PING, PONG,
  SYNC, EQREQ, EQD, EQS, QNQ, QNA, LH, LHGO, QTREQ, QTS, QTD, QTAB).
- Helpers: `MMT.Print`, `MMT.FirstName(key)`, `MMT.FullDisplay(key)`, `MMT.SortedMembers()`,
  `MMT.IsOnline(key)`, `MMT.IsSelf(key)`, `MMT.PlayerFull()`, `MMT.HoverMember`, read-only `MMT.status[key]`.
- Do not write to `MMT.db` or other core internals.

## Modules
### MMT_PawnCompare (v0.5.1)
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
- `sync = true` (core Sync button, nothing per client), `M.OnSyncReceived` = `PawnResetTooltips` + PAWN_SCALES_CHANGED.
- `Manage.lua` (0.4.0): window `MMTPawnScalesWindow` (`mod.OpenScales`, `/mmtpc scales`, button on the page).
  Pawn's API (PawnCommon is ACCOUNT-wide, visibility per character): `PawnGetAllScalesEx` {Name, LocalizedName,
  IsVisible, IsProvider}, `PawnDoesScaleExist`, `PawnScaleIsReadOnly` (= provider scale: only hideable, never
  deletable), `PawnDeleteScale(name)` (custom only; no event). After deleting we clear `PawnUICurrentScale` if it
  was deleted and refresh Pawn's UI if shown (as its own Delete button does), then `mod.UpdateOwn(true)` = PCMP_S.
  `mod.ScaleRows(showHidden)` = own scales shown in Pawn (all own with the session-only "Show hidden" check) + team-only
  names (the team shares DISPLAY names: matched by name or LocalizedName; a team name that is a built-in scale here,
  shown or hidden, is built-in). Row `action`: custom = "del" (PawnDeleteScale), built-in = "hide" (PawnSetScaleVisible
  false: per character; Forever's Pawn has no automatic spec mode - `VgerCore.SpecsExist` false - so it stays hidden),
  hidden built-in = "show". `mod.ApplyLocal(action, names)`, `mod.SendAction` -> `PCMP_DEL` / `PCMP_HIDE` / `PCMP_SHOW`
  `:<escaped>~<escaped>` (< 240 bytes each); receivers resolve names with `mod.FindScale` (name or display name),
  do what `mod.Target` allows, asking first (`askDelete`; not while the core's `MMTDB.autoAcceptSync` is on, read only; one `MMT.UI.Confirm` per sender, later requests queue);
  members offline then: `M.store.pendingDel[key] = { del, hide, show = {[name]=true}, time }` (0.4.0: `names` = del),
  whispered on their next XP_RECEIVED (14 days). The window is FULLSCREEN_DIALOG + Toplevel (MMT's settings are DIALOG) and takes the opening button's
  effective scale / UIParent's (else `MMT.ConfigScale()`): popups parented to UIParent must match MMT's window scale. Test: test_pawn_scales.py (two clients + stand-in Pawn); the window is built in test_settings.py.
- `Proficiency.lua`: `mod.CanUse(key, link)` from GetItemInfoInstant classID/subclassID and Classic weapon /
  armor skills per class (mail/plate count before 40); `hideUnusable` skips those members (test_proficiency.py).
- Ideas: ring/trinket best-slot pick, showing own-scale scores without ItemCompare.

### MMT_CooldownTimers (v0.14.10) / MMT_BuffTimers (v0.17.11) – ports of ema_cooldowns / ema_buffs
- Renamed 2026-10-25 (the user plans a real buff module): module names "CooldownTimers" / "BuffTimers", titles
  "Cooldown Timers" / "Buff Timers", slash `/mmtct` / `/mmtbt`. Old names "Cooldowns" / "Buffs": `TakeOver()` in each
  Module.lua (OnEnable + OnProfileChanged) copies `MMT.db.modules[OLD]` (READ only) into M.db once per profile and
  `MMTDB.moduleData[OLD]` into M.store once (`takenFrom`, in syncExclude). Comm tags (MCD*, MBF*), heartbeat keys,
  export prefixes (MMTCD1 / MMTBF1) and frame names (MMTCooldowns / MMTBuffs) are unchanged.
- **This client forbids `COMBAT_LOG_EVENT_UNFILTERED`** (WoW: Forever runs on the modern client:
  registering it raises ADDON_ACTION_FORBIDDEN, blamed on MMT). Never register it. Values can be
  "secret" (`MMT.IsSecret`), guard unit/aura/spell data with it.
- **Old globals don't exist here**: no `GetSpellInfo`, `GetSpellCooldown`, `UnitBuff`, ...
  Use `Compat.lua` (`mod.SpellInfo`, `mod.SpellIcon`, `mod.SpellCooldown`, `mod.Buff`,
  `mod.ItemSpell`, `mod.SpellIconAny` = icon by ID else by name; C_Spell / C_UnitAuras first, old globals as fallback, "secret" handled). **Spell data is lazy**: right after login
  GetSpellInfo can be nil for spells the character never used (Battle Shout showed "missing" while on). Buffs' scan keeps
  EVERY buff (no index filter), `BuildIndex` requests unknown spells (C_Spell.RequestLoadSpellData); Cooldowns rebuilds
  its index when a cast comes in while something was missing. Buffs `EntryIcon` also falls back to the icon the buff had when last seen (`M.store.icons`, Tracker `mod.SeeIcon`): some spell IDs have no texture on this client (Seal of Righteousness showed "?").
  Same file in MMT_CooldownTimers and MMT_BuffTimers, keep identical.
- **No addon messages for live data** (user's decision: would flood comms). Cooldowns:
  `UNIT_SPELLCAST_SUCCEEDED` on party/raid units (spell ID -> name) + duration from the list;
  "after buff" spells (NS, EM, PoM, Inner Focus) start when the buff is gone (`UNIT_AURA` +
  `UnitBuff`); own character via `GetSpellCooldown`/`GetItemCooldown`. Buffs: `UnitBuff` on
  group units (exact). Buffs of members outside the group can't be tracked.
- Exception agreed with the user: Cooldowns `Share.lua` sends ONE message per use of a tracked
  cooldown (`MCDU:<s|i><id>:<rem>/<dur>` or `:a` for after-buff spells), from own state changes
  on SPELL/BAG_UPDATE_COOLDOWN, + `:b<rem>/<dur>` for the buff the use gave. Never periodic. The received length is
  remembered (`M.store.durs[key][ek]`, `mod.MemberDuration`) for their next cast seen before a message; a timer from a
  message (`c.msg`) isn't replaced by their cast event within 5 s. List seconds: click "120s" in the list to edit.
- `Known.lua`: own tracked spells not learned (`mod.OwnUnlearned`: SpellName known and SpellCooldown nil) ->
  `MCDK:<id>,<id>` via `MMT.SendLong` when it changes (`mod.KnownCheck`: login, SPELLS_CHANGED, list change, sync,
  profile), heartbeat `cdk=<hash>`, mismatch -> whispered `MCDKQ` (60 s). Stored `M.store.unlearned[key]`; `State`
  hides them for others when `hideUnknown`. Spells only (user's choice); never sent -> everything shows.
- Share.lua also sends `MCDU:<ek>:r` when an own cooldown becomes ready > 1.5 s early (Cold Snap,
  Preparation); a newly tracked running cooldown is announced (lists changed: `mod.ShareCheck()`);
  `MCDQ` = "send me your running cooldowns" (after taking over lists), answered by whisper.
  After login / reload (0.14.8): PLAYER_LOGOUT saves others' running timers in `M.store.running` (rem, dur, `time()`),
  `mod.RestoreRunning()` in OnEnable puts them back (GetTime restarts on relog, so the real clock); and each member's
  first XP_RECEIVED of the session gets a whispered `MCDQ` (`asked[key]`). Same in Totems 0.4.6 (`M.store.running`,
  `MTTR` -> an `MTT` per own totem, whispered) and Buffs 0.17.9 weapons (`M.store.weaponsSaved`, `MBWQ` whispered).
- `showBuffs`: a tracked spell/item's buff = buff with the SAME NAME as the cast on the user
  (player / group unit via `unitOf`, else the time from MCDU); helpful auras first, then harmful ones
  (`mod.Debuff` in Compat: Death Wish is a debuff on the warrior). Icon: state "buff" + glow,
  `after` = the cooldown.
- Lists in `M.db.lists[key]`, key = class token | "ALL" | "RACE:<race token>" | "ROLE:<MMT role>" | "CHAR:<team key>"
  (`ListKeys.lua`, identical in both: `ListKeysFor`, `CollectEntries` with de-dup, `ListChoices`,
  `ValidListKey`, `RaceOf`, `AddPreset`; `ListsInUse` = lists that apply to the team now, shown green in `ListChoices`). Cooldowns entry `{t="s"|"i", id, cd, off}`, Buffs `{id, off}`;
  `off` = in the list but not tracked. Races: own `UnitRace`, others from the heartbeat `race=<token>`
  (registered by Cooldowns only), cached in `M.store.races`. `DEFAULT_LISTS` = the presets
  (Cooldowns: class extras + `RACE:*` racials all `off`). Sync / export carry `off` ("-" suffix).
- Only register events that exist on this client (e.g. NO `LEARNED_SPELL_IN_TAB`, NO
  `COMBAT_LOG_EVENT_UNFILTERED`); `RegisterEvent` errors on unknown ones. Check another installed
  addon (EllesmereUI) uses an event before relying on it.
- Always create FontStrings WITH a template (e.g. "GameFontHighlightSmall"): SetText before a
  font is set errors ("Font not set"). The test stub enforces this.
- Settings of Cooldowns / Buffs are tabbed (`SettingsKit.lua`, identical in all five: Cooldowns, Buffs, Totems, TeamInventory, QoL: `mod.Tabs`,
  `mod.LookTab`, `mod.ShareBar` = Import/Export bottom left under every tab, the core's Sync button bottom right (panels leave
  BOTTOM = 50 px), `mod.PresetBox`, `mod.AcceptSpellLinks(box, onLink)`): Bars / Look / lists.
  Status line just above the share bar. `mod.DragReorder(list, getData, moved)` = drag the rows of a core
  `ConfigHelpers.List` (rows need `row.index`; accent line marks the drop gap, cursor past an edge scrolls every 0.15 s,
  `mod.MoveEntry(data, from, slot)`; `mod.DragGrip(row)` = 2 x 3 dots at the row's left, lit while hovered, 0.17.4); both list editors use it instead of ^ / v buttons (Buffs 0.17.3, Cooldowns 0.14.3).
  `mod.MoveTab(frame, {locked, start, stop, always, tip})` = the move tab (like the XP window proposal): 40 x 12 tab above the
  top-left corner, shown while not locked and the mouse is over the frame (`IsMouseOver(14, 0, 0, 0)`, or `always()`: arranging),
  polled from the frame's OnUpdate (HookScript); drag runs the frame's own OnDragStart / OnDragStop. Used by the Cooldowns /
  Buffs windows (Window.lua) and Totems (container, and each bar while ungrouped; replaced the 8 px grey grips). SettingsKit
  is loaded BEFORE Window.lua / Bars.lua in those TOCs for it. Test: test_bardrag.py. Test: test_dragreorder.py (copy of the core's List on frames that keep scripts).
- Name search: `Search.lua` (identical in Cooldowns / Buffs): the game finds
  spells BY NAME only if the character knows them, so `mod.AttachSearch(box, {items, onPick})` builds a
  session index of all names over ID ranges 1-60000, 400000-440000, 1250000-1330000 (ticker, 3000 per
  step, presets' IDs win for duplicate names) and shows a popup; `box.picked` = the chosen {t, id, text};
  `mod.FindByName` for typed exact names; names shared by several IDs: the best `Score` wins (known by this character 4, has a base cooldown 2 - e.g. Fire Nova 408341 not the old effect 17366 -, real icon 1); a "Teaches X" trainer spell (generic icon `mod.GENERIC_ICON` 136235, e.g. 864 Seal of Righteousness) loses to a real spell of the same name, and its icon counts as none in `SpellIconAny`. Items: bags + equipped only. Test: test_search.py.
- Spell links: this client inserts shift-clicked links via `ChatFrameUtil.InsertLink`;
  `ChatEdit_InsertLink` is only a fallback. Hook through `mod.AcceptSpellLinks`.
- Spec lists (`Specs.lua`, identical in both; setting `specLists`, default off): list key "SPEC:<CLASS>:<SPEC>" (same
  keys as the spec presets) replaces the class key in `ListKeysFor` when `mod.SpecOf(key)` is known; `EnsureSpecLists`
  fills missing spec lists from the presets. Spec = tree with most points (`mod.TreePoints`, moved here from Roles.lua;
  `mod.OwnTree`; 0.14.9 / 0.17.10: Forever's trait groups first = `C_Traits.GetGroupDisplayInfoByTreeID` by orderIndex,
  points `GetGroupCurrencyInfo(config, {groupID})[1].currencyInfos[1].spent` like EllesmereUI's LibSpecialization, then
  the classic tabs, each only when the sum > 0 - **Forever HAS GetTalentTabInfo but it reads 0 for every tree** -, then
  the node-column bands; 0.14.10 / 0.17.11: `OwnTree` keeps only a KNOWN tree for 10 s (a read before the trait config
  is ready no longer sticks), re-read on PLAYER_ENTERING_WORLD / TRAIT_CONFIG_LIST_UPDATED; `/mmtct spec` / `/mmtbt spec`
  and the debug dump print `mod.SpecReport`: points per source), heartbeat `cts` (Cooldowns) / `bts` (Buffs, only while Cooldowns is off) + `MSPC:<tree>` once on
  change; druid Feral + `mod.PlayerRole` TANK (Buffs only) = BEAR. Preview ALL/MIXED: made-up tree from a hash.
  Set by hand: `M.db.specSet[key]` (Specs tab = `mod.SpecsTab(panel, status, changed)` in Specs.lua, both modules;
  holds the "Use spec lists" check), else the OTHER module's `MMT.db.modules[OTHER].specSet` (read only); must fit
  `mod.SpecsOf(class)`. With spec lists on, `ListChoices` leaves out the class lists (ALL stays); the editor opens on `mod.OwnListKey()`.
- Spec presets (2026-10-25, replaced the class ones): `SPECS[class] = { {key, name, on, off} }` in each Presets.lua,
  key "<CLASS>:<SPEC>" (DRUID: BALANCE / FERAL / BEAR / RESTO). Data: Wowhead Forever "<spec> abilities" guide pages
  (spell links = max-rank IDs) + nether.wowhead.com/forever/tooltip/spell/<id> for cooldowns; talent cooldowns the
  pages miss added by hand (verify in the tooltip: Last Stand is 3 min on Forever). Cooldown class default = all specs'
  entries, on when on in ANY spec (hideUnknown now defaults ON); buff class default = on only when on in EVERY spec.
- Presets: `Presets.lua` in each (`mod.PRESETS` {key, group = class | "RACE" | "ALL", race, name,
  entries}; `mod.DEFAULT_LISTS` built from them). Data from Wowhead Forever (nether.wowhead.com
  tooltips; 40xxxx IDs that aren't talents are Season of Discovery runes, leave them out).
  `ListKeys.lua`: `PresetChoices`, `PresetByKey`, `DefaultPreset`, `ApplyPreset(listKey, key, replace, id)`.
- Settings pages are ~564 px high (tab panels 484): `tests/test_layout.py` adds up every column's real widget heights
  (notes estimated) and fails on a column past its page / panel or a widget on the line of a 0-height `Add` (give the
  row its height when something else is placed beside it by SetPoint); it prints columns within 20 px of the limit.
- `IconBars.lua` = shared window lib `MMTIconBars` (embedded-lib pattern, newest VERSION wins).
  **Both copies must stay identical** (`IconBars`, `Compat`, `Transfer`, `ListKeys`: `cmp` each pair);
  bump VERSION on change (now 13: v13 icon `drag = {group, id, move}` = drag along its row (+ dotted `b.grip`), `lib.SetArrange` / `lib.Arranging`, see below; v11 cfg `iconZoom` = % cut off each icon edge, default 8, also used by Totems slots; v7 backdrop/border/row colours, font, timerColor; v5 icon/cfg `activeAlpha`; row `label`/`color`, icon `tint`/`desaturate`/`glow`/`after`, cfg `fullNames` + `lib.MemberName`). Buffs attaches to Cooldowns via `MMTIconBars.SetExtra("MMTCooldowns", ...)`.
- Bar drag (IconBars v13, Cooldowns 0.14.4 / Buffs 0.17.5; own mode since 0.14.5 / 0.17.6 - tying it to "unlocked"
  showed everything on every profile: unlocked is the default): arrange mode = session-only `MMTIconBars.arrange[windowName]`
  (`lib.SetArrange(name, on)` refreshes that window, `lib.Arranging(name)`; shared ListKeys `mod.Arranging(name, ...)` = any
  of them), toggled by `mod.ToggleArrange()` (each Window.lua; `/mmtct arrange`, `/mmtbt arrange`, "Arrange icons" button
  under Test / Reset position on the Bars tab, label via `ArrangeText` in OnRefresh). Lock / clickThrough don't matter:
  icons with `drag` take the mouse and show `b.grip` (2 x 3 dots on a dark patch, top left). Then Window.lua shows every switched-on entry, skipping hideReady / hideUnknown / hideUnseenItems
  (State nil -> "ready") and Buffs' Applies / Castable / Unlearned / BlessingCovered (All row too); Buffs member rows arrange with
  "MMTBuffs" or, attached, "MMTCooldowns" too (`ArrangingRows`); the All row with "MMTBuffs". `CollectEntries` returns `out, from` (list key per entry);
  icon `drag = mod.DragFor(lk, e)` = { group = the list TABLE (so Buffs icons on the Cooldowns bars never mix with
  Cooldowns'), id = entry, move = MoveIcon } -> `mod.MoveEntry` + `mod.ListsChanged()` (each Window.lua; also
  `MMT.RefreshConfig`). Lib: icon OnDragStart (has drag) -> `drag`, a parentless driver frame's OnUpdate draws
  the row's drop line (`row.drop`, yellow, frame level +20) via `Target` (cursor vs icon centres, clamped to the group's
  first/last icon) and ends on mouse up (`IsMouseButtonDown`) or OnDragStop; no drag data / locked -> forwards to the
  window's drag. `row.key` / `row.vertical` set in Refresh.
  Test: test_bardrag.py (positions from SetPoint("TOPLEFT", x, y)).
- All bar counter: IconBars v12 icon `tally` / `tallyPos` / `tallySize` / `tallyColor` = a second number in its own
  corner; Buffs AllRow sets it to "have/checked" (e.g. "3/5", only while someone misses it; no separate missing count since 0.16.6) from `allCount` (corner | "OFF"), `allCountSize`,
  `allCountColor` (Look tab right column: `mod.LookTab` returns L, R). Test: test_buffbar.py (whole Buffs with
  test_settings' stubs).
- Preview (`mod.preview` = nil | "REAL" | "MIXED" | "ALL" (shared ListKeys `mod.PreviewMembers()` = nine made-up
  "<Name>-Preview" keys, one per class; Members() returns them; rows get `color` = `mod.PreviewColor`), session only, `mod.SetPreview`, Bars tab Cycle, `/mmtct|mmtbf preview [mixed]`;
  MIXED: shared ListKeys `mod.ClassOf` returns `mod.PreviewClass(key)` = warrior, paladin, priest, ... by team order,
  you first; Buffs `ClassesHere` = the classes the preview shows (whole team counts as present)): `Members()`
  takes every team member (+ self), `mod.State` returns made-up states from a hash of key + entry (stable between
  redraws; Buffs: 1 in 4 missing, else 10/20/30 min buffs; Cooldowns: 1 in 3 ready, else somewhere in its cd).
- Buff presets: `PartyBuffs()` in Presets.lua (no auras, NO "Only for" - the user sets those) = DEFAULT_LISTS.ALL and
  "ALL:RAID"; "ALL:RAIDAURAS" = the old mix incl. Trueshot / LotP / Moonkin. Shared `AddPreset` deep-copies table
  fields (the filter) so lists never share a preset's tables.
- Buffs `Known.lua` (setting `hideUnlearned`, default on): own tracked CLASS buffs not learned (class = ids in the
  class's presets + `mod.CASTERS[class]`, matched by canonical name; learned = Compat `mod.KnowsSpell(id, name)` (IsPlayerSpell / IsSpellKnown / C_SpellBook.IsSpellKnown by ID, or a cooldown for the name; talent spells!) or in the spellbook, like
  Cooldowns) -> `MBFK:<ids>` via SendLong on change, heartbeat `bfk=<hash>`, `MBFKQ` whispered on mismatch (60 s),
  `M.store.unlearned[key]`. `mod.Unlearned(key, e)`: own row skips it (Window Icons); `Castable` needs a caster of
  the class here who learned it (`ClassesHere` returns present, who[class] = keys + `stranger` for non-team units =
  counts as able). Name patterns: learned when a learned spellbook spell matches (`C_SpellBook.GetSpellBookItemType` == Spell, so not FutureSpell; ID = 3rd value OR the action ID, like EllesmereUI), for patterns in own lists + `caster == class`; sent after "#" (`MBFK:<ids>#<pattern>...`), `rec.patterns`. Weapon entries: `#@imbue` when `mod.OwnCanImbue()` is false (shaman without a "... Weapon" imbue spell, rogue without Poisons; other classes always can). `mod.KnownCheck()` on list change / profile / sync / SPELLS_CHANGED; `mod.KnownReset()` clears caches.
- Blessings (`Casters.lua`, `blessingLimit`, default on): `mod.BlessingCovered(key, e)` = a missing blessing (`IsBlessing`:
  canonical name of Might / Wisdom / Kings / Light / Sanctuary; NOT Salvation: on Forever its own buff, stacks) while the member has >= `mod.PaladinsHere()`
  (paladin units in the group; preview: its team) blessings CAST BY A GROUP UNIT (`a.group` from Compat `mod.Buff`'s 6th
  value = aura sourceUnit; randoms outside the group give nil). Member row: not shown; All bar: `covered`, not counted.
- Buffs `Casters.lua`: `CASTERS` = class -> spell IDs of its buffs (matched by canonical name); with `hideNoCaster`
  (default on) `mod.Castable(e)` hides a buff whose class isn't in the group (units) or online in the team
  (`mod.ClassesHere`, cached 0.5 s); buffs not in the table always show.
- Buffs "Only for" (`Roles.lua`): `e.only = { roles = {MELEE=true}, classes = {...}, specs = {["PALADIN:RET"]=true}, mmt = {...} }` (specs via `mod.SpecOf`; spec unknown -> any ticked spec of the member's class counts; popup section from `mod.AllSpecs()`), nothing = everyone,
  else ANY match (`mod.Applies(e, key)`, used in Window `Icons` and the All classes row: members it isn't for aren't
  counted). Player role (`mod.PlayerRole` -> role, source): `M.db.playerRoles[key]` (Roles tab) > druid form from
  `mod.auras` (Cat M, Bear/Dire Bear T, Moonkin C, Tree H; only while in it) > a `BPR:<letter>` message < 40 s old >
  heartbeat `bpr=<T|H|M|R|C>` > class default. Own talents: `GetTalentTabInfo` tabs or Forever's trait tree split
  into three column bands (most points wins), `BPR` sent once on PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED / ...
  (own frame, pcall RegisterEvent). Cog per row of the ALL list ("All bar", `mod.ALL_LABEL`; other lists only while a filter is set) -> `mod.OpenFilter` popup (Settings.lua); export keeps
  `only` via `mod.CleanFilter`. Test: test_buffroles.py.
- Buffs: group buffs count as the single one (`GROUP` in Lists.lua: Prayer of Fortitude ->
  Fortitude, Gift of the Wild, Arcane Brilliance, Prayers, Greater Blessings); `mod.Canonical(name)`
  on every scanned buff and in `BuffName`; `EntryName` keeps the entry's own name.
- Name pattern entries `{ name = "Seal of *" }` (no id; Lists.lua `IsPattern`, `Matches` = `*` -> any text, case
  ignored, anchored; `ParsePattern` for the add box / import). `State` returns the matching aura with the most time
  left + its name and icon (ScanUnit keeps `icon`, `raw`); the window uses that icon, `tip` instead of `spell`.
  Everything keyed by entry uses `e.id or e.name` (presets, PresetBox, preview hash). Presets `P(name)`: paladin
  specs "Seal of *" on, hunters "Aspect of the *". Casters: patterns always count as castable, unless they carry
  `caster = "<CLASS>"` (preset `T(name, iconSpell)` = totem buffs, "ALL:TOTEMS"; `e.icon` = spell whose icon a never-seen pattern shows (BuildIndex fills it into older list entries from the presets): buff "Strength of Earth" / totem "... Totem").
- Weapon enchants (`Weapons.lua`): entries `{ weapon = "MH" | "OH" }` = any enchant on that weapon. Own via
  `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot.X)` (Forever: imbue type beside temporary; imbue wins) else old
  `GetWeaponEnchantInfo`; events WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED (pcall) + a 5 s re-read. Others:
  ONE `MBW:<MH>;<OH>` per change (part "0" none | "x" no weapon | "rem/dur/icon/name", name from the weapon's
  tooltip line "X (30 min)"), `MBWQ` at enable -> whispered answer (user agreed, like MCDU). `mod.weapons[key]`;
  never heard -> nil (nothing shown). `mod.EntryKey(e)` = id | name | "weapon:MH" everywhere entries are keyed.
- Buffs missing look `allMissingLook` (PLAIN/RED/GREY) + `glowMissing` apply to ALL buff icons
  (`Look()` in Window.lua). "All classes" row (`allBar`, `allExclude`): ALL-list buffs aggregated
  over the team, removed from member rows; stays in the Buffs window even when attached. A member row with no icons is left out (own window).
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

### MMT_Totems (v0.4.9) – port of ema_totems
- Bars per shaman (`Bars.lua`, own frames, NOT IconBars: own slots + `MMTTotemsSequenceButton` are
  secure). ALL layout/attribute/binding changes only out of combat (`pending` + PLAYER_REGEN_ENABLED);
  in combat only textures/cooldowns/timers. Key: override binding + Bindings.xml CLICK entry
  under header MMT_TOTEMS (see "Key bindings").
  Never re-apply bindings on UPDATE_BINDINGS (setting an override fires it: loop).
- Totems: own `GetTotemInfo`; others `MTT:<slot>:<rem>/<dur>:<name>` / `MTT:<slot>:0` per change
  (PLAYER_TOTEM_UPDATE), + group `UNIT_SPELLCAST_SUCCEEDED`. Chosen totems `MTTS:<el>:<id>:<key>`,
  sequences `MTTQ:<key>=<text>`; everything at once via the core sync.
- Learned totems: own via IsPlayerSpell / IsSpellKnown (all missing -> show all); others send
  `MTTK:<ids>` at login / on learning, stored in `M.store.known[key]`; no list yet -> show all.
  Chooser + preset editor filter by it, own casting skips unlearned chosen totems.
- Looks like the IconBars rows: name LEFT of the icons in one shared name column (grouped;
  own width ungrouped), above them when vertical; same timer text (tenths under 10 s).
- Spell data is lazy (0.4.7): `mod.LoadTotemData()` (OnEnable) requests every totem, SPELL_DATA_LOAD_RESULT ->
  `mod.TotemDataArrived` rebuilds the name lookup (`byName` in Data.lua) and redraws. `SlotShown` judges another
  shaman by their MTTK list only (no `SpellInfo` here: a warrior's client lacked it, so `hideUnlearned` hid whole bars).
- Presets window `MMTTotemsPresets` is DIALOG + Toplevel (0.4.9): on FULLSCREEN_DIALOG, the layer of MMT's dropdown
  list `MMTDropdownList`, the Toplevel window came in front of its own dropdowns, and raising the list after
  `UI.OpenList` (0.4.8) didn't win in game. Any window of ours with MMT dropdowns: stay below FULLSCREEN_DIALOG.
- Practice shaman (0.4.7, session only): `mod.PRACTICE` = "Practice-Shaman", `mod.SetPractice(on)` (Bars tab button,
  `/mmtt practice`); `IsShaman` true while on, Shamans() adds it last; knows every totem (no known list) and every item;
  SetSelected / SetSequence never send for it (`mod.IsPractice`); its selected / sequences / presets / barPoints are
  wiped when it goes and on OnEnable.
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

### MMT_Whispers (v0.1.4) – like EMA Talk (credit EMA / EbonyFaye in descriptions; EMA is "All Rights Reserved": never copy its code)
- Files: `Module.lua` (defaults, `/mmtw`), `Forward.lua` (alts: CHAT_MSG_WHISPER / _INFORM / BN_WHISPER / BN_WHISPER_INFORM,
  `mod.Receivers()` from `to` = LEADER (group, default) | FTL (`MMT.FTLLeader()`, sent with `MMT.SendToLeader`) | CHAR:<key> | ROLE:<role>;
  profiles that got FTL as default in 0.1.1/0.1.2 go back to LEADER once (`toLeader` flag), pass-on of the receiver's whispers,
  `mod.recentSenders`), `Display.lua` (receiver: MWF assembly, `mod.Show`, `mod.SetReply`), `Settings.lua`.
- Pass-on "@Name text": "@First Last: text"; without a colon the first TWO words are the name when they match a recent
  sender or a team member (characters have two names - "@Alash Erelia hey" whispered only "Alash" before 0.1.4), else
  the first word; team members are whispered via `MMT.WhisperTarget(key)`.
- Comm: `MWF:<id>:<part>:<total>:<kind>:<flags>:<name>:<text>` (kinds W I B b N, flag G = GM) by WHISPER to
  online receivers only. Secret texts/names stay on the alt. Skipped whispers (`<...>`, ignore words) aren't
  remembered as reply targets. `sync = true`, `syncExclude = { "chatFrame" }`.
- Reply target: `ChatFrameUtil.SetLastTellTarget` (fallback `ChatEdit_SetLastTellTarget`), pcall; sending:
  `C_ChatInfo.SendChatMessage` (fallback `SendChatMessage`), BN via `BNSendWhisper`.
- Test: `tests/test_whispers.py` (two clients, Anna = leader/receiver, Bob = alt).

### MMT_TeamGear (v0.2.1)
- Files: `Module.lua` (data: reads Item Compare's `MMTDB.moduleData.ItemCompare.equipment[key]` READ ONLY,
  members, class/level from `MMT.status`, `UnitOf` for the model, `/mmtgear`), `Window.lua` (inspect-like
  window `MMTTeamGearWindow`, slots LEFT/RIGHT/BOTTOM, `mod.ItemData`, redraw on GET_ITEM_INFO_RECEIVED and
  Item Compare's `EQUIPMENT_CHANGED`), `Button.lua` (button on `CharacterFrame`, shift-drag, `buttonPoint`
  offsets from its TOPLEFT; member list via `MMT.UI.OpenList`), `Settings.lua`, `Talents.lua` + `TalentsView.lua`.
  Gear: sends nothing (Item Compare's data). Talents: see below.
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
- Talents (0.2.0): `Talents.lua` reads OWN talents: classic `GetTalentTabInfo`/`GetTalentInfo` when they have points
  (0.2.1: Forever has them, every rank 0), else Forever's ONE trait tree (`C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo` treeIDs[1],
  `GetTreeNodes`, `GetNodeInfo` posX/posY/activeRank/maxRanks/groupIDs/isVisible, `activeEntry` or entryIDs[1] ->
  `GetEntryInfo` -> `GetDefinitionInfo` spellID/overrideIcon). The 3 trees = `C_Traits.GetGroupDisplayInfoByTreeID`
  sorted by orderIndex (names = displayName; how EllesmereUI's Forever ClassicTalents does it), else the 3 bands of node
  columns (names from `mod.TREE_NAMES`). Grid row/col per tree from positions (`Axis`: step = smallest gap above a
  quarter of the median; a position with an extra zero is read at a tenth). Comm: heartbeat `tgt=<hash>`, on change
  only (first read after login only sets the heartbeat) `TGT:<hash>#<n1>~<n2>~<n3>#<tree>.<row>.<col>.<rank>.<max>.<spell>.<icon>[.<name>];...`
  via SendLong; hash mismatch -> whispered `TGTQ` (60 s), answered by whisper. `M.store.talents[key] = {hash, text, time}`
  (parsed on demand, weak cache). Own = read live. `mod.TalentSummary` ("Retribution 5 / 11 / 35") in the window's sub
  line. `TalentsView.lua`: "Talents" button toggles `mod.showTalents` (kept while stepping), `mod.talentPanel` = 3 trees
  side by side (fixed window size `mod.WINDOW_W/H`), icons lit/desaturated, "rank/max", spell tooltip.
- Test: `tests/test_teamgear.py` (stand-in frames: read optional fields with `rawget`, or keep state on `mod`;
  the stub keeps every `M:Listen`/`M:On` handler; stand-in trait tree + classic API, comm round trip).

### MMT_TeamInventory (v0.10.1)
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
  search, styled like MMT's settings (fill 0.05/0.94, border 0.22/0.24, popups 0.07 + accent border 0.5, headers with a 0.08 white line, team rows like its nav list: accent bar + 0.06 bg for the one shown), window pinned by TOPLEFT (`mod.PinTop`, saved as such: height changes only move the bottom), `mod.CATEGORIES` = Baganator's default Classic order by GetItemInfoInstant classID, quality 0 = Junk
  last; lines = headers + rows of 10; the window grows to fit, scrolls by line only past the screen height) and the own minimap button
  `MMTTeamBagsMinimapButton` (`minimapAngle`, left bags / right bank, drag). Keys: `Bindings.xml` (header
  MMT_TEAMINVENTORY, binding names still MMTTEAMINV_* so bound keys survive) -> global `MMTTeamInventory_Toggle(place, who)`.
- `BaganatorCats.lua`: with Baganator on, `mod.BaganatorGroups(slots)` reads `BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE]`
  (category_display_order, custom_categories, category_modifications priority / addedItems "i:<id>",
  category_hidden) READ ONLY on every draw; default_* searches rebuilt like Baganator's Forever defaults
  (its definitions are private); matching = `Syndicator.Search.CheckItem(GetBaseInfo{...}, search)`, highest
  priority wins (prio = offset + (mod.priority+1)*200, ties by order). Auto categories skipped. Any problem: nil
  -> built-in `mod.Group`. Setting `baganatorCats`.
- `Give.lua`: planned gifts. Bags tab, any view: drag a slot (ALL view: slots have no `owner`; a drop takes
  `mod.Holders(id, to)`, the only one or a `UI.OpenList` "who gives it"; "__" view keys are never stored, old ones
  cleaned in `mod.Gives()`) (`OnDragStart/Stop`; drop zones =
  the side panel `f.team` beside the window (`mod.RefreshTeam`: `f.teamButtons` = every team member, click = their
  bags, "+n" incoming; then `f.pairRows` = one block per `mod.GiftPairs` pair with Trade, "x" (`mod.CancelGifts`) and
  small item icons (right-click cancels one); `mod.PlaceTeam` flips it left at the screen edge, also while the window
  is dragged (OnUpdate while `isMoving`); setting `sidePanel` hides it), then `f.bands` per character section; Shift = amount box `MMTTeamBagsAmount`); `M.store.gives[from][to][id] = {n, t}`
  (t = GetServerTime, newest wins, n = 0 kept a week as tombstone). `TIVG:<id>:<n>:<t>:<from>:<to>` to the team,
  whispered to a member the first time they're seen online (XP_RECEIVED). `mod.BagSlots` (one char, "b"):
  giver's count minus `PlannedOut` plus dimmed `outgoing` slots (receiver's name), receiver gets glowing `planned`
  slots (giver's name, `b.tag`); both first in BYCHAR, right-click cancels. The panel's "Trade" button: `TIVT:<from>:<to>` -> the giver's client
  `InitiateTrade(unit)` (works from an addon message, user-tested with party1), unit from `mod.UnitOf`
  (partyN / raidN, then friendly nameplates, matched by `MMT.SplitUnit` key: same first names!); not found -> `TIVN` whispered back.
  Trade: TRADE_SHOW -> `mod.FillTrade` after 0.2 s (0.10.1; was 2.2 s after the CORE's own Trade.lua fill): `FreeSlot(claimed)`
  takes trade slots from 6 DOWN (the core takes its precomputed free slots from 1 up, so they only clash past 6 stacks together),
  `claimed` = slots this fill used (the game reports them a moment later). A trade slot holds a BAG SLOT: a split dropped on it puts
  the whole stack in, so `PutAll` first splits EVERY split into its own empty bag slot at once (Split + Pickup(empty); needs free
  bag slots), whole stacks go in 0.05 s apart (`STEP_GAP`), each split stack goes in as soon as it exists (polled 0.05 s, 3 s max), skips bound/locked,
  counts what's already in the trade. Completion: our trade slots read every 0.25 s while open, applied on
  UI_INFO_MESSAGE == ERR_TRADE_COMPLETE (TRADE_ACCEPT_UPDATE etc. not confirmed on this client). Setting `giveTrade`;
  **AcceptTrade is PROTECTED for addons** (in game from OnUpdate / C_Timer: "The game blocked MMT_TeamInventory
  from calling UNKNOWN()"; an earlier /run test misled us). No auto-accept: `mod.AcceptPlanned()` from the key
  binding MMTTEAMINV_ACCEPT (`MMTTeamInventory_AcceptPlanned`, Bindings.xml) or the "Accept planned gifts" button
  under TradeFrame (both sides) accepts only when `mod.TradeIsPlanned()`: only planned items each side (<= plan),
  giver has nothing left to add (`Steps` empty), no gold, slot 7 empty; else prints why. The watcher prints a hint
  once the trade is just the planned gifts (steady 1.5 s). "Planned items" button (giver) fills by hand.
- Gold: `rec.gold` / `goldTime` (copper) on each character's record, NOT synced by us: own from `GetMoney` (ScanGold:
  OnEnable, PLAYER_MONEY, PLAYER_ENTERING_WORLD), others from the core heartbeat (`status.money` in XP_RECEIVED); a
  TIVS snapshot keeps it. `mod.Gold`, `mod.TotalGold` (shown characters), `mod.FormatGold` (coin icons, every coin that isn't 0, also on the rows: rounded rows looked like a wrong total;
  Look settings `goldSilver` / `goldCopper` hide those coins, display only). Others' gold: core heartbeat ~5 s after PLAYER_MONEY
  (`SetGold` in Sync.lua redraws the open window on a change - before 0.9.3 it didn't, so trades looked lost) + `TIVM:<copper>`
  whispered with every TIVREQ reply. `mod.RefreshAll()` (5 s throttle) = own scan + RequestAll: `mod.RefreshButton(parent)` icon
  in the window's top bar (left of the cog; the search box stretches from the character button to -72: fixed 140 px overlapped it at the narrowest window, MIN_W) and the panel's Team header.
- `otherChars` = false | "RULESET" | "ALL" (old `true` = RULESET; `mod.CharsMode()` -> TEAM/RULESET/ALL, settings Cycle "Characters"):
  `mod.Shown(key)` = `mod.InTeam(key)` (SortedMembers or self), or ALL, or RULESET and `mod.SameRuleset(key)`; filters BagOwners
  (rest sorted: this ruleset / unknown first, then by ruleset), the added-up views, the panel and the total. The item tooltip still counts everyone.
  Rulesets (0.9.0): team keys "First-Last" carry no realm; `mod.Ruleset()` = C_GameRules.IsGameRuleActive(Enum.GameRule.Hardcore/PvP/RPRuleset)
  -> HC | RPPvP | PvP | RP | PvE (like Syndicator / EllesmereUI; elsewhere the normalized realm). `rec.rs`: own on enable, others = heartbeat
  `tir=<rs>`, else ours when their XP/TIVS/TIVD reaches us (same ruleset); older records: Syndicator's SYNDICATOR_DATA.Characters
  "First Last-<rs>" (own account only, one match). Unknown = counts as this ruleset. No gifts across rulesets (Drop / Holders);
  other rulesets tagged " (PvE)" in the picker and panel. Only characters this account heard from are stored: another account's
  SavedVariables can't be read in game (on the user's PC each account only has its own teams' characters).
  Teams (0.10.0): `rec.team` = `mod.TeamSig()` (keys of own + SortedMembers, sorted, joined ","), stamped on every stored
  member by `mod.StampTeam()` (OnEnable, TEAM_CHANGED, each `mod.TeamGroups`). `mod.TeamGroups(withEmpty)` = { {current, keys},
  {sig, keys}, ... } (this team in team order - withEmpty adds members nothing is stored of, for the panel -, then by sig: this
  ruleset first, unknown team last); `mod.BagOwners()` flattens it; `mod.GroupLabel(g)` "This team" / "Team: <first names of
  the sig>" / "Team not known". Titles only when CharsMode ~= TEAM: picker (`mod.PickerItems()`, headers) and panel
  (`f.teamTitles` label + the group's gold). The picker ends with "Show" + `__MODE_<TEAM|RULESET|ALL>__` entries = the
  Characters setting. ALL / BYCHAR are named "All characters ..." when more than the team is shown.
- Settings: tabs General / Team bags / Look (`SettingsKit.lua` `mod.Tabs`; own ResetButton, no ShareBar). Look keys
  `bagIconSize`, `bagColumns`, `bagSpacing` (read by `ReadLook()` into the SIZE / COLS / GAP upvalues each redraw;
  window never narrower than `MIN_W`), `bagBgTexture` (LSM) / `bagBgColor` / `bagBgAlpha` / `bagBorderColor`
  (`mod.SkinFrame`, window + side panel), `bagQuality`, `bagFont`, `bagCountSize`.
- Filters `bagFilters` = { boe / bound / reagent / quest / consumable = "HIDE" | "ONLY" } ("ONLY" shown as Include;
  `mod.Filters()`, old single `bagFilter` converted once; window: `f.filter` toggles the sticky panel `f.filters` /
  `f.filterRows`, click cycles Show/Hide/Include, right-click Show, `f.filters.only` = "Showing only: ..." line;
  settings: one Cycle per kind; not synced). HIDE removes; with any Include an item must be one of them.
  `mod.ItemKinds(id, class, count, who, place)` = every kind of an item (quest: class 12 or bind 4; consumable: class 0).
  bound = bind 1/4, equipped bind 2, or owner(s)' `s` covers the count; boe = bind 2 weapon/armour not bound;
  applied in `mod.BagSlots` to ordinary slots only (planned gifts always shown); NOREAGENT / REAGENT via
  `mod.IsReagent` (item info value 17 "crafting reagent", else class 7 Trade Goods).
- **`MMT.Safe` returns only 7 values**: the bind type (14th) / crafting reagent (17th) need `mod.ItemInfo(id)`
  (own pcall, all values). The test stubs' `MMT.Safe` now match the core (7 values) so this shows up in tests.
- Tradeable: `mod.NeverTradeable(id)` = bind type 1 / 4 (14th GetItemInfo value); `mod.Tradeable(key, id)` = bags -
  soulbound - promised. Soulbound counts per bag item = synced place `s` (`mod.SYNC_PLACES`, NOT in `mod.PLACES`, not
  in totals or the hash; older clients ignore it). Drag / drop / Holders use Tradeable; `WhyNot` tooltip line.
- Tests: `tests/test_teaminventory.py` (two clients, incl. gifts + trade), `tests/test_teambags.py` (window, Baganator categories, drag, stand-ins).

### MMT_QoL (v0.6.3) – "Quality of life": home for small team conveniences
- One file per feature, registered with `mod.Feature{ key, slash, addon, title, checkText, tip, tags = { TAG = fn(key,
  sender, body) }, SendAll, OnEnable, OnDisable, Page(ui), Report(add) }` (Module.lua). `mod.Active(f)` = module on +
  `M.db[f.key]` + `mod.AddonState(f.addon)` (C_AddOns.IsAddOnLoaded; false + why: MISSING / DISABLED / not loaded).
  One TEAM_MESSAGE listener dispatches `^(Q[A-Z]+):` to the active feature's tag. Settings.lua: one TAB per feature
  (0.4.0: SettingsKit.lua copied in, `mod.Tabs`, ids = `f.key`, label `f.tabText or f.title`; column left, `f.notes` =
  "How it works" column right; main checkbox greyed with the reason as tooltip; `ui.Check/Cycle/Button/Confirm/Note`
  options greyed and ignored while the feature is off; `f.Refresh()` runs on page refresh). `Ask.lua`:
  `mod.Ask(from, f, lines, apply, ignored)` queues one `MMT.UI.Confirm` per sender + feature (a dialog replaced by
  another counts as Ignore; `ignored()` runs then); `f.askText(who, n)` / `f.askAccept` word the dialog.
  Slash: `commands[""]` = `/mmtqol <slash>`; a command returning nothing prints nothing.
- Tags: `QDJ`, `QDJL`, `QDJR` (Dejunk), `QBG`, `QBGL`, `QBGF` (Baganator), `QWAH`, `QWA`, `QWAR` (ForeverAuras), `QEUH`, `QEU`, `QEUR` (EllesmereUI), `QSB` (SmartBuff). One message per change; > 10 changes at once
  (import, Remove all, reset) are NOT sent (chat hint). Full pushes via `MMT.SendLong`, receivers merge (add only).
- `Dejunk.lua`: Dejunk 3.4 has NO list API (DejunkApi = IsJunk + AddListener; its Lists / store are in the private
  addon table). Read + write `__DEJUNK_ADDON_V3_SAVED_VARIABLES__` (rewritten as a shallow copy on every state change;
  `.global.inclusions/exclusions` and `.profiles.profileMap[characterMap[<GetUnitName-realm>] or "DEFAULT_PROFILE"]
  .settings.inclusions/exclusions` ARE the store's tables, keys = item ID strings). Lists GI/GE/PI/PE. Local changes:
  StateUpdated listener -> 0.3 s -> diff with `snap`; a move sends only the "+" (Dejunk takes it off the opposite list
  itself). Taken changes go into those tables, but Dejunk filters with its in-memory `Lists` copy (read only at
  login), so they count after a /reload; meanwhile Dejunk saves its copy over the state on its next change of that
  list: `pending[list][id]` = "+"/"-" puts them back and is not sent. Another profile = resnapshot, no send.
- Dejunk RIGHT AWAY (0.2.0, `djLive`, default on): Dejunk's keybinding handlers (`DejunkKeybinding_addTo<List>` /
  `removeFrom<List>`, List = GlobalInclusions ...) run `Lists[x]:Add/Remove(GameTooltip's item)` = its own code path.
  Dejunk creates those buttons only for bindings with a key, at its first StateUpdated after login, so `SetupChords()`
  runs at OUR file load (Dejunk's SV is loaded, its store isn't built yet) and gives unbound ones ALT-CTRL-SHIFT-F13..F20
  in `SV.global.keybindings` (keys the user set stay; Reconcile keeps them). Apply: queue, item data loaded first, waits
  while the player's own GameTooltip is up (max ~9 s), `GameTooltip:SetOwner(UIParent,"ANCHOR_NONE")` + SetItemByID +
  `button:Click()` + Hide. `expect["+GI<id>"]` (10 s) keeps Dejunk's resulting change (and its opposite-list removal)
  out of what we send. No button / option off -> the saved-state fallback below.
  The user's first in-game test read this as "not synced" (alt's Dejunk window empty, push said nothing new): chat lines
  say "in Dejunk after a /reload"; "Reload the team for Dejunk" (`QDJR`, `/mmtqol dejunk reload`) makes the characters
  with `dj.taken > 0` call `C_UI.Reload`/`ReloadUI` (after combat). Feature `commands = { word = fn }` for `/mmtqol <slash> <word>`.
- `Baganator.lua`: no API to add items to a category; `BAGANATOR_CONFIG.Profiles[BAGANATOR_CURRENT_PROFILE]
  .category_modifications[src].addedItems["i:<id>"|"p:<id>"]` is what Config.Get returns and is read on every redraw.
  Baganator replaces it (Config.Set copy) on each change: a 1 s ticker compares the reference (full diff every 5 s),
  snap keyed `item\tsrc` (renames are no change). Category on the wire: `default_*` key, custom = `c:<name>` (%XX
  escapes `%;=,:`). Apply = write the table in place (an item in one category only) + public
  `Baganator.API.RequestItemButtonsRefresh()` / `RequestLayoutUpdate()`. Scope `bgScope` ALL | JUNK (default_junk).
  Whole setup (`QBGF:BGR!1!...`): export built like Baganator's CategoriesExportTable, C_EncodingUtil CBOR + compress
  + base64; receiver always asked, then public `Baganator.API.ImportString` + `SlashCmdList.Baganator(
  "removeunusedcategories")` (the import re-adds custom categories under new keys), then resnapshot.
- Junk link (0.3.0, `junkLink`, Baganator column, default on), local changes only (taken ones update snap, so no
  link): Baganator Tick sees `i:<id>` into / out of `default_junk` -> `mod.DejunkFromHere(sign, id)` on GI (button op
  with `own = true`: no `expect`, so Dejunk's Check sends it like the player's; no button: state + QDJ sent directly).
  Dejunk Check sees a genuine removal from GI / PI (incl. a move to not junk) -> `mod.BaganatorUnjunk(id)` (in place,
  `changedHere` forces the next tick's full compare, which sends QBG "-"). Loops end because the other side is a no-op.
- `Bulk.lua` (0.5.0): `mod.Bulk{ tag, noun, plural, where, fromKey, settings, process(t, entries), ready(), open(item,
  done) -> opened, why, busy = {[why] = true} }` = big import strings to one member / the online team, used by
  ForeverAuras (tag QWA) and EllesmereUI (QEU). Wire: `<tag>H:<batch>:<count>:<bytes>:<names>` (< 250, SendAddon whisper
  / SendToTeam online) then the payload `<%XX name>=<string>;...` in parts of 6000 bytes, each
  `MMT.SendLong("<tag>:<batch>:<i>:<n>:<part>", whisper target | nil = online team)` - the core's MPT drops a text after
  400 parts x 220 bytes or 2 minutes, and team BULK outside instances is a whisper per member at ~800 B/s in all, so
  big single texts would time out. Receiver: refuses when `M.db[fromKey] == "LEADER"` and the sender isn't the FTL
  leader (`MMT.IsFTLLeader`); joins parts (any order, forgotten after 10 min idle) -> `process`; the feature asks
  (`mod.Ask`) then `b:Queue(t, items)` = replies A, one `open` at a time (`importing` set BEFORE open: done may come at
  once), retry 2 s while `busy[why]`, after combat (`b:InCombatEnded()` on PLAYER_REGEN_ENABLED), else skipped. Replies
  whispered `<tag>R:<batch>:A` | `:N:<why>` (ignored / not the leader / not one of ours) | `:D:<imported>:<total>`;
  every step prints a chat line on both sides. `b.stats`, `b:Waiting()`, `b:Count()` for the report. Strings are
  printable (LibDeflate EncodeForPrint, no ; or =).
- `ForeverAuras.lua` + `AurasWindow.lua` (0.4.0, key `auras`, options `waAsk` (default on), `waFrom` TEAM | LEADER,
  `waDock`): ForeverAuras (`ForeverAuras` = its `WeakAuras` table; global `WeakAuras` too) has a PUBLIC API in
  ForeverAuras/API.lua, `ForeverAurasAPI`: `:GetAuras()` {parent, children, icon} by id, `:ExportAura(id)` (= its export
  window's string, "!WA:2!" + EncodeForPrint; a group includes its children), `:DecodeAuraString(s)` ({m="d", d, c} or
  nil), `:ImportAura(s, cb)` (= `WeakAuras.Import` -> its own import / update window; false + "in combat" | "another
  import is still open" | ...; cb(accepted, id) once), `:GetConfigFrame()` (`ForeverAurasOptions`, nil until the options
  opened once). Its own transfer (chat link + "ForeverAuras" comm) only works from a chat link, one aura. Ask lines:
  name, "(group, n inside)", "- you have one by this name". Window `MMTQoLAurasWindow` (DIALOG, below MMT's dropdown
  lists): "All auras" + tree list with filter; groups start closed (+/- or double-click, `expanded[id]` session only; a
  filter shows every match flat; `mod.AurasRows`, `mod.AurasToggle`); sorted like ForeverAuras' list (0.4.2): "Loaded"
  (public `ForeverAuras.IsAuraLoaded(id) ~= nil`: loaded or standby; a group = any aura inside) then "Not loaded", each
  by name, closable section rows (ids "\001loaded" / "\001unloaded", open by default); `mod.AuraList` entries carry
  `section` (nil = no IsAuraLoaded = one plain list). Target via `UI.OpenList` (online team | each online member).
  Placed beside the options frame when it's shown (`win.docked`: then it closes with them, OnHide hooked on the options
  frame). "Send to team" button parented to the options frame (above its top right), made on
  `hooksecurefunc(ForeverAuras, "OpenOptions")`.
- `Ellesmere.lua` + `EllesmereWindow.lua` (0.5.0, key `eui`, options `euAsk`, `euFrom`, `euDock`): EllesmereUI (9.7) public
  profile functions in EllesmereUI/EllesmereUI_Profiles.lua: `GetProfileList()` -> profileOrder, profiles,
  `GetActiveProfileName()`, `ExportProfile(name)` (a bare call = COMPLETE profile: every module, layout, CDM spells for
  every spec, overrides, globals - what Wago packs use), `ExportFullAccountData()` (account-wide settings + the active
  profile only), `ImportProfileInteractive{ importString, profileName, source, callback }` (its own Profiles import page;
  false + "in combat" | "an interactive import is already pending"; callback(accepted)). That API page does NOT route
  full account strings: like its paste flow we `DecodeImportStringAsync`, check `IsFullAccountPayload`, show its own
  `EllesmereUI:ShowConfirmPopup{ typeToConfirm = "Confirm", onConfirm, onCancel }` and call `ImportFullAccountData`
  (ReloadUI first thing - must run inside the click; our done(true) = the D reply is queued before it). Entry names
  `P|<profile>` / `F|<active profile>`; a full account is always asked (whatever euAsk says). EllesmereUI sends no addon
  messages of its own. Window `MMTQoLEllesmereWindow`: profiles in its order (active marked, default selection) +
  "Full account" row, target, Send; "Send to team" above `EllesmereUIFrame` (built one frame after
  `EllesmereUI:Show()` on the first open: hooks on Show / Toggle look again now and 0.5 s later).
- `SmartBuffAlerts.lua` (0.6.0, key `smartbuff`, options `sbSend`, `sbExpire`, `sbRepeat` (s), `sbShow` LEADER | ALL | OFF,
  `sbRaid`, `sbSound`): SmartBuff Forever builds every missing / running-out alert in the GLOBAL
  `SMARTBUFF_SetMissingBuffMessage(target, buff, icon, canCharge, charges, timeLeft, expiring)` (SmartBuff/Buff.lua;
  splash, chat line and sound all come from it, every AutoTimer = 5 s while missing). `hooksecurefunc` on it
  (`mod.SmartBuffHook()`, OnEnable) -> one `MMT.SendAlert("QSB:<N|E|C>:<seconds|charges>:<target>:<buff>")` (fields
  %XX escaped incl. ":"; "item:ID" buffs -> `mod.ItemText`) per target + buff and `sbRepeat`, at once on a kind change.
  Receiver (`mod.SmartBuffShowsHere`): LEADER = this is the FTL leader (`MMT.FTLLeader`), without one the group leader
  (solo: yes); chat line + `RaidNotice_AddMessage(RaidWarningFrame)` + `PlaySound(SOUNDKIT.RAID_WARNING)` like the core's
  Warnings.lua (its display only knows its own NOTE:WARN kinds); the same target + buff + kind once per 10 s from anyone.
  SmartBuff's Check stops at the FIRST missing buff (its button's cast), so only one alert per check; it checks at
  PLAYER_REGEN_ENABLED itself. 0.6.1: `sbAfterCombat` (default on) = an alert last sent before the latest
  PLAYER_REGEN_DISABLED counts as new (0.6.2: also when anyone in the group starts fighting - `mod.SmartBuffCombatTick`,
  1 s ticker, UnitAffectingCombat on player + party/raid units, secret = fighting: followers often never get combat
  themselves; report: seen / sent / held / lastFight). SmartBuff itself reports nothing while mounted, eating /
  drinking, or with a group buff's target out of range. 0.6.3: the user's debug log (sniffer logs every PLAYER_* event)
  had PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT per fight but NO PLAYER_REGEN_DISABLED / _ENABLED, and the poll saw no
  combat either (`lastFight=-`): PLAYER_ENTER_COMBAT (auto attack) counts as a fight too; report `fights=regen/attack/poll`;
  `/mmtqol smartbuff combat` prints UnitAffectingCombat / InCombatLockdown live. Names shown with the privacy setting on the receiver
  (`mod.SmartBuffShownName`: team member by "First Last" / key / unambiguous first name, case ignored, via
  `MMT.RealFirst` / `MMT.RealName` -> `MMT.ShownName`; the sender too; pets / others unchanged).
- Test: `tests/test_qol.py` (two clients; stand-ins for Dejunk's state / its own list copy and Baganator's config).
  ForeverAuras: stand-in ForeverAurasAPI; one aura, a group in parts out of order, all to the team, ask / ignore,
  waiting for an open import window / combat, FTL-leader-only, the window's rows. EllesmereUI: stand-in with export /
  interactive import / full account functions; profile in parts, busy import page, full account always asked +
  confirmed in its popup, straight import without ask.

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
