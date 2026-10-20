# Quiding's MMT modules

Modules for [MMT - Manage My Team](https://github.com/bnetworking/MMT), a multiboxing addon
for World of Warcraft: Forever.

This repository lives directly in `Interface/AddOns`. The `.gitignore` ignores every other
addon and only lists our own module folders.

## Modules
- **MMT_PawnCompare** (0.3.0): adds Pawn scores to the Item Compare tooltips. Each member's
  hovered-item score is calculated with *their* Pawn scales and compared against the item they
  have equipped. Needs MMT_ItemCompare switched on. Scales are synced between clients and stored,
  so offline members and clients without Pawn still work (stats are approximate without Pawn).
  The normal item tooltip can also list every team member's gain from the hovered item,
  replacing Pawn's own lines (setting: Replace / Add below / Off).
  Members whose class can never use the item (a bow for a shaman, plate for a mage) get no value
  (switchable). `/mmtpc`, `/mmtpc send`, `/mmtpc request`.

  <img src="media/pawncompare.png" alt="Team upgrades in the item tooltip" width="306">

- Cooldowns and Buffs track lists per class, race, MMT role or character; list entries can be
  switched off without deleting them. Presets from Wowhead's WoW: Forever data (per class:
  recommended / major only / everything; racials per race; potions & runes; raid, world buff and
  flask buffs) can be added to a list or replace it. Type a name in the add box and pick from the
  search list (every spell, also ones your character doesn't know; for Cooldowns also the items you
  carry), or shift-click a spell / item.
- All three bar modules: growth direction (Top > Down, Down > Top, Left > Right, Right > Left),
  and a bar at the bottom of every settings tab: "Import / Export" on the left, MMT's own
  "Sync to team" on the right (`/mmt sync cooldowns|buffs|totems`; every setting incl. the window
  position, the other clients are asked first; the Totems key binding stays on each client).
- **MMT_Cooldowns** (0.8.3): port of [EMA Cooldowns](https://github.com/Quiding/ema_cooldowns).
  One row per member with their important spells, trinkets and potions. Every client sends one
  short message when its character uses a tracked cooldown (exact remaining time), so members
  outside the group are tracked too; group members are also seen directly. While a spell's buff
  is up (Berserking, Evasion, trinkets, ...) its icon glows with the buff's time left. Per-class
  lists, editable on the settings page, can be sent to the team. Import / export as a text
  string (choose: lists, look, position). `/mmtcd`, `/mmtcd test`, `/mmtcd export`.

  ![Cooldowns bar](media/cooldowns.gif)

  <img src="media/cooldowns_lists.png" alt="Cooldowns: tracked spells and presets" width="600">

- **MMT_Buffs** (0.7.2): port of [EMA Buffs](https://github.com/Quiding/ema_buffs). Which group
  members have or miss the buffs tracked for their class (any rank, group versions like Prayer
  of Fortitude count too), with exact timers. Own window or
  attached to the Cooldowns bars. Missing buffs show as the normal icon, red or grey (optionally glowing), at their own opacity. An
  "All classes" row sums up the team-wide buffs: missing when anyone lacks one, otherwise the shortest time left; members can be left out of it.
  Import / export as a text string. `/mmtbf`, `/mmtbf test`, `/mmtbf export`.

  ![Buffs bar](media/buffs.gif)

  <img src="media/buffs_lists.png" alt="Buffs: tracked buffs and the name search" width="600">
  <img src="media/buffs_look.png" alt="Buffs: look settings" width="600">

- **MMT_Totems** (0.4.3) *(probably not ready yet, not heavily tested)*: port of [EMA Totems](https://github.com/Quiding/ema_totems). A bar per
  shaman (Fire, Air, Water, Earth): active totem with timer, else the chosen / last one.
  Right-click a slot to choose a totem (only those that shaman has learned, for any shaman), left-click your own to cast it, a
  sequence (reorder the four element buttons) + key (`/castsequence`, spam-safe option), individual and team presets (P / TP),
  grouped or ungrouped bars. Slots hide when the shaman has no totem item for that element or no totem
  of it learned yet (switchable, plus "always hide" per element). Tabbed settings (Bars / Look / Casting & presets); background and
  border textures and colours (LibSharedMedia, colour strength), a background per bar, font, timer colour.
  Each client sends one short message per totem change.
  `/mmtt`, `/mmtt test`, `/mmtt presets`, `/mmtt export`.
- **MMT_Whispers** (0.1.3): inspired by the Talk module of [EMA](https://github.com/ebonyfaye/ema)
  by EbonyFaye (written new, not copied). Whispers your alts get from players outside the team
  show up in a chat window of the receiver (the group leader by default; or MMT's FTL leader,
  i.e. the character you play, a chosen character or everyone with an MMT role), with clickable names, timestamps and a sound; what the alts whisper back is shown
  too. Answer through the alt: whisper it and it passes the text on to whoever last whispered it
  (`@Name text` / `@First Last: text` picks someone else); R can reply through the alt or
  straight to the sender. Optional Battle.net whispers (never real names); automatic answers
  (`<DBM> ...`) and whispers with ignored words stay on the alt. Texts the game hides in combat
  lockdown aren't forwarded. Settings sync through MMT's "Sync to team". `/mmtw`, `/mmtw test`.
- **MMT_TeamGear** (0.1.0): a button on the character panel lists the team; click a member to
  see their equipped items in an inspect-like window (item names and levels, average item level,
  their 3D model while they're in your group and in sight). Works for offline members too: the
  items come from Item Compare's stored gear (needs MMT_ItemCompare on). Hover for the tooltip,
  Shift-click to link, Ctrl-click to try on; `<` `>` step through the list. Option "Also show other teams":
  the list becomes Team 1 (this team), Team 2, ... (your other profiles' teams) and Other characters
  (everyone else Item Compare stored on this account), each with its members below it.
  Out of sight the model is their race and gender wearing the stored gear (default face and hair;
  each client shares its race and gender on MMT's heartbeat). "Whole team" (top of the list, the
  Team button or `/mmtgear all`) shows everyone at once: one row per member with every slot.
  `/mmtgear <name>`.

  <img src="media/teamgear.png" alt="Team Gear: whole team and one member's gear" width="600">
- **MMT_TeamInventory** (0.1.0) *(probably not ready yet, not heavily tested)*: the item tooltip shows how many your team has, across all your
  accounts and characters (bags, bank, mail, equipped), also for members who are offline. Each
  client counts its own items and shares them (a hash on MMT's heartbeat, a full copy when it
  differs, then only the changes). Bank and mailbox are counted while open: open them once on
  each character. Next to Baganator / Syndicator (which list the account you're on) it adds your
  other accounts' characters below their lines, with a total over everyone. `/mmtinv send | request`.

  <img src="media/teaminventory.png" alt="Team inventory lines in the item tooltip" width="277">

Every module's settings page has **Reset to defaults** (click twice), next to Import / Export and
Sync to team.

## Install
Copy the `MMT_*` folders from this repo next to the `MMT` folder in
`World of Warcraft/_classic_beta_/Interface/AddOns/` on every client, then restart the game
completely (new addon folders don't show up after just /reload).
