# Quiding's MMT modules

Modules for [MMT - Manage My Team](https://github.com/bnetworking/MMT), a multiboxing addon
for World of Warcraft: Forever.

This repository lives directly in `Interface/AddOns`. The `.gitignore` ignores every other
addon and only lists our own module folders.

## Modules
- **MMT_PawnCompare** (0.2.0): adds Pawn scores to the Item Compare tooltips. Each member's
  hovered-item score is calculated with *their* Pawn scales and compared against the item they
  have equipped. Needs MMT_ItemCompare switched on. Scales are synced between clients and stored,
  so offline members and clients without Pawn still work (stats are approximate without Pawn).
  The normal item tooltip can also list every team member's gain from the hovered item,
  replacing Pawn's own lines (setting: Replace / Add below / Off).
  `/mmtpc`, `/mmtpc send`, `/mmtpc request`.
- **MMT_BugFixes** (0.1.0): runtime fixes for other MMT modules, each switchable on its settings
  page, with a patch for the module's author in `MMT_BugFixes/patches/`:
  - Item Compare's team tooltips no longer cover the game's "Equipped" comparison tooltips
    (`patches/ItemCompare_overlap.patch`, apply with `git apply` in `Interface/AddOns`).
- **MMT_Cooldowns** (0.2.0): port of [EMA Cooldowns](https://github.com/Quiding/ema_cooldowns).
  One row per member with their important spells, trinkets and potions. Every client sends one
  short message when its character uses a tracked cooldown (exact remaining time), so members
  outside the group are tracked too; group members are also seen directly. Per-class
  lists, editable on the settings page, can be sent to the team. `/mmtcd`, `/mmtcd test`.
- **MMT_Buffs** (0.1.1): port of [EMA Buffs](https://github.com/Quiding/ema_buffs). Which group
  members have or miss the buffs tracked for their class, with exact timers. Own window or
  attached to the Cooldowns bars. `/mmtbf`, `/mmtbf test`.

## Install
Copy the `MMT_*` folders from this repo next to the `MMT` folder in
`World of Warcraft/_classic_beta_/Interface/AddOns/` on every client, then restart the game
completely (new addon folders don't show up after just /reload).
