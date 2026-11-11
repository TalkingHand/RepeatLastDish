# Repeat Last Dish

A Project Zomboid Build 42 mod. Cooking the same salad or stir fry ten times means ten trips through the same right-click menus. This mod remembers the ingredients you put into your last dish, in order, and makes it again.

## How it works

- Make a dish the usual way: right-click an empty bowl, pan or pot and add ingredients. The mod records the base item, the recipe and each ingredient in the order you added them.
- Next time, right-click an empty base of the same kind: **Repeat last dish: Salad**, at the top of the vanilla "Make Salad" submenu (at the end of the menu when nothing can go in right now). Select several bases to make several dishes in a row.
- The ingredients are taken from your inventory first, then from containers next to you (the fridge, counters, the floor): whatever the loot window shows. Fresh or stale doesn't matter (older ones go first); **rotten food is never used**. Frozen food is skipped unless the recipe allows it, as in vanilla.
- Each ingredient goes in with the normal "add ingredient" action and time; leftovers go back where they came from.
- The option is greyed out, with the missing ingredients in the tooltip, when something is not there. With several bases, it stops before a dish it can't finish. An ingredient that runs out halfway through a dish is skipped and reported.
- Cancel at any time like any other action.

## Compatibility

- Client-side Lua; uses only vanilla actions, so the server needs nothing beyond having the mod in its list.
- Single player tested. Multiplayer: each step waits until the server's change shows in your inventory. 0.1.1 fixed dishes made on a server not being recorded (the state was read after the server's change had already arrived); checked on a dedicated server.
- Safe to add to or remove from an existing save. The last dish is kept in the player's mod data (single player) or in `Zomboid/Lua/RepeatLastDish_<server>_<name>.txt` on your PC (multiplayer).

## Install

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3837665530), or copy `Contents/mods/RepeatLastDish` into `%USERPROFILE%\Zomboid\mods\`.

## Testing

`pzt live` in this folder (PZTestHarness). Scenarios: recording a hand-made salad, repeating two salads from a fridge with a rotten and a stale ingredient, missing ingredient, partial run, other base items, cancel, a spice (garlic) in the dish, the submenu position, and the multiplayer order (server change before perform).

## Support

If this mod helps you, you can support it via [Ko-fi](https://ko-fi.com/talkinghands2285) or [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/talkinghands2285)
