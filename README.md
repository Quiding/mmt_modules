# Quiding's MMT modules

Modules for [MMT - Manage My Team](https://github.com/bnetworking/MMT), a multiboxing addon
for World of Warcraft: Forever.

This repository lives directly in `Interface/AddOns`. The `.gitignore` ignores every other
addon and only lists our own module folders.

## Modules
- **MMT_PawnCompare** (0.1.2): adds Pawn scores to the Item Compare tooltips. Each member's
  hovered-item score is calculated with *their* Pawn scales and compared against the item they
  have equipped. Needs MMT_ItemCompare switched on. Scales are synced between clients and stored,
  so offline members and clients without Pawn still work (stats are approximate without Pawn).
  `/mmtpc`, `/mmtpc send`, `/mmtpc request`.

## Install
Copy the `MMT_*` folders from this repo next to the `MMT` folder in
`World of Warcraft/_classic_beta_/Interface/AddOns/` on every client, then restart the game
completely (new addon folders don't show up after just /reload).
