# Quiding's MMT modules

Modules for [MMT - Manage My Team](https://github.com/bnetworking/MMT), a multiboxing addon
for World of Warcraft: Forever.

This repository lives directly in `Interface/AddOns`. The `.gitignore` ignores every other
addon and only lists our own module folders.

## Modules
- **MMT_PawnCompare** (0.2.2): adds Pawn scores to the Item Compare tooltips. Each member's
  hovered-item score is calculated with *their* Pawn scales and compared against the item they
  have equipped. Needs MMT_ItemCompare switched on. Scales are synced between clients and stored,
  so offline members and clients without Pawn still work (stats are approximate without Pawn).
  The normal item tooltip can also list every team member's gain from the hovered item,
  replacing Pawn's own lines (setting: Replace / Add below / Off).
  `/mmtpc`, `/mmtpc send`, `/mmtpc request`.
- **MMT_BugFixes** (0.1.1): runtime fixes for other MMT modules, each switchable on its settings
  page, with a patch for the module's author in `MMT_BugFixes/patches/`:
  - Item Compare's team tooltips no longer cover the game's "Equipped" comparison tooltips
    (`patches/ItemCompare_overlap.patch`). Merged upstream in Item Compare 1.0.2; the fix
    switches itself off there.
- Cooldowns and Buffs track lists per class, MMT role or character.
- **MMT_Cooldowns** (0.6.2): port of [EMA Cooldowns](https://github.com/Quiding/ema_cooldowns).
  One row per member with their important spells, trinkets and potions. Every client sends one
  short message when its character uses a tracked cooldown (exact remaining time), so members
  outside the group are tracked too; group members are also seen directly. While a spell's buff
  is up (Berserking, Evasion, trinkets, ...) its icon glows with the buff's time left. Per-class
  lists, editable on the settings page, can be sent to the team. Import / export as a text
  string (choose: lists, look, position). `/mmtcd`, `/mmtcd test`, `/mmtcd export`.
- **MMT_Buffs** (0.5.2): port of [EMA Buffs](https://github.com/Quiding/ema_buffs). Which group
  members have or miss the buffs tracked for their class (any rank, group versions like Prayer
  of Fortitude count too), with exact timers. Own window or
  attached to the Cooldowns bars. Missing buffs show as the normal icon, red or grey (optionally glowing), at their own opacity. An
  "All classes" row sums up the team-wide buffs: missing when anyone lacks one, otherwise the shortest time left; members can be left out of it.
  Import / export as a text string. `/mmtbf`, `/mmtbf test`, `/mmtbf export`.
- **MMT_Totems** (0.3.3): port of [EMA Totems](https://github.com/Quiding/ema_totems). A bar per
  shaman (Fire, Air, Water, Earth): active totem with timer, else the chosen / last one.
  Right-click a slot to choose a totem (only those that shaman has learned, for any shaman), left-click your own to cast it, a
  sequence button + key (`/castsequence`, spam-safe option), individual and team presets (P / TP),
  grouped or ungrouped bars. Slots hide when the shaman has no totem item for that element or no totem
  of it learned yet (switchable, plus "always hide" per element). Tabbed settings (Bars / Look / Casting & presets); background and
  border textures and colours (LibSharedMedia, colour strength), a background per bar, font, timer colour.
  Each client sends one short message per totem change.
  `/mmtt`, `/mmtt test`, `/mmtt presets`, `/mmtt export`.

## Install
Copy the `MMT_*` folders from this repo next to the `MMT` folder in
`World of Warcraft/_classic_beta_/Interface/AddOns/` on every client, then restart the game
completely (new addon folders don't show up after just /reload).
