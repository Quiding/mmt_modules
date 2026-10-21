# Quiding's MMT modules

Modules for [MMT - Manage My Team](https://github.com/bnetworking/MMT), a multiboxing addon for
World of Warcraft: Forever. Each module is its own addon folder and shows up in `/mmt` under
MODULES, with its own settings page.

| Module | What it does | Version |
| --- | --- | --- |
| [Cooldowns](#cooldowns) | Bars with every member's important cooldowns | 0.8.3 |
| [Buffs](#buffs) | Who has, and who misses, the buffs you track | 0.7.2 |
| [Totems](#totems) | Totem bars for the team's shamans *(not heavily tested yet)* | 0.4.3 |
| [Pawn Compare](#pawn-compare) | Pawn scores for the whole team in the item tooltips | 0.3.0 |
| [Team Gear](#team-gear) | Any member's equipped gear, like inspecting them | 0.1.0 |
| [Team Inventory](#team-inventory) | Item counts and bags across all accounts *(not heavily tested yet)* | 0.3.0 |
| [Whispers](#whispers) | Your alts' whispers on the character you play | 0.1.3 |

## Install

1. Copy the `MMT_*` folders next to the `MMT` folder in
   `World of Warcraft/_classic_beta_/Interface/AddOns/` on every client.
2. `/reload` (or log in) and switch the modules on under `/mmt` > MODULES if needed.
3. Recommended: [Baganator](https://www.curseforge.com/wow/addons/baganator) - Team Inventory then
   uses its categories and puts its tooltip lines right below Baganator's.

Every settings page has **Sync to team** (MMT's own: the other clients are asked first) and
**Reset to defaults** (click twice). Cooldowns, Buffs and Totems also have **Import / Export** as a
text string, a growth direction (top > down, down > top, left > right, right > left) and
background / border / font options.

---

## Cooldowns

Port of [EMA Cooldowns](https://github.com/Quiding/ema_cooldowns): one row per member with their
important spells, trinkets and potions.

- Every client sends **one short message** when its character uses a tracked cooldown (exact time
  left), so members outside the group are tracked too; group members are also seen directly.
- While a spell's buff is up (Berserking, Evasion, Death Wish, trinkets, ...) its icon glows with
  the buff's time left.
- Lists per class, race, MMT role or character; entries can be switched off without deleting them.
- **Presets** from Wowhead's WoW: Forever data: per class (recommended / major only / everything),
  racials per race, potions & runes.
- **Name search** in the add box: every spell (also ones your character doesn't know) and the items
  you carry; shift-click a spell or item works too.

`/mmtcd` · `/mmtcd test` · `/mmtcd export`

![Cooldowns bar](media/cooldowns.gif)

<img src="media/cooldowns_lists.png" alt="Cooldowns: tracked spells and presets" width="600">

## Buffs

Port of [EMA Buffs](https://github.com/Quiding/ema_buffs): which group members have or miss the buffs
tracked for them, with exact timers.

- Any rank counts, and group versions too (Prayer of Fortitude, Greater Blessings, ...).
- Own window, or attached to the Cooldowns bars.
- Missing buffs: normal icon, red or grey, optionally glowing, at their own opacity.
- "All classes" row: the team-wide buffs in one place (missing when anyone lacks one, otherwise the
  shortest time left); members can be left out of it.
- Presets (raid buffs, world buffs, flasks & elixirs, per class) and the same name search as Cooldowns.

`/mmtbf` · `/mmtbf test` · `/mmtbf export`

![Buffs bar](media/buffs.gif)

| | |
| --- | --- |
| <img src="media/buffs_lists.png" alt="Buffs: tracked buffs and the name search" width="420"> | <img src="media/buffs_look.png" alt="Buffs: look settings" width="420"> |

## Totems

*Probably not ready yet, not heavily tested.* Port of
[EMA Totems](https://github.com/Quiding/ema_totems): a bar per shaman (Fire, Air, Water, Earth).

- Active totem with its timer, else the chosen / last one.
- Right-click a slot to choose a totem (only the ones that shaman has learned), left-click your own
  to cast it.
- A cast sequence (reorder the four element buttons) on a key, spam-safe option.
- Individual and team presets (P / TP buttons), grouped or ungrouped bars.
- Slots hide when the shaman has no totem item or no totem of that element learned yet.

`/mmtt` · `/mmtt test` · `/mmtt presets` · `/mmtt export`

## Pawn Compare

Pawn scores for the whole team. Needs MMT's Item Compare switched on.

- In Item Compare's tooltips: each member's score for the hovered item with **their** Pawn scales,
  against what they have equipped (a two-hander against main + off hand).
- In the normal item tooltip: every member's gain from the item, replacing Pawn's own lines
  (or below them, or off).
- Members whose class can never use the item (a bow for a shaman) get no value.
- Scales are synced and stored, so offline members and clients without Pawn still work.

`/mmtpc` · `/mmtpc send` · `/mmtpc request`

<img src="media/pawncompare.png" alt="Team upgrades in the item tooltip" width="306">

## Team Gear

A button on the character panel: see any member's equipped items, like inspecting them - also
while they're offline. The items come from Item Compare's stored gear (needs Item Compare on).

- Item names, item levels and enchants, average item level, when the gear last changed.
- Their 3D model while they're in your group and in sight, else their race and gender wearing the
  stored gear.
- **Whole team**: one row per member with every slot.
- Option: your other profiles' teams and every other character Item Compare stored on this account.
- Hover for the tooltip, Shift-click to link, Ctrl-click to try on, `<` `>` to step through.

`/mmtgear <name>` · `/mmtgear all`

<img src="media/teamgear.png" alt="Team Gear: whole team and one member's gear" width="600">

## Team Inventory

*Probably not ready yet, not heavily tested.* How many of an item your team has, across all your
accounts and characters - bags, bank, mail and equipped, also for members who are offline.

- **Tooltip**: the team's counts under the item, per character with a total. Next to Baganator /
  Syndicator (which list the account you're on) it adds your other accounts' characters below theirs.
- **Team bags**: a bag window for any character, the whole team added up, or the whole team by
  character - with Bags / Bank / Mail / Equipped tabs and a search box.
- Grouped in **Baganator's categories** when it's on (your order, custom and hidden categories,
  priorities and dragged items, read live), else in built-in ones like Baganator's defaults.
- **Planned gifts**: in "whole team, by character" (Bags tab), drag an item onto another character
  (Shift: choose how many). It moves there and glows; the next time those two trade, the giver's
  client puts it into the trade window (never accepted automatically). Right-click a glowing item
  to cancel. A "Planned items" button under the trade window fills it by hand.
- Open it from the minimap button (left-click bags, right-click bank) or a key (Keybindings >
  AddOns > MMT - Team Inventory).
- The bank and mailbox are counted while open: open them once on each character.
- Each client counts its own items and shares them; only changes are sent after the first time.

`/mmtinv bags` · `/mmtinv bank` · `/mmtinv mail` · `/mmtinv send` · `/mmtinv request`

| | |
| --- | --- |
| <img src="media/teambags_team.png" alt="Team bags: the whole team in Baganator's categories" width="420"> | <img src="media/teambags_bycharacter.png" alt="Team bags: the whole team by character" width="420"> |
| <img src="media/teambags_equipped.png" alt="Team bags: one character's equipped items" width="420"> | <img src="media/teaminventory.png" alt="Team inventory lines in the item tooltip" width="277"> |

## Whispers

Inspired by the Talk module of [EMA](https://github.com/ebonyfaye/ema) by EbonyFaye (written new,
not copied): whispers your alts get show up on the character you play.

- Shown in a chat window of the receiver (the group leader by default; or MMT's FTL leader, a chosen
  character, or everyone with an MMT role), with clickable names, timestamps and a sound.
- What the alts whisper back is shown too.
- **Answer through the alt**: whisper it, and it passes the text on to whoever last whispered it
  (`@Name text` picks someone else). R can reply through the alt or straight to the sender.
- Optional Battle.net whispers (never real names). Automatic answers (`<DBM> ...`) and whispers with
  ignored words stay on the alt.

`/mmtw` · `/mmtw test`

---

## Development

This repository lives directly in `Interface/AddOns`; the `.gitignore` ignores every other addon
and only lists our own module folders. Tests run the modules in Lua 5.1 (the same as WoW) through
Python and [lupa](https://github.com/scoder/lupa): `python tests/run_all.py`.
